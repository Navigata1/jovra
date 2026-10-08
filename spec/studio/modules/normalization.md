---
module: normalization
reference: [spec/reference/studio/normalization.py]
cases: [spec/reference/studio/cases/normalization_cases.py]
kinds: [jovra.pts-table/1, normalization]
coverage: covered
swift: pending
kotlin: pending
---

# Normalization: the PTS table from original PTS to render-proxy frames

`spec/reference/studio/normalization.py` derives a render proxy's **PTS table** from the original's decoded
presentation timestamps and checks a stored one. `spec/reference/studio/cases/normalization_cases.py` writes the
`normalization` vectors, the Sample table `records/pts-table.sample-corner.json` and its invalid cases, and registers
two self-tests. `python3 scripts/spec/validate_studio.py --list` prints the current case count of every kind below and
its Swift and Kotlin status.

| Schema | Record | What the reference adds beyond the schema |
|---|---|---|
| `pts-table` | The original's PTS index (run-length, rational timescale, `endPts`, frame count, coded size, rotation, HDR flag and transfer); the proxy clock (rate, track timescale, frame duration, zero start, frame count), geometry (rotation applied, display rotation 0), colour (8-bit BT.709, tone map) and `upconverted`; the run-length proxy-frame → original-frame map | **Rebuilds the whole map** from the PTS index with the half-up rule and requires identical runs and frame count; track timescale `lcm(fps.num, 1000)`; rotation applied exactly once with the display orientation and aspect; tone map declared exactly for HDR; `upconverted` exactly when the proxy rate is above the nominal rate; canonical run forms (so equal tables hash equal) |

The table's canonical SHA-256 (`normalization.table_sha256`, RFC 8785 for float-free JSON) is the value a
SourceManifest render proxy binds as `ptsTableSha256`.

### The one rule (`normalization.py`)

All arithmetic is exact (integers and `Fraction`), with the shared half-up rounding (`core.round_half_up`, the time
analogue of ADR-0011). For original frame *i* (presentation order, which is what an embedded frame ID counts) with
timestamp `pts_i` on timescale *T*, a proxy at rate *fps* and an original ending at `endPts`:

- `tick_i = ⌊(pts_i − pts_0) · fps / T + ½⌋`: the proxy frame of every original PTS. This is the mapping analysis and
  sync use (`original_to_proxy`, `proxy_frame_of`); a tick at or past the frame count lies outside the proxy.
- Proxy frame *k* shows the **last original frame whose tick is ≤ k**, for `0 ≤ k < N`, with
  `N = ⌊(endPts − pts_0) · fps / T + ½⌋`. Proxy frame 0 is always original frame 0 (zero start).
- This is the selection observed against FFmpeg with embedded frame IDs (multicam-sync research §5.2: 184/184 slots at
  30 fps, 368/368 at 60 and 153/153 at 25), not "the nearest frame" (137/184). At 120 → 30 it shows frame 4k + 1, a
  quarter of an output frame after the instant; analysis and sync still use the original PTS.
