#!/usr/bin/env bash
# PXL database backup.
#
# Produces three artifacts per run, in one directory:
#   pxl-<timestamp>.dump         custom-format pg_dump of the whole database
#   pxl-<timestamp>.dump.sha256  content hash, so a corrupted file is detectable
#   pxl-<timestamp>.manifest.json  what the database contained at dump time
#
# The manifest is the point. A backup file proves a dump ran; the manifest is
# what `restore_verify.sh` compares a restored database against, so a restore
# that silently loses rows, functions, policies or peso value fails loudly
# instead of looking successful.
#
# Optional encryption: set PXL_BACKUP_PASSPHRASE to produce a .dump.enc
# (AES-256-CBC, PBKDF2) and remove the plaintext dump.
#
# Usage:
#   scripts/backup.sh [output_dir]
#   PXL_BACKUP_PASSPHRASE=... scripts/backup.sh backups/

set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER="${PXL_DB_CONTAINER:-supabase_db_PXL}"
DB="${PXL_DB_NAME:-postgres}"
OUT_DIR="${1:-backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BASE="pxl-${STAMP}"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "FAIL: database container '$CONTAINER' is not running" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
DUMP="${OUT_DIR}/${BASE}.dump"
MANIFEST="${OUT_DIR}/${BASE}.manifest.json"

echo "[backup] source     : container=${CONTAINER} db=${DB}"
echo "[backup] destination: ${DUMP}"

# ── Capture what the database contains, before dumping ──────────────────────
# Financial totals are included deliberately. Object counts prove the schema
# survived; these prove the books did.
read -r -d '' MANIFEST_SQL <<'SQL' || true
SELECT json_build_object(
  'schema_migration_head', (SELECT max(version) FROM supabase_migrations.schema_migrations),
  'database_bytes',        pg_database_size(current_database()),
  'objects', json_build_object(
    'tables',   (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r'),
    'views',    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='v'),
    'functions',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'),
    'triggers', (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal),
    'policies', (SELECT count(*) FROM pg_policies WHERE schemaname='public'),
    'indexes',  (SELECT count(*) FROM pg_indexes WHERE schemaname='public')
  ),
  'books', json_build_object(
    'companies',            (SELECT count(*) FROM companies),
    'journal_entries',      (SELECT count(*) FROM journal_entries),
    'journal_entry_lines',  (SELECT count(*) FROM journal_entry_lines),
    'total_debit',          (SELECT COALESCE(SUM(debit_amount),0)::text FROM journal_entry_lines),
    'total_credit',         (SELECT COALESCE(SUM(credit_amount),0)::text FROM journal_entry_lines),
    'inventory_value',      (SELECT COALESCE(SUM(total_cost),0)::text FROM stock_balances),
    'audit_log_rows',       (SELECT count(*) FROM sys_audit_logs)
  ),
  'row_counts', (
    SELECT json_object_agg(relname, n) FROM (
      SELECT c.relname,
             (xpath('/row/cnt/text()', query_to_xml(format('select count(*) as cnt from public.%I', c.relname), false, true, '')))[1]::text::bigint AS n
      FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
      WHERE ns.nspname='public' AND c.relkind='r'
    ) t WHERE n > 0
  )
) AS manifest;
SQL

docker exec -i "$CONTAINER" psql -U postgres -d "$DB" -t -A -c "$MANIFEST_SQL" > "$MANIFEST"

if [ ! -s "$MANIFEST" ]; then
  echo "FAIL: manifest capture produced no output" >&2
  exit 1
fi

# ── Dump ────────────────────────────────────────────────────────────────────
START=$(date +%s)
docker exec "$CONTAINER" pg_dump -U postgres -d "$DB" --format=custom --compress=6 > "$DUMP"
END=$(date +%s)
DURATION=$((END - START))

if [ ! -s "$DUMP" ]; then
  echo "FAIL: dump file is empty" >&2
  exit 1
fi

sha256sum "$DUMP" | awk '{print $1}' > "${DUMP}.sha256"

# ── Optional encryption ─────────────────────────────────────────────────────
if [ -n "${PXL_BACKUP_PASSPHRASE:-}" ]; then
  openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
    -in "$DUMP" -out "${DUMP}.enc" -pass env:PXL_BACKUP_PASSPHRASE
  sha256sum "${DUMP}.enc" | awk '{print $1}' > "${DUMP}.enc.sha256"
  # Keep the plaintext checksum: restore_verify decrypts to <base>.dump and
  # checks it against this file, which detects a passphrase or archive problem
  # before any comparison runs. Only the plaintext dump itself is removed.
  rm -f "$DUMP"
  echo "[backup] encrypted : ${DUMP}.enc"
  DUMP="${DUMP}.enc"
fi

SIZE=$(du -h "$DUMP" | cut -f1)
echo "[backup] duration  : ${DURATION}s"
echo "[backup] size      : ${SIZE}"
echo "[backup] sha256    : $(cat "${DUMP}.sha256")"
echo "[backup] manifest  : ${MANIFEST}"
echo "[backup] PASS: backup written. It is NOT proven until scripts/restore_verify.sh runs against it."
echo "$BASE"
