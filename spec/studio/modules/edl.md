---
module: edl
reference: [spec/reference/studio/edl.py]
cases: [spec/reference/studio/cases/edl_cases.py]
kinds: [jovra.edit-plan/2, edl-context]
coverage: covered
swift: pending
kotlin: pending
---

# EDL: `jovra.edit-plan/2` and the clean alternate

`spec/reference/studio/edl.py` validates an edit plan against the story profiles and the trusted context, and derives
the clean alternate. `spec/reference/studio/cases/edl_cases.py` writes the `edl-context` vectors and the edit-plan
invalid cases. `python3 scripts/spec/validate_studio.py --list` prints the current case count of every kind below and
its Swift and Kotlin status.

| Schema | Record | What the reference adds beyond the schema |
|---|---|---|
| `edit-plan` | **`jovra.edit-plan/2`** (below) | `edl.validate` (requires the trusted context) |

### `jovra.edit-plan/2` (superset of the starter `/1`)

The starter's rules all still hold: strict fields, a revision binding, contiguous output coverage, source windows
inside coverage, the current event revision on every overlay, and allowlists. The fields it requires are renamed
(`bindings`, `proxy`, `coverage`) and extended. New in v2, each rule enforced by `spec/reference/studio/edl.py`:

- **Segment ops:** `live`, `broll`, `replay`, `freeze` and `title-card`. Live action and B-roll stay at 1×.
  Replays run at 1, ½, ¼ or ⅛ speed, only if the profile allows that speed. Source seconds must equal output seconds
  × speed exactly. Under the **clean-frame rule** (source fps × speed ≥ output fps), no interpolated frames are made,
  so a ½× replay at 30 fps output needs 60 fps capture.
- **Replays** need the `label.replay` label and at most 8 s of output. They must follow the live segment they
  re-show, inside that segment's session interval (any angle). In strict-chronology profiles they come before the
  next live point.
- **Freezes** carry `label.paused` and must last within the profile's range. **Cards** use a `card.*` template and
  text references only.
- **Session binding:** each live segment's `sessionInUs` must equal the sync-map mapping of its first frame.
  Coverage intervals are half-open `[inFrame, outFrame)` and may be adjacent (a restart), so the first frame of a
  restarted interval maps through that interval, never through the previous interval's extrapolated end (the
  `edl-context` vectors pin this with a two-interval Camera 2). Strict profiles (Match Broadcast) keep live segments
  in session order.
- **One live showing per moment:** in every profile, a live segment may not show session time an earlier live
  segment already showed (beyond one source frame of the coarser angle at an angle cut). Showing it again is a
  replay, with the Replay label (`replayWithoutLabel`).
- **Project:** the plan's `projectId` must be the project whose records built the trusted context
  (`projectMismatch`).
- **Transitions:** `cut`, `dissolve` or `dip`, within the profile's allowlist and maximum length. A transition of n
  frames needs n/2 source handle frames on each side inside the same coverage interval, so it never crosses a gap.
  It never touches a protected contact window, and never blends any stored keeper contact on either side (live or
  replay), whatever keeper the plan names. Every stored contact inside a live window must lie in a declared protected
  window, also when `keeperId` is null (`contactUnprotected`).