- Ties go up. Half-even (Python's `round`) or half-down selects other frames at every tie, and the conformance check
  refuses it (`frameSelectionMismatch`). Ties are common: every odd frame at 60 → 30, every other frame at 24 → 30,
  frame 500 of a 29.97 fps angle in a 30 fps film, any VFR timestamp that lands exactly between two slots.

Proxy clock and picture:

- **Track timescale** `lcm(fps.num, 1000)`: 3000 for 24, 30, 60 and 120 fps; 30000 for 30000/1001; 1000 for 25.
  Proxy frame *k* has PTS `k · frameDurationTicks`, with `frameDurationTicks = timescale · den / num` (an integer by
  construction), starting at 0.
- **Rotation** is baked into the pixels exactly once (`rotationAppliedDegrees` equals the original's
  `rotationDegrees`) and none is left in the container (`displayRotationDegrees` is the constant 0, a schema rule:
  players would apply a kept rotation a second time). The proxy has the display orientation, so a quarter turn
  swaps width and height. Its size is the display size scaled to the target long edge, the short edge rounded
  half-up to an even number; a different aspect is a framing operation in the edit plan, never an implicit crop or pad.
- **Colour:** the proxy is 8-bit BT.709 (schema constants). An HDR original (HLG or PQ only, `colourMismatch`)
  declares its tone map `{method, params, version}` (`toneMapUndeclared` when missing); an SDR original has none
  (`toneMapOnSdr`). Methods: `ffmpeg-zscale-tonemap`, `ffmpeg-libplacebo`, `avfoundation-videotoolbox`,
  `media3-opengl`.
- **Upconversion** (a proxy rate above the original's nominal rate duplicates frames) is labelled: `upconverted` is
  true exactly then (`unlabelledUpconversion`), so the angle can show its source rate.

Run-length forms (canonical greedy: a run takes the difference of its first two values as its step and extends while
that difference holds; a final single value has step 0):

- `original.pts`: `{value, step, count}`, the frames `value, value + step, …`. Timestamps strictly increase in
  presentation order and the runs count `frameCount` frames (`badPtsIndex`).
- `runs`: `{proxyFrame, count, originalFrame, originalStep, originalPts}`. Proxy frames `proxyFrame + j` show original
  frame `originalFrame + j · originalStep` (step 0 holds a frame, for example across a dropped-frame burst);
  `originalPts` is the timestamp of `originalFrame`. A 60 → 30 proxy is one run of step 2; a 29.97 angle in a 30 fps
  film is two runs.

### Embedded-ID conformance (multicam-sync §8.2)

`check_conformance(original, fps, emitted, decoded)` is the platform test: a normalizer's emitted table must match the
frame IDs decoded from its proxy 100% (`ptsTableMismatch`, naming the proxy frame), and those IDs must be the half-up
selection (`frameSelectionMismatch`, naming the proxy frame, the expected and the found original frame). A Swift or
Kotlin port builds each vector's synthetic coded clip from its explicit PTS list (the frame index in luma, low part
left and high part right, limited range, read back from the Y plane without range conversion), normalizes it with its
real pipeline, decodes the IDs and calls the same check.

## Vectors

`vectors/normalization.json`, one kind, four modes. Every case's `assert` block is hand-derived on paper and checked
against the stored table directly, never through the reference.

- **derive** (22): input = a source description with every PTS explicit; expect = the PTS table, its SHA-256 and
  `proxyFrameOfOriginal` (the tick of every original frame). CFR 30 → 30, 60 → 30, 120 → 30, 24 → 30, 25 → 30,
  30 → 60 (upconverted); mixed rates 29.97 in a 30 fps film (slot 500 holds frame 499) and 30 in a 29.97 film (frame
  500 dropped, track timescale 30000); 29.97 identity; a 25 fps project (track timescale 1000); VFR jitter under half a
  frame; a dropped-frame burst (six frames, 200 ms) at 600 and an eight-frame burst at a 90 kHz timescale; a VFR tie;
  a stall with a catch-up burst; a non-zero first PTS; S12 (VFR + rotation 90 + HLG, also the Sample record);
  rotation 270 and 180; PQ HDR; 4:3; and an even-rounding aspect (1366 × 768 → 1920 × 1080).
- **mutation** (6): a normalizer following another rule, as emitted table plus decoded IDs, which the conformance
  check must refuse. S4 (multicam-sync §8.3, case 4) three times with half-even ties: the 29.97/30 case
  (`frameSelectionMismatch` at proxy frame 500, expected 499, found 500), 60 → 30 (frame 0: 0 vs 1) and the VFR tie
  (frame 10: 9 vs 10); half-down at 24 → 30 (frame 2: 1 vs 2); nearest-frame at 120 → 30 (frame 0: 1 vs 0); and a
  proxy with the right frames but a half-even table (`ptsTableMismatch`).
- **reject** (6): source descriptions the reference refuses: HDR without a tone map, SDR with one, timestamps out of
  order, HDR with a BT.709 transfer, `endPts` before the last frame, an odd long edge.
- **check** (3): emitted tables that pass the schema and that the record rule refuses: a quarter turn left landscape
  (`proxyRotation`), a 600 track timescale (`badTimescale`) and an unlabelled 30 → 60 (`unlabelledUpconversion`).

## Invalid cases

On `records/pts-table.sample-corner.json` (S12): rotation not swapped, rotation not applied, an HDR tone map omitted,
an SDR original tone-mapped, a 600 track timescale, half-even runs forged into the table, a frame count off by one, a
non-canonical PTS index, a wrong original frame count, `endPts` at the last frame, an unlabelled upconversion and an
odd short edge (reference layer); and at the schema layer, display rotation kept (applied twice), an unknown tone-map
method, an HDR transfer on the proxy, a non-zero proxy start and a float frame rate.

Self-tests (registered in `normalization_cases.py`):

- `normalization-tie-coverage`: at least five derive vectors select differently under half-even, so a port that
  rounds like Python's `round` fails them, and every half-even mutation vector really contains a tie.
- `normalization-pts-queries`: on the Sample record every original PTS maps to its tick, a PTS exactly half a frame
  in maps up to proxy frame 1, and a PTS before the first frame is refused (`badPtsIndex`).

## Decisions

- One vector kind with four modes, rather than one kind per mode: a platform consumes one file.
- The original → proxy direction is stored as a plain list per original frame, not run-length (its tick sequence is
  stair-shaped, so the greedy form would not be shorter).
- The table carries the whole original PTS index, so the map is checked rather than trusted (the reference rebuilds
  it); an hour of VFR video costs one run per irregular step.
- Proxy dimensions keep the display aspect; the target long edge is the normalizer's input, not part of the table.

## Not covered yet

- **Binding to the Sample manifest:** the Sample SourceManifest's `ptsTableSha256` values are still stand-in hashes of
  hour-long fictional sources. Binding them to real table hashes (and a cross-record check that a render proxy's
  `fps`, size, frame count, `rotationApplied` and `toneMapped` agree with its table) is a later step.
- **Same tone map across a film:** every angle of one film should use the same method and parameters (research
  §5.4); no cross-table check exists yet.
- **Audio:** 48 kHz resampling, zero start and missing-audio state (research §5.6) are not part of the table.
- **Real pipelines:** no FFmpeg, AVFoundation or Media3 normalizer has been run against these vectors; the observed
  FFmpeg rule comes from the research's scratch run (FFmpeg 9.0.1). Swift and Kotlin status is `pending`.
- **Slow motion:** 120/240 fps practice clips played as slow motion are a replay operation, not a proxy rate.

## Sources

Repository material (OBSERVED, read 2026-10-08):
- `docs/research/studio/multicam-sync.md` §5 (normalization), §6.1–6.2 (the editor's preconditions: track timescale,
  zero start, no rotation side data, half-even `round` in the editor) and §8.2–8.3 (embedded-ID fixtures, S4, S12).
- `design-reference/studio/brief/backend-media-design.md` (normalize VFR, rotation and HDR with an explicit original-PTS
  ↔ proxy-frame mapping; keep original hashes).
- `GLOSSARY.md` (Proxy, Render proxy, PTS table); ADR-0011 (half-up rounding).
