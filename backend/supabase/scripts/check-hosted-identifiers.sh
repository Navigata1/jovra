#!/usr/bin/env bash
# Fails when a hosted Supabase identifier or a real email address appears in the backend tree (S75 acceptance:
# no hosted URL, project ref, key or real email; ADR-0014 gate 2, CLAUDE.md rules 5 and 7).
#
#   check-hosted-identifiers.sh [path ...]     default: backend/ and .github/workflows/backend-db.yml
#
# Looks for: a *.supabase.co host, secret or publishable API keys (sb_secret_, sb_publishable_), JWT-shaped
# strings (legacy anon or service_role keys) and any email address whose domain is not
# example.test. A self-test runs first, so a broken pattern fails the check instead of passing silently.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$repo"

# Patterns are assembled from pieces so this file does not match itself.
host_pattern='[a-z0-9-]+\.supa''base\.co([^m]|$)'
key_pattern='sb_(sec''ret|publish''able)_[A-Za-z0-9_-]+'
jwt_pattern='eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}'
email_pattern='[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+'
allowed_email='@example\.test\b'

scan() {  # prints offending lines of the given files; exit status 0 when something was found
  local found=1
  grep -nHIE "$host_pattern|$key_pattern|$jwt_pattern" "$@" && found=0
  grep -nHIoE "$email_pattern" "$@" | grep -viE "$allowed_email" && found=0
  return $found
}

# Self-test: each planted sample must be caught, and an example.test address must not be.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'url = "https://abcdefghijklmnopqrst.%s.co"\n' "supabase" > "$tmp/host"
printf 'key = "sb_%s_0123456789abcdef"\n' "secret" > "$tmp/key"
printf 'anon = "eyJ%s.eyJ%s.x"\n' hbGciOiJIUzI1NiJ9 yb2xlIjoiYW5vbiJ9 > "$tmp/jwt"
printf 'owner = "someone@%s.com"\n' "gmail" > "$tmp/email"
printf 'tester = "owner.tester@example.test"\ndocs = "https://supabase.com/docs"\n' > "$tmp/clean"
for sample in host key jwt email; do
  scan "$tmp/$sample" > /dev/null || { echo "self-test: the $sample pattern missed its sample" >&2; exit 2; }
done
if scan "$tmp/clean" > /dev/null; then echo "self-test: a clean file was flagged" >&2; exit 2; fi

if [[ $# -eq 0 ]]; then
  set -- backend .github/workflows/backend-db.yml
fi
# Only tracked files count (git ls-files, which includes staged and intent-to-add files): gitignored local files
# such as signing_keys.json, .dev.vars or a real testers.allowlist are never part of the tree.
files=()
while IFS= read -r -d '' file; do [[ -f "$file" ]] && files+=("$file"); done < <(git ls-files -z -- "$@")
if [[ ${#files[@]} -eq 0 ]]; then echo "FAIL  no tracked files under: $*" >&2; exit 1; fi

if scan "${files[@]}"; then
  echo "FAIL  hosted identifiers or non-example.test email addresses found (above)" >&2
  exit 1
fi
echo "OK  ${#files[@]} files: no supabase.co host, API key, JWT or email outside example.test"
