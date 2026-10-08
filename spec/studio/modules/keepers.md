---
module: keepers
reference: [spec/reference/studio/keepers.py, spec/reference/studio/staleness.py]
cases: [spec/reference/studio/cases/keepers_cases.py]
kinds: [keepers, staleness]
coverage: covered
swift: pending
kotlin: pending
---

# Keepers: keeper selection, ranking and staleness

`spec/reference/studio/keepers.py` is the reference for `KeeperSelector` (candidates and the per-profile ranking) and
`spec/reference/studio/staleness.py` for staleness propagation (SD20). `spec/reference/studio/cases/keepers_cases.py`
writes the `keepers` and `staleness` vectors and registers their checkers and one self-test.
`python3 scripts/spec/validate_studio.py --list` prints the current case counts and the Swift and Kotlin status. Swift
ticket S35 flips `swift:` here when its tests reproduce every vector of both kinds.

All times are integer microseconds on the session (match) clock. Frames come from the one time-to-frame rule
`floor(t · fps + 1/2)` after mapping the session time through the source's sync transform
(`t_source = (t_session − offset) / rate`).

## Candidates (`keepers.candidates`)

Input, a project: `sessionDurationUs`; `sources` (each `sourceId`, `isPrimary`, `syncState`, `transform` with
`offsetUs` and `rate`, render-proxy `fps` and `frameCount`); `points` (each `eventId`, `index`, `startUs`, `endUs`,
`rallyLength`, `provenance`, `breakPoint`, `setPoint`, `matchPoint` and the angle `sourceId` it was scored from, or
null); `shots` (`eventId`, `atUs`, `provenance`); `marks` (`markId`, `atUs`, `note`); `lessonClips` (`clipId`,
`lessonId`, and an `eventId` or a session `window`). `points_from_fold` turns a core fold (`jovra_ref.scoring.fold`)
into point inputs: every point slot that is a played point before the match ended, with the fold's rally length,
outcome provenance and pressure flags (break point; set point or match point for either side).

- **One keeper per effective point** (story 102). Voided and superseded events are already resolved by the fold, so a
  voided point is never a keeper. Keeper ids are `k-` plus the event, Mark or clip id.
- **Cross-angle dedupe** (story 107). Points are merged by session event id: the same point scored from Camera 1 and
  from Camera 2 is one keeper whose window is the union of both, `seenFrom` lists both angles, and its facts come from
  the stronger provenance (`validated > reviewed > manual > estimated`; the first listed on a tie). Two different event
  ids are never merged, whatever their times.
- **Windows** (story 104). The point plus the default pre-roll 1.5 s and post-roll 2.5 s, widened first to cover every
  contact's protected window, and clamped to `[0, sessionDurationUs]`.
- **Views.** A source offers a view only when its sync piece is `reference` or `reviewed` (as the trusted EDL context
  requires) and its recording covers the whole window; the view is the window in render-proxy frames. The project's
  primary source is the primary view when it has one, else the first view in source order.
- **Contacts.** Reviewed, validated and manual shots are contacts that protect `[t − 0.25 s, t + 0.25 s)` (15 frames
  at 60 fps, as the Sample plans protect). An estimated hit inside one of those windows is absorbed, so the reviewed
  window is never narrowed or moved; any other estimated hit stays, labelled `Estimated`, with the same protection.
  Each contact also lists its frame on every view.
- **Marks.** A Mark inside a point's recorded time belongs to that point's keeper (the same moment counted once);
  any other Mark is its own keeper with the default rolls.
- **Lesson clips.** A clip on a point links to that point's keeper; a clip with its own window is its own keeper; a
  clip with neither, and a shot for an unknown event, is reported in `unplaced` with a reason.
- Output order: session start, then point, Mark, lesson clip, then keeper id.

## Ranking (`keepers.rank`)

`rank(profileId, keepers, options)` returns `order` (items `{kind, id, chapter}`), `label`, `fallback` and `missing`.
An `excluded` keeper is never offered by any profile (story 108), and `limit` keeps the head of the order.

