# Backend-ready v1: three environments, live only behind activation gates

Status: accepted (2026-10-07); amends ADR-0002 (backend boundary only; the local-first document store stands).
ADR-0002 carries the matching note, added by its owner: "Status: amended by ADR-0014 (backend boundary only)". The
two notes use one word, "amended"; this ADR does not supersede any part of ADR-0002.

ADR-0002 put "a JOVRA cloud account/backend" out of scope for v1. Jon's Studio direction of 2026-10-07 asks for the
backend to be designed, built and tested in v1 ("all that rls and thoughtfulness in place and built in"), with auth as
tester items "until the wired up backends ... is in place provisioned and live" (`docs/handoff/JON-ORIGINAL-PROMPT.md`,
Studio addendum, OBSERVED). We therefore ship v1 **backend-ready**: stable client interfaces with a local adapter, plus
a backend (Supabase Auth and Postgres with RLS, a Cloudflare gateway Worker, private R2, Workflows and Queues, a
separate render host) built as code, migrations and local tests by the backend tickets (`docs/backend/architecture.md`
§15, B-00…B-25). The app never needs it.

**Status of that backend on 2026-10-07 (OBSERVED in the repo):** it is a design, not code. `docs/backend/` holds the
architecture and the security model (tables, per-table RLS policies, command functions, gateway API, role matrix and
the T-DB/T-GW/T-R2 test lists); `spec/schemas/studio` and `spec/reference/studio` hold the Studio record contracts and
their checked reference. There is no `supabase/`, migration, Worker or render-host code yet, and RLS, gateway
authorization and the queue/lease protocol are "not covered yet" in `spec/studio/README.md`. Nothing above may be
reported as built or tested until those tickets land with failing-capable tests (CLAUDE.md rule 9).

There are exactly three environments, chosen by build configuration and never by a runtime toggle the user can flip:

| Environment | What it is | Network | Identity | Money |
|---|---|---|---|---|
| **Local demo** | In-process adapters with fictional Sample fixtures | None | Demo profile (ADR-0022) | Never; quotes say "Sample quote" |
| **Isolated test** | Its own Supabase project, Worker environment and R2 buckets | Test endpoints from config | Tester identities seeded via config | No money charged: Sample credits for the tester, but the internal cost cap and an operator-set environment ceiling bound real model and container spend (ADR-0019) |
| **Live** | Separate Supabase project, Worker environment and buckets | Live endpoints from config | Live accounts | Only after ADR-0019's gates |

Test and live share no keys, buckets or JWT issuer; the gateway pins `iss` per environment, so a test token fails in
live (INFERRED from the documented issuer format, backend-architecture §2). Base URLs and publishable keys come from
xcconfig / Gradle config, never source (CLAUDE.md rule 5). Under the IDC domain doctrine, no hostname enters code
until its DNS resolves.

**Local first is unchanged.** Recording, replay, scoring, stats, lessons, local films, export and the Drive archive
work with no account and no network (ADR-0002, ADR-0010, ADR-0013). Each Studio project stays a folder with its JSON
document as source of truth. Cloud sync is opt-in per project and per source, links local UUIDs to cloud IDs through
a reviewed migration, keeps offline access after sign-out, and never lets a local edit silently overwrite a newer
cloud revision: both are kept until the user resolves the conflict.

**Activation gates.** An environment, or a capability within it, goes live only when all of the following hold:
1. Jon creates the account or project himself. No agent provisions, signs up or spends.
2. Secrets are set through a configuration channel, never committed. The client holds only the publishable key and
   base URLs.
3. In the target environment: migrations apply cleanly, pgTAP RLS tests pass under real auth roles
   (`supabase test db`), and `supabase db advisors --type security --fail-on warn` is clean.
4. Tenant tests with the gateway refuse cross-project rows and media, expired invites, wrong-project upload
   completion, stale grants and forged demo sessions (expansion prompt acceptance list).
5. The App Privacy label and privacy policy match what the capability actually collects. Core v1 still targets
   "Data Not Collected" (ADR-0013).
6. Any capability-specific gate is met: Apple token revocation on deletion (ADR-0022), planner access verified
   (ADR-0016), the Remotion licence decision (ADR-0015), and pricing (ADR-0019).
7. Infrastructure gates with their own evidence: the render host (a synthetic fixture film fully verified in the
   cloud), remote push notifications (APNs/FCM keys; until then a cloud job's "film ready" appears only inside the
   app), Hyperdrive with query caching disabled and Workers invocation logs off (`docs/backend/architecture.md` §13,
   G2, G3, G3b).

Until a gate passes, the UI shows the honest state ("Not connected", "Awaiting setup"), never a fake "Connected"
(ADR-0008 precedent).

## Considered Options

- Keep ADR-0002's "no backend in v1" and design later: it contradicts the founder's direction, and RLS, tenancy and
  idempotency are expensive to retrofit.
- Make the backend required (accounts first): it breaks the own-your-footage contract and CLAUDE.md rule 3.
- One shared test/live project separated by flags: one leaked key or policy bug crosses tenants. Rejected.

## Consequences

The backend is real code with real tests, but it is **unverified against hosted services** until Jon activates the
test environment. Local Supabase (Docker), Miniflare and `@cloudflare/vitest-plugin` prove behaviour locally
(`docs/backend/architecture.md` §12; the activation gates are §13). ADR-0013's "no JOVRA server" still holds for the core app; the Studio cloud exception is
recorded in ADR-0019.

Sources: https://supabase.com/docs/guides/database/postgres/row-level-security ;
https://supabase.com/docs/guides/local-development/testing/overview ;
https://supabase.com/docs/guides/database/database-advisors ; https://supabase.com/docs/guides/auth/jwts ;
https://developers.cloudflare.com/workers/testing/vitest-integration/ ; `docs/research/studio/backend-architecture.md`;
`design-reference/studio/brief/backend-media-design.md`.

## Amendment note (2026-10-07): finding 30, item (3)

Append-only; no decision above changes. Finding 30 (ADR consistency, Studio review round 2) item (3) said this ADR
cited the backend tickets as "B-00…B-22", leaving out what `docs/backend/architecture.md` §15 lists after them: the
review-round-1 hardening B-23 (D1–D24), the JOVRA editor adapter B-24 and the review-round-2 hardening B-25
(`security-model.md` §13). The range was corrected to "B-00…B-25" during that review, before this ADR was first
committed, so git holds no earlier wording; on 2026-10-07 it matches §15, whose last row is B-25.

One related difference is recorded here, not fixed: §15's B-00 row still describes the scope change as superseding
"the 'no backend' line of ADR-0002", while this ADR and ADR-0002 both say "amended (backend boundary only)". This
ADR's word governs. The row belongs to the backend architecture owner and is left to the re-verification of findings
13–48 (Studio ticket S02; register entry SOF-R4-05 in `docs/spec/studio-open-findings.md`).
