#!/usr/bin/env bash
# Set a known password on the local demo users so you can sign in to the app.
#
# The canonical seed creates demo users with no usable password, because nothing
# in the automated lanes signs in through the UI. This grants each of them a
# development password so `npm run dev` is actually usable.
#
# LOCAL ONLY. It refuses to run against anything but the local container, and the
# password it sets is trivial by design. Never run this against a hosted project.
#
# Re-run it after `npm run test:canonical` or any database reset — a reset
# restores the seeded users and wipes the password again.
#
# Usage:
#   npm run dev:login            # default password: pxl-dev-password
#   PXL_DEV_PASSWORD=… npm run dev:login

set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER="${PXL_DB_CONTAINER:-supabase_db_PXL}"
PASSWORD="${PXL_DEV_PASSWORD:-pxl-dev-password}"

# Refuse to touch anything that is not the local development container.
case "$CONTAINER" in
  supabase_db_*) ;;
  *) echo "FAIL: refusing to set development passwords on '${CONTAINER}'." >&2; exit 1 ;;
esac
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "FAIL: local database container '${CONTAINER}' is not running. Run: npx supabase start" >&2
  exit 1
fi

docker exec -i "$CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q <<SQL
UPDATE auth.users
SET encrypted_password = extensions.crypt('${PASSWORD}', extensions.gen_salt('bf')),
    email_confirmed_at = COALESCE(email_confirmed_at, now()),
    updated_at         = now()
WHERE email LIKE '%@pxl.local';
SQL

echo "[dev:login] development password set for the local demo users."
docker exec "$CONTAINER" psql -U postgres -d postgres -t -A -F' | ' -c \
  "SELECT email FROM auth.users WHERE email LIKE '%@pxl.local' ORDER BY email;" \
  | sed 's/^/  /'
echo
echo "  password: ${PASSWORD}"
echo "  sign in at the dev server with any address above."
