#!/usr/bin/env bash
# Generates the local ES256 JWT signing key at backend/supabase/signing_keys.json (gitignored; ADR-0022).
# Run from backend/. Keeps an existing key unless --force is given. The key is for the local stack only.
#
# config.toml names the key file, and the Supabase CLI refuses to load the config while that file is missing,
# including for `gen signing-key` itself, so an empty key list is written first.
set -euo pipefail

cd "$(dirname "$0")/../.."
keys="supabase/signing_keys.json"

if [[ -s "$keys" && "${1:-}" != "--force" ]] && grep -q '"ES256"' "$keys"; then
  echo "kept existing ES256 signing key: backend/$keys"
  exit 0
fi

umask 077
echo '[]' > "$keys"
supabase gen signing-key --algorithm ES256 --yes > /dev/null
grep -q '"ES256"' "$keys" || { echo "no ES256 key was written to backend/$keys" >&2; exit 1; }
echo "generated ES256 signing key: backend/$keys"
