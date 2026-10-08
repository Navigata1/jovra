#!/usr/bin/env bash
# Runs JovraUITests on the simulator, prints per-class counts and the .xcresult path, and exports
# every named screenshot attachment to evidence/ios/<ticket>/.
#
# Usage: scripts/ios/ui-test.sh [-only-testing <Target/Class[/test]>]... [ticket-slug]
#   With -only-testing (repeatable; --only-testing also works), only the named classes or tests run,
#   so a ticket shows exactly its own tests. Without it the whole suite runs, followed by the
#   system-appearance pass: testSystemAppearanceIsFollowed with the simulator itself in light, then
#   in dark (the simulator's original appearance is restored afterwards).
#   The ticket slug defaults to the branch name minus "ticket/".
#
# Environment: SIMULATOR_ID (your own simulator), DERIVED_DATA (inside your worktree).
set -euo pipefail
source "$(dirname "$0")/common.sh"

FILTERS=()
TICKET=""
while [ $# -gt 0 ]; do
  case "$1" in
    -only-testing|--only-testing)
      [ $# -ge 2 ] || { echo "$1 needs a value, e.g. JovraUITests/HarnessUITests" >&2; exit 2; }
      FILTERS+=("$2"); shift 2 ;;
    -only-testing:*|--only-testing=*)
      FILTERS+=("${1#*[:=]}"); shift ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) TICKET="$1"; shift ;;
  esac
done
for filter in ${FILTERS[@]+"${FILTERS[@]}"}; do
  case "$filter" in
    JovraUITests|JovraUITests/*) ;;
    *) echo "-only-testing $filter: UI test filters start with JovraUITests/" >&2; exit 2 ;;
  esac
done
TICKET="${TICKET:-$(git -C "$ROOT" rev-parse --abbrev-ref HEAD | sed 's#^ticket/##')}"
EVIDENCE="$ROOT/evidence/ios/$TICKET"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE"

run_tests() { # <result-bundle> <only-testing value>...
  local bundle="$1"; shift
  local args=()
  for filter in "$@"; do args+=("-only-testing:$filter"); done
  xcodebuild test \
    -project "$IOS_DIR/Jovra.xcodeproj" \
    -scheme Jovra \
    "${args[@]}" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$bundle" \
    -quiet
}

export_screenshots() { # <result-bundle> [file-prefix]
  local export_dir
  export_dir="$(mktemp -d)"
  xcrun xcresulttool export attachments --path "$1" --output-path "$export_dir" >/dev/null
  # Keep the named XCTAttachment screenshots (lower-case words joined by hyphens), named after the
  # attachment.
  python3 - "$export_dir" "$EVIDENCE" "${2:-}" <<'PY'
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

summarize() { # <result-bundle>
  [ -d "$1" ] || { echo "no result bundle at $1"; return 1; }
  "$(dirname "$0")/xcresult-summary.py" "$1"
}

"$(dirname "$0")/generate.sh"
boot_simulator

status=0
RESULT="$DERIVED_DATA/ui-tests-$STAMP.xcresult"
if [ ${#FILTERS[@]} -gt 0 ]; then
  echo "==> JovraUITests on $SIMULATOR_ID, only: ${FILTERS[*]}"
  run_tests "$RESULT" "${FILTERS[@]}" || status=$?
else
  echo "==> JovraUITests on $SIMULATOR_ID (full suite)"
  run_tests "$RESULT" JovraUITests || status=$?
fi
echo "==> Screenshots exported to $EVIDENCE"
[ -d "$RESULT" ] && export_screenshots "$RESULT"
echo "==> Summary"
summarize "$RESULT" || status=1

if [ ${#FILTERS[@]} -eq 0 ]; then
  ORIGINAL_APPEARANCE="$(xcrun simctl ui "$SIMULATOR_ID" appearance)"
  trap 'xcrun simctl ui "$SIMULATOR_ID" appearance "$ORIGINAL_APPEARANCE"' EXIT
  for mode in light dark; do
    echo "==> System appearance pass: simulator in $mode"
    xcrun simctl ui "$SIMULATOR_ID" appearance "$mode"
    bundle="$DERIVED_DATA/ui-system-$mode-$STAMP.xcresult"
    run_tests "$bundle" JovraUITests/JovraSmokeUITests/testSystemAppearanceIsFollowed || status=$?
    [ -d "$bundle" ] && export_screenshots "$bundle" "simulator-$mode-"
    summarize "$bundle" || status=1
  done
fi

exit $status
