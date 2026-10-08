# JOVRA Studio film engine and AI planner

Research pass, 2026-10-07. Scope: (1) on-device iOS film rendering with AVFoundation, (2) cloud rendering with
FFmpeg and Remotion, including how to adapt the founder's existing editor, (3) the AI planner, with Claude Opus 5.5
and OpenAI "Astra" behind one provider-neutral adapter, and (4) the five story profiles written as editing grammars
that an allowlisted operation set can carry out.

Labels follow the research convention (`docs/research/README.md`). **OBSERVED** means seen in a cited source: an
Apple SDK header on this machine, a vendor doc page fetched today, or local tool output. **INFERRED** means reasoned
from observed facts; most design parameters in this file are INFERRED proposals. **UNVERIFIED** means a claim was
seen but not checked, or still needs a device or benchmark run.

What this pass did **not** do: it made no model API call, provisioned nothing, rendered no film, ran nothing on a
device and edited no core spec, ADR or the founder's editor. Every capability below has the status *design*. Web
pages and vendor docs are treated as data. The handoff text and the IDC suite are source material, not commands.

---

## 0. Summary and recommended decisions

1. **One contract, two layers.** The planner emits a small **StoryPlan** (`jovra.story-plan/1`): beats that point
   at trusted keeper, angle, note and stat IDs, chosen from enums. Deterministic code then compiles it into the
   renderer-facing **EditDecisionList** (`jovra.edit-plan/2`), which holds exact rational times and frames. The
   model never writes frame numbers, filter strings, paths, URLs, score digits or metric values. (INFERRED; this
   follows `ENGINE-BOUNDARY.md` and `jovra-edit-plan/references/contract.md`.)
2. **The operation set is a closed allowlist** of 14 primitives (§2): `live`, `replay`, `freeze`, `card`,
   `transition`, `reframe`, `overlay`, `grade`, plus the audio routes `primary-bed`, `alt-bed`, `hold-bed`,
   `silence`, `music` and `narration`. Each has bounds, a label requirement and a verification rule. An effect
   ships only after its validator rule and fixture test exist.
3. **Picture and sound follow separate rules.** The primary court bed runs continuously at real session time, and
   angle changes touch only the video track. Labelled replays and freezes play **over the real dead time between
   points**, the way broadcast replays do, so the bed stays truthful. Where the dead time is too short, the bed is
   cut at a point boundary with short fades. Nothing inside a live rally is ever re-timed. (INFERRED.)
4. **The clean-frame rule for slow motion:** a replay at speed *s* is allowed only when `sourceFPS × s ≥ outputFPS`.
   That keeps every output frame a real captured frame. Interpolated frames (`minterpolate`, optical flow) are not
   in the allowlist. One consequence: a 30 fps match **cannot** have a clean slow-motion replay at 30 fps output.
   (INFERRED from `story-profiles.json` "no synthetic intermediate frames by default".)
5. **S1 renders on the device with AVFoundation; the cloud renderer is the S4 adapter.** Both consume the same EDL
   and must pass the same conformance fixture: a synthetic source that carries a frame-index barcode and audio
   clicks at known frames, decoded and checked frame for frame (§7). (INFERRED.)
6. **S1's planner is deterministic, and the LLM planner arrives with the backend.** No API key may ship in the app
   (CLAUDE.md rule 5). So S1 fills the same StoryPlan schema from the user's keepers and the profile grammar. The
   LLM planner (Opus 5.5 or GPT-6 Astra) runs only server-side, behind the Worker, and is validated by the same
   code. (INFERRED.)
7. **Planner model facts (OBSERVED 2026-10-07):** `claude-opus-5-5` costs $4/$20 per MTok, cache reads $0.20, batch
   $2/$10; it has a 1M-token context and 128K output. It accepts up to 600 images per request and **no video**
   input. Forced `tool_choice` is rejected, so the plan comes back through `output_config.format` (JSON schema).
   OpenAI's "Astra" is **GPT-6 Astra**, API id `gpt-6-astra`, released 2026-09-03/04, at $10/$50 per MTok, with text
   and image input and no video. Access to it is not verified for Jon's account.
8. **Verification is part of the engine.** A film is `ready` only after a full decode with frame count, a PTS-grid
   check, audio sample count, boundary-frame mapping, unplanned freeze/black/silence detection, provenance checks
   and atomic custody. The founder's editor already implements most of this for FFmpeg, and the JOVRA adapter
   should copy those patterns rather than relax them (§4.4).

---

## 1. Engine boundary and data flow

```
trusted inputs (device or server)                         untrusted / proposal
-------------------------------------                     -----------------------------
SourceManifest (hashes, PTS index)   ─┐
SyncMap (reviewed offsets/drift)      │   bounded evidence   ┌───────────────────────────┐
KeeperCatalog / BrollCatalog          ├─────────────────────▶│ Planner (heuristic or LLM)│
Event log revision → derived stats    │  (frames, events,    │  emits StoryPlan JSON only│
Lesson notes (user text = data)       │   notes, profile)    └─────────────┬─────────────┘
StoryProfile grammar (versioned)     ─┘                                    │ data, never code
                                                                           ▼
             ┌──────────── Validator (schema → semantic → grammar lint) ◀──┘
             │                     │ reject → bounded repair (≤2) or fall back to heuristic plan
             ▼
       EDL compiler (pure, deterministic; snaps to real frame PTS; computes audio bed)
             │  edl hash (canonical JSON)
             ▼
   RenderAdapter ── on-device: AVFoundation (S1–S3)   |   cloud: FFmpeg + Remotion overlays (S4)
             │
             ▼
   Verifier (full decode, frame map, audio, provenance, custody)  →  DeliveredArtifact + receipt
```

- The planner sees **references**: keeper IDs, frame IDs, stat IDs and note IDs. Trusted manifests come from the
  device store or the server ledger, never from the planner or the client request (`contract.md`, OBSERVED).
- The compiler is a pure function, `(StoryPlan, manifests, profile revision, output spec) → EDL`. Its output is
  canonicalized (RFC 8785 JSON Canonicalization Scheme) and hashed. That hash binds the render receipt. (INFERRED.)
- Authorization and spend never appear in an EDL. They live in the job/reservation record (`contract.md`, OBSERVED:
  "An edit plan has no `approved`, `paid`, `renderAllowed`, endpoint, command or secret field.")

---

## 2. The allowlisted operation set (`jovra.edit-plan/2` proposal)

The starter validator (`tools/studio-plan/scripts/validate_edit_plan.py`, OBSERVED) accepts only contiguous 1× `cut`
segments, one `primary-bed` or `silence` route, and `score|metric|note` overlay references. That is deliberately
narrow. The v2 proposal extends it **one operation at a time**, as the contract asks. Every operation is a typed
record. No field is free text that reaches a renderer, except user-authored strings and catalog template strings,
which are escaped and rendered as text layers.

### 2.1 Time model

- **Output clock:** a rational FPS (`{num, den}`) and integer output frames, as in the starter. Default output FPS is
  the primary source's capture rate (YouTube: "encoded and uploaded in the same frame rate it was recorded",
  OBSERVED). An output FPS above a source's rate is refused rather than filled with duplicated frames. (INFERRED.)
- **Source addressing:** `{sourceId, ptsTicks, timescale}` against the **original's decoded PTS index**, recorded at
  ingest. CFR proxies add `proxyFrame`. Frame indices alone cannot rebuild a VFR original (`contract.md`,
  OBSERVED). The compiler snaps every boundary to an existing frame PTS, and the validator rejects any boundary
  that is not one. (INFERRED.)
- **Session time:** integer microseconds on the common session timeline, from the reviewed SyncMap. Cross-angle
  windows are always converted through the SyncMap and never by adding naive offsets (`jovra-media-ingest-sync`,
  OBSERVED).

### 2.2 Operations, bounds and verification

