# JOVRA backend

The Studio cloud backend (ADR-0014, ADR-0018, ADR-0022), built as code and tested locally. Nothing here is
provisioned: there is no hosted project, URL, key or account in this tree, and none may be added by an agent
(ADR-0014, activation gate 1). The app never needs this backend; recording, scoring and local films work offline.

Design: `docs/backend/architecture.md` (layout §1.2, local test strategy §12, gates §13, tickets §15) and
`docs/backend/security-model.md`.

## Subprojects

| Folder | What | Test command | CI workflow | Status |
|---|---|---|---|---|
| `supabase/` | Local Supabase project: config, migrations, seed testers, pgTAP suite | `supabase test db` (see below) | `.github/workflows/backend-db.yml` | Scaffold (S75 / B-02); migrations 1 (S76 / B-03), 2 (S77 / B-04) and 3 (S78 / B-05); gateway commands (S79 / B-06); orchestrator commands (S80 / B-06) |
| `gateway/` | Cloudflare signing gateway Worker | — | — | Not started (B-07) |
| `render/` | Render-host image | — | — | Not started (B-13) |
| `contracts/` | Gateway and queue JSON Schemas | See `contracts/README.md` | `.github/workflows/backend-contracts.yml` | Implemented contract/checker foundation (S81 / B-01); gateway/render runtime remains separate |

## `supabase/` (S75)

What it holds:

- `config.toml`: the local stack. Sign-ups off (`enable_signup = false`), anonymous sign-in off, a mandatory
  `before_user_created` allow-list hook, six-digit email codes delivered to Mailpit, an ES256 signing key read from
  `signing_keys.json` (generated locally, gitignored). Storage, Realtime, Studio, Edge Runtime and Analytics are off:
  media lives in private R2 behind the gateway (ADR-0018).
- `migrations/20261008000000_tester_signup_lock.sql`: `app_ops.tester_allowlist` (HMACs only, never addresses),
  `app_private.email_hmac` (key in Vault) and the hook `app_private.before_user_created`, which refuses every email
  that is not allow-listed, every sign-up without an email, and everything when the key is missing.
- `seed/00_testers.sql`: a random local HMAC key and five fictional testers at `example.test` (owner, coach, viewer,
  camera, unrelated), plus `pending.tester@example.test`, allow-listed but not created. No passwords.
- `seed/testers.allowlist.example`: the format of the untracked allow-list the operator keeps for the hosted test
  project (`seed/testers.allowlist`, gitignored). One address per line, `#` comments; addresses are trimmed and
  lower-cased before hashing.
- `tests/database/`: the pgTAP suite. `000_harness.test.sql` installs basejump-style helpers in a `tests` schema
  (`create_supabase_user`, `get_supabase_uid`, `authenticate_as`, `authenticate_as_service_role`,
  `clear_authentication`, `rls_enabled`); later files run inside `begin; ... rollback;`.
- `scripts/`: `gen-signing-key.sh`, `otp_smoke.py` (sign-in through Auth and Mailpit, refusals) and
  `check-hosted-identifiers.sh` (no `*.supabase.co`, API key, JWT or non-`example.test` email in the tree).

### Run it locally

Needs Docker and the Supabase CLI (2.100.1 in CI). From `backend/`:

```sh
supabase/scripts/gen-signing-key.sh          # once per checkout; the CLI will not load config.toml without it
supabase start
supabase db reset                            # migrations + seed from scratch
supabase db advisors --local --type security --fail-on warn
supabase db advisors --local --type performance --level info --fail-on warn
supabase test db
supabase status -o env > /tmp/jovra-status.env && python3 supabase/scripts/otp_smoke.py /tmp/jovra-status.env
python3 supabase/scripts/postgrest_identity_smoke.py /tmp/jovra-status.env
supabase/scripts/check-hosted-identifiers.sh
supabase stop --no-backup
```

To sign in by hand, request a code for a seeded tester (for example `owner.tester@example.test`) and read it in
Mailpit at http://127.0.0.1:54324. Advisors run before `supabase test db` because the harness leaves its `tests`
helpers in the local database; `supabase db reset` removes them.

