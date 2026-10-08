# Paid cloud production is opt-in: quote, consent, cap, idempotent reservation

Status: accepted (2026-10-07) for the cloud mechanism. Retail prices are not set. Amends ADR-0013 for the Studio
cloud boundary only. **Amended 2026-10-07 (review round 2):** whether *on-device* Studio features are free or premium
is Jon's decision and is not settled here (see "The line").

ADR-0013 requires a new ADR before any pricing is added, and requires that nothing restrict footage or data already
on the phone. This is that ADR, for Studio cloud production only.

**The line.** Core v1 stays free (ADR-0013, binding). Anything that costs JOVRA money each time it runs is opt-in,
quoted and paid. Nothing the user already has is ever locked.

- **Free, binding:** all of core v1.
- **On-device Studio — recommended free, pending Jon (spec open question 9):** Build your match local capture on every
  phone; import of extra angles, plus manual and on-device sync; synchronized multi-angle replay; lessons; the five
  story profiles rendered by AVFoundation (ADR-0015) from the heuristic planner (ADR-0016); "Prepare for YouTube"
  files for local films. Jon's addendum calls Studio "super-premium" and "the moat", and ADR-0013 covered core v1
  only, so making these free is a recommendation (they cost JOVRA nothing per use), not a decision. The app reads one
  entitlement (`StudioEntitlements.localStudio`, available in every build until Jon decides), so either answer is a
  configuration and pricing-ADR change, not a redesign. If Jon makes them premium, that pricing ADR must still keep
  everything in "Never charged or locked" below and core v1 free.
- **Paid, opt-in, quoted:**
  - uploading selected sources to cloud staging;
  - cloud proxies;
  - the model-planned story;
  - cloud render and verification;
  - hosted private previews and expiring share links;
  - later, measured cloud vision and extended retention.
- **Never charged or locked:**
  - originals and "Save original";
  - the full data export;
  - local films and downloaded cloud films;
  - watching, trimming or exporting anything after a lapse.

**The mechanism**, in the job state machine `draft → quoted → consented → … → ready`:
1. **Quote.** The server computes it from the actual source bytes and angles, story profile, output spec, retention
   and current rates. It shows upload size, retention, output, an estimate and a **cap** (maximum authorized cost),
   and expires after about 30 minutes. An expired quote is re-quoted, never auto-accepted. Prices from the client or
   the model are never authoritative.
2. **Consent.** The owner explicitly accepts the quote and the cloud processing, including frames sent to a model
   provider. Archive permission (ADR-0020) is not processing consent. Publishing is a separate action. Nothing is
   ever auto-published to YouTube.
3. **Cap.** The budget is checked before every stage and every retry. A job that would overrun stops at
   `budget_exceeded` with a resumable offer. Model, effort, quality and retention never escalate automatically.
4. **Idempotent reservation.** The maximum exposure is reserved before any work starts, under the key
   `(project, plan revision, output spec)`, computed by the server from the stored plan version. While the job has
   not produced its plan yet, the plan itself stands in for the revision, and an empty revision counts as a value, so
   two identical "plan by job" quotes still share one key (`docs/backend/security-model.md` §13.6). A revision inside
   the same job moves the key with it. The quote and the
   consent in it are bound to the same output spec hash, and an accepted quote funds exactly one reservation. The key
   does not include the quote id, so re-quoting identical work can never open a second hold; after `budget_exceeded`
   an accepted re-quote **tops up** the existing reservation (contract vector `budget-exceeded-topup-resumes`). A
   retry under the same key cannot charge twice. Credits are consumed when a stage attempt succeeds, once per
   `(job, stage)`: a failed attempt is not charged and a retried stage is never charged twice (the pricing research's
   retry overhead is operator cost inside the internal cap). Failure before `ready`, or cancellation, releases every
   unconsumed unit. A film that fails verification is never charged as delivered. Receipts keep the estimate, cap,
   actual usage and refunds separate. Open caps are bounded per owner and per environment per day, and a missing or empty limit refuses
   rather than allows (`security-model.md` §13.7).

