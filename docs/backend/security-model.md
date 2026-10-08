# JOVRA Studio backend security model (design, not provisioned)

Status: **proposed design, 2026-10-07.** Nothing here is deployed. The SQL is illustrative design text written to be
turned into migrations and pgTAP tests by the tickets in `architecture.md` §15; it has not been executed against any
database. Labels: **OBSERVED** (cited official doc, carried from `docs/research/studio/backend-architecture.md`, read
2026-10-07, not re-fetched), **INFERRED** (design reasoning), **UNVERIFIED** (needs a spike or a provisioned account).

Read with [`architecture.md`](architecture.md) (topology, tables and columns, API, flows).

## 1. Trust boundaries and principles

```
 ┌──────────── untrusted ─────────────┐   ┌──────── trusted, least privilege ────────┐   ┌── trusted data ──┐
 │ native app, its requests, its JSON │   │ Gateway Worker: user routes (jovra_gateway)│   │ Postgres ledger  │
 │ camera guest phones                │──►│ jovra-internal Worker: Workflow, Queue    │──►│ R2 objects       │
 │ share-link holders                 │   │   consumer, host routes (orchestrator)    │   └──────────────────┘
 │                                    │   │ Render host (no DB, attempt-scoped media) │
 │ media bytes (hostile parser input) │   └───────────────────────────────────────────┘
 │ model output (proposal only)       │        ▲ Planner provider (external; receives consented frames + IDs)
 └────────────────────────────────────┘
```

Principles (INFERRED from the brief and OBSERVED Supabase/R2 behaviour):

1. **Deny by default, twice.** RLS denies rows; the gateway denies objects. RLS covers Postgres only and never R2
   (brief). Every media operation is authorized against current rows at the moment it happens.
2. **Roles live in tables, never in token claims.** A claim is frozen until the next token (default 1 h), which would
   delay revocation. Policies read only `auth.uid()` and the `is_anonymous` claim.
3. **The client is never authoritative** for `owner_id`, roles, prices, caps, R2 keys, bucket names, URLs, provenance
   `validated`, verification state or job state.
