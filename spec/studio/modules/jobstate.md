---
module: jobstate
reference: [spec/reference/studio/jobstate.py]
cases: [spec/reference/studio/cases/jobstate_cases.py]
kinds: [jovra.render-job/1, jovra.render-job-transitions/1, job-transitions]
coverage: covered
swift: pending
kotlin: pending
---

# Jobstate: the RenderJob state machine

`spec/reference/studio/jobstate.py` checks RenderJob transitions and replays a job's history; the transition contract
is `spec/studio/contracts/render-job-transitions.v1.json` (`jovra.render-job-transitions/1`).
`spec/reference/studio/cases/jobstate_cases.py` writes the `job-transitions` vectors and the render-job invalid cases.
`python3 scripts/spec/validate_studio.py --list` prints the current case count of every kind below and its Swift and
Kotlin status.

| Schema | Record | What the reference adds beyond the schema |
|---|---|---|
| `render-job` | State, `resumeStage` (only a stage the state can return to), attempt, quote/reservation, idempotency key, per-stage progress, delivered artifacts, full history | `jobstate.Machine.replay` must reach the stored state, resume stage and attempt; `ready` only when every listed artifact resolves to a verified film of this job (bundle) |

### Job state machine (`render-job-transitions.v1.json`, `jobstate.py`)

The states come from the backend brief. Terminal states are `ready`, `canceled`, `failed_terminal` and `deleted`.
`paused`, `failed_retryable`, `quote_expired` and `budget_exceeded` can be resumed.

- **Pausing and retrying:** pause and retryable failure remember `resumeStage`. Resuming returns only there, and a
  retry uses up an attempt (`retriesExhausted` once `attempt = maxAttempts`). A stored `resumeStage` is checked, not
  trusted: it must be in `pausableFrom` / `retryableFrom` / `budgetExceededFrom` for that state and is null otherwise
  (`badResumeStage`), so `ready`, `deleted` or a terminal state can never be resumed into.
- **Budget and expiry:** `budget_exceeded` and `quote_expired` resume only through a new quote. Nothing is
  auto-raised or auto-accepted.
- **Reservations:** stages from `upload_pending` onward need a reservation.
- **Readiness:** `ready` needs a verified delivered artifact.
- **Shortcuts:** `syncing → planning` is the analysis-unavailable fallback. `upload_pending → queued` covers
  sources that are already verified.

## Vectors

- Job transitions, including resume stages that are refused.

## Invalid cases the review rounds added

Review round 1 added two render-job invalid cases: a ghost artifact on a ready job and a resume stage of `ready`.

The self-test `jobstate-contract-drift` (registered in `jobstate_cases.py`) checks that the render-job schema's states
and resume stages agree with `render-job-transitions.v1.json` (resume stages are exactly the pausable, retryable and
budget-exceeded states, and never a terminal one).
