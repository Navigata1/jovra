---
module: ledger
reference: [spec/reference/studio/ledger.py]
cases: [spec/reference/studio/cases/ledger_cases.py]
kinds: [jovra.quote/1, jovra.usage-reservation/1, jovra.credit-classes/1, ledger, quote-credits]
coverage: covered
swift: pending
kotlin: pending
---

# Ledger: quotes, credits and the reservation ledger

`spec/reference/studio/ledger.py` computes quote credits, accepts quotes and runs the idempotent reservation ledger;
the credit contract is `spec/studio/contracts/credit-classes.v1.json` (`jovra.credit-classes/1`).
`spec/reference/studio/cases/ledger_cases.py` writes the `ledger` and `quote-credits` vectors and the quote and
usage-reservation invalid cases. `python3 scripts/spec/validate_studio.py --list` prints the current case count of
every kind below and its Swift and Kotlin status.

| Schema | Record | What the reference adds beyond the schema |
|---|---|---|
| `quote` | Film class, **`plannerChoice`** (`heuristic` or `model`), estimate and cap in credits, cost estimate, line items, retention (1, 7 or 30 days, D-3), illustrative display amounts, expiry, status, consent (upload, `modelProvider`, `textClasses`, `retentionDays`, `consentTextVersion`), **`outputSpecSha256`** | Cap = `max(class minimum, ceil(cost / 800 000 µUSD))`; at most 30 min; an illustrative quote is Sample, never accepted, and is the only kind that shows dollars; acceptance needs consent before expiry (parsed times); the job, reservation and quote share one output-spec hash (bundle); a rules-planned quote estimates no model tokens and records `modelProvider: false`, a model quote needs `modelProvider: true`, the consent confirms the retention, and a film binds the planner kind its quote covered (bundle) |
| `usage-reservation` | Idempotency key `(projectId, planRevision, outputSpecSha256)`, job, initial and current quote, cap, reserved/consumed/released credits, keyed entries | Totals equal entries; keys unique; at most one consume entry per job and stage; within cap; closed reservations account for every credit; demo holds zero; demo/test are Sample; live is refused |

### Quote and reservation ledger (`ledger.py`)

Studio Credits are the one unit for quotes, caps, reservations and receipts. `credit-classes.v1.json` marks the
amounts **proposal, not a price**.

- **Request key:** a reservation is keyed by `(projectId, planRevision, outputSpecSha256)`. A replay returns the same
  reservation and charges nothing. The same key with other terms is `idempotencyConflict`. A new plan revision gets
  a new reservation. A quote carries the `outputSpecSha256` it was computed for and funds only that one reservation
  (`quoteMismatch`, `quoteAlreadyUsed`).
- **Budget exceeded:** the same key is never re-reserved; an accepted re-quote for the same plan revision and output
  **tops up** the held reservation (`topup`), and the old quote becomes `superseded`.
- **Stage key:** consumption is written when a stage attempt succeeds and is keyed by `(jobId, stage)`; a later
  attempt of a charged stage replays instead of charging again, and a failed attempt writes nothing.
- **One job per reservation:** the reservation names its job when the job is created (`reserve(job_id=…)` or
  `attach_job`; another job is `jobMismatch`). `consume` must name that job (`jobMismatch`) and a charged stage of
  the job contract spelled exactly (`unknownStage`), so one hold is never consumed by another job or under a
  respelled or invented stage.
- **Retries after a top-up:** a reservation remembers every `(quoteId, credits)` request it applied, so a
  redelivered original reserve or a redelivered top-up replays (no charge, no error).
- **Stored entries are tied to the record** (`badEntryKey`): reserve keys are
  `reserve:<projectId>:<planRevision>:<outputSpecSha256>` (the record's own key, one initial entry, first) or that key
  plus `:topup:<quoteId>`, where the top-up quote is neither the record's `initialQuoteId` (the quote that funded
  the first hold) nor one an earlier top-up used, and without a top-up `quoteId` equals `initialQuoteId` (the bundle
  requires an accepted quote for the same output, and every quote a top-up replaced to be `superseded`); consume keys are
  `consume:<jobId>:<stage>:<attempt>` with the record's job and a charged stage spelled exactly as in the job
  contract; release keys are `release:<jobId>:<outcome>` matching the status; the key prefix is the entry kind.
- **Types and time:** credits are integers, never booleans (`badAmount`); timestamps are parsed, never compared as
  text.
- **Limits:** going over the reservation is `budgetExceeded`. A failure or cancellation returns every unconsumed
  credit.
- **Environments:** the demo never reserves, test is Sample, and live is refused (`liveChargingNotActivated`) until
  a new pricing ADR exists (ADR-0013).

## Vectors

- Ledger sequences (including one hold per quote, the budget-exceeded top-up, retries after a top-up that replay,
  retries not charged twice, fractional-second expiry and boolean credits) and quote credits.

## Invalid cases the review rounds added

The quote and usage-reservation invalid cases cover, from the first round: double consumption, live charging, an
accepted illustrative quote and a client-set cap. Review round 1 added: a stage charged on two attempts, a quote
accepted 0.5 s after expiry, and an unbound quote. Review round 2 added: reserve, consume and release entry keys of
another output, job or stage (or with the wrong prefix or outcome), and a quote hash with a trailing newline.

The self-test `ledger-contract-drift` (registered in `ledger_cases.py`) checks that the quote schema's film classes
are exactly the classes of `credit-classes.v1.json`, in order.

## Decision

- Credit minimums and the $0.80 credit budget are copied from the pricing research as a labelled proposal. Money
   amounts appear only in an illustrative Sample quote.
