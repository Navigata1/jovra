# JOVRA Studio contracts (`spec/schemas/studio`, `spec/studio`)

The Studio layer (multi-angle capture, sync, story films, lessons, optional cloud production) follows the core rule
from ADR-0001: iOS, Android and any server share **contracts, not code**. This folder holds versioned JSON Schemas,
shipped contract data, golden fixtures (valid records, deliberately invalid cases and reference vectors) and a
dependency-free Python reference that every implementation must agree with.

Everything here is a **proposal plus checked fixtures**. Nothing in it is a renderer, a live backend, a measured sync
result, a price or a charge. All fixture data is fictional and labelled Sample (implementation-states.md).

```
spec/schemas/studio/          JSON Schema 2020-12, one file per record; studio-common.schema.json holds shared $defs
spec/studio/contracts/        data apps read: story-profiles.v1.json, render-job-transitions.v1.json, credit-classes.v1.json
spec/studio/fixtures/
  records/                    31 valid records for one Sample project (sample-court-day)
  invalid/                    25 files, 168 cases: patches to a valid record that must be rejected
  vectors/                    7 files, 135 cases: sync fits, sound delays, job transitions, ledger, credits, sample
                              truth, EDLs against a patched trusted context (edl-context)
spec/reference/studio/        reference package `studio` (core, edl, syncfit, jobstate, ledger, records, bundle)
                              and the deterministic generator (generate_studio_fixtures.py + _records + _cases)
scripts/spec/validate_studio.py   validates all of the above and re-runs the reference; non-zero exit on any failure
```

Run from the repo root:

```
python3 spec/reference/studio/generate_studio_fixtures.py   # rewrites spec/studio/fixtures (same bytes every run)
python3 scripts/spec/validate_studio.py                      # add -v for detail
```

Current result (2026-10-07, after review round 2): `RESULT: PASS`, with 20 schemas (ECMA-262 pattern anchors), 31
records, 15 cross-record mutations rejected, 168 invalid cases rejected (141 by the reference with the expected code,
27 by the schema), 135 vector cases, 4 trusted-context self-tests, 4 capture-hint self-tests and 64 generated files
current. The core gate `scripts/spec/validate.py` and its shared `jsonschema_subset.py` are untouched.

**Why the fixtures are not in `spec/fixtures/studio/`.** The core validator walks every `spec/fixtures/**/*.json` and
fails on any `kind` it does not know. That script belongs to the core workflow and must not be edited from here, so
Studio fixtures live in `spec/studio/fixtures/`. `spec/fixtures/studio/README.md` points here. Moving them only takes
a one-line skip in `scripts/spec/validate.py` (for example, `if "studio" in path.parts: continue`), made by the
owner of that file.

## Conventions

- **Versions.** Every record has `schemaVersion: "jovra.<name>/<major>"`, following the starter's
  `jovra.edit-plan/1`. A breaking change bumps the major. Additive changes also need a fixture change. No schema has
  an `$id`, and references are relative files, as in the core.
- **Strictness.** Every object has `additionalProperties: false`. The reference also rejects unknown or missing
  fields itself (as the starter does), refuses integral floats such as `744.0` for frames, and refuses floats
  anywhere it hashes (`floatInContract`).
- **Ids** match `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`, so an id can never be a path, URL or command. Template ids
  (`card.goal`, `label.replay`) come from catalogs, and on-screen text comes only from stored user records.
- **Time.** Proxy frames are integers on exact rational clocks (`{num, den}`). Original PTS use `{value, timescale}`.
  The session (match) clock is integer microseconds. Rates are `num / 1 000 000 000`. There is one rounding rule,
  `floor(x + 1/2)` in exact arithmetic (`core.round_half_up`, the time analogue of ADR-0011), and Python's half-even
  `round()` is never used. Percentages use the core `pct(n, d) = (200n + d) div 2d`.
- **Hashes.** `canonical_sha256` is SHA-256 over sorted-key, whitespace-free UTF-8 JSON. It equals RFC 8785 for
  documents without floats, which is why floats are refused. Fixture media hashes are deterministic stand-ins,
  because no real Sample media exists.
- **Provenance** uses the core enum (`manual | estimated | reviewed | validated`). The validator fails if the
  Studio copy drifts from `spec/schemas/common.schema.json`.

## Schemas

