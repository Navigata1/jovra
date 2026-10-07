# JOVRA Studio — cloud, media and integration design

Status: proposed design, October 7, 2026. No live backend, billable job or integration was provisioned or verified in this task.

## Recommended division of responsibility

- SwiftUI/AVFoundation and later Kotlin/Compose/CameraX: independent local capture, project documents, event-derived scores, offline replay and lesson journal.
- Supabase Auth/Postgres: optional identities, project membership, lesson metadata, cloud job ledger, source manifests, film versions, access grants and usage accounting.
- Cloudflare Worker: authenticate requests, enforce project access, issue bounded media capabilities, accept idempotent job requests and coordinate jobs.
- Private Cloudflare R2 Standard buckets: staged originals, analysis proxies, reviewed results, thumbnails and finished films. Upload media directly in bounded multipart parts, not through an in-memory Worker buffer.
- Cloudflare Queues plus durable job state: enqueue job identifiers and manifest references, never whole video bytes. Consumers hand heavy work to a separately provisioned container/VM renderer.
- FFmpeg/ffprobe plus new Remotion tennis compositions: normalize media, cut/assemble, render overlays and verify exports. A separate measured vision worker may use a GPU; ordinary editing must not require a GPU by assumption.
- Configurable multimodal planner: propose source-linked observations and a typed edit decision list. “Astra” and “Opus” are preference labels to map to actually available server APIs and pinned model versions when provisioned. Do not invent an API identifier, video support, entitlement, price or ability to render pixels. Feed supported sampled frames/clips and structured events within verified limits.
- Optional pgvector later: authorized search over lesson notes and clip descriptions. No vector database is necessary for score calculation, replay or editing. Start with ordinary Postgres search; if embeddings add measured value, use Supabase pgvector before introducing Pinecone.

Recommendation: retain Supabase as the metadata authority and R2 as the large-video store. Do not mirror every original into both Supabase Storage and R2. User-owned iCloud Drive, Google Drive, Box and Dropbox are archive/import providers, not the cloud compute engine. Keep provider credentials separate from JOVRA identity.

