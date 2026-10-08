# JOVRA Studio backend architecture (design, not provisioned)

Status: **proposed design, 2026-10-07.** Nothing in this document has been provisioned, deployed, signed up for or
paid for. No Supabase project, Cloudflare account, R2 bucket, Worker, Queue, Workflow, container, model API key or
Apple key exists for JOVRA because of this work. Every "live" behaviour below is **UNVERIFIED** until the activation
gates in section 13 produce evidence.

Companion: [`security-model.md`](security-model.md) holds the Postgres roles, helper functions, every RLS policy in
SQL-like form, the role matrix with explicit allow/deny tests for each table and each R2 operation, capability formats,
logging/PII rules and the STRIDE threat model. This file holds topology, environments, the data model (tables,
columns, foreign keys), the gateway API, the upload/job/delivery/retention flows, the app-side sync model and the local
test strategy.

Labels follow the repo's research convention:

- **OBSERVED**: read in a cited official document or seen on this machine. Vendor facts are carried from
  `docs/research/studio/backend-architecture.md` (which read the cited pages on 2026-10-07) and its siblings; they
  were not re-fetched for this design and must be refreshed at activation.
- **INFERRED**: a design decision or arithmetic reasoned from observed facts.
- **UNVERIFIED**: needs a spike, a measurement or a provisioned account.

## 0. Scope, and what this does not change

- **The core app stays local, free and complete** (ADR-0002, ADR-0013). Recording, replay, scoring, stats, lessons,
  on-device films and every export work with no account, no network and no backend. Nothing here may become a
  dependency of capture (CLAUDE.md hard rule 3).
- **Scope change needs an ADR first.** ADR-0002 says "A JOVRA cloud account/backend: out of scope for v1." The Studio
  expansion prompt asks for a backend-ready v1 with optional, gated cloud activation and requires an ADR recording
  that change (ticket B-00 in section 15). Until that ADR is accepted this document is a proposal.
- **Paid cloud production is later and opt-in.** Quotes, consent, caps and reservations are built and tested in the
  test environment with **Sample** credits and zero money charged; the internal cost cap and an operator-set
  environment ceiling still bound the real model and container spend that test can incur (ADR-0019 amendment). Real charging needs its own ADR restating ADR-0013's
  own-your-footage contract (`docs/research/studio/pricing-and-premium.md` section 6). Nothing here prices anything.
- **Not decided here:** local camera-room transport (see `docs/research/studio/multicam-sync.md`), the edit-plan
  operation set and renderer internals (see `docs/research/studio/film-engine.md`), retail prices.

## 1. Topology

```
 Native apps (iOS SwiftUI first, Android Compose later)                        per environment: TEST | LIVE
 ┌───────────────────────────────────────────────────────────────┐            (separate projects, keys, buckets)
 │ Local store (ADR-0002): session/project JSON + originals =    │
 │ source of truth. Capture, replay, on-device films: no network.│
 │ StudioBackend protocol ─┬─ DemoBackend (in-process, Sample)   │
 │                         └─ RemoteBackend (test | live config) │
 │   • supabase-swift/-kt: Auth, PostgREST (RLS), Realtime (opt.)│──── HTTPS + user JWT ────► Supabase
 │   • Gateway client (base URL from config)                     │                             Auth (SIWA, email OTP)
 └───────────────┬───────────────────────────────────────────────┘                             Postgres 17 + RLS
                 │ HTTPS: user JWT | guest capability                                            (ledger of record)
                 ▼                                                                                Realtime (optional)
 ┌───────────────────────────────────────────────────────────────┐   Hyperdrive (query caching DISABLED), role jovra_gateway
 │ Gateway Worker (Cloudflare) — the only privileged front door  │── EXECUTE app_gateway.* only ──► Postgres
 │  verify JWT (JWKS, ES256, iss pinned per env) | capabilities   │
 │  authorize every media op against Postgres (fresh, per call)  │── R2 binding ──► R2 (private)
 │  upload sessions (multipart, 32 MiB parts through the Worker) │                 jovra-<env>-work  (staging/,
 │  quotes, consent, reservations, job creation + outbox         │                   proxies/, frames/, previews/)
 │  delivery: Range streaming; 24 h share links                  │                 jovra-<env>-films (films, thumbs,
 │  NO orchestrator binding, NO host secret, NO /internal routes │                   captions, manifests)
 └──────┬────────────────────────────────────────────────────────┘                  │ object events
        │ service binding: startJob(jobId), notifyReview(jobId) only                 ▼
        ▼                                                                 Queue r2-events → reconcile rows
 ┌───────────────────────────────────────────────────────────────┐   Hyperdrive #2 (caching DISABLED), role jovra_orchestrator
 │ jovra-internal Worker (separate script, no user route)        │── EXECUTE orchestration + *_for_attempt only ──► Postgres
 │  Workflow class, Queue consumer, reconciler cron,             │
 │  render-host routes /internal/v1/attempts/… (host signature + │
 │  attempt lease token)                                         │
 └──────┬─────────────────────────────┬──────────────────────────┘
        │ Workflow create(jobId)      │ Queue send {attemptId} (ids only)
        ▼                             ▼
 ┌───────────────────────────┐  ┌──────────────────────────┐
 │ Workflow RenderJob        │  │ Queue render-work        │──► push consumer → Cloudflare Container (FFmpeg)
 │ (instance id = job id)    │  │ + DLQ render-work-dlq    │    or HTTP pull consumer → external host (fallback)
 │ verify→normalize→sync→    │  └──────────────────────────┘    Render host: ffprobe/FFmpeg (+Remotion overlays
 │ analyze→plan→validate→    │◄── stage results / heartbeats ───  only after licence decision). No DB credential,
 │ preview→review→final→     │    (jovra-internal host routes)    no model key, no outbound network except jovra-internal.
 │ verify→deliver            │    (stage results arrive on jovra-internal's host routes, not the user gateway)
 └──────────┬────────────────┘   Cron Trigger (jovra-internal): reconciler (outbox re-dispatch, lease expiry, cleanup, retention)
            │ planner step (server-held key; sampled frames + structured events only; consent required)
            ▼
   Planner adapter: heuristic (default, no network) | Anthropic Messages API (claude-opus-5-5; only with modelProvider consent) | OpenAI "Astra" (ships disabled, no model ID configured)
```

### 1.1 Component responsibilities

| Component | Holds | Does | Must never |
|---|---|---|---|
| Native app | Originals, project JSON, local films, Keychain tokens | Records offline; links selected projects; uploads only consented sources; shows Sample on demo/test data | Hold a Supabase secret key, R2 credential, model key or render-host secret; trust its own role or price |
| Supabase Auth | Users, sessions | Issues ES256 access JWTs (default 1 h, OBSERVED local config) | Carry project roles in claims (roles live in tables; see security-model §1) |
| Postgres + RLS | Ledger of record | Deny-by-default row access; append-only revisions; command functions for privileged transitions | Trust client `owner_id`, roles, prices, R2 keys or provenance `validated` |
| Gateway Worker (`jovra-gateway`) | Nothing durable | AuthN, authZ, upload/download capabilities, quote/consent/reservation, job creation (through `jovra-internal.startJob`), share links | Buffer whole originals or parts (it streams each part to R2 while hashing it); execute model output; use the Supabase secret key on request paths; read through a caching Hyperdrive config; hold the orchestrator binding or the host secret (security-model §13.1) |
| Internal Worker (`jovra-internal`) | Nothing durable | Workflows (render, deletion), Queue consumers, reconciler, render-host routes, as `jovra_orchestrator` | Be reachable from a user route except through its two-method service binding; serve a `workers.dev` or preview URL |
| R2 | Bytes | Private storage, lifecycle backstop, object events | Be reachable through a public bucket, custom-domain public access or `r2.dev` |
| Workflow `RenderJob` | Orchestration state | Durable stage sequence, retries, waits for callbacks and review | Be the user-visible truth (each step mirrors state into Postgres) |
| Queues | Attempt ids only | Dispatch to render hosts; DLQ | Carry media bytes, URLs, user text, lease tokens or input/output lists: a message is a wake-up hint, never authority (the host claims the attempt and the gateway reads inputs and outputs from `render_attempts`) |
| Render host | Ephemeral scratch | Probe, hash, normalize, assemble, verify; writes new objects | Run model text, shell strings or filter strings; overwrite originals; reach the DB |
| Planner adapter | Nothing | Proposes a StoryPlan (IDs and fixed choices only) from bounded evidence | Receive originals, R2 keys/URLs, secrets, emails or names beyond consented display text; decide spend |