### What CI proves

`backend-db` runs on every pull request touching `backend/supabase/**` or the workflow: the identifier check, then
`supabase start`, `supabase db reset`, the security and performance advisors (each fails on warn; the performance
run also prints its info-level findings, where `unused_index` is expected on a fresh database), `supabase test db`,
the OTP smoke
test and the PostgREST identity smoke test. A failing pgTAP assertion or smoke check turns it red.

## Migration 1 (S76 / B-03)

`migrations/20261008010000_identity_membership_rls.sql` (security-model §3, §4, §5.1–5.2, §9, §13.0, §13.11):

- Schemas `app_private` (helpers, trigger functions; `authenticated` has USAGE so policies can call helpers),
  `app_gateway` (commands, B-06; only `jovra_gateway` and `jovra_orchestrator` have USAGE) and `app_ops`; none is
  exposed through PostgREST.
- Roles: `jovra_owner` (nologin) owns every table, enum, helper and trigger function (T-DB-66), so definer helpers
  read rows as the table owner without re-entering RLS, and no table is `FORCE ROW LEVEL SECURITY`.
  `jovra_gateway` and `jovra_orchestrator` log in (passwords set out of band at G2, never in a migration) and hold
  no table privilege anywhere (T-DB-05).
- Enums of architecture §4.2; tables `profiles` (created by a trigger on `auth.users`), `projects`,
  `project_members` (the owner row is created by trigger; coach rows only through `app_gateway`) and
  `camera_invites` (written only through `app_gateway`; `code_hash` and the device thumbprint never selectable).
- Helpers `project_role`, `has_project_role`, `shares_project_with` (approval predicate on both sides, so a pending
  coach shares nothing; T-DB-63), `project_is_live`, `is_real_user`, `is_client_path` and `can_insert_projects`.
  The definer helpers read the request claims through `app_private.current_actor()` (the same claims `auth.uid()`
  reads; `jovra_owner` has no access to the `auth` schema), and identity_03 pins the two together.
- Triggers in the §13.0 order: `a00_rls_guard` on `projects` raises RLS's own `42501` from the same predicate as
  the INSERT policy, before anything else (T-DB-65/67); `a10_validate` raises `P0422 field_too_long:<col>`,
  `required:<col>` or `invalid_value:<col>` before a CHECK or NOT NULL can emit a `Failing row contains` DETAIL;
  `b50_bump_revision`; `a10_create_owner_membership` (after insert).
- Deliberate narrowing of §5.2: a coach reads its own `project_members` row only while the membership is active, so
  a pending coach sees 0 rows (T-DB-63) and a revoked or expired one 0 rows at once (T-DB-31/32).

Tests: `tests/database/identity_01_catalog.test.sql` (T-DB-02, 03, 04, 05, 66, 67a), `identity_02_role_matrix`
(T-DB-01, 06–11, 28, 30–32, 63, as anon and as authenticated with owner, unrelated, coach, pending/revoked/expired
coach, viewer, camera and anonymous-user claims) and `identity_03_guards` (T-DB-65, 67b, P0422 errors, owner-row
invariant). `scripts/postgrest_identity_smoke.py` checks T-DB-35 (only `public` and `graphql_public` exposed) and
the owner/unrelated paths through PostgREST with real ES256 session tokens minted by the admin `generate_link` API.

### Two facts found while building this (OBSERVED)

- In the CLI, `[auth.email] enable_signup` switches the email provider on or off (`GOTRUE_EXTERNAL_EMAIL_ENABLED`);
  setting it to false disables email codes for everyone. Sign-ups are closed by `[auth] enable_signup = false`.
- Supabase Auth runs `before_user_created` on sign-up, OTP, anonymous, OAuth, SAML, Web3 and invite, but not on
  `POST /auth/v1/admin/users` (no call in `internal/api/admin.go` of supabase/auth). The operator's admin creation
  is therefore not checked by the hook; it needs the secret key, which never leaves the operator. The smoke test
  proves the hook alone through the invite path, which also ignores the sign-up switch.

### Not covered yet