| Schema | Record | What the reference adds beyond the schema |
|---|---|---|
| `project-lock` | Frozen inputs: manifest revision and canonical hash, event/sync revisions, profile and revision, output, participants and rights, privacy, quote authorization, brand tokens (const) | Demo projects use the demo profile, never reserve and never upload; cloud consent needs a record and a recording acknowledgement; a hidden location hides the venue; the lock hash equals the manifest (bundle) |
| `source-manifest` | Per source: hash, size, container, duration, rational timescale and start PTS, frame count, nominal fps, VFR flag, codec, dimensions, rotation, pixel aspect, colour/HDR, audio, lens, capture hints (wall clock, room offset and round trip, `fileZeroHostNs`), segments and restarts, analysis/render proxies with PTS-table hashes, verification | One primary, at most six match sources, unique slots; HDR implies HLG/PQ; segments add up; journalled host times increase; render proxies bake rotation once (and swap dimensions) and tone-map HDR |
| `sync-map` | Per device: pieces per recorded segment with an affine transform, fit statistics, anchors (modality, source/reference times, event position, sound delays, residual, inlier, reviewed), match coverage, gaps, review state, checkpoints; speed of sound; placements; method version | **Refits every non-reference device** with `syncfit.fit_device` and requires identical transforms, statistics, delays and residuals; stored state must equal the rule state, or be `reviewed` with start/middle/end checkpoints; coverage equals the transform over the file; gaps are exactly the uncovered spans; origin is the earliest coverage; provenance never `validated` |
| `observation` | Kind, source time, session time, sync/event revision, capability and version, provenance (producer, confidence, calibration dependency, benchmark), status, reviewer | Estimated needs a capability, producer and confidence; manual is a person with no confidence; reviewed names the reviewer; validated needs a benchmark; a calibration-dependent capability without a calibration is rejected; an accepted estimate is refused |
| `keeper-catalog` | Keepers bound to point events at one event revision, with views per source, contact frames, selection and provenance | An event appears in at most one keeper (a second angle is a view); one primary view; contacts inside a view |
| `broll-catalog` | Origin, `depictsThisMatch`, rights (holder, scope, record), disclosure label, location and people | Stock, generated or other-day footage never depicts this match; stock or generated material is labelled and has a rights record |
| `story-profile` | The five profiles, with their text carried over unchanged from `design-reference/studio/brief/story-profiles.json`, plus a versioned machine grammar | Grammar duration equals the recommended range; replay speeds exist only where replays are allowed; an estimated cue is never instruction |
| `story-brief` | The planner's proposal (the research's "StoryPlan"): profile/revision, bindings, planner kind and pinned model id, feeling, audience, aspect, audio policy, privacy, beats made of ids and enums, before/after comparisons, omitted ideas | Every beat has evidence (keeper, B-roll item or card template); ops and overlays allowed by the profile; a change claim needs reviewed evidence on both sides and no user-chosen selection; the comparison display is re-derived (`12 / 30 · 40%`, `+20 percentage points`) |
| `edit-plan` | **`jovra.edit-plan/2`** (below) | `edl.validate` (requires the trusted context) |
| `reference-catalog` | The trusted index of everything an EDL or brief names by id: score states, points and stats at one event revision, user and lesson notes, cues, annotations (kind, stored provenance, origin), narration consents (participant, scope, granted), music rights (asset, scope) | Unique ids; kind follows the origin; one event revision; bundle: cues and lesson notes carry their lesson's provenance, consents name a ProjectLock participant, brief overlays and notes resolve |
| `render-job` | State, `resumeStage` (only a stage the state can return to), attempt, quote/reservation, idempotency key, per-stage progress, delivered artifacts, full history | `jobstate.Machine.replay` must reach the stored state, resume stage and attempt; `ready` only when every listed artifact resolves to a verified film of this job (bundle) |
| `quote` | Film class, estimate and cap in credits, cost estimate, line items, retention, illustrative display amounts, expiry, status, consent, **`outputSpecSha256`** | Cap = `max(class minimum, ceil(cost / 800 000 µUSD))`; at most 30 min; an illustrative quote is Sample, never accepted, and is the only kind that shows dollars; acceptance needs consent before expiry (parsed times); the job, reservation and quote share one output-spec hash (bundle) |
| `usage-reservation` | Idempotency key `(projectId, planRevision, outputSpecSha256)`, cap, reserved/consumed/released credits, keyed entries | Totals equal entries; keys unique; at most one consume entry per job and stage; within cap; closed reservations account for every credit; demo holds zero; demo/test are Sample; live is refused |
| `delivered-artifact` | Media facts, chapters, captions, full bindings (source hashes, revisions, profile, planner, edit-plan hash, story-brief revision), verification, private delivery and share link, retention, YouTube preparation (`published` const false), stale marker | Chapters tile the film; `passed` needs probe, full decode, frame count, audio and overlay provenance; share links last at most 24 h and only for verified films; demo stays on the device |
| `lesson` | Date, focus, coach, notes, clips, source-linked cues with provenance, practice checklist, next goal, films, sharing | Notes and cues link this lesson's clips; coach notes need a coach; estimated cues come from an observation and are not reviewed; practice status follows done/target (a five-clip goal with three clips saved is valid) |
| `camera-invite` | Roster (one primary plus up to five cameras, each with a slot, status, recording acknowledgement and permissions) and invitations (display code, single use, host approval, TLS fingerprint, at most 10 min) | One primary at the near baseline; cameras never get host controls; ready means joined and acknowledged; invites expire within 10 min, bind one device, never target a filled slot; the demo accepts none |
| `storage-provider-capability` | device, iCloud Drive (Files), Google Drive, Box, Dropbox: status, integration, platforms, operations, credential and folder references, `processing` const false | Unconnected or planned providers claim no operations and hold no credential; iCloud Drive is iOS Files only, with no quota; an OAuth provider is active only when verified and connected; the demo holds no tokens |
| `contracts`, `fixture` | Shapes of the contract data and of invalid-case and vector files | |

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
  profile allows. At most one annotation is shown at a time.
