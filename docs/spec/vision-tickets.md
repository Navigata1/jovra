# JOVRA analysis engine — the V ticket track

Authority: [ADR-0031](../adr/0031-automatic-analysis-in-v1-and-iphone-first.md). Sizing evidence:
[analysis spike 1](../research/vision-spike-2026-11-09.md). Feasibility and gate numbers:
[technical-feasibility.md](../research/technical-feasibility.md) §0 and §5–§12.

The V track adds automatic analysis to v1. Parent issue: [#525](https://github.com/Navigata1/jovra/issues/525). It reuses what the T track already defines instead of inventing a second
path:

- Analysis runs as the **analyze stage of `ProcessingQueue`** (T27). It never blocks recording, saving or replay.
- Every output is an **event with `estimated` provenance**, a `source` of `model:<capability>@<version>` and review
  state `needsReview`. Corrections are stored separately and win (ADR-0003, T04 decision 24).
- A capability's registry status moves from `disabled` to `estimated` **only in the pull request that also checks in
  a passing benchmark record** (the T34 rule).
- The founder's recordings are measured locally. Label files and aggregate metrics may be committed; imagery may not.

## Rules for every V ticket

1. One vertical slice per pull request, at most two pull requests stacked.
2. Evidence goes in the pull request that changes the code. Simulator, physical iPhone, and benchmark results are
   reported separately and never merged into one "passed".
3. A model enters the repository only with its licence, source, training-data provenance and hash recorded in
   `spec/models/manifest.json`. No weights with a non-commercial or unknown licence.
4. Analysis reports **coverage**: what share of the recording each stage could analyse, and why not for the rest.
   It never fills gaps with guesses.

## Tickets

| ID | Title | Blocked by | Gate to turn the capability on |
| --- | --- | --- | --- |
| V00 ([#526](https://github.com/Navigata1/jovra/issues/526)) | `JovraVision` package and the analysis pipeline skeleton | T27 | — |
| V01 ([#527](https://github.com/Navigata1/jovra/issues/527)) | Benchmark kit: label format, local labelling tool and scorer | — | — (the founder's label set gates V02–V07) |
| V02 ([#528](https://github.com/Navigata1/jovra/issues/528)) | Automatic court calibration | V00, V01, T13 | Line RMSE ≤ 3 px; near-half ground error ≤ 0.10 m |
| V03 ([#529](https://github.com/Navigata1/jovra/issues/529)) | Player tracking and pose, near and far | V00, V01 | Near player held ≥ 95% of in-play frames; far player box ≥ 90% |
| V04 ([#530](https://github.com/Navigata1/jovra/issues/530)) | Ball detection | V00, V01, V02 | Per-shot recall ≥ 0.9 near half, ≥ 0.7 far half; ≤ 5% identity swaps |
| V05 ([#531](https://github.com/Navigata1/jovra/issues/531)) | Shot, rally and point detection | T34, V03, V04 | Hit precision ≥ 0.95, recall ≥ 0.90; boundary F1 ≥ 0.90 at ±1 s |
| V06 ([#532](https://github.com/Navigata1/jovra/issues/532)) | Stroke type | V03, V05 | Accuracy ≥ 0.90 on the near player, ≥ 300 strokes per class |
| V07 ([#533](https://github.com/Navigata1/jovra/issues/533)) | Bounce placement and serve speed range | V02, V04, V05 | Median ≤ 0.3 m near half, ≤ 0.8 m far half; speed within ±10% on 90% of serves |
| V08 ([#534](https://github.com/Navigata1/jovra/issues/534)) | Analysis in the product: processing screen, suggestions in review, coverage report | V00, T28, T30 | — |

### V00 · `JovraVision` package and the pipeline skeleton

A new Swift package beside `JovraMedia`. It defines `AnalysisStage` (input: a frame/audio window reader and prior stage
outputs; output: typed observations), a runner that registers with `ProcessingQueue` as the analyze stage, resumable
checkpoints per stage, cancellation, and a device budget hook (pause on critical heat or low battery).

Acceptance:
- A fixture stage runs over the synthetic sample video in the simulator, checkpoints, is killed mid-run, resumes, and
  produces byte-identical observations to an uninterrupted run.
- Recording and replay stay usable while analysis runs (UI test).
- Observations convert to session events with `estimated` provenance and a `model:` source; a reviewed point is never
  overwritten (unit test against the T04 rule).

### V01 · Benchmark kit

A label format (`spec/benchmarks/labels.schema.json`): per recording hash, hits (media time, player near/far, stroke
type), bounces (media time, image point, in-play flag), rally boundaries, and court corners per camera position. A small
macOS labelling tool that plays a local file frame by frame and writes labels with keyboard shortcuts. A scorer that
takes labels and stage observations and prints precision, recall, timing error and placement error, split into tuning
and held-out windows fixed by hash.

Acceptance:
- The scorer reproduces hand-computed metrics on a synthetic fixture (unit test).
- The labelling tool is usable by the founder without help: open a local file, step frames, mark a hit, bounce,
  stroke type or court corner with one key each, undo, save. A UI test covers it with the synthetic sample video.
- **Founder step, not an agent step:** labels for the three founder recordings (target: at least 300 hits and 150
  bounces on the match recording, at least 100 strokes on the side-view recording). An agent must not view frames of
  these recordings, because that would send them to a model API (`docs/fixtures/real-footage.md`). V01 can merge
  before the labels exist; the label set is tracked as `founder-pending` and gates V02–V07, not V01.
- The tool can pre-fill hit candidates from audio onsets so the founder confirms or rejects instead of searching.
- Held-out windows are disjoint from tuning windows and the split is recorded with the label file's hash.

### V02 · Automatic court calibration

Detect court-line keypoints in a still frame, fit the homography to the T13 court model, and offer it as the
calibration suggestion with a reprojection overlay. Manual four-tap stays as the fallback and as the correction.

Acceptance:
- Gate numbers above on held-out labelled frames, plus the synthetic calibration set.
- A wrong or low-confidence fit is refused with a reason ("corners not visible") and never applied silently.
- Camera-moved detection (T35) re-triggers the fit.

### V03 · Player tracking and pose

Near player: built-in body pose (spike 1 holds a body in 89% of frames). Far player: a small-person detector at native
resolution on a court-aware crop, tracked across frames; pose on the far player only if the benchmark supports it.

Acceptance:
- Gate numbers above. Both-wrist confidence is reported, because spike 1 measured it under 50% from behind.
- Players on neighbouring courts are rejected using the V02 court region.
- Runs at least at real time on the iPhone 15 Pro Max (device measurement, reported separately).

### V04 · Ball detection

A heatmap ball detector (three stacked frames in, heatmap out) converted to Core ML, with a short physics-based tracker
to link detections and reject outliers. It runs only inside windows around audio hits to bound compute. Training code
and data provenance are in the repository; weights follow rule 3.

Acceptance:
- Gate numbers above on held-out labels, reported separately for near and far half and for 30 and 60 fps sources.
- Recordings below the capture guidance report reduced coverage instead of low-quality tracks.
- Device throughput and heat on the iPhone are measured and reported.

### V05 · Shot, rally and point detection

Fuse audio onsets (T34), ball direction change (V04) and near-player arm speed (V03) into hits; group hits into rallies
with the T32 segmenter; emit `PointCandidate` events.

Acceptance:
- Gate numbers above on held-out labels of the match recording.
- Neighbouring-court hits are excluded (labelled negatives in the benchmark).
- The founder can score the labelled match excerpt by accepting or correcting suggestions in fewer taps than manual
  entry (measured, reported).

### V06 · Stroke type

A small temporal classifier over pose windows around each hit: forehand, backhand, serve, volley, other.

Acceptance: gate numbers above; a confusion matrix in the benchmark record; left-handed players are a setting and are
tested by mirroring.

### V07 · Bounce placement and serve speed

Bounce points from the ball track, projected through the V02 homography to court coordinates. Serve speed from the
first flight segment, always shown as a range with the method named.

Acceptance: gate numbers above; far-half placement shows its larger uncertainty; no line call or in/out verdict is ever
rendered.

### V08 · Analysis in the product

The Processing screen shows each stage, its progress and its coverage. Fast Review (T30) and Smart Replay (T28) show
suggestions with the Estimated badge and one-tap accept or correct. A per-session analysis report states what was
analysed, what was skipped and why.

Acceptance: CoreFlow extended to record → analyse → review suggestions → export on the simulator with the synthetic
video, then the same flow as a signed run on the iPhone with a real recording.

## Order of work

V01 and V00 start now and in parallel with the Phase 1 iPhone screens. V02 and V03 follow, then V04, which is the
longest and riskiest item. T34 (audio hits) is already specified and gives V05 its first signal before V04 lands.