Sources: [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [permissioned vectors](https://supabase.com/docs/guides/ai/rag-with-permissions), [R2 multipart uploads](https://developers.cloudflare.com/r2/objects/upload-objects/), [Worker limits](https://developers.cloudflare.com/workers/platform/limits/), [queue limits](https://developers.cloudflare.com/queues/platform/limits/), [Remotion rendering](https://www.remotion.dev/docs/renderer/render-media).

## Demo, tester and live identity

Three explicit environments: local demo, isolated test backend, live backend. The demo is an in-process adapter with fictional data and no network, tokens, uploads or charges. Provide a “Use demo profile” action rather than a hardcoded production password. If credentials are needed for an isolated tester environment, seed them through configuration, keep secrets out of source, and remove the fixture login from production builds. The UI must distinguish demo authentication from a real Supabase session. Never accept demo tokens or UI role flags at the cloud API.

Local documents use stable UUIDs. Opt-in account connection links selected local projects to a cloud owner without deleting or rewriting originals. A reviewed migration maps local IDs to cloud IDs, records document revisions and retains offline access after sign-out. A local edit cannot silently overwrite a newer cloud revision: show conflict and retain both until resolved.

## Suggested metadata model

profiles; projects; project_members; camera_sources; sync_maps; calibration_versions; point_event_revisions; observations; lessons; lesson_clips; story_plans; story_plan_versions; render_jobs; render_attempts; artifacts; access_grants; usage_reservations; provider_connections; deletion_requests; audit_events.

Every cloud object belongs to a project or user with enforced foreign keys. Every film records source hashes, point-event revision, sync/calibration revision, story profile and version, planner model/version, deterministic edit-plan hash, renderer version and result hash. Corrections invalidate stale overlays and derived films; keep earlier films as labelled historical versions until deliberately deleted.

## Access policy specification

| Actor | Read | Write | Spend or publish |
|---|---|---|---|
| Local demo | Local fictional fixtures only | Local demo only | Never |
| Unauthenticated | No project records or media | None | Never |
| Owner | Own project and chosen sources | Membership, source grants, point corrections, film settings | May accept quote/start private render; publication separately |
| Invited camera uploader | Invite metadata and its own assigned upload receipts | Assigned source parts only, until expiry/revocation | Never |
| Coach/editor | Explicit shared project/lesson clips | Notes or story drafts within assigned role | Only owner can approve spend or public sharing |
| Viewer | Explicit selected film or lesson grant | None | Never |
| Render service | Inputs for assigned job, for bounded duration | Assigned derived artifacts and trusted job status | Cannot raise budget or publish |

Implementation requirements:
- Deny by default. Enable RLS on exposed tables; write explicit SELECT, INSERT, UPDATE and DELETE policies with both existing-row and resulting-row checks where needed.
- Membership roles come from trusted rows. A client cannot change owner_id, grant itself a role, edit someone else’s project_id, or create an unbounded billing reservation.
- Avoid recursive membership policies: use a carefully scoped helper/ownership lookup with fixed search path and explicit privileges. Test the helper under real auth roles.
- RLS covers Postgres, not R2. The signing gateway must independently authorize each R2 object/operation against current membership and source grants. Never accept arbitrary bucket/key/URL from a client.
- R2 keys are server-generated; signed capabilities include exact key/operation, size/type constraints where supported and short expiry. Validate part manifest and byte count at completion; reject mixed-project parts and stale upload sessions.
- A shared application link can expire after 24 hours. Redeem it through an access-checking gateway; underlying media URLs should be much shorter-lived. Revocation stops new capabilities, but already issued direct presigned URLs remain usable until expiry. Do not promise immediate revocation of those URLs.
- Service credentials stay server-side. Workers verify token signature, issuer, audience and expiry; permission checks are repeated before upload signing, job creation and delivery. A privileged service-role database connection bypasses RLS and therefore needs explicit scoped authorization.
- Encrypt transport, sanitize logs, limit parser/render resources, and sandbox untrusted media. The model returns validated data, never executable shell or arbitrary FFmpeg commands.
- Tenant isolation must hold for metadata, originals, proxies, thumbnails, vector retrieval, exported films, queue messages and logs.

## Job state and money

State machine:
draft → quoted → consented → upload_pending → uploading → queued → normalizing → syncing → analyzing → planning → preview_rendering → awaiting_review → final_rendering → verifying → ready.

Terminal or resumable paths: paused, canceled, failed_retryable, failed_terminal, quote_expired, budget_exceeded, deleted. Unavailable analysis may produce a manual-review fallback without blocking playback.

The simple flow creates a private preview automatically after profile selection and valid quote acceptance. Offer optional review for uncertain synchronization/observations and editable story beats. Rendering a new revision must have its own bounded reservation; retries under the same idempotency key must not charge twice. Owner can cancel queued work; work already consumed remains accounted for.

Preflight shows upload size, storage duration, output dimensions/duration, estimated compute and model usage, quote expiry and maximum authorized cost. Reserve maximum exposure before work; check budget before each stage, including retries. Never auto-upgrade to a more expensive model or extend retention. Keep actual usage separate from estimate, and show service fees/tax only once their actual policy exists. Mock quotes must stay marked Sample.

Implement leases, heartbeats, idempotent stage results, a transactional job outbox or reconciler, dead-letter handling, safe retry, partial upload resume, orphan cleanup, notifications through platform-supported push only when wired, and deletion that cancels jobs and removes temporary copies. A phone may suspend; server jobs must not depend on its UI staying open.

## Storage providers

Uniform archive interface: capability status, account/folder selection, read/write/resume, quota, disconnected/expired token handling, sidecar version and integrity checks. iCloud Drive via Files/document picker can be an initial folder export; this is not Android iCloud support or CloudKit sync. Google Drive, Box and Dropbox need their own verified integrations and scopes later. Import is allowed from any accessible Files provider without pretending dedicated OAuth integration exists.

Cloud opt-in is per selected project/source. Archives, backups, render staging, final films and public publishing are separate choices. Proposed staging retention: seven days, clearly editable/confirmed at preflight; abandoned multipart uploads need lifecycle cleanup. Final films have an explicit retention choice and deletion path. Cloud deletion does not delete local originals unless the user independently selects that action.

## Synchronization and analysis boundaries

Save each phone’s source PTS/timebase, wall-clock hints, monotonic capture time, start/stop/restart segments, audio availability, lens/rotation, frame rate, resolution and source hash. A host start command and shared join code coordinate people but do not provide frame-accurate hardware synchronization.

Estimate source-to-session time from a shared visible/audio cue and corroborating anchors. Distance-dependent sound arrival can bias alignment; inspect matching visible events too. Estimate offset and drift, use piecewise maps around discontinuities, and record residuals/confidence. If audio is absent, use a visual cue or manual marker. Review alignment at start/middle/end and every restart. No extrapolated playback through missing coverage.

Normalize VFR, rotation and HDR into compatible analysis/render proxies with an explicit original-PTS ↔ proxy-frame mapping. Keep original hashes; never substitute a normalized proxy as the original. The existing strict constant-frame assembler can receive normalized sources once they pass its real checks; do not relax its invariants invisibly.

Selectable recorded perspectives are feasible design goals. Seamless free-camera 3D, six-view live inference, reliable high-speed ball tracking, spin RPM, biomechanical measurements and officiating-grade line calls are not assumed. A planar court homography maps ground contacts; it cannot by itself give a flying ball’s 3D position or trustworthy velocity. Multiple-camera triangulation is a separate benchmarked capability requiring camera calibration, matched timing, correspondence and uncertainty. Local live analysis should use the primary feed; full multi-angle processing runs after capture.

An interactive project retains the synchronized sources and event index. A downloaded MP4 is a flattened chosen edit; it cannot retain the same arbitrary angle switching. Export both the film and, optionally, a portable project bundle.

## Cost model — arithmetic, not a vendor quote

Pricing checked October 7, 2026:
- R2 Standard list storage $0.015 per GB-month; direct R2 egress free, but connected compute/providers can charge separately.
- Supabase Pro starts at $25/month; Workers Paid has a $5/month minimum. Existing account plans and incremental cost were not inspected.
- Queue operations have a separate meter; the video compute provider, model tokens and renderer licensing are not included in those base fees.

Assume each camera records 60 minutes at 8 megabits/second, decimal units, excluding audio/container overhead:
one camera = 8 × 3,600 / 8 / 1,000 = 3.6 GB.
Three cameras = 10.8 GB. Six cameras = 21.6 GB.
For seven days, six raw sources alone = 21.6 × 7/30 × $0.015 = $0.0756 of unrounded list-rate storage usage.
For thirty days = $0.324. Actual R2 billing aggregates usage, applies free allowances and rounds billing units; these are not exact invoices.

At an effective 20 Mbps upstream, 21.6 GB needs at least 21.6 × 8,000 / 20 = 8,640 seconds = 144 minutes, excluding overhead/retries. At 100 Mbps: 28.8 minutes. Three angles at 20 Mbps: 72 minutes. This is why upload/resume/proxy-first design matters more than the small raw-storage line item.

Illustrative planning inputs, explicitly NOT market prices:
render compute $0.25–$1.00 per hour × 0.5–2 hours = $0.125–$2.00;
optional vision compute $0.50–$2.00 per hour × 0.5–2 hours = $0.25–$4.00;
planner allowance $0.25–$2.00;
seven-day raw storage $0.0756.
Illustrative total = $0.7006–$8.0756, before proxies/films, operations, retries, connected-provider transfer, fixed infrastructure, licensing, support, fees and margin. Actual inference/render runtimes may lie outside these assumptions.

The reference screen’s $4–$8 sample quote / $12 cap demonstrates UX only. Do not use it as a product price or invoice. Benchmark actual jobs first, refresh official provider rates, then establish credit/subscription pricing with a real margin model. No dollar amount is charged by this pack.

Sources: [R2 rates and rounding](https://developers.cloudflare.com/r2/pricing/), [Supabase pricing](https://supabase.com/pricing), [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [Queues pricing](https://developers.cloudflare.com/queues/platform/pricing/). Check Remotion’s applicable commercial license before offering a rendering service.

## Delivery and YouTube

Ready means media probes and complete decode passed, timing/frame count matches the plan, expected audio/captions/metric provenance are present, and the private output hash is recorded. Human content review remains available for meaningful cues and uncertain edits.

Return private playable preview, downloadable MP4, thumbnail, chapters, SRT/VTT when actual captions exist, source-linked edit manifest, and optional portable project. YouTube preparation creates export, cover and editable title/description. Actual upload needs a deliberate user action and verified OAuth integration; public uploads from an unverified API project can be restricted. No posting occurs here. [YouTube upload API](https://developers.google.com/youtube/v3/docs/videos/insert).