**INFERRED rationale** for the shape: Supabase gives RLS-backed metadata and Auth; R2 gives private bulk storage
with free egress (OBSERVED, https://developers.cloudflare.com/r2/pricing/); one user-facing Worker gateway keeps user
authorization in one place while orchestration lives in a second script so that no user-route code shares a process
with the orchestrator's database role (review round 2, E8), has R2/Queue/Workflow bindings that Supabase Edge Functions lack, and avoids splitting policy across two
gateways (OBSERVED limits: https://supabase.com/docs/guides/functions/limits,
https://developers.cloudflare.com/workers/platform/limits/). Workflows give durable steps, `waitForEvent` and
idempotent `createBatch()` (OBSERVED, https://developers.cloudflare.com/workflows/build/workers-api/). Containers
(GA 2026-04-13; max 4 vCPU / 12 GiB / 20 GB ephemeral disk, no GPU documented; OBSERVED,
https://developers.cloudflare.com/containers/platform-details/limits/) are the first render host, with Cloud Run Jobs
as the fallback for longer or GPU stages.

### 1.2 Proposed repository layout (when tickets land)

```
backend/
  supabase/            config.toml, migrations/, seed/ (fictional testers, Sample rows), tests/database/*.test.sql
  gateway/             Worker (TypeScript): src/, test/ (@cloudflare/vitest-plugin), wrangler.jsonc, .dev.vars (gitignored)
  render/              Render-host image: Dockerfile, src/, tests/ (synthetic media), pinned FFmpeg build manifest
  contracts/           JSON Schemas for gateway requests/responses and queue messages (shared by Worker, render, apps)
```

`.dev.vars` is not covered by the current `.gitignore` (OBSERVED in the research doc); the first gateway ticket adds
it. Core `spec/` files are not touched by backend work; Studio contracts (SourceManifest, SyncMap, StoryPlan, EDL)
get their own versioned schemas when the S0 contract ticket lands.

## 2. Environments

| | **Demo** | **Test** (isolated) | **Live** |
|---|---|---|---|
| What | In-process `DemoBackend` adapter in the app | Separate Supabase project, Worker env, R2 buckets, Queues, Workflows | Separate Supabase project, Worker env, R2 buckets, Queues, Workflows |
| Network | None | Yes | Yes |
| Identity | "Use demo profile" action; a local fictional profile, no token of any kind | Seeded tester accounts (email OTP, pre-created, allow-listed); optional anonymous sign-in for lobby experiments only | Sign in with Apple, email OTP; anonymous off |
| Data | Fictional fixtures, always labelled **Sample** | Fictional fixtures and testers' own footage; rows may be `sample = true` | Real users |
| Money | Never; quotes say "Sample quote", no reservation | No money is charged: the user-facing credits are Sample. The internal cost cap (`cap_cost_micro_usd`, real micro-USD) is always computed and enforced per reservation, and every stage also checks an operator-set environment ceiling (`app_ops.spend_limits`) because test can call a real model and run real containers | Disabled until the paid-cloud ADR and activation; the code path exists behind a server flag |
| Model planner | Heuristic only (no network) | Heuristic default; LLM only with a test-project key, inside the internal cost cap and the test environment ceiling set by Jon | Off until activation gate G6 |
| Media | Local synthetic sample video (ADR-0012) | Synthetic fixtures; testers' consented uploads | Consented uploads |

Rules (INFERRED from the brief and OBSERVED JWT behaviour):

1. **Demo has no token.** The UI shows "Demo profile, nothing leaves this phone". There is no demo credential any
   gateway could accept; a request carrying a demo marker is rejected with `401 demo_not_accepted` (test T-GW-03).
2. **Issuer pinning separates test and live.** The gateway accepts only JWTs whose `iss` equals its own environment's
   `https://<project-ref>.supabase.co/auth/v1` and whose `alg` is ES256, verified against that project's JWKS
   (OBSERVED format, https://supabase.com/docs/guides/auth/jwts). A test token is rejected by live and vice versa.
3. **Configuration, never source.** The app reads environment name, Supabase URL, publishable key, gateway base URL
   and allowed features from a build configuration (xcconfig / Gradle properties), following ADR-0008's pattern.
   Publishable keys are not secrets but still live in config so test and live builds cannot be crossed. Secret keys,
   the Hyperdrive password, render-host secrets, model keys and the Apple revoke key exist only as Worker/host
   secrets (`wrangler secret put`, OBSERVED https://developers.cloudflare.com/workers/configuration/secrets/).
4. **Tester identities come from configuration, enforced on the server.** Test-project users are created by an
   operator script reading an untracked allow-list (emails only; email OTP has no password to leak). Sign-ups are
   disabled on the test Auth project and a mandatory `before_user_created` hook rejects unknown emails; the client's
   `shouldCreateUser: false` is never the control (security-model §13.3). Locally, `supabase/seed/` creates fictional
   users at `*@example.test` addresses whose OTP mail lands in Mailpit (OBSERVED, local stack). Production builds do
   not contain a tester login path; a release build compiled against live config hides the environment switcher.
5. **The live environment is created by Jon**, not by an agent, at activation (section 13). Hostnames follow the IDC
   domain doctrine: no hostname enters code before DNS resolves; until a JOVRA deed exists the gateway would ride a
   lane hostname chosen by Jon (open question Q7).

## 3. Identity summary

Details, token checks and tests are in security-model §2. In short:

- **Sign in with Apple** (native ID token + raw nonce to Supabase, hashed nonce to Apple; OBSERVED,
  https://supabase.com/docs/guides/auth/social-login/auth-apple). The app saves the full name at first sign-in
  because it is not in the token. This is a cloud account, distinct from the core app's local-only "Continue with
  Apple" (spec story 3), which is unaffected.
- **Email one-time code** for testers and non-Apple users (OBSERVED,
  https://supabase.com/docs/guides/auth/auth-email-passwordless); production needs custom SMTP (built-in sender is
  2 emails/hour, OBSERVED https://supabase.com/docs/guides/auth/rate-limits). Sender identity is a role address under
  IDC Rule 07 (open question Q8).
- **Anonymous sign-in off in live.** Camera guests do not get accounts; they get a gateway-issued, source-scoped
  upload capability after the host approves them (section 6.1).
- **Render service** has no user identity and no database credential; it authenticates to the gateway with a host
  credential plus a per-attempt lease token (security-model §8).
- **Account deletion** is in-app and server-side, and revokes Apple tokens through Apple's REST API (OBSERVED
  requirement, https://developer.apple.com/support/offering-account-deletion-in-your-app/). Whether Supabase does the
  revocation itself is **UNVERIFIED** (Q2); the design assumes the gateway must.

## 4. Data model

### 4.1 Conventions

- Schemas: `public` (exposed through PostgREST; RLS on every table), `app_private` (not exposed; RLS helper
  functions and trigger functions; EXECUTE granted to `authenticated` only where policies need it), `app_gateway`
  (not exposed; command functions; EXECUTE granted to `jovra_gateway` for user commands or `jovra_orchestrator` for
  orchestration and `*_for_attempt` commands, never both) and `app_ops` (not
  exposed; server-only tables: upload parts, outbox, idempotency records, audit). Exposed schemas stay at the
  Supabase default (`public`, `graphql_public`); `app_*` are never added.
- IDs are `uuid` from `gen_random_uuid()`, generated by the server. Local UUIDs (ADR-0002) are stored in `local_*_id`
  columns and are unique per owner, never used as cloud primary keys (prevents primary-key existence probing across
  tenants, INFERRED).
- Time: `timestamptz` for wall-clock; match-clock and source positions are integers (`*_us bigint` microseconds, or
  rational `(value bigint, timescale int)` pairs) as in the SyncMap proposal; core `timeMs` schemas stay untouched.
- Money and credits are integers: `*_credits int`, internal cost in `*_micro_usd bigint`. No floating point (matches
  ADR-0011's integer discipline).
- Every client-editable row has `revision bigint not null default 1` bumped by trigger, and `updated_at`. Append-only
  tables (`point_event_revisions`, `source_manifests`, `sync_maps`, `calibration_versions`, `story_plan_versions`)
  get `revision int` assigned by trigger as `max + 1` under a per-project advisory lock, and no UPDATE/DELETE grants.
- Every row that can hold demo or test content has `sample boolean not null default false`; anything `sample = true`
  is shown labelled Sample and never pooled with real stats.
- Large JSON documents have size checks (`octet_length(doc::text) <= N`) so a client cannot store media in rows.
- Foreign keys are enforced. Deletes from the client are not used for anything that has R2 objects or derived media
  (lessons and lesson clips included: their deletes go through `deletion_requests`, scope `lesson`); deletion is a
  `deletion_requests` job (section 10) that removes objects first, then rows (`on delete cascade` from `projects`).
- **Actor columns never block deletion.** Every column that records who did something (`created_by`, `reviewed_by`,
  `requested_by`, `granted_by`) and can sit in a row of a project the actor does not own is
  `FK → profiles(id) on delete set null`; ownership columns (`owner_id`) cascade. So deleting a coach's account
  finishes even when the coach authored rows in other owners' projects (ADR-0022 amendment: those rows stay with the
  project, attributed to "a former collaborator").
- **Cross-project references are impossible by construction.** `camera_sources` has `U (project_id, id)`, and every
  table that names a source together with a project uses the composite
  `FK (project_id, source_id) → camera_sources(project_id, id)` (`lesson_clips`, `observations`,
  `calibration_versions`), so a row of project A can never point at project B's footage even though source UUIDs
  are not secret. Quotes, jobs and EDLs resolve sources only through the job project's current verified source
  manifest (section 7.6). The same holds for plans (story plans and versions carry their project, and jobs, quotes
  and reservations use composite FKs to them) and for server-written artifact references (security-model §13.5,
  §13.16).
- **One owner.** Every Studio table, helper, trigger and command function is owned by `jovra_owner` (security-model
  §3, T-DB-66).
- **Quotas.** Every client-insertable table has a BEFORE INSERT quota trigger (`P0429`, security-model §13.10), and
  every BEFORE trigger first checks the caller's role and raises the RLS error (§13.11).

### 4.2 Enumerated types

```sql
create type public.member_role      as enum ('owner', 'coach');                 -- coach = "coach or editor"
create type public.camera_slot      as enum ('primary_baseline', 'opposite_baseline',
                                             'near_deuce_corner', 'near_ad_corner',
                                             'far_deuce_corner', 'far_ad_corner');
create type public.source_state     as enum ('declared', 'uploading', 'uploaded_unverified', 'verified',
                                             'rejected', 'deleted');
create type public.provenance       as enum ('manual', 'estimated', 'reviewed', 'validated');
create type public.review_state     as enum ('estimated', 'needs_review', 'reviewed', 'rejected');
create type public.planner_kind     as enum ('heuristic', 'model', 'user');   -- the contract's planner.kind (story-brief, delivered-artifact); quotes.planner_choice is 'heuristic' | 'model'
create type public.job_state        as enum ('consented', 'upload_pending', 'uploading', 'queued', 'normalizing',
                                             'syncing', 'analyzing', 'planning', 'preview_rendering',
                                             'awaiting_review', 'final_rendering', 'verifying', 'ready',
                                             'paused', 'canceled', 'failed_retryable', 'failed_terminal',
                                             'quote_expired', 'budget_exceeded', 'deleted');
create type public.job_stage        as enum ('verify_sources', 'normalize', 'sync', 'analyze', 'plan', 'validate',
                                             'preview_render', 'final_render', 'remux_no_audio', 'verify_output',
                                             'deliver', 'cleanup');   -- remux_no_audio: §9.1 audio variants
create type public.artifact_kind    as enum ('analysis_proxy', 'render_proxy', 'pts_table', 'frame_set',
                                             'contact_sheet', 'preview', 'film', 'thumbnail', 'captions',
                                             'chapters', 'edit_manifest', 'project_bundle', 'clip_excerpt');
create type public.grant_kind       as enum ('project_coach', 'lesson_coach', 'lesson_view', 'film_view',
                                             'lesson_clip_view', 'share_link');
create type public.provider_kind    as enum ('files_icloud', 'google_drive', 'box', 'dropbox');  -- no 'youtube' until its own ADR (ADR-0020 covers storage providers only)
create type public.deletion_scope   as enum ('account', 'project', 'source', 'artifact', 'lesson', 'lesson_clip');
```

`draft` and `quoted` from the brief's state machine are quote states (table `quotes`), not job states: a job row is
created by quote acceptance, so it starts at `consented` (INFERRED; keeps the brief's full user-visible sequence).

### 4.3 Tables

Notation: `PK`, `FK → table(col) [on delete …]`, `U` unique, `CK` check. "Writes" names the only write path; RLS
policies are in security-model §5.

#### Identity and membership

**profiles** — one per auth user. Writes: trigger on `auth.users` insert (definer); owner updates `display_name`.
| Column | Type | Notes |
|---|---|---|
| id | uuid PK, FK → auth.users(id) on delete cascade | |
| display_name | text CK length ≤ 80 | User-entered; never put in logs or model prompts without consent |
| is_tester | boolean default false | Set only by operator script in test; read only by `accept_quote` in test (security-model §13.3), never by an RLS policy; not selectable by clients |
| created_at, updated_at | timestamptz | |
| revision | bigint | |

Email stays in `auth.users`; it is never copied to public tables.

**projects** — one Studio project (a match, an imported match, or a lesson set) linked from a local project.
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | server-generated |
| owner_id | uuid not null FK → profiles(id) on delete cascade | default `auth.uid()`; immutable (column grant + policy) |
| local_project_id | uuid not null | U (owner_id, local_project_id) |
| title | text CK ≤ 120 | |
| kind | text CK in ('match','import','lesson_set') | |
| sample | boolean | |
| current_event_revision | int null | set by trigger on `point_event_revisions` insert |
| current_source_manifest_revision | int null | set by gateway |
| current_sync_map_revision | int null | set by trigger |
| created_at, updated_at, revision | | |
| deleted_at | timestamptz null | set when a deletion request starts; policies hide deleted projects |

**project_members** — who besides the owner may see a project. The owner also has a row (role `owner`) so helpers
are uniform; a trigger keeps exactly one owner row equal to `projects.owner_id`.
| Column | Type | Notes |
|---|---|---|
| project_id | uuid FK → projects(id) on delete cascade | PK (project_id, user_id) |
| user_id | uuid FK → profiles(id) on delete cascade | index (user_id) |
| role | member_role | |
| granted_by | uuid null FK → profiles(id) on delete set null | |
| grant_id | uuid null FK → access_grants(id) on delete cascade | the redeemed `project_coach` invitation; revoking that grant revokes this row in the same transaction |
| approved_at | timestamptz null | coach rows only: the owner approved the redemption; `has_project_role` ignores a coach row until then |
| created_at | timestamptz | |
| expires_at, revoked_at | timestamptz null | |

Writes: owner row by trigger on `projects` insert; coach rows only by `app_gateway.redeem_grant` (pending, and only for
the invitee whose confirmed email matches the grant's `invitee_email_hmac`) and `app_gateway.approve_member` (owner,
after seeing the redeemer's verified, masked email and the short code both phones show; never the display name, which
the redeemer controls; security-model §13.2);
revocation by `app_gateway.revoke_member` or `app_gateway.revoke_grant` on the originating `project_coach` grant.

**camera_invites** — one-slot, one-use invitation for a camera phone to upload its assigned source.
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| project_id | uuid FK → projects(id) on delete cascade | index |
| slot | camera_slot | |
| display_label | text CK ≤ 60 | chosen by the host ("Jon's match, far corner"); the only project text a guest sees |
| code_hash | bytea not null U | SHA-256 of the 32-byte secret; secret shown once in the QR, never stored |
| created_by | uuid FK → profiles(id) on delete cascade | must be project owner |
| redeem_by | timestamptz | ≤ created_at + 10 min |
| redeemed_at | timestamptz null | |
| redeemed_by_user_id | uuid null FK → profiles(id) on delete set null | only from a verified JWT `sub` when the guest is signed in; never from the request body |
| device_key_thumbprint | bytea null | SHA-256 of the guest device's capability public key (security-model §8.2) |
| approved_at | timestamptz null | host approval tap after comparing the short code derived from the thumbprint, shown on both phones; no capability before this |
| capability_expires_at | timestamptz null | ≤ approved_at + 24 h |
| max_bytes | bigint CK > 0 | default 8 GB (INFERRED cap for a 60-min 8 Mbps source with headroom) |
| revoked_at | timestamptz null | |

One open invite per (project_id, slot): partial unique index on `(project_id, slot) where revoked_at is null and
redeemed_at is null`. An index predicate cannot use `now()` (not immutable), so expiry is not in the index:
`create_camera_invite` locks the slot's rows `FOR UPDATE`, revokes an expired unredeemed invite, then inserts.

**camera_sources** — one recorded angle in a project (the owner's own phone or a guest).
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | also U (project_id, id), the target of every composite source FK |
| project_id | uuid FK → projects(id) on delete cascade | |
| slot | camera_slot | partial U (project_id, slot) where state <> 'deleted' |
| local_source_id | uuid not null | the recording's local UUID on the device that made it |
| invite_id | uuid null FK → camera_invites(id) on delete set null | null for the owner's own sources |
| uploader_user_id | uuid null FK → profiles(id) on delete set null | null for anonymous guests |
| label | text CK ≤ 60 | owner-editable |
| state | source_state | |
| declared_bytes | bigint CK > 0 | server-held expectation |
| declared_sha256 | bytea CK octet_length = 32 | server-held expectation |
| verified_sha256 | bytea null | written only by the verify stage |
| verified_at | timestamptz null | |
| retention_until | timestamptz null | set at quote acceptance from `retentionDays` (1, 7 or 30); the daily retention sweep deletes the staged original after it (§10) |
| verified_etag | text null | R2 etag of the object the verify stage hashed; every later read uses `onlyIf: {etagMatches}` so bytes swapped after verification are never processed; column hidden from clients |
| current_session_id | uuid null | the one open upload session; completion requires it and state `uploading` |
| client_probe | jsonb CK ≤ 2 KB | the device's declaration, schema-allowlisted to codec, width, height, nominal fps, duration, rotation; never free-form tags (QuickTime location) |
| probe | jsonb CK ≤ 16 KB | codec, dimensions, rotation, HDR, timebase, duration, audio; written only by the server ffprobe in the verify stage |
| r2_key | text null | server-generated, per session (`…/original/<sessionId>`); column hidden from clients |
| rejected_reason | text null | machine code (`hash_mismatch`, `probe_rejected`, `size_mismatch`) |
| participant_ack_at | timestamptz null | guest confirmed "I'm recording this match with the players' agreement" |
| created_at, updated_at, revision | | |

**source_manifests** — immutable SourceManifest revisions (server-held expectations and verified facts).
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| project_id | uuid FK → projects(id) on delete cascade | U (project_id, revision) |
| revision | int | assigned by trigger |
| manifest | jsonb CK ≤ 512 KB | per source: ids, declared/verified hashes, probe, segments, gaps, fileZeroHostNs, rational timebases |
| manifest_sha256 | bytea | of RFC 8785 canonical JSON |
| created_by_kind | text CK in ('gateway','render') | |
| created_at | timestamptz | |

#### Sync, calibration, events, observations

**sync_maps** — immutable SyncMap revisions (`jovra.sync-map` proposal in multicam-sync §7).
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| project_id | uuid FK → projects(id) on delete cascade | U (project_id, revision) |
| revision | int | trigger |
| source_manifest_revision | int not null | FK (project_id, source_manifest_revision) → source_manifests(project_id, revision) |
| map | jsonb CK ≤ 1 MB | |
| map_sha256 | bytea | |
| review_state | review_state | `reviewed` requires `reviewed_by` |
| reviewed_by | uuid null FK → profiles(id) on delete set null | forced to `auth.uid()` by trigger when set from the client |
| reviewed_at | timestamptz null | |
| method, method_version | text | |
| created_by | uuid null FK → profiles(id) on delete set null | null when produced by a server stage |
| sample | boolean | |
| created_at | timestamptz | |

**calibration_versions** — immutable court calibrations per source.
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| project_id | uuid FK → projects(id) on delete cascade | |
| source_id | uuid; FK (project_id, source_id) → camera_sources(project_id, id) on delete cascade | U (source_id, version) |
| version | int | trigger |
| calibration | jsonb CK ≤ 64 KB | homography, reprojection residuals, image size, court model version |
| method, method_version | text | |
| provenance | provenance | client path may write only `manual`/`estimated`; never `validated` |
| reviewed_by, reviewed_at | uuid null FK → profiles(id) on delete set null; timestamptz | |
| created_by | uuid null FK → profiles(id) on delete set null | |
| created_at | timestamptz | |

**point_event_revisions** — append-only snapshots of the session event log (the score source of truth in the cloud).
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| project_id | uuid FK → projects(id) on delete cascade | U (project_id, revision) |
| revision | int | = parent_revision + 1, assigned by trigger |
| parent_revision | int null | must equal `projects.current_event_revision` at insert or the insert fails with `revision_conflict` |
| local_session_id | uuid not null | the session.json `id` |
| schema_version | text | session schema version of the embedded log |
| event_log | jsonb CK ≤ 2 MB | the session's `logEvent` array (spec/schemas/session.schema.json), unchanged |
| event_log_sha256 | bytea | of canonical JSON |
| created_by | uuid null FK → profiles(id) on delete set null | forced to `auth.uid()` at insert |
| client_device_id | uuid | random per-install id, not a hardware identifier |
| created_at | timestamptz | |

Scores and stats are never stored as authoritative cloud values. Any server component that needs a score (the EDL
compiler's score bug) derives it from `event_log` with an engine that passes the `spec/` conformance fixtures
(ADR-0001, ADR-0003), and records the revision it used. Insert triggers mark older films and plan versions `stale`.

**observations** — source-linked notes and estimated cues, with provenance.
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| project_id | uuid null FK → projects(id) on delete cascade | |
| lesson_id | uuid null FK → lessons(id) on delete cascade | a lesson-only observation dies with its lesson, and its embeddings with it |
| source_id | uuid null; FK (project_id, source_id) → camera_sources(project_id, id) on delete set null (source_id) | a source of this observation's own project only; requires `project_id`; deleting the source keeps the observation and its `project_id` |
| match_start_us, match_end_us | bigint | CK start < end |
| sync_map_revision, event_revision | int null | what the observation was computed against |
| capability_id | text | from the capability registry (spec/contracts/capability-registry.v1.json) |
| kind | text CK ≤ 40 | e.g. `note`, `cue`, `serveContact` |
| body | text CK ≤ 2,000 | user text or generated text; treated as data, never instructions |
| provenance | provenance | |
| confidence_milli | int null CK 0–1000 | |
| calibration_version_id | uuid null FK → calibration_versions(id) | |
| method, method_version | text | |
| review_state | review_state | |
| reviewed_by, reviewed_at | uuid null FK → profiles(id) on delete set null; timestamptz | |
| created_by | uuid null FK → profiles(id) on delete set null | null when produced by a server stage |
| sample | boolean | |
| created_at, updated_at, revision | | |

CK: `num_nonnulls(project_id, lesson_id) >= 1` (no parentless observation); `source_id is null or project_id is not
null`. When both parents are set, policies require access to **both** (security-model §5.3).

#### Lessons

**lessons**
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| owner_id | uuid FK → profiles(id) on delete cascade | immutable |
| local_lesson_id | uuid | U (owner_id, local_lesson_id) |
| lesson_date | date | |
| title | text CK ≤ 120 | |
| notes | text CK ≤ 10,000 | |
| next_goal | text CK ≤ 500 | |
| practice | jsonb CK ≤ 32 KB | drill items and completion counts (numerator/denominator integers) |
| sample | boolean | |
| created_at, updated_at, revision | | |

**lesson_clips** — an exact window of a project, attached to a lesson. Sharing a clip never shares the match.
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| lesson_id | uuid FK → lessons(id) on delete cascade | |
| project_id | uuid FK → projects(id) on delete cascade | the lesson owner must be owner or coach of this project (policy), checked again at every read |
| source_id | uuid null; FK (project_id, source_id) → camera_sources(project_id, id) on delete set null (source_id) | a source of `project_id` only (no cross-project clip) |
| share_approved_at | timestamptz null | set by the **project owner** (`app_gateway.approve_clip_share`), cleared by `revoke_clip_share` or by trigger `pin_shared_clip` when the window or keeper changes; a clip whose lesson owner is only a coach of the project can be granted to anyone else only after this; null for clips of the lesson owner's own projects (implicitly approved) |
| match_start_us, match_end_us | bigint | CK 0 < end − start ≤ 600,000,000 (10 min) |
| share_approved_sha256 | bytea null | `clip_share_fingerprint` of the clip at approval (project, source, window, keeper, bound revisions); a viewer sees a coach's clip only while it still equals the current fingerprint (security-model §13.8) |
| sync_map_revision, event_revision | int null | |
| keeper_ref | text null CK ≤ 96 | KeeperCatalog id |
| excerpt_artifact_id | uuid null FK → artifacts(id) on delete set null | the rendered `clip_excerpt` a viewer may stream; trigger `check_clip_excerpt` requires its kind, `lesson_clip_id` and `project_id` to match this clip; the artifact is deleted with the clip (objects first, by the deletion job) |
| note | text CK ≤ 1,000 | |
| position | int | ordering in the lesson |
| created_at, updated_at, revision | | |

#### Story plans

**story_plans**
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | also U (project_id, id), the target of the composite plan FKs |
| project_id | uuid FK → projects(id) on delete cascade | |
| lesson_ids | uuid[] CK cardinality ≤ 12 | for Progress Story across lessons; trigger `check_story_plan_lessons` requires `lesson_access(id) in ('owner','coach')` **and** the lesson owner = the project owner (a viewer grant can never bind a lesson into a plan); an array has no FK, so lesson deletion removes the id here and invalidates dependent versions and films (§10) |
| profile_id | text CK in ('coach-cut','match-broadcast','rally-pulse','progress-story','court-memories') | |
| profile_revision | int | from story-profiles.json |
| title | text CK ≤ 120 | |
| current_version | int null | |
| created_by | uuid null FK → profiles(id) on delete set null | |
| sample | boolean | |
| created_at, updated_at, revision | | |

**story_plan_versions** — immutable planner output plus the compiled EDL and its validation report.
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| story_plan_id | uuid FK → story_plans(id) on delete cascade | U (story_plan_id, version); U (story_plan_id, id) |
| project_id | uuid not null; FK (project_id, story_plan_id) → story_plans(project_id, id) on delete cascade | set by trigger from the plan, never by the client; U (project_id, id) |
| version | int | trigger |
| planner_kind | planner_kind | client path: `user` or `heuristic` only (`model` only through `app_gateway`) |
| planner_model_id | text null | pinned id, e.g. `claude-opus-5-5`; null for heuristic |
| planner_adapter_version | text | |
| story_plan | jsonb CK ≤ 256 KB | `jovra.story-plan/1`: ids and fixed choices only |
| edl | jsonb null CK ≤ 1 MB | `jovra.edit-plan/2`, compiled by deterministic code; a client-inserted EDL is only a draft: `valid` is set only after `edl.validate` with the trusted context of **this** project (its verified source manifest, reviewed sync map, reference catalog), so an EDL naming another project's source is `untrustedSource` |
| edl_sha256 | bytea null | of RFC 8785 canonical JSON |
| bound_source_manifest_revision, bound_sync_map_revision, bound_event_revision | int | |
| validation_state | text CK in ('unvalidated','valid','invalid') | only the gateway/Workflow sets `valid` |
| validation_report | jsonb CK ≤ 64 KB | |
| stale | boolean default false | set when bound revisions are superseded |
| created_by | uuid null FK → profiles(id) on delete set null | null for server-produced versions |
| created_at | timestamptz | |

#### Jobs, artifacts, money

**quotes** — a server-computed preflight. Never authored by the client.
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| project_id | uuid FK → projects(id) on delete cascade | |
| owner_id | uuid FK → profiles(id) on delete cascade | |
| story_plan_id | uuid not null; FK (project_id, story_plan_id) → story_plans(project_id, id) | the plan this quote is for, also when the version will be produced by the job |
| story_plan_version_id | uuid null; FK (story_plan_id, story_plan_version_id) → story_plan_versions(story_plan_id, id) | null when the plan will be produced by the job; with the FK above the version is of this plan and this project; `create_quote` raises `P0404` otherwise |
| output_spec_sha256 | bytea not null | canonical SHA-256 of `(projectId, planRevision, output)` computed in SQL from the stored plan version and output spec; the quote and the consent captured in it are bound to this one output (contract `jovra.quote/1`) |
| supersedes_quote_id | uuid null FK → quotes(id) | a re-quote after `budget_exceeded`; its acceptance tops up the existing reservation instead of opening a second one |
| inputs | jsonb CK ≤ 64 KB | source ids (resolved only from this project's current verified source manifest) and verified/declared bytes, angle count, profile, output spec, retention days, planner choice |
| inputs_sha256 | bytea | acceptance must present the same hash |
| rates_version | text | the rate card used (refreshed at activation) |
| line_items | jsonb | upload/storage/compute/planner estimates, each with low/high |
| estimate_low_credits, estimate_high_credits, cap_credits | int | |
| estimate_high_cost_micro_usd, cap_cost_micro_usd | bigint | internal ceiling used by stage checks |
| state | text CK in ('open','accepted','expired','superseded','declined') | `quote_expired` is surfaced from here |
| expires_at | timestamptz | ≈ 30 min after creation (pricing research §7) |
| accepted_at | timestamptz null | |
| consent | jsonb null | `{cloudProcessing, modelProvider, textClasses, retentionDays, consentTextVersion}` captured at acceptance (contract `jovra.quote/1` `consent`; `modelProvider` must be true exactly when `planner_choice = 'model'`); `textClasses` names which note text may reach a model (coach-authored text excluded by default; security-model §13.14) |
| sample | boolean | test/demo quotes are always `true` until the paid ADR |
| created_at | timestamptz | |

**usage_reservations** — the idempotent hold that bounds a job's spend.
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| project_id | uuid FK → projects(id) on delete cascade | |
| owner_id | uuid FK → profiles(id) on delete cascade | |
| quote_id | uuid U FK → quotes(id) | the current funding quote; an accepted quote funds exactly one reservation; a top-up moves this to the re-quote and marks the old quote `superseded` |
| job_id | uuid null U FK → render_jobs(id) | |
| story_plan_id | uuid not null; FK (project_id, story_plan_id) → story_plans(project_id, id) | |
| story_plan_version_id | uuid null; FK (story_plan_id, story_plan_version_id) → story_plan_versions(story_plan_id, id) | moved together with the job's version by an in-job revise (§7.1) |
| output_spec_sha256 | bytea | equals the quote's; moved by an in-job revise |
| idempotency key | — | **U (project_id, story_plan_id, story_plan_version_id, output_spec_sha256) NULLS NOT DISTINCT where state = 'held'**, the ADR-0019 / contract key `(project, plan revision, output spec)` (a plan revision names its plan, so `story_plan_id` only matters while the version is null). `NULLS NOT DISTINCT` makes two plan-by-job quotes for identical work of one plan collide, while plan-by-job work for two different plans of a project does not (security-model §13.6). The quote id is not part of it, so re-quoting identical work can never open a second hold; the client `Idempotency-Key` only deduplicates HTTP retries |
| cap_credits | int | |
| cap_cost_micro_usd | bigint | always real micro-USD, also in test (Sample applies to the credits shown, never to this cap) |
| reserved_cost_micro_usd | bigint | running sum of stage reservations |
| consumed_cost_micro_usd | bigint | actual, recorded per attempt |
| released_cost_micro_usd | bigint | returned on cancel/failure/settle |
| state | text CK in ('held','settled','released') | |
| sample | boolean | |
| created_at, updated_at | | |

CK: `reserved_cost_micro_usd <= cap_cost_micro_usd`; `consumed + released <= reserved`.

**app_ops.spend_limits** `(scope ('owner','environment'), owner_id null, max_open_cap_micro_usd bigint not null CK > 0,
daily_ceiling_micro_usd bigint not null CK > 0, updated_by_operator_at)`, with partial unique indexes so there is at
most one environment row, one default owner row (`owner_id is null`) and one row per owner. **app_ops.spend_commitments**
`(id, at timestamptz default now(), owner_id, reservation_id, kind ('cap_open','cap_topup','stage_reserve'),
amount_micro_usd bigint CK > 0)` is append-only and written in the same transaction as the reservation change it
records. `accept_quote` refuses (`P0402`) when the owner's held caps plus the new cap exceed the owner's
`max_open_cap_micro_usd`, or when today's `cap_open` + `cap_topup` commitments (UTC day) plus the new cap (or top-up
delta) exceed the environment's `daily_ceiling_micro_usd`; `reserve_stage` refuses when today's `stage_reserve`
commitments plus the stage estimate exceed it. **Fail closed:** an owner without their own row uses the default owner
row; a missing default or environment row, or a NULL limit reached through any path, is `P0402` (the SQL in
security-model §13.7 compares with `coalesce(limit, -1)`, so NULL can never pass). In test the environment row is set
by Jon and bounds real model and container spend even though no credits are charged.

**render_jobs**
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | also the Workflow instance id |
| project_id | uuid FK → projects(id) on delete cascade | |
| story_plan_id | uuid; FK (project_id, story_plan_id) → story_plans(project_id, id) | |
| story_plan_version_id | uuid null; FK (story_plan_id, story_plan_version_id) → story_plan_versions(story_plan_id, id) | the version currently being rendered; `review_job` asserts a revision's version belongs to this plan |
| parent_job_id | uuid null FK → render_jobs(id) | a revision rendered under a new quote |
| quote_id | uuid FK → quotes(id) | the accepting quote (a top-up re-quote is recorded on the reservation) |
| reservation_id | uuid U FK → usage_reservations(id) | |
| requested_by | uuid null FK → profiles(id) on delete set null | must be owner at request time |
| output_spec_sha256 | bytea | U (project_id, story_plan_id, story_plan_version_id, output_spec_sha256) NULLS NOT DISTINCT where state is not terminal: identical work never runs as two jobs |
| idempotency_key | text | the accept request's HTTP key (deduplicates retries only; never the domain key) |
| state | job_state | |
| stage | job_stage null | current stage |
| stage_progress_milli | int null CK 0–1000 | progress of the current stage only (screen 38's 42% is a stage value) |
| output_spec | jsonb CK ≤ 4 KB | fps rational, width, height, container/codecs, aspect, duration target |
| error_code | text null | machine code; user copy is mapped in the app |
| cancel_requested_at, paused_at | timestamptz null | |
| review_requested_at, reviewed_at | timestamptz null | |
| sample | boolean | |
| created_at, updated_at, finished_at | | |

**render_attempts** — one row per (job, stage, attempt): leases, fencing, measurements and actual usage.
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| job_id | uuid FK → render_jobs(id) on delete cascade | U (job_id, stage, attempt) |
| stage | job_stage | |
| attempt | int CK ≥ 1 | |
| state | text CK in ('reserved','dispatched','running','succeeded','failed','lease_expired','canceled','dead_lettered') | |
| lease_token_hash | bytea null | SHA-256 of the lease token, minted only when a host claims the attempt (`claim_attempt`); null until then; a second claim is fenced; column hidden from clients |
| claimed_by_host | text null | host credential id that claimed it |
| leased_until | timestamptz | |
| heartbeat_at | timestamptz null | |
| host_kind | text | `cf-container`, `cloud-run`, `local-test` |
| input_refs | jsonb CK ≤ 64 KB | computed by `reserve_stage` in SQL from the job's own project only (its verified source manifest and prior verified artifacts); the only list `authorize_attempt_input` accepts |
| output_plan | jsonb CK ≤ 16 KB | output refs, kinds and a byte cap per output computed by `reserve_stage`; the only list `register_artifact` and `authorize_output_upload_for_attempt` accept |
| input_hash | bytea | hash of the stage's canonical inputs |
| output_refs | jsonb CK ≤ 64 KB | artifact ids actually written by this attempt (⊆ `output_plan`) |
| measurements | jsonb CK ≤ 64 KB | wall time, CPU, bytes in/out, planner tokens (input, cache, output); not granted to clients (cost is derivable from it) |
| reserved_cost_micro_usd, actual_cost_micro_usd | bigint | the reservation is computed in SQL from `rates_version` and the inputs with a floor (never a caller estimate); the host's wall-time limit is derived from it, and for the `plan` stage so are the planner's `max_tokens`, image count, effort and the one repair call (§7.6, security-model §13.7); an actual cost above the reservation is committed as `stage_overrun` and stops the job at `budget_exceeded` |
| planner_budget | jsonb null CK ≤ 4 KB | `plan` stage only, written by `reserve_stage`: `{maxImages, maxInputTokens, maxOutputTokens, effort, repairAllowed}` derived from `reserved_cost_micro_usd`; the Workflow's planner step reads it back and passes exactly these to the provider |
| error_code | text null | |
| retryable | boolean null | |
| created_at, started_at, finished_at | | |

**artifacts** — every server-made object in R2 (sources are in `camera_sources`).
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | also U (project_id, id) |
| project_id | uuid FK → projects(id) on delete cascade | |
| job_id | uuid null FK → render_jobs(id) on delete set null | |
| attempt_id | uuid null FK → render_attempts(id) on delete set null | |
| source_id | uuid null; FK (project_id, source_id) → camera_sources(project_id, id) on delete cascade | for proxies/frames |
| parent_artifact_id | uuid null; FK (project_id, parent_artifact_id) → artifacts(project_id, id) on delete cascade | thumbnail/captions/chapters belong to a film of the same project; the deletion job deletes children's objects before the cascade |
| lesson_clip_id | uuid null FK → lesson_clips(id) on delete cascade | for `clip_excerpt` (row cascade is a backstop; the deletion job removes the object first) |
| kind | artifact_kind | `project_bundle` = the delivered film(s) plus EDL, chapters, captions and edit manifest of one job; never originals, proxies, frames or PTS tables; owner-only |
| bucket_class | text CK in ('work','films') | column hidden from clients |
| r2_key | text not null U | server-generated; column hidden from clients |
| bytes | bigint | |
| sha256 | bytea | computed by the writer and re-checked by verification |
| media | jsonb CK ≤ 16 KB | duration (rational), frame count, dimensions, fps, codecs, audio |
| state | text CK in ('writing','verifying','ready','failed','deleted') | |
| verification | jsonb null | full-decode report (film-engine §3.10) |
| edl_sha256 | bytea null | binds a film to its plan |
| event_revision, sync_map_revision, source_manifest_revision | int null | |
| profile_id, profile_revision | text, int null | |
| renderer_version | text null | |
| stale | boolean default false | true once a newer event revision exists; still downloadable, labelled "older version" |
| retention_until | timestamptz null | films: user's explicit choice; work: the accepted quote's `retentionDays` after creation (1, 7 or 30), executed by the daily retention sweep |
| display_title | text CK ≤ 120 | what a viewer sees |
| sample | boolean | |
| created_at, verified_at, deleted_at | | |

**artifact_sources** `(artifact_id FK → artifacts(id) on delete cascade, project_id, source_id; FK (project_id, source_id)
→ camera_sources(project_id, id) on delete cascade; PK (artifact_id, source_id))` — written by `register_artifact` from
the attempt's `input_refs`; the source-scope deletion uses it to find every film, preview and excerpt that contains
the source's frames (security-model §13.9).

**access_grants** — every non-member access path: coach invitations, lesson/film/clip shares, 24 h share links.
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| kind | grant_kind | |
| project_id | uuid null FK → projects(id) on delete cascade | also set (server-side) on every artifact-targeted grant |
| lesson_id | uuid null FK → lessons(id) on delete cascade | |
| artifact_id | uuid null; FK (project_id, artifact_id) → artifacts(project_id, id) on delete cascade | `film_view`, `share_link` |
| lesson_clip_id | uuid null FK → lesson_clips(id) on delete cascade | |
| grantee_user_id | uuid null FK → profiles(id) on delete cascade | null until a code is redeemed; always null for `share_link` |
| token_hash | bytea null U | SHA-256 of invitation or share token; column hidden |
| invitee_email_hmac | bytea null | HMAC-SHA256 (server key) of the invitee's lower-cased email; required for every kind except `share_link`; redemption needs an account whose confirmed email matches; column hidden; the email itself is never stored or logged (security-model §13.2) |
| created_by | uuid FK → profiles(id) on delete cascade | must own the target; for `lesson_clip_view` and for `lesson_view` of a lesson with clips, the clip's project owner must also have approved sharing each clip (`lesson_clips.share_approved_at`) unless the creator owns that project |
| redeem_by | timestamptz null | invitation codes: ≤ created_at + 7 days to redeem; null for `share_link` |
| expires_at | timestamptz null | end of access; `share_link` requires ≤ created_at + 24 h; null = until revoked |
| redeemed_at | timestamptz null | a grant is active once redeemed (or immediately for `share_link`), unrevoked and unexpired; a `project_coach` redemption only creates a pending membership until the owner approves it |
| revoked_at | timestamptz null | |
| created_at | timestamptz | |

CK: exactly the target columns required by `kind` are non-null (e.g. `share_link` ⇒ `project_id` and `artifact_id`; a share link
can target only a `film`, `preview` owned by the creator, or a `clip_excerpt`, never a source or proxy, enforced in
`app_gateway.create_share_link`).

#### Providers, deletion, audit, server-only tables

**provider_connections** — capability *status* of optional archives. Tokens never leave the device (ADR-0008).
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| user_id | uuid FK → profiles(id) on delete cascade | U (user_id, provider) |
| provider | provider_kind | |
| state | text CK in ('planned','awaiting_setup','not_connected','connected','expired','revoked') | |
| account_label | text null CK ≤ 120 | user-visible label only; no email copied here |
| scopes | text[] | e.g. `{drive.file}` |
| updated_at, revision | | |

No token, refresh token or secret column exists. `provider_kind` has no `youtube` value: "Prepare for YouTube" is a
local export, and any YouTube connection (server-side token, upload) needs its own ADR using Supabase Vault and is out
of scope.

**deletion_requests**
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| requested_by | uuid null FK → profiles(id) on delete set null | null after an account deletion completes |
| scope | deletion_scope | |
| target_id | uuid | |
| state | text CK in ('requested','canceling_jobs','deleting_objects','deleting_rows','revoking_apple','done','failed') | |
| counts | jsonb | objects/rows deleted per class (numbers only) |
| error_code | text null | |
| created_at, updated_at, finished_at | | |

**audit_events** (in `app_ops`, append-only, no client access)
| Column | Type | Notes |
|---|---|---|
| id | bigint generated always as identity PK | |
| at | timestamptz | |
| env | text | |
| actor_kind | text CK in ('user','camera_guest','render_host','gateway','cron','operator') | |
| actor_id | uuid null | user id, invite id or attempt id; never an email |
| project_id | uuid null | not a FK, so tombstones survive project deletion |
| action | text | e.g. `quote.accept`, `upload.complete`, `grant.create`, `artifact.download`, `job.cancel` |
| target_kind, target_id | text, uuid | |
| outcome | text CK in ('allowed','denied','error') | |
| reason_code | text null | |
| request_id | uuid | |
| detail | jsonb CK ≤ 4 KB | hashes, counts, revision numbers; no names, notes, emails, tokens, keys or IPs |

**app_ops.upload_sessions**, **app_ops.upload_parts** — server-held upload expectations.
| upload_sessions column | Notes |
|---|---|
| id uuid PK; source_id FK → camera_sources(id) on delete cascade; project_id | |
| actor_kind ('owner','camera_guest','render_host'); actor_id | who opened it |
| r2_key, r2_upload_id | server-generated, unique per session (`staging/p/<pid>/s/<sid>/original/<sessionId>`), so two sessions never write one key |
| expected_bytes bigint; expected_sha256 bytea; part_size int (fixed 32 MiB); part_count int | from the source declaration, not from the part requests |
| state ('opening','open','completing','completed','aborted','expired') | partial U (source_id) where state in ('opening','open','completing'): one open session per source; opening a new one aborts the old in the same transaction |
| expires_at, hard_expires_at | idle expiry ≤ 24 h after the last part; absolute ceiling `hard_expires_at = created_at + 48 h`, never extended |
| capability_hash bytea | session capability, hashed |

| upload_parts column | Notes |
|---|---|
| session_id FK on delete cascade; part_number int CK 1–10,000 | PK (session_id, part_number) |
| bytes int; etag text; sha256 bytea; received_at | sha256 from the gateway's streamed digest (UNVERIFIED performance) |

**app_ops.job_outbox** — `(id, job_id, kind, payload jsonb ≤ 8 KB, created_at, dispatched_at, attempts)`; written in
the same transaction as the job or attempt, re-dispatched by the reconciler. The payload holds ids only
(`{jobId}` or `{attemptId}`), never a lease token or any `jv*_` secret.

**app_ops.idempotency_records** — `(actor_id, route, key) PK, request_sha256, response_status, response_body jsonb
≤ 16 KB, created_at, expires_at (created_at + 7 days)`. Routes that mint a bearer secret (camera invite `code`, guest
`capability`, upload `sessionCapability`, share-link `url`, grant `code`) store a **redacted** body (ids and expiry,
no secret). A replay of such a request returns `409 secret_not_replayable` with the resource id; the client then asks
for a fresh secret through the resource's own route, which revokes the earlier one in the same transaction. No
`jv[igslhc]_` value ever lands in `app_ops` (test T-DB-47).

#### Optional: embeddings (later, only after a measured retrieval need)

**lesson_embeddings** (pgvector, `create extension vector with schema extensions`, OBSERVED
https://supabase.com/docs/guides/database/extensions/pgvector)
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| owner_id | uuid FK → profiles(id) on delete cascade | |
| lesson_id | uuid null FK → lessons(id) on delete cascade | |
| observation_id | uuid null FK → observations(id) on delete cascade | |
| project_id | uuid null FK → projects(id) on delete cascade | |
| content_sha256 | bytea | of the embedded text, so stale embeddings are detectable |
| embedding | extensions.vector(1024) | ≤ 2,000 dimensions to stay HNSW-indexable (OBSERVED, https://github.com/pgvector/pgvector) |
| model_id | text | |
| created_at | timestamptz | |

Retrieval is a `security invoker` SQL function in `public` so RLS applies (OBSERVED pattern,
https://supabase.com/docs/guides/ai/rag-with-permissions), with `set search_path = ''` and the distance operator
qualified as `OPERATOR(extensions.<=>)` (T-DB-03 lints every function in `public`), and `hnsw.iterative_scan` enabled
because filtering after an approximate scan can under-return rows. Deleting a lesson or observation cascades its
embeddings in the same transaction (ADR-0021); a row with both `project_id` and `lesson_id` is visible only with
access to both. Start with Postgres full-text search on `lessons.notes` and
`observations.body`; Pinecone is not used.

#### Deferred (optional cloud camera lobby, stage S3)

`recording_acks (project_id, source_id, intent_id, segment_id, file_zero_host_ns, reported_at)` and a private
Realtime topic per project. Durable facts are rows; presence carries readiness only (backend research §6). Local
transport remains the primary capture coordination path.

### 4.4 Derived-state triggers (INFERRED)

| Trigger | On | Effect |
|---|---|---|
| `bump_revision` | UPDATE of any client-editable row | `new.revision = old.revision + 1; new.updated_at = now()` |
| `assign_next_revision` | INSERT on append-only revision tables | takes `pg_advisory_xact_lock(hashtext(project_id::text))`, sets `revision = coalesce(max,0)+1` |
| `check_event_parent` | INSERT on `point_event_revisions` | raises `revision_conflict` (SQLSTATE `P0409`) unless `parent_revision is not distinct from projects.current_event_revision`; then sets the project pointer |
| `mark_stale` | after the above | `update artifacts set stale = true where project_id = … and event_revision < new.revision and kind in ('preview','film','clip_excerpt')`; same for `story_plan_versions` |
| `create_owner_membership` | INSERT on `projects` | inserts the `owner` row |
| `handle_new_user` | INSERT on `auth.users` | inserts `profiles` |
| `force_actor_columns` | INSERT/UPDATE | sets `created_by`/`reviewed_by` to `auth.uid()` when called through PostgREST |
| `check_story_plan_lessons` | INSERT/UPDATE on `story_plans` | on the client path (`app_private.is_client_path()`), every `lesson_ids` entry **added** by this statement (in `new.lesson_ids` and not in `old.lesson_ids`) has `lesson_access in ('owner','coach')` for the caller, and every entry's owner is the project owner. On the server path (`auth.uid()` is null: the lesson-scope deletion step's `array_remove`, server stages) the caller check is skipped, because removing an id never grants access; the same-owner check still runs (security-model §13.9 (b), T-DB-73) |
| `a00_rls_guard` | BEFORE INSERT on every client-insertable table | the INSERT policy's predicate, evaluated first; `42501` (security-model §13.11) |
| `enforce_quota` | BEFORE INSERT on every client-insertable table | per-project and per-user daily rows and bytes, lifetime bytes; a table without a limits row refuses; `P0429 quota_exceeded` (security-model §13.10) |
| `pin_shared_clip` | BEFORE UPDATE on `lesson_clips` | a change of the clip's fingerprint (source, window, keeper, revisions) clears `share_approved_at`/`share_approved_sha256` and unlinks and hides the excerpt (security-model §13.8) |
| `check_clip_excerpt` | BEFORE INSERT/UPDATE of `excerpt_artifact_id` (server path) | the excerpt is a `clip_excerpt` of this clip and project |
| `validate_lengths` | BEFORE INSERT/UPDATE on every client-written table | checks every length/size limit and raises a coded error (`P0422 field_too_long:<column>`) before a CHECK or NOT NULL constraint can fire, so Postgres never emits a `Failing row contains (…)` DETAIL holding row values (hashes, thumbprints, notes, bodies) into logs or PostgREST responses |

Order is by name (PostgreSQL fires same-event triggers alphabetically), so BEFORE triggers carry sort prefixes
(security-model §13.0): `a00_rls_guard` first, then `a05_set_parent_project`, `a10_validate_lengths`,
`a20_enforce_quota`, `a30_force_actor_columns`, `a40_assign_next_revision`/`a40_check_event_parent`, then the `b20_`
clip triggers. `a00_rls_guard` calls the same predicate as the table's INSERT policy and raises RLS's own `42501`
before any lock, lookup or update: PostgreSQL enforces `WITH CHECK` after BEFORE triggers fire, so a trigger that ran
first would otherwise be an existence and revision oracle (security-model §13.11). Server stages are recognised by
`app_private.is_client_path()` and skip the guard and quotas.
All trigger functions are `security definer`, `set search_path = ''`, fully qualified, live in `app_private`, and have
EXECUTE revoked from `public`, `anon` and `authenticated` (also for functions added by later migrations, through
`alter default privileges for role jovra_owner`, security-model §3).

## 5. Gateway API

Base URL: `<gateway-origin>/v1`, origin from configuration (Q7). JSON over HTTPS. Every response carries
`X-Request-Id` (a UUID minted by the gateway; a client-supplied id is echoed only as `clientRequestId` after format
validation).

**Envelope.** Success: `{"data": …, "requestId": "…"}`. Error: `{"error": {"code": "…", "message": "…",
"retryable": bool}, "requestId": "…"}`. Error messages never reveal whether an object exists in another tenant: an
object the caller may not see returns `404 not_found`, identical to a missing one (security-model I7).

**Authentication headers.**
- `Authorization: Bearer <supabase access JWT>` for signed-in users.
- `Authorization: JOVRA-Capability <token>` for camera guests (session or guest capability) and share-link redemption.
- Render host: `Authorization: JOVRA-Host <host credential>` plus `JOVRA-Lease: <attempt lease token>` (security-model §8.4).

**Idempotency.** Every POST that creates or changes state requires `Idempotency-Key: <UUIDv4>`. The gateway stores
`(actor, route, key) → (request hash, response)` for 7 days; a replay with the same body returns the stored response;
the same key with a different body returns `422 idempotency_key_reused`. Responses that carry a bearer secret are
stored redacted and their replay is `409 secret_not_replayable` (§4.3 `idempotency_records`). Domain-level uniqueness
backs it up and is the real guarantee: one held reservation and one non-terminal job per
`(project, story plan, story plan version, output spec hash)` (NULLS NOT DISTINCT) whatever the HTTP key or quote, Workflow instance id = job id,
attempt rows unique per `(job, stage, attempt)`, consumption once per `(job, stage)`.

**Database access.** The gateway reaches Postgres through Hyperdrive with **query caching disabled**
(`wrangler hyperdrive create … --caching-disabled`). OBSERVED: caching is on by default with `max_age` 60 s and 15 s
stale-while-revalidate, and uncacheable queries are found by "text-based pattern matching"
(https://developers.cloudflare.com/hyperdrive/concepts/query-caching/, read 2026-10-07). INFERRED: a call such as
`select app_gateway.authorize_artifact_read($1,$2,$3)` names no known volatile builtin and could be served from cache,
undoing per-request revocation and returning a cached result instead of running a state change. As defence in depth,
command functions are invoked with `call`/non-`select` forms where the driver allows, and every authorization function
is declared `volatile`. Test T-GW-21 revokes a share link and requests it again within 60 s through the Hyperdrive
local binding; activation gate G2 records the config's caching flag.

**Platform logs.** The gateway's Wrangler config sets `[observability.logs] invocation_logs = false`: OBSERVED,
invocation logs record "the Request, Response, and related metadata" (https://developers.cloudflare.com/workers/observability/logs/workers-logs/,
read 2026-10-07), which would put `/s/<token>` paths, client IPs and headers into Workers Logs, Logpush and tails.
Only the allowlisted app logger writes logs (security-model §9).

**Rate limits** (INFERRED starting values, enforced with Cloudflare rate-limiting bindings or a Durable Object
counter; tune after measurement): invite redemption 10/min per IP-hash and 5 failures per invite; grant redemption (`/v1/grants/redeem`) 10/hour and 5
failures/hour per user; quote creation
20/hour per user; share-link creation 50/day per user; job acceptance 10/hour per user; `/s/<token>` 60 requests/min
per token hash with a byte budget of 3× the artifact size per hour (security-model §13.15).

### 5.1 Endpoints

| Method and path | Caller | Request (body) | Response `data` | Checks (all re-run per request) |
|---|---|---|---|---|
| `GET /v1/health` | anyone | — | `{env, version}` | none; no data |
| `GET /v1/me` | user | — | `{userId, displayName, env, features}` | JWT |
| `POST /v1/projects/{projectId}/sources` | owner | `{slot, localSourceId, declaredBytes, declaredSha256, probeSummary}` | `{sourceId, state}` | owner; slot free; bytes ≤ cap; sha256 64 hex; `probeSummary` schema-allowlisted (codec, width, height, fps, duration, rotation) and stored as `client_probe`, never as `probe` |
| `POST /v1/projects/{projectId}/camera-invites` | owner | `{slot, displayLabel}` | `{inviteId, code, redeemBy}` (code returned once) | owner; slot free; ≤ 5 live invites |
| `DELETE /v1/projects/{projectId}/camera-invites/{inviteId}` | owner | — | `{revokedAt}` | owner |
| `POST /v1/camera-invites/redeem` | guest (no JWT needed; a JWT, if present, is verified and its `sub` is the only source of `redeemed_by_user_id`) | `{code, devicePublicKey (P-256 JWK), deviceLabel}` | `{redemptionId, deviceCode, status:"awaiting_host"}` (`deviceCode` = 6 digits derived from the key thumbprint; no project text before approval) | code hash match; unexpired; unredeemed; not revoked; rate limit |
| `POST /v1/projects/{projectId}/camera-invites/{inviteId}/approve` | owner | `{redemptionId, deviceCode}` | `{approvedAt}` | owner; redemption pending; `deviceCode` equals the one derived from the stored thumbprint (the host compares the code shown on both phones; the guest-supplied label is never the basis for approval) |
| `POST /v1/camera-invites/redemptions/{redemptionId}/capability` | guest | signed challenge `{nonce, signature}` | `{capability, displayLabel, slot, scope:{projectRef, slot, ops:["source.declare","upload"]}, expiresAt}` | approved; device key signature valid; nonce unused (replay cache); not revoked |
| `POST /v1/guest/sources` | guest capability | `{localSourceId, declaredBytes, declaredSha256, probeSummary, participantAck:true}` | `{sourceId}` | capability scope = slot; one source per invite; request signature with nonce (replay cache, 10 min) |
| `POST /v1/sources/{sourceId}/uploads` | owner or guest | `{declaredBytes, declaredSha256, contentType}` (must equal the source declaration) | `{sessionId, partSize, partCount, sessionCapability, expiresAt, hardExpiresAt, partTarget:{method:"PUT", urlTemplate, headers}}` | actor may upload this source; state `declared` or `uploading`; bytes and hash equal the server-held declaration; any open session of this source is aborted in the same transaction and becomes `current_session_id` (one open session per source) |
| `GET /v1/uploads/{sessionId}` | session holder | — | `{state, confirmedParts:[{n,bytes,etag}], expiresAt}` | session capability + fresh actor check |
| `PUT /v1/uploads/{sessionId}/parts/{n}` | session holder | raw bytes; `Content-Length`; `X-Jovra-Part-Sha256` | `{n, bytes, etag, sha256}` | session open; actor still authorized; n in 1..partCount; exact length; digest match |
| `POST /v1/uploads/{sessionId}/complete` | session holder | `{parts:[{n, etag}]}` | `{sourceState:"uploaded_unverified"}` | section 6.3 |
| `DELETE /v1/uploads/{sessionId}` | session holder or owner | — | `{state:"aborted"}` | |
| `POST /v1/projects/{projectId}/quotes` | owner | `{storyPlanId, storyPlanVersionId?, plannerChoice:"heuristic"|"model", outputSpec, sourceIds, retentionDays}` | quote (all `quotes` columns except internal cost) | owner; every `sourceId` resolves through **this** project's current verified source manifest (a foreign or unknown id is `404`); inputs and `output_spec_sha256` computed server-side from rows, not from the request's numbers |
| `POST /v1/quotes/{quoteId}/accept` | owner | `{inputsSha256, consent:{cloudProcessing:true, modelProvider:bool, textClasses:[…], retentionDays, consentTextVersion}, acceptedCapCredits}` | `{jobId, reservationId, state:"consented"}` (a re-quote after `budget_exceeded` returns the existing job and the topped-up reservation) | owner; quote open and unexpired; hash and cap equal stored; real user; owner open-cap and environment ceilings (`app_ops.spend_limits`); no held reservation for the same `(project, plan, plan version, output spec)` unless this quote supersedes its quote |
| `GET /v1/jobs/{jobId}` | owner, coach | — | `{state, stage, stageProgressMilli, stages:[…], artifacts:[…]}` plus `usage:{estimate, cap, actual}` for the owner only | role; coaches never see money (T-DB-25) |
| `POST /v1/jobs/{jobId}/cancel` | owner | — | `{state}` | owner; not terminal |
| `POST /v1/jobs/{jobId}/pause`, `/resume` | owner | — | `{state}` | owner |
| `POST /v1/jobs/{jobId}/review` | owner | `{decision:"approve"|"revise", storyPlanVersionId?}` | `{state}` | owner; job `awaiting_review`; a revision over the remaining reservation returns `409 requote_required` |
| `POST /v1/jobs/{jobId}/retry` | owner | — | `{state}` | `failed_retryable`; budget check |
| `GET /v1/artifacts/{artifactId}/content` | owner, coach, granted viewer | `Range` header optional; `?audio=include|none` for a download of a film (default from the profile's `exportAudio.includeByDefault`; `none` forced in junior mode); in-app playback omits it and streams the film itself | bytes (206/200) of the artifact actually chosen: the film, or its verified no-audio child | section 9 |
| `POST /v1/artifacts/{artifactId}/share-links` | owner | `{expiresInSec ≤ 86400, includeAudio: bool}` (`includeAudio` required for a film; false forced in junior mode) | `{shareLinkId, url, expiresAt}` (token in URL, returned once; a replay is `409 secret_not_replayable`) | owner; artifact kind shareable; state ready; the link stores the id of the artifact it serves (the film, or its verified no-audio child, created on demand by `remux_no_audio` + `verify_output` before the link is returned) |
| `DELETE /v1/share-links/{shareLinkId}` | owner | — | `{revokedAt}` | owner |
| `GET /s/{token}` | anyone with the link | `Range` optional | bytes of the linked artifact | section 9.2 |
| `GET /s/{token}/thumbnail` | anyone with the link | — | bytes of the linked artifact's thumbnail (`parent_artifact_id` = linked artifact) | section 9.2; no other artifact is addressable under a token |
| `POST /v1/grants` | owner | `{kind, inviteeEmail, projectId?, lessonId?, artifactId?, lessonClipId?, expiresInSec}` | `{grantId, code, expiresAt}` | owner of target; kind/target consistency; `inviteeEmail` required (stored only as an HMAC, never logged); for clip-bearing targets every clip is of the creator's own project or carries the project owner's `share_approved_at` |
| `POST /v1/grants/redeem` | user | `{code}` | `{kind, target, status}` (`project_coach`: `status:"awaiting_owner"`, with a 6-digit code to read to the owner) | real user with a confirmed email whose HMAC equals the grant's `invitee_email_hmac` (else `404`, identical to an unknown code); unexpired; unredeemed |
| `POST /v1/projects/{projectId}/members/{userId}/approve` | owner | `{code}` | `{approvedAt}` | owner; pending coach redemption; code matches; the pending view shows the redeemer's verified, masked email, never the display name |
| `POST /v1/lesson-clips/{clipId}/share-approval` | project owner | — | `{shareApprovedAt}` | owner of the clip's project |
| `DELETE /v1/lesson-clips/{clipId}/share-approval` | project owner | — | `{shareApprovedAt:null}` | owner of the clip's project (`revoke_clip_share`) |
| `DELETE /v1/grants/{grantId}` | grant creator, or owner of the project whose footage a clip grant reaches | — | `{revokedAt}` | a `project_coach` grant revokes the membership it created in the same transaction |
| `POST /v1/account/apple-link` | user (SIWA) | `{authorizationCode}` | `{linked:true}` | real user; exchanged once for the refresh token needed to revoke at deletion (security-model §2.3) |
| `POST /v1/deletion-requests` | user | `{scope, targetId, confirmDependents?}` | `{deletionRequestId, state}` or `409 dependents` (a source used in films: lists them; resend with `confirmDependents:true`) | owner of target; account scope needs an **authentication** within 10 minutes: the JWT's `session_id` must name an Auth session created ≤ 10 min ago (a new sign-in; a refresh keeps the old session, and a refreshed token's `iat` is never enough; `401 reauth_required`; security-model §2.2, §13.4) |
| `GET /v1/deletion-requests/{id}` | requester | — | `{state, counts}` | requester |
| *Internal routes below are served by `jovra-internal`, never by the user gateway (security-model §13.1).* | | | | |
| `POST /internal/v1/attempts/{attemptId}/claim` | render host | — | `{leaseToken, leasedUntil, inputRefs, outputPlan}` (token minted now; only its hash is stored) | host credential; attempt `dispatched` and unclaimed; a second claim → `409 already_claimed` (fenced) |
| `POST /internal/v1/attempts/{attemptId}/heartbeat` | render host | `{progressMilli, measurementsSoFar}` | `{leasedUntil, cancel:bool}` | host credential; lease token matches current attempt; state running |
| `GET /internal/v1/attempts/{attemptId}/inputs/{inputRef}` | render host | `Range` optional | bytes | lease valid; `inputRef` ∈ `render_attempts.input_refs` (computed by `reserve_stage`; nothing from the queue message is consulted) |
| `POST /internal/v1/attempts/{attemptId}/outputs` | render host | `{outputRef, kind, declaredBytes, sha256}` | upload session (same protocol as section 6, through the `*_for_attempt` commands) | lease valid; `outputRef` ∈ `render_attempts.output_plan`; `declaredBytes` ≤ that output's cap |
| `POST /internal/v1/attempts/{attemptId}/result` | render host | `{outcome:"succeeded"|"failed", outputs:[…], measurements, errorCode?, retryable?}` | `{accepted:bool}` | lease token fencing (security-model §8.4) |

Owner-editable metadata (project titles, lessons, lesson clips, manual observations, story drafts, event revisions,
sync map and calibration revisions, provider status) goes straight to PostgREST under RLS; it does not need the
gateway. Deleting a lesson or a lesson clip does not: it is a `POST /v1/deletion-requests` with scope `lesson` or
`lesson_clip` so its derived media are removed first. Lesson search is `POST /rest/v1/rpc/search_lessons` with the
query in the body, never a query-string filter (security-model §9). Direct inserts are bounded by quota triggers. Everything that issues a capability, touches R2, money, membership or another user's access goes through
the gateway.

### 5.2 Capability lifetimes

| Capability | Lifetime | Revocation takes effect | Bound to |
|---|---|---|---|
| Supabase access JWT | 1 h default (OBSERVED local config); refresh token rotation per Supabase | Next token refresh; DB checks are fresh on every gateway call, so revoked membership stops at the next request | user |
| Camera invite code | redeem within 10 min; single use | Immediately (row check) | project + slot |
| Guest capability | ≤ 24 h after host approval, ends at upload completion | Next request (row check) | invite, device key, slot |
| Upload session capability | idle ≤ 24 h, renewed while parts arrive; absolute ceiling 48 h from opening | Next part; a newer session for the source aborts it | session, source, project |
| Attempt lease token | minted at claim; 5 min, extended by heartbeat (every 60 s) up to the stage's maximum wall time | Next heartbeat/callback (fenced) | job, stage, attempt, claiming host |
| Coach/viewer invitation code | redeem within 7 days; a `project_coach` redemption also needs the owner's approval | Immediately; revoking the grant also revokes the membership | target |
| Share link token | ≤ 24 h | Immediately (row check per request) | one artifact |
| Presigned R2 GET (optional, after spike) | ≤ 5 min | **Not revocable before expiry** (OBSERVED, https://developers.cloudflare.com/r2/api/s3/presigned-urls/) | one object, GET |
| Quote | ≈ 30 min | — | inputs hash |
| Idempotency record | 7 days | — | actor + route + key |

## 6. Upload flow

### 6.1 Who uploads what

- **Owner's own sources**: the owner declares each source (`POST /projects/{id}/sources`) from the local manifest
  (bytes, SHA-256, probe summary), then opens upload sessions.
- **Camera guests**: the host creates a one-slot invite; the guest's phone scans the QR (the local room's QR can
  carry it, multicam-sync §2.4), redeems with a fresh device key pair, waits for the host's approval tap, receives a
  guest capability bound to that key, declares exactly one source for its slot and uploads it. A guest cannot list,
  read or download anything, including its own upload after completion (it still has its local original).
- **Render host outputs** use the same session protocol through `jovra-internal` and the lease-fenced
  `*_for_attempt` commands (orchestrator role); the user commands refuse a render-host actor (T-DB-57).

### 6.2 Protocol (default: through the gateway)

```
App                          Gateway Worker                         Postgres (app_gateway.*)          R2 (binding)
 │ POST /sources/{s}/uploads ─►│ verify actor; authorize_upload ──────►│ checks role/slot/state;          │
 │                             │                                      │ bytes+hash == declaration;       │
 │                             │                                      │ inserts session 'opening', key   │
 │                             │ createMultipartUpload(key) ───────────────────────────────────────────►│
 │                             │ attach_upload_id ────────────────────►│ session 'open'                   │
 │◄─ {sessionId, partSize=32 MiB, partCount, sessionCapability} ───────│                                  │
 │ PUT /uploads/{id}/parts/{n} ►│ fresh check (session open, actor still │                                  │
 │   (background URLSession)   │ authorized, n valid, length exact);   │                                  │
 │                             │ tee body → SHA-256 digest; uploadPart(n) ─────────────────────────────►│
 │                             │ record_part(n, bytes, etag, sha256) ─►│                                  │
 │◄─ {n, etag, sha256} ────────│                                      │                                  │
 │ … resume: GET /uploads/{id} returns confirmed parts                 │                                  │
 │ POST /uploads/{id}/complete►│ complete_upload_check ───────────────►│ section 6.3                      │
 │                             │ complete(parts from DB, not request) ─────────────────────────────────►│
 │                             │ head(key).size == expected ──────────────────────────────────────────►│
 │                             │ mark_uploaded_unverified ────────────►│ source 'uploaded_unverified'     │
 │◄─ {sourceState} ────────────│                                      │                                  │
                                 verify_sources stage (render host) reads all bytes, SHA-256 == declared,
                                 ffprobe allowlist → source 'verified' (or 'rejected' + object deleted)
```

OBSERVED basis: multipart through a Worker's R2 binding is a documented pattern
(https://developers.cloudflare.com/r2/api/workers/workers-multipart-usage/); part rules are 5 MiB–5 GiB, equal size
except the last, ≤ 10,000 parts (https://developers.cloudflare.com/r2/objects/multipart-objects/); the Worker request
body limit is 100 MB on Free/Pro zones (https://developers.cloudflare.com/workers/platform/limits/). 32 MiB parts give
108 parts for a 3.6 GB source. Re-uploading a part number replaces it and a failed re-upload loses the earlier part
(OBSERVED, https://developers.cloudflare.com/r2/api/s3/api/), so the client clears its "confirmed" mark before
retrying a part.

The part target is described by the server (`partTarget`), so moving to direct-to-R2 parts (presigned `UploadPart`,
**UNVERIFIED**, or temporary credentials scoped to the exact key and multipart actions, OBSERVED
https://developers.cloudflare.com/r2/api/s3/temporary-credentials/) is a server change only, after a spike (ticket
B-12). Gateway throughput on cellular is **UNVERIFIED**. The gateway never buffers a part: it streams the request body to
`uploadPart` through a hashing tee. The backend brief asks for media to go "directly in bounded multipart parts, not
through an in-memory Worker buffer"; routing parts through the Worker is a recorded deviation (ADR-0018,
studio-v1-spec "Conflicts recorded") that keeps one authorization point until the direct-to-R2 spike lands.

### 6.3 Completion validation against server-held expectations

`app_gateway.complete_upload_check(p_actor, p_session, p_parts)` refuses completion unless every check passes:

1. Session state `open`, `expires_at > now()`, and the actor is still authorized right now (owner still owns the
   project; guest invite not revoked and capability unexpired). Render outputs use
   `complete_upload_check_for_attempt`, whose step 1 is instead "attempt lease current" (orchestrator role only).
2. The source row belongs to the session's project, is not deleted, and its project is not deleted (rejects a session
   reused against another project or source: "wrong-project completion").
3. Part numbers are exactly `1..part_count` with no gaps; `part_count = ceil(expected_bytes / part_size)`; every part
   except the last has `bytes = part_size`; the last has `expected_bytes − (part_count − 1) × part_size`; the sum is
   `expected_bytes`.
4. The ETags used for `complete()` come from `upload_parts`, never from the request; the request's list must equal
   them (a mismatch means the client is confused or stale: `409 parts_mismatch`).
5. Every part's streamed SHA-256 matched the client's `X-Jovra-Part-Sha256` when received.
6. The session is the source's `current_session_id` and the source state is `uploading` (a stale or parallel session
   can never complete; each session writes its own key `…/original/<sessionId>`).
7. After `complete()`, `head(key).size == expected_bytes`; the etag is recorded.
8. The source becomes `uploaded_unverified`. R2 cannot attest a whole-object SHA-256 for multipart objects (OBSERVED:
   composite checksums only; full-object only CRC64NVME, https://developers.cloudflare.com/r2/objects/multipart-objects/),
   so the `verify_sources` stage reads the object, computes SHA-256 and compares it with `declared_sha256`, then
   probes it against an allowlist (MP4/MOV; H.264/HEVC; AAC or no audio; duration ≤ 4 h; ≤ 3840 px; rotation
   0/90/180/270). Only then `verified`, with `verified_etag` set to the etag it read under; every later read of the
   original (normalize, sync, render) uses `onlyIf: {etagMatches: verified_etag}`, so bytes that were never hashed or
   probed are never processed (T-R2-15). Mismatch ⇒ `rejected`, object deleted, reason recorded, local original
   untouched. This mirrors ADR-0008's "verified backup" rule.

Stale-session rules: a session expires 24 h after its last part and never later than 48 h after opening; a revoked
invite or membership stops the next part; opening a new session or a new declaration for the same source aborts the
open one in the same transaction (one open session per source, which also bounds storage per invite to one object); R2 lifecycle aborts incomplete uploads after 2 days as a
backstop (bucket default is 7 days, OBSERVED; a custom shorter rule is INFERRED).

## 7. Job flow

### 7.1 State machine

```
quote: open ──accept──► job: consented ──► upload_pending ──► uploading ──► queued
                    │expire                                              │ (all inputs verified)
               quote_expired                                             ▼
   normalizing ─► syncing ─► analyzing ─► planning ─► preview_rendering ─► awaiting_review ─► final_rendering
                                               (validate inside planning)        │revise (within cap)   │
                                                                                 └──► planning           ▼
                                                                                           verifying ─► ready
 any non-terminal ──cancel──► canceled          any non-terminal ──over cap──► budget_exceeded (resumable offer)
 any running ──pause──► paused ──resume──► (previous)   stage failure ──► failed_retryable ──retry──► (stage)
 failed_retryable ──retries exhausted / non-retryable──► failed_terminal       deletion ──► deleted
```

Rules (INFERRED, implementing the brief and the pricing guardrails):

- **`analyzing` is optional and non-blocking.** If no measured analysis capability exists, the stage records
  "manual review" and passes; playback never depends on it.
- **`planning` includes validation.** The planner returns a StoryPlan; deterministic code validates it (schema →
  semantics → profile grammar), compiles the EDL, validates the EDL (`tools/studio-plan` rules extended to
  `jovra.edit-plan/2`), and stores a `story_plan_versions` row. At most one repair attempt for a model plan, then fall
  back to the heuristic plan (film-engine decision). No render spend happens before a valid EDL exists.
- **`awaiting_review`** is entered automatically only when sync or observations are `needs_review` or the owner
  asked for review; the simple flow goes preview → final automatically after acceptance (brief). Waiting uses
  `step.waitForEvent` (default 24 h, up to 365 days, OBSERVED
  https://developers.cloudflare.com/workflows/build/events-and-parameters/); the job shows "Waiting for you".
- **A revision** that fits in the remaining reservation continues the same job; the same transaction moves the
  reservation's `story_plan_version_id` and `output_spec_sha256` to the new version, so the domain key follows the
  work (security-model §13.6). Otherwise `409 requote_required`: a new quote and job with `parent_job_id`.
- **A plan-by-job job's planning stage** does the same when it produces its version: the job and its held
  reservation, created under `(plan, NULL, hash of the unplanned output)`, move to `(plan, V, hash of V)` in the
  transaction that records the stage's success, so a later quote naming V with the same output meets the existing
  hold (`409` or a top-up), never a second hold and job (security-model §13.6, T-DB-68).
- **`ready`** only after the `verify_output` stage passes full decode, frame count against the EDL's rational clock,
  audio sample count, frame-map and provenance checks, and the artifact is atomically exposed (film-engine §3.10). A
  process exit is never `ready`.

### 7.2 Dispatch, outbox and idempotency

1. `app_gateway.accept_quote` runs one transaction: lock the quote; check state/expiry/inputs hash/cap; check the
   owner open-cap and environment ceilings; then either insert `usage_reservations` (unique held key
   `(project, story plan, story plan version, output spec hash)` (NULLS NOT DISTINCT)), `render_jobs` (state `consented`) and a `job_outbox` row
   `kind = 'start_workflow'`, or, when the quote supersedes the held reservation's quote after `budget_exceeded`, top
   that reservation up (raise `cap`, mark the old quote `superseded`) and move the existing job to `consented`; write
   `audit_events`.
2. The gateway then calls `INTERNAL.startJob(jobId)` over the service binding (it holds no Workflow binding); in
   `jovra-internal`, `startJob` re-reads the job row and outbox row as `jovra_orchestrator` and, only if the job is
   `consented` and the outbox row undispatched, calls `RENDER_JOB.createBatch([{id: jobId, params:{jobId}}])`;
   `createBatch()` skips existing ids while `create()` throws on a reused id (OBSERVED,
   https://developers.cloudflare.com/workflows/build/workers-api/), so a retry is harmless. On success it marks the
   outbox row dispatched.
3. The reconciler (Cron Trigger, every minute) re-dispatches any outbox row not marked dispatched after 60 s through the
   same idempotent call. Supabase Queues (pgmq) is the fallback if this dual-write proves fragile (OBSERVED option,
   https://supabase.com/docs/guides/queues).
4. Each Workflow step mirrors state into Postgres through `app_gateway.set_job_state(job, expected_state, new_state)`
   (compare-and-set against the transition table of `spec/studio/contracts/render-job-transitions.v1.json`, stored in
   SQL; `ready` requires a verified artifact; a stored `resume_stage` must be a stage the state can return to). It
   and every other orchestration function (`reserve_stage`, `claim_attempt`, `finish_attempt`,
   `mark_artifact_verified`) are executable only by the separate `jovra_orchestrator` role, whose binding exists only
   in the `jovra-internal` Worker (Workflow, consumer, internal routes), never by the `jovra_gateway` role that serves
   user routes in another script (security-model §3, §13.1).

### 7.3 Stages on the render host, leases and heartbeats

For each heavy stage the Workflow step:

1. Calls `app_gateway.reserve_stage(job, stage, attempt)` (orchestrator role only): locks the reservation; computes
   the stage estimate **in SQL** from `rates_version` and the stage inputs, with a per-stage floor (never a caller
   estimate); refuses with `budget_exceeded` if `reserved + estimate > cap` or the environment ceiling would be
   crossed; is idempotent on `(job, stage, attempt)`; computes `input_refs` and `output_plan` from the job's own
   project (verified source manifest, prior verified artifacts) and stores them on the new `render_attempts` row
   (state `reserved`, no lease yet); writes an outbox row `{attemptId}`.
2. Sends `{attemptId}` to Queue `render-work` (no media, no user text, no token, no input or output list). The message
   is a wake-up hint: a forged or replayed message can only name an attempt that already exists and is fenced.
3. The host calls `POST /internal/v1/attempts/{attemptId}/claim` with its host credential; `claim_attempt` mints the
   lease token, stores only its hash with `leased_until = now() + 5 min`, and returns the token with the stored
   `input_refs` and `output_plan`. A second claim is refused. The token therefore never sits in the outbox, a Queue
   or a DLQ (ADR-0018: queue messages carry ids only).
4. Waits with `step.waitForEvent('stage:<attemptId>', {timeout: stageMaxWall})`.

The consumer is idempotent on `attemptId`: a push consumer Worker starts or addresses a Container for the attempt and
returns (a 15-minute consumer cannot babysit a long render; OBSERVED consumer limits); an external host consumes by
HTTP pull with a visibility timeout (OBSERVED, https://developers.cloudflare.com/queues/configuration/pull-consumers/).

The host heartbeats every 60 s; `jovra-internal` extends `leased_until` only if the token matches the current attempt and
its state is `running`, and answers `{cancel: true}` when the job is canceling. Results come back through
`/internal/v1/attempts/{id}/result`; `jovra-internal` applies them with `app_gateway.finish_attempt`, which **fences**:
a result whose token is not the current attempt's, or arrives after `lease_expired`, is rejected and its outputs are
never registered. Outputs go to new keys derived from `(job, stage, inputHash, attempt)` and are registered as
`writing` until verified, so a zombie attempt cannot overwrite a good artifact.

Lease expiry: the reconciler marks attempts with `leased_until < now()` and state `running` as `lease_expired` and
sends the Workflow event `stage:<attemptId>` with `{outcome: "lease_expired"}`. The Workflow then retries or fails.

Containers can be stopped with SIGTERM and up to 15 minutes' grace on rollout or inactivity (OBSERVED,
https://developers.cloudflare.com/containers/platform-details/architecture/), so every stage is restartable from its
inputs and the previous stage's verified outputs; a 20 GB disk cannot hold six 3.6 GB originals plus outputs, so
normalization runs per source and assembly reads only keeper windows by Range (INFERRED).

### 7.4 Retries and dead letters

| Failure | Classification | Action |
|---|---|---|
| Host crash, lease expiry, transient R2/network error | retryable | new attempt after backoff 30 s → 2 min → 8 min; max 3 attempts per stage (planner: 1 repair + heuristic fallback) |
| Out of memory/disk at the planned size | retryable once | same size; no automatic larger instance (that would be spend escalation) |
| Source hash mismatch, probe rejected, EDL invalid, verification failed twice | terminal for that stage | `failed_terminal` with evidence kept; reservation for unrun stages released |
| Budget check refused | `budget_exceeded` | offer a new quote; never raise the cap |
| Queue retries exhausted (consumer could not dispatch) | dead letter | DLQ consumer marks the attempt `dead_lettered`, the job `failed_retryable` with `dispatch_failed`, and raises an alert; no automatic replay; an operator replays with the same attempt id |

Queues deliver at least once, retry 3 times by default, and delete exhausted messages permanently unless a DLQ is
configured (OBSERVED, https://developers.cloudflare.com/queues/configuration/dead-letter-queues/), so the DLQ is
mandatory. Every retry passes through `reserve_stage`, so retries cannot exceed the cap. Credits are consumed when a
stage attempt **succeeds** (`finish_attempt`), once per `(job, stage)`: a failed attempt consumes no credits (its real
cost is still recorded in `actual_cost_micro_usd`, bounded by the internal cap, the environment ceiling and
`maxAttempts`; for the planner this bound holds because its `max_tokens`, image count, effort and repair call are
derived from the stage reservation before the call and an overrun is committed against the ceiling, §7.6), and a
later attempt of an already-charged stage is a replay (contract vector
`retry-not-charged-twice`). The pricing research's 10–50% retry overhead is therefore operator cost inside the
internal cap, never a second user charge.

### 7.5 Cancellation and cleanup

- `POST /jobs/{id}/cancel` sets `cancel_requested_at`; the Workflow checks it before every step; the next heartbeat
  answers `cancel: true`; after a grace of 2 minutes the Workflow calls `terminate()` (OBSERVED API).
- Settlement: consumed cost of finished attempts plus the measured part of the running attempt is recorded; the rest
  of the reservation is released; the receipt separates estimate, cap, actual and released.
- Cleanup stage (also run on failure and deletion): delete the job's `proxies/`, `frames/`, `previews/` objects and
  `writing`/`failed` artifacts; keep staged sources until their retention date unless the owner chooses "delete
  uploaded sources now"; never touch local originals; keep the job row, attempts and receipt.
- Daily reconciler sweep: abort expired upload sessions; diff **every prefix in both buckets** (`staging/`,
  `proxies/`, `frames/`, `previews/`, `films/`) against `camera_sources`, `artifacts` (every state, including
  `writing`) and non-terminal `app_ops.upload_sessions`, and delete only objects older than 48 h (the longest session
  lifetime) with no row (security-model §13.12; T-R2-17) (this catches cascaded `clip_excerpt` and thumbnail rows and a dashboard delete of `auth.users`); mark artifact
  rows whose object is missing (`object-delete` events, OBSERVED
  https://developers.cloudflare.com/r2/buckets/event-notifications/, are the fast path).

### 7.6 Planner adapter

- Evidence is gathered under an explicit actor check that repeats `check_story_plan_lessons`: the planner reads, with
  server rights, only the job project's verified source manifest, its keepers, and lessons whose owner is the project
  owner and that the requester can access as owner or coach (a viewer grant never feeds a plan). Note text is
  included only in the classes named in `quotes.consent.textClasses`; coach-authored text is excluded unless named
  (security-model §13.14).
- Interface: `plan(input: PlannerInput) -> PlannerResult`, where `PlannerInput` holds only IDs, the profile grammar,
  structured events from the bound event revision, keeper/B-roll catalogs, consented note text, and sampled frames as
  bytes (contact sheets from proxies, sized per film-engine §4). Never R2 keys, URLs, emails or secrets.
- Providers: `heuristic` (default; deterministic; no network), `anthropic` (model id pinned in config, currently
  `claude-opus-5-5`, image input only, no video; OBSERVED https://platform.claude.com/docs/en/build-with-claude/vision),
  `openai-astra` (**ships disabled with no model ID configured**: the research names `gpt-6-astra`, but account access,
  structured-output limits and image pricing are **UNVERIFIED**; the adapter returns `unavailable: model not
  configured` until the founder configures a real model ID that its capability probe accepts; spec D-5, SD18,
  ADR-0016). No model becomes the default planner by configuration alone (spec story 248).
  The adapter version and model id are pinned on the plan version and never changed mid-job.
- Model use requires the owner's `consent.modelProvider = true` at quote acceptance; without it the heuristic planner
  runs.
- **Spend bound.** The planner step never chooses its own budget. It reads `render_attempts.planner_budget`, written by
  `reserve_stage` from the stage's reservation, and passes those numbers as the provider's `max_tokens`, image count
  and effort. Before the call it checks that the request's worst case (input tokens counted from the built request,
  plus `max_tokens`) fits the reservation, else it makes no call and the heuristic planner runs. The one repair call
  is made only when the reservation still covers its worst case. Measured tokens go into `measurements` and
  `actual_cost_micro_usd` at `finish_attempt`; an overrun is committed as `stage_overrun` (security-model §13.7,
  T-DB-72, and the planner fixture test in §12). Sending frames to a provider changes App Privacy answers (ADR-0013 targets "Data Not Collected"); the
  privacy-label update is an activation gate (G7).
- The API key is a Worker secret available only to the Workflow's planner step. Model output is data: the validator
  rejects shell strings, filter strings, URLs, unknown operations, out-of-window cuts and invented numbers.

## 8. Normalization and render outputs (summary)

The render host follows `docs/research/studio/multicam-sync.md` §5 and `film-engine.md` §3: analysis proxies keep
original timestamps; render proxies are constant-frame-rate, rotation-baked, SDR, zero-start with an explicit hashed
original-PTS ↔ proxy-frame table; FFmpeg arguments are built from per-operation templates filled with validated
numbers and passed as files; the FFmpeg build is pinned and probed at start-up (the local 9.0.1 lacks `drawtext` and
`zscale`, OBSERVED in the film-engine research). Remotion overlays wait for the licence decision (Q1). The founder's
editor at `/Users/IDC2.5/Desktop/you-link-x/garnet-remotion` is not modified; a JOVRA adapter would sit in front of
its strict assembler after normalization.

## 9. Delivery

### 9.1 Private playback and download

`GET /v1/artifacts/{id}/content`: the gateway calls `app_gateway.authorize_artifact_read(actor, artifact)` which
allows owner and coach of the project for `preview`, `film`, `thumbnail`, `captions`, `chapters`, `edit_manifest`,
`clip_excerpt`, the owner only for `project_bundle` (films plus EDL, chapters, captions and edit manifest; never
originals, proxies, frames or PTS tables), and a viewer only for artifacts covered by an active, unexpired, unrevoked
`film_view`, `lesson_view` or `lesson_clip_view` grant (a film's children inherit its grant). Sources, proxies, frames
and PTS tables are never readable by clients. The artifact must be `ready` and not `deleted`. The gateway then streams
from the R2 binding with Range support (AVPlayer seeks with ranges), `Cache-Control: private, no-store`,
`X-Content-Type-Options: nosniff`, `Content-Security-Policy: sandbox`, and a server-generated `Content-Disposition`
filename (`JOVRA-<profile>-<yyyy-mm-dd>.mp4`; user text never goes in a header).
Revocation is immediate because no bearer URL leaves the gateway. Where offloading matters later, the gateway may
redirect to a presigned GET of ≤ 5 minutes after the spike; such a URL cannot be revoked before expiry (OBSERVED), so
the UI never promises instant revocation for it; such a URL signs `response-cache-control`,
`response-content-disposition` and `response-content-type` overrides so the headers above still apply (T-R2-13). R2 egress is free; Workers bill requests and CPU, not bandwidth
(OBSERVED, https://developers.cloudflare.com/workers/platform/pricing/).

Stale versions: when a correction creates a new event revision, existing films stay downloadable and are labelled
"Older version: points corrected since"; new films bind the new revision.

**Audio variants of downloads and links (spec D-1, SD5).** Private
playback streams the film with its court audio. Every file that leaves the app is chosen with or without audio when
the download, share link or YouTube package is created (`includeAudio`, default from the profile's contract field
`exportAudio.includeByDefault`; junior-mode projects are always without audio). A without-audio file is never the
film with a muted player: it is a separate verified artifact of the same plan (`kind = 'film'`, `media.audioCodec
= null`, `parent_artifact_id` = the film), made by a `remux_no_audio` step (stream copy of the video, no audio track;
no re-encode) and passed through `verify_output` (same frame count and video hash as the parent, no audio track).
`create_share_link` and `/content` name the artifact actually served, so a link created without audio can never
serve the audio variant. The child is created once per film on first request (idempotent on `(parent_artifact_id,
'no-audio')`), counted as a delivery step inside the job's existing reservation (a stream copy costs seconds), and
deleted with its film. "Prepare for YouTube" packages whichever variant the player chose. Tests: T-GW-38 (a link
created with `includeAudio: false` serves a file with no audio track and the parent's frame count and video hash, and
can never serve the parent; junior mode refuses `includeAudio: true` with 422).

### 9.2 24-hour share links

- Created only by the owner, for one `film`, `preview` or `clip_excerpt` (never a source or proxy, never a whole
  project), `expires_at ≤ now() + 24 h`.
- The URL is `<gateway-origin>/s/<token>`; the token is 32 random bytes, base64url; only its SHA-256 is stored.
- Each request re-checks: token hash exists, not revoked, not expired, artifact `ready`, project not deleted. Then it
  streams like 9.1. Revoking the link stops the next request.
- Exactly two resources exist under a token: `/s/<token>` (the linked artifact) and `/s/<token>/thumbnail` (the
  artifact whose `parent_artifact_id` is the linked one and whose kind is `thumbnail`). Any other id is `404`.
- `redeem_share_link(p_token_hash)` only authorizes the current request. It never writes a grant, never sets
  `grantee_user_id` and never creates a `film_view`, so a signed-in holder gains nothing beyond the link's 24 h.
- Responses under `/s/` carry `Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff` and
  `Content-Security-Policy: sandbox`; invocation logs are off (§5) and zone Logpush / WAF logging exclude `/s/*` (G2),
  so the token is not leaked through referrers or platform logs. `/s/` is rate-limited per token hash with a byte
  budget (§5).
- The link is not a web page with analytics; a native or browser player just receives the MP4. No indexing headers
  (`X-Robots-Tag: noindex`). Opening it does not create an account.

### 9.3 "Prepare for YouTube"

Produces the file, cover, chapters and editable title/description as private artifacts (or locally for on-device
films). No upload, no channel connection and no OAuth exist in this design; a real YouTube upload is a later,
user-initiated, verified integration (brief).

## 10. Retention and deletion

| Class | Where | Default retention | Mechanism |
|---|---|---|---|
| Staged originals | `jovra-<env>-work/staging/` | **7 days by default; 1 or 30 days by the player's choice at preflight** (the accepted quote's `retentionDays`, spec D-3/SD23) | per job: `camera_sources.retention_until` and each work artifact's `retention_until` are set from the accepted quote; the daily `jovra-internal` retention sweep deletes objects past that date (objects first, then the row state); a **31-day** prefix lifecycle rule is only the backstop for a missed sweep (it must outlive the longest choice; R2 lifecycle acts within ~24 h, OBSERVED https://developers.cloudflare.com/r2/buckets/object-lifecycles/), so copy says "removed within about a day after the N days you chose" |
| Incomplete multipart uploads | work bucket | abort after 2 days | lifecycle abort rule + session expiry |
| Proxies, frames, PTS tables, contact sheets | `work/proxies/`, `work/frames/` | the job's chosen retention (1, 7 or 30 days) | `retention_until` + daily sweep; job cleanup; 31-day lifecycle backstop |
| Previews | `work/previews/` | the job's chosen retention after the job ends | `retention_until` + daily sweep; 31-day lifecycle backstop |
| Films and their thumbnails/captions/chapters/manifests | `jovra-<env>-films` | user's explicit choice: "until I delete" (default), 30 or 90 days | no lifecycle rule on this bucket; the deletion job executes `retention_until` |
| Metadata rows | Postgres | until the user deletes the project or account | deletion job |
| Audit events | `app_ops.audit_events` | 400 days, then purged | cron |
| Idempotency records | `app_ops` | 7 days | cron; bodies of secret-minting routes are stored redacted |
| Workflow instance state (step outputs, which may include planner story text) | Cloudflare Workflows | retention **UNVERIFIED**; listed at G2 | step outputs hold ids and hashes only where possible; the deletion Workflow deletes the project's job instances on project and account deletion |
| Platform logs (Workers Logs, Supabase Postgres/API logs) | vendors | Workers Logs: 7 days on paid plans, 3 on free (OBSERVED, https://developers.cloudflare.com/workers/observability/logs/workers-logs/); Supabase log retention **UNVERIFIED** | invocation logs off; coded errors before constraints (no row values in DETAIL); retention listed at G2 |
| Database backups | Supabase | per plan (duration **UNVERIFIED**; refresh at activation) | deleted rows persist in backups until rotation; deletion copy says so |

Infrequent Access storage is never used for short-lived media (30-day minimum charge, OBSERVED
https://developers.cloudflare.com/r2/pricing/).

**Deletion flow** (`deletion_requests`, executed by a Workflow so it survives failures):
1. `requested` → mark targets `deleted_at` (policies hide them immediately) → `canceling_jobs` (cancel every
   non-terminal job; settle reservations; **abort every open upload session** of the target, R2 first; the part route
   refuses projects with `deleted_at`) → `deleting_objects` (explicit R2 deletes for every object derived from the
   target, enumerated through rows, not only by prefix: children by `parent_artifact_id` before the cascade, films and
   excerpts by `artifact_sources` for a source, the user's lessons' clip excerpts under other owners' prefixes for an
   account; listing by prefix as a backstop) → `deleting_rows` (cascade) → for account scope `revoking_apple` (Apple
   REST revoke with the server-held key, then delete the Vault-held refresh token, then delete the auth user) →
   `done` (security-model §13.9).
2. A failure leaves the request `failed` with a code and is retried by the reconciler; the UI shows "Deletion running"
   or "Deletion failed, retrying".
3. Cloud deletion never deletes local originals, local project JSON or local films. Deleting local data is a separate
   action in the app.
4. Audit tombstones keep ids, counts and outcome only.
5. Account scope: rows the user owns go (projects cascade); rows they authored in other owners' projects stay with
   those projects with actor columns set null (§4.1, ADR-0022 amendment). Lesson scope removes the lesson's clip
   excerpts and thumbnails (objects first), its clips, its lesson-only observations and their embeddings, removes the
   lesson id from `story_plans.lesson_ids`, invalidates plan versions that used it, deletes films rendered from them
   and deletes those jobs' Workflow instances. `lesson_clip` scope removes one clip and its excerpt.
6. Source scope: `lesson_clips` and `observations` keep their rows with `source_id` set null (`on delete set null
   (source_id)`, so the request never stalls on them); every artifact listed in `artifact_sources` for the source,
   and its share links, is deleted after the owner confirmed the list (`409 dependents`), so a guest angle withdrawn
   for consent leaves no published film.

## 11. App-side sync model

### 11.1 Principles

- **Local JSON stays the source of truth** (ADR-0002). The cloud holds a copy of selected metadata for selected
  projects, plus media the user explicitly uploads for a job. Losing the cloud loses no local data.
- **Linking is opt-in per project.** Signing in links nothing by itself.
- **Media never syncs automatically.** Uploads happen per source, per job, after consent at preflight. Archive
  providers (Files/iCloud Drive, Google Drive, Box, Dropbox) are separate operations with separate credentials;
  archive permission is not processing consent.

### 11.2 App interfaces

```
protocol StudioBackend {            // one protocol, three adapters
  var environment: StudioEnvironment { get }          // .demo | .test | .live (from build config)
  var identity: StudioIdentity { get }                // DemoIdentity (no token) | SupabaseIdentity
  var metadata: StudioMetadataStore { get }           // link/push/pull, revisions, conflicts
  var media: StudioMediaUploader { get }              // declare, sessions, parts, resume, completion
  var jobs: StudioJobService { get }                  // quote, accept, status, cancel, review
  var delivery: StudioDeliveryService { get }         // stream, download, share links
}
```

`DemoBackend` implements every call in process from fictional fixtures (`sample = true`), never opens a socket, and
returns "Sample quote" with no reservation. The Android port implements the same contract in Kotlin against the same
gateway JSON Schemas (`backend/contracts/`), sharing schemas and fixtures, not code (ADR-0001).

### 11.3 Linking a local project

1. The user signs in (real Supabase session; the UI distinguishes it from the demo profile) and picks local projects
   to link.
2. For each, the app inserts `projects` with `local_project_id` and receives the server id; it then pushes the
   current event log as `point_event_revisions` revision 1 (parent null), and any lessons/clips the user selected.
3. The local project document gains a `cloudLink` block: `{environment, issuer, projectId, ownerUserId, linkedAt,
   baseRevisions: {events, syncMap, calibration, lessons:{id: rev}, …}, idMap: {localId: cloudId}}`. This is the
   reviewed local-to-cloud ID migration record; local IDs never change.
4. Unlinking removes `cloudLink` locally and offers (separately) to request cloud deletion.

The `cloudLink` block belongs to a Studio project document, not to the core `session.json` schema; adding it to a
core schema would be a spec change for the other workflow and is not proposed here.

### 11.4 Push, pull and revisions

- **Mutable records** (projects, lessons, lesson clips, observations, story plans, provider status) carry `revision`.
  Push is a conditional update: `PATCH … ?id=eq.X&revision=eq.<base>` with `Prefer: return=representation`. One row
  back ⇒ success, store the new revision as base. Zero rows ⇒ **conflict**.
- **Append-only records** (event revisions, sync maps, calibrations, plan versions) push with `parent_revision =
  base`. The `check_event_parent` trigger rejects a stale parent with `revision_conflict`.
- **Pull** fetches rows with `updated_at > cursor` (and new revisions) for linked projects. A pulled change applies
  automatically only when the local record has no unpushed edits; otherwise it is a conflict.
- **Conflicts never overwrite silently.** Both versions are kept: the local one stays active and marked
  "Changed on this phone and in the cloud", the cloud one is stored beside it, and the user picks one or keeps both
  (for an event log, keeping both creates a new local session copy). Resolution pushes a new revision whose parent is
  the current cloud revision. No automatic merge of event logs in v1 (INFERRED: a wrong merge would silently change
  scores, which ADR-0003 forbids).
- **Corrections propagate**: a new event revision marks older films and plan versions stale on the server (trigger)
  and locally; nothing re-renders without a new consent.

### 11.5 Sign-out, offline and environment changes

- Sign-out deletes tokens from the Keychain and keeps every local document, original, local film and downloaded
  cloud film. Linked projects show "Signed out: cloud copy not updating". Cloud-only artifacts that were never
  downloaded show "Sign in to watch"; the app offers to download films before signing out.
- Offline: the app queues pushes in the project folder (atomic write-temp-then-rename, ADR-0002) and replays them in
  order with the same idempotency keys when the network returns.
- A project linked in **test** cannot push to **live** (issuer mismatch); switching environments requires an explicit
  relink, which creates a new cloud project and leaves the old link's record in history.
- Account deletion removes `cloudLink` from every local document after the server confirms `done`.

## 12. Local test strategy (no provisioning)

Tools on this machine (OBSERVED in the research doc): Supabase CLI 2.100.1, Docker 29.4.1, Node 26.8.2, Deno 2.9.6,
FFmpeg/ffprobe 9.0.1. Wrangler is not installed globally; it becomes a gateway devDependency.

| Layer | Harness | Required checks (each must be able to fail) |
|---|---|---|
| Schema, RLS, helpers | `supabase start` → `supabase db reset` → `supabase test db` (pgTAP in `backend/supabase/tests/database/`, basejump-style helpers to create users and authenticate as them; OBSERVED https://supabase.com/docs/guides/local-development/testing/overview) | The full allow/deny list in security-model §6 for owner, coach, viewer, camera (signed-in), unrelated user, anonymous-authenticated and unauthenticated; append-only tables reject UPDATE/DELETE; `owner_id` immutable; revision conflicts raise `P0409`; stale-marking trigger |
| Security lints | `supabase db advisors --local --type security --fail-on warn` (OBSERVED flag set) plus a repo lint that fails on any function with a mutable or `public` search path, any `security definer` function in `public`, any table in `public` without RLS | Zero warnings |
| Command functions | pgTAP calling `app_gateway.*` as `jovra_gateway` with forged `p_actor` values | Every command re-checks the actor; `authenticated` cannot EXECUTE them |
| Auth flows | Local Auth + Mailpit (`127.0.0.1:54324`) for OTP; local ES256 signing key (`supabase gen signing-key --algorithm ES256`, `signing_keys_path`) | OTP allow-list rejects unknown emails; gateway verifies local JWKS |
| Gateway Worker | `@cloudflare/vitest-plugin` (Miniflare; renamed from `vitest-pool-workers`, OBSERVED https://developers.cloudflare.com/workers/testing/vitest-integration/), R2 binding simulated, Queue and Workflow test APIs (`mockStepError`, `forceStepTimeout`, `mockEvent`), Hyperdrive `localConnectionString` to the local stack's Postgres | Section 12.1 list |
| Render host | Same Docker image locally; storage adapter pointed at a local directory or the Miniflare R2; ADR-0012 synthetic sample video and the barcode/click conformance fixtures (film-engine §6, multicam-sync §8) | Hash mismatch rejects; probe allowlist rejects oversize/rotated-odd/HDR-without-tonemap inputs; normalization PTS table matches embedded frame ids; SIGTERM mid-stage restarts cleanly; outputs keyed by input hash; FFmpeg args built only from templates (adversarial EDL fixtures fail) |
| Planner | Recorded fixture responses only; no API calls | Shell strings, unknown ops, URLs, out-of-window cuts and invented metric numbers are rejected; heuristic fallback after one failed repair; a fixture whose worst case (images, input, `max_tokens`, repair) exceeds the stage reservation is refused before any provider call (the fake provider records zero requests) and the request carries exactly `planner_budget` (T-DB-72) |
| Native client | `URLProtocol` stub of the gateway (ADR-0008 pattern); DemoBackend unit tests | Resume after kill; part retry clears confirmation; conflict UI paths; sign-out keeps offline playback; demo never opens a socket |

### 12.1 Gateway tests (minimum list)

T-GW-01 expired JWT → 401. T-GW-02 JWT from another issuer (test token on live config) → 401. T-GW-03 demo marker or
unsigned token → 401 `demo_not_accepted`. T-GW-04 HS256 token → 401 (alg pinned). T-GW-05 anonymous JWT on an owner
route → 403. T-GW-06 unrelated user opens upload session on another project's source → 404. T-GW-07 revoked invite:
next part → 403, session unusable. T-GW-08 part with wrong length → 400; with wrong digest → 400 and part not
confirmed. T-GW-09 completion with a missing part → 409; with a session from another project's source → 404;
completion twice → same response. T-GW-10 duplicate `quote.accept` with the same key → one job, one reservation;
same key different body → 422. T-GW-11 accept after quote expiry → 409 `quote_expired`; with a changed inputs hash →
409. T-GW-12 retry storms never push `reserved` over the cap (property test). T-GW-13 stale lease token result → 409
and outputs not registered. T-GW-14 cancel during a running stage → heartbeat answers `cancel`, reservation settled,
cleanup enqueued. T-GW-15 share link after revoke → 404; after 24 h → 404; share link for a source or proxy cannot be
created. T-GW-16 viewer with a lesson-clip grant can stream that clip excerpt and gets 404 for the match film and every
other artifact. T-GW-17 outbox re-dispatch after a simulated crash creates exactly one Workflow instance. T-GW-18 DLQ
message marks the attempt `dead_lettered` and the job `failed_retryable`. T-GW-19 logs captured during the whole
suite contain no JWT, capability, share token, invite code, email or display name (log-scrubber assertion), and every
refusal the suite provokes on a user route **and on a `jovra-internal` host route** has its `app_ops.audit_events`
denial row (`audit_denial` / `audit_denial_for_attempt`).
T-GW-20 deletion request removes every object under the project's prefixes in the simulated buckets and leaves no
artifact rows. T-GW-20b deleting the account of a coach who authored observations, plans and sync reviews in another
owner's project finishes `done`; those rows remain with actor columns null. T-GW-21 with the Hyperdrive local
binding, revoke a share link (and a coach grant) and request again within 60 s → 404. T-GW-22 replaying a
secret-minting request (invite, guest capability, session, share link, grant) → `409 secret_not_replayable`; no
`jv[igslhc]_` value in `app_ops`. T-GW-23 replayed guest request signature (same nonce) → 401. T-GW-24 a quote or
EDL naming another project's source → 404 / `untrustedSource`. T-GW-25 two concurrent upload sessions for one
source: the first is aborted and cannot complete; completing the current one after verification of an earlier object
is refused. T-GW-26 coach `GET /jobs/{id}` has no `usage`. T-GW-27 `/s/{token}/thumbnail` streams only the linked
film's thumbnail; a signed-in holder has no grant afterwards. T-GW-28 a second `claim` of an attempt → 409; a queue
message naming another project's input → that input is never readable (also T-R2-08b); each such refusal, a forged or
stale lease token and an output over its cap leave one `audit_events` row with `actor_kind = 'render_attempt'`
written by `audit_denial_for_attempt`. Review round 2 (security-model
§13): T-GW-29 the user gateway's Wrangler config has no orchestrator Hyperdrive binding, no host secret and no
`/internal/` route, and its service binding exposes only `startJob`/`notifyReview`; T-GW-30 an OTP request with
`create_user: true` for an unknown email is refused (local `enable_signup = false` plus the hook; hosted at G1);
T-GW-31 account deletion with a freshly refreshed token whose Auth session is old → 401 `reauth_required`, and a new
sign-in then passes; T-GW-32
each deletion gap (source with dependent films, lesson in a Progress plan, including one lesson of a two-lesson
Progress plan, which must reach `done` on the server path, coach account with excerpts in another owner's project, an
open multipart session, a film's thumbnail/captions/chapters) leaves no object behind; T-GW-33 a
stranger redeeming a forwarded invitation → 404; T-GW-34 `/s/` beyond its rate limit or byte budget → 429; T-GW-35
the app's PostgREST request builder never puts user text in a query string; T-GW-36 a render output declared above its
kind's cap → 422; T-GW-37 a sixth failed grant redemption within an hour by one user → 429, and a correct code after
that still 429 until the window passes. T-GW-38 audio variants (§9.1): a share link or download chosen without audio
serves the verified no-audio child (no audio track, same frame count and video hash as the film) and never the film;
junior mode refuses `includeAudio: true` (422).

### 12.2 What stays UNVERIFIED until activation

Hosted JWKS caching, Hyperdrive in front of Supabase with a custom login role and caching disabled (Q5), Workflows
instance-state retention and platform log retention (Supabase), gateway upload throughput on
cellular and Wi-Fi (Q3), presigned `UploadPart` (Q3), real lifecycle timing, Container runtimes per stage (Q4),
Realtime presence accounting (Q6), SIWA end to end and Apple token revocation (Q2), custom SMTP deliverability (Q8),
live model behaviour and spend, push notifications. Each is reported separately from local success.

## 13. Activation gates (each needs Jon's action and captured evidence)

| Gate | What | Evidence before "live" |
|---|---|---|
| G0 | ADR accepting the backend-ready scope change (B-00) | ADR merged |
| G1 | Test Supabase project created by Jon; publishable key and URL in test config | pgTAP suite and advisors pass against the hosted test project; sign-ups disabled and the `before_user_created` allow-list hook active (an OTP with `create_user: true` for an unknown email is refused, T-GW-30); the `session_id` claim, `auth.sessions` columns and `amr` shape recorded for re-authentication (T-GW-31) |
| G2 | Cloudflare account, test Worker env, R2 buckets, Queues, Workflow | Gateway suite passes against hosted bindings; lifecycle rules listed; Hyperdrive config shows caching disabled; `invocation_logs = false`; zone Logpush and WAF/Security Events logging off for the gateway hostname or excluding `/s/*`; two Worker scripts with the orchestrator binding only on `jovra-internal` (T-GW-29); Workflows and platform log retention recorded; test environment ceiling and default owner row (`app_ops.spend_limits`) set by Jon |
| G3 | Render host (Containers test instance) | Synthetic fixture film fully verified in the cloud; measured runtime per stage |
| G3b | Remote push (APNs key, later FCM) for "film ready" on cloud jobs | Device receives a push from the test environment; until then cloud jobs show status only in the app (local notifications for on-device films need no gate) |
| G4 | Sign in with Apple capability and Apple revoke key | Device sign-in and an account-deletion revoke captured |
| G5 | Custom SMTP sender under IDC Rule 07 | OTP delivered from the role address; MX custody untouched |
| G6 | Model provider key (test cap set by Jon) | Recorded plan cost per film against the pricing research's benchmark list |
| G7 | App Privacy answers and consent copy for cloud processing and model providers | Updated privacy label draft reviewed by Jon |
| G8 | Paid-cloud ADR and pricing (later) | ADR merged; benchmarks from pricing research §8 |
| G9 | Live environment | Separate projects/buckets; security checklist re-run; Jon's go |

## 14. Open questions

Q1 Remotion licence (IDC headcount incl. contractors, or $100/month Automators). Q2 Apple token revocation on
deletion: Supabase or gateway, which key, where stored. Q3 presigned `UploadPart` and gateway throughput.
Q4 per-stage runtime at 4 vCPU / 12 GiB; is Cloud Run or a GPU needed. Q5 Hyperdrive with a custom login role
(pooling mode, limits, caching disabled). A PostgREST fallback is **not** pre-approved: it would need an exposed schema
and the secret key, so it requires its own ADR-0018 amendment (security-model §3: a dedicated exposed `app_rpc`
schema of thin wrappers, EXECUTE for `service_role` only, the key held by a separate internal Worker that is not on
the user route, T-DB-03/T-DB-35 updated). Q6 Realtime presence counting. Q7 gateway hostname under the IDC domain doctrine.
Q8 auth email sender and SMTP without disturbing `islanddevcrew.com` MX custody. Q9 "Astra" API access, image limits
and pricing for Jon's account. Q10 backup retention on the chosen Supabase plan and how deletion copy states it. Q11 age requirements for cloud
accounts and for uploading footage of minors (juniors are common in tennis); needs Jon's decision and legal review.
Q12 invitations bound to an email (security-model §13.2): a coach who signs in with Sign in with Apple and hides their
email has a private-relay address the owner cannot know; confirm that "sign in with the invited email by code" is
acceptable for coaches (identity linking UNVERIFIED).

## 15. Recommended backend tickets

Every ticket is local-only until its gate; "done" means the listed checks ran and could have failed (CLAUDE.md
rule 9). Hosted verification is reported separately at activation.

| ID | Ticket | Depends on | Acceptance evidence |
|---|---|---|---|
| B-00 | ADR: backend-ready v1 scope change (supersedes the "no backend" line of ADR-0002 for Studio only; restates local-first and ADR-0013; lists gates G1–G9) | — | ADR merged |
| B-01 | Studio contracts: JSON Schemas for gateway requests/responses, queue messages, SourceManifest, SyncMap, StoryPlan, `jovra.edit-plan/2` refs, with fixtures (no core `spec/` edits) | B-00 | Schema validation tests with failing fixtures |
| B-02 | `backend/supabase` scaffold: config with ES256 signing key path, anonymous off, Mailpit OTP, fictional seed testers at `example.test`; `.dev.vars` added to `.gitignore` | B-00 | `supabase start`, `db reset` clean |
| B-03 | Migration 1: schemas, roles, enums, identity/membership/project tables, helpers, triggers, RLS (§5.1–5.2) | B-02 | T-DB-01..11, 28–33, 35; advisors clean |
| B-04 | Migration 2: sources, manifests, sync, calibration, event revisions, observations, lessons, clips, story plans + RLS | B-03 | T-DB-12..24, 41–43 |
| B-05 | Migration 3: quotes, reservations, jobs, attempts, artifacts, grants, providers, deletion, `app_ops` tables + RLS | B-04 | T-DB-25..27, 29, 34, 36–38 |
| B-06 | `app_gateway` command functions with actor re-checks and `audit_denial` | B-05 | T-DB-33..39 |
| B-07 | Gateway Worker scaffold: JWKS verification, envelope, idempotency store, allowlisted logger | B-01, B-06 | T-GW-01..05, 19 |
| B-08 | Camera invites and guest capabilities (redeem, approve, device-key proof) | B-07 | T-DB-39, T-R2-01/02 |
| B-09 | Upload sessions through the gateway (32 MiB parts, per-part digest, completion checks, abort, expiry) | B-07 | T-GW-06..09, T-R2-10 |
| B-10 | Quote, consent, reservation, job creation with outbox and idempotent Workflow start (Sample amounts only) | B-07 | T-GW-10..12, 17 |
| B-11 | Workflow `RenderJob` + Queue + DLQ + reconciler (leases, heartbeats, fencing, cancel, cleanup) with a fake render host | B-10 | T-GW-13, 14, 18 |
| B-12 | Spike (test bucket, needs G2): presigned `UploadPart`, temporary credentials, gateway throughput on cellular/Wi-Fi | G2 | Measured report; decision recorded |
| B-13 | Render host image: pinned FFmpeg, probe allowlist, full-file SHA-256 verify, per-source normalization with PTS table, metadata stripping, SIGTERM-safe stages, local storage adapter | B-01 | Synthetic + malformed media tests; I9 fixture |
| B-14 | Render host assembly + `verify_output` (full decode, frame count, audio, provenance) from a validated EDL; conformance fixtures shared with the iOS renderer | B-13, film-engine contract ticket | Barcode/click fixture passes frame for frame |
| B-15 | Planner adapter: heuristic default; provider interface; recorded-fixture tests; adversarial plans rejected; consent gate | B-01, B-11 | Planner adversarial suite |
| B-16 | Delivery: Range streaming, share links (≤ 24 h), grants, stale labelling | B-11 | T-GW-15, 16; T-R2-04..07, 14 |
| B-17 | Deletion Workflow (project, source, artifact, lesson, account; Apple revoke behind G4) and retention sweeps | B-16 | T-GW-20, T-R2-12 |
| B-18 | iOS `StudioBackend` protocol + `DemoBackend` (no socket) + `RemoteBackend` with `URLProtocol`-stubbed gateway; background upload with resume | B-01 | Unit tests; demo opens no socket |
| B-19 | iOS project linking and metadata sync (conditional updates, append-only revisions, conflict UI, sign-out keeps offline access) | B-18, B-04 | Conflict and sign-out tests against the local stack |
| B-20 | Optional lesson search: full-text first; pgvector table + permissioned retrieval behind a measured-need decision | B-04 | T-DB-40 |
| B-21 | Activation runbook (G1–G9) for Jon: what to create, which secrets go where, which hosted checks to run; no agent provisions anything | B-11 | Runbook reviewed by Jon |
| B-22 | Privacy: App Privacy answers, consent copy (cloud, model provider, retention), participant acknowledgement, minors question | B-00 | Draft reviewed by Jon (G7) |
| B-23 | Review-round-1 hardening (D1–D24): Hyperdrive caching off, invocation logs off, redacted idempotency, claim-minted leases, attempt input/output lists, composite source FKs, clip share approval, actor `set null`, lesson deletion routing, one upload session per source with etag pinning, spend ceilings and SQL estimates, orchestrator role, coach approval, length triggers | B-03…B-11 | T-DB-45…56, T-GW-20b…28, T-R2-08b, T-R2-15 |
| B-24 | JOVRA editor adapter (spec SD22): `jovra.edit-plan/2` → `production-lab.video-editor.v1`, `idc.production-handoff/1`, `production-lab.editor-plan.v1`, `production-lab.editor-media-map.v1`, silent segment audio plus a verified JOVRA bed; run only on a copy of the editor | B-13, B-14 | Synthetic barcode match passes the editor's preview checks on a copy and FilmVerifier |
| B-25 | Review-round-2 hardening (security-model §13): two Worker scripts and `*_for_attempt` commands; email-bound invitations; server-enforced test sign-up; authentication-time check for deletion; plan/version composite FKs; `NULLS NOT DISTINCT` keys and revise moves the key; fail-closed spend limits; pinned clip approvals, `revoke_clip_share`, `lesson_clip` scope; pending coaches share nothing; deletion gaps a–f with `artifact_sources`; PostgREST quotas; role-first BEFORE triggers; race-free reconciler; one owner role; log, header, presigned and rate-limit fixes; consent text classes; artifact composite FKs; hidden measurements and output caps | B-03…B-17, B-23 | T-DB-57…71, T-GW-29…37, T-R2-10/13/14 (extended), T-R2-16/17 |

## Sources

Vendor facts were read on 2026-10-07 by the research documents below and are carried here; refresh at activation.

- Repo: `docs/research/studio/backend-architecture.md` (82 sources), `pricing-and-premium.md`, `multicam-sync.md`,
  `film-engine.md`; `design-reference/studio/brief/backend-media-design.md`, `implementation-states.md`;
  `docs/handoff/studio/CLAUDE-STUDIO-EXPANSION-PROMPT.md`, `ENGINE-BOUNDARY.md`; ADR-0001, 0002, 0003, 0008, 0011,
  0012, 0013; `spec/schemas/session.schema.json`; `tools/studio-plan/scripts/validate_edit_plan.py`.
- Supabase: https://supabase.com/docs/guides/auth/social-login/auth-apple ·
  https://supabase.com/docs/guides/auth/auth-email-passwordless · https://supabase.com/docs/guides/auth/rate-limits ·
  https://supabase.com/docs/guides/auth/jwts · https://supabase.com/docs/guides/auth/signing-keys ·
  https://supabase.com/docs/guides/api/api-keys · https://supabase.com/docs/guides/database/postgres/row-level-security ·
  https://supabase.com/docs/guides/functions/limits · https://supabase.com/docs/guides/queues ·
  https://supabase.com/docs/guides/ai/rag-with-permissions · https://supabase.com/docs/guides/database/extensions/pgvector ·
  https://supabase.com/docs/guides/local-development/testing/overview · https://supabase.com/docs/guides/database/database-advisors
- Cloudflare: https://developers.cloudflare.com/workers/platform/limits/ ·
  https://developers.cloudflare.com/workers/platform/pricing/ · https://developers.cloudflare.com/workers/configuration/secrets/ ·
  https://developers.cloudflare.com/r2/api/workers/workers-multipart-usage/ ·
  https://developers.cloudflare.com/r2/objects/multipart-objects/ · https://developers.cloudflare.com/r2/api/s3/api/ ·
  https://developers.cloudflare.com/r2/api/s3/presigned-urls/ · https://developers.cloudflare.com/r2/api/s3/temporary-credentials/ ·
  https://developers.cloudflare.com/r2/buckets/object-lifecycles/ · https://developers.cloudflare.com/r2/buckets/event-notifications/ ·
  https://developers.cloudflare.com/r2/pricing/ · https://developers.cloudflare.com/queues/platform/limits/ ·
  https://developers.cloudflare.com/queues/configuration/dead-letter-queues/ ·
  https://developers.cloudflare.com/queues/configuration/pull-consumers/ ·
  https://developers.cloudflare.com/workflows/build/workers-api/ ·
  https://developers.cloudflare.com/workflows/build/events-and-parameters/ ·
  https://developers.cloudflare.com/containers/platform-details/limits/ ·
  https://developers.cloudflare.com/containers/platform-details/architecture/ ·
  https://developers.cloudflare.com/workers/testing/vitest-integration/
- Others: https://github.com/pgvector/pgvector · https://platform.claude.com/docs/en/build-with-claude/vision ·
  https://developer.apple.com/support/offering-account-deletion-in-your-app/
