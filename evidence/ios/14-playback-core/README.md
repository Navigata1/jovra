# T14 playback core: evidence

All runs were on 2026-11-08, on the build Mac. The simulator was JOVRA-T14 (`B7D403BE-869C-4F1D-B84F-0CBF0006402F`), an iPhone 17 Pro on iOS Simulator 27.2. No physical device was used.

| File | What it shows |
|---|---|
| `01-red-missing-api.txt` | Red run. The tests were written first, so the playback API they call did not exist yet. |
| `03-red-proxy-timescale.txt` | Red run caught by the timing gate. The first proxy decoded frame 469 as frame 468 (a timescale rounding bug), and that run is kept here with its fix. |
| `02-jovramedia-green.txt` | Green run of `swift test --package-path ios/Packages/JovraMedia --no-parallel`, after `render.py --check` passed. It includes 100 seeded seek and step targets per fixture, checked at 60 and 240 fps by reading the frame code on the displayed decoded frame. It also covers the A–B loop wraps, the proxy, and the XCTClockMetric timing. |
| `04-ui-tests.txt` | `scripts/ios/ui-test.sh` summary for `PlaybackCoreUITests` (9 tests). It also covers the regression classes `CoreComponentsUITests` (4) and `ReplayFlowUITests` (1). |
| `05-hosted-tests.txt` | Hosted `JovraTests` results. One test sends a VoiceOver accessibility increment to the jog strip and checks that the real player and the readout move exactly one frame. |
| `s10-*.jpg`, `reviews.txt` | Screenshots of the video lab in light, dark and AX5, portrait and landscape, plus the half-rate, zoom, missing-file and sample states. `reviews.txt` reviews each one against `design-reference/screens/10-smart-replay.png`. |
| `t12-*-badges.jpg` | Regression screenshots for the shared `SampleBadge`, which this ticket changed so it can take a custom caption. |

## Fixtures

The bundled frame-counter fixtures are copies of the T10 renders `frameCounter/fc-060` and `frameCounter/fc-240`. They live in `ios/Jovra/Resources/Fixtures/frame-counter-0{6,24}0fps.mp4`, and their decoded-frame signatures match the committed ground truth (`render.py --check` PASS). Every clip in the lab is synthetic.
