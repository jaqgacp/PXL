#!/usr/bin/env bash
# Deploy pending migrations to the hosted PXL project — safely.
#
# This exists so the safety steps cannot be skipped under time pressure. It
# refuses to push until it has taken a hosted backup, rehearsed the upgrade
# locally, and shown you exactly what will be sent.
#
# ── What you must provide ───────────────────────────────────────────────────
#   1. An access token, EITHER by running `supabase login` once (preferred —
#      stored in ~/.supabase, outside this repository), OR by exporting
#      SUPABASE_ACCESS_TOKEN.
#   2. The remote Postgres password, exported as SUPABASE_DB_PASSWORD.
#
#   Never commit either. Never paste either into a chat transcript. If a token
#   is ever exposed, revoke it in the Supabase dashboard immediately — this
#   project has already had to do that once (PXL-AUD-055).
#
# ── Usage ───────────────────────────────────────────────────────────────────
#   supabase login                       # once
#   export SUPABASE_DB_PASSWORD='…'
#   npm run deploy:hosted                # dry run: shows the plan, pushes nothing
#   npm run deploy:hosted -- --execute   # actually deploys

set -euo pipefail
cd "$(dirname "$0")/.."

EXECUTE=0
[ "${1:-}" = "--execute" ] && EXECUTE=1

DEPLOYED_THROUGH="${PXL_DEPLOYED_THROUGH:-20260716000005}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="backups/hosted"
say() { printf '\n\033[1m[deploy] %s\033[0m\n' "$*"; }

# ── 0. Preflight: credentials ───────────────────────────────────────────────
say "0/6  preflight"
if ! npx supabase projects list >/dev/null 2>&1; then
  cat >&2 <<'EOF'
FAIL: the Supabase CLI is not authenticated.

  Run ONE of these yourself — do not send the value to anyone:

    supabase login                      # preferred; stores a session in ~/.supabase
    export SUPABASE_ACCESS_TOKEN='…'    # Dashboard -> Account -> Access Tokens

EOF
  exit 1
fi
echo "  access token      : OK"

if [ -z "${SUPABASE_DB_PASSWORD:-}" ]; then
  cat >&2 <<'EOF'
FAIL: SUPABASE_DB_PASSWORD is not set.

  export SUPABASE_DB_PASSWORD='…'       # Dashboard -> Project Settings -> Database

EOF
  exit 1
fi
echo "  database password : set"

# ── 1. What is pending ──────────────────────────────────────────────────────
say "1/6  migrations pending on the remote"
npx supabase migration list --linked --password "$SUPABASE_DB_PASSWORD" || {
  echo "FAIL: could not read remote migration history" >&2; exit 1; }

# ── 2. Rehearse locally against the deployed version ────────────────────────
say "2/6  rehearsing the upgrade locally (from ${DEPLOYED_THROUGH})"
bash scripts/deploy_rehearsal.sh "$DEPLOYED_THROUGH" | tail -12
echo "  rehearsal         : PASS"

# ── 3. Back up the hosted database ──────────────────────────────────────────
# A deploy without a restorable backup is a gamble. There is no supported
# "undo migration" path; this backup IS the rollback plan.
say "3/6  backing up the hosted database"
mkdir -p "$BACKUP_DIR"
SCHEMA_FILE="${BACKUP_DIR}/hosted-${STAMP}.schema.sql"
DATA_FILE="${BACKUP_DIR}/hosted-${STAMP}.data.sql"
ROLES_FILE="${BACKUP_DIR}/hosted-${STAMP}.roles.sql"

npx supabase db dump --linked --password "$SUPABASE_DB_PASSWORD" -f "$SCHEMA_FILE"
npx supabase db dump --linked --password "$SUPABASE_DB_PASSWORD" --data-only --use-copy -f "$DATA_FILE"
npx supabase db dump --linked --password "$SUPABASE_DB_PASSWORD" --role-only -f "$ROLES_FILE" || true

for f in "$SCHEMA_FILE" "$DATA_FILE"; do
  [ -s "$f" ] || { echo "FAIL: backup file $f is empty — refusing to deploy" >&2; exit 1; }
  sha256sum "$f" | awk '{print $1}' > "${f}.sha256"
  printf "  %-46s %s\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)"
done

if [ -n "${PXL_BACKUP_PASSPHRASE:-}" ]; then
  for f in "$SCHEMA_FILE" "$DATA_FILE" "$ROLES_FILE"; do
    [ -s "$f" ] || continue
    openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -in "$f" -out "${f}.enc" -pass env:PXL_BACKUP_PASSPHRASE
    rm -f "$f"
  done
  echo "  encrypted         : yes"
else
  echo "  encrypted         : NO — set PXL_BACKUP_PASSPHRASE to encrypt at rest"
fi

# ── 4. Show exactly what would be sent ──────────────────────────────────────
say "4/6  dry run — what will be applied"
npx supabase db push --linked --password "$SUPABASE_DB_PASSWORD" --dry-run

# ── 5. Push ─────────────────────────────────────────────────────────────────
if [ "$EXECUTE" -ne 1 ]; then
  say "5/6  STOPPING — dry run only"
  cat <<EOF
  Nothing was pushed. A hosted backup was taken and the upgrade was rehearsed.

  Review the dry-run output above, then run:

      npm run deploy:hosted -- --execute

  Rollback plan if the deploy fails: restore from
      ${BACKUP_DIR}/hosted-${STAMP}.*
  following docs/PXL/00. Governance/PXL_BACKUP_AND_RECOVERY_RUNBOOK.md
EOF
  exit 0
fi

say "5/6  pushing to the linked project"
npx supabase db push --linked --password "$SUPABASE_DB_PASSWORD"

# ── 6. Confirm parity ───────────────────────────────────────────────────────
say "6/6  verifying parity"
npx supabase migration list --linked --password "$SUPABASE_DB_PASSWORD"
cat <<EOF

[deploy] Local and remote migration lists are printed above. Every local
[deploy] migration must now appear on the remote side.

Next:
  - update the hosted status block in AI/AI_STATE.md
  - run: npm run test:hosted:read-only
  - keep ${BACKUP_DIR}/hosted-${STAMP}.* until the deploy is confirmed healthy
EOF
