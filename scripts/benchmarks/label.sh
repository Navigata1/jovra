#!/usr/bin/env bash
# Open the JOVRA labelling tool (V01, docs/fixtures/labelling.md).
#
#   scripts/benchmarks/label.sh [VIDEO]
#
# Label files go to spec/benchmarks/labels/rec-<hash>.labels.json. The video is read on this Mac and is
# never copied, uploaded or committed. Seal a finished label file with scripts/benchmarks/seal-labels.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARGS=(--labels-dir "$ROOT/spec/benchmarks/labels")
if [[ $# -ge 1 ]]; then
  [[ -f "$1" ]] || { echo "label.sh: no such file: $1" >&2; exit 2; }
  ARGS+=(--open "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")")
fi
swift build -c release --package-path "$ROOT/tools/label-tool" --product jovra-label
exec "$(swift build -c release --package-path "$ROOT/tools/label-tool" --show-bin-path)/jovra-label" "${ARGS[@]}"
