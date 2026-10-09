# T05 bounded native stats — work in progress

Authorized seams: StatsEngine.compute over the public MatchTimeline; typed metric evidence for honest UI values; canonical session data and exact points/stats CSV export in a subsequent bounded slice. Tests use independent shared fixtures and the hand-derived sample overview (124 points, 72/124=58%, 40/60=67%, 28/40=70%, 386 shots).

The first public sample-overview test failed at the absent StatsEngine API (01), then passed with the typed port (02): one Swift Testing test, 124 points, 58% total points won, 67% first serves in, 70% first-serve points won and 386 shots. Full independent corpus and evidence projection verification follow; no full-ticket completion is claimed.

The closed shared StatsResult shape stays intact, with concrete model fields and exact two-integer momentum pairs. A separate typed evidence projection will preserve contributing point IDs, weakest provenance and unreviewed counts; no observations means no claimed measurement in the UI. The existing independent fixtures remain the numeric authority. Full T05 stays open for pooled trends, complete Export-my-data/Share Pack layouts and any unused full-ticket criteria.

The headline evidence API failed at the absent `metric` seam (03), then passed the weakest-input test (04): Estimated, 124 contributing points, nine unreviewed points, and Sample. The convention-discovered runner (05) compares every scoring checkpoint's full stats result plus the three stats-kind fixtures. `T01-integer-percentages` is correctly consumed by the existing pct-kind runner. The independent Python comparator (06) confirms all **110** native results match closed schemas and exact golden canonical bytes, including unknown-field refusal controls. Only the sample fixture kind remains pending until the subsequent CSV export slice.

Reproduce the complete numeric corpus:

```sh
JOVRA_STATS_OUTPUT_DIR=/tmp/jovra-stats-out swift test --package-path ios/Packages/JovraCore --jobs 2 --filter allDiscoveredRunnerFixturesPass
python3 scripts/spec/verify_native_stats.py /tmp/jovra-stats-out
python3 scripts/spec/generate_stats_models.py
git diff --exit-code -- ios/Packages/JovraCore/Sources/JovraCore/Stats/StatsModels.swift
```

The bounded display projection supports points, points won by side, first serves in by side, first-serve points won by side and shots. It uses every denominator contributor, ranks Estimated below Manual below Reviewed below Validated, and records Sample independently. An observed zero remains a number; absence of observations returns no value or provenance. No pooled trend, backend, analysis capability, native UI or device validation is claimed by this slice.

Final controls (07) pass: chosen-side denominator contributors, no observations versus an observed zero, required nullable duration and fixed momentum-pair refusals. The full Core gate (08) passes **12 XCTest cases in 207.13 s plus 48 Swift Testing tests in 4.74 s**, including the existing 1,000-event store operations and complete typed corpus. The production implementation was unchanged after this full build. Four additional setup/assertion lines in the same public evidence test verify the ticket's exact one-estimated/one-unreviewed case; final focused run (10) passes. Attempt 09 waited on the still-running SwiftPM cache lock and was terminated before compilation; it is explicitly nonqualifying evidence. Independent Standards review at source candidate `106293d` records zero findings; Spec review is separate.

Publication source rebind: both independent axes accept `6ba0b3a` after reconciling current main `3ae5caa`. Stats source/tests/generator/comparator remain byte-identical to `106293d`; the small documentation correction reconciles existing shared-contract decision 4 without changing reference fixtures or engine behavior. Evidence-only commits follow. The earlier local full gate predates the latest directory-durability composition; fresh Linux CI must validate that combined tree before merge.

A subsequent glossary pass found an identifier breach: the Stat entry avoids Metric. Initial Standards acceptance is preserved in `independent/STANDARDS-SUPERSEDED.md` and withdrawn on that naming axis. The correction changes only selector/API/local vocabulary to `StatSelector` and `StatsEngine.stat`; exact corrected-head focused/corpus gates and fresh Linux CI follow before merge.

Corrected vocabulary gate (11) passes six focused/corpus Swift tests on the latest directory composition; all 110 independently emitted schema/canonical results still pass (12). Numeric engine/models/fixed-pair bytes are unchanged; only `StatsMetric` → `StatSelector`, `StatsEngine.metric` → `StatsEngine.stat`, selector/stat locals and test identifiers changed. Standards and Spec must rebind this exact corrected source before the PR's fresh CI can authorize merge.
