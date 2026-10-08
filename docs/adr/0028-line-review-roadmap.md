# Line review: bookmarks and manual notes first; any automated hint needs its own ADR, benchmark and abstention, and never changes the score

Status: accepted (2026-10-07). Keeps the v1 prohibition on line calls unchanged; adds a roadmap for review tooling on
top of it. Applies to phones, tablets, both watches and Studio films.

The adaptive brief imagines four to six cameras and watch "mark for review" buttons around a court, which invites the
assumption that JOVRA can now tell In from Out. It cannot. Line calls are `unsupported` in the v1 capability registry
(`docs/spec/ios-v1-spec.md` capability list; GLOSSARY "Capability status"), shot placement is "entered by tapping in
v1; never a line call" (GLOSSARY "Shot placement"), and CLAUDE.md rule 1 bans officiating-grade line calls (all
OBSERVED). A court homography is valid only for points on the ground, never for a ball in the air (GLOSSARY
"Homography"). More cameras widen coverage; they do not by themselves measure anything: bounce or line classification
needs measured clock alignment, lens and court calibration per view, occlusion handling, annotated representative
footage and uncertainty and latency tests (`CLAUDE-ADAPTIVE-WATCH-PROMPT.md` §Analysis, OBSERVED).

## Decision

**Stage 1, now: evidence markers and the user's own notes.**
- **Mark for review** from the phone (Mark point) or a watch (ADR-0026) creates a source-linked note: point event ID,
  match or session time, the angles and segments that cover it, who marked it, and a receipt. It never pauses
  recording and never alters the score.
- **Review on the phone.** The marked moment opens in replay, multi-angle where a SyncMap exists, with each angle's
  sync state shown (Reviewed, Estimated, or not aligned; ADR-0017). Frame stepping and slow motion are tools for the
  person reviewing, not evidence of a call.
- **Manual call notes.** The user may record their own call as a note ("I called it out", "Let") and may place the
  bounce by tapping, labelled In, Out or Needs review with provenance Manual, exactly as shot placement works today.
  The app never words a manual note as JOVRA's verdict.
- **Score changes stay explicit.** If the players agree a point was scored wrongly, the user corrects that point event;
  the correction is stored beside the original and every later score, stat and export is recomputed (ADR-0003,
  CLAUDE.md rule 4). A review note alone changes nothing.

**Stage 2, later: any automated hint is a new capability with its own ADR.** Before any automatic bounce, In/Out or
"close call" indicator is implemented, even as a hidden experiment shown to users, all of these must exist:
1. **A scoped ADR** naming the capability, the camera configurations it covers, and what it will never claim.
2. **A capability registry entry** (ADR-0004), starting `disabled`, with method and model version, calibration
   dependency and the sync requirement it consumes.
3. **A benchmark plan and run** on representative, annotated real footage (not only synthetic), reporting by
   configuration: false-call rate on close balls (within a stated distance of a line), miss rate, **abstention rate**,
   coverage, latency, and the clock-alignment and calibration error budget it assumes. Promotion to `estimated` or
   `validated` follows ADR-0004's gate rules; `validated` needs the real-footage gate.
4. **Abstention by design.** The hint abstains whenever uncertainty exceeds its benchmarked threshold, the bounce frame
   is occluded or outside calibrated coverage, the angles are not aligned to Reviewed quality, or calibration is
   missing or moved. Abstention shows **"Review needed"** and opens Stage 1 review; it is a normal, frequent outcome,
   not an error.
5. **Presentation rules.** A hint carries its provenance label (Estimated until validated), its uncertainty, the
   angles it used and its age. It is phrased as a hint ("Looks out · Estimated · review"), never as a call. No
   officiating-grade, professional-accuracy, electronic-line-calling, spin or injury wording anywhere.
6. **Never an automatic score change.** A hint can prefill a suggested correction that the user must confirm; the
   confirmed correction is a normal point-event edit with the hint recorded as the automatic suggestion beside the
   user's decision (ADR-0003). No silent update, no auto-accept timer, no watch-initiated change from a hint.

**Watches** show "Marked for review" and "Review needed" states only. A watch never displays an In/Out result, from a
person or a model (ADR-0026).

**What does not move this.** More cameras, higher frame rates, a planner model's description of a frame, or a
demo-looking result on Sample footage do not satisfy Stage 2. Live analysis during capture stays out of scope as well
(ADR-0017).

## Note (2026-10-07): where Stage 1 is specified

No decision changes. Stage 1's surfaces are now specified: on Android, stories 352–356 of `docs/spec/android-v1-spec.md`
(where a watch or phone mark lands, multi-angle review with per-angle sync state, manual call notes and Manual
In/Out/Needs-review bounce placement); on the watches, the "Marked for review" and "Review needed" states of W64/W69
(`docs/spec/adaptive-screens.md`) and watch-spec stories 93–95, fed by the bridge's `reviewNeeded` alert kind
(`spec/room`). The iOS core review surfaces are owned by the core spec (`docs/spec/ios-v1-spec.md`); any change there
is recorded as an open finding, not made here.

## Considered Options

- **Ship an Estimated In/Out badge with a disclaimer.** Rejected: on close balls a disclaimer does not stop a user
  treating it as a call, and the v1 prohibition exists because one camera cannot measure it.
- **Auto-update the score from a confident hint, with undo.** Rejected: it breaks "the score is only as correct as its
  point log", and undo after a disputed point is too late.
- **Never plan for hints.** Rejected: multi-angle evidence is the moat Jon described, and a written gate is what keeps
  a future capability honest instead of improvised.

## Consequences

Stage 1 is buildable now on every platform and is useful on its own: it turns disputed points into reviewable moments.
Stage 2 cannot start without labelled field footage and calibration tooling, which is a separate research capability
(adaptive sequence step A5). The registry entry for line calls stays `unsupported` until a Stage 2 ADR changes it.

Sources: `CLAUDE.md` rule 1 and rule 4; `GLOSSARY.md` (Capability status, Shot placement, Homography);
`docs/spec/ios-v1-spec.md` capability registry list and user stories 88 and 371; `docs/adr/0003`, `0004`, `0017`,
`0026`; `docs/handoff/adaptive-v3/CLAUDE-ADAPTIVE-WATCH-PROMPT.md` (Analysis and line-review roadmap; sequence A5);
`design-reference/adaptive/brief/session-connectivity.md` (Analysis result envelope), `acceptance-matrix.md`.