4. **Privileged changes are named functions**, each re-checking its actor, callable only by the `jovra_gateway`
   database role. The Supabase secret key (which bypasses RLS, OBSERVED
   https://supabase.com/docs/guides/api/api-keys) is not used on request paths.
5. **Short, narrow capabilities.** One object or one session, one operation set, short expiry, hashed at rest,
   checked against rows on every use.
6. **Model output is data.** It is validated against an allowlist and compiled by deterministic code; it never
   becomes a command, path, URL or filter string.
7. **Local originals are never at risk.** No server action deletes or modifies anything on the phone.

## 2. Identity and token verification

### 2.1 Accepted identities per environment

| Identity | Demo | Test | Live | How it is proven |
|---|---|---|---|---|
| Demo profile | yes (local only) | no | no | Nothing to prove: it never reaches a server |
| Sign in with Apple user | no | yes | yes | Apple ID token + raw nonce exchanged with Supabase (`signInWithIdToken`); hashed nonce sent to Apple (OBSERVED, https://supabase.com/docs/guides/auth/social-login/auth-apple); `skip_nonce_check = false` |
| Email OTP user | no | yes (pre-created testers only) | yes | Six-digit code, 60 s request window, 1 h expiry (OBSERVED, https://supabase.com/docs/guides/auth/auth-email-passwordless). In test: **sign-ups disabled on the Auth project** (`enable_signup = false`; testers are created by the operator script) **and** a mandatory `before_user_created` hook that rejects any email not on the allow-list (§13.3). `shouldCreateUser: false` is a client request parameter and is never relied on |
| Anonymous Supabase user | no | optional, lobby experiments only | **off** | `is_anonymous` claim; a restrictive policy denies every Studio table (§5.1) |
| Camera guest | no | yes | yes | Invite code (one use, 10 min) + host approval + device key proof → guest capability (§8.2); no Supabase identity |
| Render host | no | yes | yes | Host credential + attempt lease token (§8.4); no Supabase identity, no DB credential |

### 2.2 Gateway JWT verification (every user request)

1. Parse `Authorization: Bearer`; reject anything else on user routes.
2. Header `alg` must be `ES256`; `kid` must be in the environment's JWKS fetched from
   `https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json` with `createRemoteJWKSet` + `jwtVerify`
   (OBSERVED pattern, https://supabase.com/docs/guides/auth/jwts; ES256 recommended and HS256 legacy secret "not
   recommended for production", OBSERVED https://supabase.com/docs/guides/auth/signing-keys).
3. `iss` equals the pinned issuer for this environment; `aud = authenticated`; `exp` in the future with ≤ 60 s skew;
   `sub` is a UUID; `role = authenticated`.
4. Owner, coach, viewer and grant routes require `is_anonymous = false`.
5. Account-scope deletion and payment-adjacent routes (later) require a **fresh authentication**, not a fresh token:
   `iat` is reset by every silent refresh, so it proves nothing. The gateway reads the authentication time from the
   `amr` claim (optional in Supabase JWTs, OBSERVED in the research §3.4; the latest `amr[].timestamp` must be within
   10 minutes; claim shape **UNVERIFIED**, checked against
   https://supabase.com/docs/guides/auth/jwt-fields at G1), or, if that claim is unusable, requires a re-authentication
   bound to the request: a fresh SIWA ID token whose nonce hashes the deletion request id, or an email code from
   Supabase's reauthentication flow (UNVERIFIED for this use). A refreshed token with an old authentication time gets
   `401 reauth_required` (T-GW-31).
6. The verified `sub` is passed to command functions as `p_actor`; nothing else from the token is trusted for
   authorization.

There is no "demo token". A request with no signature, an unknown `kid`, an HS256 token or a body/header claiming demo
mode fails at step 1–3 (test T-GW-03/04).

### 2.3 Apple account deletion

Apps with Sign in with Apple are expected to revoke user tokens through Apple's REST API on account deletion (OBSERVED,
https://developer.apple.com/support/offering-account-deletion-in-your-app/). That needs an authorization code at
sign-in exchanged for a refresh token, and a server-held Apple key to call the revoke endpoint. Design: the app sends
the authorization code once to `POST /v1/account/apple-link` after sign-in; the gateway exchanges it and stores only
the encrypted refresh token in Supabase Vault (UNVERIFIED that Vault is the right store; Q2); the deletion Workflow
calls revoke and then deletes the auth user. Whether Supabase performs revocation itself is **UNVERIFIED**.

## 3. Postgres roles, schemas and grants

| Role | Login | Purpose | Grants |
|---|---|---|---|
| `anon` | via PostgREST | unauthenticated requests | **none** on any Studio object (all revoked) |
| `authenticated` | via PostgREST | signed-in users | column-scoped grants listed per table in §5; USAGE on `app_private`; EXECUTE on the `app_private` helpers only |
| `jovra_gateway` | yes, via Hyperdrive with query caching disabled (password is a Hyperdrive secret, set by Jon), bound **only** to the user-facing gateway Worker | the gateway's user routes | USAGE on `app_gateway`; EXECUTE on the user-route commands only; **no table privileges anywhere**; `connection limit 20`; `nobypassrls` |
| `jovra_orchestrator` | yes, via a second Hyperdrive config (caching disabled) bound only to the separate **`jovra-internal` Worker script** (Workflow, queue consumer, render-host routes), never to the user gateway (§13.1) | job orchestration | EXECUTE on `set_job_state`, `reserve_stage`, `claim_attempt`, `heartbeat_attempt`, `finish_attempt`, `register_artifact`, `mark_artifact_verified`, `authorize_attempt_input` and the `*_for_attempt` upload and read variants; nothing else. Because no user-route code runs in a script that holds this binding, a user-route bug or compromised dependency cannot move a job or verify an artifact |
| `jovra_owner` | no | owns **every** Studio table, every `app_private` helper and trigger function and every `app_gateway` command (one owner, so definer helpers run as the table owner and do not re-enter RLS; tables are not `FORCE ROW LEVEL SECURITY`) | owner of objects; not used by any client; migrations create objects and then `alter … owner to jovra_owner` (T-DB-66) |
| `service_role` / secret key | — | migrations, operator scripts only | never in the Worker request path, never in an app |

```sql
-- Schemas
create schema if not exists app_private;   -- RLS helpers + trigger functions; NOT exposed through PostgREST
create schema if not exists app_gateway;   -- command functions; NOT exposed
create schema if not exists app_ops;       -- server-only tables (upload parts, outbox, idempotency, audit); NOT exposed
revoke all on schema app_private, app_gateway, app_ops from public, anon, authenticated;
grant usage on schema app_private to authenticated;          -- policies call helpers as the querying role

-- Supabase grants table privileges in public to anon/authenticated by default; every Studio migration
-- revokes them and grants back only what §5 lists.
revoke all on all tables in schema public from anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges in schema app_gateway revoke execute on functions from public, anon, authenticated;
-- ALTER DEFAULT PRIVILEGES without FOR ROLE applies only to objects the migrating role creates, and a one-off
-- "revoke ... on all functions" covers only functions existing at that moment; so also:
alter default privileges for role jovra_owner in schema app_private, app_gateway, public
  revoke execute on functions from public, anon, authenticated;

-- Gateway role (password supplied out of band; never in a migration)
create role jovra_gateway with login noinherit nobypassrls connection limit 20;
create role jovra_orchestrator with login noinherit nobypassrls connection limit 10;
grant usage on schema app_gateway to jovra_gateway, jovra_orchestrator;
```

Hyperdrive query caching is disabled for both configs (`--caching-disabled`). OBSERVED: it is on by default
(`max_age` 60 s, 15 s stale-while-revalidate) and finds uncacheable queries by "text-based pattern matching"
(https://developers.cloudflare.com/hyperdrive/concepts/query-caching/). A cached `authorize_*` or command result would
undo per-request revocation (§8.5) or skip a state change (test T-GW-21).

PostgREST exposed schemas stay `public, graphql_public`; `app_*` schemas are never added (a `security definer`
function in an exposed schema is callable over the Data API with its owner's privileges, OBSERVED
https://supabase.com/docs/guides/database/postgres/row-level-security). Test T-DB-35 asserts the config.

Fallback if Hyperdrive with a custom role fails its spike (Q5): **not pre-approved.** PostgREST can call only
functions in exposed schemas, so the fallback would break T-DB-35/E1 and put the secret key on the request path
(principle 4, ADR-0018). It therefore needs its own ADR-0018 amendment, which must use a dedicated exposed schema
`app_rpc` of thin wrappers around `app_gateway` with EXECUTE granted to `service_role` only, keep the secret key in a
separate internal Worker that is not on the user route (the user-facing gateway calls it over a service binding), and
update T-DB-03 and T-DB-35 to allow exactly `app_rpc`. The functions still re-check `p_actor`.

## 4. Helper functions

All helpers: `security definer` (so a lookup on `project_members` inside a `project_members` policy does not recurse;
this holds only because the helper and the tables have the **same owner**, `jovra_owner`, and no table is
`FORCE ROW LEVEL SECURITY`: T-DB-66 asserts `proowner = relowner` for every helper and every table it reads),
`set search_path = ''`, fully qualified names, `stable`, owned by `jovra_owner`, EXECUTE revoked from `public` and
`anon` and granted to `authenticated` (OBSERVED pattern, https://supabase.com/docs/guides/database/functions). Tables
are not `FORCE ROW LEVEL SECURITY`, so the owner-run lookups see rows (INFERRED; documented choice).

```sql
create or replace function app_private.is_real_user() returns boolean
language sql stable set search_path = '' as $$
  select (select auth.uid()) is not null
     and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
$$;

create or replace function app_private.project_role(p_project uuid) returns public.member_role
language sql stable security definer set search_path = '' as $$
  select m.role
    from public.project_members m
    join public.projects p on p.id = m.project_id
   where m.project_id = p_project
     and m.user_id    = (select auth.uid())
     and m.revoked_at is null
     and (m.expires_at is null or m.expires_at > now())
     and (m.role = 'owner' or m.approved_at is not null)   -- a redeemed coach code is pending until the owner approves
     and p.deleted_at is null
$$;

create or replace function app_private.has_project_role(p_project uuid, p_roles public.member_role[])
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(app_private.project_role(p_project) = any (p_roles), false)
$$;

-- An access grant is active when redeemed (or a share link), not revoked and not expired.
create or replace function app_private.grant_active(g public.access_grants) returns boolean
language sql stable security definer set search_path = '' as $$
  select g.revoked_at is null
     and (g.expires_at is null or g.expires_at > now())
     and (g.kind = 'share_link' or g.redeemed_at is not null)
$$;

-- 'owner' | 'coach' | 'viewer' | null
create or replace function app_private.lesson_access(p_lesson uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from public.lessons l
                  where l.id = p_lesson and l.owner_id = (select auth.uid())) then 'owner'
    when exists (select 1 from public.access_grants g
                  where g.lesson_id = p_lesson and g.kind = 'lesson_coach'
                    and g.grantee_user_id = (select auth.uid()) and app_private.grant_active(g)) then 'coach'
    when exists (select 1 from public.access_grants g
                  where g.lesson_id = p_lesson and g.kind = 'lesson_view'
                    and g.grantee_user_id = (select auth.uid()) and app_private.grant_active(g)) then 'viewer'
  end
$$;

-- A clip is visible only while (a) its project is not deleted, (b) the lesson owner still holds a role on the clip's
-- project, and (c) for anyone but the lesson owner, the clip is shareable: the lesson owner owns the project or the
-- project owner approved sharing it. Revoking a coach therefore removes every downstream viewer's access too.
create or replace function app_private.can_view_lesson_clip(p_clip uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.lesson_clips c
      join public.lessons l  on l.id = c.lesson_id
      join public.projects p on p.id = c.project_id and p.deleted_at is null
     where c.id = p_clip
       and exists (select 1 from public.project_members m
                    where m.project_id = c.project_id and m.user_id = l.owner_id and m.revoked_at is null
                      and (m.expires_at is null or m.expires_at > now())
                      and (m.role = 'owner' or m.approved_at is not null))
       and (l.owner_id = (select auth.uid())
            or ((p.owner_id = l.owner_id or c.share_approved_at is not null)
                and (app_private.lesson_access(c.lesson_id) in ('coach', 'viewer')
                     or exists (select 1 from public.access_grants g
                                 where g.lesson_clip_id = c.id and g.kind = 'lesson_clip_view'
                                   and g.grantee_user_id = (select auth.uid()) and app_private.grant_active(g))))))
$$;

-- Viewer path only (owners and coaches use has_project_role). A viewer may see a granted film or clip excerpt
-- and that artifact's thumbnail, captions and chapters; nothing else.
create or replace function app_private.viewer_can_see_artifact(p_artifact uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  with a as (
    select coalesce(x.parent_artifact_id, x.id) as root_id, x.kind
      from public.artifacts x
     where x.id = p_artifact and x.state = 'ready' and x.deleted_at is null
  ), root as (
    select r.id, r.kind from public.artifacts r join a on r.id = a.root_id
     where r.state = 'ready' and r.deleted_at is null and r.kind in ('film', 'clip_excerpt')
  )
  select exists (select 1 from a, root
                  where (a.kind in ('film', 'clip_excerpt') and a.root_id = root.id)
                     or a.kind in ('thumbnail', 'captions', 'chapters'))
     and exists (select 1 from public.artifacts r join public.projects p on p.id = r.project_id, root
                  where r.id = root.id and p.deleted_at is null)   -- viewers lose access when deletion starts
     and (
       exists (select 1 from public.access_grants g, root
                where g.artifact_id = root.id and g.kind = 'film_view'
                  and g.grantee_user_id = (select auth.uid()) and app_private.grant_active(g))
       or exists (select 1 from public.lesson_clips c, root
                   where c.excerpt_artifact_id = root.id and app_private.can_view_lesson_clip(c.id))
     )
$$;

create or replace function app_private.shares_project_with(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.project_members a
                   join public.project_members b on a.project_id = b.project_id
                   join public.projects p on p.id = a.project_id and p.deleted_at is null
                  where a.user_id = (select auth.uid()) and b.user_id = p_user
                    and a.revoked_at is null and b.revoked_at is null
                    and (a.expires_at is null or a.expires_at > now())
                    and (b.expires_at is null or b.expires_at > now())
                    -- the same activity predicate as project_role, on both sides: a pending (unapproved) coach shares
                    -- nothing yet, so a stranger awaiting approval cannot read members' display names (T-DB-63)
                    and (a.role = 'owner' or a.approved_at is not null)
                    and (b.role = 'owner' or b.approved_at is not null))
$$;

revoke execute on all functions in schema app_private from public, anon;
grant execute on function app_private.is_real_user(), app_private.project_role(uuid),
  app_private.has_project_role(uuid, public.member_role[]), app_private.lesson_access(uuid),
  app_private.can_view_lesson_clip(uuid), app_private.viewer_can_see_artifact(uuid),
  app_private.shares_project_with(uuid) to authenticated;
-- grant_active(access_grants) and all trigger functions: no EXECUTE for authenticated.
```

Hash functions use `extensions.digest(...)` and random bytes `extensions.gen_random_bytes(...)` (pgcrypto lives in
the `extensions` schema on Supabase); no function ever pins `search_path = public` (repo lint, §11). The lint and
T-DB-03 cover every function in `public` too (the `security invoker` embedding retrieval function sets
`search_path = ''` and qualifies its operator as `OPERATOR(extensions.<=>)`).

### 4.1 Command functions (`app_gateway`)

Template (every command follows it):

```sql
create or replace function app_gateway.<name>(p_actor uuid, …, p_request_id uuid)
returns … language plpgsql security definer set search_path = '' as $$
begin
  -- 1. Re-check the actor against current rows (ownership, membership, invite, lease) with FOR UPDATE where state changes.
  -- 2. Validate every input against server-held expectations; never accept keys, prices or roles from the caller.
  -- 3. Perform the transition; write app_ops.audit_events ('allowed') in the same transaction.
  -- 4. Raise coded errors: P0401 unauthorized, P0404 not_found (also used for "exists but not yours"),
  --    P0409 conflict, P0410 expired, P0422 invalid, P0402 budget_exceeded.
end $$;
revoke all on function app_gateway.<name>(…) from public, anon, authenticated;
grant execute on function app_gateway.<name>(…) to jovra_gateway;   -- or to jovra_orchestrator, never both
-- A command that serves both a user and a render attempt exists twice: the user variant (jovra_gateway; actor kinds
-- 'user' and 'camera_guest' only) and a *_for_attempt variant (jovra_orchestrator; lease-fenced). T-DB-57.
```

A raised exception rolls back the transaction, including any audit row written in it, so **denials are audited by a
second call** `app_gateway.audit_denial(p_actor_kind, p_actor, p_action, p_target_kind, p_target, p_reason,
p_request_id)` that the gateway makes after catching the error (INFERRED; T-GW-19 checks denials appear).

Commands (signatures abbreviated; all take `p_request_id`):

| Function | Actor check | Notes |
|---|---|---|
| `declare_source(p_actor, p_project, p_slot, p_local_source, p_bytes, p_sha256, p_client_probe)` | owner | slot free; bytes ≤ cap; client probe allowlisted to codec/width/height/fps/duration/rotation and stored as `client_probe` |
| `create_camera_invite(p_actor, p_project, p_slot, p_label, p_code_hash)` | owner | locks the slot `FOR UPDATE`, revokes an expired unredeemed invite, ≤ 5 live invites; `redeem_by = now() + 10 min` |
| `redeem_camera_invite(p_code_hash, p_device_key_thumbprint, p_device_label, p_user uuid null)` | code | single use; returns redemption id and the 6-digit device code derived from the thumbprint; `p_user` is passed only from a verified JWT `sub` (never from the body); rate-limited by gateway |
| `approve_camera_invite(p_actor, p_invite, p_redemption, p_device_code)` | owner | device code equals the one derived from the stored thumbprint; sets `approved_at`, `capability_expires_at ≤ now()+24 h` |
| `issue_guest_capability(p_invite, p_device_key_thumbprint, p_capability_hash)` | approved invite, matching device key | |
| `guest_declare_source(p_invite, p_capability_hash, p_local_source, p_bytes, p_sha256, p_probe)` | guest capability | one source per invite; `participant_ack_at` required |
| `authorize_upload(p_actor_kind, p_actor, p_source, p_bytes, p_sha256)` → `(session, key)` | owner or guest of that slot (`p_actor_kind` ∈ `user`, `camera_guest`; anything else `P0422`) | bytes/hash equal declaration; source state `declared`/`uploading`; aborts any open session of the source and sets `current_session_id`; per-session key; refused when the project has `deleted_at` |
| `attach_upload_id`, `record_part`, `complete_upload_check`, `mark_uploaded_unverified`, `abort_upload` | session capability + fresh actor check (user or guest sessions only) | architecture §6.3 (completion requires `current_session_id` and state `uploading`); `record_part` refuses when the project has `deleted_at` |
| `authorize_output_upload_for_attempt(p_attempt, p_lease_hash, p_output_ref, p_bytes, p_sha256)`, `record_part_for_attempt`, `complete_upload_check_for_attempt`, `mark_output_written_for_attempt`, `authorize_artifact_read_for_attempt(p_attempt, p_lease_hash, p_artifact)` | **orchestrator role only**; current lease | `p_output_ref` ∈ the attempt's `output_plan`, `p_bytes` ≤ that output kind's cap stored in `output_plan` (§13.15); reads only the verify stage's own outputs or listed inputs |
| `create_quote(p_actor, p_project, p_plan, p_planner_choice, p_output_spec, p_sources, p_retention_days)` | owner | every source resolved through this project's current verified source manifest (else `P0404`); inputs and `output_spec_sha256` computed from rows; `sample` forced true unless paid flag on |
| `accept_quote(p_actor, p_quote, p_inputs_sha256, p_consent, p_cap_credits, p_idempotency_key)` | owner, real user | one transaction: owner open-cap and environment ceilings; reservation + job + outbox, or a top-up of the held reservation when the quote supersedes its quote; one held reservation per `(project, plan version, output spec)` |
| `set_job_state(p_job, p_expected, p_new)` | orchestrator role | compare-and-set against the SQL transition table (the contract's); `ready` requires a verified artifact; resume stages restricted as in the contract |
| `reserve_stage(p_job, p_stage, p_attempt)` → `attempt_id` | orchestrator role | estimate computed in SQL from `rates_version` and inputs with a floor; cap and environment ceiling; stores `input_refs` and `output_plan` from the job's own project; idempotent; no lease yet |
| `claim_attempt(p_attempt, p_host)` → `lease_token` | orchestrator role (internal route, host credential) | mints the token, stores its hash; second claim refused |
| `heartbeat_attempt(p_attempt, p_lease_hash)` / `finish_attempt(p_attempt, p_lease_hash, p_outcome, p_outputs, p_measurements)` | orchestrator role; lease fencing | consumption written on success only, once per `(job, stage)` |
| `register_artifact`, `mark_artifact_verified` | orchestrator role; lease fencing / verify stage | output ref ∈ the attempt's stored `output_plan` |
| `authorize_artifact_read(p_actor_kind, p_actor, p_artifact)` | owner/coach/viewer/share token (`p_actor_kind` ∈ `user`, `share_link`) | mirrors §5 artifact policies + `viewer_can_see_artifact` logic for an explicit actor; render attempts use `authorize_artifact_read_for_attempt` |
| `authorize_attempt_input(p_attempt, p_lease_hash, p_input_ref)` | orchestrator role; lease | `p_input_ref` ∈ the attempt's stored `input_refs`; returns the key and verified etag only to the gateway |
| `create_grant`, `redeem_grant`, `approve_member`, `revoke_grant`, `approve_clip_share`, `revoke_clip_share`, `create_share_link`, `redeem_share_link(p_token_hash)`, `revoke_member` | owner / redeemer / project owner of the footage | share links only for `film`, `preview`, `clip_excerpt`; ≤ 24 h. Every invitation grant is **bound to its intended recipient** (`invitee_email_hmac`); `redeem_grant` succeeds only when the redeemer's confirmed `auth.users.email` matches it, else `P0404` like a missing code (§13.2). `redeem_grant` of a `project_coach` code creates a **pending** membership; `approve_member` (owner) activates it after seeing the redeemer's verified, masked email (never the display name). `revoke_clip_share` and `revoke_grant` are also available to the owner of the project whose footage a clip-bearing grant reaches (§13.8). `revoke_grant` of a `project_coach` grant revokes the linked `project_members` row in the same transaction. Clip-bearing grants need each clip shareable (creator owns the clip's project or the project owner approved it). `redeem_share_link` authorizes one request only: it never writes a grant or `grantee_user_id` |
| `cancel_job`, `pause_job`, `resume_job`, `review_job` | owner | |
| `request_deletion(p_actor, p_scope, p_target)` and deletion step functions | owner of target | |
| `audit_denial(…)` | gateway | append only |

Because the helpers in §4 read `auth.uid()`, which is null for `jovra_gateway`, command functions use explicit
`p_actor` comparisons instead of the helpers (INFERRED; T-DB-36 checks a forged actor fails everywhere).

## 5. RLS policies, table by table

### 5.1 Applied to every Studio table in `public`

```sql
alter table public.<t> enable row level security;
-- Anonymous Supabase users (test-only lobby experiments) never touch Studio tables.
create policy <t>_real_users_only on public.<t> as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
-- anon: no table grants at all, so unauthenticated requests fail before RLS.
```

Every column used in a policy is indexed (`project_id`, `owner_id`, `user_id`, `grantee_user_id`, `lesson_id`,
`uploader_user_id`, `redeemed_by_user_id`, `created_by`), and every policy names its role and wraps `auth.uid()` as
`(select auth.uid())` (OBSERVED performance guidance, RLS doc above). UPDATE policies have matching SELECT policies.

### 5.2 Identity and membership

```sql
-- profiles
grant select (id, display_name, created_at) on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or app_private.shares_project_with(id));
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
-- no insert (trigger on auth.users), no delete (account deletion workflow)

-- projects
grant select on public.projects to authenticated;
grant insert (local_project_id, title, kind, sample) on public.projects to authenticated;  -- owner_id defaults to auth.uid()
grant update (title, kind) on public.projects to authenticated;
create policy projects_select on public.projects for select to authenticated
  using (deleted_at is null
         and (owner_id = (select auth.uid()) or app_private.has_project_role(id, '{coach}')));
create policy projects_insert on public.projects for insert to authenticated
  with check (owner_id = (select auth.uid()) and deleted_at is null);
create policy projects_update on public.projects for update to authenticated
  using (owner_id = (select auth.uid()) and deleted_at is null)
  with check (owner_id = (select auth.uid()));
-- no delete grant: deletion goes through deletion_requests (R2 objects first)

-- project_members (writes only via app_gateway)
grant select on public.project_members to authenticated;
create policy members_select on public.project_members for select to authenticated
  using (user_id = (select auth.uid()) or app_private.has_project_role(project_id, '{owner}'));

-- camera_invites (writes only via app_gateway); code_hash and device thumbprint are never selectable
grant select (id, project_id, slot, display_label, redeem_by, redeemed_at, approved_at,
              capability_expires_at, max_bytes, revoked_at, created_at) on public.camera_invites to authenticated;
create policy invites_select on public.camera_invites for select to authenticated
  using (app_private.has_project_role(project_id, '{owner}')
         or (redeemed_by_user_id = (select auth.uid())
             and approved_at is not null and revoked_at is null));   -- nothing about the project before approval
```

### 5.3 Sources, manifests, sync, calibration, events, observations

```sql
-- camera_sources: r2_key never selectable; writes via app_gateway except the owner's label
grant select (id, project_id, slot, local_source_id, invite_id, uploader_user_id, label, state, declared_bytes,
              declared_sha256, verified_sha256, verified_at, probe, rejected_reason, participant_ack_at,
              created_at, updated_at, revision) on public.camera_sources to authenticated;
-- not granted: r2_key, verified_etag, current_session_id, client_probe (the device's declaration stays server-side)
grant update (label) on public.camera_sources to authenticated;
create policy sources_select on public.camera_sources for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}')
         or (uploader_user_id = (select auth.uid())            -- a signed-in camera sees only its own source,
             and exists (select 1 from public.camera_invites i  -- and only while its invite is approved and live
                          where i.id = invite_id and i.approved_at is not null and i.revoked_at is null)));
create policy sources_update_label on public.camera_sources for update to authenticated
  using (app_private.has_project_role(project_id, '{owner}'))
  with check (app_private.has_project_role(project_id, '{owner}'));

-- source_manifests: read-only to members; written by app_gateway
grant select on public.source_manifests to authenticated;
create policy manifests_select on public.source_manifests for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'));

-- sync_maps and calibration_versions: append-only; owner inserts; trigger assigns revision and forces
-- created_by/reviewed_by = auth.uid(); provenance 'validated' rejected by CHECK trigger on the client path
grant select on public.sync_maps to authenticated;
grant insert (project_id, source_manifest_revision, map, review_state, method, method_version, sample)
  on public.sync_maps to authenticated;
create policy sync_select on public.sync_maps for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'));
create policy sync_insert on public.sync_maps for insert to authenticated
  with check (app_private.has_project_role(project_id, '{owner}')
              and review_state in ('estimated', 'needs_review', 'reviewed'));

grant select on public.calibration_versions to authenticated;
grant insert (project_id, source_id, calibration, method, method_version, provenance)
  on public.calibration_versions to authenticated;
create policy calib_select on public.calibration_versions for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'));
create policy calib_insert on public.calibration_versions for insert to authenticated
  with check (app_private.has_project_role(project_id, '{owner}')
              and provenance in ('manual', 'estimated'));
-- (project_id, source_id) is a composite FK to camera_sources(project_id, id): no cross-project calibration

-- point_event_revisions: append-only; owner only; trigger enforces parent = current (P0409) and marks stale
grant select on public.point_event_revisions to authenticated;
grant insert (project_id, parent_revision, local_session_id, schema_version, event_log, client_device_id)
  on public.point_event_revisions to authenticated;
create policy events_select on public.point_event_revisions for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'));
create policy events_insert on public.point_event_revisions for insert to authenticated
  with check (app_private.has_project_role(project_id, '{owner}'));

-- observations: clients create only 'manual'; review may turn 'estimated' into 'reviewed' (trigger);
-- 'validated' only from a server stage tied to a validated capability
grant select on public.observations to authenticated;
grant insert (project_id, lesson_id, source_id, match_start_us, match_end_us, sync_map_revision, event_revision,
              capability_id, kind, body, sample) on public.observations to authenticated;   -- provenance defaults 'manual'
grant update (review_state, body) on public.observations to authenticated;
-- Access requires EVERY non-null parent (AND, never OR): a project coach cannot read a row that also belongs to a
-- lesson they have no access to, and vice versa.
create policy obs_select on public.observations for select to authenticated
  using ((project_id is null or app_private.has_project_role(project_id, '{owner,coach}'))
         and (lesson_id is null or app_private.lesson_access(lesson_id) in ('owner', 'coach'))
         and num_nonnulls(project_id, lesson_id) >= 1);
create policy obs_insert on public.observations for insert to authenticated
  with check (provenance = 'manual'
              and (project_id is null or app_private.has_project_role(project_id, '{owner,coach}'))
              and (lesson_id is null or app_private.lesson_access(lesson_id) in ('owner', 'coach'))
              and num_nonnulls(project_id, lesson_id) >= 1);
-- source_id: composite FK (project_id, source_id) → camera_sources(project_id, id), so it names this project's source
create policy obs_update on public.observations for update to authenticated
  using ((project_id is null or app_private.has_project_role(project_id, '{owner,coach}'))
         and (lesson_id is null or app_private.lesson_access(lesson_id) in ('owner', 'coach')))
  with check (provenance <> 'validated');
-- trigger: body may change only when created_by = auth.uid(); estimated→reviewed sets provenance 'reviewed',
-- reviewed_by = auth.uid(), reviewed_at = now(). No delete: reject instead (review_state 'rejected').
```

### 5.4 Lessons

```sql
grant select on public.lessons to authenticated;
grant insert (local_lesson_id, lesson_date, title, notes, next_goal, practice, sample) on public.lessons to authenticated;
grant update (lesson_date, title, notes, next_goal, practice) on public.lessons to authenticated;
-- no delete grant: a lesson owns derived media (clip excerpts, thumbnails); deletion is a deletion_requests job
-- (scope 'lesson') that removes objects first, then clips, lesson-only observations and embeddings
create policy lessons_select on public.lessons for select to authenticated
  using (owner_id = (select auth.uid()) or app_private.lesson_access(id) in ('coach', 'viewer'));
create policy lessons_insert on public.lessons for insert to authenticated
  with check (owner_id = (select auth.uid()));
create policy lessons_update on public.lessons for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

-- lesson_clips: excerpt_artifact_id is set only by app_gateway after rendering the excerpt
grant select on public.lesson_clips to authenticated;
grant insert (lesson_id, project_id, source_id, match_start_us, match_end_us, sync_map_revision, event_revision,
              keeper_ref, note, position) on public.lesson_clips to authenticated;
grant update (match_start_us, match_end_us, keeper_ref, note, position) on public.lesson_clips to authenticated;
-- no delete grant (deletion_requests scope 'lesson_clip' or 'lesson', so the clip_excerpt object goes first);
-- share_approved_at only via app_gateway. Trigger pin_shared_clip (§13.8): changing match_start_us, match_end_us or
-- keeper_ref clears share_approved_at and unlinks the excerpt, so an approval never follows a moved window.
create policy clips_select on public.lesson_clips for select to authenticated
  using (app_private.can_view_lesson_clip(id));
create policy clips_write on public.lesson_clips for insert to authenticated
  with check (app_private.lesson_access(lesson_id) = 'owner'
              and app_private.has_project_role(project_id, '{owner,coach}'));
create policy clips_update on public.lesson_clips for update to authenticated
  using (app_private.lesson_access(lesson_id) = 'owner')
  with check (app_private.lesson_access(lesson_id) = 'owner'
              and app_private.has_project_role(project_id, '{owner,coach}'));
-- (project_id, source_id) is a composite FK to camera_sources(project_id, id): a clip names its own project's source
```

Note: `clips_select` lets a lesson viewer see the clip row (window, note, keeper ref), not the project, its sources
or other clips; the media they can stream is only the `clip_excerpt` artifact (§5.6). A lesson owner who is only a
**coach** of the clip's project can attach the clip for their own use, but nobody else sees it until the project
owner approves sharing it, and everyone loses it when the coach's membership ends (`can_view_lesson_clip`).

### 5.5 Story plans

```sql
grant select on public.story_plans to authenticated;
grant insert (project_id, lesson_ids, profile_id, profile_revision, title, sample) on public.story_plans to authenticated;
grant update (title) on public.story_plans to authenticated;
create policy plans_select on public.story_plans for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'));
create policy plans_insert on public.story_plans for insert to authenticated
  with check (app_private.has_project_role(project_id, '{owner,coach}'));
  -- trigger check_story_plan_lessons: every lesson_ids entry has lesson_access(id) in ('owner','coach') for the
  -- caller AND its owner is the project owner; a lesson_view grantee can never bind a lesson into a plan
create policy plans_update on public.story_plans for update to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'))
  with check (app_private.has_project_role(project_id, '{owner,coach}'));

-- story_plan_versions: append-only; clients may add manual/heuristic drafts; validation_state, edl_sha256 and
-- planner_model_id are server-set; 'llm' versions only via app_gateway
grant select on public.story_plan_versions to authenticated;
grant insert (story_plan_id, planner_kind, planner_adapter_version, story_plan, edl,
              bound_source_manifest_revision, bound_sync_map_revision, bound_event_revision)
  on public.story_plan_versions to authenticated;
create policy versions_select on public.story_plan_versions for select to authenticated
  using (exists (select 1 from public.story_plans p where p.id = story_plan_id
                  and app_private.has_project_role(p.project_id, '{owner,coach}')));
create policy versions_insert on public.story_plan_versions for insert to authenticated
  with check (planner_kind in ('manual', 'heuristic')
              and exists (select 1 from public.story_plans p where p.id = story_plan_id
                           and app_private.has_project_role(p.project_id, '{owner,coach}')));
```

### 5.6 Jobs, money, artifacts, grants

```sql
-- quotes and usage_reservations: owner reads; internal cost columns hidden; no client writes
grant select (id, project_id, story_plan_version_id, inputs, inputs_sha256, rates_version, line_items,
              estimate_low_credits, estimate_high_credits, cap_credits, state, expires_at, accepted_at,
              consent, sample, created_at) on public.quotes to authenticated;
create policy quotes_select on public.quotes for select to authenticated
  using (owner_id = (select auth.uid()) and app_private.has_project_role(project_id, '{owner}'));

grant select (id, project_id, quote_id, job_id, cap_credits, state, sample, created_at, updated_at)
  on public.usage_reservations to authenticated;
create policy reservations_select on public.usage_reservations for select to authenticated
  using (owner_id = (select auth.uid()) and app_private.has_project_role(project_id, '{owner}'));

-- render_jobs / render_attempts: members read; lease, money and requester columns hidden; no client writes
grant select (id, project_id, story_plan_id, story_plan_version_id, parent_job_id, state, stage,
              stage_progress_milli, output_spec, error_code, cancel_requested_at, paused_at, review_requested_at,
              reviewed_at, sample, created_at, updated_at, finished_at) on public.render_jobs to authenticated;
-- not granted: requested_by, idempotency_key, quote_id, reservation_id, output_spec_sha256 (owners read money
-- through quotes/usage_reservations; the gateway returns usage to the owner only)
create policy jobs_select on public.render_jobs for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'));
grant select (id, job_id, stage, attempt, state, heartbeat_at, host_kind, error_code,
              retryable, created_at, started_at, finished_at) on public.render_attempts to authenticated;
-- not granted: measurements (planner tokens, CPU and wall time let a reader derive cost; coaches never see money,
-- T-DB-25); owners read usage through the gateway's owner-only `usage` block (§13.15)
create policy attempts_select on public.render_attempts for select to authenticated
  using (exists (select 1 from public.render_jobs j where j.id = job_id
                  and app_private.has_project_role(j.project_id, '{owner,coach}')));

-- artifacts: r2_key and bucket_class never selectable; no client writes
grant select (id, project_id, job_id, source_id, parent_artifact_id, kind, bytes, sha256, media, state,
              verification, edl_sha256, event_revision, sync_map_revision, source_manifest_revision,
              profile_id, profile_revision, renderer_version, stale, retention_until, display_title, sample,
              created_at, verified_at) on public.artifacts to authenticated;
create policy artifacts_select_members on public.artifacts for select to authenticated
  using (deleted_at is null
         and ((kind in ('preview', 'film', 'thumbnail', 'captions', 'chapters', 'edit_manifest', 'clip_excerpt')
               and app_private.has_project_role(project_id, '{owner,coach}'))
              or (kind = 'project_bundle' and app_private.has_project_role(project_id, '{owner}'))));
create policy artifacts_select_viewers on public.artifacts for select to authenticated
  using (app_private.viewer_can_see_artifact(id));

-- access_grants: creator and grantee read; token_hash hidden; writes via app_gateway
grant select (id, kind, project_id, lesson_id, artifact_id, lesson_clip_id, grantee_user_id, created_by,
              redeem_by, expires_at, redeemed_at, revoked_at, created_at) on public.access_grants to authenticated;
create policy grants_select on public.access_grants for select to authenticated
  using (created_by = (select auth.uid()) or grantee_user_id = (select auth.uid()));
```

### 5.7 Providers, deletion, embeddings, server-only tables

```sql
-- provider_connections: own rows only; status metadata, no tokens exist in the table
grant select, delete on public.provider_connections to authenticated;
grant insert (provider, state, account_label, scopes) on public.provider_connections to authenticated;
grant update (state, account_label, scopes) on public.provider_connections to authenticated;
create policy prov_all on public.provider_connections for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- deletion_requests: requester reads; created only through the gateway
grant select (id, scope, target_id, state, counts, error_code, created_at, updated_at, finished_at)
  on public.deletion_requests to authenticated;
create policy deletions_select on public.deletion_requests for select to authenticated
  using (requested_by = (select auth.uid()));

-- lesson_embeddings (optional): members of the project or owners/coaches of the lesson; never viewers
grant select (id, lesson_id, observation_id, project_id, content_sha256, embedding, model_id, created_at)
  on public.lesson_embeddings to authenticated;
-- every non-null parent must be accessible (AND): embeddings are invertible toward text
create policy emb_select on public.lesson_embeddings for select to authenticated
  using ((project_id is null or app_private.has_project_role(project_id, '{owner,coach}'))
         and (lesson_id is null or app_private.lesson_access(lesson_id) in ('owner', 'coach'))
         and (num_nonnulls(project_id, lesson_id) >= 1 or owner_id = (select auth.uid())));
-- retrieval function: security invoker, in public, so the policy above applies; sets hnsw.iterative_scan.

-- app_ops.* (upload_sessions, upload_parts, job_outbox, idempotency_records, audit_events):
-- no grants to anon or authenticated; reached only by app_gateway definer functions.
```

## 6. Role matrix and explicit tests

### 6.1 Database access matrix

S = select, I = insert, U = update (listed columns), D = delete, — = denied. "Own" = rows the actor created or is the
subject of. Columns not listed in §5 grants are denied even where S appears. Anonymous-authenticated users (test env
only) are denied everything by the restrictive policy. Camera guests, render hosts and the demo profile have **no
database credential**; they appear in §6.3 only. `jovra_gateway` has no table privileges (EXECUTE on `app_gateway.*`
only).

| Table | Unauthenticated | Unrelated user | Owner | Coach/editor | Viewer (grant) | Camera uploader (signed in) |
|---|---|---|---|---|---|---|
| profiles | — | S self; U self | S self + co-members; U self | S self + co-members; U self | S self; U self | S self; U self |
| projects | — | — | S, I, U(title, kind) | S | — | — |
| project_members | — | — | S project rows | S own row | — | — |
| camera_invites | — | — | S (no code hash) | — | — | S invites it redeemed, after approval, until revoked |
| camera_sources | — | — | S (no key), U(label) | S (no key) | — | S its own source, after approval, until revoked |
| source_manifests | — | — | S | S | — | — |
| sync_maps | — | — | S, I | S | — | — |
| calibration_versions | — | — | S, I (manual/estimated) | S | — | — |
| point_event_revisions | — | — | S, I (append, parent check) | S | — | — |
| observations | — | — | S, I (manual), U(review_state; body if author); every non-null parent accessible | S, I (manual), U (same) | — | — |
| lessons | — | own lessons: S, I, U (D via deletion request) | own lessons: S, I, U (D via deletion request) | S (lesson_coach) | S (lesson_view) | — |
| lesson_clips | — | own lessons' clips | S, I, U (own lessons; project owner/coach; same-project source) | S (while the lesson owner keeps a project role) | S (lesson_view or clip grant; only shareable clips) | — |
| story_plans | — | — | S, I, U(title) | S, I, U(title) | — | — |
| story_plan_versions | — | — | S, I (manual/heuristic) | S, I (manual/heuristic) | — | — |
| quotes | — | — | S (no internal cost) | — | — | — |
| usage_reservations | — | — | S (credits only) | — | — | — |
| render_jobs | — | — | S (granted columns; no money, key or requester) | S (same) | — | — |
| render_attempts | — | — | S (no lease, no cost) | S (same) | — | — |
| artifacts | — | — | S client-visible kinds incl. `project_bundle` (no key) | S client-visible kinds except `project_bundle` | S granted ready film/clip + its thumbnail, captions, chapters, while the project is not deleted | — |
| access_grants | — | S where grantee | S created (no token hash) | S where grantee | S where grantee | — |
| provider_connections | — | own: S, I, U, D | own | own | own | own |
| deletion_requests | — | S own | S own | S own | S own | S own |
| lesson_embeddings | — | own lessons | S | S | — | — |
| app_ops.* | — | — | — | — | — | — |

Writes to `project_members`, `camera_invites`, `camera_sources` (except label), `source_manifests`, `quotes`,
`usage_reservations`, `render_jobs`, `render_attempts`, `artifacts`, `access_grants`, `deletion_requests`,
`lesson_embeddings` and `app_ops.*` are denied to every client role; they happen only in `app_gateway` functions.

### 6.2 Database tests (pgTAP, `supabase test db`)

Each test runs in `begin … rollback`, authenticates as a seeded fictional user, and must be able to fail.

| ID | Role | Action | Expected |
|---|---|---|---|
| T-DB-01 | unauthenticated | select/insert on every `public` Studio table | permission denied |
| T-DB-02 | — | `tests.rls_enabled('public')` | every table has RLS |
| T-DB-03 | — | no `security definer` function in `public`; every function in `app_*` **and in `public`** has `search_path=''` in `proconfig`; no function in `app_private`/`app_gateway`/`public` is executable by `public` or `anon` (including functions created after the first migration) | pass |
| T-DB-04 | authenticated, anon | EXECUTE on any `app_gateway.*` | denied (`function_privs_are`) |
| T-DB-05 | jovra_gateway, jovra_orchestrator | select/insert on any table in `public`, `app_private`, `app_ops` | denied (`table_privs_are`) |
| T-DB-06 | unrelated user | select from projects, camera_sources, source_manifests, sync_maps, calibration_versions, point_event_revisions, observations, story_plans, story_plan_versions, quotes, usage_reservations, render_jobs, render_attempts, artifacts of owner A | 0 rows each |
| T-DB-07 | unrelated user | insert project specifying `owner_id = A` | permission denied (column not granted) |
| T-DB-08 | owner | update `projects.owner_id` | permission denied |
| T-DB-09 | owner | update another owner's project title | 0 rows |
| T-DB-10 | owner, coach | insert into `project_members` (self-grant, role escalation) | denied |
| T-DB-11 | coach | update project title | 0 rows |
| T-DB-12 | coach | insert point_event_revisions | RLS violation |
| T-DB-13 | owner | insert event revision with stale `parent_revision` | `P0409`; with current parent → revision + 1 |
| T-DB-14 | owner, coach | update/delete on point_event_revisions, sync_maps, calibration_versions, source_manifests, story_plan_versions | denied |
| T-DB-15 | owner | new event revision | older `preview`/`film`/`clip_excerpt` artifacts and plan versions become `stale` |
| T-DB-16 | camera (signed in) | select camera_sources | only its own source; 0 rows of projects, manifests, other sources, artifacts |
| T-DB-17 | owner | select `camera_invites.code_hash`, `camera_sources.r2_key`, `artifacts.r2_key`, `artifacts.bucket_class`, `render_attempts.lease_token_hash`, `access_grants.token_hash`, `quotes.cap_cost_micro_usd` | permission denied each |
| T-DB-18 | viewer with `film_view` | select artifacts | the film + its thumbnail/captions/chapters; not its preview, edit manifest, other films |
| T-DB-19 | viewer | same after revoke; after `expires_at` | 0 rows (no token refresh needed) |
| T-DB-20 | viewer with `lesson_clip_view` | select lesson_clips, artifacts, lessons, projects | that clip and its excerpt only; lesson, project, match film: 0 rows |
| T-DB-21 | viewer with `lesson_view` | select observations, projects | 0 rows |
| T-DB-22 | coach with `lesson_coach` (not a project member) | insert observation with `lesson_id` only | allowed; with a `project_id` they do not coach → denied |
| T-DB-23 | owner, coach | insert observation with provenance `estimated` or `validated`; update provenance | denied; review of `estimated` → provenance `reviewed`, `reviewed_by = auth.uid()` |
| T-DB-24 | owner, coach | insert story_plan_versions with `planner_kind = 'llm'` or set `validation_state` | denied |
| T-DB-25 | coach | select quotes, usage_reservations | 0 rows |
| T-DB-26 | owner | insert/update quotes, usage_reservations, render_jobs, render_attempts, artifacts, access_grants, deletion_requests | denied (cannot create an unbounded reservation, a job, a grant or a ready artifact) |
| T-DB-27 | grantee | select access_grants | own grant rows; unrelated user: 0 |
| T-DB-28 | anonymous-authenticated | any select/insert on Studio tables, including provider_connections | 0 rows / RLS violation |
| T-DB-29 | user | provider_connections of another user | 0 rows; `hasnt_column` for any token/secret column |
| T-DB-30 | user | update another profile; select `is_tester` | 0 rows; denied |
| T-DB-31 | owner, coach | any child table of a project with `deleted_at` set | 0 rows |
| T-DB-32 | coach | after membership `revoked_at` or `expires_at` | 0 rows immediately |
| T-DB-33 | jovra_gateway | each owner-only command with `p_actor` = unrelated user | `P0404` for every command; audit row via `audit_denial` |
| T-DB-34 | jovra_gateway | `accept_quote` twice with one key; with expired quote; with changed inputs hash | one job and reservation; `P0410`; `P0409` |
| T-DB-35 | — | PostgREST config exposes only `public, graphql_public` | pass |
| T-DB-36 | jovra_gateway | `reserve_stage` beyond cap; same `(job, stage, attempt)` twice | `P0402`; one attempt row |
| T-DB-37 | jovra_gateway | `finish_attempt` with stale token; after `lease_expired` | rejected; no artifact registered |
| T-DB-38 | jovra_gateway | `complete_upload_check` with a missing part, wrong last-part size, session bound to another project's source | refused each |
| T-DB-39 | jovra_gateway | `redeem_camera_invite` after `redeem_by`, twice, after revoke; `issue_guest_capability` before approval or with another device key | refused each |
| T-DB-40 | user B | similarity search over lesson_embeddings while holding A's `lesson_clip_view` grant | 0 of A's rows |
| T-DB-41 | owner | insert lesson_clip referencing a project they neither own nor coach | denied |
| T-DB-42 | owner | story_plans with a `lesson_ids` entry they cannot access | trigger error |
| T-DB-43 | owner | insert sync_map with `review_state = 'reviewed'` and `reviewed_by` = someone else | `reviewed_by` forced to caller |
| T-DB-44 | — | `supabase db advisors --local --type security --fail-on warn` | zero findings (OBSERVED flags) |
| T-DB-45 | owner, coach | insert lesson_clip, observation or calibration whose `source_id` belongs to another project they can see | FK violation (composite FK) |
| T-DB-46 | coach | attach a clip of the owner's match to their lesson and grant `lesson_clip_view`; then the owner revokes the coach | grant creation refused until `share_approved_at`; after approval the viewer sees the clip; after the coach's revocation the viewer gets 0 rows and the gateway 404 |
| T-DB-47 | jovra_gateway | run every secret-minting command, then scan `app_ops.*` | no `jv[igslhc]_` value anywhere |
| T-DB-48 | owner | `delete from lessons`, `delete from lesson_clips` | permission denied; deletion request scope `lesson` removes excerpt objects, clips, lesson-only observations and embeddings |
| T-DB-49 | project coach | select observations and lesson_embeddings rows that also carry a lesson the coach cannot access | 0 rows |
| T-DB-50 | viewer (film_view, clip grant) | select after the owner starts project deletion (`deleted_at` set) | 0 rows |
| T-DB-51 | coach | redeem a `project_coach` code | membership pending, `has_project_role` false until `approve_member`; `revoke_grant` afterwards → membership revoked in the same transaction |
| T-DB-52 | user with `lesson_view` | insert a story_plan whose `lesson_ids` contains that lesson | trigger error |
| T-DB-53 | jovra_gateway | call `set_job_state`, `reserve_stage`, `finish_attempt`, `mark_artifact_verified` | permission denied (orchestrator role only); as `jovra_orchestrator`, `set_job_state(verifying → ready)` without a verified artifact → `P0409` |
| T-DB-54 | owner | insert a row violating a length limit | coded `P0422 field_too_long:<column>`; the error has no `Failing row contains` DETAIL |
| T-DB-55 | jovra_orchestrator | `reserve_stage` | estimate computed in SQL (a zero estimate is impossible); `input_refs` contain only the job project's verified sources and artifacts |
| T-DB-56 | jovra_gateway | `accept_quote` for identical work under a second quote while a reservation is held; beyond the owner open-cap or environment ceiling | `P0409` (or a top-up when the quote supersedes); `P0402` |
| T-DB-57 | jovra_gateway | `authorize_upload('render_host', …)`; any `*_for_attempt` function | `P0422` (actor kind not accepted); permission denied |
| T-DB-58 | stranger (confirmed email ≠ invitee) | redeem a forwarded `project_coach`, `lesson_coach`, `lesson_view`, `film_view` or `lesson_clip_view` code; invitee with an unconfirmed email | `P0404` each (identical to an unknown code); the intended invitee succeeds; the owner's approval view shows the masked verified email, never `display_name` |
| T-DB-59 | owner of A (former coach of B) | `create_quote` or `review_job` naming B's story plan or plan version; insert `render_jobs`/`quotes` rows (as `jovra_owner` in the test) pairing A with B's plan | `P0404`; FK violation for each composite FK |
| T-DB-60 | jovra_gateway | two `accept_quote` for identical plan-by-job work (`story_plan_version_id` null); an in-job revise followed by a quote for the new version and the same output | one held reservation and one non-terminal job (`P0409` for the second); the revise moved the reservation key, so the new quote is refused or tops up |
| T-DB-61 | jovra_gateway | `accept_quote` with no `app_ops.spend_limits` rows; with a NULL limit (inserted by disabling the NOT NULL check in the test) | `P0402` (fail closed) |
| T-DB-62 | coach (lesson owner) | after the project owner approves a clip, update its `match_start_us`; viewer selects it | `share_approved_at` null, excerpt unlinked; viewer 0 rows and gateway 404 until re-approved and re-rendered; `revoke_clip_share` by the project owner has the same effect |
| T-DB-63 | pending coach (redeemed, not approved) | select `profiles`, `project_members` | only self; 0 member rows |
| T-DB-64 | owner | insert `point_event_revisions`, `story_plan_versions`, `sync_maps`, `lessons` past each quota | `P0429` at the boundary, allowed one below it |
| T-DB-65 | unrelated user | insert into `point_event_revisions` (and every table with a BEFORE trigger) naming a victim project, with every `parent_revision` value | identical `42501` "new row violates row-level security policy"; the victim's `current_event_revision` and advisory lock untouched |
| T-DB-66 | — | owner of every `public` Studio table, `app_private` helper and `app_gateway` function; `relforcerowsecurity` on tables helpers read | all `jovra_owner` (`proowner = relowner`); false |

### 6.3 R2 operations matrix (enforced by the gateway; R2 has no notion of users)

| # | Operation | Demo | Unauth | Unrelated | Owner | Coach | Viewer | Share-link holder | Camera guest | Camera (signed in) | Render attempt | System (cron/deletion) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| R-01 | Create multipart upload for a source | — | — | — | own sources | — | — | — | its slot only | its slot only | — | — |
| R-02 | Upload part | — | — | — | own open session | — | — | — | own session | own session | own output session | — |
| R-03 | Complete / abort upload | — | — | — | own session | — | — | — | own session | own session | own output session | abort expired |
| R-04 | Read original (`staging/`) | — | — | — | — (has it locally) | — | — | — | — (including its own) | — | listed inputs, lease valid | verify/hash only |
| R-05 | Read proxy / frames / PTS table | — | — | — | — | — | — | — | — | — | listed inputs | — |
| R-06 | Write derived object | — | — | — | — | — | — | — | — | — | listed outputs, new keys only | — |
| R-07 | Read preview | — | — | — | yes | yes | — | if the link targets it | — | — | — | — |
| R-08 | Read film / clip excerpt + thumbnail/captions/chapters | — | — | — | yes | yes | granted only | the one linked artifact (`/s/<token>`) and its thumbnail (`/s/<token>/thumbnail`) only | — | — | verify stage | — |
| R-09 | Read edit manifest | — | — | — | yes | yes | — | — | — | — | — | — |
| R-09b | Read project bundle (films + EDL, chapters, captions, edit manifest; never originals or proxies) | — | — | — | yes | — | — | — | — | — | — | — |
| R-10 | Delete object | — | — | — | via deletion request only | — | — | — | — | — | — | deletion job, cleanup |
| R-11 | List objects | — | — | — | — | — | — | — | — | — | — | cleanup sweep only |
| R-12 | Issue presigned URL (after spike) | — | — | — | GET ≤ 5 min for R-07/08 | GET ≤ 5 min | GET ≤ 5 min | — (always proxied) | — | — | — | — |

No route accepts a bucket name, key, URL or path from a client; keys are derived by the gateway from row ids.

### 6.4 R2 and gateway tests (Miniflare + vitest, simulated R2)

| ID | Expected |
|---|---|
| T-R2-01 | Camera guest PUTs a part to another slot's session id → 404; to its own → 200 |
| T-R2-02 | Camera guest GETs any artifact, including its own completed source → 404 |
| T-R2-03 | Owner requests an original or proxy through any client route → 404 (no route exists; probe all routes with source/artifact ids) |
| T-R2-04 | Coach streams film and preview → 200/206; requests a source → 404 |
| T-R2-05 | Viewer streams a granted film → 206 with Range; any other film, the preview, the edit manifest → 404 |
| T-R2-06 | Share link streams its film and thumbnail; a different artifact id under the same token → 404; after revoke/expiry → 404 |
| T-R2-07 | Share link creation for a source, proxy, project bundle or another owner's film → 404/422 |
| T-R2-08 | Render attempt reads a listed input → 200; an unlisted key → 404; after lease expiry → 403; writes to an unlisted output ref → 404 |
| T-R2-08b | A forged queue message naming another project's source as an input (attempt of project A) → the input is never served (404): inputs come only from `render_attempts.input_refs` |
| T-R2-09 | Render attempt attempts delete or list → no such route (404) |
| T-R2-10 | Request bodies or query strings containing `key`, `bucket`, `url` or `path` are ignored or rejected (400); derived keys never contain user text |
| T-R2-11 | Unauthenticated calls on every media route → 401/404; demo marker → 401 `demo_not_accepted` |
| T-R2-12 | Deletion request removes every object under the project's prefixes in both simulated buckets; staged sources of other projects untouched; lesson scope removes the lesson's clip excerpts and thumbnails; the reconciler deletes objects with no row in every prefix |
| T-R2-13 | Presigned GET (when enabled) has `X-Amz-Expires ≤ 300`, method GET, one key, and signed `response-cache-control=private, no-store`, `response-content-disposition` (server filename) and `response-content-type` overrides (deterministic SigV4 test with a fixed clock) |
| T-R2-14 | Responses carry `Cache-Control: private, no-store`; `Content-Disposition` filename is server-generated; every media response (including `/s/` and `/content`) carries `X-Content-Type-Options: nosniff` and `Content-Security-Policy: sandbox`; `/s/` responses carry `Referrer-Policy: no-referrer` |
| T-R2-15 | After verification, replace the original's bytes through a second (or stale) session → completion refused; a direct object swap → every later read fails `etagMatches` |
| T-R2-16 | Deletion: source scope removes the films, previews and excerpts whose `artifact_sources` include it and their share links (after the owner's explicit choice); lesson scope removes plan versions and films derived from the lesson; a coach's account deletion removes their lessons' excerpts under the other owner's prefix; open multipart sessions are aborted and later parts refused; a film's thumbnail, captions and chapters go with it |
| T-R2-17 | Reconciler race: complete an upload in R2, run the sweep before `mark_uploaded_unverified`, then mark → object still present; an artifact in `writing` is never swept; only objects older than 48 h with no row and no live session are deleted |

## 7. R2 layout

- Buckets per environment and retention class: `jovra-<env>-work` and `jovra-<env>-films`. Public access and
  `r2.dev` off (`r2.dev` is "not intended for production", OBSERVED https://developers.cloudflare.com/r2/platform/limits/).
- Keys are opaque and server-generated from UUIDs only, so a key never carries a name, email or file name:
  `staging/p/<projectId>/s/<sourceId>/original/<sessionId>`, `proxies/p/<projectId>/s/<sourceId>/<normVersion>/<attempt>.mp4`,
  `frames/p/<projectId>/j/<jobId>/<attempt>/…`, `previews/p/<projectId>/j/<jobId>/<attempt>.mp4`,
  `films/p/<projectId>/a/<artifactId>.mp4`. UUIDs are not secrets; authorization never relies on key secrecy.
- The gateway's R2 binding is the only credential in the default design. Direct-to-R2 (presigned or temporary
  credentials scoped to the exact key and multipart actions, OBSERVED
  https://developers.cloudflare.com/r2/api/s3/temporary-credentials/) is adopted only after the spike, and its
  parent token is a Worker secret that can be rotated to revoke all derived credentials at once.
- Media metadata: iPhone files carry QuickTime metadata that can include location (INFERRED from common iOS
  behaviour; UNVERIFIED per device setting). Originals are stored unchanged (they are the user's), but every derived
  proxy, frame, preview and film is written with metadata stripped (`-map_metadata -1` and explicit allowlisted tags),
  and probe tags are never logged.

## 8. Capabilities

### 8.1 Format

Opaque random tokens: 32 bytes from a CSPRNG, base64url, with a type prefix for secret scanning and log redaction:
`jvi_` camera invite code, `jvg_` guest capability, `jvs_` upload session, `jvl_` attempt lease, `jvh_` share link,
`jvc_` coach/viewer invitation. Only `SHA-256(token)` is stored; lookup is by hash. This holds for every store: the
idempotency store keeps redacted bodies for routes that mint these tokens (a replay is `409 secret_not_replayable`),
and lease tokens are minted at claim time, never written to an outbox, Queue or DLQ. Opaque tokens are preferred to
self-contained signed tokens because every use needs a fresh row check for revocation anyway (INFERRED).

### 8.2 Camera guests

1. The host creates an invite; the 32-byte code goes into the QR (custom scheme, not a web URL, multicam-sync §2.4)
   and is shown once.
2. The guest generates a P-256 key pair in the Secure Enclave / Android Keystore and redeems the code with its
   public key and a device label. The redemption only reaches `awaiting_host`.
3. Both phones show a 6-digit code derived from the guest key's thumbprint; the host compares them and taps
   Approve (the approval request carries the code). The guest-supplied device label is shown but is never the basis
   for approval, since a stranger can name a device "Jon's iPhone". Until approval no capability exists and the guest
   sees no project text. A photographed QR that a stranger redeems first fails the code comparison and can be
   revoked (single use, 10 minutes).
4. The guest proves key possession (signature over a server nonce) to receive `jvg_`; session opening and source
   declaration require a fresh signature over `(method, path, timestamp, nonce, body SHA-256)`, ±5 minutes skew, with
   a nonce replay cache (Durable Object, 10 minutes) as for the render host; parts then use the `jvs_` session token.
5. Scope: declare one source for its slot, upload it. No read, list or download route accepts `jvg_` or `jvs_`.

### 8.3 Share links

`jvh_` tokens, ≤ 24 h, one artifact, created by the owner, checked per request (revocation immediate). The link
carries no user data; opening it creates no account and sets no cookie.

### 8.4 Render host

- Host credential: for Cloudflare Containers, the consumer Worker reaches the container through its binding and the
  container calls back through a service binding (no public ingress; INFERRED from the Containers model). For an
  external host, HMAC-SHA256 request signing over `(method, path, timestamp, nonce, body SHA-256)` with a per-
  environment secret, ±5 minutes skew, nonce replay cache (Durable Object or KV, 10 minutes).
- Attempt lease token `jvl_`: minted by `claim_attempt` when the host claims an attempt id (the queue message carries
  only `{attemptId}`), returned once in the claim response, stored only as a hash; a second claim is fenced. 5-minute
  lease extended by heartbeats. Every internal route requires both the host credential and the current lease;
  `finish_attempt` fences stale tokens. Inputs and outputs are authorized only against the lists `reserve_stage` stored
  on the attempt row, never against message fields.
- The host has no database credential, no model key, no R2 credential in the default design (it reads and writes
  through the gateway's internal routes), and an egress allowlist of the gateway origin only.

### 8.5 Revocation semantics (what the UI may promise)

| Change | Effect | UI copy |
|---|---|---|
| Revoke coach membership or a grant | Next database query and next gateway request (Hyperdrive caching disabled); revoking a `project_coach` grant also revokes the membership it created; revoking a coach also ends viewers' access to the coach's clips of that project | "Access removed" |
| Revoke a camera invite | Next part upload | "This camera can no longer upload" |
| Revoke a share link | Next request through the gateway | "Link turned off" |
| Optional presigned GET already issued | Valid until expiry (≤ 5 min), not revocable (OBSERVED) | "Downloads already started may finish" |
| Optional Realtime lobby | Policies cached per connection until reconnect or JWT expiry (OBSERVED, https://supabase.com/docs/guides/realtime/authorization) | "Access ends within an hour" |

## 9. Logging and PII hygiene

**Never logged by JOVRA code** (gateway, Workflow, consumers, render host, Postgres errors raised by our functions): `Authorization` headers; any
`jv*_` token or invite code; JWTs or JWT payloads; presigned URLs; emails; display names; device labels; lesson notes,
observation bodies, story text, titles; model prompts and responses; frames; original file names; QuickTime/EXIF
metadata; raw IP addresses; Apple tokens; provider tokens.

**Logged** (structured JSON, allowlisted fields only): `requestId`, route template (`/s/:token`, never the token),
method, status, latency, `actorKind`, actor UUID, project UUID, job/attempt UUIDs, error code, SHA-256 of the
idempotency key, byte counts, stage measurements. Rate limiting uses an HMAC of the IP with a key rotated daily.

Mechanisms (INFERRED):
- One logger module with a field allowlist; unknown fields are dropped, not redacted. Headers are never passed to it.
- A redaction regex for the `jv[igslhc]_` prefixes and `eyJ` (JWT) runs on every log line as defence in depth; test
  T-GW-19 fails the suite if any captured line matches or contains a seeded email/display name.
- Postgres functions raise coded errors without values; no `log_statement = all`; command parameters never include
  user text that would appear in error contexts.
- Render-host FFmpeg stderr is parsed for progress and error codes, then discarded; probe output is reduced to the
  allowlisted fields before storage.
- Audit `detail` stores hashes, counts and revision numbers only.
- Planner calls: prompts and responses are not logged; the validated plan is stored in `story_plan_versions` under
  RLS. Provider-side data retention for API inputs must be reviewed at activation (UNVERIFIED; gate G6/G7).
- Diagnostics from the app leave the phone only when the user taps to send (ADR-0013).
- Logs outside the Workers (§13.13): zone-level HTTP-request Logpush and WAF/Security Events record request URIs, so
  G2 evidence shows they are off for the gateway hostname or exclude/redact `/s/*`; Supabase API-gateway logs record
  PostgREST paths and query strings, so no user text ever goes in a query string (lesson search is a `POST /rpc/…`
  body), and T-GW-19 also scans the app's PostgREST request builder.
- Platform logs are separate from the app logger and are configured, not assumed: the Worker sets
  `[observability.logs] invocation_logs = false` because invocation logs contain "the Request, Response, and related
  metadata" (OBSERVED, https://developers.cloudflare.com/workers/observability/logs/workers-logs/), which would hold
  `/s/<token>` paths, client IPs and headers; `/s/` responses send `Referrer-Policy: no-referrer`.
- Postgres constraint violations add a `Failing row contains (…)` DETAIL with every column value (INFERRED from
  standard Postgres behaviour), which reaches Supabase Postgres logs and PostgREST clients. A `validate_lengths`
  BEFORE trigger and the command functions raise coded errors before any CHECK/NOT NULL constraint can fire
  (T-DB-54).
- Retention: Workers Logs keeps 7 days on paid plans, 3 on free (OBSERVED, same page); Supabase log retention and
  Workflows instance-state retention are **UNVERIFIED** and recorded at gate G2. Nothing requires longer.

## 10. Threat model (STRIDE)

| ID | Threat | Mitigation | Test |
|---|---|---|---|
| S1 | Forged or demo JWT accepted | ES256 only, JWKS per env, `iss`/`aud`/`exp` pinned; no demo token exists | T-GW-01..04 |
| S2 | Test-environment token used against live | Issuer pinning; separate projects | T-GW-02 |
| S3 | Stranger redeems a photographed camera QR (and names the device like the host's) | 10-min single use, host approval only after comparing the thumbprint code on both phones, no project text before approval, device-bound capability, nonce replay cache, revoke | T-DB-39, T-GW-23 |
| S7 | An invitation code (coach, lesson, film or clip) is forwarded and redeemed by a stranger | Every invitation is bound to the invitee's email (HMAC) and redeemable only by an account with that confirmed email; a coach redemption is still pending until the owner approves after seeing the verified, masked email (a display name is attacker-chosen and never the basis); revoking the grant revokes the membership | T-DB-51, T-DB-58 |
| S4 | Render host impersonated to post results | Host credential (binding or HMAC + nonce) + lease token fencing | T-GW-13, T-DB-37 |
| S5 | Apple ID token replay | Nonce: hashed to Apple, raw to Supabase; `skip_nonce_check = false` | unit test + device check (G4) |
| S6 | Share link forwarded beyond intent | ≤ 24 h, one artifact, revocable per request; copy explains anyone with the link can watch | T-R2-06 |
| T1 | Client sets `owner_id`, role, price, cap, provenance, key or job state | Column grants, policies, server-computed quotes, server-generated keys, command functions | T-DB-07/08/10/23/26, T-R2-10 |
| T2 | Uploaded bytes differ from the declared original | Per-part length + SHA-256, completion checks, server full-file SHA-256 before `verified` | T-GW-08/09, render tests |
| T3 | Malicious media exploits a parser | Probe allowlist before decode, pinned FFmpeg, container isolation, ulimits/timeouts, no outbound network, per-stage disk caps | render tests (malformed fixtures) |
| T4 | Model output smuggles commands, filters, URLs or invented metrics | StoryPlan holds IDs and enums only; validator; deterministic compiler; fixed FFmpeg templates; heuristic fallback | planner adversarial fixtures |
| T5 | Prompt injection through lesson notes or user text | User text passed as quoted data fields, never as instructions; model output can only choose from catalog IDs; validator is the authority | planner adversarial fixtures |
| T6 | Zombie attempt overwrites good outputs | New keys per attempt, `writing` until verified, lease fencing | T-GW-13 |
| T8 | Queue message forged or replayed to read another project's media or write unplanned outputs | Messages carry ids only; inputs and outputs authorized against `render_attempts.input_refs`/`output_plan` computed in SQL; lease minted at claim, second claim fenced | T-R2-08b, T-GW-28 |
| T9 | Verified source swapped after verification (TOCTOU) | One open session per source, per-session keys, completion bound to `current_session_id`, reads pinned to `verified_etag` | T-R2-15, T-GW-25 |
| T10 | Confused deputy: a row of project A names project B's source, so a server stage copies B's footage into A | Composite `(project_id, source_id)` FKs; quotes, jobs and EDLs resolve sources only through the job project's verified manifest | T-DB-45, T-GW-24 |
| T7 | Event history rewritten to change scores silently | Append-only revisions with parent check; scores derived from the bound revision; stale marking | T-DB-13/14/15 |
| R1 | User disputes consent or a charge | Quote inputs hash, consent JSON with text version, reservation and receipts, audit events | T-DB-34 |
| R2 | Disputed deletion | `deletion_requests` states with counts; audit tombstones | T-GW-20 |
| I1 | Cross-tenant metadata through an RLS gap | Deny by default, restrictive real-user policy, helpers tested under each role, advisors in CI | T-DB-01..44 |
| I2 | Cross-tenant media by guessing keys or ids | No client-supplied keys; per-request authorization; identical 404 for "missing" and "not yours" | T-R2-01..11 |
| I3 | A lesson-clip share exposes the whole match | Clip grants reach only the `clip_excerpt` artifact and the clip row | T-DB-20, T-R2-05 |
| I3b | A coach redistributes the owner's footage through their own lesson | Clips of another owner's project are shareable only after the project owner approves; the approval pins the window and keeper (moving them clears it); the project owner can withdraw it or revoke any grant reaching their footage; access ends when the coach's role ends | T-DB-46, T-DB-62 |
| I3d | A plan or plan version of project B is named in a job, quote or review of project A (confused deputy) | Composite FKs bind plans and versions to their project and versions to their plan; `create_quote` and `review_job` assert them | T-DB-59 |
| I11 | Existence or revision oracle through a BEFORE trigger that runs before RLS | Every BEFORE trigger on a client-written table first checks the caller's role on `new.project_id` and raises the same `42501` as RLS | T-DB-65 |
| I12 | A pending coach reads members' display names | `shares_project_with` applies the approval predicate on both sides | T-DB-63 |
| I3c | A viewer grant launders lesson notes into a plan the attacker can read | `check_story_plan_lessons` (owner/coach access and same owner); planner evidence gathered under the same actor check | T-DB-52 |
| I4 | Tokens or PII in logs | Allowlisted logger, redaction, log-scrub test; invocation logs off; coded errors before constraints; no secrets in the idempotency store | T-GW-19, T-GW-22, T-DB-47, T-DB-54 |
| I10 | Cached authorization result after revocation | Hyperdrive query caching disabled; authorization functions `volatile` | T-GW-21 |
| I5 | Thumbnails, proxies, frames or vectors leak | Same authorization path as films; proxies/frames never client-readable; embeddings under RLS, no viewer access | T-R2-03, T-DB-40 |
| I6 | Presigned URL leaks and cannot be revoked | Default is gateway streaming; presigned only after spike, GET only, ≤ 5 min | T-R2-13 |
| I7 | Existence oracle through ids or error messages | Server-generated ids, identical `not_found` responses, no project titles in guest views | T-GW-06, T-R2-01 |
| I8 | Frames sent to a model provider without consent | `consent.modelProvider` required per job; heuristic otherwise; frames stripped of metadata | gateway test on accept |
| I9 | Location metadata in derived media | Metadata stripped from every derived object | render test (fixture with location tag) |
| D1 | Upload floods exhaust storage or Worker requests | Declared size cap per source, ≤ 6 sources per project, session expiry, abort rule, rate limits; render outputs capped per output kind | T-GW-08, T-GW-36 |
| D7 | Direct PostgREST inserts (event revisions, plan versions, sync maps, lessons…) exhaust database storage and backups | Per-project and per-user quotas in BEFORE INSERT definer triggers (`P0429`) | T-DB-64 |
| D8 | Spend limits missing or NULL make the ceiling comparison NULL (never refuses) | Fail closed: no row or a NULL limit is `P0402`; a default owner row; NOT NULL limits | T-DB-61 |
| D9 | Two identical plan-by-job quotes (NULL plan version) each open a hold; an in-job revise leaves the hold on the old version | `NULLS NOT DISTINCT` unique indexes; revise moves the reservation key in the same transaction | T-DB-60 |
| D10 | A leaked share link is hammered with Range requests for 24 h | Per-token-hash rate limit and byte budget on `/s/` | T-GW-34 |
| D2 | Job spam, re-quotes or retry storms burn spend | Quote + consent + reservation cap; one held reservation per (project, plan version, output spec); per-owner open-cap and environment daily ceiling (also in test); stage estimates computed in SQL with a floor; retries reserve first; no automatic escalation | T-GW-10/12, T-DB-36, T-DB-55, T-DB-56 |
| D3 | Poison queue message loops | Idempotent consumers, bounded retries, mandatory DLQ, alert | T-GW-18 |
| D4 | OTP email bombing | Supabase 60 s window, allow-list in test, custom SMTP rate limits | local Mailpit test |
| D5 | Decompression-bomb-like media (huge dimensions, frame counts, durations) | Probe allowlist before decode; dimension/duration caps; per-stage timeouts | render tests |
| D6 | Realtime lobby limits exhausted | Lobby optional; local transport primary; presence on change only | (S3, later) |
| E1 | Definer function callable over the Data API | No definer functions in exposed schemas; `app_*` not exposed | T-DB-03, T-DB-35 |
| E2 | Secret key or model key shipped in an app | Keys only as Worker/host secrets; build-time scan for `sb_secret_`, `sk-ant-`, `jv*_` patterns | CI secret scan |
| E3 | `search_path` hijack in definer functions | `search_path = ''`, fully qualified names; lint | T-DB-03 |
| E4 | Camera guest escalates to project read | Guest has no DB identity; `jvg_`/`jvs_` accepted only on upload routes | T-R2-02 |
| E5 | Coach approves spend or creates public links | Quote, accept, share-link and grant routes are owner-only; clip grants of another owner's footage need that owner's approval | T-DB-25/26/46, T-R2-07 |
| E8 | A bug or compromised dependency in a user route moves a job or marks an artifact verified | Orchestration functions executable only by `jovra_orchestrator`, whose Hyperdrive binding and host secret exist only in the separate `jovra-internal` Worker; the user gateway reaches it through a service binding with no orchestration methods; render-output uploads use `*_for_attempt` variants; SQL transition table; `ready` needs a verified artifact | T-DB-53, T-DB-57, T-GW-29 |
| E9 | Anyone holding the test publishable key signs up and spends real model and container money in test | Sign-ups disabled on the test Auth project; mandatory allow-list hook; `accept_quote` in test requires the tester flag | T-GW-30 |
| E10 | A stolen refresh token or an unlocked phone deletes the account | Deletion checks the authentication time (or a bound re-authentication), never a refreshed `iat` | T-GW-31 |
| E6 | Render service raises a budget or publishes | No such command accepts a lease token; reservation cap enforced in SQL | T-DB-36 |
| E7 | Anonymous Supabase user writes Studio rows | Restrictive policy; anonymous sign-in off in live | T-DB-28 |

## 11. Security gates for every backend change (local, required)

1. `supabase db reset && supabase test db` passes (all T-DB tests).
2. `supabase db advisors --local --type security --fail-on warn` reports nothing.
3. Repo lint: no `security definer` in `public`; every function in `app_*` and `public` sets `search_path = ''`; no
   `search_path = public` anywhere; every `public` table has RLS and the restrictive real-user policy; every new
   table appears in the §6 matrix and has at least one allow and one deny test.
4. Gateway `vitest` suite with `@cloudflare/vitest-plugin` passes (T-GW and T-R2 lists), including the log-scrub test.
5. Secret scan over the repo and built app bundles for `sb_secret_`, `service_role`, `sk-ant-`, `-----BEGIN`,
   `jv[igslhc]_` patterns; `.dev.vars` and `.env*` ignored.
6. Render-host tests with synthetic and malformed media pass.
7. A PR that changes a policy, grant, command function, capability or log field states which tests changed and
   includes their output. Green CI does not replace hosted verification at activation (CLAUDE.md rule 9).

## 12. Privacy and consent notes

- Cloud use changes App Privacy answers (ADR-0013 targets "Data Not Collected" for the free app). Studio cloud
  features stay behind sign-in and explicit per-project, per-job consent; the privacy label and consent copy are
  activation gate G7.
- People in footage: guests acknowledge they record with the players' agreement (`participant_ack_at`); share links
  and coach access are explicit owner actions; nothing is public.
- Minors: tennis footage often shows juniors. Age requirements for cloud accounts and for footage of minors are not
  decided here (open question Q11 for Jon; legal review **UNVERIFIED**).
- Model providers receive only consented, metadata-stripped frames and IDs; never names or emails, and note text
  only in the classes named in the quote's consent (`consent.textClasses`, e.g. `["ownerNotes"]`). Coach-authored
  text (observation bodies, coach notes) is another person's data and is excluded by default; the planner evidence
  builder filters by the stored classes (§13.14, ADR-0016).
- Public contact in any email template or copy is the role address under IDC Rule 07 (`hello@islanddevcrew.com` as
  text), never a personal address.

## 13. Review round 2 hardening (2026-10-07)

Each item below answers a verified review finding; the table and endpoint changes are in `architecture.md` (§4.3,
§5, §7, §10, ticket B-25). Labels as above.

### 13.1 Two Worker scripts (E8)

- **`jovra-gateway`** serves user and guest routes and `/s/`. It holds only the `jovra_gateway` Hyperdrive binding, the
  R2 bindings and a service binding to `jovra-internal`. It has no orchestrator binding, no render-host secret and no
  Workflow binding that can do more than `create` (job start goes through `jovra-internal.startJob(jobId)`).
- **`jovra-internal`** holds the `jovra_orchestrator` Hyperdrive binding, the host HMAC secret (or the Container
  binding), the Workflow class, the Queue consumer, the reconciler cron and the `/internal/v1/attempts/…` routes. Its
  service-binding entrypoint exposes exactly `startJob(jobId)` and `notifyReview(jobId)`, both of which re-read the job
  row and act only on its stored state; it never exposes `set_job_state`, `mark_artifact_verified` or any upload
  method. Its routes are not on the user hostname (INFERRED: a Worker without a route is reachable only by bindings).
- Render-output uploads and verify-stage reads use the `*_for_attempt` command variants (§4.1), fenced by the lease.
- Tests: T-DB-57; **T-GW-29** parses both Wrangler configs and asserts the user gateway has no orchestrator Hyperdrive
  binding, no host secret and no route under `/internal/`, and that the service binding's RPC surface is the two
  methods above.

### 13.2 Invitations bound to their recipient (S7)

- `create_grant` takes the invitee's email from the owner (`inviteeEmail`), stores only
  `invitee_email_hmac = HMAC-SHA256(server key, lower(trim(email)))` and never logs or returns it. Every invitation kind
  needs it (`project_coach`, `lesson_coach`, `lesson_view`, `film_view`, `lesson_clip_view`); `share_link` has no
  invitee (it is a 24 h bearer link by design, §8.3).
- `redeem_grant` (definer) compares the HMAC of the redeemer's `auth.users.email` and requires `email_confirmed_at is
  not null`; a mismatch is `P0404`, identical to an unknown code (INFERRED that these `auth.users` columns are readable
  by the definer owner; checked at G1). A SIWA user with a hidden private-relay email redeems after signing in with
  the invited address by email code (UNVERIFIED identity-linking behaviour; Q12).
- `approve_member` shows the owner the redeemer's verified email, masked (`j•••@e•••.com`), plus the code both phones
  show; never `display_name`, which the redeemer controls.
- Tests: T-DB-58, T-DB-51 (still pending until approval).

### 13.3 Test sign-up enforced on the server (E9)

- Test Auth project: sign-ups disabled (`[auth] enable_signup = false` in `supabase/config.toml` locally; the hosted
  "Allow new users to sign up" setting off at G1); testers are created by the operator script with the admin API
  (UNVERIFIED that admin creation still works with sign-ups off; G1 evidence).
- The `before_user_created` hook (named in `docs/research/studio/backend-architecture.md` §3.3 from the local Supabase
  config; availability on the chosen hosted plan UNVERIFIED, G1)
  is mandatory in test and rejects any email whose HMAC is not in the allow-list table.
- `accept_quote` in test also requires `profiles.is_tester = true` (set only by the operator script); that is the only
  reader of `is_tester`, and no RLS policy uses it.
- **G1 evidence (T-GW-30):** `POST /auth/v1/otp` with `create_user: true` for an unknown email against the hosted test
  project is refused and no `auth.users` row appears.

### 13.4 Re-authentication for deletion (E10)

§2.2 step 5. `POST /v1/deletion-requests` with scope `account` returns `401 reauth_required` unless the authentication
time is within 10 minutes (T-GW-31: a token refreshed 2 minutes ago whose authentication is 2 hours old is refused).

### 13.5 Plans bound to their project (I3d)

`story_plans` gets `U (project_id, id)`; `story_plan_versions` gets `project_id` (set by trigger from its plan, never
by the client) with `FK (project_id, story_plan_id) → story_plans(project_id, id)` and `U (project_id, id)`,
`U (story_plan_id, id)`; `render_jobs` gets `FK (project_id, story_plan_id) → story_plans(project_id, id)` and
`FK (story_plan_id, story_plan_version_id) → story_plan_versions(story_plan_id, id)`; `quotes` and
`usage_reservations` get `FK (project_id, story_plan_version_id) → story_plan_versions(project_id, id)`.
`create_quote` asserts the plan and version belong to `p_project`; `review_job` asserts
`version.story_plan_id = job.story_plan_id`. Test T-DB-59.

### 13.6 One hold, also without a plan version (D9)

The held-reservation and non-terminal-job unique indexes are `NULLS NOT DISTINCT` (PostgreSQL 15+, OBSERVED
https://www.postgresql.org/docs/current/sql-createindex.html; Supabase runs Postgres 17 per architecture §1). An
in-job revise (architecture §7.1) updates `render_jobs.story_plan_version_id` **and** the reservation's
`story_plan_version_id` and `output_spec_sha256` in one transaction, so a later quote for the new version and the same
output hits the same key. Test T-DB-60.

### 13.7 Spend limits fail closed (D8)

`app_ops.spend_limits` limit columns are `NOT NULL CHECK (> 0)`. A default owner row (`scope = 'owner', owner_id =
null`) applies to every owner without a row of their own; the environment row is required. `accept_quote` and
`reserve_stage` raise `P0402` when the applicable row is missing. "Environment spend today" = the sum of
`reserved_cost_micro_usd` added today (UTC) by reservations created or topped up today, plus the new cap. Test
T-DB-61.

### 13.8 Clip share approval pins what was approved (I3b)

Trigger `pin_shared_clip` (BEFORE UPDATE on `lesson_clips`): when `match_start_us`, `match_end_us` or `keeper_ref`
changes on a clip whose project is not the lesson owner's, it clears `share_approved_at`, sets
`excerpt_artifact_id = null` and marks the old excerpt for deletion; viewers lose access until the project owner
approves again and a new excerpt is rendered. `app_gateway.revoke_clip_share(p_actor, p_clip)` (project owner)
clears the approval. `deletion_scope` gains `lesson_clip`. `revoke_grant` accepts the creator **or** the owner of the
project whose footage a `lesson_clip_view` grant reaches. Test T-DB-62.

### 13.9 Deleting derived media completely (deletion gaps a–f)

- **(a) Source scope.** `lesson_clips` and `observations` use `FK (project_id, source_id) → camera_sources(project_id,
  id) ON DELETE SET NULL (source_id)` (column list, PostgreSQL 15+, OBSERVED
  https://www.postgresql.org/docs/current/sql-createtable.html), so `project_id` survives. A new
  `artifact_sources(artifact_id, project_id, source_id)` table, written by `register_artifact` from the attempt's
  `input_refs`, lists every artifact derived from a source; the source-scope deletion shows the owner the dependent
  films, previews and excerpts ("This angle is in 2 films; deleting it deletes them") and, on confirmation, deletes
  their objects and share links before the rows. A guest angle withdrawn for consent therefore leaves no published
  film.
- **(b) Lesson scope.** The workflow removes the lesson id from every `story_plans.lesson_ids`, marks plan versions
  that used it `invalid` and deletes films rendered from them (objects first), and deletes the Workflow instances of
  those jobs (planner story text lives in step outputs).
- **(c) Account scope.** Objects are enumerated through rows the user's data produced, not only by project prefix:
  the clip excerpts of the user's lessons (`artifacts.lesson_clip_id` → their clips) live under the other owner's
  prefix and are deleted explicitly before the request reports `done`.
- **(d) Uploads.** `canceling_jobs` also aborts every open upload session of the target (R2 `abort` first, then the
  row); `record_part` and `authorize_upload` refuse a project with `deleted_at`.
- **(e) Apple.** `revoking_apple` deletes the Vault-held Apple refresh token after the revoke call (or immediately if
  revoke fails terminally, recording the failure).
- **(f) Children.** Before the row cascade, the workflow enumerates `artifacts` children (`parent_artifact_id`:
  thumbnail, captions, chapters) and deletes their objects, since they are keyed by their own ids, not the parent's.
- Tests T-R2-16, T-GW-32.

### 13.10 Quotas on direct PostgREST writes (D7)

`enforce_quota` (BEFORE INSERT, definer, `app_private`) on every client-insertable table raises `P0429 quota_exceeded`
past INFERRED starting values (tune after measurement): ≤ 50 `point_event_revisions` per project per day; ≤ 200
`story_plan_versions` per project per day; ≤ 20 `sync_maps` and ≤ 20 `calibration_versions` per project per day;
≤ 1,000 `observations` per project per day; ≤ 50 `lessons` and ≤ 500 `lesson_clips` per user per day; and a running
total of stored JSON bytes per project (≤ 256 MB across revision tables). Test T-DB-64.

### 13.11 BEFORE triggers check the role first (I11)

OBSERVED (PostgreSQL CREATE POLICY documentation, https://www.postgresql.org/docs/current/sql-createpolicy.html, as
quoted by the reviewer and not re-fetched here): `WITH CHECK` expressions are enforced after BEFORE triggers fire.
So the first statement of every BEFORE trigger on a client-written table (`check_event_parent`,
`assign_next_revision`, `enforce_quota`, `force_actor_columns`, `validate_lengths`, `check_story_plan_lessons`,
`pin_shared_clip`) is `if not app_private.has_project_role(new.project_id, <the insert policy's roles>) then raise
exception using errcode = '42501', message = 'new row violates row-level security policy'; end if;` (or the lesson
check for lesson tables), before any lock, lookup or update. Test T-DB-65.

### 13.12 The reconciler never deletes fresh media (race)

The daily sweep diffs object keys against `camera_sources`, `artifacts` (every state, including `writing`) **and**
`app_ops.upload_sessions` in any non-terminal state, and deletes only objects whose `uploaded` time is older than
48 h (the longest session lifetime) with no row. Test T-R2-17.

### 13.13 Logs outside the Worker

§9. G2 evidence adds: zone Logpush jobs and WAF/Security Events logging for the gateway hostname are off or exclude
`/s/*` (INFERRED that they record the request URI). Lesson search is `POST /rest/v1/rpc/search_lessons` with the query
in the body.

### 13.14 Consent names the text classes

`quotes.consent` gains `textClasses` (enum array: `ownerNotes`, `ownerLessonNotes`, `coachNotes`), default
`["ownerNotes", "ownerLessonNotes"]`; coach-authored text is included only if `coachNotes` is ticked, and the copy says
whose words they are. The planner evidence builder filters by the stored classes. ADR-0016 amended.

### 13.15 Share links, presigned GETs, money visibility, output size

- `/s/` gets a per-token-hash rate limit (60 requests/min) and a byte budget (3× the artifact size per hour) (INFERRED
  starting values; T-GW-34).
- Every media response sets `X-Content-Type-Options: nosniff` and `Content-Security-Policy: sandbox`; captions are
  served as `text/vtt` (T-R2-14).
- Presigned GETs (only after the spike) sign `response-cache-control`, `response-content-disposition` and
  `response-content-type` overrides (T-R2-13).
- `render_attempts.measurements` is not granted to clients; the owner-only `usage` block of `GET /v1/jobs/{id}`
  carries credits only (T-DB-25, T-GW-26).
- `output_plan` stores a byte cap per output (film: 4 GB; preview: 1 GB; thumbnail: 2 MB; captions/chapters: 1 MB;
  INFERRED); `authorize_output_upload_for_attempt` refuses `declaredBytes` above it (T-GW-36).

### 13.16 Server-written references are project-constrained (defence in depth)

`artifacts` gets `U (project_id, id)` and composite FKs `(project_id, source_id) → camera_sources(project_id, id)` and
`(project_id, parent_artifact_id) → artifacts(project_id, id)`; artifact-targeted `access_grants` carry `project_id`
with `FK (project_id, artifact_id) → artifacts(project_id, id)`; trigger `check_clip_excerpt` requires the excerpt
artifact's `kind = 'clip_excerpt'`, `lesson_clip_id = clip.id` and `project_id = clip.project_id`. One server bug
can then no longer register a cross-project parent or excerpt (T-DB-45 extended).

## Sources

Added in review round 2:
https://www.postgresql.org/docs/current/sql-createpolicy.html (BEFORE triggers run before `WITH CHECK`, as quoted by the
reviewer) · https://www.postgresql.org/docs/current/sql-createindex.html (`NULLS NOT DISTINCT`) ·
https://www.postgresql.org/docs/current/sql-createtable.html (`ON DELETE SET NULL (column)`) ·
https://supabase.com/docs/guides/auth/jwt-fields (`amr`; UNVERIFIED, read at G1).

Carried from `docs/research/studio/backend-architecture.md` (read 2026-10-07); refresh at activation.

- https://supabase.com/docs/guides/database/postgres/row-level-security (deny by default, USING/WITH CHECK, definer
  placement, performance guidance)
- https://supabase.com/docs/guides/database/functions (security definer, `search_path = ''`, revoke execute)
- https://supabase.com/docs/guides/api/api-keys (publishable/secret keys; secret keys bypass RLS; legacy keys deprecated)
- https://supabase.com/docs/guides/auth/jwts · https://supabase.com/docs/guides/auth/signing-keys (JWKS, ES256)
- https://supabase.com/docs/guides/auth/social-login/auth-apple · https://supabase.com/docs/guides/auth/auth-email-passwordless ·
  https://supabase.com/docs/guides/auth/auth-anonymous · https://supabase.com/docs/guides/auth/rate-limits
- https://supabase.com/docs/guides/realtime/authorization (cached channel policies)
- https://supabase.com/docs/guides/ai/rag-with-permissions · https://github.com/pgvector/pgvector
- https://supabase.com/docs/guides/local-development/testing/overview ·
  https://supabase.com/docs/guides/local-development/testing/pgtap-extended ·
  https://supabase.com/docs/guides/database/database-advisors
- https://developers.cloudflare.com/r2/api/s3/presigned-urls/ (GET/HEAD/PUT/DELETE, no revocation) ·
  https://developers.cloudflare.com/r2/api/s3/temporary-credentials/ · https://developers.cloudflare.com/r2/platform/limits/ ·
  https://developers.cloudflare.com/r2/objects/multipart-objects/ · https://developers.cloudflare.com/r2/api/workers/workers-multipart-usage/
- https://developers.cloudflare.com/queues/configuration/dead-letter-queues/ ·
  https://developers.cloudflare.com/workers/configuration/secrets/ ·
  https://developers.cloudflare.com/workers/testing/vitest-integration/ ·
  https://developers.cloudflare.com/containers/platform-details/architecture/
- https://developer.apple.com/support/offering-account-deletion-in-your-app/ ·
  https://developer.apple.com/app-store/review/guidelines/
