---
module: planner
reference: [spec/reference/studio/director.py, spec/reference/studio/planner.py]
cases: [spec/reference/studio/cases/planner_cases.py]
kinds: [director, planner]
coverage: covered
swift: pending
kotlin: pending
---

# Planner: StoryDirector and the RulesPlanner

`spec/reference/studio/director.py` is the reference for `StoryDirector`: the story brief for one profile and the
player's options, the card text catalog and the grammar lint. `spec/reference/studio/planner.py` is the reference for
the `RulesPlanner` (contract planner kind `heuristic`, the default and always the fallback, ADR-0016 and SD18) and for
the trust check every story plan passes before it is compiled, whichever planner wrote it.
`spec/reference/studio/cases/planner_cases.py` writes the `director` and `planner` vectors and registers their checkers
and one self-test. `python3 scripts/spec/validate_studio.py --list` prints the current case counts and the Swift and
Kotlin status. Swift ticket S37 flips `swift:` here when its tests reproduce every vector of both kinds; the TypeScript
server copy (S88) and the Kotlin port (A75) reproduce the same vectors.

The story plan is the `jovra.story-brief/1` document (the shipped contract kept that name; GLOSSARY "Story plan"). The
director fills its header and the planner fills `beats`, `comparisons`, `omitted` and `unresolved`. Compiling a plan to
a `jovra.edit-plan/2` is the compiler's job (S07); nothing here computes frames.

## The planning context

Plain data the app assembles from its stores; a vector file stores it once and each case patches it. Fields:

| Field | Meaning |
|---|---|
| `projectId`, `sample`, `bindings` | The project, its Sample flag, and the event, sync, keeper-catalog and B-roll-catalog revisions a plan binds to |
| `coverageSeconds` | Whole seconds of the primary angle's usable match coverage (sync pieces `reference` or `reviewed`) |
| `primaryHasAudio`, `juniorMode` | SD5 inputs |
| `pointCoverageComplete` | Whether the kept points cover the whole match (a final score card needs it) |
| `keepers` | Keepers in the `keepers.rank` shape (`keeperId`, `origin`, `eventRefs`, `session`, `markIds`, `lessonClipIds`, `facts`) plus `slots` (the angles with a view, primary first), `selection` and `provenance` |
| `brolls` | `brollId`, the chapter the player marked it for (`arrival`, `preparation`, `after`), `durationMs`, `depictsThisMatch`, `revealsLocation` |
| `references` | The reference catalog: `refId`, `kind`, `provenance` |
| `notes` | Stored notes a card may show: `noteId`, `use` (`goal`, `drill`, `next`, `players`, `caption`, `dedication`, `lesson`) and the lesson date |
| `lessons` | `lessonId`, `date`, the lesson's stored `noteIds` |
| `cues`, `annotations` | Each with the keeper it belongs to (a cue through its observation's point, else its clip) and the cue's provenance |
| `progress` | The Progress Story stat: `statId`, `statDefinitionId`, the `earlier` and `later` scopes `progress.compare` takes, the session `dates` of the dated keepers and the `selectionRule` (or null) |
| `rights`, `consents` | Music rights records and participant consents |

The Sample context is projected from the Sample records by `sample_context` in the cases module, plus a few Sample
facts no record carries (rally lengths, the k-02 break point, note uses, B-roll chapters, the dates of the dated
examples, the annotation's keeper); they are named `SAMPLE_*` there and are fictional like every fixture.

## StoryDirector

### `brief(profiles, context, profileId, options)`

Returns `{"brief": <story-brief header>, "directions": {...}}`, or `{"refusal": {code, message}}`, or raises a typed
rejection for an option that is not offered.

| Option | Values | Brief |
|---|---|---|
| `length` | `3min` (180 s), `5min` (300 s), `full` | `durationTargetSeconds`; Full = min(profile maximum, `coverageSeconds`). Default: 5 min when the profile allows it, else 3 min (ST29) |
| `aspect` | `16:9` (default), `9:16` | `aspect`; 9:16 is letterboxed landscape (`directions.framing: letterbox`, SD15) |
| `effects` | `subtle` (default) → `low`, `medium` | `effectIntensity`. Only Rally Pulse offers it; `high` is not in the grammar yet (`optionUnavailable`) |
| `shake`, `keepFullRallies` | false, true | Fixed in this version; any other value is `optionUnavailable` |
| `caption`, `dedication` | a note id of that use | `directions` (a note of another use is `untrustedReference`) |
| `venueVisible`, `blurBystanders` | booleans, default false | `privacy` |
| `audience` | `self`, `coach`, `family`, `private-share` | Default `family` for Court Memories, else `self` |
| `music` | `{assetId}` | Bound to the asset's rights record. A profile without music is `optionUnavailable`; an asset with no rights record leaves `music` null and sets `directions.musicUnavailable` (the planner's court-sound fallback) |
| `narration` | `{voice, consentRecordId}` | Needs the profile's narration and a granted `narration-voice` consent (`noConsent`) |

Also: `primaryAudioPolicy` is `no-audio` in junior mode or when the primary has no audio, else
`continuous-primary-court-audio` (SD5); `cleanAlternate` is true for Rally Pulse and Court Memories; `feelingKey` is
`feeling.next-action`, `feeling.relive-match`, `feeling.worth-keeping`, `feeling.growing-game` or
`feeling.day-mattered`; the planner block is `heuristic`, no model, `jovra-planner@0.1.0`; `briefId` is
`brief-<profile>-<length>`.

Refusals (copy from ST29): no keepers → `noKeepers` "Mark a few moments first"; a length under the profile minimum →
`lengthUnavailable` "Match Broadcast needs at least 5 min."; over the maximum → "Rally Pulse films are up to 3 min.";
longer than the recording → "The recording is shorter than 5 min.".

### Card text catalog (story 157)

A card names a template and at most one stored note; code fills every other slot from stored data.

| Template | Profiles | Note | Other slots |
|---|---|---|---|
| `card.goal` | Coach's Cut, Progress Story | goal | date |
| `card.examples` | Coach's Cut | none | fixed text "Your examples" |
| `card.drill`, `card.next-checkpoint` | Coach's Cut (these two instruct) | drill, next | — |
| `card.match-intro` | Match Broadcast | players | date, format |
| `card.final-score` | Match Broadcast | none | derived score |
| `card.accent` | Rally Pulse | none | date |
| `card.lesson` | Progress Story | lesson | date |
| `card.what-changed` | Progress Story | none | the stored comparison |
| `card.method-change` | Progress Story | none | dates; fixed text "These sessions were counted differently, so they are not compared." |
| `card.not-compared` | Progress Story | none | dates, reason |
| `card.next-goal` | Progress Story | next | — |
| `card.date` | Court Memories | none | date |
| `card.dedication` | Court Memories | dedication | — |

### `lint(profiles, plan, context)`: the bold grammar rules

Every finding is `{"code": "grammarViolation", "rule", "beatId"}` (beat null for a header rule); an empty list passes.

| Rule | Bold rule it checks (film-engine section 6) |
|---|---|
| `duration-range` | The target lies in the profile's duration range |
| `effect-intensity` | Effects above `low` only where offered (Rally Pulse) |
| `music`, `narration` | Music only with a rights record and where the grammar allows it; narration only where allowed and consented |
| `op-not-in-profile` | Each beat's treatment is one of the profile's operations |
| `replay-speed` | Replays at the profile's speeds only; no speed on any other beat |
| `replay-before-live` | A replay comes after the moment's original-speed showing |
| `one-live-showing` | A moment is shown at 1× once |
| `strict-chronology` | Match Broadcast: points in session order, and a replay right after its point (it ends before the next serve) |
| `wide-angle-only` | Match Broadcast: live play stays on the selected wide (primary) angle |
| `overlay-not-allowed` | An overlay's stored provenance meets the profile minimum (an estimated cue is never an instruction title) |
| `card-template` | A card's template belongs to the profile |
| `instruction-without-cue` | Coach's Cut: no drill or checkpoint card without a reviewed cue (story 125) |
| `final-score-incomplete` | Match Broadcast: a final score card only when every point is recorded |
| `broll-not-this-match`, `hidden-location` | Court Memories: B-roll depicts this match; a hidden location stays hidden |
| `comparison-claim` | No "% improvement" wording; a change claim needs Reviewed or Validated on both sides |

Ids that do not resolve are the trust check's concern, so the lint does not guess about them.

## RulesPlanner

### `plan(profiles, briefed, context)`

Returns `{"plan", "estimate": {totalMs, beats: [{beatId, ms}]}, "fallback", "belowMinimum"}` or a refusal. The
director's brief must lint clean; the planner then checks and lints its own plan and rejects itself rather than emit an
invalid one. Each profile ranks its evidence with `keepers.rank` (keepers.md) and places it:

| Profile | Structure (display order) |
|---|---|
| Coach's Cut | goal card → up to three examples: the ranked keepers (reviewed cue, then lesson-linked), then keepers the player chose (`selection: manual`) by time; a cue example adds a paused frame with its annotation and cue and a labelled ½× replay → drill card → next-checkpoint card |
| Match Broadcast | intro card (players note) → every point keeper in match order on the primary angle, each followed by a ½× replay from its second angle when it has one → final score card only with complete point coverage |
| Rally Pulse | the ranked rallies (break, set and match points, then the longest real rallies), always whole, shown in time order: first `opening`, last `payoff`, the top-ranked between them `key-exchange`, others `build` → a static `card.accent` close |
| Progress Story | dated goal card → earliest dated example (with the stat overlay) → lesson cards dated between the examples → latest dated example and its ½× replay → what-changed card (stat overlay) → next goal; `comparisons` holds the `progress.compare` result |
| Court Memories | arrival B-roll (with the caption overlay) → moments in time order (the first ranked moment is the `highlight`, then other chosen keepers) → after B-roll → optional dedication card; no score bug |

Durations are the planner's estimate (the compiler binds exact frames): a live beat is its keeper window, a replay
`min(replayMaxMs, window × speed)`, a freeze 2 s and a card 4 s (each clamped to the profile's range; a Rally Pulse
card is 1.5 s), a B-roll shot at most 6 s. Beats come in atomic groups. Required groups are always kept; optional
groups are added in priority order while the estimate stays within the target; then, only if the estimate is under the
profile minimum, more optional groups are added while it stays within the profile maximum. Nothing is repeated or
stretched. If the estimate is still under the minimum, `belowMinimum` is true and `unresolved` says
"About 2 min 47 s of real material; Coach’s Cut needs at least 3 min. Mark more moments for a longer film."; if it is
only under the target, "About 3 min 5 s of real material, so this film is shorter than 5 min. Nothing is padded."

### Fallbacks (first-class outputs, each listing its omitted ideas)

| Profile | When | Fallback |
|---|---|---|
| Coach's Cut | no reviewed or validated cue on any keeper | `your-examples`: a "Your examples" card and the examples at 1×; no paused cue, replay, drill or checkpoint card; omitted "Reviewed cue" and "Practice drill and next checkpoint" |
| Match Broadcast | no keeper has a second angle | `one-angle-match`: every point on one angle; omitted "Replays from another angle" |
| Rally Pulse | music was asked for without a rights record | `court-sound-highlights`: court sound, effects back to low, static titles; omitted "Licensed music" |
| Progress Story | `progress.compare` finds the sides not comparable | `lesson-chronology`: lesson-linked dated examples and lesson cards by date, a `card.method-change` note (or `card.not-compared` for another reason), no metric and no comparison; omitted "Before and after comparison" with the reason |
| Court Memories | no usable B-roll | `one-camera-excerpts`: the Arrival chapter shrinks to a 4 s date card, no after chapter; omitted "Arrival footage" and "After the match", each with the real reason (story 147): nothing is marked for the chapter, or the marked B-roll "is not from this match", or it "shows where you played, and the venue is hidden" |

Any profile with no keepers is refused ("Mark a few moments first").

### `check(profiles, plan, context)`: the trust check

Strict fields on the plan, each beat and each overlay (`unknownField` for a card carrying its own text,
`missingField`); `projectMismatch`; `staleRevision` when the bindings differ from the context's; `profileMismatch`; a
keeper, B-roll item, angle, note, overlay, card template, music rights record or consent that does not resolve is
`untrustedReference`; a card whose note is missing, of the wrong use or not allowed is `badTemplateSlot`; a beat whose
fields disagree with its treatment (a card naming a keeper) is `treatmentMismatch`. Comparisons are re-derived
(stories 146 and 157): a plan may carry only the comparison `progress.compare` gives for the context's stored
`progress`, equal field for field (strict fields, so a comparison with its own caption is `unknownField`; only its
`comparisonId` label may differ). A comparison with no stored progress, from progress that is not comparable, or with
any number or display text that differs from the derived one is `untrustedReference`.

## Vectors

Both files start with the case `context-sample-court-day`, whose `expect.context` is the Sample planning context. Every
other case runs on that context patched by its `contextPatch` (the RFC 6902 subset in `core.apply_patch`); a `lint` or
`check` case runs on the expected plan of the named planner case (`fromCase`) patched by `planPatch`, or on a Sample
record (`fromRecord`). The checker re-derives the context from the records, so a record change fails the vectors until
they are regenerated.

`director` (ops `context`, `brief`, `templates`, `lint`): Full per profile, default lengths, the two refused lengths, a
short recording, no keepers in each profile, 9:16, junior mode and a silent primary, effects, shake and full rallies,
music and narration with and without rights or consent, caption and venue, unknown options and profiles, the card
catalog, and one lint case per bold rule plus the two Sample briefs.

`planner` (ops `context`, `plan`, `check`): the five profiles × {3 min, 5 min, Full} on the unpatched Sample context
(13 plans; Match Broadcast at 3 min and Rally Pulse at 5 min are lengths the profile refuses), the five fallbacks,
licensed music, no keepers, Court Memories with B-roll marked but unusable (it shows the hidden venue, or is not from
this match; and the same B-roll with the venue shown), the RulesPlanner's own Coach's Cut and Progress Story plans
through the trust check, sixteen refused plans (an unknown keeper, a card with free text, an unknown template, a note
of the wrong use or missing, an angle with no view, an overlay that is not stored, a card naming a keeper, a stale
revision, another project, music without rights, a fabricated comparison number or delta, a comparison with its own
caption, a comparison with no stored progress or across a method change), and the two Sample briefs.

Every case stores `expect` (the reference output) and an `assert` block of hand-derived literals: beat lists as
`role treatment id angle speed` strings, estimates summed from the keeper windows, omitted ideas and their reasons,
unresolved copy,
refusal copy and lint rules. For each plan the checker also validates the plan against `story-brief.schema.json`,
checks every id it names against the context and the card catalog independently of `planner.check`, requires a clean
lint, checks the planner left its input unchanged, and plans the same brief a second time and compares the canonical
JSON bytes (the determinism check). The self-test `planner-matrix` requires one unpatched vector for every profile ×
length that either plans or refuses the length.

## Decisions

- **Two of the fifteen profile × length pairs are refusals, not plans.** ST29 disables lengths outside a profile's
  range with a reason, so Match Broadcast at 3 min and Rally Pulse at 5 min return `lengthUnavailable` with that copy.
- **Full** is the profile maximum bounded by the primary angle's recorded coverage (ST29: "profile range ∩ coverage").
- **The target is a target.** The planner may pass it only to reach the profile minimum with real material, and never
  pads: a short film says so in `unresolved` and sets `belowMinimum`.
- **Coach's Cut needs a reviewed (or validated) cue** for instruction (story 125, GLOSSARY "Cue"); a manual cue alone
  gives "Your examples". Examples beyond the ranked ones are keepers the player chose, never heuristic or estimated
  ones.
- **Rally Pulse shows its rallies in time order**, so the opening never breaks chronology and needs no "Coming up"
  teaser.
- **Court Memories shows no score bug** by default (film-engine 6.5).
- The card catalog, the lint rule ids and the fallback ids live in this reference and on this page, not yet in the
  story-profile contract.

## Findings

- The Sample progress brief (`records/story-brief.progress.json`) shows keeper k-04 only as a ½× replay (`b04`) with no
  original-speed showing before it, which breaks "replays come after the original-speed showing". The lint vector
  `sample-progress-brief-replay-first` records this finding; the record belongs to the records module and is unchanged
  here.

## Not covered yet

- Real stills in the Court Memories fallback: Court Memories' grammar has no `freeze` operation, so the shrunken
  Arrival chapter is a date card. Stills need a profile revision.
- Preparation B-roll and personal-highlight marks beyond the ranked moments; a metric card in Coach's Cut (no Sample
  record links a stat to a keeper); Rally Pulse replays and "Coming up" teasers; Match Broadcast game and set lower
  thirds and chapter cards; seeded-random and user-chosen Progress selections through the planner (the ranking
  supports them).
- Effects `high`, shake and cut rallies, which the grammar does not allow yet.
- The model planner's repair loop and the cloud dual-provider pipeline (S4); only the trust check is shared.
- Exact durations: the compiler (S07) binds frames and checks the profile range on the compiled film.