- **Overlays:** `score`, `metric`, `note`, `cue` and `annotation` are references to stored records, never values.
  Each is bound to the plan's event revision (an older one is `staleRevision`) and must carry a provenance the
  profile allows. At most one annotation is shown at a time. A point's `score` or `metric` (a ReferenceCatalog entry
  whose origin is a point event) is bound to that point's moment: over live, replayed or frozen match play it is
  shown only when the play's session time lies inside the session window of a keeper whose `eventRefs` carry the
  point (`overlayOutsideMoment`; the context carries these windows as `references[refId].pointWindows`, and the
  bundle also checks a live or replayed segment's named keeper). Score states and stats are not bound to one rally.
- **Output and framing:** aspect `16:9`, `9:16`, `1:1` or `4:5`. `fill` only when the aspects match and with no
  upscale. `letterbox` always works. `reframe` only from a reviewed action-safe box, with keyframes in 1/10 000 of
  the frame, matching aspect, at most 2× upscale and a bounded pan speed. Match Broadcast letterboxes.
- **Audio:** exactly one bed route per output frame:
  - `primary-bed` is the designated court source, in sync with every live frame to within half an output frame,
    through the session clock. It sits only under live segments, and so does an `alt-bed` from a match source
    (`courtBedOffLive`): under a replay, freeze, card or B-roll, court audio is `hold-bed` over real dead time, B-roll
    audio, or silence, never unchecked court audio from another moment.
  - `hold-bed` continues the primary without a jump under non-live segments, over real dead time that no live
    segment shows.
  - `alt-bed` is another source's audio, with fades of at least 20 ms.
  - Every change of bed source (to or from an `alt-bed`, the return to the primary, or to or from silence), and every
    jump to another position of the same source, sits on a segment boundary (`bedSwitchNotAtBoundary`). At a cut, each sounding side fades for at least 20 ms. At a
    dissolve or dip, the switch is an audio dip across the picture transition: the outgoing bed fades out over at
    least the transition frames before the boundary and the incoming bed fades in over at least those after it
    (`fadeTooShort`), so two sources' court audio never play at once.
  - `silence` is explicit. An all-silent plan is allowed (for example a junior-mode or silent-source film). A
    no-audio export of a film with sound is not an all-silent plan: it is a separately verified no-audio artifact of
    the same plan (spec D-1; the cloud side is `docs/backend/architecture.md` §9.1, the `remux_no_audio` step).

  Narration is optional and must be consented, ducked by 6–24 dB, grounded in notes and labelled when generated.
  Music needs a rights record covering the private film. Both are allowed only where the profile allows them.
- **Clean alternate:** `cleanAlternate: true` plans may not have dissolves, dips or moving reframes. The validator
  reports `needsCleanAlternate`. `edl.clean_alternate(plan)` derives the alternate (same cuts; dissolves and dips
  become cuts; moving reframes become letterbox), and the fixtures pin two such pairs.
- **No command, path, URL, secret, approval or price field:** these keys are refused by name anywhere, and values
  that look like paths or URLs are refused. Authorization and spend live in RenderJob and UsageReservation.
- **Trusted context (required):** `edl.validate(plan, profiles, context)` refuses to run without the full context
  that `bundle.edl_context` builds from stored records: current revisions; the sources offered for cutting with the
  exact snapshot and coverage the plan must copy (a match source only with a reference or reviewed sync piece;
  `untrustedSource`, `coverageMismatch`); the project id; keeper and B-roll ids; every stored keeper contact by
  source; the ReferenceCatalog. Every overlay `refId`, card
  `textRef` and narration `scriptNoteId` must resolve (`untrustedReference`), with the stored kind (`kindMismatch`)
  and the stored provenance (`provenanceMismatch`); narration needs a stored, granted consent of the right scope and
  music a stored rights record for that asset covering every claimed scope (`consentMissing`, `rightsMissing`). The
  bundle checks also require live windows to lie inside keeper views with every contact protected, and B-roll
  windows to lie inside catalog items.

## Vectors

- EDL against a patched trusted context (4): Camera 2 split into two adjacent coverage intervals (a restart).

## Invalid cases the review rounds added

The edit-plan invalid cases cover, from the first round: executable fields, approval or URL fields, unlabelled
speeds, copied score digits, stale overlay/event/sync revisions, gaps, overruns, forged session time, integral
floats, transitions that are too long, lack handles or cover a contact, court audio that is out of sync or missing
during live play, hold-bed over live or over shown time, alt-bed mid-segment, missing consent or disclosure, music
outside the profile, interpolated slow motion, replays before or outside their original, blind portrait crops, pans
that are too fast and out-of-order points. Review round 1 added: score digits or unknown ids as overlay refs, a
relabelled overlay kind, a re-pointed cue overlay keeping `reviewed`, unresolved card text and narration notes,
self-attested consent and rights, a rights scope overclaim, and forged coverage with matching session time. Review
round 2 added: an unlabelled live re-showing of a moment, contact protection switched off by a null keeper, a plan of
another project, a bed returning to the primary mid-segment, and an alternate bed switching hard at a dissolve.
Review round 3 added: a primary bed returning hard (0 ms fade) at a cut.

The self-tests `edl-context-required` and `edl-schema-refusals` (registered in `edl_cases.py`) check that
`edl.validate` refuses a plan with no or a partial trusted context (`contextMissing`) and a boolean speed
(`badSpeed`), and that the schema refuses an empty plan and a plan with a command field.

## Decisions

- The bed sync tolerance is half an output frame. At the Sample 300 ppm drift, cross-angle primary-bed spans longer
   than about 55 s fail, so the fixtures switch to `alt-bed` at a cut. This is a real constraint, not a fixture
   quirk.
- Proposed grammar numbers (transition maxima of 400/267/200/400/500 ms, freeze and card ranges, ½ and ¼ replays,
   2× reframe upscale, 50 units per frame of pan) are INFERRED from film-engine §6 and must be tuned on footage.

## Not covered yet

- **Rendering:** barcode render-conformance media (film-engine §7), J/L audio cuts, shake, captions content and
  portrait safe-area checks on real frames.
