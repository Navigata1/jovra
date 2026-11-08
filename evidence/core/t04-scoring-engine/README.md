# T04 scoring engine — completion evidence (2026-11-08)

Package-only ticket: no simulator, device, UI or ML claim is made here.

| File | What it shows |
|---|---|
| `swift-test.log` | `swift test --package-path ios/Packages/JovraCore --jobs 2` on this branch: 64 Swift Testing tests in 5 suites plus 12 XCTest tests, all passing. The discovered runner consumes 111 `jovra.fixture.scoring` fixtures (93 checkpoint folds, 18 typed refusals; 116 complete outputs). |
| `native-scoring-verify.log` | `scripts/spec/verify_native_scoring.py` over the folds the Swift runner emitted (`JOVRA_SCORING_OUTPUT_DIR`): 116 native folds schema-valid and byte-equal to the Python goldens, schema negative controls refused. |
| `spec-validate.log` | `python3 scripts/spec/validate.py`: the reference engine reproduces all 111 scoring fixtures (671 hand assertions). `generate_fixtures.py` regenerates every existing fixture byte-for-byte; the only new files are S67–S71. |
| `spec-python-tests.log` | The `scripts/spec/test_*.py` suites, including the two new `test_order_overrides.py` tests for `servedFromSide` (1.2.0-only field; wrong half stands and is flagged). |
| `side-mismatch-red.log` | Red run: with `ScoringEngine.swift` as of 8512292 (no wrong-half rule) and the S71 fixture present, `allDiscoveredRunnerFixturesPass` fails on both S71 checkpoints. |
| `pending-allow-list.diff` | Commit 5d997ae (#346) removing `jovra.fixture.scoring` from `FixtureManifest.pending`; the allow-list is now empty. |

## Every spec conflict kind has a passing fixture

`everyContractConflictKindComesFromAPassingFixture` now asserts all eight kinds that docs/spec/ios-v1-spec.md names:
`serverMismatch`, `tiebreakAppeared`, `tiebreakVanished`, `pointsAfterMatchEnd`, `matchIncomplete`,
`checkpointConflict`, `doublesOrderConflict` and `sideMismatch`. It also asserts every `TimelineConflictType`.

`sideMismatch` is a contract amendment (spec/README.md decision 25, rules §3 Rule 27a):

- `session.schema.json`: point events may carry `servedFromSide` (`deuce | ad`, observed), since 1.2.0. `pre_v1_2`
  forbids it on documents stamped 1.0 or 1.1.
- `engine-output.schema.json`: the `sideMismatch` conflict (`pointId`, `recorded` = the half served from, `derived`
  = the half the rules required).
- Reference fold (`jovra_ref/scoring.py`) and Swift fold (`ScoringEngine.swift`) raise it right after
  `decidingPointSideIgnored`, only on determined points with a known derived half. The point stands, the fault
  before discovery stands, the derived half is kept.
- S71 (`spec/fixtures/scoring/S71-served-from-wrong-half.json`, stamped 1.2.0): a point served from the deuce half
  when the ad half was due keeps its first-serve fault (serve number 2) and its score; the next point is on the deuce
  half. A missed point inserted before two correctly-served points moves both to the other half, so both are
  flagged as well (three conflicts at the second checkpoint).

## Red before green

- `generate_fixtures.py` refused S67 against the unmodified reference resolver: a newer-version suggestion
  replaced the reviewed point (winner B became A, provenance `reviewed` became `estimated`).
- With the Swift `LogResolver` reverted to main, `allDiscoveredRunnerFixturesPass` (S67 checkpoint) and
  `reanalysisLeavesTheReviewedPointUntouched` failed; restoring the change turned both green.
- `ScoringEngine.diff(before:after:)` did not exist (compile failure) before `ChangedValue` was added.
- `side-mismatch-red.log`: S71 failed against the Swift fold without the wrong-half rule.

## Point-42 diff (independent expectation)

The Python reference fold of the Jon vs Alex sample, before and after flipping the 42nd point's winner, changes
every point from the 42nd on (83 of 124), games 8–10 of set 1 and all ten games of set 2, both sets
(`6-4 6-3` becomes `6-3 6-4`) and the result's scoreline. The Swift diff lists exactly those 99 values and no stats.

## Not covered

- Wrong ends (Rule 27b, where the open fault is voided) and suspensions stay under "Not yet covered" in
  spec/README.md. Neither is an acceptance criterion of issue #6.
- The free-count practice set has no format preset in the contract.
- No UI shows `sideMismatch` yet. The point editor's conflict banners belong to T29 (docs/spec/tickets.json).
