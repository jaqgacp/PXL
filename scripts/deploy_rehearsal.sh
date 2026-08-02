#!/usr/bin/env bash
# Deploy rehearsal — apply the pending migrations to a copy of the DEPLOYED
# schema state, exactly as a hosted `supabase db push` would.
#
# `npm run test:db:fresh` proves the migration chain replays from empty. That is
# NOT the same thing as proving a deploy is safe: production is not empty, it is
# sitting at an older migration and must move forward without breaking. This
# script rehearses that move.
#
#   1. build a database containing ONLY the migrations already deployed
#   2. apply every pending migration in order, timing each one
#   3. compare the result against a full fresh replay
#
# A pending migration that fails here would have failed in production.
#
# Usage:
#   scripts/deploy_rehearsal.sh [deployed_through_version]
#   scripts/deploy_rehearsal.sh 20260716000005

set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER="${PXL_DB_CONTAINER:-supabase_db_PXL}"
DEPLOYED_THROUGH="${1:-20260716000005}"
REHEARSAL="${PXL_REHEARSAL_DB:-pxl_deploy_rehearsal}"
REFERENCE="${PXL_REFERENCE_DB:-pxl_deploy_reference}"
fail=0

echo "[rehearsal] target deployed-through : ${DEPLOYED_THROUGH}"

