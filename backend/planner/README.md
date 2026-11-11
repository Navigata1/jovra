# Planner adapter (`backend/planner`)

The package the `jovra-internal` Workflow's plan step imports (docs/backend/architecture.md §7.6, ADR-0016, ADR-0023).
Part 1 (S88, issue #157) is the **heuristic** planner: a TypeScript server copy of the device's StoryDirector,
RulesPlanner, trust check, grammar lint, EDL compiler and `jovra.edit-plan/2` validator, ported from the Python
reference in `spec/reference/studio/` and held to it byte for byte by the S06 and S07 vectors. The model adapters
(Anthropic, OpenAI) and the draft-and-critique pipeline are part 2 (S89); they always fall back to this one.

It is pure and deterministic: no network, clock, randomness or file access, and no runtime dependency. Inputs are
plain data built from stored records; outputs are canonical JSON (sorted keys, no floats) whose SHA-256 is the hash a
render receipt binds. Nothing here is provisioned and no key, URL or account appears in it.

## Layout

```
src/heuristic/core.ts       exact BigInt fractions, half-up rounding, time <-> frame, pct, canonical JSON + SHA-256,
                            typed Reject, the RFC 6902 patch subset, and the Python semantics the reference relies on
src/heuristic/director.ts   StoryDirector.brief, the card catalog, the grammar lint        (director.py)
src/heuristic/keepers.ts    keeper ranking per profile, SplitMix64                         (keepers.py: rank only)
src/heuristic/progress.ts   ProgressStoryBuilder.compare                                   (progress.py)
src/heuristic/planner.ts    RulesPlanner.plan and the trust check                          (planner.py)
src/heuristic/edl.ts        the jovra.edit-plan/2 validator                                (edl.py)
src/heuristic/compile.ts    the EDL compiler                                               (compile.py)
src/heuristic/index.ts      the public surface
test/heuristic/vectors.ts   the parity harness (resolves cases the way the Python checkers do)
test/heuristic/*.test.ts    parity, binding, adversarial and core tests (node:test)
test/heuristic/parity-table.ts   prints the parity table; exits non-zero on any difference
```

`keepers.candidates` (building keepers from the core fold) is not ported: the planning context already carries the
keepers, and candidate building stays on the device.

## Run it

Node 24 or later (TypeScript runs through Node's built-in type stripping, so there is no build step):

```sh
cd backend/planner
npm ci
npm run typecheck   # tsc --noEmit, strict
npm test            # node --test: every vector, binding, adversarial and core test
npm run parity      # the parity table and counts
```

CI: `.github/workflows/backend-planner.yml` runs the same four steps on every pull request that touches this folder,
the Studio reference, its vectors, the story-brief records or the story-profile catalog, and writes the counts to the
job summary.

## What parity means here

For every case in `spec/studio/fixtures/vectors/director.json`, `planner.json` (S06) and `compile.json` (S07) the
harness re-runs the port on the case's resolved input and compares the canonical JSON bytes with the stored Python
expectation. On top of that:

- every plan the port produces passes the port's own trust check and grammar lint, plans twice to the same bytes and
  leaves its input unchanged;
- every EDL passes the port's `validate`, hashes to its stored `sha256`, compiles twice to the same bytes, and comes
  from the plan the port's own planner makes for the case's `planFrom`;
- moving one keeper window in a case's input changes its output hash, and altering one stored expectation fails that
  case only (`binding.test.ts`);
- ids that name `Object.prototype` members (`constructor`, `toString`, ...) resolve to nothing (`adversarial.test.ts`).

The base contexts are the vector files' own `context` cases. That they equal today's Sample records is proved by the
Python validator (`python3 scripts/spec/validate_studio.py`), not here. When a reference ticket regenerates the vectors
(for example S55), this suite checks the regenerated files with no change.

## Known differences from the Python reference

- Dates in a progress scope must be `YYYY-MM-DD` (the studio-common `date` format). Python's `date.fromisoformat`
  also accepts other ISO 8601 forms; no stored record uses them.
- Messages inside a typed rejection are close to the reference's but not compared: vectors assert the code. Refusal
  messages, which reach the player, are identical and are compared.
- Inputs that crash the Python reference (a `TypeError` on a malformed context) are outside the contract; the port may
  reject or throw on them differently.