- Everything hosted is UNVERIFIED until gate G1: the hook's availability, config keys and payload shape on the
  chosen plan, the operator script that creates testers from the untracked allow-list, and where the hosted HMAC key
  lives (security-model §13.2–13.3).
- `gateway/` will hold its own `.dev.vars` (already gitignored).
- Migration 1 leaves to later tickets: T-DB-29 (`provider_connections`, B-05) and T-DB-33 (owner-only
  `app_gateway` commands and `audit_denial`, B-06). Migration 2 closed the rest: the `parent_revision` variant of
  T-DB-65, quotas on `projects` and the `project_members.grant_id` foreign key.
- The two S75 auth-hook functions (`before_user_created`, `email_hmac`) read Vault and keep the migration owner;
  T-DB-66 names them as its only exception.

## Migration 2 (S77 / B-04)

`migrations/20261008020000_media_lessons_rls.sql` (architecture §4.1, §4.3, §4.4; security-model §4, §5.3–5.6,
§13.0, §13.5, §13.8–13.11, §13.16):

- Tables `camera_sources`, `source_manifests`, `sync_maps`, `calibration_versions`, `point_event_revisions`,
  `observations`, `lessons`, `lesson_clips`, `story_plans` and `story_plan_versions`, plus `artifacts` and
  `access_grants`, which this migration's helpers and triggers need (`lesson_access`, clip sharing, excerpts, stale
  marking). Their full column sets are in place; migration 3 (S78) adds the `artifacts.job_id`/`attempt_id` foreign
  keys with `render_jobs`/`render_attempts`, `artifact_sources`, and the audit and outbox rows noted below.
- Composite foreign keys make cross-project references impossible: a clip, observation, calibration or artifact
  names a source of its own project, an artifact's parent and a grant's artifact are of the same project, and a
  plan version is bound to its plan's project (findings 17, 31). `story_plans (project_id, id)` and
  `story_plan_versions (story_plan_id, id)` are the targets S78's jobs, quotes and reservations reference.
  Deleting a source keeps clips and observations with `source_id` null (`ON DELETE SET NULL (source_id)`,
  finding 22a; user story 173).
- Append-only tables (`point_event_revisions`, `source_manifests`, `sync_maps`, `calibration_versions`,
  `story_plan_versions`): revision or version assigned under a per-project advisory lock, no UPDATE or DELETE grant.
  An event revision whose `parent_revision` is not the project's current one is `P0409 revision_conflict`; a new
  revision marks older films, previews, clip excerpts and plan versions `stale`.
- Clip sharing (finding 20): `app_gateway.approve_clip_share` (project owner only, else `P0404`) pins the approval
  to `clip_share_fingerprint`; `b20_pin_shared_clip` clears it, unlinks the excerpt and hides it when the window,
  source, keeper or bound revisions change; `can_view_lesson_clip` also requires the stored fingerprint to equal the
  current one, so a bypassed trigger still cannot carry an approval to another window; `app_gateway.revoke_clip_share`
  withdraws it. A clip-bearing grant is refused (`P0409 clip_share_not_approved`) until the clip is shareable.
- Quotas (finding 23): `a20_enforce_quota` on every client-insertable table (including `projects`), per project or
  per user, plus the per-user aggregate `*user_total`, in `app_ops.quota_limits` / `quota_counters`. A missing
  limits row refuses, a lesson-only observation counts against the writing user, a refusal rolls its increments
  back (`P0429 quota_exceeded`).
- Performance hygiene: one permissive policy per table, role and command (`artifacts_select` covers members and
  viewers), and every foreign key in `public` has a covering index, author and reviewer columns included, so a
  profile deletion's `SET NULL` never scans a table. `media_01_catalog` asserts both.
- Every client-insertable table has `a00_rls_guard` (one function, `app_private.rls_guard()`, calling the same
  `can_insert_<table>` predicate as the INSERT policy) and coded `P0422` validation before constraints.