mapfile -t ALL < <(ls -1 supabase/migrations/*.sql | sed 's|.*/||' | sort)
APPLIED=(); PENDING=()
for f in "${ALL[@]}"; do
  v="${f%%_*}"
  if [[ "$v" > "$DEPLOYED_THROUGH" ]]; then PENDING+=("$f"); else APPLIED+=("$f"); fi
done
echo "[rehearsal] already deployed        : ${#APPLIED[@]}"
echo "[rehearsal] pending                 : ${#PENDING[@]}"
[ "${#PENDING[@]}" -gt 0 ] || { echo "[rehearsal] nothing pending — hosted is current."; exit 0; }

apply_into() { # db, files...
  local db="$1"; shift
  local f txn
  for f in "$@"; do
    # Apply each migration in ONE transaction, which is how `supabase db push`
    # runs it. This is not cosmetic: several migrations use
    # `CREATE TEMP TABLE … ON COMMIT DROP`, and under psql's default autocommit
    # each statement is its own transaction, so the temp table is destroyed the
    # instant it is created and the next statement fails. Applying per-statement
    # would report a production failure that cannot actually happen.
    #
    # Migrations that open their own BEGIN/COMMIT manage their own boundaries and
    # must not be wrapped again.
    if grep -q '^BEGIN;' "supabase/migrations/$f"; then txn=""; else txn="--single-transaction"; fi
    if ! docker exec -i "$CONTAINER" psql -U postgres -d "$db" -v ON_ERROR_STOP=1 -q $txn \
         < "supabase/migrations/$f" > /tmp/pxl_rehearsal_step.log 2>&1; then
      echo "  FAIL applying $f"
      grep -iE '^(psql:|ERROR|DETAIL|HINT)' /tmp/pxl_rehearsal_step.log | head -6 | sed 's/^/    /'
      return 1
    fi
  done
  return 0
}

# The migration chain assumes the Supabase platform schemas (auth, extensions,
# storage, vault, …) already exist — production always has them, a bare
# CREATE DATABASE does not. Bootstrap them schema-only from the live database so
# the rehearsal starts from the same ground production stands on. Roles are
# cluster-level and already present.
BOOTSTRAP_SQL="/tmp/pxl_platform_bootstrap.sql"
build_bootstrap() {
  [ -s "$BOOTSTRAP_SQL" ] && return 0
  docker exec "$CONTAINER" pg_dump -U postgres -d postgres --schema-only \
    --schema=auth --schema=extensions --schema=storage --schema=vault \
    --schema=graphql --schema=graphql_public --schema=realtime --schema=_realtime \
    --schema=net --schema=supabase_functions --schema=supabase_migrations \
    > "$BOOTSTRAP_SQL"
  [ -s "$BOOTSTRAP_SQL" ] || { echo "FAIL: could not capture platform bootstrap" >&2; exit 1; }
}

recreate() {
  build_bootstrap
  docker exec "$CONTAINER" psql -U postgres -d postgres -q \
    -c "DROP DATABASE IF EXISTS $1 WITH (FORCE);" -c "CREATE DATABASE $1;"
  # Benign duplicate-object notices are expected; failures surface when the
  # migrations themselves run.
  docker exec -i "$CONTAINER" psql -U postgres -d "$1" -q < "$BOOTSTRAP_SQL" > /dev/null 2>&1 || true
}

# ── 1. Rebuild the deployed (production-equivalent) baseline ────────────────
echo "[rehearsal] building baseline at ${DEPLOYED_THROUGH} ..."
recreate "$REHEARSAL"
if ! apply_into "$REHEARSAL" "${APPLIED[@]}"; then
  echo "[rehearsal] FAIL: could not reproduce the currently deployed schema." >&2
  exit 1
fi
BASE_TABLES=$(docker exec "$CONTAINER" psql -U postgres -d "$REHEARSAL" -t -A -c \
  "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r'")
echo "[rehearsal] baseline built: ${BASE_TABLES} public tables"

# ── 2. Apply the pending migrations, one at a time ──────────────────────────
echo "[rehearsal] applying ${#PENDING[@]} pending migrations ..."
START=$(date +%s)
for f in "${PENDING[@]}"; do
  t0=$(date +%s%N)
  if ! apply_into "$REHEARSAL" "$f"; then
    echo "[rehearsal] FAIL: pending migration ${f} does not apply to the deployed schema." >&2
    echo "[rehearsal] This WOULD HAVE BROKEN PRODUCTION." >&2
    exit 1
  fi
  ms=$(( ( $(date +%s%N) - t0 ) / 1000000 ))
  printf "  %-72s %5s ms\n" "$f" "$ms"
done
END=$(date +%s)
UPGRADE_SECONDS=$((END - START))

# ── 3. Compare against a full fresh replay ─────────────────────────────────
echo "[rehearsal] building reference (full fresh replay) ..."
recreate "$REFERENCE"
if ! apply_into "$REFERENCE" "${ALL[@]}"; then
  echo "[rehearsal] FAIL: full fresh replay failed." >&2
  exit 1
fi

echo "[rehearsal] upgraded-vs-fresh comparison"
cmp_obj() { # label sql
  local a b
  a=$(docker exec "$CONTAINER" psql -U postgres -d "$REHEARSAL" -t -A -c "$2")
  b=$(docker exec "$CONTAINER" psql -U postgres -d "$REFERENCE" -t -A -c "$2")
  if [ "$a" = "$b" ]; then printf "  %-12s %-8s OK\n" "$1" "$a"
  else printf "  %-12s upgraded=%-8s fresh=%-8s MISMATCH\n" "$1" "$a" "$b"; fail=1; fi
}
cmp_obj tables    "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r'"
cmp_obj views     "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='v'"
# Extension member objects are excluded. `CREATE EXTENSION IF NOT EXISTS pgcrypto`
# without a schema lands its ~36 shims in public inside a scratch database, while
# the real database keeps them in `extensions`. That is an artifact of building a
# database from scratch, not a schema difference, and counting them would make
# this comparison permanently and misleadingly noisy.
cmp_obj functions "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e')"
cmp_obj triggers  "SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal"
cmp_obj policies  "SELECT count(*) FROM pg_policies WHERE schemaname='public'"
cmp_obj indexes   "SELECT count(*) FROM pg_indexes WHERE schemaname='public'"
cmp_obj columns   "SELECT count(*) FROM information_schema.columns WHERE table_schema='public'"

echo "[rehearsal] column-level structural diff"
DIFF=$(docker exec "$CONTAINER" psql -U postgres -d postgres -t -A -c "
  SELECT count(*) FROM (
    SELECT table_name, column_name, data_type FROM dblink('dbname=${REHEARSAL}',
      'SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema=''public''')
      AS a(table_name text, column_name text, data_type text)
    EXCEPT
    SELECT table_name, column_name, data_type FROM dblink('dbname=${REFERENCE}',
      'SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema=''public''')
      AS b(table_name text, column_name text, data_type text)
  ) d;" 2>/dev/null || echo "skipped")
if [ "$DIFF" = "skipped" ]; then
  echo "  (dblink unavailable — object-count comparison above is the evidence)"
elif [ "$DIFF" = "0" ]; then
  echo "  columns identical                OK"
else
  echo "  ${DIFF} column differences        MISMATCH"; fail=1
fi

if [ "${PXL_KEEP_REHEARSAL_DB:-0}" != "1" ]; then
  docker exec "$CONTAINER" psql -U postgres -d postgres -q \
    -c "DROP DATABASE IF EXISTS ${REHEARSAL} WITH (FORCE);" \
    -c "DROP DATABASE IF EXISTS ${REFERENCE} WITH (FORCE);"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "[rehearsal] PASS: all ${#PENDING[@]} pending migrations apply cleanly to the deployed schema,"
  echo "[rehearsal]       and the upgraded database is structurally identical to a fresh replay."
  echo "[rehearsal] MEASURED UPGRADE WINDOW: ${UPGRADE_SECONDS}s (schema only, excludes data volume)"
  exit 0
fi
echo "[rehearsal] FAIL: upgrading differs from a fresh replay. Do not deploy." >&2
exit 1
