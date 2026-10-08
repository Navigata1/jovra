# Studio films: a planner proposes, code validates, a deterministic renderer executes

Status: accepted (2026-10-07).

A JOVRA Studio film is made in three separate roles that never collapse into one:

1. **Planner** (ADR-0016) proposes a **story plan**. The plan holds only IDs and fixed choices: keeper, angle, note and
   stat IDs, one of the allowlisted operations, an enum treatment and catalog text templates. The planner never writes
   frame numbers, score digits, metric values, quotes, file paths, URLs, shell commands or filter strings.
2. **Code** validates the story plan against the trusted project lock (source manifest, sync map, point-event
   revision, story profile version and output spec). It then compiles the plan into a typed **edit decision list**
   (EDL, `jovra.edit-plan/2`): exact rational source windows bound to source hashes, output frame placement, audio
   routes, and overlays that reference stored point and metric records. Validation runs before any rendering or
   spend. Unsupported beats are omitted and reported, never approximated.
3. A deterministic **renderer** executes only the validated EDL. Its display values (scores, stats, dates,
   provenance labels) come from stored events through the same derivation as the app (ADR-0003, ADR-0004).

**Model output is data, never code.** Nothing a model returns is executed, interpolated into a command line or
filtergraph, or used as a path, URL or price.

**Renderers, in order.**
- **S1: on the device.** AVFoundation renders the film: a composition, Core Animation overlays, the reader-to-writer
  path for the final H.264 film, and export-session previews. The renderer branches between the iOS 26
  `AVVideoComposition.Configuration` API and the deprecated mutable classes for the iOS 18 floor (ADR-0007). The S1
  planner is the deterministic heuristic planner, so no model call and no upload are needed.
- **S4: cloud worker.** FFmpeg runs from fixed per-operation filtergraph templates filled only with validated numbers,
  passed as a file. The FFmpeg build is pinned and probed at startup; the local 9.0.1 build lacks `drawtext` and
  `zscale` (OBSERVED, film-engine §3). Only after Jon's Remotion licence decision does Remotion render a transparent
  graphics layer that FFmpeg overlays; until then the cloud slice is FFmpeg-only (see Consequences). The worker runs on
  a separate container host, not in a Worker isolate.

**Shared rules for every renderer.**
- The operation set is a closed allowlist. In the shipped contract `jovra.edit-plan/2` (`spec/studio/README.md`) it
  is expressed as fields, not as one flat list:
  - segment `op`: `live`, `broll`, `replay`, `freeze`, `title-card` (the "card" operation);
  - `transitionIn.type` per segment: `cut`, `dissolve`, `dip` (the "transition" operation);
  - `overlayRefs[].kind`: `score`, `metric`, `note`, `cue`, `annotation` (the "overlay" operation; references to
    stored records resolved against a trusted reference catalog, never values);
  - `framing.mode`: `fill`, `letterbox`, `reframe` (reframe only from a reviewed action-safe box);
  - `grade.presetId` from the profile's list (`none`, `warm-court-1`);
  - `audio.bed[].route`: `primary-bed`, `alt-bed`, `hold-bed`, `silence`; optional lanes `audio.music` (stored rights
    record) and `audio.narration` (stored consent; generated voice labelled).
  `broll` was missing from this ADR's first list and is added: Court Memories needs real non-point footage. An
  operation is enabled in product only once its validator rule and fixture test exist; the stage at which each is
  enabled is the spec's SD6b. The contract can describe operations that are not yet enabled in product (the Rally
  Pulse fixture already carries a moving reframe and rights-bound music), and the profile grammar plus the stage
  allowlist decide what an app accepts.
- **Clean-frame rule:** a replay at speed *s* is allowed only if `sourceFPS × s ≥ outputFPS`. No interpolated frames
  are ever made.
- One continuous primary court audio bed plays during live action. Replays and freezes sit over real dead time
  between points.
- A film is **ready** only after it passes a full decode with exact frame count, PTS grid, audio sample count,
  boundary-frame mapping, provenance checks and atomic custody. A process that exited successfully is not ready.
- Both renderers, and Android later, must reproduce the same barcode-and-click conformance fixtures frame for frame.
- A pure `cleanAlternate(edl)` gives the Reduce Motion version the same cuts with no motion effects.

## Considered Options

- **Let the model emit FFmpeg commands or a Remotion script.** Rejected. It is shell or code injection by design and
  cannot be validated against sources.
- **Send the skill Markdown to a Worker and let it "make the film."** Rejected. ENGINE-BOUNDARY.md: "None of those
  roles can be replaced by 'send the Markdown to a Worker'."
- **Cloud-first rendering.** Rejected. It makes the core experience depend on network and money, and S1 must work
  offline with a free film.
- **Reuse the founder's editor (`garnet-remotion`) directly.** Rejected. It requires constant-frame, same-dimension
  sources with no rotation, rejects iPhone-timescale clips, and takes audio per cut (OBSERVED, multicam-sync §6).
  Instead, a JOVRA adapter copies its patterns (plan-hash binding, pinned sources, full decode, custody) behind a
  normalization stage. The editor itself stays read-only and unmodified.

## Consequences

The iOS 18 composition branch is **unverified locally**, because only the iOS 26.5 simulator exists (ADR-0007).
Cloud Remotion renders wait on Jon's licence decision. The free licence covers companies of up to 3 people,
contractors count from 5.0, and Automators costs $0.01 per render with a $100/month minimum (OBSERVED,
backend-architecture F9). Until then, the first cloud slice is FFmpeg-only. Corrections to point events mark existing
film revisions stale; they are never silently re-rendered.

Sources: `docs/handoff/studio/ENGINE-BOUNDARY.md`; `docs/research/studio/film-engine.md` §§0–4, 7;
`.claude/skills/jovra-edit-plan/SKILL.md`; https://developer.apple.com/documentation/avfoundation/avvideocomposition ;
https://developer.apple.com/documentation/avfoundation/avassetwriter ; https://ffmpeg.org/ffmpeg-filters.html ;
https://www.remotion.dev/docs/renderer/render-media ; https://github.com/remotion-dev/remotion/blob/main/LICENSE.md ;
https://www.remotion.pro/license .
