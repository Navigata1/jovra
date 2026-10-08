#!/usr/bin/env bash
# Localization checks, run locally and in CI (job "l10n"):
#   1. the tools' own tests, including the negative tests (scripts/l10n/tests, scripts/ios/tests);
#   2. the literal-string lint over the app sources;
#   3. the copy lint over every String Catalog;
#   4. with BRANCH and BASE set (CI sets them on pull requests), the String Catalog ownership check.
# Usage: scripts/l10n/check.sh            BRANCH=ticket/t19-home-dashboard BASE=origin/main scripts/l10n/check.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
echo "==> tool tests"
python3 -m unittest discover -s scripts/l10n/tests -t scripts/l10n
python3 -m unittest discover -s scripts/ios/tests -t scripts/ios
echo "==> literal-string lint"
python3 scripts/l10n/literal_lint.py
echo "==> copy lint"
python3 scripts/l10n/copy_lint.py
if [ -n "${BRANCH:-}" ] && [ -n "${BASE:-}" ]; then
  echo "==> String Catalog ownership ($BRANCH against $BASE)"
  python3 scripts/l10n/catalog_ownership.py --branch "$BRANCH" --base "$BASE"
fi
