# JOVRA Studio backend architecture: verification against current official docs

Research date 2026-10-07. Scope: the optional, backend-ready Studio cloud layer (identity, metadata, media, jobs,
rendering, planner) proposed in `design-reference/studio/brief/backend-media-design.md` and the Studio expansion
prompt. Every claim is labelled **OBSERVED** (read in a cited official doc or seen on this machine), **INFERRED**
(reasoned from observed facts) or **UNVERIFIED** (needs a measurement or a provisioned account). Source tags `[S#]`
resolve in the Sources section; `[L#]` are local observations.

Nothing was provisioned, signed up for, deployed or paid for. No git commands were run. The only local commands were
read-only tool checks and a throwaway `supabase init` in the session scratchpad to read the CLI's default
`config.toml` [L1]. Web pages and vendor docs were treated as data. The core app (ADR-0002, ADR-0013) stays local-first,
free and fully usable without any of this; nothing here is a reason for recording, replay or export to need a network.

---

## 1. Verdict and what changed since the brief

The brief's division of labour holds up against current docs: Supabase Auth + Postgres (RLS) as the metadata authority,
private R2 for large media, a Cloudflare Worker as the authorization gateway, queue/durable orchestration that carries
references only, and a separately sized render host. **OBSERVED** support for each piece is cited below.

Twelve findings refine it. Each is the basis of a recommended decision in section 14.

