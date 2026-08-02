#!/usr/bin/env bash
# One unattended cycle of the PXL backup service.
#
# `npm run backup:drill` demonstrates that recovery works. This script is what
# turns that demonstration into an operated service, and it is the single unit
# of work the schedule invokes:
#
#   1. take an encrypted backup            scripts/backup.sh
#   2. prove it restores                   scripts/restore_verify.sh
#   3. copy it offsite and read it back    scripts/backup_offsite.sh
#   4. enforce retention                   scripts/backup_prune.mjs --apply
#   5. record the outcome                  backups/drill-history.jsonl
#
# It fails closed at every step. A schedule that keeps reporting success while
# one stage quietly stopped working is worse than no schedule, because the gap
# is discovered during the incident.
#
# The journal is the evidence that the schedule ran, as distinct from the
# evidence that the tooling works. Both are needed: the drill can be perfect and
# still be worthless if nothing invokes it.
#
# Usage:
#   PXL_BACKUP_PASSPHRASE=… PXL_OFFSITE_URL=s3://bucket/pxl scripts/backup_operate.sh
#
# Env: as scripts/backup.sh, restore_verify.sh and backup_offsite.sh, plus
#   PXL_SKIP_OFFSITE=1   run stages 1, 2, 4 and 5 only. For a workstation with
#                        no destination; never for an operated deployment.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="${PXL_BACKUP_DIR:-backups}"
HISTORY="${OUT_DIR}/drill-history.jsonl"
STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STAGE="start"
SET_NAME=""

record() { # outcome detail
  mkdir -p "$OUT_DIR"
  printf '{"started_at":"%s","finished_at":"%s","set":"%s","outcome":"%s","failed_stage":"%s","offsite":"%s","detail":"%s"}\n' \
    "$STARTED" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SET_NAME" "$1" "$2" \
    "${PXL_OFFSITE_URL:-none}" "$3" >> "$HISTORY"
}

on_failure() {
  record fail "$STAGE" "stage ${STAGE} failed; see the run log"
  echo "[operate] FAIL: the backup service cycle failed at stage '${STAGE}'." >&2
  echo "[operate] Recoverability is NOT operated until this passes." >&2
}
trap on_failure ERR

if [ -z "${PXL_BACKUP_PASSPHRASE:-}" ]; then
  echo "[operate] WARNING: PXL_BACKUP_PASSPHRASE is unset — the archive will not be encrypted."
  echo "[operate] WARNING: an unencrypted archive cannot be replicated offsite."
fi

# ── 1. Back up ──────────────────────────────────────────────────────────────
STAGE="backup"
echo "[operate] stage 1/5: taking a backup"
SET_NAME="$(bash scripts/backup.sh "$OUT_DIR" | tail -1)"
BASE_PATH="${OUT_DIR}/${SET_NAME}"
echo "[operate] set: ${SET_NAME}"

# ── 2. Prove it restores ────────────────────────────────────────────────────
STAGE="restore_verify"
echo "[operate] stage 2/5: verifying the restore"
bash scripts/restore_verify.sh "$BASE_PATH"

# ── 3. Offsite ──────────────────────────────────────────────────────────────
STAGE="offsite"
if [ "${PXL_SKIP_OFFSITE:-0}" = "1" ]; then
  echo "[operate] stage 3/5: SKIPPED — PXL_SKIP_OFFSITE=1"
  echo "[operate] NOTE: without an offsite copy this cycle does not make the books"
  echo "[operate]       survivable. It proves the tooling, nothing more."
  OFFSITE_STATE="skipped"
else
  echo "[operate] stage 3/5: replicating offsite"
  bash scripts/backup_offsite.sh "$BASE_PATH"
  OFFSITE_STATE="verified"
fi

# ── 4. Retention ────────────────────────────────────────────────────────────
STAGE="prune"
echo "[operate] stage 4/5: enforcing retention"
node scripts/backup_prune.mjs --apply "$OUT_DIR"

# An object-storage destination should use a bucket lifecycle policy instead;
# only a filesystem destination is prunable from here.
if [ "${PXL_SKIP_OFFSITE:-0}" != "1" ]; then
  OFFSITE_PATH="${PXL_OFFSITE_URL:-}"
  OFFSITE_PATH="${OFFSITE_PATH#file://}"
  case "$OFFSITE_PATH" in
    /*) node scripts/backup_prune.mjs --apply "$OFFSITE_PATH" ;;
    *)  echo "[operate] offsite retention is the destination's lifecycle policy, not this script" ;;
  esac
fi

# ── 5. Journal ──────────────────────────────────────────────────────────────
STAGE="record"
trap - ERR
record pass "" "offsite ${OFFSITE_STATE}"

echo "[operate] stage 5/5: recorded in ${HISTORY}"
echo "[operate] PASS: backup taken, restore proven, offsite ${OFFSITE_STATE}, retention enforced."
