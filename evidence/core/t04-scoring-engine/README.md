# T04 scoring engine — completion evidence (2026-11-08)

Package-only ticket: no simulator, device, UI or ML claim is made here.

| File | What it shows |
|---|---|
| `swift-test.log` | `swift test --package-path ios/Packages/JovraCore --jobs 2` on this branch: 64 Swift Testing tests in 5 suites plus 12 XCTest tests, all passing. The discovered runner consumes 110 `jovra.fixture.scoring` fixtures (92 checkpoint folds, 18 typed refusals). |
| `native-scoring-verify.log` | `scripts/spec/verify_native_scoring.py` over the folds the Swift runner emitted (`JOVRA_SCORING_OUTPUT_DIR`): 114 native folds schema-valid and byte-equal to the Python goldens, schema negative controls refused. |
| `spec-validate.log` | `python3 scripts/spec/validate.py`: the reference engine reproduces all 110 scoring fixtures. `generate_fixtures.py` regenerates every existing fixture byte-for-byte; the only new files are S67–S70. |
| `pending-allow-list.diff` | Commit 5d997ae (#346) removing `jovra.fixture.scoring` from `FixtureManifest.pending`; the allow-list is now empty. |

## Red before green

- `generate_fixtures.py` refused S67 against the unmodified reference resolver: a newer-version suggestion
  replaced the reviewed point (winner B became A, provenance `reviewed` became `estimated`).
- With the Swift `LogResolver` reverted to main, `allDiscoveredRunnerFixturesPass` (S67 checkpoint) and
  `reanalysisLeavesTheReviewedPointUntouched` failed; restoring the change turned both green.
- `ScoringEngine.diff(before:after:)` did not exist (compile failure) before `ChangedValue` was added.

## Point-42 diff (independent expectation)

The Python reference fold of the Jon vs Alex sample, before and after flipping the 42nd point's winner, changes
every point from the 42nd on (83 of 124), games 8–10 of set 1 and all ten games of set 2, both sets
(`6-4 6-3` becomes `6-3 6-4`) and the result's scoreline. The Swift diff lists exactly those 99 values and no stats.

## Not covered

`sideMismatch` (wrong-half service) has no field in the session or engine-output contract; `spec/README.md`
lists wrong-half corrections under "Not yet covered". The free-count practice set has no format preset in the
contract either. Both need a contract amendment before the engine can produce them.
