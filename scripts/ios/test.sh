#!/usr/bin/env bash
# Runs every non-UI test: JovraCore and JovraMedia with `swift test`, then the hosted JovraTests
# bundle on the simulator, and prints per-class counts and the .xcresult path.
set -euo pipefail
source "$(dirname "$0")/common.sh"

for package in JovraCore JovraMedia; do
  echo "==> swift test ($package)"
  swift test --package-path "$IOS_DIR/Packages/$package" --scratch-path "$DERIVED_DATA/spm-$package"
done

"$(dirname "$0")/generate.sh"
boot_simulator
RESULT="$DERIVED_DATA/unit-tests-$(date +%Y%m%d-%H%M%S).xcresult"
echo "==> xcodebuild test (JovraTests) on $SIMULATOR_ID"
status=0
xcodebuild test \
  -project "$IOS_DIR/Jovra.xcodeproj" \
  -scheme Jovra \
  -only-testing:JovraTests \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT" \
  -quiet || status=$?
if [ -d "$RESULT" ]; then
  echo "==> JovraTests summary"
  "$(dirname "$0")/xcresult-summary.py" "$RESULT" || status=1
fi
exit $status
