#!/usr/bin/env bash
# Runs every non-UI test: renders the media fixtures if needed, JovraCore and JovraMedia with `swift test`,
# then the hosted JovraTests bundle on the simulator, and prints per-class counts and the .xcresult path.
set -euo pipefail
source "$(dirname "$0")/common.sh"

# JovraMedia's fixture tests decode rendered media (cached under .cache/media; only missing clips render).
# --check never writes ground truth: it fails unless every clip, cached or fresh, reproduces the committed
# decoded-frame hashes, so the Swift tests below compare against the committed values, not a fresh rewrite.
# After changing a fixture set, run `python3 scripts/media/render.py` yourself and commit the new truth.
echo "==> render media fixtures (check against committed ground truth)"
python3 "$ROOT/scripts/media/render.py" --check

for package in JovraCore JovraMedia; do
  echo "==> swift test ($package)"
  swift_test_flags=(--package-path "$IOS_DIR/Packages/$package" --scratch-path "$DERIVED_DATA/spm-$package")
  if [ "$package" = JovraMedia ]; then swift_test_flags+=(--no-parallel); fi
  swift test "${swift_test_flags[@]}"
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
