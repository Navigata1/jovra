#!/usr/bin/env bash
# Runs every backend contract check (S81). Usage: backend/contracts/check.sh [--require-jsonschema]
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo"
tools=backend/contracts/tools
python3 "$tools/generate.py" --check
python3 "$tools/route_coverage.py"
python3 "$tools/validate.py" "$@"
python3 "$tools/check_fixture_hygiene.py"
python3 -m unittest discover -s "$tools" -p 'test_*.py'
