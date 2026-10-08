---
module: core
reference: [spec/reference/studio/core.py]
cases: [spec/reference/studio/cases/core_cases.py]
kinds: [jovra.studio-fixture.invalid-cases/1, jovra.studio-fixture.vectors/1]
coverage: covered
swift: pending
kotlin: pending
---

# Core: conventions and fixture formats

`spec/reference/studio/core.py` holds the exact rounding, time and frame conversions, integer `pct`, canonical JSON
hashing, the typed rejection (`Reject`, a stable machine code) and the fixture patch (`apply_patch`) every other
module uses. It owns the two fixture formats every cases module writes (schema `fixture.schema.json`):

- **Invalid-case sets** (`jovra.studio-fixture.invalid-cases/1`): patches applied to a valid record under `records/`.
  A `schema` case must fail the schema; a `reference` case must pass the schema and be rejected by the reference with
  the expected code.
- **Vectors** (`jovra.studio-fixture.vectors/1`): inputs, the reference's expected output, and hand-derived
  assertions that do not come from the reference. A vector file's `kind` names the checker its cases module
  registers; the schema does not list the kinds.

The fixtures live under `spec/studio/fixtures/`: `records/` holds the valid records of the one Sample project
(`sample-court-day`), `invalid/` the invalid-case sets and `vectors/` one file per vector kind.

The self-test `core-provenance-drift` (registered in `core_cases.py`) checks that the provenance enum in
`studio-common.schema.json` is the app's (`spec/schemas/common.schema.json`), in order.

## Conventions

- **Versions.** Every record has `schemaVersion: "jovra.<name>/<major>"`, following the starter's
  `jovra.edit-plan/1`. A breaking change bumps the major. Additive changes also need a fixture change. No schema has
  an `$id`, and references are relative files, as in the core.
- **Strictness.** Every object has `additionalProperties: false`. The reference also rejects unknown or missing
  fields itself (as the starter does), refuses integral floats such as `744.0` for frames, and refuses floats
  anywhere it hashes (`floatInContract`).
- **Ids** match `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`, so an id can never be a path, URL or command. Template ids
  (`card.goal`, `label.replay`) come from catalogs, and on-screen text comes only from stored user records.
- **Time.** Proxy frames are integers on exact rational clocks (`{num, den}`). Original PTS use `{value, timescale}`.
  The session (match) clock is integer microseconds. Rates are `num / 1 000 000 000`. There is one rounding rule,
  `floor(x + 1/2)` in exact arithmetic (`core.round_half_up`, the time analogue of ADR-0011), and Python's half-even
  `round()` is never used. Percentages use the core `pct(n, d) = (200n + d) div 2d`.
- **Hashes.** `canonical_sha256` is SHA-256 over sorted-key, whitespace-free UTF-8 JSON. It equals RFC 8785 for
  documents without floats, which is why floats are refused. Fixture media hashes are deterministic stand-ins,
  because no real Sample media exists.
- **Provenance** uses the core enum (`manual | estimated | reviewed | validated`). The validator fails if the
  Studio copy drifts from `spec/schemas/common.schema.json`.
