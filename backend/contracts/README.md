# Backend contracts (`backend/contracts`)

JSON Schemas and fixtures for every request and response of the Studio gateway (`docs/backend/architecture.md`
§5.1, 41 routes) and for the `render-work` queue messages (S81, issue #150). The gateway (S82) and the iOS client
(S97) both test against these files, so neither waits on the other. Nothing here is provisioned: every URL is at
`example.test`, every id, token and address is a Sample value (ADR-0014; CLAUDE.md rules 5 and 7).

## Layout

```
routes.v1.json                     the route manifest: id, method, path, worker, auth, Idempotency-Key, schemas, error codes
schemas/common.schema.json         shared $defs: ids, hashes, tokens, enums, header values, the error envelope
schemas/route.<id>.request.schema.json   one per route
schemas/route.<id>.response.schema.json  one per route
schemas/queue.render-work.message.schema.json   {attemptId} and nothing else (render-work and render-work-dlq)
fixtures/routes/<id>/request.<case>.json      valid request descriptors (at least one per route)
fixtures/routes/<id>/response.<case>.json     valid response descriptors (at least one per route; many routes add errors)
fixtures/queues/<queue>/message.<case>.json   valid queue messages
fixtures/invalid/<folder>/<case>.json + cases.json   deliberately invalid instances that must be rejected, and why
tools/definitions.py   the contract, declared once      tools/generate.py   writes schemas/ and routes.v1.json
tools/validate.py      schemas + fixtures + invalid cases + cross-checks
tools/route_coverage.py   §5.1 table against routes.v1.json, schemas and fixtures
tools/check_fixture_hygiene.py   no hosted URL, project ref, JWT, real email, real UUID or token
tools/test_contracts.py   the tools' own tests (unittest)
check.sh                runs all of the above
```

Schemas and the manifest are **generated**: edit `tools/definitions.py`, run `tools/generate.py`, commit both.
`generate.py --check` (in CI) fails when a committed file differs from the generator's output. Fixtures are
hand-written data and are never generated.

## Run it

From the repository root (Python 3.10+; the standard library is enough, `jsonschema` adds a second validator):

```sh
backend/contracts/check.sh
```

which runs, in order:

```sh
python3 backend/contracts/tools/generate.py --check          # schemas and manifest match the definitions
python3 backend/contracts/tools/route_coverage.py            # every §5.1 route: schemas + request and response fixtures
python3 backend/contracts/tools/validate.py                  # add --require-jsonschema to make the second validator mandatory
python3 backend/contracts/tools/check_fixture_hygiene.py
python3 -m unittest discover -s backend/contracts/tools -p 'test_*.py'
```

CI: `.github/workflows/backend-contracts.yml` runs the same steps (with `jsonschema==4.26.0` installed and
`--require-jsonschema`) on every pull request that touches these files, the architecture document, the Studio
schemas this imports, or the bundled checker.

## Descriptors

A fixture is an HTTP exchange descriptor, not a raw body, so a route without a body still has a request contract
(its path parameters and headers) and a bytes route still has a response contract (status and headers).

- Request: `{pathParams?, query?, headers, body?}`. `body` is present exactly when the route takes JSON; the
  JSON body's own schema is `#/$defs/body` of the request schema, for a gateway that validates bodies only.
- Response: `{status, headers, body?}`. JSON successes are `200` with `{data, requestId}`; the data schema is
  `#/$defs/data`. Bytes successes are `200`, or `206` with `Content-Range`, and carry no body in the descriptor.
  Errors are the §5 envelope `{error: {code, message, retryable, details?}, requestId}` with one of the route's
  codes at its own status.
- Header names are canonical (compare case-insensitively). Header objects are closed: a real request may carry
  others the contract does not use (User-Agent), but a fixture may not, and a response may never add one the
  contract forbids (a share link sets no cookie).
- Every response carries `X-Request-Id`; a JSON body's `requestId` must equal it (checked by `validate.py`).

## Authentication schemes

| `auth` in the manifest | Headers | Used by |
|---|---|---|
| `none` | none | health, share links (`/s/{token}`), the signed capability challenge, an anonymous invite redemption |
| `user` | `Authorization: Bearer <Supabase access JWT>` | every owner, coach and user route |
| `guest-signed` | `Authorization: JOVRA-Capability jvg_…` + `JOVRA-Timestamp`, `JOVRA-Nonce`, `JOVRA-Signature` (device P-256) | guest source declaration, guest upload session |
| `session` | `Authorization: JOVRA-Capability jvs_…` | upload status, parts, completion, abort |
| `host` | `Authorization: JOVRA-Host <credential>` (+ optional HMAC signature headers for an external host) | attempt claim |
| `host-lease` | as `host` + `JOVRA-Lease: jvl_…` | heartbeat, inputs, outputs, result |

Every `POST` requires `Idempotency-Key` (a UUIDv4). Tokens are `jv?_` + 43 base64url characters
(security-model §8.1). No route takes a Supabase API key or any other secret from the app (story 245): the app
holds only the user's own access token, and the schemas leave no header for anything else.

## Decisions this contract makes (INFERRED)

The architecture fixes the routes, bodies and checks; it leaves these wire details open. This contract chooses
them so S82 and S97 agree; change them here first (definitions, then fixtures), never in one client.

1. HTTP statuses for the SQL command errors: `P0401` → 401 `unauthorized`, `P0402` → 402 `budget_exceeded`,
   `P0404` → 404 `not_found`, `P0409` → 409 `conflict`, `P0410` → 410 `expired`, `P0422` → 422 `invalid`,
   `P0429` and the §5 rate limits → 429 `rate_limited`; 416 `range_not_satisfiable`; 500 `internal`. The documented
   codes keep their documented statuses (`demo_not_accepted`, `reauth_required`, `already_claimed`,
   `parts_mismatch`, `requote_required`, `dependents`, `secret_not_replayable`, `idempotency_key_reused`).
   `routes.v1.json` `errorCodes` records the basis of each.
2. Header names for request signing: `JOVRA-Timestamp` (Unix seconds), `JOVRA-Nonce`, `JOVRA-Signature`
   (guest: raw P-256 `r||s`, base64url; external host: HMAC-SHA256, base64url). The optional client request id
   is sent as `X-Request-Id` and echoed as `clientRequestId`.
3. Successful JSON responses are all `200` (no `201`).
4. `details` on two error codes: `dependents` lists `{artifactId, kind}`; `secret_not_replayable` names the
   `resourceId` whose own route issues a fresh secret.
5. Field shapes the table names without detail: `probeSummary` (`codec`, `width`, `height`, `fps`, `durationUs`,
   `rotationDegrees`), `/v1/me` `features` (feature ids), `jobs.get` `stages`, `artifacts` and `errorCode`,
   `grants.redeem` `approvalCode`, `claim` `inputRefs` items (`inputRef`, `kind`, `bytes`, `sha256`), heartbeat and
   result `measurements`, `grants.create` `expiresInSec` bound (365 days).
6. Imported, not restated: the `quotes.create` response is `jovra.quote/1` (`spec/schemas/studio/quote.schema.json`)
   without `estimatedMaxCostMicroUsd` and `creditCostBudgetMicroUsd`, plus `storyPlanId` and `storyPlanVersionId`;
   a quote request's `outputSpec` is the EDL `output` of `jovra.edit-plan/2` with `totalFrames` replaced by
   `durationTargetSec`. `jobState` must equal the states of `spec/studio/contracts/render-job-transitions.v1.json`
   minus `draft` and `quoted` (checked by `validate.py`).

## Open questions (not answered by the documents)

1. **Capability challenge nonce.** `POST /v1/camera-invites/redemptions/{redemptionId}/capability` takes a
   signature over "a server nonce" (security-model §8.2), but no §5.1 response carries one. The contract accepts a
   `nonce` in the body; whether the server issues it (and from which route) must be settled in S82.
2. **Guest signing input.** The canonical byte string for `(method, path, timestamp, nonce, body SHA-256)` is not
   specified; S82 should fix it and add a signing vector here.
3. **Share-link and grant expiry status.** The contract returns `404` for an expired share link or grant code, the
   same as unknown (no existence oracle); `410 expired` is used only for camera invites and upload sessions.

## How the clients use it

- **Gateway (S82, TypeScript):** load `schemas/` with any 2020-12 validator, registering each file under its file
  name (schemas have no `$id`, as in `spec/`; their `$ref`s are relative file references such as
  `common.schema.json#/$defs/uuid`), validate each incoming request descriptor and each response the Worker
  produces in tests, and replay every `fixtures/routes/<id>/request.*.json` against the Worker under vitest.
- **iOS (S97):** a test target reads `backend/contracts/fixtures` from the repository (resolve the path from
  `#filePath`, as the JovraCore conformance tests do for `spec/fixtures`), decodes every
  `response.*.json` body with the app's real `Decodable` types and encodes its requests to bodies that validate.
  Nothing is copied into the app bundle.

## What this does not prove

The schemas check shapes, formats, enums and per-route error codes. They cannot check ownership, state,
expiry, signatures, rate limits or any row-level rule: those are the gateway's and the database's tests
(architecture §12). Whether the hosted gateway conforms is UNVERIFIED until S82 runs these fixtures against it.
