# T05 stats, data export and pooled trends: completion evidence (2026-11-08)

Package and contract ticket. No simulator, device, UI or ML claim is made here. Every number below comes from a
check that could fail; `mutation-red.log` shows the new checks failing against broken implementations.

| File | What it shows |
|---|---|
| `swift-test.log` | `swift test` in `ios/Packages/JovraCore` (macOS host): all Swift Testing and XCTest tests pass. The discovered runners consume 3 `jovra.fixture.stats`, 1 `jovra.fixture.sample`, 1 `jovra.fixture.pct` (32 vectors), 111 `jovra.fixture.scoring` and the new 1 `jovra.fixture.trend` fixture (9 cases, 67 hand assertions). `FixtureManifest.pending` is empty. |
| `spec-generate-validate.log` | `generate_fixtures.py` regenerates every existing fixture byte-for-byte and adds only `spec/fixtures/trend/TR01-pooled-trends.json`; `validate.py` passes, including the new `jovra.fixture.trend checks` (re-run of the reference engine plus the hand assertions). |
| `spec-python-tests.log` | `scripts/spec/test_*.py`, including `test_trend_fixture.py`: an averaging engine, a hand-edited expectation and an unknown field are each refused. |
| `native-verify.log` | Independent Python checks of what Swift wrote: the session JSON re-validates against the session schema (`validate.py --encoded-dir`), the stats outputs are byte-equal to the goldens (`verify_native_stats.py`), and the Export-my-data and Share Pack bundles pass `verify_native_bundle.py` (export schema, file list, sizes and SHA-256 by hashlib, session schema, golden CSVs, self-contained viewer, negative controls refused). |
| `csv-byte-compare.log` | `cmp` of the Swift-written `points.csv` and `stats.csv` against `spec/fixtures/sample`: identical (19,629 and 1,761 bytes). |
| `mutation-red.log` | Red run: with buckets never hidden, the weakest-provenance rule inverted (`max`) and the stats diff comparing percentages instead of fractions, the trend fixture, the provenance tests and the point-42 diff test fail. |
| `share-pack-viewer.sample.html` | The Share Pack `index.html` Swift generated for the labelled Sample match. |
| `share-pack-viewer-{light,dark,large}.jpg` | That viewer in headless Chrome at 500 px: light, dark (DesignSystem tokens) and 150% text. |

## Acceptance criteria

- All `jovra.fixture.stats` files pass (StatsRunner, 3 fixtures) and their Swift outputs are byte-equal to the goldens.
- Sample fixture: fold and stats deep-equal; both CSVs byte-identical; overview 124 points, 58% (72/124), 67% (40/60),
  70% (28/40), 386 shots (`sampleOverviewStatsMatchIndependentValues`, SampleRunner).
- Weakest provenance: `oneEstimatedContributorMakesTheStatEstimatedWithOneUnreviewedPoint` folds a stats fixture whose
  first point is an unreviewed estimate through the real engine: points won is `estimated` with 1 unreviewed point.
- Trend fixtures: 1/2 + 30/40 = 31/42 = 74%; a bucket under 20 points is hidden; +4 from displayed integers (raw 3.33);
  sample sessions excluded; Python generates them with hand assertions and Swift's TrendRunner passes them.
- Session JSON schema validation in CI: the `native-data-export` job (unchanged) plus the new bundle verification.
- `StatsEngine.diff` after flipping point 42: the reference value is **68/116**, not 71/124. Point 42 (seq 42) is
  Alex's in the sample; giving it to Jon breaks serve, the match ends 8 points earlier, so points won goes
  72/124 -> 68/116. The test checks this against the Python reference and that exactly the reference's changed
  stats are listed (the 18 unchanged lines are not).
- Pending allow-list: already empty on main (`jovra.fixture.sample` removed in #357, stats earlier).
