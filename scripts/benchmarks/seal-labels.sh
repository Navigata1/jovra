#!/usr/bin/env bash
# Record a finished label file in the label set (spec/benchmarks/labels/manifest.json): its SHA-256, its
# hash-fixed tuning / held-out split and its counts. Then commit the label file and the manifest together.
#
#   scripts/benchmarks/seal-labels.sh spec/benchmarks/labels/rec-<hash>.labels.json
#   scripts/benchmarks/seal-labels.sh            # only show what is labelled against each target
#
# Exit status: 0 the label set is complete; 4 it is still founder-pending; 2 the file was refused.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN=(swift run -c release --package-path "$ROOT/ios/Packages/JovraMedia" jovra-benchmark labels)
if [[ $# -ge 1 ]]; then
  "${RUN[@]}" seal "$1" --repo "$ROOT"
else
  "${RUN[@]}" status --repo "$ROOT"
fi
