#!/usr/bin/env bash
# Runs JovraUITests on the simulator and exports the named screenshot attachments to
# evidence/ios/<ticket>/:
#   1. the full suite (app forced to light and dark through its Appearance preference), then
#   2. testSystemAppearanceIsFollowed with the simulator itself in light, then in dark
#      (the simulator's original appearance is restored afterwards).
# Usage: scripts/ios/ui-test.sh [ticket-slug]   (default: the branch name minus "ticket/")
set -euo pipefail
source "$(dirname "$0")/common.sh"

TICKET="${1:-$(git -C "$ROOT" rev-parse --abbrev-ref HEAD | sed 's#^ticket/##')}"
EVIDENCE="$ROOT/evidence/ios/$TICKET"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE"

run_tests() { # <result-bundle> <xcodebuild -only-testing value>
  xcodebuild test \
    -project "$IOS_DIR/Jovra.xcodeproj" \
    -scheme Jovra \
    -only-testing:"$2" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$1" \
    -quiet
}

export_screenshots() { # <result-bundle> <attachment-name-regex> [file-prefix]
  local export_dir
  export_dir="$(mktemp -d)"
  xcrun xcresulttool export attachments --path "$1" --output-path "$export_dir" >/dev/null
  # Keep only our XCTAttachment screenshots whose names match the regex, named after the attachment.
  python3 - "$export_dir" "$EVIDENCE" "$2" "${3:-}" <<'PY'
import json, pathlib, re, shutil, sys
src, dst, pattern, prefix = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4]
for test in json.loads((src / "manifest.json").read_text()):
    for item in test.get("attachments", []):
        match = re.match(rf"({pattern}-[A-Za-z0-9-]+)_\d+_", item.get("suggestedHumanReadableName", ""))
        if match:
            target = dst / f"{prefix}{match.group(1)}.png"
            shutil.copyfile(src / item["exportedFileName"], target)
            print(f"   {target}")
PY
  rm -rf "$export_dir"
}

"$(dirname "$0")/generate.sh"
boot_simulator

echo "==> JovraUITests on $SIMULATOR_ID"
status=0
run_tests "$DERIVED_DATA/ui-tests-$STAMP.xcresult" JovraUITests || status=$?
export_screenshots "$DERIVED_DATA/ui-tests-$STAMP.xcresult" "(?:light|dark)"

ORIGINAL_APPEARANCE="$(xcrun simctl ui "$SIMULATOR_ID" appearance)"
trap 'xcrun simctl ui "$SIMULATOR_ID" appearance "$ORIGINAL_APPEARANCE"' EXIT
for mode in light dark; do
  echo "==> System appearance pass: simulator in $mode"
  xcrun simctl ui "$SIMULATOR_ID" appearance "$mode"
  run_tests "$DERIVED_DATA/ui-system-$mode-$STAMP.xcresult" JovraUITests/JovraSmokeUITests/testSystemAppearanceIsFollowed || status=$?
  export_screenshots "$DERIVED_DATA/ui-system-$mode-$STAMP.xcresult" "system" "simulator-$mode-"
done

exit $status
