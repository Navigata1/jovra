# T10 evidence: media fixtures and the benchmark harness

Simulator: JOVRA-T10 (iPhone 17 Pro, iOS 26.5), C8F1B001-511F-42A7-A107-05C093B0582D. Build Mac, Xcode 26.6,
ffmpeg 9.0.1 (Homebrew). This ticket adds no screen. The two app-smoke JPEGs show that the app still builds and
runs with the new JovraMedia manifest.

| File | What it shows |
|---|---|
| `render-check.txt` | `render.py --check`: 18 clips, 1,034,778 bytes rendered in total, decoded-frame hash check PASS |
| `determinism-two-runs.txt` | A forced re-encode of every clip into a second cache reproduces the committed ground truth and hashes, and the media bytes are identical on this machine |
| `negative-hash-check.txt` | One committed hash altered: `render.py --check` exits 1 and the Swift `DecodedFrameHashTests` fails |
| `swift-test-jovramedia.txt` | `swift test` for JovraMedia: 30 tests (63 parameterized cases) in 7 suites pass |
| `benchmark-cli.txt` | `jovra-benchmark`: the oracle passes the floor (exit 0), the null estimator fails it (exit 3), a tuning run carries no verdict, and gating on the tuning seed is refused with no record written (exit 2) |
| `validate.txt` | `scripts/spec/validate.py`: 18 ground truths, 3 benchmark records re-scored in Python, 12 media self-tests, PASS |
| `fixture-camera-frame74.jpg` | Fixture-camera frame 74: court, ball, flash cell and frame code |
| `frame-counter-240fps-frame137.jpg` | 240 fps counter at frame 137: code bits 8, 12 and 15, the digits 0137 and scan cell 9 |
| `import-portrait-rotated-as-displayed.jpg` | The iPhone-style portrait clip with its 90-degree matrix applied: the arrow points up |
| `import-native-portrait-frame5.jpg` | The native 720x1280 portrait clip |
| `app-smoke-{light,dark}-1-home.jpg` | JovraUITests on JOVRA-T10 after the manifest change (6/6 and 2 system-appearance passes) |

Test counts on JOVRA-T10: `scripts/ios/test.sh` gave JovraCore 15 tests, JovraMedia 30 tests and JovraTests
10/10. `scripts/ios/ui-test.sh` gave JovraUITests 6/6, plus system light 1/1 and system dark 1/1.
