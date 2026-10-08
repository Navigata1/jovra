# JOVRA Studio — open findings register

Status: living register · Opened 2026-10-07 (review round 4) · Owner: the Studio spec owner · Companion to
`docs/spec/studio-v1-spec.md` (Further Notes) and `spec/studio/README.md`.

This register holds the verifier findings that are **not** closed by a change in the Studio-owned files, each with
the ticket stage that must close it and a check that can fail. An entry leaves the register only when its check has
passed and the evidence (command output or decision record) is cited in the closing change. Nothing here is a claim
that the work is done.

Severity follows the verifier's labels. Stages: S0–S5 and ticket IDs as in `studio-v1-spec.md` (Studio tickets) and
`docs/backend/architecture.md` (B-xx).

## Open

| ID | Severity | Area | Description | Must close by | Falsifiable check that proves it closed |
|---|---|---|---|---|---|
| SOF-R4-01 | LOW (fails closed) | Sync fitter (`spec/reference/studio/syncfit.py` `_robust_start`) | The pooled Theil-Sen start of `robust-trimmed-ols/1` is not robust at small n, despite its docstring. Four anchors (three clean at 8 ppm, the end one +2 s): every anchor is trimmed and the piece is `failed` instead of trimming one. Three anchors with the end one +2 s: the line passes through the outlier, the clean middle anchor is trimmed, and the map reads 583 ppm with a 34.5 ms offset error. It stays safe (with two inliers it can never be marked reviewed, so it is never offered for cutting), but the numbers are wrong. Changing the start changes the method's results, so it needs a new method id (`robust-trimmed-ols/2`, retiring `/1` as `/1` retired `trimmed-ols/1`) carried through the sync-map schema `const`, the fixtures, ADR-0017 and SD9. Proposed method: Siegel's repeated-median slope (fixes one outlier for n ≥ 4) plus, for at most 8 anchors, a consensus start over every within-piece pairwise line (most inliers within three output frames, ties broken by the smaller \|rate − 1\|, because phones drift about 8 ppm); with three anchors and one outlier the outlier is not identifiable without that prior. | S2, before STU-03 (Swift parity) freezes the fitter | `python3 scripts/spec/validate_studio.py` passes with new sync-fit vectors: (a) `four-anchors-one-outlier`: `nOutliers` 1, offset within ±2 000 µs of the truth, drift within ±3 ppm, `reviewable` true; (b) `three-anchors-end-outlier`: the end anchor is the one trimmed (or the piece is `failed`), drift within ±3 ppm when fitted, `reviewable` false; (c) every existing sync-fit vector's hand assertions still hold. The r3 repro `fsync.py` prints no 583 ppm map. |
| SOF-R4-02 | LOW (core-owned) | Core schema gate (`scripts/spec/jsonschema_subset.py:131-134`) | `pattern` is compiled with Python `re` and matched with `search`, so `$` accepts a trailing newline for the **core** schemas (`'...\n'` passes `^...$`). Studio is fixed through `StudioSchemaSet.ecma_pattern` (`scripts/spec/validate_studio.py`); the core file is owned by the core gate and is not edited by Studio. | Core gate owner, before STU-01 (the Swift decoders assume ECMA-262 patterns for every schema they share) | With the core gate fixed, `python3 scripts/spec/validate.py` rejects a core fixture whose id or hash field ends in `\n` (a new invalid case in the core fixtures), and still prints `RESULT: PASS`. |
| SOF-R4-03 | MEDIUM (product decision) | Free/paid line for on-device films and local film lengths (spec D-4, SD2, SD4, open question 9; ADR-0019; ADR-0023) | Round 3 recorded "on-device Studio is free; the model-planned story and cloud production are paid and opt-in" (D-4) and "the rules planner is the default; cloud planning only on opt-in" (D-5) as decisions, citing only `pricing-and-premium.md` §6, although Jon's addendum calls Studio "super-premium" and "the moat"; round 4 returned both to working defaults and reopened open question 9. **Jon's decisions addendum of 2026-10-07 (`docs/handoff/JON-ORIGINAL-PROMPT.md`, items 1–3), recorded by ADR-0023, answers part of it:** Studio films are priced in credits by story length (3 to 30 minute tiers and Full match) and capture quality, the cloud planners are Opus 5.5 with GPT-6 Astra or GPT-6.1 Sol handing off back and forth, and the Remotion licence (open question 5) is settled. ADR-0023 adds, in its own words rather than Jon's, that the on-device rules planner stays the free default and that cloud planning runs only with the player's consent (D-5 now has an ADR source, not a founder quote). **What remains open:** whether the on-device template films stay free or become premium, and whether local films (3 min, 5 min or Full today) gain the 10 to 30 minute tiers. S0–S3 build to the D-4 working default (everything on the device free, at today's local lengths); the `localStudio` entitlement keeps either answer a configuration and pricing-ADR change. | Before STU-05 freezes Studio copy, and in any case before the SD4 pricing ADR (S4) | While open, `grep -n "D-4 · The free/paid line (working default" docs/spec/studio-v1-spec.md` prints the D-4 line and `grep -n "Still open:" docs/spec/studio-v1-spec.md` prints open question 9; if either prints nothing while no dated answer from Jon is recorded, the answer was silently assumed and the check fails. To close: Jon's answer to both open points is recorded with its date and source (message, meeting note or ADR) in open question 9 and D-4, the SD4 pricing ADR cites it, `grep -n "working default" docs/spec/studio-v1-spec.md` then finds no D-4 entry still marked as a working default, and ADR-0019's "The line" matches the recorded answer. |
| SOF-R4-04 | LOW (cost decision) | Cloud film retention vs pricing (spec D-3, SD23; ADR-0019:28; `pricing-and-premium.md` §6; `jovra.quote/1`) | D-3 and SD23 keep cloud films "until the player deletes them" with no lifecycle, while ADR-0019 and the pricing research list extended retention as paid, and the quote prices storage for at most 30 days (`lineItems.storageDays` ≤ 30). Nothing quotes, bounds or records as a decision the ongoing R2 cost of films kept indefinitely. | SD4 pricing ADR (S4), before live charging is activated (ADR-0014 gates) | The pricing ADR states one of: (a) films are kept free indefinitely, with the measured cost per film-month and a per-account storage bound that the gateway enforces (a test refuses the film that would cross it); or (b) a default film lifetime with a paid extension that the quote prices. `docs/backend/architecture.md` §10's films row and SD23 then match the ADR word for word on the default. |

## Closed by re-verification (2026-10-08, ticket S02)

| ID | Severity | Area | Closed by | Evidence |
|---|---|---|---|---|
| SOF-R4-05 | PROCESS | Verification scope of round 3 (findings 13–48 never re-checked) | The verifier pass below: each of round-2 findings 13–48 read against the current `docs/backend/architecture.md`, `docs/backend/security-model.md`, `docs/spec/studio-v1-spec.md` and `docs/spec/studio-screens.md` (and the ADR or ticket file a finding names). 36 closed with cited lines, 0 re-raised, so no new register id and no S4 ticket gains an entry. | Table "Findings 13–48 re-verification" below. Scratch evidence: `/private/tmp/claude-502/-Users-IDC2-5-jv/studio-verify-r5/` (`studio-defects.json`, the round-2 list of 49 findings, sha256 `81e5c1a3…7134b25`; `check_citations.py`; `transcript.txt`). `python3 check_citations.py <repo>` asserts that every cited line below holds the cited text and that six pre-fix phrases are absent: 122 citations, 0 failures, `RESULT: PASS` at `20a527b`. With `--register` it checks that every `file:line` in the table below is one of those 122 and that no row lacks one (36 rows, 0 failures). On a copy with one cited line changed, or one row's citation removed, it prints `FAIL`. |

### Findings 13–48 re-verification

Indices are those of the round-2 verifier list. "Closed" means the defect in the documents is gone: the design text,
its threat row and its named test are in place. It does not mean the behaviour exists. Backend items are designs whose
pgTAP, gateway and R2 tests run when the owning S4 ticket implements them, and each stays unverified until then. Owner
tickets are copied from the findings map in `docs/spec/studio-tickets.md`, which also lists S99 without an index. File
names are unique in the repository: `architecture.md` and `security-model.md` are in `docs/backend/`, the spec, screens
and tickets files are in `docs/spec/`, and ADRs are in `docs/adr/`.

| # | Round-2 finding | Owner (findings map) | Result | Cited lines |
|---|---|---|---|---|
| 13 | Orchestrator role reachable from user routes; render-host upload/read functions granted to both roles | S80, S82 | closed | architecture.md:63, architecture.md:90, security-model.md:94, security-model.md:318, security-model.md:733 (T-DB-57) |
| 14 | Coach approval by display name; lesson/film codes active on redemption | S83 | closed | architecture.md:661, architecture.md:880, security-model.md:328, security-model.md:734 (T-DB-58). Narrowed: a Sign in with Apple user with a hidden relay email cannot match an email-bound invitation (architecture Q12) |
| 15 | Tester-only sign-up enforced on the client | S75, S82, S104 | closed | security-model.md:48, architecture.md:149, security-model.md:1138, architecture.md:1429 (T-GW-30) |
| 16 | 10-minute `iat` check for account deletion is ineffective | S94, S98 | closed | security-model.md:63, security-model.md:66, architecture.md:885, security-model.md:963 (E10). The `session_id` claim and `auth.sessions` shape stay UNVERIFIED until G1 |
| 17 | Story plans and versions not bound to their project | S77, S79 | closed | architecture.md:494, architecture.md:518, architecture.md:543, architecture.md:576, security-model.md:735 (T-DB-59) |
| 18 | Idempotency key breaks on a NULL plan version; revise leaves the hold on the old version | S78, S79 | closed | architecture.md:545, architecture.md:581, architecture.md:1032, security-model.md:736 (T-DB-60) |
| 19 | Missing or NULL spend limit never refuses | S79 | closed | architecture.md:566, security-model.md:1270, security-model.md:946 (D8), security-model.md:737 (T-DB-61) |
| 20 | Clip share approval not pinned; no withdrawal; no `lesson_clip` deletion scope | S77 | closed | architecture.md:463, architecture.md:247, architecture.md:882, security-model.md:1384, security-model.md:738 (T-DB-62) |
| 21 | `shares_project_with` ignores approval, so a pending coach reads names | S76 | closed | security-model.md:258, security-model.md:388, security-model.md:739 (T-DB-63) |
| 22 | Derived-media deletion gaps (a)–(f) | S77, S94 | closed | (a) architecture.md:421; (b) architecture.md:480; (c) architecture.md:1265; (d) architecture.md:1262; (e) architecture.md:1267; (f) architecture.md:1264; security-model.md:791 (T-R2-16) |
| 23 | Direct PostgREST writes unbounded | S77 | closed | architecture.md:788, security-model.md:1502, security-model.md:945 (D7), security-model.md:740 (T-DB-64) |
| 24 | Definer BEFORE triggers leak existence and revision before RLS | S76 | closed | architecture.md:787, security-model.md:934 (I11), security-model.md:741 (T-DB-65) |
| 25 | Reconciler races uploads and render outputs | S90 | closed | architecture.md:1136, security-model.md:949 (D11), security-model.md:792 (T-R2-17) |
| 26 | Helper and table ownership ambiguous | S76 | closed | security-model.md:95, security-model.md:742 (T-DB-66) |
| 27 | Tokens and user text in logs outside the Worker | S82, S96, S102 | closed | security-model.md:891, architecture.md:897, architecture.md:1430 (G2), security-model.md:937 (I4) |
| 28 | `/s/` unlimited; no `nosniff`; presigned overrides unsigned | S93 | closed | architecture.md:846, security-model.md:788 (T-R2-13), security-model.md:789 (T-R2-14), security-model.md:948 (D10) |
| 29 | Consent does not record which text classes reach a model | S86, S89 | closed | architecture.md:530, security-model.md:1608, 0016-provider-agnostic-planner-adapter.md:45, security-model.md:942 (I8) |
| 30 | ADR-0014/0018/0019/0022 wording inconsistent with the design | S01 | closed | 0018-cloud-media-security-rls-and-signing-gateway.md:93 (items 1, 4), 0019-paid-cloud-production-is-opt-in.md:97 (item 2), 0014-backend-ready-v1-three-environments.md:81 (item 3), 0022-identity-siwa-demo-profile-tester-config.md:71 (item 5) |
| 31 | Server-written references not project-constrained | S77, S78 | closed | architecture.md:624, architecture.md:625, architecture.md:657, architecture.md:790 |
| 32 | Coaches see `measurements`; render outputs take uncapped bytes | S78 | closed | architecture.md:610, security-model.md:574, architecture.md:891 |
| 33 | Coverage summary (information, no defect) | S34 | closed (still holds) | studio-screens.md:1567, studio-screens.md:1575; ST21–ST40 and A1–A25 each have one §3 row; `python3 scripts/spec/validate_studio.py` prints `RESULT: PASS` |
| 34 | No Studio tickets | this DAG | closed | studio-tickets.md:39, studio-tickets.md:23, studio-v1-spec.md:1516 |
| 35 | On-device Studio declared free without Jon | S01, S87, Jon | closed (as an open question) | studio-v1-spec.md:475, studio-v1-spec.md:483, studio-v1-spec.md:1642. The decision itself stays open as SOF-R4-03 |
| 36 | Live analysis on the primary undefined | S19, S72 | closed | studio-v1-spec.md:831, studio-v1-spec.md:836, studio-v1-spec.md:1649 |
| 37 | EDL segment binding deviation not recorded | none listed (recorded conflict) | closed | studio-v1-spec.md:1323, studio-v1-spec.md:1335 |
| 38 | No six-device sync acceptance | S73, S74 | closed | studio-v1-spec.md:1125, studio-v1-spec.md:1608 |
| 39 | "Visible events" over-claims automatic detection | S61 | closed | studio-v1-spec.md:82, studio-v1-spec.md:247, studio-screens.md:567 |
| 40 | ST21 angle tile not gated by stage | S17 | closed | studio-screens.md:186, studio-screens.md:1575 |
| 41 | `analyzing` implies vision analysis | S27 | closed | studio-v1-spec.md:979, studio-screens.md:1343, studio-screens.md:1345 |
| 42 | New Remotion tennis compositions neither specified nor deferred | deferred | closed | studio-v1-spec.md:986, studio-v1-spec.md:987, studio-tickets.md:29 |
| 43 | ADR-0002 note presented as done | S01 | closed | 0002-local-first-document-store.md:16, studio-v1-spec.md:1588; `grep -rn "superseded in part" docs/spec/studio-v1-spec.md docs/spec/studio-screens.md` prints nothing |
| 44 | 21.6 GB / 144 min baseline and upload-time estimate missing | S26 | closed | studio-v1-spec.md:971, studio-v1-spec.md:972, studio-screens.md:1259 |
| 45 | FilmVerifier omits dimensions, aspect and codec facts | S40 | closed | studio-v1-spec.md:811, studio-v1-spec.md:813 |
| 46 | No mixed Pixel/iPhone media or lobby interop acceptance | deferred | closed | studio-v1-spec.md:1159, studio-v1-spec.md:1162, studio-tickets.md:29 |
| 47 | Sandboxing and provider URLs not covered in the spec | S91 | closed | studio-v1-spec.md:923, studio-v1-spec.md:925, studio-v1-spec.md:929 |
| 48 | Advanced section: testers and founder vs Test mode only | S29 | closed | studio-v1-spec.md:1029, studio-screens.md:73, studio-screens.md:1483 |

## Closed in round 4 (for the verifier)

Each line names the change and the check that now fails if the defect returns. Contract and reference checks run in
`python3 scripts/spec/validate_studio.py`; backend items are designs whose tests run when S4 implements them.

| Finding | Closed by | Check |
|---|---|---|
| Sync map omits a restarted segment (bundle) | `bundle.check_sync_against_manifest` requires exactly one piece per recorded segment of every match source (`unmappedSegment`); `trusted_sources` and `check_plan_against_trusted` offer a match source only when the manifest records one segment and the one piece maps it | bundle mutation `restart-segment-unmapped`; r3 `n8.py` now stops at `unmappedSegment` and camera-2 is not offered |
| Score overlay of another point (EDL v2) | `edl_context.references[refId].pointWindows`; `edl._check_overlays` binds a point-event score or metric over live, replayed or frozen play to a keeper window that carries the point (`overlayOutsideMoment`); `bundle.check_plan_against_trusted` checks the named keeper's `eventRefs` | invalid cases `score-of-another-point`, `score-over-another-rally`; r3 `n_edl.py` N1a/N1b rejected by both |
| Court audio under a replay (EDL v2) | `primary-bed`, and `alt-bed` from a match source, only under live segments (`courtBedOffLive`); a jump to another position of the same source is a switch (boundary and fades) | invalid cases `primary-bed-under-replay`, `alt-court-bed-under-replay`, `same-source-jump-at-dissolve`, `primary-returns-hard-at-cut`; r3 N2 rejected |
| Ledger consumption not bound to job and stage | `Ledger.reserve(job_id=…)` / `attach_job`; `consume` requires the reservation's job (`jobMismatch`) and an exact charged stage (`unknownStage`) | ledger vectors `consume-bound-to-job-and-stage`, `job-attached-after-reserve`; r3 `n67.py` N6 charges nothing past the first stage |
| Top-up funded by the initial quote (record) | `usage-reservation.initialQuoteId` (required); top-ups differ from it and from each other; `check_money` requires every replaced quote to be `superseded` | invalid cases `topup-from-initial-quote`, `quote-is-not-initial`; bundle mutations `topup-from-initial-quote`, `topup-leaves-initial-quote-accepted`; ledger vector `topup-from-initial-quote-refused` |
| Quote cannot say whether model planning was quoted or consented (D-5) | `jovra.quote/1` gains `plannerChoice` and consent `modelProvider`, `textClasses`, `retentionDays`, `consentTextVersion`; `records.check_quote` and `bundle.check_money` bind them | invalid cases `heuristic-quote-with-planner-tokens`, `model-planning-without-provider-consent`, `note-text-without-model-consent`, `consent-retention-differs`, `retention-not-offered`, `consent-without-model-field`; bundle mutation `model-film-from-rules-quote` |
| Export audio default not in a contract (D-1) | `story-profile.exportAudio` (`includeByDefault` on only for Rally Pulse and Court Memories, switch always shown, junior mode no audio and no switch), checked by `records.check_profile_catalog` | `validate_studio.py` contract check; `story-profiles.v1.json` |
| Cloud no-audio export undesigned (D-1) | architecture §9.1 audio variants, `remux_no_audio` stage, `includeAudio` on downloads and share links | T-GW-38 (S4) |
| Retention 7-day lifecycle vs 1/7/30 choice (D-3) | architecture §10: per-object `retention_until` from the accepted quote and a daily sweep, 31-day lifecycle backstop; SD12, SD23, ST37 copy; quote `retentionDays` ∈ {1, 7, 30} | invalid case `retention-not-offered`; T-R2-18 (S4) |
| Per-project quotas multiply (D7) | security-model §13.10 per-user aggregate `*user_total` counter | T-DB-64 N-project case (S4) |
| Planner spend not bounded by the reservation | `render_attempts.planner_budget`, security-model §13.7 `stage_overrun`, architecture §7.6 | T-DB-72 and the planner fixture test (S4) |
| Lesson deletion stalls on `check_story_plan_lessons` | trigger checks only ids a client path adds; server path skips the caller check | T-DB-73, T-GW-32 (S4) |
| Lesson-only observation hits a NULL quota subject | `enforce_quota` subject `coalesce(project_id, auth.uid())`, refuses a NULL subject with `P0429` | T-DB-64 lesson-only case (S4) |
| Plan-by-job reservation key never moved | planning stage moves job and reservation to `(plan, V, hash of V)` in one transaction | T-DB-68 (S4) |
| T-DB-36/37 named `jovra_gateway` | both rows now `jovra_orchestrator` | security-model §6.2 |
| Host-route denials unaudited | `audit_denial_for_attempt` (orchestrator only, append only) | T-GW-19, T-GW-28 (S4) |
| `stable` authorization functions | `authenticated_within`, `reconcile_orphans` declared `volatile`; T-DB-03 lints `provolatile = 'v'` in `app_gateway` | T-DB-03 (S4) |
| ADR-0019 vs D-4; D-4 without a founder source | D-4/D-5 returned to working defaults, open question 9 reopened (SOF-R4-03 above) | `grep -n "working default" docs/spec/studio-v1-spec.md` |
| ADR-0002 note described as missing; "superseded" vs "amended" | SD3, the index row, STU-00 and ADR-0014 say "amended by ADR-0014 (backend boundary only)" | `grep -rn "superseded in part" docs/spec/studio-v1-spec.md docs/spec/studio-screens.md docs/adr/001[4-9]*.md` returns nothing |
| `openai-astra` not shown as disabled; planner vocabulary | architecture §1 and §7.6 say it ships disabled with no model ID; `planner_kind` is `heuristic`, `model`, `user` in every layer | `grep -n "'llm'" docs/backend/*.md` returns nothing |
| ST30–ST32 lack junior and silent-source sound states | states and §3 coverage rows added | `studio-screens.md` §3 rows ST30–ST32 |
| ST37 consent copy for cloud planning | a second, required consent checkbox for the planning service | `studio-screens.md` ST37 item 6 |
| SD13 status spelling | contract spellings (`choose-folder`, `not-connected`, `token-expired`) | SD13 |
| ST38 "Plan story" stage ambiguity | planning is part of "Build film" for every job | ST38 item 4, story 193 |
| ST26 muted-source wording | "visible events you mark" | ST26 States |
