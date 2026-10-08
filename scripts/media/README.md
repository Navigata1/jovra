# Media fixtures and the benchmark harness

`scripts/media/render.py` renders the small media that playback, capture, import and the benchmark harness
need, deterministically, from code. Only the ground truth and the expected decoded-frame hashes are
committed (`spec/fixtures/media/<set>/*.truth.json`). The media goes to the git-ignored cache
`.cache/media/<set>-<hash16>/`, keyed by the SHA-256 of the renderer core plus that set's module, so editing
one set re-renders only that set.

```sh
python3 scripts/media/render.py            # render missing clips, (re)write the ground truth
python3 scripts/media/render.py --check    # CI and test.sh: fail unless every committed truth file is reproduced exactly
python3 scripts/media/render.py --force    # re-encode everything, even what the cache has
```

It needs ffmpeg with libx264, libx265 and ffv1 (`brew install ffmpeg`, `apt-get install ffmpeg`) and
Python 3.10+ standard library only. A full render takes about 15 s and about 1 MB of disk.

## Sets

| Set | Clips | For |
|---|---|---|
| `frameCounter` | H.264 640x360, 2 s at 24, 30, 60, 120 and 240 fps. Frame N shows the 16-bit code N, four block digits and a scan cell | frame-accurate playback, seek and step (T14) |
| `fixtureCamera` | H.264 1280x720 30 fps, 12 s, AAC 48 kHz mono. Court with exact corners, a ball turning at each hit, hit clicks with a flash cell, frame code | the Simulator fixture camera (D9, ADR-0012; T15, T17) |
| `import` | HEVC and H.264; 24, 29.97, 30, 60 and 240 fps; variable frame rate (nominal 30 fps at timescale 30000 with a 749-tick frame, like the Android originals); HLG HDR (HEVC Main 10, BT.2020); iPhone-style portrait (90-degree track matrix) and native portrait pixels; FFV1 in QuickTime (unsupported); a byte-identical duplicate pair | import (T26), media library probe (T08) |
| `harness` | the court scene from seed 11 (tuning) and seed 23 (held out), 10 s each, hit clicks with exact onsets | the benchmark harness self-test |

T11 adds its sample, practice and benchmark-corpus scenes as new modules in `jovra_media/sets/` (discovered by
convention, so no shared list changes).

## The decoded-frame hash (`jovra.cellLuma.v1`)

Encoders are not byte-reproducible across machines (x264 on the Mac and on Ubuntu differ), but H.264 and HEVC
decoding is bit-exact. So the committed hash is over a coarse per-frame signature that every conformant encode
of the same source keeps: the coded picture is split into a grid of cells (16 x 9 for landscape), each
cell's central half is averaged and quantized to `mean8 // 64`, and the clip hash is the SHA-256 of every
frame's cell levels in presentation order.

Fixtures are drawn as flat cells (court lines and the ball ride cell boundaries, outside every cell's central
half), and the renderer refuses any source frame whose cell means sit within 12 code values of a quantization
boundary. After encoding it decodes the clip and refuses the encode unless every decoded frame's signature
equals its source signature. The same signature is computed in Swift from AVFoundation's decode
(`JovraBenchmark.FrameSignature`): `DecodedFrameHashTests` proves AVFoundation and ffmpeg see identical frames
for every supported clip, and CI proves an Ubuntu render reproduces the hashes committed from a Mac render.

### The cache is checked, not trusted

`scripts/ios/test.sh` runs `render.py --check`, which never writes ground truth, so the Swift tests compare
AVFoundation against the committed hashes. The plain mode (which does write truth) refuses to rewrite a
committed hash from a cached clip when the renderer source is unchanged: a cached clip that no longer decodes to
its committed hash (or to its frame count) means the clip or the committed truth was altered, and the run fails
with the clip named (re-render it with `--force` to tell which). A clip that fails keeps its committed truth file. For a variable-frame-rate clip the renderer also
reads the encoded presentation times back and fails unless they are exactly the clip's schedule.

## Ground truth

`spec/schemas/ground-truth.schema.json`. Each file records the encoded facts a probe must report (codec,
four-cc, bit depth, coded and display size, rotation, orientation, exact frame rate, frame count, duration,
HDR transfer, whether the apps can decode it, and `variableFrameRate`), the audio track, the frame code, the signature, and any events
(hit onsets as exact 48 kHz sample indices, with the video frame on screen). `scripts/spec/validate.py`
checks each file's internal consistency.

`frameRate` is the nominal rate, never 1 / the shortest frame. `JovraMedia.MediaProbe` (for import, T26, and the
library, T08) reads every frame's presentation time from the sample table and reports the median frame
duration's rate, snapped to a standard camera rate when within a tick, plus `isVariableFrameRate`
(`FrameTiming`). The Android 13 originals in `docs/fixtures/real-footage.md` probe as 30 fps VFR;
`RealFootageProbeTests` checks that on the build Mac and is skipped where the files are absent.

## Benchmark harness (`ios/Packages/JovraMedia/Sources/JovraBenchmark`)

`BenchmarkHarness.run(estimator, task:, clipIDs:, mode:, floor:)` loads the ground truth, runs a
`BenchmarkEstimator` on each clip, scores the outputs with a `BenchmarkTask` and returns a
`BenchmarkRecord` (`spec/schemas/benchmark-record.schema.json`) with the estimator's method version.

- **Seeds never mix.** A `gate` run accepts held-out clips only and refuses a tuning seed before the
  estimator runs; a `tuning` run accepts tuning clips only and carries no verdict. Clips without a split
  cannot be benchmarked.
- **Each clip counts once.** A clip listed twice is refused (`duplicateClips`) before the estimator runs, so
  denominators are never inflated.
- **Floors.** A gate run applies its floor to the exact metric values; an undefined metric (0/0) fails.
- **Only a candidate backs a capability (ADR-0004).** A run that names a capability (`--capability ID`) must
  come from a `candidate` estimator, and its floor is that capability's gate in
  `spec/contracts/capability-registry.v1.json` (the CLI uses it when `--floor` is omitted; any other floor is
  refused). Oracle and null runs never name a capability: the harness refuses, the schema forbids it and
  `validate.py` re-checks the floor against the registry.
- **Malformed JSON fails, never traps.** A zero timescale, frame rate or fraction denominator, or a threshold
  that is not a plain decimal, is a decoding error in Swift and a reported failure in `validate.py`.
- **Self-test.** The oracle estimator (returns the truth) passes the floor and the null estimator (returns
  nothing) fails it. Their records are committed in `spec/fixtures/media/benchmark/`, and
  `CommittedRecordTests` re-runs them.
- **Two implementations.** `scripts/spec/validate.py` re-scores every committed record in Python
  (`spec/reference/jovra_ref/benchmark.py`) and requires the same metrics and verdict.

Write a record from the command line:

```sh
swift run --package-path ios/Packages/JovraMedia jovra-benchmark run \
  --estimator oracle.eventTimes --clip harness/events-s23 --mode gate --floor harnessSelfTest \
  --out spec/fixtures/media/benchmark/oracle.gate.json
```

Exit status 0 means written (a tuning run, or a gate that passed), 3 means written but the gate failed, and
2 means refused or invalid, with no record written. An analysis ticket adds its estimator as one entry in
`EstimatorRegistry.all` and, for a new kind of output, a `BenchmarkTask` with a Python scorer of the same id.

Records here are synthetic-band harness self-tests. They promote nothing (ADR-0004): no capability's
`lastBenchmark` may point at an oracle or null record.
