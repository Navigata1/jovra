# backend-planner CI: green on the PR head, red with one vector altered

## Green: run 42467380866 (commit f51afeb, PR #389)
https://github.com/Navigata1/jovra/actions/runs/42467380866

```
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:29:35.4053672Z ℹ tests 176
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:29:35.4054735Z ℹ pass 176
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:29:35.4054944Z ℹ fail 0
backend-planner	Parity table against the S06 and S07 vectors	2026-11-08T09:29:36.0225707Z director (spec/studio/fixtures/vectors/director.json): 58/58 byte-identical, plus 1 base context case(s); results {"brief":16,"refusal":9,"reject":10,"templates":1,"findings":22}
backend-planner	Parity table against the S06 and S07 vectors	2026-11-08T09:29:36.0227907Z planner (spec/studio/fixtures/vectors/planner.json): 46/46 byte-identical, plus 1 base context case(s); results {"plan":23,"refusal":3,"check":4,"reject":16}
backend-planner	Parity table against the S06 and S07 vectors	2026-11-08T09:29:36.0229865Z compile (spec/studio/fixtures/vectors/compile.json): 39/39 byte-identical, plus 5 base context case(s); results {"edl":28,"refusal":6,"reject":5}
backend-planner	Parity table against the S06 and S07 vectors	2026-11-08T09:29:36.0231238Z TOTAL: 143/143 reference vectors reproduced byte for byte (canonical JSON).
```

## Red: run 42467957634 (commit 31a7fec: planner.json coach-cut-3min expect.estimate.totalMs 184500 -> 184501; reverted by the next commit)
https://github.com/Navigata1/jovra/actions/runs/42467957634

```
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:37:27.5033401Z ✖ a planner vector: moving one keeper window changes the output hash and the estimate (5.795646ms)
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:37:27.6052535Z ✖ planner plan coach-cut-3min (0.800299ms)
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:37:27.6165374Z ✖ every vector file has cases, and every re-run case is byte-identical (0.807049ms)
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:37:27.6259930Z ℹ pass 173
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:37:27.6260125Z ℹ fail 3
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:37:27.6271153Z ✖ failing tests:
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:37:27.6271792Z ✖ a planner vector: moving one keeper window changes the output hash and the estimate (5.795646ms)
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:37:27.6276966Z ✖ planner plan coach-cut-3min (0.800299ms)
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:37:27.6277547Z   AssertionError [ERR_ASSERTION]: planner coach-cut-3min: the port's output differs from the stored reference expectation
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:37:27.6278309Z   +   "the port's output differs from the stored reference expectation"
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:37:27.6282371Z     actual: [ "the port's output differs from the stored reference expectation" ],
backend-planner	Parity, binding and adversarial tests	2026-11-08T09:37:27.6283540Z ✖ every vector file has cases, and every re-run case is byte-identical (0.807049ms)
```
