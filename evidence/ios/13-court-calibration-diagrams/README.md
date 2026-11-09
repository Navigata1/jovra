# T13 evidence: court geometry, 4-tap calibration maths and the court diagram components

Branch `ticket/t13-court-calibration-diagrams`, simulator `JOVRA-T13` (iPhone 17 Pro, iOS Simulator 27.2,
`EC62AF47-253F-497F-B735-233029F969BA`). No physical device was used.

| File | What it shows |
|---|---|
| `01-core-red-before-court-module.txt` | The calibration conformance runner failing to compile before `JovraCore/Court` existed (red) |
| `02-core-green.txt` | `swift test` for JovraCore on macOS: 9 calibration fixtures (58 vectors, 16 fits) and the Court suites green |
| `03-core-mutation-centre-line-caught.txt` | A centre service line drawn baseline to baseline fails both the layout test and the C08 geometry fixture |
| `04-benchmark-court-calibration.txt` | The `courtCalibration` benchmark record: RMSE, on-court error, per-intersection breakdown, Python re-score |
| `05-ui-tests.txt` | `CourtComponentsUITests` on JOVRA-T13: 5 passed (accessibility audit in light, dark and AX5) |
| `t13-{light,dark,ax5}-{diagrams,markers,guide}.jpg` | Gallery screenshots; `diagrams-2/-3` scroll to the legend, service-box and half-court variants |
| `t13-light-markers-read-aloud.jpg` | The five marker shapes and the placement words VoiceOver reads |
| `t13-light-guide-dragged-poor.jpg`, `t13-dark-guide-poor.jpg`, `t13-light-guide-loupe.jpg` | The framing guide after a bracket is dragged off (poor fit), a far corner 11 px off, and the 2x loupe |

All gallery data is synthetic and badged Sample. The framing guide's background is a vector drawing of the
renderer's behind-baseline camera at 1080p (the synthetic calibrated frame of `spec/fixtures/calibration`), not footage.

## The 0.10 m acceptance claim (measured, not met as written)

With the four doubles corners tapped up to 2 px off at 1080p, untapped intersections on the near half and at the
net side of the far service line stay within 0.06 m, but points on the far baseline reach 0.17 m: on this camera one
pixel spans about 0.10 m of depth at the far baseline (`spec/fixtures/calibration/C03-jittered-corners.json`: 5 of its 6 seeded
draws put at least one far point beyond 0.10 m; the benchmark's 32 draws give 92.19% of untapped intersections within 0.10 m, RMSE 51 mm). The fixture
and the record state this per point; nothing hides it.