Tests: `media_01_catalog` (tables, composite FKs and delete actions, append-only grants, hidden columns, quota
lints, command privileges, FK covering indexes and policy overlap, T-DB-01 for the new tables), `media_02_sources_events` (T-DB-12, 13, 14, 15, 16, 24, 43,
59 FK half, the `parent_revision` variant of T-DB-65), `media_03_lessons_clips` (T-DB-17, 18–23, 41, 42, 45, 46, 49,
52, 62, 69; stories 173 and 179) and `media_04_quotas` (T-DB-64, 70).

Not covered here (later tickets): the render_jobs/quotes/usage_reservations half of T-DB-59 (an S78 acceptance
criterion; this migration ships its targets, asserted in `media_01` test 24) and the `render_attempts.lease_token_hash`
and `quotes.cap_cost_micro_usd` columns of T-DB-17 (S78 creates those tables); the gateway `404` halves of
T-DB-46/62 (gateway routes, S83 onward); `lesson_embeddings` in T-DB-49 (B-20); audit rows for the clip-share
commands and the outbox row that deletes an unlinked excerpt's object (`app_ops.audit_events`, `app_ops.job_outbox`,
S78); `create_grant`'s creator checks (S79).

## Migration 3 (S78 / B-05)

`migrations/20261008030000_money_jobs_rls.sql` (architecture §4.1, §4.3, §7, §10; security-model §5.6, §5.7, §6,
§8.1, §13.5–13.7, §13.9, §13.15–13.17):

