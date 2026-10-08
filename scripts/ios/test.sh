#!/usr/bin/env bash
# Runs every non-UI test: renders the media fixtures if needed, JovraCore and JovraMedia with `swift test`,
# then the hosted JovraTests bundle on the simulator.
set -euo pipefail
source "$(dirname "$0")/common.sh"

# JovraMedia's fixture tests decode rendered media (cached under .cache/media; only missing clips render).
echo "==> render media fixtures"
python3 "$ROOT/scripts/media/render.py"

for package in JovraCore JovraMedia; do
  echo "==> swift test ($package)"
  swift test --package-path "$IOS_DIR/Packages/$package" --scratch-path "$DERIVED_DATA/spm-$package"
done

"$(dirname "$0")/generate.sh"
boot_simulator
echo "==> xcodebuild test (JovraTests) on $SIMULATOR_ID"
xcodebuild test \
  -project "$IOS_DIR/Jovra.xcodeproj" \
  -scheme Jovra \
  -only-testing:JovraTests \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet
