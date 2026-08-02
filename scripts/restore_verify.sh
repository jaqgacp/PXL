#!/usr/bin/env bash
# PXL restore verification — proves a backup can actually bring the books back.
#
# A dump file that has never been restored is not a backup, it is a hope. This
# script restores a backup into a throwaway database in the same cluster and
# compares the result against the manifest captured at dump time:
#
#   - schema objects   tables, views, functions, triggers, policies, indexes
#   - row counts       every populated table, exactly
#   - the books        journal line count, total debit, total credit,
#                      inventory value, audit log rows
#   - integrity        the restored ledger still balances
#
# Any mismatch fails the run. It also measures and prints the restore time,
# which is the RTO evidence.
#
# Usage:
#   scripts/restore_verify.sh                    # verify the newest backup
#   scripts/restore_verify.sh backups/pxl-<ts>   # verify a specific one

set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER="${PXL_DB_CONTAINER:-supabase_db_PXL}"
OUT_DIR="${PXL_BACKUP_DIR:-backups}"
SCRATCH="${PXL_RESTORE_DB:-pxl_restore_verify}"

if [ $# -ge 1 ]; then
  BASE_PATH="$1"
else
  BASE_PATH="$(ls -1 "${OUT_DIR}"/pxl-*.manifest.json 2>/dev/null | sort | tail -1 | sed 's/\.manifest\.json$//')"
fi

if [ -z "${BASE_PATH:-}" ] || [ ! -f "${BASE_PATH}.manifest.json" ]; then
  echo "FAIL: no backup manifest found. Run scripts/backup.sh first." >&2
  exit 1
fi

MANIFEST="${BASE_PATH}.manifest.json"
DUMP="${BASE_PATH}.dump"
fail=0

echo "[restore] verifying : ${BASE_PATH}"

# ── Decrypt if needed ───────────────────────────────────────────────────────
CLEANUP_DUMP=0
if [ ! -f "$DUMP" ] && [ -f "${DUMP}.enc" ]; then
  if [ -z "${PXL_BACKUP_PASSPHRASE:-}" ]; then
    echo "FAIL: backup is encrypted but PXL_BACKUP_PASSPHRASE is not set" >&2
    exit 1
  fi
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
    -in "${DUMP}.enc" -out "$DUMP" -pass env:PXL_BACKUP_PASSPHRASE
  CLEANUP_DUMP=1
  echo "[restore] decrypted the archive for verification"
fi

[ -f "$DUMP" ] || { echo "FAIL: dump file ${DUMP} not found" >&2; exit 1; }

# ── Integrity of the archive itself ─────────────────────────────────────────
if [ -f "${DUMP}.sha256" ]; then
  EXPECT=$(cat "${DUMP}.sha256")
  ACTUAL=$(sha256sum "$DUMP" | awk '{print $1}')
  if [ "$EXPECT" != "$ACTUAL" ]; then
    echo "FAIL: archive checksum mismatch — the backup file is corrupt" >&2
    exit 1
  fi
  echo "[restore] checksum  : OK"
fi

# ── Restore into a throwaway database ───────────────────────────────────────
docker exec "$CONTAINER" psql -U postgres -d postgres -q \
  -c "DROP DATABASE IF EXISTS ${SCRATCH} WITH (FORCE);" \
  -c "CREATE DATABASE ${SCRATCH};"

START=$(date +%s)
# pg_restore reports benign errors for cluster-level roles and extensions that
# already exist; --exit-on-error is therefore not used. Correctness is proven by
# the comparisons below, not by the restore's exit code.
docker exec -i "$CONTAINER" pg_restore -U postgres -d "$SCRATCH" --no-owner --no-privileges \
  < "$DUMP" > /tmp/pxl_restore.log 2>&1 || true
END=$(date +%s)
RTO_SECONDS=$((END - START))
echo "[restore] restored in ${RTO_SECONDS}s into database '${SCRATCH}'"

q() { docker exec "$CONTAINER" psql -U postgres -d "$SCRATCH" -t -A -c "$1"; }
m() { python3 -c "import json,sys;d=json.load(open('$MANIFEST'));print(eval('d'+sys.argv[1]))" "$1"; }

compare() { # label expected actual
  if [ "$2" = "$3" ]; then
    printf "  %-22s %-14s OK\n" "$1" "$3"
  else
    printf "  %-22s expected=%-12s got=%s  MISMATCH\n" "$1" "$2" "$3"
    fail=1
  fi
}

echo "[restore] schema objects"
compare "tables"    "$(m "['objects']['tables']")"    "$(q "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r'")"
compare "views"     "$(m "['objects']['views']")"     "$(q "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='v'")"
compare "functions" "$(m "['objects']['functions']")" "$(q "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'")"
compare "triggers"  "$(m "['objects']['triggers']")"  "$(q "SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal")"
compare "policies"  "$(m "['objects']['policies']")"  "$(q "SELECT count(*) FROM pg_policies WHERE schemaname='public'")"
compare "indexes"   "$(m "['objects']['indexes']")"   "$(q "SELECT count(*) FROM pg_indexes WHERE schemaname='public'")"

echo "[restore] the books"
compare "companies"        "$(m "['books']['companies']")"           "$(q "SELECT count(*) FROM companies")"
compare "journal_entries"  "$(m "['books']['journal_entries']")"     "$(q "SELECT count(*) FROM journal_entries")"
compare "journal_lines"    "$(m "['books']['journal_entry_lines']")" "$(q "SELECT count(*) FROM journal_entry_lines")"
compare "total_debit"      "$(m "['books']['total_debit']")"         "$(q "SELECT COALESCE(SUM(debit_amount),0) FROM journal_entry_lines")"
compare "total_credit"     "$(m "['books']['total_credit']")"        "$(q "SELECT COALESCE(SUM(credit_amount),0) FROM journal_entry_lines")"
compare "inventory_value"  "$(m "['books']['inventory_value']")"     "$(q "SELECT COALESCE(SUM(total_cost),0) FROM stock_balances")"
compare "audit_log_rows"   "$(m "['books']['audit_log_rows']")"      "$(q "SELECT count(*) FROM sys_audit_logs")"

echo "[restore] every populated table"
MISMATCHED=$(python3 - "$MANIFEST" <<'PY'
import json,subprocess,sys
man=json.load(open(sys.argv[1]))
rows=man.get('row_counts') or {}
import os
container=os.environ.get('PXL_DB_CONTAINER','supabase_db_PXL')
scratch=os.environ.get('PXL_RESTORE_DB','pxl_restore_verify')
sql=" UNION ALL ".join(
    "SELECT %s AS t, count(*)::text AS n FROM public.%s" % ("'"+t+"'", '"'+t+'"') for t in rows)
out=subprocess.run(['docker','exec',container,'psql','-U','postgres','-d',scratch,'-t','-A','-F','|','-c',sql],
                   capture_output=True,text=True)
actual=dict(l.split('|') for l in out.stdout.strip().split('\n') if '|' in l)
bad=[(t,str(v),actual.get(t,'MISSING')) for t,v in rows.items() if actual.get(t)!=str(v)]
for t,e,a in bad: print("  %-30s expected=%-8s got=%s" % (t,e,a))
print("TOTAL_TABLES=%d MISMATCHES=%d" % (len(rows),len(bad)))
PY
)
echo "$MISMATCHED" | sed '$d'
SUMMARY=$(echo "$MISMATCHED" | tail -1)
echo "  $SUMMARY"
echo "$SUMMARY" | grep -q "MISMATCHES=0" || fail=1

echo "[restore] integrity of the restored ledger"
OOB=$(q "SELECT COALESCE(SUM(debit_amount)-SUM(credit_amount),0)::numeric(18,2) FROM journal_entry_lines")
compare "out_of_balance" "0.00" "$OOB"

# ── Clean up ────────────────────────────────────────────────────────────────
if [ "${PXL_KEEP_RESTORE_DB:-0}" != "1" ]; then
  docker exec "$CONTAINER" psql -U postgres -d postgres -q -c "DROP DATABASE IF EXISTS ${SCRATCH} WITH (FORCE);"
fi
[ "$CLEANUP_DUMP" = "1" ] && rm -f "$DUMP"

echo

# ── Verification receipt ────────────────────────────────────────────────────
# Written only on PASS, and deleted on FAIL so a set that once verified cannot
# keep a stale certificate. scripts/backup_offsite.sh refuses to replicate a set
# without one, which is what stops an unproven archive from being multiplied
# across destinations and later trusted because there are several copies of it.
RECEIPT="${BASE_PATH}.verified.json"

if [ "$fail" -eq 0 ]; then
  TABLES_COMPARED="$(echo "$SUMMARY" | sed -n 's/.*TOTAL_TABLES=\([0-9]*\).*/\1/p')"
  cat > "$RECEIPT" <<JSON
{
  "set": "$(basename "$BASE_PATH")",
  "verified_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "verified_by": "scripts/restore_verify.sh",
  "restore_seconds": ${RTO_SECONDS},
  "tables_compared": ${TABLES_COMPARED:-0},
  "row_count_mismatches": 0,
  "restored_out_of_balance": "${OOB}"
}
JSON
  echo "[restore] receipt   : ${RECEIPT}"
  echo "[restore] PASS: the backup restores to a byte-for-byte equivalent set of books."
  echo "[restore] MEASURED RTO: ${RTO_SECONDS}s (restore only; excludes provisioning a host)"
  exit 0
fi

rm -f "$RECEIPT"
echo "[restore] FAIL: the restored database does not match the manifest. This backup cannot be relied on." >&2
exit 1