| Profile | Rule |
|---|---|
| Rally Pulse | Point keepers that were a break, set or match point, then the longest real rallies (a rally length a person entered or reviewed; an estimated length is not real); ties by point order |
| Coach's Cut | Keepers linked to a reviewed or validated cue first, then keepers linked to a lesson clip; by time |
| Match Broadcast | Every point keeper, in point order |
| Progress Story | Dated examples (`options.dates`) with `selectionRule` `all` (every dated example), `seeded-random` (`count` picked by a Fisher–Yates shuffle with the core sample's SplitMix64 and `seed`) or `user-chosen` (`chosen`, labelled "Examples you chose"), shown by date. With `comparable: false` the order is the lesson-linked examples by date and `fallback: lesson-chronology` (story 137) |
| Court Memories | Chapter `arrival` B-roll, then match moments (keepers with a Mark, a lesson link, or a break, set or match point) by time, then chapter `after` B-roll; `missing` names any empty part (story 120) |

## Staleness (`staleness.propagate`)

The input is the projects' current revisions, plan dependencies and film dependencies, then revision changes applied
in order. `plan_dependencies(plan)` reads a stored edit plan: its `eventRevision`, `syncRevision` and
`keeperCatalogRevision` bindings, every source a segment or the audio bed uses, every keeper a segment names, and the
plan's canonical hash. `film_dependencies(film)` reads a delivered film: the edit-plan hash it was rendered from and
whether it is already stale.

- **Event change** (a point correction): every plan of that project is stale (`event-revision`). Scores, stats and
  keeper windows all come from the whole fold, so no plan of the project is exempt.
- **Sync change** names the sources whose mapping changed: only plans that use one of them are stale
  (`sync-revision`); every other plan of the project is carried to the new sync revision.
- **Keeper change** names the keepers that changed: only plans that use one of them are stale (`keeper-revision`);
  every other plan is carried to the new keeper-catalog revision.
- A plan bound to an older revision than the project's before any change is already stale.
- A **film** is stale when its plan is stale (matched by canonical edit-plan hash) or it already was; it is labelled
  "Made before a correction" and `keptAsVersion` is always true: nothing is deleted or re-rendered.
- **Refusals:** a revision that does not increase (`revisionNotIncreasing`), a film whose plan is not listed
  (`unknownPlan`), a plan bound ahead of its project (`futureRevision`), an unknown project or change kind.

## Vectors

`keepers`: the core Jon vs Alex fold (124 keepers; its Mark lands on point 42), a voided point, default rolls,
clamping, the same point from two angles (one keeper, two views, Camera 3 excluded because its sync needs review), an
angle without coverage, a missing primary angle, reviewed contacts widening the window, an estimated hit inside and
outside a reviewed contact window, Marks, lesson clips and an unknown shot event; then each profile's ranking,
exclusion, a limit, the three selection rules, the chronology fallback, Court Memories chapters and missing parts, and
Match Broadcast and Rally Pulse over the whole Jon vs Alex fold. A `coreFold` input names a core session file (or an
inline setup and log) that the checker folds with the core reference; Swift and Kotlin fold it with their own core.

`staleness`: plans and the film derived from the Sample records (`fromRecord`: the checker re-derives them, so a
changed record fails the vector until it is regenerated) plus hand-written plans: a point correction, a sync change on
Camera 2 and on Camera 1, keeper changes that spare or stale the delivered film, two changes in order, a kept old
version, and two refusals.

Every case stores `expect` (the reference output) and an `assert` block of hand-derived literals (window arithmetic
from the raw log times, the expected view frames, the stale and current plan ids) that the checker compares on its
own. The Rally Pulse case over the fold checks that the 13 break points listed in the core CSV and the match point rank
before every point without pressure, using the core fold's pressure flags, not the keeper facts.

The self-test `keepers-sample-catalog` checks that every view in the Sample keeper catalog lies inside its source's
recording and that the Sample film binds the canonical hash of the final plan (the key staleness uses).

## Decisions

- Contact protection is 0.25 s each side, and estimated hits get the same protection; tune on real footage.
- Event changes stale the whole project rather than only the plans that show a changed point.
- `jovra.delivered-artifact/1` `stale.reason` has no `keeper-revision` value; the vectors report it in their own
  output, and the record schema needs that value before a keeper change can be stored on a film.

## Not covered yet

- `select`, `annotate` and `markBroll` (user edits of the catalog), and turning candidates into a stored
  `jovra.keeper-catalog/1` record.
- Calibration and source-manifest revisions as staleness causes, and the profile revision.
- Ranking rules are in this reference and on this page, not yet in the story-profile contract.
