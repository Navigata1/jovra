# T13 evidence: court geometry, 4-tap calibration maths and the court diagram components

Branch `ticket/t13-court-calibration-diagrams`, simulator `JOVRA-T13` (iPhone 17 Pro, iOS Simulator 27.2,
`EC62AF47-253F-497F-B735-233029F969BA`). No physical device was used. The files were refreshed on 2026-11-09 after
merging `origin/main` at `1d41080`.

| File | What it shows |
|---|---|
| `01-core-red-before-court-module.txt` | The calibration conformance runner failing to compile before `JovraCore/Court` existed (red) |
| `02-core-green.txt` | `swift test` for JovraCore on macOS: 9 calibration fixtures (65 vectors, 16 fits) and the Court suites green |
| `03-core-mutation-centre-line-caught.txt` | A centre service line drawn baseline to baseline fails both the layout test and the C08 geometry fixture |
| `04-benchmark-court-calibration.txt` | Both `courtCalibration` benchmark records: error by court half, per-intersection table, metres per pixel, Python re-score |
| `05-ui-tests.txt` | `CourtComponentsUITests` on JOVRA-T13 (accessibility audit in light, dark and AX5), `LoupePlacementTests` and the whole `JovraTests` target |
| `06-core-reopen-mutation-caught.txt` | Ignoring a reopened record's stored status fails both the C05 fixture and `CourtCalibrationTests` |
| `t13-{light,dark,ax5}-{diagrams,markers,guide}.jpg` | Gallery screenshots; `diagrams-2/-3` scroll to the legend, service-box and half-court variants |
| `t13-light-markers-read-aloud.jpg` | The five marker shapes and the placement words VoiceOver reads |
| `t13-light-guide-dragged-poor.jpg`, `t13-dark-guide-poor.jpg`, `t13-light-guide-loupe.jpg` | The framing guide after a bracket is dragged off (poor fit), a far corner 11 px off, and the 2x loupe kept inside the frame |

All gallery data is synthetic and badged Sample. The framing guide's background is a vector drawing of the
renderer's behind-baseline camera at 1080p (the synthetic calibrated frame of `spec/fixtures/calibration`), not footage.

## The 0.10 m acceptance criterion: not met as written

The criterion reads "projecting the untapped line intersections with corners jittered by up to 2 px lands within
0.10 m of truth on court". Measured over 32 seeded draws on the two held-out serve clips
(`spec/benchmarks/court-calibration/`):

| Untapped intersections | Within 0.10 m | Median | Worst |
|---|---|---|---|
| Near half (6 points) | 192 of 192 | 0.019 m | 0.058 m |
| Far half (6 points) | 162 of 192 (84.38%) | 0.048 m | 0.173 m |
| All 12 | 354 of 384 (92.19%) | | 0.173 m |

On this camera one pixel spans 0.018 m of depth at the near baseline and 0.102 m at the far baseline. A far corner
tapped 2 px off is itself 0.20 m off on court, so no fit of four taps can keep the untapped far-baseline points
within 0.10 m; the taps would have to be within about 1 px. The six draws of
`spec/fixtures/calibration/C03-jittered-corners.json` show the same per point (`errorM`, `withinTenCm`).

The research gate the criterion paraphrases (`docs/research/technical-feasibility.md` section 8, and row 8 of its
summary table) bounds the near half at 0.10 m and has the far half reported separately. That shape passes on the
synthetic frame and is recorded as `fourTap.nearHalf.gate.json`. It is a synthetic-frame result, not the 20-court gate.
The ticket's literal claim is recorded as failing in `fourTap.gate.json`. Neither record names a capability.
