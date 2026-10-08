# Cloud media security: RLS guards rows, a signing gateway guards every R2 object

Status: accepted (2026-10-07); amended 2026-10-07 after review round 2 (two Worker scripts; download wording; guest
approval step).

Postgres row-level security (RLS) protects database rows and nothing else. It does not protect R2, so JOVRA uses two
independent locks:

- **Rows.** Every exposed table has RLS enabled and denies by default. Explicit SELECT, INSERT, UPDATE and DELETE
  policies check both the existing row and the resulting row. **Roles live in tables** (`project_members` and grant
  rows), never in JWT claims, because a claim stays frozen until the token refreshes and that would delay revocation.
  Policies read only `auth.uid()` and `is_anonymous`, never `user_metadata`. Permission helpers are `security
  definer` functions with an empty `search_path`, kept in a non-exposed `app_private` schema. Privileged changes
  (accepting a quote, completing an upload, making a job transition) are named functions. User routes call them
  as a least-privilege `jovra_gateway` database role. Orchestration (job transitions, stage reservations, leases,
  render-output uploads, artifact verification) runs as `jovra_orchestrator` in a **separate Worker script**
  (`jovra-internal`: the Workflow, the queue consumer and the render-host routes), which alone holds that Hyperdrive
  binding and the host secret; the user-facing gateway reaches it only through a service binding that exposes no
  orchestration method, so a bug or a compromised dependency in a user route cannot move a job or verify an artifact.
  Each command is executable by exactly one of the two roles. Both connect through Hyperdrive with query caching
  **disabled** (OBSERVED: on by default, 60 s, https://developers.cloudflare.com/hyperdrive/concepts/query-caching/),
  never with the Supabase secret key. A PostgREST-with-secret-key fallback is not covered by this ADR; it needs its
  own amendment (`docs/backend/security-model.md` §3).
- **Media.** R2 buckets are private, with no public bucket and no `r2.dev` URL. The Cloudflare **signing gateway**
  Worker is the only path to an object. On every operation it:
  - verifies the user's ES256 JWT against Supabase JWKS, with `iss` and `alg` pinned;
  - re-checks current membership and the exact source or artifact grant in Postgres;
  - generates object keys on the server, never accepting a bucket, key or URL from a client;
  - issues **short-lived, exact-object, single-operation capabilities**.

**Uploads** pass through the gateway as R2 multipart uploads with fixed 32 MiB parts, under the 100 MB Worker
request-body limit. The gateway streams each part to R2 through a hashing tee and never buffers a part or an original.
This deviates from the backend brief's "directly in bounded multipart parts, not through an in-memory Worker buffer"
on the routing (not the buffering) and is recorded in the spec's conflicts list. Each part is authorized separately,
and revocation takes effect immediately. A source has one open upload session at a time, each session writes its own
key, and the object that was verified is pinned by its etag for every later read. The part protocol
does not depend on where parts go, so direct-to-R2 uploads (presigned part URLs or R2 temporary credentials) can
replace it after a spike. Presigning `UploadPart` is UNVERIFIED.

On completion, the gateway rejects stale sessions, parts from another project and byte counts that do not match. A
source is marked **verified** only after the server re-hashes the stored bytes and the SHA-256 matches the source
manifest. R2 cannot attest a whole-object SHA-256 for multipart uploads (OBSERVED, backend-architecture F4).

**Downloads** stream through the gateway by default, with the grant re-checked on every request and no bearer
capability leaving it. An optional presigned GET, adopted only after the spike, lasts at most 5 minutes. An
application share link can last up to 24 h, but it is redeemed through the gateway, which re-checks it each time. Already issued presigned URLs cannot be revoked (OBSERVED,
F1), so the product never promises instant revocation of them.

**Never in a client:** the Supabase secret key (the legacy `service_role` key), R2 parent credentials, the render
host's HMAC secret, or a model key. The app holds only the publishable key and the base URLs. A **camera guest**
gets no account. It gets a project-, source- and device-scoped upload capability only after three steps: it redeems
the invite with a fresh device key, the host compares the six-digit code derived from that key's thumbprint on both
phones and approves, and the guest proves possession of the key (`docs/backend/architecture.md` §6.1,
`security-model.md` §8.2). Redemption alone grants nothing. A
guest can upload its assigned source but cannot browse anyone else's footage. Sharing one lesson clip shares that
clip only, never the match.

**Tenant isolation** covers every place data lives: metadata, originals, proxies, frames, thumbnails, vectors,
films, queue messages and logs. Queue messages carry only an attempt ID, never media, signed URLs, lease tokens,
input lists or output plans. The host claims the attempt through an internal route; the lease token is minted at
claim time and stored only as a hash, and the attempt's inputs and outputs come from the `render_attempts` row that
`reserve_stage` computed from the job's own project. The render host reads exact objects for its leased job, writes
only new keys and cannot raise a budget or publish.
Deletion cancels jobs and removes cloud copies. It never deletes local originals unless the user chooses that
separately.

## Considered Options

- **Supabase Storage for media.** Rejected. It would mirror multi-GB originals into a second store, and R2 has free
  egress.
- **RLS-only security with public or long-lived media URLs.** Rejected because R2 is outside RLS.
- **Roles in custom JWT claims.** Rejected because revocation would lag until the token refreshes (default 1 h).
- **Anonymous Supabase sessions for camera guests.** Rejected. It adds MAU and abuse surface, needs a CAPTCHA, and
  gives guests access to PostgREST.

## Consequences

Each backend ticket must pass local checks: pgTAP under real roles (owner, unrelated user, camera uploader, coach,
viewer, unauthenticated), `supabase db advisors --fail-on warn`, and gateway tests in `@cloudflare/vitest-plugin`.
Uploads that go through the gateway cost Worker CPU and request time. That cost is accepted until a measured spike
justifies direct uploads.

Sources: https://supabase.com/docs/guides/database/postgres/row-level-security ;
https://supabase.com/docs/guides/database/functions ; https://supabase.com/docs/guides/api/api-keys ;
https://supabase.com/docs/guides/auth/signing-keys ; https://developers.cloudflare.com/r2/api/s3/presigned-urls/ ;
https://developers.cloudflare.com/r2/api/s3/temporary-credentials/ ;
https://developers.cloudflare.com/r2/api/workers/workers-multipart-usage/ ;
https://developers.cloudflare.com/r2/objects/multipart-objects/ ;
https://developers.cloudflare.com/workers/platform/limits/ ; `docs/research/studio/backend-architecture.md` §§1, 4, 7.
