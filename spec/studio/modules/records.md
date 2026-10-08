---
module: records
reference: [spec/reference/studio/records.py, spec/reference/studio/generate_studio_records.py]
cases: [spec/reference/studio/cases/records_cases.py]
kinds: [jovra.project-lock/1, jovra.source-manifest/1, jovra.observation/1, jovra.keeper-catalog/1, jovra.broll-catalog/1, jovra.story-profile-catalog/1, jovra.story-brief/1, jovra.reference-catalog/1, jovra.delivered-artifact/1, jovra.lesson/1, jovra.camera-invite/1, jovra.storage-providers/1]
coverage: covered
swift: pending
kotlin: pending
---

# Records: the Studio records and their reference rules

`spec/reference/studio/records.py` holds the semantic rules for the records below (beyond what each schema checks),
and `spec/reference/studio/cases/records_cases.py` writes the Sample project's records and their invalid cases. The
profile catalog (`jovra.story-profile-catalog/1`) is the shipped contract
`spec/studio/contracts/story-profiles.v1.json`. `python3 scripts/spec/validate_studio.py --list` prints the current
case count of every kind below and its Swift and Kotlin status.

| Schema | Record | What the reference adds beyond the schema |
|---|---|---|
| `project-lock` | Frozen inputs: manifest revision and canonical hash, event/sync revisions, profile and revision, output, participants and rights, privacy, quote authorization, brand tokens (const) | Demo projects use the demo profile, never reserve and never upload; cloud consent needs a record and a recording acknowledgement; a hidden location hides the venue; the lock hash equals the manifest (bundle) |
| `source-manifest` | Per source: hash, size, container, duration, rational timescale and start PTS, frame count, nominal fps, VFR flag, codec, dimensions, rotation, pixel aspect, colour/HDR, audio, lens, capture hints (wall clock, room offset and round trip, `fileZeroHostNs`), segments and restarts, analysis/render proxies with PTS-table hashes, verification | One primary, at most six match sources, unique slots; HDR implies HLG/PQ; segments add up; journalled host times increase; render proxies bake rotation once (and swap dimensions) and tone-map HDR |
| `observation` | Kind, source time, session time, sync/event revision, capability and version, provenance (producer, confidence, calibration dependency, benchmark), status, reviewer | Estimated needs a capability, producer and confidence; manual is a person with no confidence; reviewed names the reviewer; validated needs a benchmark; a calibration-dependent capability without a calibration is rejected; an accepted estimate is refused |
| `keeper-catalog` | Keepers bound to point events at one event revision, with views per source, contact frames, selection and provenance | An event appears in at most one keeper (a second angle is a view); one primary view; contacts inside a view |
| `broll-catalog` | Origin, `depictsThisMatch`, rights (holder, scope, record), disclosure label, location and people | Stock, generated or other-day footage never depicts this match; stock or generated material is labelled and has a rights record |
| `story-profile` | The five profiles, with their text carried over unchanged from `design-reference/studio/brief/story-profiles.json`, plus `exportAudio` (D-1: the Include audio default for files that leave the app, always shown; junior mode forces no audio and no switch) and a versioned machine grammar | Grammar duration equals the recommended range; replay speeds exist only where replays are allowed; an estimated cue is never instruction; Include audio starts on only for Rally Pulse and Court Memories |
| `story-brief` | The planner's proposal (the research's "StoryPlan"): profile/revision, bindings, planner kind and pinned model id, feeling, audience, aspect, audio policy, privacy, beats made of ids and enums, before/after comparisons, omitted ideas | Every beat has evidence (keeper, B-roll item or card template); ops and overlays allowed by the profile; a change claim needs reviewed evidence on both sides and no user-chosen selection; the comparison display is re-derived (`12 / 30 · 40%`, `+20 percentage points`) |
| `reference-catalog` | The trusted index of everything an EDL or brief names by id: score states, points and stats at one event revision, user and lesson notes, cues, annotations (kind, stored provenance, origin), narration consents (participant, scope, granted), music rights (asset, scope) | Unique ids; kind follows the origin; one event revision; bundle: cues and lesson notes carry their lesson's provenance, consents name a ProjectLock participant, brief overlays and notes resolve |
| `delivered-artifact` | Media facts, chapters, captions, full bindings (source hashes, revisions, profile, planner, edit-plan hash, story-brief revision), verification, private delivery and share link, retention, YouTube preparation (`published` const false), stale marker | Chapters tile the film; `passed` needs probe, full decode, frame count, audio and overlay provenance; share links last at most 24 h and only for verified films; demo stays on the device |
| `lesson` | Date, focus, coach, notes, clips, source-linked cues with provenance, practice checklist, next goal, films, sharing | Notes and cues link this lesson's clips; coach notes need a coach; estimated cues come from an observation and are not reviewed; practice status follows done/target (a five-clip goal with three clips saved is valid) |
| `camera-invite` | Roster (one primary plus up to five cameras, each with a slot, status, recording acknowledgement and permissions) and invitations (display code, single use, host approval, TLS fingerprint, at most 10 min) | One primary at the near baseline; cameras never get host controls; ready means joined and acknowledged; invites expire within 10 min, bind one device, never target a filled slot; the demo accepts none |
| `storage-provider-capability` | device, iCloud Drive (Files), Google Drive, Box, Dropbox: status, integration, platforms, operations, credential and folder references, `processing` const false | Unconnected or planned providers claim no operations and hold no credential; iCloud Drive is iOS Files only, with no quota; an OAuth provider is active only when verified and connected; the demo holds no tokens |

The sync map, edit plan, render job, quote and usage reservation have their own module pages.

## Invalid cases the review rounds added

The invalid cases of these records cover, from the first round: readiness without full decode, a 48 h link and
auto-publishing (the delivered film), a laundered cue provenance (a lesson's estimated cue marked reviewed), invite
escalation and storage-provider overclaims. Review round 1 added: an invite accepted 0.5 s after expiry, and
reference-catalog duplicates, kind and revision errors. Review round 2 added: ids and hashes with a trailing newline
(a lesson id, a film's plan hash).

The self-test `records-profile-catalog` (registered in `records_cases.py`) checks that `story-profiles.v1.json` keeps
the defaults and profile text of `design-reference/studio/brief/story-profiles.json` and passes
`records.check_profile_catalog`.

## Decision

- StoryBrief is the planner-facing contract (the research's StoryPlan), so one contract carries one concept.