- **Output and framing:** aspect `16:9`, `9:16`, `1:1` or `4:5`. `fill` only when the aspects match and with no
  upscale. `letterbox` always works. `reframe` only from a reviewed action-safe box, with keyframes in 1/10 000 of
  the frame, matching aspect, at most 2× upscale and a bounded pan speed. Match Broadcast letterboxes.
- **Audio:** exactly one bed route per output frame:
  - `primary-bed` is the designated court source, in sync with every live frame to within half an output frame,
    through the session clock.
  - `hold-bed` continues the primary without a jump under non-live segments, over real dead time that no live
    segment shows.
  - `alt-bed` is another source's audio, with fades of at least 20 ms.
  - Every change of bed source (to or from an `alt-bed`, the return to the primary, or to or from silence) sits on a
    segment boundary (`bedSwitchNotAtBoundary`). At a cut, each sounding side fades for at least 20 ms. At a
    dissolve or dip, the switch is an audio dip across the picture transition: the outgoing bed fades out over at
    least the transition frames before the boundary and the incoming bed fades in over at least those after it
    (`fadeTooShort`), so two sources' court audio never play at once.
  - `silence` is explicit. An all-silent plan is allowed: D5 exports default to no audio.

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

### Sync fitter (`syncfit.py`, method `robust-trimmed-ols/1`)

- **Model:** `t_match = offset_k + rate · t_src`, with one rate per device and one offset per recorded segment
  (piecewise across restarts; gaps stay uncovered). A robust start (the exact median of all within-piece pairwise
  slopes, Theil–Sen, and per-piece median intercepts), one trim of residuals larger than 3 output frames, then an
  exact pooled OLS on the inliers. The rate is rounded half-up to 1 ppb, and offsets and residuals to 1 µs. RMS uses
  an integer square root. (The retired `trimmed-ols/1` started from plain OLS: one anchor 2 s off could drag the line
  so far that every anchor was trimmed while the map stayed reviewable.)
- **Guards:** every anchor lies inside its piece (`0 ≤ sourceTimeUs < sourceDurationUs`, else `badAnchor`); a piece
  with fewer than two inliers is `failed` with no transform and no statistics; a fitted rate outside 0.9–1.1 fails
  the device; a drift above 1000 ppm (real phones: about 8 ppm; the stress fixture: 300 ppm) adds a needs-review
  reason. A piece has `matchCoverage` exactly when it has a transform (schema `if`/`then` and the reference).