- Tables `quotes` (the `consent` object of contract `jovra.quote/1`: `modelProvider`, `textClasses`, `retentionDays`,
  `consentTextVersion`; `planner_choice`), `usage_reservations` (`initial_quote_id`), `render_jobs`,
  `render_attempts` (leases, `input_refs`, `output_plan` with a byte cap per output, `output_refs`, `measurements`,
  `planner_budget`), `artifact_sources`, `provider_connections` (status rows only) and `deletion_requests`; in
  `app_ops`: `upload_sessions`, `upload_parts`, `job_outbox`, `idempotency_records`, `spend_limits`,
  `spend_commitments` and `audit_events` (the quota tables are migration 2's).
- No client writes money, jobs, attempts, artifacts, artifact sources, grants or deletion requests: no INSERT, UPDATE
  or DELETE grant exists for `authenticated` or `anon` (T-DB-26). Owners read quotes and holds as credits only; the
  micro-USD columns, the plan key and the requester are not granted. Coaches read jobs and attempts but no money and
  no `measurements`, `planner_budget`, leases or refs (finding 32, T-DB-25).
- One hold and one live job per `(project, plan, plan version, output)` with `NULLS NOT DISTINCT`, so plan-by-job work
  (version null) cannot open a second hold or job (finding 18, §13.6); an accepted quote funds exactly one hold and a
  hold bounds exactly one job.
- Composite foreign keys bind every plan, version, quote, hold, job, attempt and artifact source to its own project,
  and the excerpt links in both directions (`artifacts.lesson_clip_id`, `lesson_clips.excerpt_artifact_id`) replace
  migration 2's single-column ones (findings 17, 31; T-DB-59 FK half). `artifacts.job_id`/`attempt_id` get their FKs.
- `ready` needs a verified, delivered film of the job (`b10_check_job_state`, `P0409 artifact_not_verified`): the
  table half of T-DB-53, which `set_job_state` (S80) inherits. A hold is never unbounded (positive micro-USD cap,
  reserved ≤ cap, consumed + released ≤ reserved), output caps stay inside a per-kind ceiling, and planner budgets
  exist only on the `plan` stage, all as coded `P0422` errors before any CHECK.
- `provider_connections` has no token, secret, key, URL, endpoint or email column (T-DB-29); scopes are names, never
  URLs, and `account_label` never holds an email. It is client-insertable for the row's own user, so it has
  `a00_rls_guard`, `a10_validate`, a quota row and `a20_enforce_quota` like every such table.
- `app_ops` is server-only. `a05_refuse_secrets` on every `app_ops` table with a text or JSON column refuses any
  `jv[igslhc]_` token, JWT or email address (`P0422 secret_not_storable`, T-DB-47 table half); the outbox holds ids
  only, one shape per kind; `spend_limits` fails closed: NOT NULL limits, one seeded default owner row and no
  environment row until the operator sets it (§13.7, finding 19); the spend ledger and audit log are append-only
  (the audit log may only be purged after 400 days).
- `approve_clip_share` and `revoke_clip_share` now write audit rows; a withdrawal also unlinks and hides the excerpt.
  Every unlinked excerpt (withdrawal or moved window) gets a `delete_object` outbox row. Grant rows disappear for
  creators and grantees as soon as their project's deletion starts (T-DB-50). `lesson_deletion_artifacts` lists a
  lesson's excerpts and their children so the deletion step removes objects before the row cascade (T-DB-48).

Tests: `money_01_catalog` (tables, composite FKs and delete actions, the two `NULLS NOT DISTINCT` keys, hidden columns,
T-DB-26 grants, T-DB-29 `hasnt_column`, app_ops privileges and the T-DB-47 trigger lint, spend-limit seeding, T-DB-01
for the new tables), `money_02_roles` (T-DB-25, 26, 27, 28, 29, 31, 50 and T-DB-06 for the new tables, as owner, coach,
viewer, clip viewer, unrelated and anonymous users) and `money_03_integrity` (finding 18 unique-index test, one live
job, T-DB-53 table half, T-DB-59 FK half as `jovra_owner`, consent, output caps and planner budgets, finding 31
excerpts and artifact sources, clip-share audit and outbox rows, T-DB-48, T-DB-47 table half with a scan that is shown
to fail on a planted secret, upload sessions, append-only ledgers). `identity_01` and `media_01` lint the new objects
too (owner, search_path, RLS, quotas, FK covering indexes, one permissive policy per role and command).

Not covered here (later tickets): the command halves. T-DB-47's "run every secret-minting command" and T-DB-59's
`create_quote`/`review_job` `P0404` are S79 (gateway commands); T-DB-53's `set_job_state`, `reserve_stage`,
`finish_attempt` and `mark_artifact_verified` role checks are S80 (orchestrator commands); T-DB-48's deletion
Workflow is S94. Denial audit rows (`audit_denial`) are S79.

## Gateway commands (S79 / B-06, gateway half)

`migrations/20261008040000_gateway_commands_access.sql` and `migrations/20261008041000_gateway_commands_money.sql`
(architecture §5.1, §6.2, §6.3, §7.1, §7.2, §10; security-model §4.1, §13.1-13.7; findings 18 and 19):

- The user-route commands the gateway calls as `jovra_gateway`: `create_project`, `declare_source`,
  `create_camera_invite`, `revoke_camera_invite`, `redeem_camera_invite`, `approve_camera_invite`,
  `issue_guest_capability`, `guest_declare_source`, `authorize_upload`, `attach_upload_id`, `record_part`,
  `complete_upload_check`, `mark_uploaded_unverified`, `abort_upload`, `create_grant`, `redeem_grant`,
  `list_pending_members`, `approve_member`, `revoke_grant`, `revoke_member`, `create_share_link`,
  `redeem_share_link`, `request_deletion`, `create_quote`, `accept_quote`, `review_job` and `audit_denial`. Each is
  volatile, security definer, `search_path = ''`, owned by `jovra_owner` and executable by `jovra_gateway` only
  (never by `jovra_orchestrator` or a client role). Results that carry several values are returned as jsonb with
  the route's camelCase keys; internal micro-USD costs never leave the database.
- Every command re-checks its actor against current rows. An unrelated or unknown actor is `P0404`, identical to a
  missing object (T-DB-33); the gateway then records the refusal with `audit_denial`, an append-only second call
  that writes one `denied` row with a coded reason and reads nothing else.
- Uploads: per-session keys, one open session per source, exact part sizes, the streamed digest compared with the
  client's, completion only from the stored parts of the source's current session in its own live project
  (T-DB-38), and `uploaded_unverified` only after the head size matches.
- Camera invites and invitations: 10-minute single-use camera codes, approval by the device code derived from the key
  thumbprint, a device-bound guest capability (stored as a hash in `camera_invites.capability_hash`) (T-DB-39);
  every coach, lesson, film and clip invitation bound to the invitee's email HMAC, redeemable only by that confirmed
  email, else `P0404` like an unknown code (T-DB-58); a coach redemption stays pending until `approve_member`, whose
  view shows the masked verified email, never `display_name`; `revoke_grant` revokes the membership it created
  (T-DB-51).
- Money: `create_quote` computes the inputs, the inputs hash, the contract's `output_spec_sha256` and the estimate
  (rate card `rates-v0-inferred`, INFERRED values) from rows; sources resolve only through the project's current
  verified manifest and plans only within the project (T-DB-59). `accept_quote` is idempotent by its key, refuses
  expired quotes (`P0410`) and changed inputs or caps (`P0409`, also when a source changed since the quote), needs
  the tester flag outside the local stack, checks the owner open cap and the environment daily ceiling through
  `app_private.commit_spend` (fail closed, one advisory lock: T-DB-61, T-DB-71) and keeps one held reservation per
  `(project, plan, version, output)` also for plan-by-job work, or tops up that hold when the quote supersedes its
  quote after `budget_exceeded` (T-DB-56, T-DB-60). `review_job` approves, or revises within the remaining
  reservation and moves the job's and the hold's key together, else `P0409 requote_required`.
- `app_ops.settings` holds the environment name (`local` from `seed/01_settings.sql`; the operator writes `test` or
  `live` at G1). No row reads as `test`, so a missing row fails closed.
- `app_private.auth_user_facts` reads the auth schema (confirmed email, anonymous flag, Auth session creation time
  for the 10-minute re-authentication of account deletion). `jovra_owner` cannot read `auth`, so this one helper
  keeps the migration owner, is executable by `jovra_owner` only, and is the third named exception in T-DB-66.

Tests: `commands_gateway_01_catalog` (T-DB-04, T-DB-05, T-DB-57, the §4.1 template), `commands_gateway_02_uploads_cameras`
(T-DB-38, T-DB-39, T-DB-54 command half), `commands_gateway_03_grants_links_deletion` (T-DB-51, T-DB-58, share links,
deletion, T-DB-47 command half), `commands_gateway_04_money` (T-DB-34, 56, 59 command half, 60, 61, the tester flag,
output-hash vectors from `spec/reference/studio/core.py`) and `commands_gateway_05_actor_audit` (T-DB-33). T-DB-71 needs
two real concurrent transactions, which one pgTAP session cannot open, so it is `scripts/concurrent_accept_smoke.py`,
run by CI after the pgTAP suite.

Not covered here (later tickets): the orchestrator commands are S80 (below); the `*_for_attempt` upload variants; `cancel_job`,
`pause_job`, `resume_job` and `retry` belong with the state machine there too. The gateway Worker that calls these
commands, mints the bearer tokens, verifies device-key signatures and nonces and writes `idempotency_records` is
S83 onward. The no-audio share-link variant waits for S80's `remux_no_audio` (until then such a link is
`P0409 audio_variant_pending`). The rate card is INFERRED and refreshed at activation.

