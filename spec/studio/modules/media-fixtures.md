---
module: media-fixtures
reference: [scripts/media/studio/render_studio.py, scripts/media/studio/reader.py, scripts/media/studio/install_demo.py]
cases: [spec/reference/studio/cases/media_fixtures_cases.py]
kinds: [jovra.studio-media-truth/1, jovra.studio-media-demo-subset/1]
coverage: covered
swift: pending
kotlin: pending
---

# Media fixtures: barcode and click sources, the coherent match, B-roll and the labelled angle renders

Frame-truth media for every Studio renderer and FilmVerifier (film-engine section 7; ADR-0012 extended). The media is
**generated at test time** by `scripts/media/studio/render_studio.py` into the git-ignored cache
`.cache/media/studio/<set>-<hash16>/`; only the ground-truth manifests are committed, one per file under
`spec/studio/fixtures/media/<set>/<clip>.json` (`jovra.studio-media-truth/1`), plus
`spec/studio/fixtures/media/demo-subset.json` (`jovra.studio-media-demo-subset/1`). The generator reuses T10's
renderer core (`scripts/media/render.py` `render_clip`: drawing, encoder settings, the signature-margin refusal and the
decoded-signature proof) and T11's scene and match play (`jovra_media.court3d`, `animation`, `sets/sample.py`); it
never copies them. `spec/reference/studio/cases/media_fixtures_cases.py` declares every manifest and checks them.

```
python3 scripts/media/studio/render_studio.py                  # render what the cache lacks, (re)write the manifests
python3 scripts/media/studio/render_studio.py --check          # verify every file; fail unless the manifests reproduce
python3 scripts/media/studio/render_studio.py --force --sha256-log run.txt   # re-encode all; list each file's SHA-256
python3 scripts/media/studio/reader.py FILE --manifest M [--picture X,Y,W,H] [--labels N]
python3 scripts/media/studio/install_demo.py                   # copy the demo subset into the app's resources
python3 -m unittest discover -s scripts/media/studio -p 'test_*.py' -v
```

A cold render of everything takes about 8 minutes on the build Mac (the 54:00 match and six 54:00 angles dominate).

## Sets

| Set | Files | What |
|---|---|---|
| `barcodeSources` | `bc-024`, `bc-030`, `bc-060` (10 s each); `bc-030-restart-seg0`/`-seg1`; `bc-030-silent` | H.264 1280x720 CFR. Every frame carries the 40-bit barcode in its bottom row (source id, segment, frame id), the frame id in block digits, a scan cell and a white flash row on click frames. AAC 48 kHz mono with eight 1 kHz clicks at seeded frames, each starting 1 ms after its frame's presentation time. The restart is one 30 fps capture in two files: segment 0 is session frames 0-149, segment 1 resumes at session frame 195 (1.5 s gap) and its barcodes keep counting on the session clock; the click scheduled at frame 170 fell in the gap and is in neither file. The silent variant has no audio track at all. |
| `match` | `match-jon-vs-alex` | The coherent synthetic match: T11's Jon vs Alex play (all 124 points of the core sample log on the full 54:00 timeline, behind the baseline) at 640x360 30 fps, with the Sample label, a 40-bit barcode strip in the bottom 20 px (source 16, frame id = frame index) and a 1 kHz click at each of the 440 hits. Its manifest carries the session's point log, the setup it folds under, each point's window in frames and the expected score. |
| `broll` | `broll-court-push`, `broll-ball-drop`, `broll-sideline-pan` | 6 s B-roll of the empty court at 640x360 30 fps, marked "Sample video (synthetic)", with the barcode strip (sources 32-34). The ball drop's six bounces (free fall, restitution 0.7) are clicks. |
| `angles` | `angle-baseline`, `angle-far-baseline`, `angle-near-left`, `angle-near-right`, `angle-far-left`, `angle-far-right` | The bundled ST27 demo: six visibly different synthetic views of the same 54:00 match timeline (frame N of every angle is the same match instant), each with the Sample label top-left and its angle name top-right. 640x360 at 12 fps, CRF 38 and a 30 s GOP so all six fit the 25 MB budget; picture only (no barcode, no audio). They are not a multi-camera simulation: no drift, restart or shake (that is S58). |

## The barcode (`jovra.frame-barcode/1`, `scripts/media/studio/jovra_studio_media/barcode.py`)

40 equal blocks across the barcode rectangle, most significant bit first: start bit 1, source id (7 bits, 1-127),
segment (3 bits), frame id (20 bits, so 54:00 at 60 fps fits), CRC-8 (polynomial 0x07, init 0) over the 30 payload
bits packed big-endian into 4 bytes, stop bit 0. White (Y' 235) is 1 and black (Y' 16) is 0. The reader averages the
central half of each block and thresholds at Y' 128; a block within 40 code values of the threshold is unreadable,
not guessed. Every single-bit error fails the CRC or a start/stop bit, so a flipped bit is reported as a mismatch and
never as another frame id. `map_rect` carries the rectangle into an output frame that shows the source scaled or
letterboxed (the 9:16 letterbox output), so FilmVerifier reads output frames with the same code.

