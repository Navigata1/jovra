# T10 evidence: media fixtures and the benchmark harness

Simulator: JOVRA-T10 (iPhone 17 Pro, iOS 26.5), C8F1B001-511F-42A7-A107-05C093B0582D. Build Mac, Xcode 26.6,
ffmpeg 9.0.1 (Homebrew). This ticket adds no screen. The two app-smoke JPEGs show that the app still builds and
runs with the new JovraMedia manifest.

| File | What it shows |
|---|---|
| `render-check.txt` | `render.py --check`: 19 clips (now with the VFR import clip), 1,068,590 bytes rendered in total, decoded-frame hash check PASS |
| `determinism-two-runs.txt` | A forced re-encode of every clip into a second cache reproduces the committed ground truth and hashes, and the media bytes are identical on this machine |
| `negative-hash-check.txt` | One committed hash altered: `render.py --check` exits 1 and the Swift `DecodedFrameHashTests` fails |
| `render-cache-tamper.txt` | Round 1: the cached fc-060 replaced by a re-encode with frame 30 removed, then with frame 30 duplicated (same frame count). Plain `render.py` and `--check` both exit 1 and the committed truth is untouched (`test.sh` now runs `--check`) |
| `swift-test-jovramedia.txt` | `swift test` for JovraMedia: 63 tests (129 cases, 11 of the tests parameterized) in 13 suites pass. Round 2 adds `CapabilityBindingTests` (a perfect candidate passes the real `audio.hitDetection` registry gate; a caller-chosen tolerance, or a gated capability without a binding, is refused before estimating) and `MediaProvenanceTests` (a candidate on an unrendered clip, or on a rendered clip that is not the committed media, is refused before estimating; record clips carry the truth's renderer and decoded-frame hashes; an overflowing tolerance names itself) |
| `real-footage-probe.txt` | Round 1: `FrameTiming` unit tests, and `MediaProbe` on the private Android 13 originals (30 fps, VFR; previously 30000/749 and 90000/1847) and a CFR excerpt (30 fps, constant); with the files absent the three real-footage tests are skipped with the reason |
| `validate-attacks-r2.txt` | Round 2: a perfect candidate on the registry gate (control) passes; the same record with the task's metric names, or with a 200 ms tolerance, a record whose clip `decodedFramesSha256` is altered, and a round-1 record without the media hashes each fail `validate.py` |
| `validate-attacks.txt` | Round 1: the verifier's records (oracle naming a capability, candidate on a self-declared floor, one clip pooled 3 times, a zero timescale) placed in a scratch `spec/benchmarks/`: each one fails `validate.py`, none crashes |
| `benchmark-cli.txt` | `jovra-benchmark`: the oracle passes the floor (exit 0), the null estimator fails it (exit 3), a tuning run carries no verdict, and gating on the tuning seed is refused with no record written (exit 2). Round 1: an oracle or null run naming `audio.hitDetection`, and a run listing one clip 3 times, are refused with no record written (exit 2). Round 2: `--tolerance 9223372036854775807/1` fails with a message naming the tolerance (exit 2, no record); records regenerated with the clip media hashes |
| `validate.txt` | `scripts/spec/validate.py`: 19 ground truths, 3 benchmark records re-scored in Python, the benchmark bindings checked against the registry gates, 37 media self-tests, PASS |
| `fixture-camera-frame74.jpg` | Fixture-camera frame 74: court, ball, flash cell and frame code |
| `frame-counter-240fps-frame137.jpg` | 240 fps counter at frame 137: code bits 8, 12 and 15, the digits 0137 and scan cell 9 |
| `import-portrait-rotated-as-displayed.jpg` | The iPhone-style portrait clip with its 90-degree matrix applied: the arrow points up |
| `import-native-portrait-frame5.jpg` | The native 720x1280 portrait clip |
| `app-smoke-{light,dark}-1-home.jpg` | JovraUITests on JOVRA-T10 after the manifest change (6/6 and 2 system-appearance passes) |

Test counts on JOVRA-T10 after verifier round 2 (2026-10-07): `scripts/ios/test.sh` (`render.py --check` first: 19
clips, 1,068,590 bytes, PASS) gave JovraCore 15 tests, JovraMedia 63 tests (129 cases) in 13 suites and
JovraTests 10/10. `scripts/ios/ui-test.sh` gave system light 1/1 and system dark 1/1; its full JovraUITests pass
was 5/6 because `testEveryTabAtLargestAccessibilityTextSize` hit "Audit failed to complete in time" (an XCTest
accessibility-audit timeout), and an immediate re-run of the full suite gave 6/6. Round 2 changed no app code or
screen, so the app-smoke JPEGs were not replaced. Real-footage results are build-Mac only (CI skips them);
simulator, device and ML validation are separate and none is claimed here.

Round 1 counts, for the record: JovraMedia 52 tests (117 cases), JovraTests 10/10, JovraUITests 6/6.
