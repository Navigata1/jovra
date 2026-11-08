---
module: compile
reference: [spec/reference/studio/compile.py]
cases: [spec/reference/studio/cases/compile_cases.py]
kinds: [compile]
coverage: covered
swift: pending
kotlin: pending
---

# Compile: story plan to `jovra.edit-plan/2`

`spec/reference/studio/compile.py` is the reference for the `EDLCompiler`: it turns a validated story plan (the
`jovra.story-brief/1` document any planner writes) and the trusted context into the edit decision list a renderer
executes. `spec/reference/studio/cases/compile_cases.py` writes the `compile` vectors and registers their checker and two
self-tests. `python3 scripts/spec/validate_studio.py --list` prints the current case count and the Swift and Kotlin
status. The Swift compiler flips `swift:` here when its tests reproduce every vector; the TypeScript server copy (S88)
and the Kotlin port (A75) reproduce the same vectors.

The compiler is pure and deterministic. Every EDL it returns has already passed `edl.validate` (edl.md) against the same
trusted context; a plan the validator would refuse is never handed to a renderer. Approving or compiling a plan never
approves spend or publication.

## `compile_plan(profiles, plan, context, request)`

Returns `{"edl", "sha256", "omitted", "notInThisBuild", "gaps", "validation"}`, or `{"refusal": {code, message}}`, or
raises a typed rejection.

1. **Trust first (story 148).** The plan passes `planner.check` (unknown keepers, B-roll, notes, overlays, card
   templates, stale bindings: `untrustedReference`, `staleRevision`, ...) and the grammar lint (`grammarViolation`).
   Its bindings must equal the stored records' current revisions, every overlay must resolve at the current event
   revision, every angle must be a source offered for cutting (`untrustedSource`), and a cut window that crosses a
   recording gap is `outsideCoverage`.
2. **Choose what can be made.** Each beat's operation must be enabled by the context's stage and supported by the
   renderer; otherwise the beat is omitted and listed. A replay whose original was omitted is omitted
   (`originalOmitted`). A final score card over a recording gap is omitted (`coverageIncomplete`, story 128).
3. **Output clock and size.** Then segments, recording-gap cards, the profile range, chapters and the audio bed.
4. **Assemble, validate, hash.** The EDL is canonical JSON (sorted keys, no floats; `core.canonical_bytes`) and
   `sha256` is its canonical SHA-256 (`core.canonical_sha256`), the hash a render receipt binds.

### The compile context

The planning context (planner.md) plus four keys, all built from stored records:

| Key | Meaning |
|---|---|
| `edl` | The trusted EDL context `bundle.edl_context` builds (edl.md): current revisions, the sources offered for cutting with their proxy snapshot and coverage, stored contacts, the reference catalog with event revision and point windows, consents and rights |
| `media` | `primarySourceId`, `slots` (angle slot to source), `views` (each keeper's stored view window per source) and `brolls` (each B-roll item's source and window) |
| `stage` | `S1` or `S2`, the app's stage allowlist (SD6b) |
| `renderer` | `supportedOps`: the SD6b operations this renderer build can execute |

### The request

| Key | Meaning |
|---|---|
| `fps` | `{num, den}`; default below |
| `width`, `height` | An even size of the plan's aspect; default below |
| `planId` | Default `film-<briefId without brief->` |
| `trims` | `{beatId: {inFrame, outFrame}}`: the player's storyboard trims (ST storyboard `JogStrip`), source frames inside the beat's trusted window; outside it is `trimOutsideWindow` |

Any other key is `unknownField`.

## Operations: the stage allowlist and the renderer's set

SD6b names map onto the contract: `live`, `broll`, `replay`, `freeze`, `card` (segment op `title-card`); `transition`
(`transitionIn`); `overlay` (`overlayRefs`); `grade` (`grade.presetId`); `primary-bed`, `hold-bed`, `alt-bed`, `silence`
(`audio.bed[].route`); `reframe` (`framing.mode`); `music`, `narration` (the audio lanes).

| Stage | Enables |
|---|---|
| `S1` | `live`, `broll`, `replay`, `freeze`, `card`, `transition`, `overlay`, `grade` (`none` only), `primary-bed`, `hold-bed`, `silence`; one angle (the primary) |
| `S2` | S1 plus `alt-bed`, a second angle for `live`, `replay` and `freeze` (`multi-angle`), and `grade: warm-court-1` |

`reframe`, `music` and `narration` are S5 and not compiled yet: a plan's music or narration lane is omitted and listed.

Omission reasons, each listed in `omitted` as `{beatId, op, reason}` (`beatId` null for a film-level item):

| Reason | When |
|---|---|
| `notInThisStage` | The stage has not enabled the operation (`op` names it; `multi-angle` for a non-primary angle at S1; `grade` with `preset`) |
| `notInThisBuild` | The renderer does not support it. `notInThisBuild` in the result lists these operations, so a renderer that is still being built renders an honest subset |
| `cleanFrame` | A slow replay whose source fps × speed is below the output fps; `fallback: originalSpeedFallback` (the moment plays at original speed only; ST30) |
| `originalOmitted` | A replay whose live original is omitted |
| `coverageIncomplete` | A final score card over a recording gap |
| overlay omissions | `op: overlay` with `overlay: "<kind>:<refId>"` |

