#!/usr/bin/env bash
# Replicate a verified PXL backup set to an offsite destination, then read it
# back and prove the copy is intact.
#
# A backup on the same host as the database does not survive the failure that
# destroys the host, so the offsite copy is the one that matters. And an offsite
# copy that has never been read back is subject to exactly the criticism this
# repository already applies to an unrestored dump: it is a hope, not a backup.
# This script therefore always downloads what it just uploaded and compares the
# SHA-256 against the local receipt.
#
# Two things it refuses to do:
#   1. Send an archive that restore_verify.sh has not passed. Replicating an
#      unverified dump multiplies a possibly-broken artifact.
#   2. Send unencrypted books off the host. Client books leaving the machine
#      without AES-256 is a disclosure, not a backup.
#
# Usage:
#   PXL_OFFSITE_URL=s3://bucket/pxl        scripts/backup_offsite.sh
#   PXL_OFFSITE_URL=/mnt/offsite/pxl       scripts/backup_offsite.sh backups/pxl-<ts>
#
# Env:
#   PXL_OFFSITE_URL             required — s3://…, gs://…, file:///abs, or /abs
#   PXL_OFFSITE_TOOL            optional — aws | rclone | file (inferred from the URL)
#   PXL_BACKUP_PASSPHRASE       required to produce the encrypted archive
#   PXL_OFFSITE_ALLOW_PLAINTEXT set to 1 only for a non-client test destination

set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="${PXL_BACKUP_DIR:-backups}"
MODE="replicate"

if [ "${1:-}" = "--check" ]; then
  MODE="check"
  shift
fi