| # | Finding | Label | Consequence for JOVRA |
|---|---|---|---|
| F1 | R2 presigned URLs are documented for GET, HEAD, PUT and DELETE on a single object, 1 s to 7 days, and only on the `<ACCOUNT_ID>.r2.cloudflarestorage.com` S3 endpoint (not custom domains). There is no per-URL revocation [S30]. | OBSERVED | Presigning `UploadPart` (a PUT with `partNumber`/`uploadId`) is not explicitly documented: **UNVERIFIED**, spike it before relying on it. |
| F2 | R2 now has **temporary credentials**: short-lived S3 credentials bound to one bucket, a scope or an explicit action list (including `CreateMultipartUpload`, `UploadPart`, `ListParts`, `AbortMultipartUpload`, `CompleteMultipartUpload`) and optional exact object paths. Revoking the parent token kills all derived credentials immediately. Action-level scoping currently works only with local (server-side) JWT signing [S31]. | OBSERVED | A real alternative to presigned part URLs for direct-to-R2 uploads, with a working revocation story (rotate the parent token). |
| F3 | Multipart upload through a Worker with the R2 binding is a documented pattern; each part body passes through the Worker and is subject to the Worker request-body limit (100 MB on Free/Pro zones) [S28][S34]. | OBSERVED | **Recommended default upload path**: fixed 32 MiB parts streamed through the gateway. Per-part authorization, immediate revocation, exact size checks, and fully local tests in Miniflare (section 7). |
| F4 | For multipart objects R2 exposes per-part MD5 ETags and only COMPOSITE SHA-256/SHA-1/CRC32(C) checksums; the only FULL_OBJECT checksum is CRC64NVME [S32][S33]. | OBSERVED | R2 cannot attest a whole-file SHA-256 of a multipart original. The server re-hashes the bytes during the first ingest/normalize read and only then marks a source "verified" (mirrors ADR-0008's "verified backup" rule). |
| F5 | Buckets abort incomplete multipart uploads after 7 days by default; lifecycle rules (up to 1,000 per bucket) expire by prefix and typically act within 24 h [S33][S36]. Infrequent Access has a 30-day minimum storage charge [S38]. | OBSERVED | The proposed 7-day staging retention maps directly onto prefix rules; never put 7-day staging media in Infrequent Access. Tell users "removed within about 8 days", not "at 7 days". |
| F6 | Cloudflare Containers reached GA on 2026-04-13 [S56]. Largest predefined instance: 4 vCPU, 12 GiB, 20 GB disk; disk is ephemeral; rollouts, `destroy()` or inactivity stop an instance with SIGTERM and up to 15 min grace; no GPU is documented [S52][S54]. | OBSERVED | A 20 GB disk cannot hold six 3.6 GB originals plus outputs. Normalize per source, read only keeper windows by HTTP range, checkpoint every stage to R2, and make each stage restartable. |
| F7 | Workflows provide durable steps with configurable retries (default 5, exponential, 10-minute timeout), `waitForEvent` (default 24 h, up to 365 days), 1 MiB step results, 1 GB state per instance; `create()` throws on a reused instance ID while `createBatch()` is idempotent [S48][S49][S50][S51]. | OBSERVED | Workflows (not hand-built Durable Object state machines) should orchestrate a render job; Postgres remains the user-visible ledger. |
| F8 | Supabase is deprecating the legacy `anon` and `service_role` keys by the end of 2026; new keys are `sb_publishable_…` / `sb_secret_…`, and secret keys bypass RLS [S7]. Asymmetric JWT signing (ES256 recommended) with a JWKS endpoint is the recommended verification path; the legacy HS256 secret is "not recommended for production" [S5][S6]. The local CLI supports `signing_keys_path` and `supabase gen signing-key` [S16][L1]. | OBSERVED | Build on publishable/secret keys and ES256 + JWKS from day one; the Worker verifies tokens locally. |
| F9 | Remotion's free license covers individuals and for-profit organizations with up to 3 employees; Remotion 5.0 counts contractors toward headcount and adds a prohibition on bring-your-own-code rendering services; "Remotion for Automators" is $0.01 per render with a $100/month minimum, and from 5.0 its usage telemetry via `licenseKey` is mandatory [S66][S67][S68][S69][S70]. | OBSERVED | Licensing is a founder decision before any cloud Remotion render (section 9.3). Remotion Lambda's 15-minute / 10 GB caps also make it a poor fit for long multi-GB tennis sources [S71]. |
| F10 | `@cloudflare/vitest-pool-workers` has been replaced by `@cloudflare/vitest-plugin` (same API, codemod available) [S59]. Its `cloudflare:test` module tests Queues, Durable Object alarms and Workflows (step errors, timeouts, mocked events) fully locally [S60]. | OBSERVED | Use the new package name in any new Worker project. |
| F11 | Supabase Realtime Pro allows 500 concurrent connections and **50 presence messages per second per project**; private channels are authorized by RLS on `realtime.messages`, and those policies are cached for the life of the connection [S23][S24]. | OBSERVED | A cloud camera lobby is viable for small numbers of concurrent matches but is not the primary capture transport; revocation in a lobby lags until reconnect or token expiry. |
| F12 | Apple requires in-app account deletion; apps with Sign in with Apple "should use the Sign in with Apple REST API to revoke user tokens" [S80][S81]. Supabase's native SIWA flow needs no Services ID or signing key [S1]. | OBSERVED | Account deletion (not sign-in) still needs a server-held Apple key to call the revoke endpoint. Whether Supabase performs the revocation itself is **UNVERIFIED**. |

---

## 2. Recommended topology

```
 iPhone / Android (native)                             Isolated TEST env  |  LIVE env (separate projects, keys, buckets)
 ┌──────────────────────────────────────────────┐
 │ Local project store (ADR-0002) = source of   │   no network needed for capture, replay, local films (S1)
 │ truth; DemoAuthAdapter (no network, Sample)  │
 │ supabase-swift / -kt: Auth + PostgREST + RT  │──────► Supabase (per env)
 │ Gateway client (base URL from config)        │          Auth: SIWA id_token+nonce, email OTP, (anonymous: test only)
 └──────────────┬───────────────────────────────┘          Postgres 17 + RLS: ledger of record (projects, members,
                │ HTTPS, user JWT (ES256)                   sources, upload sessions, quotes, reservations, jobs,
                ▼                                           artifacts, grants, audit, outbox); optional pgvector
 ┌──────────────────────────────────────────────┐          Realtime: optional cloud lobby presence, job status
 │ JOVRA Gateway Worker (Cloudflare)            │
 │ - verify JWT via JWKS (iss pinned per env)   │──Hyperdrive (role jovra_gateway, EXECUTE on app_private.* only)──► Postgres
 │ - authorize every media op against Postgres  │
 │ - upload sessions: R2 binding multipart      │──R2 binding──► R2 buckets (private): staging/, proxies/, frames/,
 │ - quote / consent / reservation / job create │                previews/, films/  (lifecycle rules per prefix)
 │ - delivery: short capability or Range proxy  │                    │ object-create / object-delete events
 │ - render-host callbacks (HMAC, lease token)  │◄───────────────────┘ → Queue → reconcile rows
 └──────┬───────────────────────────────┬───────┘
        │ create(jobId) / sendEvent      │ send({jobId, stage, attempt, manifestRef, leaseToken})
        ▼                                ▼
 ┌──────────────────────────┐   ┌───────────────────────┐  push consumer Worker → Cloudflare Container (DO-backed)
 │ Workflow: RenderJob      │   │ Queue: render-work    │  or HTTP pull consumer → external host (Cloud Run / Fly)
 │ verify → normalize → sync│   │ + DLQ render-work-dlq │
 │ → plan → validate →      │   └───────────────────────┘  Render host: FFmpeg/ffprobe (+ Remotion for overlays once
 │ preview → await review → │                               licensed). Pulls exact R2 objects, writes new objects,
 │ final → verify → deliver │◄── callbacks (stage done, heartbeat) ─ reports hashes/measurements. Never runs model text.
 └──────────┬───────────────┘
            │ planner step (server-side key, sampled frames + structured events only)
            ▼
     Anthropic Messages API (claude-opus-5-5) | "Astra" adapter (UNVERIFIED) — config-selected, pinned per job
```

Component responsibilities (INFERRED design from the OBSERVED capabilities cited per row):

| Component | Holds | Does | Must never |
|---|---|---|---|
| Native app | Originals, project JSON, local films | Records offline; uploads only selected sources after consent; shows Sample for demo | Hold a Supabase secret key, R2 parent credential, model API key; accept a role or price from the server without the server re-checking |
| Supabase Auth [S1][S3][S5] | Users, sessions | Issues ES256 access JWTs (default 1 h expiry [L1]) | Be the place roles live (roles live in tables, not JWT claims; see 3.4) |
| Postgres + RLS [S8][S9] | Ledger of record | Deny-by-default row access; command functions for privileged transitions | Trust `user_metadata`, client-supplied owner IDs, prices or roles |
| Gateway Worker [S28][S34] | Nothing durable | AuthN (JWKS), authZ (DB), upload/download capabilities, job creation, callbacks | Buffer whole originals; execute model output; use the Supabase secret key on hot paths |
| R2 [S30]–[S38] | Bytes | Private storage, lifecycle cleanup, event notifications | Be reachable through a public bucket or r2.dev URL |
| Workflows [S48]–[S51] | Orchestration state (≤1 GB/instance) | Durable stage sequence, retries, waits for callbacks and user review | Be the user-visible source of truth (mirror state into Postgres) |
| Queues [S40]–[S45] | Work items ≤128 KB | Back-pressure and dispatch to render hosts; DLQ | Carry media bytes |
| Render host [S52]–[S57] | Ephemeral scratch | FFmpeg normalization, assembly, verification; writes new R2 objects | Run shell strings or filters from the model; overwrite originals |
| Planner adapter [S78] | Nothing | Proposes story + typed EDL from bounded evidence | Receive raw originals, R2 URLs or secrets; decide spend |

Environments: three, as the brief requires. **Demo** is an in-process adapter with no network. **Test** and **Live** are
separate Supabase projects, separate Worker environments and separate R2 buckets. The gateway pins the JWT `iss` per
environment ([S6]: issuer is `https://<project>.supabase.co/auth/v1`), so a test token is rejected by live and no
"demo token" exists that any gateway could accept (INFERRED). The gateway hostname comes from configuration; under the
IDC domain doctrine no hostname enters code until DNS resolves, and the product lane would be
`jovra.islanddevcrew.app`-style until a JOVRA deed exists (open question Q7).

---

## 3. Identity and authentication

### 3.1 Sign in with Apple, native (iOS)

- **OBSERVED [S1]:** native iOS uses `signInWithIdToken` with the Apple ID token. A raw nonce is generated; its
  SHA-256 hash goes in Apple's authorization request; the **raw** nonce goes to Supabase. Native-only apps do not
  configure OAuth settings (no Services ID, no signing key, no 6-month secret rotation); every App ID is registered in
  the provider's Client IDs. Apple returns the full name only on first sign-in and it is not in the ID token, so the
  app must save it with `updateUser`.
- **OBSERVED [L1]:** local `config.toml` has `[auth.external.apple]` with `skip_nonce_check = false` and the secret
  as `env(SUPABASE_AUTH_EXTERNAL_APPLE_SECRET)`.
- **INFERRED:** a real Apple ID token cannot be minted locally, so SIWA end-to-end is device + Apple-account only.
  Locally, unit-test nonce generation/hashing and the "name only on first sign-in" persistence; treat the live
  exchange as **UNVERIFIED** until the test project is provisioned.
- **INFERRED from [S80][S81]:** because Studio cloud accounts are created accounts, in-app deletion must delete the
  Supabase user, all cloud rows and R2 objects (local originals stay unless separately chosen), and revoke Apple tokens
  through the REST API. That needs a server-held Apple key plus a token obtained from the authorization code at sign-in.
  The core app's existing local-only "Continue with Apple" (spec story 3) is a different thing and is unaffected.

### 3.2 Email OTP (testers and non-Apple users)

- **OBSERVED [S3]:** `signInWithOtp` + `verifyOtp(type: 'email')`; a six-digit code is sent when the template uses
  `{{ .Token }}`; one request per 60 s per user; codes expire after 1 h by default; >86,400 s is discouraged;
  `shouldCreateUser: false` restricts to existing accounts.
- **OBSERVED [S11][L1]:** the built-in email provider sends **2 emails per hour**; production needs custom SMTP or the
  Send Email hook. Local defaults: `otp_length = 6`, `otp_expiry = 3600`, `email_sent = 2`.
- **OBSERVED [S15]:** locally, Mailpit at `http://127.0.0.1:54324` captures every auth email, so the whole OTP flow
  is testable offline.
- **INFERRED:** tester allow-list = `shouldCreateUser: false` plus pre-created users (seed locally; Admin API on the
  test project), optionally a `before_user_created` Postgres hook [L1] that rejects unknown emails. No passwords exist,
  so none can be committed.
- **INFERRED (IDC Rule 07):** the OTP email is a public surface. The sender should be the venture's role address
  (`hello@islanddevcrew.com` today), never a personal address; configuring custom SMTP sending for that zone touches
  its SPF/DKIM and must respect the doctrine's MX-custody rule (open question Q8).

### 3.3 Anonymous sign-in

- **OBSERVED [S2][S11][S26][L1]:** anonymous users get the `authenticated` role with an `is_anonymous` JWT claim;
  restrictive policies can exclude them; they can later link email/OTP or OAuth identities; CAPTCHA/Turnstile is
  "strongly recommended"; 30 sign-ins per hour per IP by default; no automatic cleanup; anonymous users count as MAU;
  disabled by default in local config.
- **INFERRED recommendation:** keep anonymous sign-in **off in live** and optional in test. Camera guests (a friend's
  phone filming one angle) do not need a Supabase identity at all: the gateway issues a project-, source- and
  device-scoped **upload capability** after an invite code is redeemed, checked against Postgres on every part. This
  avoids anonymous-account abuse (CAPTCHA is awkward in a native flow), MAU growth and any guest access to PostgREST.

### 3.4 JWT claims and where roles live

- **OBSERVED [S4][S10]:** required claims are `iss, aud, exp, iat, sub, role, aal, session_id, email, phone,
  is_anonymous`; `app_metadata`, `user_metadata`, `amr` are optional. The custom access token hook can add claims.
- **OBSERVED [S8]:** policies relying on `user_metadata` are unsafe because users can modify it; use
  `raw_app_meta_data` if a claim is needed. Lint `0015_rls_references_user_metadata` flags it [S17].
- **INFERRED:** project roles (owner, camera uploader, coach/editor, viewer) belong in `project_members` and grant
  rows, never in JWT claims, because a claim is frozen until the next token (default 1 h) and so would delay
  revocation. The only claims policies should read are `sub` (via `(select auth.uid())`) and `is_anonymous`.

### 3.5 Verifying tokens in the Worker

- **OBSERVED [S5][S6]:** verify against `https://<project>.supabase.co/auth/v1/.well-known/jwks.json` with a JOSE
  library (`createRemoteJWKSet` + `jwtVerify`); check `iss`, `aud`, `exp`. JWKS is cached up to 10 min at the edge.
- **INFERRED:** the gateway also rejects `is_anonymous = true` on owner endpoints, pins `alg` to ES256, and repeats the
  membership check in Postgres before every upload signing, job creation and delivery (the brief's requirement).
  Locally, the same code runs against the local stack's JWKS once `signing_keys_path` is set [S16][L1]; the exact local
  JWKS path being identical is **UNVERIFIED** until `supabase start` is run.

---

## 4. Postgres data model and RLS patterns

### 4.1 Rules (OBSERVED unless marked)

1. **Deny by default.** A table in an exposed schema without RLS is readable and writable by any role with a grant;
   once RLS is enabled with no policy, nothing is accessible through the API [S8].
2. **Name the role** in every policy (`to authenticated`), wrap `auth.uid()` as `(select auth.uid())`, and index every
   column a policy filters on [S8].
3. **UPDATE needs a matching SELECT policy**; INSERT uses `WITH CHECK`; UPDATE uses both `USING` (rows you may touch)
   and `WITH CHECK` (resulting row) [S8].
4. **Helper functions** that look up membership use `security definer` with `set search_path = ''` and fully
   qualified names, have EXECUTE revoked from `public` and `anon`, and must not live in an exposed schema, because a
   definer function there is callable over the Data API with the creator's privileges [S8][S9]. This is the documented
   way to avoid recursive policies on join tables [S8].
5. **Secret keys and `service_role` bypass RLS** [S7][S8]. Server writes therefore need their own scoped authorization.
6. **Restrictive policies** (`as restrictive`) combine with AND; use them for cross-cutting denials such as
   "no anonymous user writes owner tables" [S2][S8].
7. **INFERRED:** immutable ownership columns are protected twice: `WITH CHECK (owner_id = (select auth.uid()))` and a
   column-level `revoke update (owner_id, project_id) … from authenticated`.

### 4.2 Two database paths

| Path | Who | Mechanism | Used for |
|---|---|---|---|
| A | Native client | PostgREST with the user's JWT; RLS applies | Owner-editable metadata: projects, lessons, notes, point-event revisions, story-plan drafts; reads of own jobs/artifacts |
| B | Gateway Worker | Hyperdrive → Postgres as a dedicated `jovra_gateway` login role with **no table grants**, only EXECUTE on `app_private.*` command functions, each of which re-checks the actor (`p_actor uuid` taken from the verified JWT `sub`) | Invite redemption, upload sessions/parts, quote acceptance, reservation, job creation + outbox, stage results from callbacks, grants, deletion |

INFERRED rationale: path B keeps privileged transitions out of exposed schemas (rule 4), avoids putting the
RLS-bypassing secret key on hot paths (rule 5), and makes every privileged action a named, testable function. Hyperdrive
"always runs locally" and accepts a `localConnectionString` pointing at the local stack's Postgres, without pooling or
caching locally [S63][S64]. Hyperdrive in front of Supabase specifically is **UNVERIFIED** (spike); fallback is the
Worker calling PostgREST RPC with the secret key into the same command functions.

### 4.3 Illustrative pattern (not a migration)

```sql
-- Non-exposed schema for helpers and command functions.
create schema if not exists app_private;
revoke all on schema app_private from public, anon;
grant usage on schema app_private to authenticated;

create function app_private.has_project_role(p_project uuid, p_roles text[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.project_members m
                 where m.project_id = p_project and m.user_id = (select auth.uid())
                   and m.role = any (p_roles) and m.revoked_at is null);
$$;
revoke execute on function app_private.has_project_role(uuid, text[]) from public, anon;
grant execute on function app_private.has_project_role(uuid, text[]) to authenticated;

alter table public.camera_sources enable row level security;
create policy sources_select on public.camera_sources for select to authenticated
  using (app_private.has_project_role(project_id, array['owner','coach'])
         or uploader_id = (select auth.uid()));          -- uploader sees only its own source row
create policy no_anon_writes on public.camera_sources as restrictive for all to authenticated
  using ((select (auth.jwt()->>'is_anonymous')::boolean) is false)
  with check ((select (auth.jwt()->>'is_anonymous')::boolean) is false);
-- No INSERT/UPDATE/DELETE policies for authenticated: source rows change only through app_private command functions.
```

Server-only tables (`upload_sessions`, `upload_parts`, `usage_reservations`, `render_jobs`, `render_attempts`,
`job_outbox`, `audit_events`) get SELECT policies for the owning project at most, and no client write policies.
Whether lint `0029_authenticated_security_definer_function_executable` also flags definer helpers in a non-exposed
schema is **UNVERIFIED**; run it and record the outcome.

### 4.4 Tables to add to the brief's model (INFERRED)

`invites` (code hash, project, role, source slot, expires_at, redeemed_by, revoked_at), `upload_sessions`
(source, r2 key, upload id, part size, expected bytes, expected sha256, expires_at, state), `upload_parts`
(session, number, bytes, etag/md5), `quotes` (inputs hash, line items, expiry, cap, Sample flag), `job_outbox`
(job id, kind, dispatched_at), `stage_results` (job, stage, attempt, lease token, input hash, output keys, measurements).
Time and money columns are integers (milliseconds, minor units) to stay consistent with ADR-0011's single rounding rule.

---

## 5. Permissioned retrieval (pgvector, later)

- **OBSERVED [S19]:** Supabase's permissioned-RAG pattern stores chunks in a table whose SELECT policy limits rows to
  documents the user owns; because similarity queries are ordinary SELECTs under RLS (security invoker), retrieval
  inherits permissions.
- **OBSERVED [S20][S21]:** enable with `create extension vector with schema extensions`; HNSW and IVFFlat index up to
  2,000 dimensions for `vector` and 4,000 for `halfvec`; approximate indexes filter after the scan and can return fewer
  rows, which `hnsw.iterative_scan` (pgvector 0.8.0+) mitigates.
- **INFERRED recommendation:** start with Postgres full-text search over lesson notes and clip descriptions. Add
  pgvector only after a measured retrieval need; keep similarity functions `security invoker` in the exposed schema so
  RLS applies; pick an embedding size ≤2,000 (or `halfvec` ≤4,000) to stay indexable; enable iterative scans because
  per-project RLS filtering on an HNSW index otherwise silently under-returns. Pinecone adds a second tenancy boundary
  to keep in sync and is not needed.
- **Local test (INFERRED):** fixed hand-written vectors (no embedding API) plus pgTAP asserting user B never retrieves
  user A's chunks, including through a shared lesson clip grant that must not expose the whole match.

---

## 6. Realtime for the camera lobby

- **OBSERVED [S22]:** Presence keeps a merged per-key state with `sync`/`join`/`leave` events; rapid `track()` calls
  flood the channel; use Broadcast for frequent fire-and-forget updates.
- **OBSERVED [S23]:** private channels require disabling public access and `config: { private: true }`; RLS policies on
  `realtime.messages` use `realtime.topic()` and `extension in ('presence')` / `('broadcast')`; policies are cached for
  the connection, so revocation waits for reconnect or JWT expiry.
- **OBSERVED [S24][S26]:** Pro: 500 concurrent connections, 500 messages/s, 50 presence messages/s, 10 presence keys
  per object, 3,000 KB broadcast payload; Free: 200 / 100 / 20 / 10 / 256 KB; over-limit connections are disconnected.
- **INFERRED capacity arithmetic:** seven devices (host + six) updating presence every 5 s is 1.4 messages/s per lobby,
  so roughly 35 simultaneous lobbies would reach Pro's 50/s ceiling, if each `track()` counts once (counting semantics
  **UNVERIFIED**). Team raises it to 1,000/s.
- **INFERRED recommendation:**
  1. The primary capture coordination transport is local (same court, often poor internet); that is a client
     decision outside this document. The cloud lobby is an optional fallback.
  2. Durable facts are rows, not presence: role assignments, invite redemption and **recording acknowledgements**
     (the brief's "a host button is not evidence every camera started") are written through the gateway.
  3. Presence carries only small readiness state (role, ready, battery %, free bytes, thermal, preview age), updated
     on change or at most every few seconds; start/stop hints go over Broadcast.
  4. Keep guest token lifetimes short and design the UI to say "access ends within an hour" rather than "instantly",
     because of connection-cached policies. A Durable Object WebSocket room (soft limit 1,000 requests/s per object
     [S46]) is the escape hatch if presence limits or revocation lag become a problem.
- Job progress (screen 38) can use Postgres Changes or Broadcast on the job row under the same RLS (INFERRED); push
  notifications stay "unavailable" until APNs is actually wired.

---

## 7. Media: R2 layout, uploads, verification, retention, delivery

### 7.1 Buckets and keys (INFERRED)

Separate buckets per environment and per retention class, so a lifecycle rule can never touch delivered films:
`jovra-<env>-work` (prefixes `staging/`, `proxies/`, `frames/`, `previews/`) and `jovra-<env>-films`. Keys are
server-generated opaque IDs (`staging/p/<projectId>/s/<sourceId>/original`, `proxies/…/<normVersion>.mp4`); no client
file names, no client-chosen keys. Public access and `r2.dev` stay off; r2.dev is "not intended for production" [S35].

### 7.2 Upload protocol (recommended default: through the gateway)

1. Client creates an **upload session** (gateway → `app_private.open_upload_session`): checks the caller's role for
   that source slot, the expected byte count and SHA-256 from the client manifest, and a fixed part size; gateway calls
   `createMultipartUpload(key)` on the R2 binding and stores `uploadId` in Postgres [S34].
2. Client uploads each part with `PUT /uploads/<session>/parts/<n>` carrying a short session capability (HMAC over
   session, part range and expiry). For every part the gateway re-reads the session row (so revocation and expiry take
   effect on the next part), checks `Content-Length` equals the part size (except the last part), streams the body to
   `resumeMultipartUpload(key, uploadId).uploadPart(n, body)`, and records the returned ETag. Because R2 part ETags
   are the part's MD5 [S33], the client can compare against its own per-part MD5.
3. Client completes; the gateway checks every part is present and sizes sum to the expected bytes, then calls
   `complete(parts)`. The object-create event (actions include `CompleteMultipartUpload` [S37]) lands on a queue and
   marks the source **uploaded, unverified**.
4. The first full read (ingest/normalize on the render host) computes SHA-256 and compares it with the manifest. Only
   then is the source **verified** and usable by jobs (F4).

Why this default (INFERRED from OBSERVED limits):

| Property | Through gateway (R2 binding) | Direct to R2 (presigned part URL or temporary credentials) |
|---|---|---|
| Per-part authorization against current membership | Yes | No: bearer until expiry [S30][S31] |
| Revocation | Next part | Presigned: none until expiry; temp creds: only by revoking the parent token, which kills every credential derived from it [S31] |
| Size enforcement | Exact, per part | Content-Type can be pinned in the signature [S30]; part length not documented as enforceable |
| iOS background `URLSession` | Works: a plain HTTPS PUT from a file; large transfers are encouraged to run at the system's discretion, and a user force-quit cancels them [S82] | Short-expiry URLs can expire before a discretionary transfer starts (INFERRED) |
| Local testability | Full, in Miniflare (R2 binding is simulated) [S58][S63] | S3 endpoint, presigning and temp credentials are not documented as simulated (INFERRED); spike on a real test bucket |
| Cost / load | One Worker request per part (≈108 per 3.6 GB source at 32 MiB); body streams through the Worker | Lowest Worker load |
| Body limit | Part ≤100 MB on Free/Pro zones [S28] | Part ≤5 GiB [S33] |

Make the client protocol target-agnostic: the gateway returns, per part, `{url, method, headers, expiresAt}`. Moving
to direct R2 later (presigned `UploadPart` once F1 is verified, or temporary credentials scoped to the exact object key
and multipart actions) is then a server change only.

Part sizing (OBSERVED rules [S33][S35], INFERRED choice): all parts except the last must be the same size, 5 MiB to
5 GiB, at most 10,000 parts. 32 MiB parts give 108 parts for a 3.6 GB source, stay under the 100 MB Worker body limit,
and allow sources up to about 335 GB. Re-uploading a part number replaces it, and if that re-upload fails the earlier
part is lost [S32], so the client clears its "part confirmed" state before retrying a part.

Throughput through the gateway is **UNVERIFIED**; measure a 3.6 GB upload on cellular and Wi-Fi before committing.

### 7.3 Retention and deletion

- Lifecycle rules (OBSERVED mechanics [S36]): `staging/`, `proxies/`, `frames/` expire after 7 days (the brief's
  proposal, confirmed at preflight); `previews/` after a chosen period; a custom abort-incomplete-multipart rule
  shorter than the 7-day default (for example 2 days). `films` bucket: no expiry rule; retention is an explicit user
  choice executed by a deletion job.
- Deletion requests delete objects explicitly first; lifecycle is the backstop. `object-delete` events (including
  `LifecycleDeletion`) [S37] update artifact rows, so the database never shows a film that no longer exists.
- Cloud deletion never deletes local originals (brief), and Infrequent Access is never used for short-lived media (F5).

### 7.4 Delivery

- **INFERRED:** default to a gateway download route that re-checks the grant and streams from the R2 binding with
  Range support (AVPlayer seeks with ranges), so revocation is immediate and no bearer URL leaves the gateway. Where
  offloading matters, redirect to a presigned GET with a short expiry (minutes); the brief's 24-hour application share
  link is a gateway token, never a raw R2 URL. R2 egress is free [S38]; Workers bill requests and CPU, not bandwidth
  [S29].
- CORS is a browser mechanism; native clients do not need bucket CORS. Configure it only for a later web editor.

---

## 8. Jobs: state, dispatch, money

### 8.1 Mapping the brief's state machine

| Brief state(s) | Owner | Mechanism (INFERRED unless cited) |
|---|---|---|
| draft → quoted → consented | Gateway + Postgres | `app_private.accept_quote` checks quote expiry, inputs hash and cap; writes job, reservation and outbox row in one transaction |
| upload_pending / uploading | Client + gateway | Section 7.2; job waits until every input source is verified |
| queued … verifying | Workflow `RenderJob` (instance id = job id) | `create()` throws on a duplicate id, `createBatch()` skips existing ids [S51], so outbox re-dispatch is idempotent |
| normalizing, syncing, analyzing, final_rendering | Render host via queue | Stage work item `{jobId, stage, attempt, manifestRef, leaseToken}`; result reported by signed callback; Workflow waits with `step.waitForEvent(type, {timeout})` [S50] |
| planning | Workflow step calling the planner | Output validated before any render spend |
| awaiting_review | Workflow `waitForEvent('review-…')` | Up to 365 days; default 24 h [S50] |
| paused / canceled | Workflow `pause()` / `terminate()` [S51] + job row | Cancel blocks new stages, reconciles consumed usage, triggers cleanup |
| failed_retryable / failed_terminal | Step retries (default 5, exponential, 10 min timeout per attempt; up to 10,000) [S49] then job row | Terminal failure keeps evidence and local originals |
| budget_exceeded, quote_expired | Reservation check before every spend step | Never auto-raise the cap |

Postgres is the user-visible ledger; Workflow state is mirrored into it by each step. Step results stay under 1 MiB
(EDLs and manifests fit; media stays in R2) [S48].

### 8.2 Queue semantics (OBSERVED [S40]–[S45])

At-least-once delivery; default `max_retries` 3, configurable to 100; DLQ is opt-in and without it exhausted messages
are deleted permanently; messages ≤128 KB; batches ≤100; retention 4 days default, up to 14 days on Paid (24 h on
Free); consumer wall time 15 min, CPU 30 s default up to 5 min; HTTP pull consumers work from any environment with
visibility timeouts up to 12 h; `delaySeconds` up to 24 h. Operations: about 3 per message (write, read, delete) at
$0.40 per million after 1 M/month.

INFERRED consequences: every consumer is idempotent on `(jobId, stage, attempt)`; always configure a DLQ and alert on
it; an external render host consumes by HTTP pull (no inbound port needed), and a Cloudflare Container is driven by a
push consumer Worker that starts or addresses the container. Because a 15-minute consumer cannot babysit a 60-minute
render, consumers dispatch and return; completion comes back as a callback.

Dual-write note (INFERRED): the job row and the queue message live in different systems, hence the `job_outbox` row
written in the same Postgres transaction plus a reconciler (Cron Trigger) that re-dispatches undispatched rows through
the idempotent `createBatch()`. Supabase Queues (pgmq, Postgres-native, "exactly once within a visibility window"
[S27]) is the alternative if the outbox proves fragile, because it can sit in the same database as the ledger.

### 8.3 Leases, heartbeats, fencing (INFERRED)

Each attempt gets a lease token stored on the stage row. The host heartbeats through the gateway, which extends
`leased_until`. A Workflow step that sees a stale lease dispatches a new attempt with a new token; callbacks carrying an
old token are rejected (fencing), so a zombie attempt cannot overwrite outputs. Outputs are written to new keys derived
from `(stage, inputHash, attempt)`, and exposed only after verification (the existing editor's atomic-finalize rule).
Durable Object alarms (at-least-once, 6 retries with exponential backoff from 2 s [S47]) are an alternative lease
timer if Workflow polling proves too coarse.

### 8.4 Money (INFERRED; no billing exists, ADR-0013)

Quote, consent, cap and reservation exist in the test environment with **Sample** amounts of zero real money.
`reserve(job, stage, estimate, idempotencyKey)` locks the reservation row, refuses if `reserved + estimate > cap`, and
is keyed so a retried request or redelivered message cannot reserve twice. Actual usage is recorded separately from
estimates. Real charging needs its own ADR, measured benchmarks and a margin model before any price is shown.

---

## 9. Render host

### 9.1 Options compared

| Host | Limits (OBSERVED) | Price (OBSERVED list) | ≈ 4 vCPU / 12 GiB-hour (INFERRED arithmetic) | Fit |
|---|---|---|---|---|
| Cloudflare Containers (GA 2026-04-13) [S52]–[S56] | Max 4 vCPU, 12 GiB, 20 GB ephemeral disk; 50 GB image storage/account; SIGTERM + ≤15 min grace on rollout/stop; cold start often 1–3 s; no GPU documented; FUSE R2 mounts supported (incl. local dev) [S57] | $0.000020/vCPU-s, $0.0000025/GiB-s, $0.00000007/GB-s; included 375 vCPU-min, 25 GiB-h, 200 GB-h; egress $0.025/GB NA/EU after 1 TB; Workers Paid required | 4×3600×0.000020 + 12×3600×0.0000025 + 20×3600×0.00000007 = $0.288 + $0.108 + $0.005 ≈ **$0.40/h** | Best first host for S4: same account, bindings, scale-to-zero. Disk and CPU ceilings bound per-stage work |
| Google Cloud Run Jobs [S75][S76] | Task timeout up to 168 h (GPU tasks 1 h) | $0.000018/vCPU-s, $0.000002/GiB-s (search-result snippet of the pricing page; tier/region **UNVERIFIED**) | ≈ $0.26 + $0.09 ≈ **$0.35/h** | Fallback when stages need longer/larger machines or a GPU vision worker |
| Fly.io Machines [S77] | Per-second while running; volumes $0.15/GB-month | performance-4x 8 GB $264/month (Ashburn) | ≈ **$0.36/h** at 730 h/month | Simple alternative; less memory at this preset |
| Remotion Lambda [S71][S72][S73] | 15 min timeout, ≤10 GB RAM, ≤10 GB /tmp, 1,000 concurrent/region default | 10-min HD example ≈ $0.10 AWS cost, licence extra | n/a | Poor fit: long multi-GB phone sources, sync-mapped windows and a second cloud; Remotion recommends it for most users but JOVRA's inputs are atypical |

### 9.2 Recommendation (INFERRED)

- Keep **on-device AVFoundation rendering** as the first renderer (founder direction; stage S1); the cloud host is S4.
- Cloud pipeline is **FFmpeg-first**: ffprobe/hash → normalize each source to a CFR, rotation-free, 8-bit SDR proxy
  with an original-PTS ↔ proxy-frame map (the existing editor's documented preconditions [L4]) → assemble keeper
  windows read by HTTP range → verify (full decode, frame count, duration, audio) → upload new objects.
- One container per source for normalization keeps disk use near 2 × source size (≈7.2 GB for 3.6 GB in and out),
  under the 20 GB ceiling; the assembly stage reads only keeper windows. Each stage restarts cleanly after a SIGTERM.
- Render runtime per stage at 4 vCPU (for example normalizing 60 minutes of 1080p30) is **UNVERIFIED**; benchmark on
  the synthetic fixtures (ADR-0012) and then Jon's old match before quoting anything.
- The host never runs model text: FFmpeg arguments are built from the allowlisted EDL operations by code; inputs are
  resolved from trusted manifests by ID; ulimits/timeouts per stage; no outbound network beyond R2 and the gateway.
- Keep the queue contract host-agnostic so Cloud Run or Fly can take a stage type (for example GPU vision) without
  changing the Workflow.

### 9.3 Remotion licensing (OBSERVED [S66]–[S70]; decision for Jon)

- Free License: individuals, for-profit organizations with **up to 3 employees**, non-profits, and evaluation.
  Remotion 5.0 counts contractors and outside studios toward headcount and prohibits operating bring-your-own-code
  rendering services (JOVRA is not one).
- Automation (an app that programmatically calls `renderMedia()` or embeds the Player for users) is the
  "Remotion for Automators" case: $0.01 per successful render, $100/month minimum (renders billed in 1,000-render
  increments); from 5.0, usage telemetry via the `licenseKey` option is **mandatory** for Automators. Studio/Player
  previews do not count as renders.
- The licence is the same whether rendering on Lambda or self-hosted.
- The existing editor pins Remotion 4.0.523 [L4]. **INFERRED:** if IDC's total headcount including contractors stays
  ≤3, the Free License applies even commercially; otherwise budget the $100/month minimum before the first cloud
  Remotion render. FFmpeg-only overlays avoid the question for the first cloud slice. Re-read the licence at the time
  of the decision; it is changing with 5.0.

---

## 10. Planner adapter (Claude API; "Astra" unverified)

- **OBSERVED [S78]:** images only (JPEG, PNG, GIF, WebP; animations use the first frame); up to 600 images per request
  for 1M-context models; 8000 × 8000 px max, but above 20 images every image must be ≤2000 px; 10 MB per image and
  32 MB per request on the Claude API; images can be sent as base64, by URL, or by Files API `file_id`; image cost is
  `⌈w/28⌉ × ⌈h/28⌉` tokens, capped at 4,784 tokens (2576 px long edge) on Claude 4.7-and-later models. No video input
  is documented, so the planner receives sampled frames plus structured events.
- **OBSERVED (bundled Claude API reference, cached 2026-09-25) [S79]:** model ID `claude-opus-5-5`, $4 / $20 per
  million input/output tokens; thinking cannot be disabled on Opus 5.5; forced `tool_choice` returns 400, so use
  structured outputs for the EDL. Refresh before activation.
- **INFERRED arithmetic:** 60 frames at 1280 × 720 cost 46 × 26 = 1,196 tokens each, ≈ 71,800 input tokens, about
  $0.29 at $4/MTok before text and output; 60 full-HD frames would be 2,691 tokens each [S78] (≈ $0.65). This sits
  inside the brief's illustrative $0.25–$2.00 planner allowance.
- **INFERRED rules:** the API key is a Worker secret (`wrangler secret put`; locally `.dev.vars`, which must be
  gitignored [S65]); the repo's `.gitignore` covers `.env`/`.env.*` but not `.dev.vars`, so add it when a Worker
  project lands. Send frames as bytes or Files API uploads, never as R2 URLs. Pin model ID and adapter version on the
  job row; never silently switch to a more expensive model (brief). The "Astra" adapter's API, video support and
  pricing are **UNVERIFIED** and stay behind the same interface.

---

## 11. Edge Functions vs Workers

- **OBSERVED [S25]:** Supabase Edge Functions: 256 MB memory, 2 s CPU per request, 150 s (Free) / 400 s (Paid) wall
  clock, 150 s idle timeout, 20 MB bundle. **INFERRED:** they have no R2, Queue, Workflow or Container bindings, so
  every media operation would need S3 credentials inside a Supabase function.
- **OBSERVED [S28]:** Workers: 128 MB per isolate, CPU 30 s default up to 5 min, unlimited wall clock while the client
  is connected, 10,000 subrequests (Paid), 6 simultaneous outgoing connections, 64 MiB script.
- **INFERRED:** one gateway, in Workers. Supabase is used for Auth, Postgres, Realtime and Postgres-function hooks
  (custom access token, before-user-created [L1]). Edge Functions are optional for a Supabase-native need such as a
  Send Email hook; zero are required for v1. Two gateways would split authorization logic.

---

## 12. Limits and prices table (all OBSERVED on 2026-10-07 unless marked)

| Service | Limit / price | Value | Source |
|---|---|---|---|
| Supabase Auth | Built-in email sends | 2/hour (custom SMTP required for real use) | [S11] |
| | OTP request window / default expiry | 60 s / 1 h | [S3] |
| | Anonymous sign-ins | 30/hour/IP default | [S2][S11] |
| | Token endpoint | 150 per 5 min, burst 30 | [S11] |
| | Access token lifetime | 3,600 s default, max 604,800 s (local config) | [L1] |
| | Legacy anon/service_role keys | Deprecated by end of 2026 | [S7] |
| Supabase plans | Pro | $25/month; $10 compute credit; 100,000 MAU (incl. anonymous) then $0.00325; 8 GB disk; 250 GB egress; 2 M Edge invocations | [S26] |
| | Free | 50,000 MAU; 500 MB DB; paused after 1 week inactive | [S26] |
| Supabase Realtime | Pro connections / msgs/s / presence msgs/s | 500 / 500 / 50 | [S24] |
| | Presence keys per object; broadcast payload (Pro) | 10; 3,000 KB | [S24] |
| Supabase Edge Functions | CPU / wall / memory | 2 s / 150 s Free, 400 s Paid / 256 MB | [S25] |
| pgvector | Indexable dims | vector 2,000; halfvec 4,000 | [S21] |
| Workers | Request body (zone plan) | 100 MB Free/Pro, 200 MB Business, up to 5 GB Enterprise | [S28] |
| | CPU per request | 10 ms Free; 30 s default, 5 min max Paid | [S28] |
| | Memory | 128 MB per isolate | [S28] |
| | Paid pricing | $5/month; 10 M requests + 30 M CPU-ms included; $0.30/M requests; $0.02/M CPU-ms | [S29] |
| R2 | Object max / single PUT / parts | 5 TiB / 5 GiB / 10,000 parts, 5 MiB–5 GiB, equal size except last | [S33][S35] |
| | Presigned URL expiry; domain | 1 s–7 days; S3 endpoint only | [S30] |
| | Writes to same key | 1/s | [S35] |
| | Default incomplete-MPU abort; lifecycle rules | 7 days; 1,000 rules/bucket, act within ~24 h | [S33][S36] |
| | Standard storage / Class A / Class B | $0.015/GB-month / $4.50/M / $0.36/M; egress free; free tier 10 GB-month, 1 M A, 10 M B; usage rounded up to next unit | [S38] |
| | Infrequent Access minimum duration | 30 days | [S38] |
| Queues | Message size / batch / retries | 128 KB / 100 / default 3, max 100 | [S40][S41] |
| | Retention | 4 days default, 14 max (Paid); 24 h (Free) | [S40][S45] |
| | Throughput / backlog / concurrency | 5,000 msg/s / 25 GB / 250 push consumers | [S40] |
| | Pull visibility timeout / delay | 12 h / 24 h | [S40] |
| | Price | 1 M ops/month included, then $0.40/M ops (≈3 ops per message) | [S45] |
| Durable Objects (SQLite) | Storage per object; key+value | 10 GB; 2 MB | [S46] |
| | Alarms | One per object, at-least-once, 6 retries from 2 s | [S47] |
| | Price (Paid) | 1 M requests + 400,000 GB-s included; $0.15/M; $12.50/M GB-s | [S29] |
| Workflows | Step CPU / step result / event payload / state | 30 s default to 5 min / 1 MiB / 1 MiB / 1 GB | [S48] |
| | Steps per workflow; concurrency | 10,000 default (25,000 max); 50,000 running instances (page text also says 10,000: inconsistent) | [S48] |
| | Completed-state retention (Paid) | 30 days | [S48] |
| | Price | 10 M requests, 30 M CPU-ms, 500,000 steps included; $0.80 per extra 100,000 steps | [S29] |
| Containers | Largest preset / custom max | standard-4: 4 vCPU, 12 GiB, 20 GB; custom ≤4 vCPU, 12 GiB, 20 GB | [S52] |
| | Account concurrency | 1,500 vCPU, 6 TiB memory, 30 TB disk; 50 GB images | [S52] |
| | Stop grace | SIGTERM, up to 15 min, then SIGKILL; disk ephemeral | [S54] |
| Cloud Run Jobs | Task timeout | 168 h (GPU 1 h) | [S75] |
| Remotion | Free licence | ≤3 people incl. contractors (5.0) | [S66][S68][S70] |
| | Automators | $0.01/render, $100/month minimum | [S67] |
| | Lambda | 15 min, 10 GB RAM, 10 GB /tmp | [S71] |
| Claude API | Images per request / size | 600 (1M-context models); ≤2000 px when >20; 10 MB each; 32 MB request | [S78] |

INFERRED arithmetic refresh of the brief's media numbers: six 3.6 GB sources at 32 MiB parts = 648 `UploadPart` +
12 create/complete ≈ 660 Class A operations ≈ $0.003 (inside the free 1 M/month); seven-day storage of 21.6 GB is
$0.0756 unrounded as the brief says, but R2 rounds billed GB-months up to whole units [S38], so a small account's bill
moves in $0.015 steps.

---

## 13. Testing every piece locally, without provisioning

Tools present on this machine (OBSERVED [L2]): Supabase CLI 2.100.1, Docker 29.4.1, Node 26.8.2, Deno 2.9.6,
FFmpeg/ffprobe 9.0.1. Not present: Wrangler (a project devDependency later), `psql`, `pg_prove` (not needed;
`supabase test db` runs pgTAP inside the stack).

| Piece | Local harness | What a passing run proves | Remains UNVERIFIED until activation |
|---|---|---|---|
| Schema, RLS, helpers | `supabase start` (Docker; OrbStack recommended on macOS [S14]) → `supabase db reset` → `supabase test db` with pgTAP files in `supabase/tests/database/` and basejump test helpers (`tests.create_supabase_user`, `tests.authenticate_as`, `tests.clear_authentication`, `tests.rls_enabled`); setup file `000-setup-tests-hooks.sql`; each test in `begin … rollback` [S12][S13] | Owner, unrelated user, camera uploader, coach, viewer, anonymous and unauthenticated roles see exactly what the access matrix allows; no recursion; owner_id immutable | Hosted-project settings drift |
| Security lints | `supabase db advisors --local --type security --fail-on warn` [L1]; `splinter.sql` as a fallback [S18] | No `0013_rls_disabled_in_public`, `0011_function_search_path_mutable`, `0015_rls_references_user_metadata`, definer-function exposure | — |
| Email OTP | Local Auth + Mailpit `127.0.0.1:54324` [S15] | Sign-in, allow-list rejection, 60 s window, expiry | Custom SMTP deliverability |
| Anonymous (test only) | `enable_anonymous_sign_ins = true` in local config [L1] | `is_anonymous` restrictive policies hold | CAPTCHA integration |
| SIWA | Unit tests for nonce and first-sign-in name capture | Client logic | Entire Apple exchange and token revocation |
| JWT verification | Local ES256 key via `supabase gen signing-key --algorithm ES256` + `signing_keys_path` [S16][L1]; gateway tests fetch local JWKS | Issuer pinning, alg pinning, expiry, forged and demo tokens rejected | Hosted JWKS caching behaviour |
| Realtime lobby | Local stack Realtime; integration test with two clients; pgTAP on `realtime.messages` policies | Private channel denial for non-members; presence shape | Plan-limit behaviour, poor-network behaviour |
| pgvector | Local Postgres 17 [L1] with fixed vectors | No cross-tenant retrieval; iterative scan returns k rows under RLS | Embedding quality |
| Gateway Worker | `@cloudflare/vitest-plugin` (Miniflare) [S58][S59]: R2 binding multipart, `createMessageBatch`/`getQueueResult` for queues, `runDurableObjectAlarm`, Workflow introspection with `mockStepError`, `forceStepTimeout`, `mockEvent` [S60]; outbound fetch mocked with `@msw/cloudflare` [S59]; Hyperdrive `localConnectionString` to `127.0.0.1:54322` [S64] | Upload session lifecycle, wrong-project completion refused, revoked session stops next part, duplicate job requests create one Workflow, retries never double-reserve, cancel path | Real throughput, zone body limits, hosted Hyperdrive ↔ Supabase |
| Known harness gaps | Fake timers do not apply to R2/KV simulators; DO WebSockets need `--max-workers=1 --no-isolate`; V8 coverage unsupported (use Istanbul) [S61] | — | — |
| Direct-to-R2 signing | Deterministic unit tests of aws4fetch SigV4 output with a fixed clock [S39]; no local S3 endpoint is documented (INFERRED) | Signing code is stable | Presigned `UploadPart`, temporary credentials, account-ID URLs: one spike on a real test bucket |
| Lifecycle / events | Unit-test the event consumer with synthetic `object-create`/`object-delete` messages [S37] | Rows reconcile | Real rule timing (~24 h) |
| Render host | Same Docker image locally with FFmpeg and ADR-0012 synthetic fixtures; storage adapter pointed at a local directory; `wrangler dev` runs Containers locally when Docker is running [S55] | Normalize, assemble, verify; SIGTERM mid-stage restarts cleanly; stage outputs keyed by input hash | Runtime per stage at 4 vCPU, cost per film |
| Planner | Recorded fixture responses only (no API calls); adversarial fixtures (shell strings, unknown ops, out-of-window cuts, invented metric numbers) must fail `tools/studio-plan` validation | Validation boundary | Live model behaviour and spend |
| Native client | `URLProtocol` stub of the gateway, as ADR-0008 does for Drive | Resume after kill, part retry, verification states | Background `URLSession` scheduling on device |

Acceptance-evidence mapping (from the expansion prompt): cross-project metadata and media refusal, expired-invite
reuse, wrong-project upload completion, stale signed grants and forged demo sessions are all covered by the first,
sixth and eighth rows locally; physical-device and hosted behaviour stay separately reported.

---

## 14. Recommended decisions

1. Adopt the topology in section 2: Supabase (Auth, Postgres + RLS, optional Realtime) as metadata authority; one
   Cloudflare gateway Worker; private R2; Workflows for job orchestration with Postgres as the ledger; Queues + DLQ for
   render-work dispatch; FFmpeg-first render host on Cloudflare Containers for S4, with Cloud Run Jobs as the fallback.
2. Default uploads go through the gateway with R2-binding multipart and fixed 32 MiB parts; keep a target-agnostic part
   protocol so direct-to-R2 can replace it after a spike.
3. A source is "verified" only after a server-side SHA-256 of the stored bytes matches the manifest (R2 cannot attest
   a whole-object SHA-256 for multipart).
4. Use publishable/secret keys and ES256 asymmetric JWT signing from the start; the gateway verifies via JWKS with the
   issuer pinned per environment; the secret key stays off hot paths.
5. Roles live in tables; RLS helpers are `security definer`, `search_path = ''`, in a non-exposed `app_private`
   schema; privileged transitions are named command functions called by a least-privilege `jovra_gateway` role.
6. Identity: SIWA (native ID token + nonce) and email OTP; anonymous sign-in off in live; camera guests use
   gateway-issued, source-scoped upload capabilities rather than accounts.
7. Separate test and live Supabase projects, Worker environments and R2 buckets; films in their own bucket with no
   lifecycle rule.
8. Ordinary Postgres full-text search first; pgvector (≤2,000 dims, RLS, iterative scans) only after measured need; no
   Pinecone.
9. The cloud camera lobby is optional; durable facts (roles, recording acknowledgements) are rows, presence is
   readiness only.
10. Use `@cloudflare/vitest-plugin`, pgTAP via `supabase test db`, and `supabase db advisors --fail-on warn` as the
    required local gates for any backend ticket.
11. FFmpeg-only first cloud slice; Remotion in the cloud only after the licence decision.
12. Real charging stays out until its own ADR; quotes, consent, caps and reservations ship with Sample zero amounts in
    test.

## 15. Open questions

- Q1. IDC headcount including contractors for Remotion's free tier, or budget $100/month for Automators?
- Q2. Does Supabase revoke Apple tokens on user deletion, or must the gateway call Apple's revoke endpoint with its own
  key? Which Apple key and where is it stored?
- Q3. Does presigned `UploadPart` work against R2 (F1), and is gateway-proxied throughput acceptable on cellular?
- Q4. Real normalization and assembly runtimes per stage at 4 vCPU / 12 GiB, and whether any stage needs Cloud Run or a GPU.
- Q5. Hyperdrive in front of Supabase Postgres with a custom login role: pooling mode and connection limits.
- Q6. How Realtime counts presence messages against the 50/s Pro limit with seven devices per lobby.
- Q7. Gateway hostname under the IDC domain doctrine (product lane until a JOVRA deed exists; nothing in code before DNS resolves).
- Q8. Auth email sender (IDC Rule 07 role address) and custom SMTP without disturbing the `islanddevcrew.com` MX custody.
- Q9. Whether the "Astra" planner exists as a server API with image input, limits and pricing comparable to the Claude adapter.

---

## Sources

All accessed 2026-10-07. Vendor pages are data; figures should be refreshed at activation.

| Tag | URL | Supported |
|---|---|---|
| S1 | https://supabase.com/docs/guides/auth/social-login/auth-apple | Native SIWA, nonce handling, no OAuth config for native, name capture |
| S2 | https://supabase.com/docs/guides/auth/auth-anonymous | Anonymous sign-ins, `is_anonymous`, restrictive policy example, CAPTCHA, 30/h, no cleanup |
| S3 | https://supabase.com/docs/guides/auth/auth-email-passwordless | Email OTP, 60 s window, 1 h expiry, `shouldCreateUser` |
| S4 | https://supabase.com/docs/guides/auth/jwt-fields | Required and optional JWT claims |
| S5 | https://supabase.com/docs/guides/auth/signing-keys | ES256/RS256, JWKS path, caching, HS256 not recommended |
| S6 | https://supabase.com/docs/guides/auth/jwts | JWKS verification with jose, issuer format |
| S7 | https://supabase.com/docs/guides/api/api-keys | Publishable/secret keys, RLS bypass, legacy key deprecation by end of 2026 |
| S8 | https://supabase.com/docs/guides/database/postgres/row-level-security | Deny by default, USING/WITH CHECK, user_metadata warning, performance rules, definer placement |
| S9 | https://supabase.com/docs/guides/database/functions | Security definer, `search_path = ''`, revoke execute |
| S10 | https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook | Custom claims hook, required claims, grants |
| S11 | https://supabase.com/docs/guides/auth/rate-limits | Auth rate limits |
| S12 | https://supabase.com/docs/guides/local-development/testing/overview | `supabase test db`, pgTAP, role simulation, CI |
| S13 | https://supabase.com/docs/guides/local-development/testing/pgtap-extended | basejump test helpers, file ordering |
| S14 | https://supabase.com/docs/guides/local-development | Container runtimes, local stack |
| S15 | https://supabase.com/docs/guides/local-development/cli/getting-started | Local ports, Mailpit, CLI commands |
| S16 | https://supabase.com/docs/reference/cli/supabase-gen-signing-key | `supabase gen signing-key` |
| S17 | https://supabase.com/docs/guides/database/database-advisors | Security lint names, `supabase db advisors` |
| S18 | https://github.com/supabase/splinter | `splinter.sql` single-file lints |
| S19 | https://supabase.com/docs/guides/ai/rag-with-permissions | Permissioned RAG with RLS |
| S20 | https://supabase.com/docs/guides/database/extensions/pgvector | Enabling pgvector, filtered-index caveat |
| S21 | https://github.com/pgvector/pgvector | Dimension limits, iterative index scans |
| S22 | https://supabase.com/docs/guides/realtime/presence | Presence mechanics |
| S23 | https://supabase.com/docs/guides/realtime/authorization | Private channels, `realtime.messages` RLS, cached policies |
| S24 | https://supabase.com/docs/guides/realtime/limits | Realtime limits by plan |
| S25 | https://supabase.com/docs/guides/functions/limits | Edge Function limits |
| S26 | https://supabase.com/pricing | Plan prices and quotas |
| S27 | https://supabase.com/docs/guides/queues | Supabase Queues (pgmq) as an alternative |
| S28 | https://developers.cloudflare.com/workers/platform/limits/ | Worker limits |
| S29 | https://developers.cloudflare.com/workers/platform/pricing/ | Workers, DO, Queues, Workflows pricing |
| S30 | https://developers.cloudflare.com/r2/api/s3/presigned-urls/ | Presigned URL methods, expiry, domain, Content-Type pinning |
| S31 | https://developers.cloudflare.com/r2/api/s3/temporary-credentials/ | Temporary credentials, scoping, revocation via parent |
| S32 | https://developers.cloudflare.com/r2/api/s3/api/ | S3 compatibility, checksum types, UploadPart replacement behaviour |
| S33 | https://developers.cloudflare.com/r2/objects/multipart-objects/ | Part rules, 7-day abort, multipart ETags |
| S34 | https://developers.cloudflare.com/r2/api/workers/workers-multipart-usage/ | Multipart through a Worker binding |
| S35 | https://developers.cloudflare.com/r2/platform/limits/ | R2 limits, r2.dev not for production |
| S36 | https://developers.cloudflare.com/r2/buckets/object-lifecycles/ | Lifecycle rules, timing, rule count |
| S37 | https://developers.cloudflare.com/r2/buckets/event-notifications/ | Event types and message format |
| S38 | https://developers.cloudflare.com/r2/pricing/ | R2 prices, rounding, operation classes, IA minimum |
| S39 | https://developers.cloudflare.com/r2/examples/aws/aws4fetch/ | aws4fetch signing and presigning |
| S40 | https://developers.cloudflare.com/queues/platform/limits/ | Queue limits |
| S41 | https://developers.cloudflare.com/queues/configuration/batching-retries/ | Batching, retries, delays |
| S42 | https://developers.cloudflare.com/queues/configuration/dead-letter-queues/ | DLQ behaviour |
| S43 | https://developers.cloudflare.com/queues/reference/delivery-guarantees/ | At-least-once, idempotency keys |
| S44 | https://developers.cloudflare.com/queues/configuration/pull-consumers/ | HTTP pull consumers |
| S45 | https://developers.cloudflare.com/queues/platform/pricing/ | Queue pricing and retention |
| S46 | https://developers.cloudflare.com/durable-objects/platform/limits/ | DO limits |
| S47 | https://developers.cloudflare.com/durable-objects/api/alarms/ | DO alarms |
| S48 | https://developers.cloudflare.com/workflows/reference/limits/ | Workflow limits |
| S49 | https://developers.cloudflare.com/workflows/build/sleeping-and-retrying/ | Step retry defaults |
| S50 | https://developers.cloudflare.com/workflows/build/events-and-parameters/ | `waitForEvent`, timeouts |
| S51 | https://developers.cloudflare.com/workflows/build/workers-api/ | `create` vs `createBatch` idempotency, pause/terminate/restart |
| S52 | https://developers.cloudflare.com/containers/platform-details/limits/ | Container instance types and account limits |
| S53 | https://developers.cloudflare.com/containers/pricing/ | Container pricing |
| S54 | https://developers.cloudflare.com/containers/platform-details/architecture/ | Lifecycle, ephemeral disk, SIGTERM grace, cold starts |
| S55 | https://developers.cloudflare.com/containers/local-dev/ | Local container development with Docker |
| S56 | https://developers.cloudflare.com/changelog/product/containers/ | GA on 2026-04-13, recent features |
| S57 | https://developers.cloudflare.com/changelog/post/2025-11-21-fuse-support-in-containers/ | R2 FUSE mounts |
| S58 | https://developers.cloudflare.com/workers/testing/vitest-integration/ | Vitest integration, Miniflare |
| S59 | https://developers.cloudflare.com/workers/testing/vitest-integration/migration-guides/migrate-to-vitest-plugin/ | Package rename, `@msw/cloudflare` |
| S60 | https://developers.cloudflare.com/workers/testing/vitest-integration/test-apis/ | Queue, DO alarm and Workflow test APIs |
| S61 | https://developers.cloudflare.com/workers/testing/vitest-integration/known-issues/ | Harness gaps |
| S62 | https://developers.cloudflare.com/workers/testing/miniflare/ | Miniflare scope |
| S63 | https://developers.cloudflare.com/workers/development-testing/ | Local vs remote bindings |
| S64 | https://developers.cloudflare.com/hyperdrive/configuration/local-development/ | Hyperdrive `localConnectionString` |
| S65 | https://developers.cloudflare.com/workers/configuration/secrets/ | Worker secrets, `.dev.vars` |
| S66 | https://github.com/remotion-dev/remotion/blob/main/LICENSE.md | Free/Company licence terms |
| S67 | https://www.remotion.pro/license | Automators pricing |
| S68 | https://www.remotion.dev/docs/license/faq | Automation definition, render counting, contractors |
| S69 | https://www.remotion.dev/docs/licensing/ | `licenseKey` telemetry, mandatory for Automators in 5.0 |
| S70 | https://github.com/remotion-dev/remotion/pull/3750 | Remotion 5.0 licence changes |
| S71 | https://www.remotion.dev/docs/lambda/limits | Lambda limits |
| S72 | https://www.remotion.dev/docs/lambda/cost-example | Lambda cost examples |
| S73 | https://www.remotion.dev/docs/compare-ssr | SSR option comparison |
| S74 | https://www.remotion.dev/docs/docker | Self-hosted Remotion in Docker |
| S75 | https://docs.cloud.google.com/run/docs/configuring/task-timeout | Cloud Run task timeout |
| S76 | https://cloud.google.com/run/pricing | Cloud Run unit prices (via search-result snippet; refresh) |
| S77 | https://docs.fly.io/about/pricing | Fly Machines pricing |
| S78 | https://platform.claude.com/docs/en/build-with-claude/vision | Image limits, token formula, no video input documented |
| S79 | https://platform.claude.com/docs/en/about-claude/models/overview | Model ID and price (read from the bundled Claude API reference, cached 2026-09-25) |
| S80 | https://developer.apple.com/app-store/review/guidelines/ | 5.1.1(v) account deletion, 4.8 login services |
| S81 | https://developer.apple.com/support/offering-account-deletion-in-your-app/ | SIWA token revocation on deletion |
| S82 | https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:) | Background session behaviour, force-quit cancellation, discretionary scheduling |
| L1 | Local: `supabase init` (CLI 2.100.1) in the session scratchpad; `supabase db advisors --help`; `supabase gen signing-key --help` | Default config values, advisor flags |
| L2 | Local: `command -v` / `--version` checks | Installed tools |
| L3 | /Users/IDC2.5/jv/design-reference/studio/brief/backend-media-design.md, implementation-states.md, screens.json; docs/handoff/studio/*; .claude/skills/jovra-*; tools/studio-plan/; docs/adr/0002, 0008, 0013 | Baseline design being verified |
| L4 | /Users/IDC2.5/Desktop/you-link-x/garnet-remotion/package.json and PIPELINE.md (read-only) | Remotion 4.0.523 pin; assembler preconditions |