- **Speed of sound:** audio anchors subtract the sound travel from the event position to each phone before fitting.
  The delay, `sqrt(d²)·10⁶ / c`, is computed exactly with `isqrt`, with c = 343 m/s or `331.3·√(1 + T/273.15)` m/s
  rounded to mm/s.
- **States:**
  - `estimated` needs at least 8 inlier anchors, all three thirds covered, a maximum residual of half an output
    frame, no trimmed outliers and no uncorrected audio.
  - Otherwise the state is `needs-review`, with reasons.
  - `manual` means markers only; `from-hints` means a capture hint only, derived from the SourceManifest
    (`bundle.capture_hints`: the journal's `fileZeroHostNs` plus `roomOffsetUs`, the room clock minus the host
    clock) and checked against it, never trusted; `failed` means nothing to fit, which includes no shared coverage
    (there is no separate `no-overlap` state).
  - On the reference device only `referenceSegmentId` is `reference` (rate 1). A restarted reference segment is
    `from-hints` from its own journal (rate 1, offset derived, never invented) or `failed`; it is shown, not cut.
  - Only a person sets `reviewed`, and only on a fit with at least three inliers (with two, an outlier is invisible)
    and a drift of at most 1000 ppm (`reviewOfWeakFit`). `validated` is never given to a single map.

### Job state machine (`render-job-transitions.v1.json`, `jobstate.py`)

The states come from the backend brief. Terminal states are `ready`, `canceled`, `failed_terminal` and `deleted`.
`paused`, `failed_retryable`, `quote_expired` and `budget_exceeded` can be resumed.

- **Pausing and retrying:** pause and retryable failure remember `resumeStage`. Resuming returns only there, and a
  retry uses up an attempt (`retriesExhausted` once `attempt = maxAttempts`). A stored `resumeStage` is checked, not
  trusted: it must be in `pausableFrom` / `retryableFrom` / `budgetExceededFrom` for that state and is null otherwise
  (`badResumeStage`), so `ready`, `deleted` or a terminal state can never be resumed into.
- **Budget and expiry:** `budget_exceeded` and `quote_expired` resume only through a new quote. Nothing is
  auto-raised or auto-accepted.
- **Reservations:** stages from `upload_pending` onward need a reservation.
- **Readiness:** `ready` needs a verified delivered artifact.
- **Shortcuts:** `syncing → planning` is the analysis-unavailable fallback. `upload_pending → queued` covers
  sources that are already verified.

### Quote and reservation ledger (`ledger.py`)

Studio Credits are the one unit for quotes, caps, reservations and receipts. `credit-classes.v1.json` marks the
amounts **proposal, not a price**.

- **Request key:** a reservation is keyed by `(projectId, planRevision, outputSpecSha256)`. A replay returns the same
  reservation and charges nothing. The same key with other terms is `idempotencyConflict`. A new plan revision gets
  a new reservation. A quote carries the `outputSpecSha256` it was computed for and funds only that one reservation
  (`quoteMismatch`, `quoteAlreadyUsed`).
- **Budget exceeded:** the same key is never re-reserved; an accepted re-quote for the same plan revision and output
  **tops up** the held reservation (`topup`), and the old quote becomes `superseded`.
- **Stage key:** consumption is written when a stage attempt succeeds and is keyed by `(jobId, stage)`; a later
  attempt of a charged stage replays instead of charging again, and a failed attempt writes nothing.
- **Retries after a top-up:** a reservation remembers every `(quoteId, credits)` request it applied, so a
  redelivered original reserve or a redelivered top-up replays (no charge, no error).
