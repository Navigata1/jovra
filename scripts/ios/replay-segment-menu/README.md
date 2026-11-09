# Synthetic Replay menu probe support

This directory holds test-only source for a future generated DEBUG simulator app. The production Xcode project does not include it. A generator must supply a new lowercase UUID for `@TOKEN@` and its UUID-derived `@APP_BUNDLE@`, use a fresh isolated app container, and bundle the exact fixture below. Keep generated projects and results outside the tracked tree.

The canonical session declares two synthetic finalized segments. The alternate entry requires the first original to stay absent and seeds the second from the existing synthetic camera asset. `ProbeFixture` pins both input hashes. The launch token and bundle namespace are checked before reading those inputs. Writes use the app's private, exclusively created probe root. A bound descendant or leaf must keep its identity through acknowledgement. The library is initialized and the synthetic files rechecked before the receipt is written. Failed setup can leave partials in the never-reused test container. Leave them in place for inspection. A later runner must confirm the actual seeded Sessions row is ready as well as checking the receipt. This assumes the fresh simulator container is exclusively owned for the run. It is not an API for importing arbitrary media or seeding a live installation.

Run the macOS host controls from the repository root. These exercise fixture admission and descriptor custody with temporary directories, then validate the session against the shared schema.

```sh
probe=scripts/ios/replay-segment-menu
scratch=$(mktemp -d)
swiftc -warnings-as-errors -module-cache-path "$scratch/modules" \
  "$probe/ProbeCustody.swift" "$probe/ProbeCustodyTests.swift" -o "$scratch/probe-controls"
"$scratch/probe-controls" "$probe/segment-menu-fixture.json" \
  ios/Jovra/Resources/Fixtures/fixture-camera-720p30.mp4
python3 scripts/spec/validate.py --document "$probe/segment-menu-fixture.json"
```

These host controls exercise fixture custody. The generated app and native Replay have a separate verification gate below.

## Generate the isolated native probe

The generator and its UI test live outside the production project. Use a clean committed checkout, Python 3.12+ with PyYAML, XcodeGen 2.46, and a mounted, private output volume. The generator uses only tracked bytes from that commit. It writes a fresh alternate namespace, probe sources and a source manifest into a new directory. It never builds, creates a simulator or launches an app.

```sh
probe=scripts/ios/replay-segment-menu
python3 -B "$probe/test_generate.py" -v
# OUT is a new, absent absolute path under the reviewed mounted output volume.
python3 -B "$probe/generate.py" "$OUT"
(cd "$OUT/checkout" && scripts/ios/generate.sh && mkdir -p .cache/media)
selector=JovraUITests/ReplaySegmentMenuUITests/testActualMenuOpensLaterSegmentAfterTheFirstIsUnavailable
xcodebuild build-for-testing -project "$OUT/checkout/ios/Jovra.xcodeproj" -scheme Jovra \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$OUT/DerivedData" -jobs 2 JOVRA_SKIP_SAMPLE_MEDIA=YES
```

Before execution, verify the built app and runner IDs match the source manifest, the exact signed trees and standard simulator `.xctestrun` are bound to the review, and no production capabilities are present. Use only a freshly created, uniquely owned iPhone 17 Pro simulator on iOS 26.5, and verify the new UUID and alternate IDs against a pre-create baseline and app inventory. Maintain 9.5 GiB internal and 8 GiB mounted build and backing volume headroom. Keep the simulator and result paths explicit and run only the reviewed method.

```sh
# XCTESTRUN is the reviewed single-method standard manifest. SIMULATOR_ID is the fresh owned UUID.
xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "id=$SIMULATOR_ID" \
  -only-testing:"$selector" -parallel-testing-enabled NO -resultBundlePath "$OUT/Menu.xcresult"
```

Require the raw result to bind one passing test to that owned simulator. The test reaches the seeded Sessions row, then uses the real menu and requires frame 0, one semantic scroll, and frame 1. Verify the synthetic session and video bytes and first-original absence in the alternate container before removing only the owned simulator. Preserve raw failures and partials privately. The commands above rely on explicit operator review and custody checks. A guarded runner is a separate slice.
