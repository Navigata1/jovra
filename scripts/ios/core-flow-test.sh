#!/usr/bin/env bash
# Exercise the real native recording-to-export flow on an explicitly owned simulator.
set -euo pipefail

: "${SIMULATOR_ID:?Set SIMULATOR_ID to the dedicated simulator for this checkout}"
: "${DERIVED_DATA:?Set DERIVED_DATA to an owned build directory for this checkout}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if ! rg -q 'class CoreFlowUITests' "$ROOT/ios/JovraUITests"; then
  echo "CoreFlowUITests is not implemented in this checkout; the integration gate is pending." >&2
  exit 2
fi

exec "$SCRIPT_DIR/ui-test.sh" -only-testing JovraUITests/CoreFlowUITests core-flow