- **Stored entries are tied to the record** (`badEntryKey`): reserve keys are
  `reserve:<projectId>:<planRevision>:<outputSpecSha256>` (the record's own key, one initial entry, first) or that key
  plus `:topup:<quoteId>` (the bundle requires an accepted quote for the same output); consume keys are
  `consume:<jobId>:<stage>:<attempt>` with the record's job and a charged stage spelled exactly as in the job
  contract; release keys are `release:<jobId>:<outcome>` matching the status; the key prefix is the entry kind.
- **Types and time:** credits are integers, never booleans (`badAmount`); timestamps are parsed, never compared as
  text.
- **Limits:** going over the reservation is `budgetExceeded`. A failure or cancellation returns every unconsumed
  credit.
- **Environments:** the demo never reserves, test is Sample, and live is refused (`liveChargingNotActivated`) until
  a new pricing ADR exists (ADR-0013).

## Fixture inventory

- **Records (31), project `sample-court-day`:**
  - Inputs: the source manifest (three 60-min match sources at 3.6 GB each, 10.8 GB in total, plus two B-roll
    sources), the sync map (Camera 2 fitted to +119.837 ms and 300.102 ppm, which rounds to +120 ms and 18 ms/min,
    reviewed after its start/middle/end checkpoints, while the fitter alone gives `estimated`, which is what screen 26
    shows before "Confirm sync"; Camera 3 left needs-review), the keeper and B-roll catalogs, the reference catalog
    (scores, stat, notes, cues, annotation, one narration consent, one music rights record) and the project lock.
  - Story briefs: Court Memories, and Progress (12/30 → 18/30, +20 percentage points).
  - Seven EDLs:
    - the screen-36 storyboard, with Camera 2 at 00:12.400–00:18.600 placed at 00:12.000–00:18.200 (6.2 s);
    - its clean alternate;
    - the final Court Memories film plan (04:18 with chapters of 42 + 141 + 75 s);
    - Coach's Cut, with a freeze, a ½× replay, a hold-bed and consented narration;
    - Rally Pulse 9:16, with a moving reframe, music under a rights record, and its clean alternate;
    - Match Broadcast, with strict order and a post-point far-baseline replay.
  - Other records: three observations, three lessons (4/2/3 clips; 10 and 20 drills done; a five-clip review
    pending), the camera roster (screen 23, invite code JVR-482), storage providers (screen 40), three quotes (the
    screen-37 illustrative $4–$8 with a $12 cap, which cannot be accepted, and two accepted test quotes), two
    reservations (Sample credits; no money moves), two jobs (the screen-38 queue at a Sample 42% of `preview_rendering`, and a ready job with a pause
    and a retry) and the delivered film (412 MB illustrative, verified, 24 h private link, YouTube prepared but not
    published).
- **Invalid (151 cases).** These include executable fields, approval or URL fields, unlabelled speeds, copied score
  digits, stale overlay/event/sync revisions, gaps, overruns, forged session time, integral floats, transitions
  that are too long, lack handles or cover a contact, audio that is out of sync or missing during live play,
  hold-bed over live or over shown time, alt-bed mid-segment, missing consent or disclosure, music outside the
  profile, interpolated slow motion, replays before or outside their original, blind portrait crops, pans that are
  too fast, out-of-order points, a forged sync offset or residual, an auto-approved map, an incomplete review,
  extrapolated coverage, double consumption, live charging, an accepted illustrative quote, a client-set cap,
  readiness without full decode, a 48 h link, auto-publishing, a laundered cue provenance, invite escalation and
  provider overclaims. Review round 1 added: score digits or unknown ids as overlay refs, a relabelled overlay kind, a
  re-pointed cue keeping `reviewed`, unresolved card text and narration notes, self-attested consent and rights,
  rights scope overclaim, forged coverage with matching session time, an anchor outside its piece, a ghost artifact
  on a ready job, a resume stage of `ready`, a stage charged on two attempts, acceptance 0.5 s after expiry (quote
  and invite), an unbound quote, and reference-catalog duplicates, kind and revision errors. Review round 2 added:
  an unlabelled live re-showing of a moment, contact protection switched off by a null keeper, a plan of another
  project, a bed returning to the primary mid-segment, an alternate bed switching hard at a dissolve, a failed sync
  piece with coverage, an invented reference restart, reserve/consume/release entry keys of another output, job or
  stage (or with the wrong prefix or outcome), and ids and hashes with a trailing newline.
- **Vectors (135 cases).**
  - Sync fits (15; research S1, S2, S5–S10, S14, hint-only, manual, a 2 s gross outlier recovered by the robust start,
    two inconsistent clusters that fail, two anchors that cannot be reviewed, and a 1500 ppm drift flagged for review).
  - EDL against a patched trusted context (4): Camera 2 split into two adjacent coverage intervals (a restart).
  - Sound delays (48), reproducing the multicam research §4.4 tables within 0.1 ms, including pairwise biases and
    c(T).
  - Job transitions (32, including resume stages that are refused), ledger sequences (18, including one hold per
    quote, the budget-exceeded top-up, retries after a top-up that replay, retries not charged twice,
    fractional-second expiry and boolean credits) and quote credits (8).
  - Implementation-states sample truth (10): sync, progress, chapter length, storyboard window, import size, the
    144-min upload, $0.0756 of seven-day storage, queue progress, lesson counts and the illustrative quote.

  Each vector holds the reference output plus hand-derived assertions that do not come from the reference.

## Decisions taken where the brief left room (change only through a fixture change)

1. Studio fixtures live in `spec/studio/fixtures/`, not `spec/fixtures/studio/` (see above).
2. Versions follow `jovra.<name>/<major>` rather than the core's `kind` + semver.
3. StoryBrief is the planner-facing contract (the research's StoryPlan), so one contract carries one concept.
4. The match clock is light time on the primary's video clock, with its origin at the earliest coverage, in integer
   µs. It sits separately from the core integer-ms session timeline, which is untouched.
5. The bed sync tolerance is half an output frame. At the Sample 300 ppm drift, cross-angle primary-bed spans longer
   than about 55 s fail, so the fixtures switch to `alt-bed` at a cut. This is a real constraint, not a fixture
   quirk.
6. Proposed grammar numbers (transition maxima of 400/267/200/400/500 ms, freeze and card ranges, ½ and ¼ replays,
   2× reframe upscale, 50 units per frame of pan) are INFERRED from film-engine §6 and must be tuned on footage.
7. Credit minimums and the $0.80 credit budget are copied from the pricing research as a labelled proposal. Money
   amounts appear only in an illustrative Sample quote.
8. Cross-record coverage checks (`bundle.trusted_sources`) offer single-segment sources only. The EDL validator's
   piecewise coverage is pinned by the `edl-context` vectors (a two-interval Camera 2), and the fitter by S8.
9. Schema `pattern`s use ECMA-262 anchors: `validate_studio.py` runs the shared subset checker with `$` meaning end
   of input (Python's `$` also accepts a trailing newline). The core gate's `scripts/spec/jsonschema_subset.py` still
   uses Python semantics and should be fixed by its owner; Swift and Kotlin ports follow ECMA.

## Not covered yet (needs fixtures before any app relies on it)

- **Normalization:** original-PTS ↔ proxy-frame tables for VFR sources (only their hashes are bound), and their
  frame-ID conformance fixtures (multicam §8.2).
- **Rendering:** barcode render-conformance media (film-engine §7), J/L audio cuts, shake, captions content and
  portrait safe-area checks on real frames.
- **Sync on real footage:** Huber weighting, prediction-interval gates, rolling-shutter correction, and audio latency
  λ calibration (the Theil–Sen start is now in `robust-trimmed-ols/1`).
- **Sync:** the 95% prediction-interval gate (a planned S2 tightening of SD9).
- **Backend:** RLS and gateway authorization (`docs/backend/security-model.md`), the queue, claim, lease and fencing
  protocol (`docs/backend/architecture.md` §7), and real model planner output. These are designed, not code.

None of it is validated on field footage.

## Sources

Repository material (OBSERVED, read 2026-10-07):
- `design-reference/studio/brief/backend-media-design.md`, `implementation-states.md`, `story-profiles.json` and
  `screens.json`.
- `docs/handoff/studio/*` and `.claude/skills/jovra-*`.
- `tools/studio-plan/scripts/validate_edit_plan.py`.
- `docs/research/studio/{film-engine,multicam-sync,backend-architecture,pricing-and-premium}.md`.
- `docs/adr/0001`, `0003`, `0004`, `0011`, `0013`.
- `/Users/IDC2.5/Desktop/you-link-x/garnet-remotion/production_preview.py` (`MAX_SEGMENTS = 128`), read only.

External references carried over from those documents, not re-fetched for this task:
- JSON Schema 2020-12: https://json-schema.org/draft/2020-12/schema
- RFC 8785 JSON canonicalization: https://www.rfc-editor.org/rfc/rfc8785
- ITF court dimensions: https://www.itftennis.com/en/about-us/governance/rules-and-regulations/
- WCAG 2.3.1 three flashes: https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold.html
- R2 pricing: https://developers.cloudflare.com/r2/pricing/
- App Review 3.1.1: https://developer.apple.com/app-store/review/guidelines/#in-app-purchase
