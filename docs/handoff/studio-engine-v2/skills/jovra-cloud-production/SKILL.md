---
name: jovra-cloud-production
description: Design or execute an authorized JOVRA private production job with tenant-scoped media, bounded usage, durable processing, retention and verified delivery.
---

# Optional cloud production

Read the current Studio backend brief and applicable ADRs. Preserve offline capture and the current free/local foundation. Supabase/R2/render-host choices are the proposed architecture, not proof of provisioning. Real deployment, model access, billing and pricing need their own activation evidence.

Keep control and media execution separate: native client → authorization/preflight gateway → private direct media upload → durable job/queue reference → isolated FFmpeg/Remotion or measured analysis host → verified artifact → private gateway delivery. Queue manifests, never video bytes; do not buffer long originals inside a request isolate.

Verify authenticated project membership, exact source/artifact grants and declared uploader role. RLS protects metadata; R2 signing needs separate object checks. Camera participants upload assigned footage without browsing everyone’s originals. Validate completion/hash/size against server-held expectations. Reject live demo tokens. Do not include service-role keys, signed URLs or production secrets in skill prompts, EDLs or clients.

Preflight uses actual sources, profile/output, expected analysis/render work, retention and current rates. Present a quote/expiry/cap and accept it before paid execution. Store an idempotent usage reservation; client/model price fields are not authoritative. Reserve bounded retries and do not silently escalate quality/model/spend.

Track durable transitions with transactional dispatch, leases, heartbeats, bounded retries and dead-letter review. Distinguish upload, analysis, planning, rendering, verification and ready; partial failure cannot become a download-ready state. Cancellation blocks new work, reconciles spend and clears eligible temporary artifacts. Retain local originals and a job receipt.

Use short-lived exact-object capabilities; already issued direct URLs remain usable until expiry. Longer application share links go through fresh grant checks. Protect thumbnails, proxies, vectors and manifests too. Retention/deletion must include derived media and be reflected in the UI. Optional archive providers have separate credentials and capability states; archive permission is not processing consent.

Return measured usage, errors and readiness evidence. Price the premium service only after benchmark jobs and margin analysis. A generated demo queue or accepted JSON plan is not evidence of an isolated cloud render.