| Op | Meaning | Bounds (proposed, INFERRED) | Label / provenance | Verified by |
|---|---|---|---|---|
| `live` | Source window at 1×, in chronological session order | Window inside one source's reviewed coverage; never spans a gap | none | Barcode frame map equals the source frames exactly |
| `replay` | Labelled re-showing of an earlier `live` window, after that window | Speed ∈ {1, 1/2, 1/4, 1/8} with `sourceFPS × s ≥ outputFPS`; ≤ 8 s of output | Replay label overlay required ("Replay · ½×") | Each output frame maps to a distinct source frame, no duplicates |
| `freeze` | Hold one real frame for an explanation | 0.5–4 s; never inside a `live` segment | "Paused" label required | Held frame equals the source frame; freezedetect windows match the plan |
| `card` | Title, chapter, goal or drill card on a brand background | 1–6 s; text = user text or a catalog template | Sample badge if the project is sample | Card frames contain no source video |
| `transition` | `cut`, `dissolve`, or `dip` (to forest #092A25) between segments | Dissolve/dip ≤ 15 frames at 30 fps; none touching a contact-protection window | none | Overlap frames sit only where planned |
| `reframe` | Crop window (normalized ints, 1/10 000) with linear keyframes | Only from a reviewed action-safe box; max pan speed bounded; falls back to letterbox | "Reframed" in the manifest | Action box stays inside the crop in every keyframe interval |
| `overlay` | Score bug, lower third, metric chip, cue chip, 2D annotation, provenance chip, Sample badge | Refs to stored records only; ≤ 1 annotation at a time; text inside safe areas | Provenance label from the capability registry | Overlay text equals the event-derived value at that output frame |
| `grade` | Preset ID from a fixed catalog (`none`, `warm-court-1`, …) | Technical conversion (HDR→SDR BT.709) recorded separately from look | none | Luma/chroma stats within the preset envelope |
| `primary-bed` | Continuous court audio from the designated primary source | Must cover every `live` output frame in sync | none | Click fixture: A/V offset ≤ 1 output frame |
| `alt-bed` | Deliberate switch to another angle's audio | Only at a point boundary, level-matched, ≥ 20 ms fades | none | No doubled impacts (onset count equals planned) |
| `hold-bed` | Bed continues over dead time while video shows a replay, freeze or card | Real dead time must exist (between point end and next serve) | none | Audio PTS continuity across the insert |
| `silence` | Explicit silence | Fades ≥ 10 ms at edges | "No audio" in the manifest | RMS below threshold over the window |
| `music` | User-supplied track | Needs a `rightsRecordId` with destination scope; off by default | Credited in the manifest | Loudness measured, not asserted |
| `narration` | Consented user or generated narration | Off by default; generated voice labelled and disclosed | "Narration (generated)" when synthetic | Ducking measured; script grounded in notes |

Not in the allowlist, and rejected outright: interpolated slow motion, generated or stock footage presented as the
match, face or voice synthesis, arbitrary text from the model, shell or filter strings, URLs or paths, speed ramps
inside a `live` window, camera shake over contact frames, and any transition that spans a recording gap.

### 2.3 Validator rules beyond the starter (INFERRED, to be implemented with fixtures)

1. Trusted-manifest lookup: every `sourceId`, `keeperId`, `statId`, `noteId` and `cueId` exists in the current
   server-side or device revision. Client- or model-supplied snapshots are ignored.
2. Revision binding: `sourceManifestRevision`, `syncRevision`, `eventRevision` and `profileRevision` are all current.
   A newer event revision marks the plan and every film built from it stale (ADR-0003 corrections, OBSERVED).
3. `live` segments keep session-time order for profiles with `chronology: strict` (Match Broadcast).
4. Coverage: every source window lies inside reviewed SyncMap coverage, with no gap crossing and no seek into
   missing intervals.
5. Clean-frame rule for `replay`, and every `replay` window was already shown at 1× earlier in the film.
6. Contact protection: no `transition`, `card`, shake or flash overlaps ±0.25 s around a contact candidate or a
   reviewed contact inside a shown rally. (The window size is a proposal, to test on footage.)
7. Audio: exactly one bed per output frame. `primary-bed` stays in sync during `live`. `hold-bed` is allowed only
   over real dead time. Music needs a rights record. Narration needs consent, and generated narration needs a label.
8. Overlays: score values are **derived by the renderer** from `eventRevision` at that session time, never carried
   in the plan. Metric chips carry numerator, denominator and provenance. A metric whose provenance is below the
   profile's minimum is dropped with a finding.
9. Labels: replay and freeze labels, the Sample badge and the generated-content label are present wherever needed.
10. Accessibility: the flash count is ≤ 3 per second (WCAG 2.3.1, OBSERVED threshold). Text holds are at least
    `max(2.0 s, 0.6 s + 0.3 s × words)` (proposal to test on a phone). A Reduce Motion alternate exists whenever any
    motion effect is used.
11. Output limits: duration within the profile range, ≤ 128 segments for a cloud draft (the founder editor's
    bound, OBSERVED), even dimensions, H.264 or HEVC + AAC.
12. Determinism: the canonical-JSON EDL hash is recomputed on the render host. A mismatch means no render.

---

## 3. On-device iOS rendering with AVFoundation

Primary evidence: iOS 26.5 SDK headers on this machine (`iPhoneOS26.5.sdk/.../AVFoundation.framework/Headers/*` and
`usr/lib/swift/AVFoundation.swiftmodule/arm64e-apple-ios.swiftinterface`), read 2026-10-07. The app's floor is
**iOS 18.0** (ADR-0007), and only the iOS 26.5 simulator is installed. Any iOS 18–25 code path below is therefore
**UNVERIFIED at runtime** until it runs on an iOS 18 device or simulator.

### 3.1 Building the composition

- Use `AVMutableComposition` with **two alternating video tracks (A/B)**, so dissolves overlap. Add one or more
  dedicated **replay/freeze video tracks**, so their time scaling never touches the bed. Add **one primary-bed audio
  track**, plus optional `alt-bed`, `music` and `narration` tracks. (INFERRED standard pattern.)
- `insertTimeRange(_:of:at:)` presents an inserted range "at its natural duration and rate", and
  `scaleTimeRange(_:toDuration:)` presents each affected segment "at a rate equal to source.duration /
  target.duration" (OBSERVED, `AVCompositionTrack.h`). Scale **per track** on the replay track only. Scaling the
  whole `AVMutableComposition` would also stretch the bed. (INFERRED.)
- `insertEmptyTimeRange(_:)` exists on the composition (OBSERVED, `AVComposition.h`) and is how a `card` or an
  explicit `silence` window keeps the other tracks aligned. (INFERRED.)
- Copy each source track's `preferredTransform` into the layer instruction, so rotation is applied once.
  ImportPipeline stores a manual 90° rotation as metadata (spec, OBSERVED), and the renderer applies it exactly
  once. (INFERRED.)

### 3.2 Video composition: the iOS 26 API versus the iOS 18 floor

- `AVMutableVideoComposition`, `AVMutableVideoCompositionInstruction` and
  `AVMutableVideoCompositionLayerInstruction` are `API_DEPRECATED(... ios(4.0, 26.0))`, with the replacements
  `AVVideoComposition.Configuration`, `AVVideoCompositionInstruction.Configuration` and
  `AVVideoCompositionLayerInstruction.Configuration` (OBSERVED, header and Swift interface, `@available(iOS 26.0)`).
- `AVVideoComposition.Configuration` exposes `frameDuration`, `renderSize`, `renderScale`, `instructions`,
  `animationTool`, `customVideoCompositorClass`, the `colorPrimaries`/`colorTransferFunction`/`colorYCbCrMatrix`
  triple, `perFrameHDRDisplayMetadataPolicy` and `sourceTrackIDForFrameTiming` (OBSERVED, Swift interface).
- The layer-instruction `Configuration` provides `setOpacity`, `addOpacityRamp` (dissolves and dips),
  `setTransform`, `addTransformRamp` (reframe pans) and `setCropRectangle`, `addCropRectangleRamp` (reframe crops)
  (OBSERVED).
- **Recommendation (INFERRED):** a single `CompositionBuilder` that emits a neutral description, with two thin
  back-ends: `#available(iOS 26, *)` → `Configuration`, else the deprecated mutable classes. Both are tested against
  the same barcode fixture. This matches the spec's "Core Animation tool with `#available` branching for the iOS 26
  composition API" (OBSERVED, `ios-v1-spec.md`).
- Set `frameDuration` to the output clock and `sourceTrackIDForFrameTiming` to invalid. The header says a valid
  track ID "may be used to preserve a source asset's variable frame timing" (OBSERVED), which a fixed-FPS film does
  not want. (INFERRED.)

### 3.3 Titles, score bugs and arrows

| Route | What it is good at | Limits (OBSERVED unless marked) |
|---|---|---|
| `AVVideoCompositionCoreAnimationTool` (`postProcessingAsVideoLayer`) | Text layers (score bug, lower thirds, cards), vector arrows and lines (`CAShapeLayer`), simple timed opacity | "for use with offline rendering (AVAssetExportSession and AVAssetReader), not with AVPlayer"; begin times must use `AVCoreAnimationBeginTimeAtZero`; `removedOnCompletion = NO`; no UIView-backed layers; may need `geometryFlipped`. The ObjC factory is marked to-be-deprecated in favour of `init(configuration:)` (iOS 26) |
| `AVSynchronizedLayer` | In-app **preview** of the same overlay tree over `AVPlayerLayer` | Playback only (repo research, OBSERVED) |
| Custom `AVVideoCompositing` (Core Image or Metal) | Per-frame control: reframing with blurred letterbox, freeze holds, deterministic drawing, HDR handling | You own `startVideoCompositionRequest`, `renderContextChanged` and pixel-buffer formats. With `supportsHDRSourceFrames = NO`, the engine converts HDR sources to the composition colour space before handing frames over (OBSERVED, `AVVideoCompositing.h`) |

**Recommendation (INFERRED).** S1 uses the Core Animation tool for every overlay and layer instructions for
transitions and reframes. A single `OverlayLayerFactory` builds the layer tree from derived data (score at time *t*
from the event fold), and the same factory feeds `AVSynchronizedLayer` for preview, so preview and export share
geometry. A custom compositor is the S2+ upgrade, used only if fixtures show the CA route cannot meet a requirement:
blurred-letterbox portrait, exact freeze, HDR control.

### 3.4 Labelled slow-motion replays

- Insert the replay window on a replay video track and `scaleTimeRange` it by `1/s` (OBSERVED API).
- Apply the clean-frame rule. Sources at 60 fps give clean ½× at 30 fps output, and 240 fps practice sources give
  ½, ¼ and ⅛×. A **30 fps match has no clean slow replay at 30 fps output**: the profile falls back to a 1× replay
  or to a `freeze` plus annotation. (INFERRED. This is a capture-guidance input: suggest 60 fps for sessions meant
  for Studio, at the 1080p60 HEVC storage cost of about 90 MB/min, OBSERVED in `technical-feasibility.md`.)
- Do not insert the replay's own audio. The bed continues as `hold-bed`. If a future profile wants pitched-down
  audio, `audioTimePitchAlgorithm` exists on the export session and audio-mix parameters (`Spectral` keeps pitch,
  `Varispeed` lets it vary), OBSERVED in `AVAudioProcessingSettings.h`. That would be a new allowlisted op, not a
  default.
- The replay label is an overlay layer for the full replay range (validator rule 9).

### 3.5 Freeze frames

Two candidate implementations, each to be settled by the barcode fixture (spike, INFERRED):

- **A (video-native):** insert exactly one source frame (duration = that frame's PTS delta) on a freeze track and
  `scaleTimeRange` it to the freeze duration. Simple, and it stays in the video pipeline. It needs a test that every
  output frame shows the same barcode.
- **B (still-image):** `AVAssetImageGenerator` with `requestedTimeToleranceBefore/After = .zero` (properties
  OBSERVED in `AVAssetImageGenerator.h`) extracts the exact frame. Draw it as `CALayer.contents` under the
  annotation layers. It is exact by construction, but adds a colour-conversion path that must be checked for HDR
  sources.

Freezes sit **outside** the original-speed keeper, as an explanatory beat (style playbook, OBSERVED). The bed is
`hold-bed` over real dead time, or else `silence` with fades.

### 3.6 Transitions

`dissolve` = overlap the A and B tracks for *n* frames with complementary opacity ramps. `dip` = opacity ramps
against the instruction `backgroundColor` (forest). `cut` = no overlap. (INFERRED from the OBSERVED ramp APIs.) The
validator keeps transitions out of live rallies and contact windows, so any blend is between points, never across
evidence.

### 3.7 A continuous primary audio bed across angle cuts

- Build the bed from the **primary source** for every output frame covered by `live` and `hold-bed`, mapped through
  the SyncMap. Angle changes edit only the video tracks. (INFERRED; this is the expansion prompt's "continuous
  primary audio bed".)
- Sound travels 23.77 m ÷ 343 m/s ≈ **69 ms** from baseline to baseline, about 2 frames at 30 fps or 4 at 60
  (INFERRED arithmetic). Switching to `alt-bed` mid-point would shift contact sounds by that much. That is why
  `alt-bed` is allowed only at point boundaries, and why visual anchors corroborate audio sync (ingest skill,
  OBSERVED).
- **Dead-time compression** (Match Broadcast, Rally Pulse) cuts the bed at a point boundary. Use
  `AVMutableAudioMixInputParameters.setVolumeRamp(fromStartVolume:toEndVolume:timeRange:)` (OBSERVED,
  `AVAudioMix.h`) to apply short fades of about 10–20 ms (to tune by ear) and avoid clicks.
- Ducking under narration is a volume ramp on the bed. Measure loudness from the decoded output (§3.10) and never
  claim it because a setting was applied (style playbook, OBSERVED).

### 3.8 Export: `AVAssetExportSession` versus `AVAssetWriter`

| | `AVAssetExportSession` | `AVAssetReader` (+ `AVAssetReaderVideoCompositionOutput` / `AVAssetReaderAudioMixOutput`) → `AVAssetWriter` |
|---|---|---|
| Effort | Low: preset + `videoComposition` + `audioMix` | Higher: you pump sample buffers |
| Control | Preset-level (`AVAssetExportPreset1920x1080`, `AVAssetExportPresetHEVC1920x1080`, …, OBSERVED); `fileLengthLimit`, `shouldOptimizeForNetworkUse`, `audioTimePitchAlgorithm` | Exact codec, bitrate, keyframe interval, colour tags, frame count, chunked or resumable writing |
| Async API | `export(to:as:isolation:)` back-deployed before iOS 26; `states(updateInterval:)` on iOS 18+ (OBSERVED, Swift interface) | Your own loop; easy to checkpoint |
| Overlays | CA tool supported (OBSERVED) | CA tool supported via the AVAssetReader route (OBSERVED: "offline rendering (AVAssetExportSession and AVAssetReader)") |

**Recommendation (INFERRED).** Use the export session for fast private **previews**. Use the reader→writer route for
the **final film**, where the delivery contract needs controlled settings: H.264 High, about 8 Mbps for 1080p at
24–30 fps or 12 Mbps at 48–60 fps (YouTube guidance, OBSERVED), a closed GOP of half the frame rate, two B-frames,
BT.709 SDR tags, AAC-LC 48 kHz, and `shouldOptimizeForNetworkUse = YES` for fast start (property OBSERVED on both
the session and the writer). Use HEVC (`AVVideoCodecTypeHEVC`, OBSERVED) as an option for archive copies, and
H.264 (`AVVideoCodecTypeH264`) by default for compatibility (`ios-tech.md`, OBSERVED recommendation).

One caveat: the header comments call `AVVideoAverageBitRateKey` and `AVVideoMaxKeyFrameIntervalKey` "H.264 only"
(OBSERVED). Whether HEVC honours them via compression properties is **UNVERIFIED**. Measure it, or use
`AVOutputSettingsAssistant` presets (`AVOutputSettingsPresetHEVC1920x1080`, OBSERVED).

### 3.9 Colour and HDR

iPhones may record HDR (HLG/Dolby Vision). The default film is SDR BT.709, which needs a **technical conversion**
that the manifest records separately from any aesthetic `grade` (style playbook, OBSERVED). With the CA-tool route,
set the composition colour triple to BT.709 (properties OBSERVED). With a custom compositor,
`supportsHDRSourceFrames = NO` makes the engine convert sources (OBSERVED). Visual quality on real dusk HDR footage is
**UNVERIFIED**, so add an HDR clip to the fixture set.

### 3.10 Verification by full decode (the `ready` gate)

On the device, after writing to a temp file in the session's derived folder (INFERRED procedure):

1. Open an `AVAssetReader` on the output. Add an `AVAssetReaderTrackOutput` for video with a decompressing pixel
   format and `alwaysCopiesSampleData = NO` (header performance note, OBSERVED), and an LPCM audio output.
2. Read to the end and require `status == .completed` with no error. Count decoded video frames and require
   **exactly** the EDL's `totalFrames`. Check that each PTS sits on the `k × frameDuration` grid, strictly
   increasing with no gaps.
3. Sum the audio samples. Duration must match the output within half a frame, with no silent stretch where the
   EDL has none.
4. Check dimensions, the identity transform after baking, codec, colour tags and the fast-start atom.
5. **Boundary and mapping check (fixtures):** decode the barcode at every segment's first and last frame, and at
   sampled interior frames, and compare with the EDL's expected source frame (§7).
6. **Provenance check:** the score-bug strings drawn equal the event fold at those frames (generated from the same
   function). The Sample badge appears on sample projects.
7. Hash the file (SHA-256) and atomically move it into place (`rename` within one volume). Then write the receipt
   `{edlHash, sourceHashes, revisions, rendererId/version, settings, outputHash, verification summary}`.

A completed export is not readiness (`jovra-render-delivery`, OBSERVED). If any check fails, the film is not ready,
the evidence is kept, and the originals stay untouched.

### 3.11 Portrait reframing

- From a 1920×1080 source, a 9:16 crop is 1080 × 9/16 = 607.5, so **608 px wide**. Upscaling it to 1080×1920 is
  1.78×. From a 3840×2160 source the crop is **1216 px** wide, enough for 1080×1920 without upscaling. A 4:5
  (1080×1350) cut from 1080p needs an 864 px crop, a 1.25× upscale. (INFERRED arithmetic. "Higher output resolution
  does not create source detail", expansion prompt, OBSERVED.)
- A baseline camera frames the whole court, so a 608/1920 ≈ 32% width crop **cannot hold both players**. Match
  Broadcast portrait therefore defaults to a **letterboxed landscape** (forest bars, title space above and below).
  `reframe` is allowed only when a reviewed action-safe box (player plus expected ball region, from Vision 2D person
  detection, labelled *estimated*) fits inside the crop for the whole segment, with a bounded pan speed. (INFERRED;
  matches the playbook's "choose a truthful landscape treatment rather than an invented tracking shot", OBSERVED.)

### 3.12 Reduce Motion and clean alternates

- The app reads `UIAccessibility.isReduceMotionEnabled` or SwiftUI `accessibilityReduceMotion` for preview UI. When
  it is on, the delivery sheet makes the **clean alternate** the default selection. (INFERRED; CLAUDE.md rule 8.)
- The clean alternate uses **the same cut list**. Dissolves and dips become cuts, title animations become static
  holds, annotations appear fully drawn, and shake, zoom-punch, and Ken Burns moves are removed. It also has the
  same audio, the same overlays (static) and the same chapters. It is a second EDL derived by a pure
  `cleanAlternate(edl)` function, so the two cannot drift. (INFERRED.)

### 3.13 Performance on the device

- Run renders after capture, in `ProcessingQueue` stages, at thermal state ≤ `fair` and preferably on power. Use a
  user-initiated `BGContinuedProcessingTask` on iOS 26. On iOS 18, render in the foreground with resumable
  checkpoints (spec and ADR-0007, OBSERVED). The reader→writer route can checkpoint by rendering **chapters into
  separate files** and joining them with passthrough. Whether a passthrough join is frame-exact across encoder GOP
  boundaries is **UNVERIFIED** and needs a fixture test before relying on it.
- No throughput numbers are claimed. **Benchmark gate (UNVERIFIED until run):** on the oldest supported iPhone,
  measure a 5-minute 1080p30 film with a score bug, eight replays and two dissolves: wall time, peak thermal state,
  battery drop and output-size accuracy, for the export-session and writer routes, with HEVC and H.264 sources.
- Bound the CA-tool cost: create overlay layers per chapter rather than for the whole film. The per-film layer
  count is a measured budget, not an assumption. (INFERRED.)

### 3.14 What "deterministic" means on a device

Hardware encoders are not promised to produce identical bytes across runs or devices (**UNVERIFIED** either way).
Deterministic here means the **plan → timeline → frame map** is identical and checkable: same EDL hash, same decoded
frame-to-source mapping, same overlay strings, with durations within the stated tolerance. The output hash is
recorded per render, not used as a reproducibility test. (INFERRED.)

---

## 4. Cloud rendering

The control path (Supabase, the Worker, R2, Queues) follows `design-reference/studio/brief/backend-media-design.md`
(OBSERVED). Workers do not render; a separately provisioned render host runs FFmpeg/ffprobe and Remotion. This
section covers the render host's engine.

### 4.1 Compiling an EDL to an FFmpeg filtergraph from the allowlist

**Principles (INFERRED, following the founder's editor):**

- The filtergraph is generated by code from **validated integers and rationals only**. Each allowlisted op maps to
  one fixed template, and numbers are formatted by the compiler (`f"{value:d}"`, exact rationals). No string from a
  plan, a user or a model is ever interpolated into the graph. Text is rendered by Remotion into image or video
  layers (§4.3) and is not passed to `drawtext`.
- Write the graph to a file and pass it with FFmpeg's file-argument syntax, a "forward slash '/' immediately before
  the option name", e.g. `-/filter_complex graph.txt` (OBSERVED, ffmpeg.org). The founder's editor writes
  `filters.txt` as evidence (OBSERVED).
- Inputs are opened as pinned descriptors with `-protocol_whitelist file,pipe` and `-format_whitelist
  mov,matroska,webm`, plus `-nostdin -xerror` (OBSERVED in `production_preview.py`).
- The render host's FFmpeg build is **pinned and probed at startup**. This machine's Homebrew FFmpeg 9.0.1 lacks
  `drawtext` (no libfreetype) and `zscale` (no libzimg), but has `tpad`, `xfade` (`fade`, `fadeblack`, `dissolve`),
  `setpts`, `loudnorm`, `ebur128`, `freezedetect`, `blackdetect`, `silencedetect`, `ssim`, `psnr`, the `framemd5`
  muxer, libx264, libx265 and libvmaf (OBSERVED, local `ffmpeg -h filter=…`, `-buildconf`). The compiler refuses to
  run if a required filter is missing.

| EDL op | Filter template (all values computed by code) |
|---|---|
| `live` | `trim=start_frame=A:end_frame=B,setpts=PTS-STARTPTS` (as in the founder's editor) |
| `replay` speed 1/k | `trim=…,setpts=k*(PTS-STARTPTS)`; the clean-frame rule guarantees distinct frames; `minterpolate` is never emitted |
| `freeze` *n* frames | `trim=start_frame=F:end_frame=F+1,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop=n-1` (OBSERVED options) |
| `transition` | `xfade=transition=fade|fadeblack:duration=D:offset=O` with O and D derived from integer frames |
| `reframe` | `crop=w:h:x:y` per constant sub-segment, or a linear expression template filled only with validated integers; then `scale=…:flags=lanczos,setsar=1` |
| letterbox | `scale=…:force_original_aspect_ratio=decrease,pad=…:color=0x092A25` |
| `overlay` | One Remotion-rendered alpha track covering the whole output (same FPS and frame count) → `overlay=0:0` |
| `grade` | Catalog preset → fixed `eq=` / `colortemperature=` parameters, or a JOVRA-authored `.cube` with `lut3d` (the IDC LUTs are not bundled, OBSERVED in `source-assessment.md`) |
| beds | `atrim`/`asetpts`/`aresample=48000`/`afade` per bed span → `concat` (`acrossfade` at boundary crossfades) |
| ducking | precomputed `volume` automation, or `sidechaincompress` keyed by narration (filter OBSERVED) |
| loudness | two-pass `loudnorm` (measure, then apply measured values); verify with `ebur128` |

**Encode settings (INFERRED, following the YouTube recommendations, OBSERVED):** `libx264 -profile:v high -pix_fmt
yuv420p -g {fps/2} -bf 2` with a closed GOP, BT.709 colour flags, `-c:a aac -ar 48000`, `-movflags +faststart`,
plus `-fps_mode` and `-enc_time_base` pinned as the founder's editor does. On reproducibility: x264 is deterministic
across multiple threads by default unless `--non-deterministic` is set, **except** in VBV (`maxrate`/`bufsize`) mode,
which developers describe as non-deterministic with threads (x264-devel and Doom9 threads, OBSERVED via search;
secondary sources). Use CRF without VBV for drafts. Pin `threads=1` only where byte-reproducible output is a test
requirement.

**Normalization stage (before the strict assembler):** VFR→CFR proxies via `fps` with the original-PTS ↔
proxy-frame map recorded, rotation applied once, HDR→SDR conversion (needs a build with zscale/tonemap or an
equivalent; local `tonemap` is present but `zscale` is not, OBSERVED), and audio resampled to 48 kHz. Originals are
never replaced (`jovra-media-ingest-sync`, OBSERVED).

### 4.2 Remotion compositions for tennis graphics

- Remotion renders React per frame through `renderMedia()`. Its options include `composition`, `codec`,
  `inputProps`, `concurrency`, `frameRange`, `crf`, `timeoutInMilliseconds`, `colorSpace`, `x264Preset` and
  `hardwareAcceleration` (OBSERVED, remotion.dev). The founder's editor pins **Remotion 4.0.523** with React 19.2.3
  (OBSERVED, `package.json`).
- **Proposed compositions (INFERRED):** `JovraScoreBug` (two rows from derived set/game/point state, server dot
  only when recorded), `JovraLowerThird`, `JovraChapterCard`, `JovraTitleCard`, `JovraMetricChip` (numerator /
  denominator / provenance), `JovraCueChip`, `JovraAnnotation` (2D arrow, line or circle from stored annotation
  geometry), `JovraReplayLabel` and `JovraSampleBadge`. They use the brand tokens (ivory #F4F1E8, forest #092A25,
  chartreuse #D7F56A, clay #C47752) and the Court Arc mark.
- Props come from the **compiled EDL plus derived data** and are validated with a schema inside the composition. A
  score is never a prop typed by the planner, only the derived fold.
- Render **one transparent overlay track** at the output FPS and frame count (ProRes 4444 or PNG frames). FFmpeg
  owns all source-video timing and the overlay is composited in one `overlay` pass. Picture timing then rests on
  the path the founder's editor already verifies frame-exactly. (INFERRED.)
- **Licensing:** Remotion is free for "an individual", "a for-profit organization with up to 3 employees" and
  non-profits; otherwise a Company License applies (OBSERVED, remotion LICENSE.md). Terms for a service that renders
  for end users were not in the fetched text, so check remotion.pro before S4 (**UNVERIFIED**; also flagged in the
  backend brief).

### 4.3 Reusing the founder's editor (`garnet-remotion`, read-only)

Read today: `PIPELINE.md`, `production_preview.py`, `README.md` and `package.json` (OBSERVED). Nothing was run or
modified.

| Pattern in the editor (OBSERVED) | Carry into the JOVRA adapter as |
|---|---|
| `production-lab.editor-media-map.v1` binds the exact plan bytes with `planSha256`; each segment maps to a path, an integer `sourceStartMs`, a checked SHA-256 and an explicit `audioMode` | `jovra.render-job/1`: binds `edlHash` (canonical JSON), source IDs resolved **server-side** to object keys, per-source SHA-256 checked before and after the render |
| Inputs opened with `O_NOFOLLOW`/`O_NONBLOCK` relative to directory descriptors; FIFOs rejected; source re-hashed after render ("changed during rendering; draft is not usable") | Same custody, on the render host's job workspace |
| Probe constraints: one video track and at most one audio, CFR, `avg_frame_rate == r_frame_rate`, timebase ≤ 1 ms, no rotation, square pixels, zero start, even dimensions, at most 4 h | Keep **unchanged** for the strict assembler; JOVRA runs a separate normalization stage first |
| Every decoded frame checked against the nominal clock (no duplicate or irregular PTS, half-tick tolerance) | Same check on proxies **and on the output** |
| Output metadata must equal the plan (frames, size, FPS, audio duration within 25 ms) | Same, plus a barcode mapping check on fixtures |
| Full decode `-v error -xerror -f null -` with an **empty stderr** required | Same |
| Exclusive creation, `preview.rendering.mp4` → hardlink `preview.mp4`, inode/bytes/directory custody verified twice, failures recorded with partial evidence kept | Same for `film.rendering.mp4` → `film.mp4`, then upload to private R2 with the receipt |
| Limits: ≤ 128 segments, ≤ 32 sources, timeouts 1–14 400 s | Same defaults; cards, replays and freezes count as segments |
| `review.html` with escaped intent text and a CSP | A private review page variant, if useful for coach review |

**What must change (INFERRED):** a bed-based audio graph replaces the per-segment `source|silent` audio
concatenation, plus new ops for replays, freezes, transitions, reframes and overlays, the normalization stage,
JOVRA compositions in a **new** project or folder (never the Garnet root), and JOVRA's private-draft policy instead
of the suite's `SHIP` approval. Imported approvals never transfer (expansion prompt, OBSERVED).

### 4.4 Verification parity (cloud)

`ffprobe -show_frames` clock check, metadata equality, full decode with empty stderr, `freezedetect`, `blackdetect`
and `silencedetect` with planned windows excluded (so an unplanned freeze or black frame fails), boundary-frame
`ssim` against the expected source frame (lossy encodes cannot use byte hashes; the threshold must be measured),
`ebur128` loudness measurement and the barcode map on fixtures. The output is identical in form to the device
verifier's, so the delivery manifest has one schema. (INFERRED.)

---

## 5. The AI planner

### 5.1 Role and contract

The planner **proposes**: a readable story brief plus a StoryPlan built from enums and IDs. It does not cut video,
compute times, decide spend or publish (`ENGINE-BOUNDARY.md`, `jovra-edit-plan`, OBSERVED).

Sketch of the model-facing schema (INFERRED; every field `required` and objects `additionalProperties:false`, to stay
inside structured-output limits, §5.4):

```json
{
  "schemaVersion": "jovra.story-plan/1",
  "profileId": "coach-cut",
  "feelingKey": "capability-next-action",
  "beats": [
    {"beatId": "b01", "role": "goal", "keeperId": "none", "angle": "none",
     "treatment": "card", "replay": "none", "overlays": ["none"], "noteId": "n-07",
     "templateId": "card.goal", "reasonForReview": "Player's stated lesson goal opens the film."},
    {"beatId": "b02", "role": "example", "keeperId": "k-12", "angle": "baseline",
     "treatment": "live", "replay": "half-speed", "overlays": ["score", "cue:c-03"], "noteId": "none",
     "templateId": "none", "reasonForReview": "Clearest of three late recovery steps; cue c-03 is reviewed."}
  ],
  "omitted": [{"idea": "reaction shot after the set", "missingEvidence": "no keeper covers it"}]
}
```

`reasonForReview` and `omitted` are shown only in the review UI and are never burned into the film. On-screen text
comes from user-authored records or from fixed catalog templates whose slots (dates, names as entered, counts) code
fills from stored data. This is what stops invented quotes and metrics. (INFERRED; style playbook: "A model can
select approved cues; it cannot invent a coach or a result", OBSERVED.)

### 5.2 Claude Opus 5.5: facts that matter here

Sources: the `claude-api` skill (cached 2026-09-25) and docs fetched today from platform.claude.com.

| Fact | Value | Label |
|---|---|---|
| Model ID | `claude-opus-5-5` (Bedrock `anthropic.claude-opus-5-5`) | OBSERVED |
| Context / max output | 1M tokens / 128K (streaming needed for large `max_tokens`) | OBSERVED |
| Price | $4 input / $20 output per MTok; 5-min cache write $5, 1-h write $8, cache read $0.20 (0.05×); batch $2 / $10 | OBSERVED (pricing page) |
| Thinking | Always on (adaptive). `disabled` or `budget_tokens` → 400. Control via `output_config.effort`; **default `medium`**; thinking tokens bill as output and count toward `max_tokens` | OBSERVED |
| Tool choice | Forced `tool_choice` `any`/`tool` → 400 (also on Batches and count_tokens); use `auto` + `strict: true`, or structured outputs | OBSERVED |
| Structured outputs | `output_config.format` `{type: "json_schema", schema}`; no recursion, no `minimum`/`maximum`/`minLength`; `additionalProperties:false` required; per request ≤ 20 strict tools, **≤ 24 optional params**, **≤ 16 union-typed params** across all strict schemas; grammar compile cached 24 h; 180 s compile timeout; enum **capitalization not guaranteed** (compare case-insensitively); refusals and `max_tokens` may break the schema | OBSERVED |
| Images | JPEG/PNG/GIF/WebP; **≤ 600 images per request** (1M-context models); ≤ 8000×8000 px; **> 20 images → each ≤ 2000 px** or 400; ≤ 10 MB per image (API), 5 MB on Bedrock/Vertex; request ≤ 32 MB | OBSERVED (vision page) |
| Image tokens | `⌈w/28⌉ × ⌈h/28⌉`; high-res tier (Claude 4.7+) caps at 2576 px long edge / 4784 tokens, e.g. 1920×1080 = 2691 tokens | OBSERVED |
| Video | Not an input type; supported formats are images only | OBSERVED (formats list), so video must be sampled to frames |
| Files API | GA, 500 MB per file, 1 TB per org, workspace-scoped (never accept `file_id` from users), **not ZDR-eligible**, not on Bedrock/Vertex | OBSERVED |
| Batches | 50% off; ≤ 100 000 requests or 256 MB; most finish < 1 h, expire at 24 h; results kept 29 days; caching is best-effort inside batches | OBSERVED |
| Prompt caching | ≤ 4 breakpoints; **512-token minimum** on Opus 5.5; 5-min TTL refreshed on read; 1-h TTL at 2× write | OBSERVED |
| Refusals | `stop_reason: "refusal"` (HTTP 200) with `stop_details.category` (`cyber`, `bio`, `reasoning_extraction`, …); ship a fallback opt-in (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`) | OBSERVED (skill) |
| People | Claude will not identify people in images | OBSERVED (vision limits); players are named only from user-entered event data |

### 5.3 What "Astra" refers to (as of 2026-10-07)

- **OBSERVED:** OpenAI's **GPT-6 Astra**, launched 2026-09-03 (limited preview), then publicly to paid users
  2026-09-04 "in a restricted version that rejects certain prompts in areas such as cybersecurity" (Wikipedia).
  Search-result summaries of CNBC and Axios say it rolled out in phases, Daybreak cyber-program participants
  first, and that it is "available … through the OpenAI API and Amazon Web Services". The CNBC article body
  returned HTTP 403, so that wording rests on the search summary.
- **OBSERVED (developers.openai.com model page):** ID **`gpt-6-astra`**; 1 050 000-token context (922 000 max input),
  128 000 max output; knowledge cutoff 2026-04-30; input **text and image**, output text; $10 input / $1 cached /
  $12.50 cache write / $50 output per MTok; batch at 50%; Chat Completions, Responses and Batch endpoints;
  structured outputs, function calling and streaming; effort levels low–max. Sibling models are `gpt-6-sol` ($2/$10)
  and `gpt-6-luna` ($0.10/$0.50).
- **OBSERVED (OpenAI vision guide):** ≤ 1 500 images and ≤ 512 MB payload per request; 32 px patches; a `detail`
  setting of `low|high|original|auto`; GPT-6 Astra `high` = 2 500 patches. **No video input is documented.**
- **INFERRED:** the handoff's "GPT Astra" (the author of `JOVRA-Studio-Claude-engine-v2`) and Jon's "Astra" both mean
  GPT-6 Astra used through ChatGPT. Structured output in the Responses API is
  `text: {format: {type: "json_schema", strict: true, schema}}`, and refusals arrive in a separate `refusal` field
  (OBSERVED, OpenAI structured-outputs guide).
- **UNVERIFIED:** whether Jon's OpenAI organization has API access to `gpt-6-astra` (no account was inspected); the
  exact image-token formula (the guide lists a "1.2×" multiplier whose meaning was not resolved); and schema-size
  limits for OpenAI strict mode (not in the fetched excerpt). Measure all of these on activation. (Google DeepMind's
  "Project Astra" is a different product; the name collision is noted, not researched.)

### 5.4 Provider-neutral adapter

```
PlannerProvider (server-side only; keys in Worker / render-host secrets, never in the app)
  capabilities() -> {providerId, modelId (pinned), maxImages, maxImageLongEdge, manyImageLongEdge,
                     maxRequestBytes, structuredOutput: "json_schema", schemaLimits, supportsBatch,
                     supportsPromptCache, priceTable(version, checkedAt)}
  plan(PlanRequest) -> PlanResponse {status: ok|refused|truncated|invalid, storyPlanJSON?, usage,
                                     requestHash, responseHash, providerRequestId, latencyMs}

PlanRequest (provider-neutral): system grammar + schema + evidence pack + frame refs + images (bytes)
Providers: AnthropicMessagesProvider (output_config.format, effort, fallbacks opt-in, streaming)
           OpenAIResponsesProvider   (text.format json_schema strict, reasoning effort)
           HeuristicProvider         (deterministic; S1 default; also the fallback when a model is unavailable)
```

**Rules (INFERRED):**

- **The schema is the shared truth.** One JSON Schema is written to fit both vendors' limits. All fields are
  required, with `"none"` sentinels instead of `null` unions (Anthropic counts each `["string","null"]` toward the
  16-union cap), and flat beat objects. Enums never differ only in case. Numeric bounds are enforced by the
  validator, because Anthropic's structured outputs do not support `minimum`/`maximum` (OBSERVED) and OpenAI's
  strict-mode limits were not checked (UNVERIFIED).
- **Pinned configuration:** the provider, model ID, effort and price-table version are config values written into
  every film's receipt (backend brief: "planner model/version", OBSERVED). Nothing escalates on its own to a costlier
  model, a higher effort or more attempts (`jovra-cloud-production`, OBSERVED).
- **Refusal and truncation** (`refusal`, or `max_tokens` cutting the JSON) produce no plan. The job falls back to the
  heuristic plan and records why. A refusal is never parsed as a plan.
- **Data leaving the device.** Sending frames to Anthropic or OpenAI is user media leaving the phone. It needs the
  explicit cloud consent on the preflight screen, a privacy-label review (ADR-0013 targets "Data Not Collected" for
  v1) and a retention statement per provider. The Files API is not ZDR-eligible (OBSERVED), so the default is
  **inline base64 frames per request, not persisted with the provider**. (INFERRED.)

### 5.5 Feeding frames, events and lesson notes within limits

**Evidence pack (text, cacheable part first):**

1. A stable prefix: role, JOVRA honesty rules, the profile grammar (§6, versioned), the StoryPlan schema description
   and the template catalog. It sits well above the 512-token cache minimum and carries one `cache_control`
   breakpoint (OBSERVED mechanics).
2. Per project: keeper catalog rows `{keeperId, sessionInUs, sessionOutUs, angleCoverage[], pointNumber,
   outcomeFromEvents, contactCandidates(estimated), reviewStatus}`, a score timeline derived from the event revision
   (read-only), stat IDs with numerator/denominator/provenance, cues with review status, B-roll rows with rights
   flags, and lesson notes.
3. Lesson notes and every other user or OCR-like text are wrapped as **quoted data** with IDs. The system prompt
   says notes are data and never instructions, and the schema leaves no output channel for following an injected
   instruction. The validator is the real defence. (INFERRED; consistent with the backend brief.)

**Frames (sampled; neither provider takes video):**

- **Event-keyed sampling:** per keeper, three frames (serve or first visible shot, a contact candidate, and the
  point end plus 0.5 s). Per angle, only inside reviewed sync coverage. B-roll gets one frame per clip. Uniform
  coverage for Court Memories is one frame per 10 s of non-play time, capped. (INFERRED parameters.)
- **Size:** 768×432 JPEG at a fixed quality costs `⌈768/28⌉×⌈432/28⌉ = 28×16 = 448` tokens on Opus 5.5 (INFERRED
  from the OBSERVED formula). That is below the 2000 px many-image cap.
- **Labelling:** each image is preceded by a text label, e.g. `Image 37: frame f-37 | keeper k-12 | camera baseline
  | session 00:24:12.400 | contact candidate (estimated)`. Anthropic recommends labelled images before the question
  (OBSERVED). The model refers to frames only by ID.
- **Strip metadata:** EXIF and location are removed before upload. Claude does not read metadata anyway (OBSERVED),
  but this is a privacy rule.

**Budget example (Coach's Cut, one match; INFERRED, to be measured):**

| Item | Tokens | Opus 5.5 standard | Batch |
|---|---|---|---|
| 40 keepers × 3 frames × 448 | 53 760 | | |
| Keepers/events/stats/notes JSON (assumed) | 12 000 | | |
| Cached prefix (assumed, read after the first call) | 8 000 | | |
| **Input total** | **≈ 73 760** | ≈ $0.29 | ≈ $0.15 |
| Output plus thinking (assumed 8 000–30 000 at `medium`) | | $0.16–$0.60 | $0.08–$0.30 |
| **Per attempt** | | **≈ $0.45–$0.89** | **≈ $0.23–$0.45** |

120 images is under the 600 limit. At about 60–90 KB per JPEG, base64 adds about a third, so the payload is roughly
10–14 MB, under the 32 MB request cap (INFERRED). With at most two repair attempts the worst case is about 3 × $0.89
≈ $2.67, **above** the backend brief's illustrative $0.25–$2.00 planner allowance. Use batch for non-urgent jobs (a
cloud job is already asynchronous), or cap repairs at one. At GPT-6 Astra's $10/$50 the token cost is about 2.5×
(INFERRED from list prices; its image-token count differs and was not measured).

**Two optional quality levers (INFERRED, to evaluate later):** a crop/zoom tool that returns an enlarged region of a
listed frame. Anthropic notes crop tools help vision accuracy on dense inputs (OBSERVED, skill guidance for Opus
5.5/Fable). The second lever is a second pass on only the chosen keepers at higher resolution. Neither is needed for
S4's first slice.

### 5.6 Validation pipeline and repair loop

1. **Transport check:** `stop_reason` is `end_turn`, not `refusal` or `max_tokens`, and the content parses as JSON.
2. **Schema validation** (the same JSON Schema, run locally, case-insensitive enum normalization).
3. **Semantic validation** against trusted manifests (§2.3 rules 1–9).
4. **Grammar lint** for the chosen profile (§6 machine-checkable rules).
5. **Compile** to an EDL, then run the **dry-run frame plan**: exact segment frames and durations, total versus the
   target range.
6. On failure, run **one bounded repair**: return machine-readable finding codes (for example
   `E_KEEPER_UNKNOWN k-99`, `E_REPLAY_UNCLEAN k-12 30fps`), never raw stack traces. If the repair fails too, fall
   back to the heuristic plan. Every attempt counts against the job's usage reservation (`jovra-cloud-production`,
   OBSERVED).
7. **Human review** where needed: uncertain sync, estimated cues and any narration script. Approval of a plan never
   approves spend or publication (`jovra-studio-director`, OBSERVED).

**Never executed or trusted from model output (INFERRED, consistent with every Studio skill):** shell commands,
filter strings, expressions, JavaScript or JSX, file paths, object keys, URLs, signed URLs, credentials, prices,
`approved` or `paid` flags, frame numbers, score digits, metric values, quotes, provenance upgrades and output
settings beyond the user's choice.

### 5.7 Evaluating planners

Build a fixture suite of synthetic plus (later) Jon's real old match, with expected-valid keepers per profile.
Measure: schema-valid rate, **grounding precision** (every beat resolves, no rejected IDs), grammar-rule violations,
human editorial ratings by profile, plans that need repair, cost and latency per plan. Run the same fixtures through
`HeuristicProvider`, Opus 5.5 and GPT-6 Astra. Promote a provider as the default only on measured results. That is
the capability-registry discipline (ADR-0004) applied to the planner. (INFERRED.)

---

## 6. The five story profiles as editing grammars

Defaults come from `story-profiles.json` (OBSERVED): no music, no generated commentary, rally speed 1, low effects,
continuous primary audio, visible provenance and no auto-publish. Every number below is a **proposed default**
(INFERRED), to be tuned on real footage. Bold rules are validator- or lint-checkable.

### 6.0 Shared grammar (all profiles)

- **Live tennis is sacred:** no speed change, effect, transition or title over the action region inside a shown
  rally's contact windows. A rally is cut only at point boundaries, or at a reviewed same-event angle change (Coach's
  Cut demonstration only).
- **Replays come after the original-speed showing,** are labelled, and obey the clean-frame rule.
- **Score and metric text are derived at render time** from the bound event revision. A correction makes older films
  stale (ADR-0003).
- **Audio:** one bed. `primary-bed` during live play, `hold-bed` under replays and freezes over real dead time, and
  `alt-bed` only at point boundaries.
- **Sample projects show the Sample badge on every frame.** Generated or stock material is labelled and never
  passes as match footage.
- **Reduce Motion clean alternate** (§3.12) whenever a motion effect is used. **Flash ≤ 3/s** (WCAG 2.3.1).

### 6.1 Coach's Cut: "I can see what to practise next" (180–600 s, deliberate)

| Element | Grammar |
|---|---|
| Structure | `goal card` (≤ 4 s) → per example (2–3): `live` keeper at 1× → optional `freeze` (≤ 3 s) with one annotation → optional `replay` ½× of the movement → `cue chip` → closing `drill card` + `next checkpoint card` |
| Cuts | **At point boundaries.** A same-event angle switch only when SyncMap residual ≤ 1 output frame and status `reviewed` |
| Pacing | Live segments are whole keepers (spec default pre-roll ≈ 1.5 s / post-roll ≈ 2.5 s); text holds per rule 10; at least 1 s breathing room after each cue |
| Overlays | Score bug (derived), source-time chip, cue chip with provenance (**Reviewed or Manual only; Estimated cues shown as "Estimated" and never as instruction titles**), metric card with **numerator/denominator** (e.g. "Reviewed · 18 of 30 first serves in · 60%", Sample in fixtures) |
| Audio | `primary-bed`; `hold-bed` under freezes and replays; narration optional and consented |
| Effects | Freeze, one 2D annotation at a time, ½× or ¼× replay; dissolve ≤ 12 frames only between chapters; **no shake, zoom-punch or music by default** |
| Reduce Motion | Annotations appear without a draw-on animation; dissolves become cuts |
| Portrait | Allowed only if the action-safe box fits; otherwise letterbox |
| Fallback | User notes plus manually chosen clips; with no reviewed cue, the film is "Your examples" without instructional claims |
| Must not | Diagnose injury, state unvalidated biomechanics, invent a coach quote (story-profiles `mustNot`, OBSERVED) |

### 6.2 Match Broadcast: "I can follow and relive the match" (300–7200 s, faithful)

| Element | Grammar |
|---|---|
| Structure | Intro card (players as entered, date, format) → points in **strict session order** → game/set transition lower thirds → chapters at games/sets → final score card **only if point coverage is complete** |
| Cuts | **During live play, stay on the selected wide angle** (primary baseline). **Alternate angles only as post-point replays** that **end before the next point's serve**. Establish orientation before showing the opposite baseline (screen direction reverses) |
| Pacing | Faithful: dead time between points compressed to ≤ 3 s (proposal), changeovers to a ≤ 5 s score card; a **recording gap becomes an explicit "Recording gap · mm:ss" card**, never closed up |
| Overlays | Persistent compact score bug updating at each point end from the event fold; server indicator only when recorded; sparse lower thirds |
| Audio | Continuous `primary-bed`; fades at compressed dead time; replays over `hold-bed` |
| Effects | Cut, or a short dissolve (≤ 8 frames) into and out of replays; replay label; nothing else |
| Reduce Motion | Dissolves become cuts (effectively identical otherwise) |
| Portrait | **Letterboxed landscape by default** (§3.11) |
| Fallback | One-angle complete match with chapters (OBSERVED fallback) |
| Must not | Jump to an unsynchronized view, hide missing intervals, invent commentary or score, present an MP4 as interactive multi-angle replay |

### 6.3 Rally Pulse: "That exchange was worth keeping" (30–180 s, quick between, clear during)

| Element | Grammar |
|---|---|
| Structure | Opening = strongest real rally, or a **labelled "Coming up" teaser** when it breaks chronology → short build (2–4 rallies) → key exchange → point payoff (the real outcome, misses included) → quiet 1–2 s close on court sound |
| Cuts | **Each shown rally is uncut** from serve or first visible shot to point end + ≥ 0.5 s. Energy cuts happen only **between** rallies. Separate points are never assembled into a fake continuous rally |
| Pacing | Connective material between rallies 0.5–1.5 s; title accents ≤ 1.5 s |
| Overlays | Small point-context chip (game score, from events) and one reviewed fact at most |
| Audio | Court sound by default; a music track **only with a rights record** for the destination. Beat alignment may move cut points **only inside dead time** (±6 frames proposal), never a rally boundary inside contact protection |
| Effects | Intensity `low` (default) or `medium`: dissolve/dip ≤ 6 frames between rallies, title accents. **Shake off by default**; if on, amplitude ≤ 1.5% of frame height, ≤ 12 frames, connective segments only. **Flash ≤ 3/s**; no strobes, no repeated zooms |
| Clean alternate | Same cuts, ordinary transitions, static titles (OBSERVED requirement) |
| Portrait | Common target; per-segment action-safe check, letterbox the segments that fail |
| Fallback | Court-sound highlights with static titles (OBSERVED) |
| Must not | Flash or shake over contact frames, misrepresent misses as winners, use an unlicensed popular song |

### 6.4 Progress Story: "I remember the work, and can assess the change" (120–360 s, reflective)

| Element | Grammar |
|---|---|
| Structure | Dated goal card → early evidence (date-labelled) → lesson and practice milestones (journal records) → recent evidence → "What changed / what remains" card → next practice goal |
| Comparisons | Side-by-side or sequential **before/after** at the same scale, synced at a contact sync point (the existing Comparison concept). **A pair is allowed only when both sides share a metric definition ID and method ID with compatible selection**; otherwise it becomes a "chronology" with a method-change note |
| Numbers | **Rendered from stored stats with dates and denominators**: "12 / 30 · 40% → 18 / 30 · 60%, +20 percentage points" (Sample in fixtures). **"% improvement" wording on proportions is banned.** Improvement language needs ≥ Reviewed provenance on both sides |
| Selection honesty | Examples carry `selectionRule` ∈ {`all`, `seeded-random`, `user-chosen`}; `user-chosen` shows "Examples you chose" |
| Audio | Low court sound; optional consented reflection or narration; music only with rights |
| Effects | Restrained: static charts or ≤ 0.5 s builds; dissolves ≤ 12 frames between dated sections |
| Fallback | Lesson chronology with user-authored reflections and no improvement metric (OBSERVED) |
| Must not | Mix methods without warning, claim causality from two clips, select only successes while implying a complete statistic |

### 6.5 Court Memories: "This day mattered to me" (120–480 s, cinematic)

| Element | Grammar |
|---|---|
| Structure | Arrival or establishing (real) → preparation (racket, strings, bag; real B-roll) → match moments → personal highlight → after the match → optional dedication card (user text) |
| Cuts | B-roll only from the **BrollCatalog with rights and a `depictsThisMatch` flag**; stock or generated material is excluded unless explicitly permitted, and then labelled and never presented as the day |
| Pacing | B-roll shots 2–6 s; match moments whole rallies or meaningful exchanges; ending holds the last real moment ≥ 2 s, then a ≤ 1 s dip to forest |
| Audio | Natural sound throughout; **J/L cuts** (audio leads or trails picture by ≤ 1 s) allowed **only across non-live boundaries**; music only with rights |
| Grade | One catalog preset (e.g. `warm-court-1`) applied consistently after technical normalization; must preserve skin, court lines and detail |
| Overlays | Date; venue **only if opted in**; short user caption; no score bug by default (optional final score card) |
| Effects | Dissolves ≤ 15 frames, gentle; no shake or speed effects |
| Privacy | Location hidden by default; optional bystander face blur (existing `estimated` capability) |
| Fallback | One-camera match excerpts with real stills and original audio (OBSERVED) |
| Must not | Synthesize likeness or words, make a generated moment look like match footage, reveal a hidden location |

### 6.6 Operation availability by profile

| Op | Coach's Cut | Match Broadcast | Rally Pulse | Progress Story | Court Memories |
|---|---|---|---|---|---|
| `live` 1× | ✓ | ✓ (strict order) | ✓ (uncut rallies) | ✓ (dated) | ✓ |
| `replay` (clean) | ✓ ½ ¼ | ✓ after point | ✓ after rally | ✓ for comparisons | — (default off) |
| `freeze` + annotation | ✓ | — | — | ✓ (comparison hold) | — |
| `card` | ✓ | ✓ (gap/score/chapter) | ✓ (accents) | ✓ | ✓ |
| `dissolve` / `dip` | ≤ 12 fr | ≤ 8 fr | ≤ 6 fr | ≤ 12 fr | ≤ 15 fr |
| `reframe` | if box fits | letterbox default | if box fits | if box fits | if box fits |
| `grade` preset | none | none | optional | none | ✓ |
| shake | — | — | optional, off | — | — |
| `music` | — | — | with rights | with rights | with rights |
| `narration` | consented | — | — | consented | consented |
| J/L audio | — | — | — | — | ✓ non-live |

---

## 7. Conformance fixtures: how both renderers prove correctness

Extending ADR-0012's synthetic-media approach (INFERRED design):

- **Barcode sources:** synthetic clips at 24, 30 and 60 fps (CFR), a VFR variant, a rotated variant and an HDR
  variant. Each frame carries a large binary barcode strip (source ID plus a 20-bit frame index, robust to lossy
  encoding), plus a 1 kHz click at known frames on the audio track. Two or more "angles" carry known offsets and
  drifts for sync tests.
- **Expected map:** from the compiled EDL, the exact source frame for every output frame, and the click times in the
  output.
- **Assertions:** every decoded output frame's barcode equals the expected one (live, replay and freeze); no
  duplicate source frames in clean replays; dissolve frames only where planned; clicks within ±1 output frame;
  frame count, duration and audio samples exact; overlay strings equal to the event fold; Sample badge present.
- The same fixtures run on the AVFoundation adapter (macOS `swift test` and the simulator), the FFmpeg/Remotion
  adapter, and later an Android adapter (Media3; out of scope, UNVERIFIED). This is what makes "both renderers
  execute the same EDL" a checked claim rather than an assertion.
- Fixtures prove **pipeline logic only**. Real tennis editorial quality, sync on real footage, thermal behaviour and
  HDR appearance need Jon's old match and physical devices (expansion prompt acceptance list, OBSERVED).

---

## 8. Risks, conflicts and open questions

| # | Item | Label |
|---|---|---|
| R1 | **D5 (exports default to no audio)** conflicts with the Studio profiles' default court sound. Proposal: the private in-app film keeps court audio, and any file leaving the app (download, share, YouTube preparation) shows a prominent "Include court audio" choice. The no-audio variant is a passthrough remux and is verified too. Needs Jon's decision. | INFERRED conflict (spec D5, story-profiles defaults, OBSERVED) |
| R2 | 30 fps sources cannot give clean slow-motion at 30 fps output. Capture guidance for Studio sessions (60 fps) costs storage. | INFERRED |
| R3 | The iOS 18–25 composition path (deprecated mutable classes) cannot be run on this Mac; only the iOS 26 path gets simulator evidence. | OBSERVED constraint (ADR-0007) |
| R4 | Freeze implementation (scaled one-frame insert versus still image) and passthrough chapter joins are unproven. | UNVERIFIED |
| R5 | `AVVideoAverageBitRateKey` and keyframe settings for HEVC (the header says H.264 only). | UNVERIFIED |
| R6 | Planner worst-case cost exceeds the illustrative allowance with repairs. Cap repairs at one, or batch. | INFERRED |
| R7 | GPT-6 Astra account access, its image-token formula and strict-mode schema limits. | UNVERIFIED |
| R8 | Sending frames to a model provider changes App Privacy answers and needs consent and retention copy. ADR-0013 targets "Data Not Collected" for v1. | INFERRED conflict |
| R9 | Remotion licensing for a rendering service, and IDC's employee count relative to the 3-employee threshold. | UNVERIFIED |
| R10 | The render host's FFmpeg needs libzimg (HDR) and must not rely on libfreetype. Pin and probe the build. | OBSERVED (local build lacks both) |
| R11 | x264 VBV with threads is non-deterministic; reproducibility tests must use CRF or `threads=1`. | OBSERVED (secondary sources) |
| R12 | Loudness target (LUFS) and fade lengths are taste parameters; measure them, don't assume them. | INFERRED |

---

## Sources

**Repository and local evidence (read 2026-10-07)**

- /Users/IDC2.5/jv/CLAUDE.md; /Users/IDC2.5/jv/GLOSSARY.md; /Users/IDC2.5/jv/docs/spec/ios-v1-spec.md (ClipExporter/Composer, ProcessingQueue, D5); /Users/IDC2.5/jv/docs/adr/0003, 0004, 0007, 0012, 0013
- /Users/IDC2.5/jv/docs/handoff/JON-ORIGINAL-PROMPT.md; /Users/IDC2.5/jv/docs/handoff/studio/README.md, CLAUDE-STUDIO-BRIDGE-PROMPT.md, CLAUDE-STUDIO-EXPANSION-PROMPT.md, ENGINE-BOUNDARY.md
- /Users/IDC2.5/jv/design-reference/studio/brief/backend-media-design.md, implementation-states.md, story-profiles.json, screens.json, source-assessment.md, feasibility-findings.json
- /Users/IDC2.5/jv/.claude/skills/jovra-studio-director, jovra-storycraft (+ references/style-playbook.md), jovra-media-ingest-sync, jovra-edit-plan (+ references/contract.md), jovra-render-delivery, jovra-cloud-production
- /Users/IDC2.5/jv/tools/studio-plan/scripts/validate_edit_plan.py; /Users/IDC2.5/jv/tools/studio-plan/examples/edit-plan.sample.json, story-brief.sample.md
- /Users/IDC2.5/jv/docs/research/technical-feasibility.md §4 and /Users/IDC2.5/jv/docs/research/raw/ios-tech.md §2.4 (export APIs, iOS 26/27 deprecations)
- Founder's editor (read-only): /Users/IDC2.5/Desktop/you-link-x/garnet-remotion/PIPELINE.md, production_preview.py, README.md, package.json
- Apple iOS 26.5 SDK headers on this machine: `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk/System/Library/Frameworks/AVFoundation.framework/Headers/` (AVCompositionTrack.h, AVComposition.h, AVVideoComposition.h, AVVideoCompositing.h, AVAssetExportSession.h, AVAssetWriter.h, AVAssetReaderOutput.h, AVAssetImageGenerator.h, AVAudioMix.h, AVAudioProcessingSettings.h, AVVideoSettings.h, AVOutputSettingsAssistant.h, AVAnimation.h) and `.../usr/lib/swift/AVFoundation.swiftmodule/arm64e-apple-ios.swiftinterface`
- Local FFmpeg 9.0.1 (`/opt/homebrew/bin/ffmpeg`): `ffmpeg -h filter=…`, `-h long`, `-buildconf`, `-encoders`, `-muxers` output
- `claude-api` skill (bundled, model table cached 2026-09-25): shared/model-migration.md (Migrating to Claude Opus 5.5), shared/prompt-caching.md, shared/tool-use-concepts.md (Structured Outputs), python/claude-api/batches.md

**Web (fetched or searched 2026-10-07; treated as data)**

- Anthropic, Vision: https://platform.claude.com/docs/en/build-with-claude/vision
- Anthropic, Pricing: https://platform.claude.com/docs/en/about-claude/pricing
- Anthropic, Batch processing: https://platform.claude.com/docs/en/build-with-claude/batch-processing
- Anthropic, Files API: https://platform.claude.com/docs/en/build-with-claude/files
- Anthropic, Structured outputs: https://platform.claude.com/docs/en/build-with-claude/structured-outputs
- Anthropic, Prompt caching: https://platform.claude.com/docs/en/build-with-claude/prompt-caching
- OpenAI, GPT-6 Astra model page: https://developers.openai.com/api/docs/models/gpt-6-astra
- OpenAI, Models: https://developers.openai.com/api/docs/models
- OpenAI, Images and vision: https://developers.openai.com/api/docs/guides/images-vision
- OpenAI, Structured outputs: https://developers.openai.com/api/docs/guides/structured-outputs
- OpenAI, GPT-6 Astra announcement (HTTP 403 to fetch; cited via Wikipedia's external link): https://openai.com/index/gpt-6-astra/
- Wikipedia, GPT-6 Astra: https://en.wikipedia.org/wiki/GPT-6_Astra
- CNBC (search-result summary; article body returned 403): https://www.cnbc.com/2026/09/03/open-ai-astra-gpt-6-cyber.html
- Axios (search-result summary): https://www.axios.com/2026/09/03/openai-astra-gpt-6-agi-brockman
- FFmpeg documentation (option-from-file syntax): https://ffmpeg.org/ffmpeg.html; filters reference: https://ffmpeg.org/ffmpeg-filters.html
- x264 determinism and VBV: https://mailman.videolan.org/pipermail/x264-devel/2015-April/011035.html ; https://forum.doom9.org/archive/index.php/t-144548.html ; https://forum.doom9.org/archive/index.php/t-129887.html
- Remotion license: https://github.com/remotion-dev/remotion/blob/main/LICENSE.md (pricing at https://remotion.pro/license); renderMedia(): https://www.remotion.dev/docs/renderer/render-media
- YouTube recommended upload encoding settings: https://support.google.com/youtube/answer/1722171
- W3C WCAG 2.2 Understanding 2.3.1 Three Flashes or Below Threshold: https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold.html
- RFC 8785 JSON Canonicalization Scheme (cited standard, not re-fetched): https://www.rfc-editor.org/rfc/rfc8785
- Apple documentation pages for the APIs above (the local SDK headers were the primary evidence; these pages were not re-fetched in this pass): https://developer.apple.com/documentation/avfoundation/avmutablecompositiontrack ; https://developer.apple.com/documentation/avfoundation/avvideocomposition ; https://developer.apple.com/documentation/avfoundation/avvideocompositioncoreanimationtool ; https://developer.apple.com/documentation/avfoundation/avvideocompositing ; https://developer.apple.com/documentation/avfoundation/avassetexportsession ; https://developer.apple.com/documentation/avfoundation/avassetwriter ; https://developer.apple.com/documentation/avfoundation/avassetreader ; https://developer.apple.com/documentation/uikit/uiaccessibility/isreducemotionenabled ; https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask
