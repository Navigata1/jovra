# JovraVision

The on-device analysis pipeline of the V track ([ADR-0031](../../../docs/adr/0031-automatic-analysis-in-v1-and-iphone-first.md),
[vision tickets](../../../docs/spec/vision-tickets.md)). V00 builds the skeleton; V02–V07 add stages.

```sh
swift test --package-path ios/Packages/JovraVision   # needs the rendered fixture-camera clip (scripts/media/render.py)
```

## Pieces

| Type | Role |
| --- | --- |
| `AnalysisStage` | One step. Reads windows of the recording through an `AnalysisWindowReader` and the finished outputs of earlier stages (`AnalysisPriorOutputs`); returns typed observations per window, or a skip with its reason. Carries state between windows in a `Codable` `State`. |
| `AnalysisWindowReader` | Frames (pulled one at a time) and mono float audio for one window. `RecordingWindowReader` reads a session's segment files with AVFoundation. |
| `AnalysisRunner` | Runs stages in order over every window. Writes each window's result and a checkpoint before reporting progress; resumes from the checkpoint after a kill or cancellation; asks an `AnalysisBudget` before every window and holds while it says pause. |
| `AnalysisStageOutput` | A finished stage: observations, coverage (analysed and skipped ranges with reasons, V-track rule 4), media identity, `model:<id>@<version>` source. Canonical JSON, so equal results are equal bytes. |
| `SessionSuggestions` | Turns point candidates into session events: `estimated`, needs review, superseding only unreviewed points (T04, spec decision 24). |
| `FixtureLumaStage`, `FixtureLumaShiftStage` | Test stages with no tennis meaning. They exercise frames, prior outputs and carried state. |

## Workspace

One folder per session (`<library>/analysis/<session id>/` in the app):

```
run.json                    resumes since the analysis last started from the beginning
<stage>.output.json         finished stage output
<stage>/checkpoint.json     unfinished stage: next window and carried state
<stage>/w-<index>.json      one finished window
```

Every file is replaced atomically, the window part before the checkpoint. A file that cannot be decoded is treated
as absent, so a stage starts again rather than resuming from a guess. A checkpoint or output whose stage version,
window length or media fingerprint differs is discarded.

## Rules for stages

- Deterministic: the same media and inputs give the same observations whether or not the run was interrupted.
- Everything carried between windows lives in `State`.
- Report coverage honestly: return `.skipped(reason)` for a window the stage cannot analyse; never fill it in.
- Let cancellation propagate; throw only on a real failure.
- A model enters the repository only with its licence, source, training-data provenance and hash in
  `spec/models/manifest.json` (V-track rule 3).