**Who can spend.** Only the project owner can accept a quote, with a real (non-anonymous) account: a live account in
live, and in test an allow-listed tester whose quotes carry Sample credits (the gateway checks the tester flag in test,
`docs/backend/security-model.md` §2.1). Demo profiles never reserve: demo
quotes say "Sample quote". Tester identities are never charged money: their quotes and reservations carry Sample
credits (the contract fixtures show non-zero Sample credits, e.g. cap 4, consumed 3, because the ledger arithmetic
must be exercised). Separately from those user-facing credits, every reservation carries an **internal cost cap in
real micro-USD** that is always enforced, and the test environment has an operator-set daily ceiling, because test
can call a real model with Jon's key and run real containers; a zero cap would refuse every stage, and bypassing it
would leave test spend unbounded. (Amended 2026-10-07; the first text said "zero Sample amounts", which conflated the
two.) The reference screen's $4–$8 estimate with a $12 cap is UX only.

**Recommended unit (proposal for Jon, not decided):** Studio Credits as the single ledger unit for quote, cap,
reservation and receipt, with purchased credits that never expire. A membership is deferred. There is no retail
price until the benchmarks in pricing-and-premium §8 have run on real footage. At the design target, a film's cost to
JOVRA is about $1.03–$2.32 (INFERRED, pricing-and-premium §4).

## Considered Options

- **A paywall or subscription gate on Studio as a whole.** Not recommended (it would charge for on-device features
  that cost JOVRA nothing), but it is Jon's product decision (spec open question 9), not settled by this ADR. Locking
  anything the user already has, or any part of core v1, stays rejected (ADR-0013).
- **A free monthly cloud allowance.** Rejected until revenue exists. At most, a one-time "first film free" (about $1).
- **Charging on completion with no prior reservation.** Rejected. Retries and partial failures make the spend
  unbounded and double charges possible.

## Consequences

Real charging needs Jon's pricing decision. Before money moves it also needs the store-payment design under App
Review 3.1.1 and the live activation gates (ADR-0014). Until then, quotes, consent, caps and reservations are built
and tested with Sample credits and no money charged, under the real internal cost cap and test ceiling. Turning on the cloud changes the App Privacy label for users who opt in. Core v1
stays "Data Not Collected".

Sources: `docs/research/studio/pricing-and-premium.md` §§4–8;
`design-reference/studio/brief/backend-media-design.md` (Job state and money);
https://developer.apple.com/app-store/review/guidelines/ ; https://developers.cloudflare.com/r2/pricing/ ;
https://platform.claude.com/docs/en/about-claude/pricing .

## Amendment note (2026-10-07): finding 30, item (2)

Append-only; no decision above changes. Finding 30 (ADR consistency, Studio review round 2) item (2): this ADR said
"Only the project owner, on a live account, can accept a quote", while testers accept Sample quotes in the isolated
test environment (`accept_quote`: "owner, real user", `docs/backend/security-model.md` §4.1). The text was
corrected during that review, before this ADR was first committed. The reading that holds is "Who can spend" above:
the project owner with a real, non-anonymous account accepts; that is a live account in live, and in test an
allow-listed tester, whose quotes carry Sample credits and are accepted only when the operator-set tester flag is
on (`security-model.md` §13.3). A demo profile never reserves.

Cross-reference, no change to "The line": ADR-0023 (founder decision, Jon, 2026-10-07) post-dates this ADR. It keeps
the on-device rules planner as the free default and prices Studio films in credits by story length (3 to 30 minute
tiers and Full match) and capture quality, with every quote Sample until the benchmarks set prices. It does not say
whether on-device template films stay free, so "On-device Studio — recommended free, pending Jon" above stays as
written until Jon answers the rest of spec open question 9 (register entry SOF-R4-03 in
`docs/spec/studio-open-findings.md`).