## Orchestrator commands (S80 / B-06, orchestrator half)

`migrations/20261008050000_orchestrator_commands.sql` (architecture §4.3, §7.1-§7.6, §10; security-model §4.1, §8.4,
§13.1, §13.6, §13.7, §13.9 (b); finding 13's database half):

- The commands `jovra-internal` calls as `jovra_orchestrator`, and nobody else: `set_job_state`, `reserve_stage`,
  `claim_attempt`, `heartbeat_attempt`, `finish_attempt`, `mark_artifact_verified`, `expire_attempt_leases`,
  `delete_lesson_rows` and `audit_denial_for_attempt`. Each is volatile, security definer, `search_path = ''`, owned by
  `jovra_owner` and executable by `jovra_orchestrator` only; the §13.1 lint (no `app_gateway` function executable by both
  command roles) returns zero rows (T-DB-53, T-DB-57).
- `set_job_state` is a compare-and-set against the SQL copy of `spec/studio/contracts/render-job-transitions.v1.json`
  (`app_private.job_transition_allowed`); a redelivered step replays; `render_jobs.resume_state` stores where a paused,
  retryable or budget-stopped job returns to; `ready` still needs a verified delivered film (`b10_check_job_state`); a
  terminal state cancels open attempts and settles (ready) or releases the hold.
- `reserve_stage` prices the stage in SQL from a versioned rate card (`app_ops.rate_cards`, `app_ops.stage_rates`, seeded
  with `rates-v0-inferred`; every stage floor is positive, so a zero estimate is impossible) and the quote's inputs; it
  refuses beyond the hold's cap or the environment ceiling (`P0402`), lists as `input_refs` only the quote's sources that
  are still verified in the current manifest plus this job's verified artifacts (`P0409 inputs_changed` when a source
  changed), stores an output plan with a byte cap per output, and writes `planner_budget` for the plan stage from what
  the reservation covers: the first model call and its repair, else no repair, else a zero budget (heuristic fallback).
  It is idempotent on `(job, stage, attempt)` and replays the charged attempt for a stage already charged.