A build without `live` or `silence` cannot render any film: `rendererIncomplete`. Omitted title beats are not replaced;
the film still validates, or is refused below.

## Output clock and size

- **Frame rate.** The default is the primary's capture rate (its render proxy's fps), lowered to the slowest source
  the film moves through (live, replay or B-roll), so the film never runs above a source's rate. A requested rate above
  any such source is refused: `fpsAboveSource`, "A 60 fps film would repeat frames: broll-1 was recorded at 30 fps."
  The default can make a slow replay unclean: at 60 fps output a ½× replay of 60 fps footage is omitted (`cleanFrame`).
- **Size (no upscale).** 16:9: the primary's own size when it is 16:9 (a 1280×720 primary gives a 1280×720 film), else
  the 16:9 frame of its height. 9:16: that size turned on its side, so the landscape picture is letterboxed (SD15)
  without enlarging it. A requested size, or a default, that would enlarge any source the film shows is refused:
  `upscaleRefused`, "A 1920x1080 film from a 1280x720 recording would only enlarge it, which adds no detail. The film can
  be at most 1280x720."
- **Framing.** `fill` when a source's aspect equals the output's, else `letterbox`. No `reframe` (S5).

## Segments: PTS snapping

All boundaries are on real proxy frames and every length is exact on the output clock.

- **Live.** The keeper's stored view on the beat's angle, inside the keeper's session window mapped onto that source
  through the trusted coverage with the one half-up time → frame rule (`core.frame_at_us`, SD7), or the player's trim.
  Its length is the most whole output frames whose source span is a whole number of source frames (and, under a court
  bed, of primary frames), so `source seconds = output seconds × speed` holds exactly. Every stored contact inside it
  gets a protected window of ±0.25 s (15 frames at 60 fps) clipped to the segment; `sessionInUs` is the session time of
  its first frame, half up.
