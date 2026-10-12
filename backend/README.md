# JOVRA backend

The Studio cloud backend (ADR-0014, ADR-0018, ADR-0022), built as code and tested locally. Nothing here is
provisioned: there is no hosted project, URL, key or account in this tree, and none may be added by an agent
(ADR-0014, activation gate 1). The app never needs this backend; recording, scoring and local films work offline.

Design: `docs/backend/architecture.md` (layout §1.2, local test strategy §12, gates §13, tickets §15) and
`docs/backend/security-model.md`.

## Subprojects

| Folder | What | Test command | CI workflow | Status |
|---|---|---|---|---|
| `supabase/` | Local Supabase project: config, migrations, seed testers, pgTAP suite | `supabase test db` (see below) | `.github/workflows/backend-db.yml` | Scaffold (S75 / B-02); migrations 1 (S76 / B-03) and 2 (S77 / B-04) |
| `gateway/` | Cloudflare signing gateway Worker | — | — | Not started (B-07) |
| `render/` | Render-host image | — | — | Not started (B-13) |
| `contracts/` | Gateway and queue JSON Schemas | — | — | Not started (B-01) |

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
`supabase start`, `supabase db reset`, the security advisors (fail on warn), `supabase test db`, the OTP smoke
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
- Every client-insertable table has `a00_rls_guard` (one function, `app_private.rls_guard()`, calling the same
  `can_insert_<table>` predicate as the INSERT policy) and coded `P0422` validation before constraints.

Tests: `media_01_catalog` (tables, composite FKs and delete actions, append-only grants, hidden columns, quota
lints, command privileges, T-DB-01 for the new tables), `media_02_sources_events` (T-DB-12, 13, 14, 15, 16, 24, 43,
59 FK half, the `parent_revision` variant of T-DB-65), `media_03_lessons_clips` (T-DB-17, 18–23, 41, 42, 45, 46, 49,
52, 62, 69; stories 173 and 179) and `media_04_quotas` (T-DB-64, 70).

Not covered here (later tickets): the render_jobs/quotes half of T-DB-59 and the `render_attempts.lease_token_hash`
and `quotes.cap_cost_micro_usd` columns of T-DB-17 (S78 creates those tables); the gateway `404` halves of
T-DB-46/62 (gateway routes, S83 onward); `lesson_embeddings` in T-DB-49 (B-20); audit rows for the clip-share
commands and the outbox row that deletes an unlinked excerpt's object (`app_ops.audit_events`, `app_ops.job_outbox`,
S78); `create_grant`'s creator checks (S79).