On the barcode sources the bits are whole signature cells, so the decoded-frame signature also pins every barcode;
on the match and B-roll the strip lies below every cell's central half, so the T11 scene's signature is unchanged.

## The click (`clicks.py`)

A 10 ms burst of 1 kHz (ten cycles at 48 kHz), 0.5 ms linear attack, linear decay, peak 16000, over a +/-60 seeded
noise floor; the PCM is integer-exact and hashed (`hashes.pcmSha256`). The detector finds the first sample over half
the peak after 50 ms of quiet, places the onset on the energy envelope's half-peak rising edge (so the pre-echo an AAC
encoder spreads before a transient does not move it), and accepts it only when the 10 ms that follow are a 1 kHz
burst. Every render requires every click within +/-1 frame of its ground-truth frame and no extra click; on the build
Mac every click lands on its frame within 2 samples.

## Manifests

Everything but `hashes` is the generator's **plan**: generator script, version and source hash (SHA-256 over T10's
core files, this package and the set module, with the repository files it reads: the T11 sample manifest and points,
and the sample session); the cache path; video and audio facts; the barcode layout, frame map (runs of
`{frame, frameId, count}`) and `frameMapSha256` (each frame's source, segment and 24-bit frame id); click events
(`sample`, exact `time`, `frame` = floor(time x fps)); the labels; and the set's facts (`restart`, `match`, `broll`,
`angle`). The cases module recomputes the plan from the generator on every validator run.

`hashes` is what a render proves and every machine reproduces: `sourceFramesSha256` (every drawn frame),
`decodedSignature` (T10's `jovra.cellLuma.v1` over the decoded file) and `pcmSha256` (the click track before AAC),
with `renderedWithSourceHash`. **The media file's own SHA-256 is not committed**: x264 and the AAC encoder differ
between ffmpeg builds (T10), so it is reproducible on one machine and is printed in the run log; the two-run check
(`--force --sha256-log`) compares those lists. A context that binds real file hashes (S09) must take them from the
machine that renders.

## The bundled demo subset

`demo-subset.json` lists the media marked `bundled` (the six angles), the install folder
`ios/Jovra/Resources/StudioSampleMedia` (git-ignored) and the 25 MB budget (`budgetBytes`; the figure the lead is to
confirm). `install_demo.py` copies them from the cache with `studio-sample-media.json` beside them, fails when one is
not rendered or the subset is over budget, and prints `du -sk`. The generator also fails over budget.
The installer only deletes files it wrote: it refuses, touching nothing, a destination not named `StudioSampleMedia`,
a non-empty one without a readable index, an index naming anything but a plain `*.mp4` name, symbolic links, and any
file neither the previous index nor this install names. Only a file the previous index lists and the subset dropped
is removed.
`scripts/media/studio/check_added_binaries.py` lists every binary a branch adds and fails on any media file outside
that folder (by extension or by its leading bytes); the Studio workflow runs it on every pull request.

## What the cases module checks

- Schema (`studio-media-truth.schema.json`, `studio-media-demo-subset.schema.json`) and, independently of the
  generator: duration = frames / fps; audio samples = duration x 48 kHz; clicks present exactly with audio, ordered,
  at least 100 ms apart, inside the audio, with `time` and `frame` derived from `sample`; frame-map runs contiguous
  and covering every frame, and `frameMapSha256` re-derived from them; the Sample label on every demo file reading
  "Sample video (synthetic)"; each angle burning in exactly its name; hashes rendered from the current source.
- The coherent match's log folds through `spec/reference/jovra_ref/scoring.py` to the manifest's expected score, and
  that is 6-4 6-3 to side A (Jon), the core sample's result; point windows equal the log's times; every hit click is
  inside a point.
- The restart's two files tile the session clock around the gap and lose at least one click to it.
- The demo subset lists exactly the bundled media, the six ST27 angles in order, with the 25 MB budget.

## What is not covered yet

- Swift and Kotlin do not read these manifests yet (`swift: pending`): S09 builds the barcode-court context over this
  media, S40 (FilmVerifier) and S41/S42 (renderers) read barcodes through a Swift port of the reader, S21 plays the
  bundled angles.
- Fixtures prove pipeline logic only (film-engine section 7). VFR, rotated and HDR angles, drift, restarts and the
  other multi-camera conditions are S58's generator ([multiangle-generator](multiangle-generator.md)), built on these
  tools; its ground truth lives under `spec/studio/fixtures/media/multiangle/` with its own kinds.
- The bundled subset's install is a script; wiring it into an Xcode build phase is left to the ticket that first plays
  it (S21).
