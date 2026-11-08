#!/usr/bin/env bash
# The JOVRA watch simulators (ticket W03, #280; gate G-W-SIMUI). Creates and deletes only devices with these exact
# names, never any other simulator or pair on the machine:
#
#   JOVRA Watch Ultra 3 49mm     Apple Watch Ultra 3 (49mm)    the largest case
#   JOVRA Watch Series 11 42mm   Apple Watch Series 11 (42mm)  the common case
#   JOVRA Watch SE 3 40mm        Apple Watch SE 3 (40mm)       the smallest case
#
# Usage:
#   scripts/ios/watch-sim.sh create   [--evidence DIR]   create the three (skips any that exist), print their ids
#   scripts/ios/watch-sim.sh delete   [--evidence DIR]   shut down and delete the three (only these names)
#   scripts/ios/watch-sim.sh list                        the JOVRA watch simulators that exist now
#   scripts/ios/watch-sim.sh udid "<name>"               the id of one of them (exit 1 when it does not exist)
#
# With --evidence DIR, `xcrun simctl list devices -j` is captured before and after into DIR and
# scripts/ios/watch_sim_diff.py checks that no device other than the three JOVRA watches was removed or changed.
# Devices another process adds meanwhile (other agents create their own simulators) are reported, never touched.
#
# Environment: WATCH_RUNTIME (default: the newest installed watchOS runtime). The newest matters: an xcodebuild
# destination that names a simulator without an OS (`platform=watchOS Simulator,name=JOVRA Watch Ultra 3 49mm`)
# resolves to OS:latest, so a device on an older runtime is "not found".
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIFF="$ROOT/scripts/ios/watch_sim_diff.py"

NAMES=("JOVRA Watch Ultra 3 49mm" "JOVRA Watch Series 11 42mm" "JOVRA Watch SE 3 40mm")
TYPES=("com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Ultra-3-49mm"
       "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-42mm"
       "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-SE-3-40mm")

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

runtime() {
  if [ -n "${WATCH_RUNTIME:-}" ]; then echo "$WATCH_RUNTIME"; return; fi
  local ids
  ids="$(xcrun simctl list runtimes available | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.watchOS-[0-9-]+' || true)"
  [ -n "$ids" ] || { echo "no watchOS simulator runtime is installed (installing one needs its own gate)" >&2; exit 1; }
  sort -t- -k2,2n -k3,3n <<<"$ids" | tail -1
}

# The id of the device with exactly this name, or nothing.
udid_of() {
  xcrun simctl list devices -j | python3 -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["name"] == name:
            print(d["udid"]); raise SystemExit
' "$1"
}

snapshot() { xcrun simctl list devices -j >"$1"; }

EVIDENCE=""
command="${1:-}"; [ -n "$command" ] || usage; shift
case "$command" in
  udid) [ $# -eq 1 ] || usage; id="$(udid_of "$1")"; [ -n "$id" ] || exit 1; echo "$id"; exit 0 ;;
  list)
    for name in "${NAMES[@]}"; do
      id="$(udid_of "$name")"; [ -n "$id" ] && echo "$name ($id)"
    done
    exit 0 ;;
  create|delete) ;;
  *) usage ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --evidence) [ $# -ge 2 ] || usage; EVIDENCE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [ -n "$EVIDENCE" ]; then
  mkdir -p "$EVIDENCE"
  BEFORE="$EVIDENCE/.simctl-$command-before.json"; AFTER="$EVIDENCE/.simctl-$command-after.json"
  snapshot "$BEFORE"
fi

if [ "$command" = create ]; then
  RUNTIME="$(runtime)"
  echo "==> runtime $RUNTIME"
  for i in "${!NAMES[@]}"; do
    name="${NAMES[$i]}"
    id="$(udid_of "$name")"
    if [ -n "$id" ]; then
      echo "   exists   $name ($id)"
    else
      id="$(xcrun simctl create "$name" "${TYPES[$i]}" "$RUNTIME")"
      echo "   created  $name ($id)"
    fi
  done
else
  for name in "${NAMES[@]}"; do
    id="$(udid_of "$name")"
    if [ -z "$id" ]; then echo "   absent   $name"; continue; fi
    xcrun simctl shutdown "$id" 2>/dev/null || true
    xcrun simctl delete "$id"
    echo "   deleted  $name ($id)"
  done
fi

if [ -n "$EVIDENCE" ]; then
  snapshot "$AFTER"
  report="$EVIDENCE/simctl-$command.txt"
  status=0
  python3 "$DIFF" --command "$command" "$BEFORE" "$AFTER" "${NAMES[@]}" | tee "$report" || status=$?
  rm -f "$BEFORE" "$AFTER"
  exit $status
fi