- `claim_attempt` mints the `jvl_` lease token and stores only its SHA-256; `heartbeat_attempt` and `finish_attempt`
  are fenced by that hash and `leased_until` (`P0409 stale_lease` / `lease_expired`); `expire_attempt_leases` is the
  reconciler's sweep. The hold's reserved total is what is committed now (charged stages plus open stage
  reservations): a success turns its stage reservation into one charge (at most the reservation; one succeeded attempt
  per `(job, stage)`, unique index), a failure or an expiry returns it, an actual cost above it is committed as
  `stage_overrun` and stops the job at `budget_exceeded`. Outputs are registered as `verifying` artifacts under
  server-generated keys, only when they are in the attempt's output plan and within their caps, with their sources in
  `artifact_sources`. The plan stage of plan-by-job work moves the job and its hold to `(plan, V, hash of V)` in the same
  transaction (`P0409 requote_conflict` if another hold owns that key).
- `mark_artifact_verified` belongs to the `verify_output` stage, under its own lease.
- `delete_lesson_rows` is the row step of a lesson-scope deletion: Progress plans keep their other lessons, their
  versions become invalid and stale, and the request reaches `done` (T-DB-73).
- Two fixes to S79's money commands found by the ledger replay: a redelivered acceptance replays after a top-up
  superseded its quote, and `commit_spend` refuses every commitment in the `live` environment
  (`P0409 live_charging_not_activated`, ADR-0013).

Tests: `commands_orchestrator_01_catalog` (T-DB-04, T-DB-53, T-DB-57, the §4.1 template, rate-card guards),
`commands_orchestrator_02_stages` (T-DB-36, T-DB-53 ready, T-DB-55, T-DB-72 SQL half, the transition table, one charge per
stage), `commands_orchestrator_03_leases` (T-DB-37, claims, heartbeats, expiry, failures, redeliveries, cancel,
`audit_denial_for_attempt`, T-DB-47 for the lease token) and `commands_orchestrator_04_plan_keys_deletion` (T-DB-68,
T-DB-73). `scripts/ledger_vector_replay.py` (CI step after T-DB-71) replays every sequence of
`spec/studio/fixtures/vectors/ledger.json` through the SQL commands and compares the balances read from
`usage_reservations`, and checks the SQL transition table against the contract for every pair of job states. The
script's docstring lists the few vector rules it enforces itself because they have no separate database request
(a reservation below the quote's cap, non-integer amounts, a refused acceptance, job naming) and the ones that live in
the gateway or the app (demo identities, illustrative quotes).

Not covered here (later tickets): the `*_for_attempt` upload and read variants (`authorize_output_upload_for_attempt`,
`record_part_for_attempt`, `complete_upload_check_for_attempt`, `authorize_attempt_input`) and the gateway Worker that
calls these commands (S82 onward); the deletion Workflow that deletes objects before `delete_lesson_rows` (S94);
`cancel_job`, `pause_job`, `resume_job` and `retry` as user commands; the planner fixture half of T-DB-72 (S88/S89).
The rate cards are INFERRED and refreshed at activation.