- **Replay** (½× or ¼×, the planner's choice). Allowed only under the clean-frame rule. The window lies inside the
  session time its live original showed (mapped onto the replay's angle with ceiling and floor, so it never leaves it)
  and inside the keeper's view there; it is at most `replayMaxMs` of output, centred on the middle stored contact of
  the original window (its middle frame when it has none), and labelled `label.replay`.
- **Freeze.** The middle stored contact of the keeper's window on that angle (else its middle frame), held 2 s within
  the profile's `freezeMs`, labelled `label.paused`.
- **Card.** 4 s within the profile's `cardMs` (Rally Pulse 1.5 s), rounded half up and kept inside the range. The text
  is the beat's stored note (`textRefs`) or the template's own fixed text; nothing else.
- **B-roll.** The middle 6 s of the stored item window (the planner's B-roll bound), or the player's trim.
- **Transitions.** Every boundary is a cut in this version (dissolves and dips are allowed by S1 but not proposed yet).

## Recording gaps (stories 127 and 128)

A recording gap is a boundary between two coverage intervals of a source (a restart). In a strict-chronology profile
(Match Broadcast), when two consecutive live segments on one source lie on either side of a restart, a
`card.recording-gap` card (4 s) goes before the later one; `gaps` lists it with its length, derived from the coverage
(`next interval's session start − previous interval's session end`) and shown as "Recording gap · 1:00". A gap is never
closed up: without cards in this build the film is refused (`gapNotShown`). A final score card is compiled only when
the planning context says point coverage is complete and the primary has no recording gap. Other profiles are excerpts
in their own order and get no gap card; their windows still never cross a gap.

## Profile range

The compiled length must lie in the profile's `durationSeconds`. Below it: `belowProfileMinimum`, "About 4 min 44 s of
real material; Match Broadcast needs at least 5 min. Mark more moments for a longer film."; above it:
`aboveProfileMaximum`. A plan with no live or B-roll segment left is `noRelevantKeepers`. Nothing is padded.

## Chapters

A beat role opens a chapter; other roles continue the open one; the first chapter starts at frame 0.

| Profile | Chapters |
|---|---|
| Coach's Cut | `chapter.goal` (goal or "Your examples" card), `chapter.example` at every example, `chapter.practice` (drill, checkpoint) |
| Match Broadcast | `chapter.intro`, `chapter.games` (points, replays, gap cards), `chapter.final` |
| Rally Pulse | none |
| Progress Story | `chapter.goal`, `chapter.before`, `chapter.lessons`, `chapter.recent`, `chapter.what-changed`, `chapter.next` |
| Court Memories | `chapter.arrival`, `chapter.match` (moments and highlight), `chapter.after`, `chapter.dedication` |

Ids are `ch-<name>`, then `ch-<name>-2`, … for a repeated chapter.

## Audio bed

One route per output frame; every piece fades 20 ms in and out, so every switch at a cut meets the validator.

- With `primaryAudioPolicy: no-audio` (junior mode, SD5) or a silent primary, the bed is silence and names no primary
  source. If the stage or renderer lacks `primary-bed`, the same, and `primary-bed` is listed.
- **Live:** `primary-bed` from the primary at the frame that shows the segment's first session time (half up), in sync
  through the session clock. Where the primary does not cover the moment, `alt-bed` from the segment's own (reviewed)
  angle where the stage enables it; otherwise `noCourtAudio`.
- **Replay, freeze or card:** `hold-bed` continuing the primary without a jump, only over real dead time: inside the
  same coverage interval, shown by no live segment, and inside no other keeper's session (the keepers are the only
  play the context knows). Otherwise silence. A renderer without `hold-bed` gets silence there, and `hold-bed` is
  listed (`notInThisBuild`).
- **B-roll:** its own sound as `alt-bed` where the stage enables it and the source has audio; otherwise silence.
- Consecutive silent pieces merge.

## Vectors

`vectors/compile.json` starts with five `context` cases: the sample-court-day compile context (stage S2, every
operation supported) and a fictional one-camera recording (20 minutes, eight 60 s points, a reviewed cue on k-02) at
60 fps, at 30 fps, at 1280×720, and restarted at 10:00 with a one-minute gap (each stage S1). Every other case names
its base context, a `contextPatch`, `planFrom` (the RulesPlanner with `profileId` and `options`, or a Sample record,
each with an optional `planPatch`) and stores the plan inline with the request.

Cases: the profile × {3 min, 5 min, Full} matrix on the Sample context at 30 fps (13 EDLs; Match Broadcast at 3 min and
Rally Pulse at 5 min are lengths the planner refuses); Coach's Cut at S1 (byte-identical to S2) and Match Broadcast at
S1 (its far-baseline replays omitted, then under 5 min and refused); the default clock (60 fps for Coach's Cut, which
omits its replay and is refused under 3 min; 30 fps for Court Memories because its B-roll is 30 fps); `fpsAboveSource`
twice; a ½× replay from 30 fps and from 60 fps footage at 30 fps output; `upscaleRefused` and the 1280×720 default; the
restarted and the whole one-camera Match Broadcast; a card whose hold-bed would run into another kept point (silence
instead); renderers without cards, replays, overlays, hold-bed or live play; junior mode; the final Court Memories film
and the same edits at S1; and four rejections (a trim outside its window, an unknown keeper, a stale event revision, a
window across a recording gap) plus an unknown request field.

Every case stores `expect` (the reference output) and a hand-derived `assert` block: the cut list as
`op source in-out output` strings, bed pieces as `route source@frame output`, total frames, clock, size, grade,
chapters, omissions and refusal copy, worked from the keeper windows above the cases. For every compiled case the
checker also validates the EDL with `edl.validate` and the edit-plan schema, checks every live window against its
keeper's view and every B-roll window against its item (independently of the compiler), checks card text is stored
notes only, re-makes the plan from `planFrom`, checks the compiler left its input unchanged, and compiles a second time
and compares the canonical bytes and sha256 (the determinism check). Self-tests: `compile-matrix` (every profile ×
length compiles or is a refused length) and `compile-mutations` (a compiled EDL shifted by one frame, with its replay
label dropped, or bound to a stale event revision fails `edl.validate`).

## Decisions

- **The Sample context is stage S2.** The sample-court-day project is a multi-camera recording; S1 enforcement is
  pinned by the S1 cases and the one-camera recording.
- **Output fps follows the source, not the profile.** The film-engine time model (§2.1): an output rate above a
  source's is refused, never filled with repeated frames.
- **Cuts only.** Transitions need handles and contact checks the planner does not propose yet.
- **`card.recording-gap`** is a compiler card, not a planner card: no planner can place or omit it.

## Findings

- `story-brief.court-memories.json` has four beats; the final film `edit-plan.court-memories-final.json` (revision 2)
  has five (k-03 is added) and trimmed windows (B-roll 42 s and 75 s, above the planner's 6 s shot bound). The brief
  alone cannot reproduce 42 + 141 + 75 s. The vector `court-memories-final-film` applies the storyboard edits the record
  does not carry (k-03 added as `planPatch`, five `trims`); the compiled cut list and chapters then equal the record's.
  The records belong to the records module and are unchanged here.
- With the default clock (the primary's 60 fps), Coach's Cut on the Sample loses its ½× replay to the clean-frame rule
  and falls under 3 min. The Sample films use 30 fps output, as S1's acceptance does.

## Not covered yet

- `reframe`, `music` and `narration` (S5); dissolves, dips and J/L cuts; Match Broadcast dead-time compression,
  changeover score cards and game chapters; a live keeper split at a restart (such a window is rejected).
- Hold-bed dead time knows only the keepers; points nobody kept are not in the compile context yet.
- Real media: nothing here reads footage. Barcode and click verification of a rendered film is the renderer's and the
  verifier's (S08, STU-12).