if [ "$MODE" = "replicate" ]; then
  if [ $# -ge 1 ]; then
    BASE_PATH="$1"
  else
    BASE_PATH="$(ls -1 "${OUT_DIR}"/pxl-*.manifest.json 2>/dev/null | sort | tail -1 | sed 's/\.manifest\.json$//')"
  fi

  if [ -z "${BASE_PATH:-}" ] || [ ! -f "${BASE_PATH}.manifest.json" ]; then
    echo "FAIL: no backup manifest found. Run scripts/backup.sh first." >&2
    exit 1
  fi

  BASE_NAME="$(basename "$BASE_PATH")"
fi

if [ -z "${PXL_OFFSITE_URL:-}" ]; then
  cat >&2 <<'MSG'
FAIL: PXL_OFFSITE_URL is not set, so there is no offsite destination.

Recoverability is not operated until a copy of the books exists somewhere the
loss of this host cannot reach. Set PXL_OFFSITE_URL to an object-storage prefix
(s3://bucket/pxl) or a path on separate storage (/mnt/offsite/pxl).
MSG
  exit 1
fi

# ── The set must have passed a restore verification ─────────────────────────
if [ "$MODE" = "replicate" ] && [ ! -f "${BASE_PATH}.verified.json" ]; then
  echo "FAIL: ${BASE_NAME} has no verification receipt." >&2
  echo "      Run scripts/restore_verify.sh ${BASE_PATH} before replicating it offsite." >&2
  exit 1
fi

# ── Refuse to send plaintext books off the host ─────────────────────────────
if [ "$MODE" = "check" ]; then
  : # --check uploads a canary, never books; the encryption rule does not apply
elif [ -f "${BASE_PATH}.dump.enc" ]; then
  ARCHIVE="${BASE_PATH}.dump.enc"
elif [ "${PXL_OFFSITE_ALLOW_PLAINTEXT:-0}" = "1" ]; then
  ARCHIVE="${BASE_PATH}.dump"
  echo "[offsite] WARNING: replicating an UNENCRYPTED archive because PXL_OFFSITE_ALLOW_PLAINTEXT=1."
  echo "[offsite] WARNING: this is acceptable for a test destination only, never for client books."
else
  cat >&2 <<MSG
FAIL: ${BASE_NAME} has no encrypted archive (.dump.enc).

Set PXL_BACKUP_PASSPHRASE when taking the backup so the archive that leaves this
host is AES-256 encrypted. Override with PXL_OFFSITE_ALLOW_PLAINTEXT=1 only for a
destination that will never hold client books.
MSG
  exit 1
fi

if [ "$MODE" = "replicate" ]; then
  [ -f "${ARCHIVE}.sha256" ] || { echo "FAIL: ${ARCHIVE}.sha256 is missing" >&2; exit 1; }
  EXPECT="$(cat "${ARCHIVE}.sha256")"
fi

# ── Resolve the transport ───────────────────────────────────────────────────
DEST="${PXL_OFFSITE_URL%/}"
case "$DEST" in
  s3://*|gs://*) TOOL="${PXL_OFFSITE_TOOL:-aws}" ;;
  file://*)      TOOL="${PXL_OFFSITE_TOOL:-file}"; DEST="${DEST#file://}" ;;
  /*)            TOOL="${PXL_OFFSITE_TOOL:-file}" ;;
  *)             TOOL="${PXL_OFFSITE_TOOL:-rclone}" ;;
esac

put() { # local_file remote_name
  case "$TOOL" in
    aws)    aws s3 cp --only-show-errors "$1" "${DEST}/$2" ;;
    rclone) rclone copyto --quiet "$1" "${DEST}/$2" ;;
    file)   mkdir -p "$DEST" && cp -f "$1" "${DEST}/$2" ;;
    *) echo "FAIL: unsupported PXL_OFFSITE_TOOL '${TOOL}'" >&2; return 1 ;;
  esac
}

get() { # remote_name local_file
  case "$TOOL" in
    aws)    aws s3 cp --only-show-errors "${DEST}/$1" "$2" ;;
    rclone) rclone copyto --quiet "${DEST}/$1" "$2" ;;
    file)   cp -f "${DEST}/$1" "$2" ;;
    *) return 1 ;;
  esac
}

rm_remote() { # remote_name
  case "$TOOL" in
    aws)    aws s3 rm --only-show-errors "${DEST}/$1" ;;
    rclone) rclone deletefile --quiet "${DEST}/$1" ;;
    file)   rm -f "${DEST:?}/$1" ;;
    *) return 1 ;;
  esac
}

# ── --check: prove the destination works before trusting it with books ──────
# Run this the moment a bucket is created, and on a schedule afterwards. It
# exercises exactly what a real replication needs — credentials, write, read,
# byte fidelity, delete — using a canary that contains no client data, so it is
# safe to point at the production destination from CI.
if [ "$MODE" = "check" ]; then
  echo "[offsite] destination: ${DEST} (via ${TOOL})"
  CANARY="$(mktemp)"
  CANARY_BACK="$(mktemp)"
  trap 'rm -f "$CANARY" "$CANARY_BACK"' EXIT
  CANARY_NAME="pxl-destination-check-$(date -u +%Y%m%dT%H%M%SZ).txt"

  printf 'PXL offsite destination check %s\nThis object contains no client data and can be deleted.\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$CANARY"
  CANARY_SUM="$(sha256sum "$CANARY" | awk '{print $1}')"

  put "$CANARY" "$CANARY_NAME"
  echo "[offsite] write      : OK"
  get "$CANARY_NAME" "$CANARY_BACK"
  echo "[offsite] read       : OK"

  if [ "$CANARY_SUM" != "$(sha256sum "$CANARY_BACK" | awk '{print $1}')" ]; then
    echo "[offsite] FAIL: the destination returned different bytes than it was given." >&2
    exit 1
  fi
  echo "[offsite] round-trip : byte-identical"

  # Retention needs delete. Finding that out during the first prune is too late.
  if rm_remote "$CANARY_NAME"; then
    echo "[offsite] delete     : OK"
  else
    echo "[offsite] FAIL: the destination does not permit delete, so retention cannot be enforced." >&2
    exit 1
  fi

  echo "[offsite] PASS: the destination accepts, returns and removes objects intact."
  echo "[offsite] NOTE: this proves the destination, not that any backup lives there."
  exit 0
fi

echo "[offsite] set        : ${BASE_NAME}"
echo "[offsite] destination: ${DEST} (via ${TOOL})"

# ── Replicate the whole set, not just the archive ───────────────────────────
# The archive alone cannot be verified later: restore_verify.sh compares against
# the manifest, and the receipt records that this set already restored cleanly.
for suffix in .manifest.json .verified.json; do
  put "${BASE_PATH}${suffix}" "${BASE_NAME}${suffix}"
done
put "${ARCHIVE}.sha256" "$(basename "${ARCHIVE}").sha256"
put "$ARCHIVE" "$(basename "$ARCHIVE")"

# ── Read it back — the part that makes this a copy rather than an intention ──
READBACK="$(mktemp)"
trap 'rm -f "$READBACK"' EXIT
get "$(basename "$ARCHIVE")" "$READBACK"

ACTUAL="$(sha256sum "$READBACK" | awk '{print $1}')"
if [ "$EXPECT" != "$ACTUAL" ]; then
  echo "[offsite] FAIL: the offsite copy does not match the local archive." >&2
  echo "          expected ${EXPECT}" >&2
  echo "          got      ${ACTUAL}" >&2
  exit 1
fi

SIZE="$(du -h "$READBACK" | cut -f1)"
echo "[offsite] read-back  : ${SIZE}, sha256 OK"
echo "[offsite] PASS: ${BASE_NAME} exists offsite and was proven readable."
