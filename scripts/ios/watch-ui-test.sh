#!/usr/bin/env bash
# Runs the JovraWatch scheme's tests (JovraWatchUITests: the harness self-test, the fake-bridge unit tests and every
# later surface's UI tests) on the JOVRA watch simulators, prints per-class counts with each simulator's id and
# .xcresult path, and exports every named screenshot to evidence/watch/<ticket>/<device>-<name>.png.
#
# Usage: scripts/ios/watch-ui-test.sh [-only-testing <JovraWatchUITests/Class[/test]>]... [-device <tag>]... [ticket]
#   -device ultra49 | series42 | se40 (repeatable; default all three), the simulators scripts/ios/watch-sim.sh makes.
#   The ticket slug defaults to the branch name minus "ticket/" (ticket/w03-watchos-target-scaffold ->
#   w03-watchos-target-scaffold).
#
# Create the simulators first (scripts/ios/watch-sim.sh create) and delete them when done.
# Environment: DERIVED_DATA (inside your worktree).
set -euo pipefail
source "$(dirname "$0")/common.sh"

declare -a FILTERS=() TAGS=()
TICKET=""
while [ $# -gt 0 ]; do
  case "$1" in
    -only-testing|--only-testing)
      [ $# -ge 2 ] || { echo "$1 needs a value, e.g. JovraWatchUITests/HarnessSelfTests" >&2; exit 2; }
      FILTERS+=("$2"); shift 2 ;;
    -device|--device)
      [ $# -ge 2 ] || { echo "$1 needs ultra49, series42 or se40" >&2; exit 2; }
      TAGS+=("$2"); shift 2 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) TICKET="$1"; shift ;;
  esac
done
for filter in ${FILTERS[@]+"${FILTERS[@]}"}; do
  case "$filter" in
    JovraWatchUITests|JovraWatchUITests/*) ;;
    *) echo "-only-testing $filter: watch test filters start with JovraWatchUITests/" >&2; exit 2 ;;
  esac
done
[ ${#TAGS[@]} -gt 0 ] || TAGS=(ultra49 series42 se40)

device_name() {
  case "$1" in
    ultra49) echo "JOVRA Watch Ultra 3 49mm" ;;
    series42) echo "JOVRA Watch Series 11 42mm" ;;
    se40) echo "JOVRA Watch SE 3 40mm" ;;
    *) echo "unknown device tag $1 (ultra49, series42, se40)" >&2; exit 2 ;;
  esac
}

TICKET="${TICKET:-$(git -C "$ROOT" rev-parse --abbrev-ref HEAD | sed -E 's#^ticket/##')}"
EVIDENCE="$ROOT/evidence/watch/$TICKET"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE"

export_screenshots() { # <result-bundle> <file-prefix>
  local export_dir
  export_dir="$(mktemp -d)"
  xcrun xcresulttool export attachments --path "$1" --output-path "$export_dir" >/dev/null
  python3 - "$export_dir" "$EVIDENCE" "$2" <<'PY'
import json, pathlib, re, shutil, sys
src, dst, prefix = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
for test in json.loads((src / "manifest.json").read_text()):
    for item in test.get("attachments", []):
        match = re.match(r"([a-z0-9]+(?:-[a-z0-9]+)*)_\d+_", item.get("suggestedHumanReadableName", ""))
        if match and item.get("exportedFileName", "").lower().endswith(".png"):
            target = dst / f"{prefix}{match.group(1)}.png"
            shutil.copyfile(src / item["exportedFileName"], target)
            print(f"   {target}")
PY
  rm -rf "$export_dir"
}

"$(dirname "$0")/generate.sh"

status=0
for tag in "${TAGS[@]}"; do
  name="$(device_name "$tag")"
  id="$("$(dirname "$0")/watch-sim.sh" udid "$name")" || {
    echo "$name does not exist: run scripts/ios/watch-sim.sh create" >&2; exit 1; }
  bundle="$DERIVED_DATA/watch-tests-$tag-$STAMP.xcresult"
  args=()
  for filter in ${FILTERS[@]+"${FILTERS[@]}"}; do args+=("-only-testing:$filter"); done
  echo "==> JovraWatchUITests on $name ($id)${FILTERS[*]+, only: ${FILTERS[*]}}"
  xcodebuild test \
    -project "$IOS_DIR/Jovra.xcodeproj" \
    -scheme JovraWatch \
    ${args[@]+"${args[@]}"} \
    -destination "id=$id" \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$bundle" \
    -quiet || status=$?
  if [ -d "$bundle" ]; then
    echo "==> Screenshots exported to $EVIDENCE"
    export_screenshots "$bundle" "$tag-"
    "$(dirname "$0")/xcresult-summary.py" "$bundle" || status=1
  else
    echo "no result bundle at $bundle"; status=1
  fi
done
exit $status
