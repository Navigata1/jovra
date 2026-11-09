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

A later slice must add the generator and focused UI test together, then run the generated app from a clean checkout. These host controls do not exercise the SwiftUI entry or native Replay.
