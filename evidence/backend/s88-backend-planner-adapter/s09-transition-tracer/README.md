# S88 S09 transition compiler tracer

This branch starts from draft [#452](https://github.com/Navigata1/jovra/pull/452) at `5b31bc6f8b5c3bcecc0cb827fb9378d81dec3e14`. Its default-branch base is `d1f13ab87fb5ac129506de1e8ff5e746cac0fd76`. The tested tracer source is `f5558b983f49011942a1737e562fc63071daafad`.

The TypeScript compiler accepts requested dissolves and dips, reports missing beats or unavailable operations, and runs its EDL validator on the result. Bed fades follow the before and after frame counts on the exact output clock. An overlong safe-integer request reaches the existing typed refusal instead of overflowing intermediate JavaScript arithmetic.

The six S09 compile cases in `spec/studio/fixtures/vectors/barcode-court.json` now match the complete stored Python compiler result. Five return an EDL with its canonical hash and one refuses protected contact blending. The comparison excludes the renderer frame, click and overlay maps, operation coverage and clean alternate that the Python fixture generator adds after compilation.

## Local evidence

The parent source with the new tests failed 11 of 12 focused tests. Node 24.15.0 strict typecheck and all 197 tests passed at the tested source. The original S06/S07 table still reports 143 of 143 exact matches. Independent Python calls agreed on the five additional control groups, including malformed requests, first-segment refusal, omitted transitions and the maximum safe integer frame span. The Studio validator passed without regenerating media.

[Command excerpts](results.txt) retain the failing and passing counts. Raw receipts and the small Python control runner are in `/tmp/jovra-s88-s09.7TPNeF`.

```sh
cd backend/planner
npm ci --no-audit --no-fund
npm run typecheck
npm test
npm run --silent parity
# From the repository root
python3 scripts/spec/validate_studio.py
```

This is local compiler evidence on a stacked branch. Current-head hosted checks, independent review, the #452 adoption decision, renderer-map parity, clean alternates, and live Workflow or provider execution remain separate. [Issue #157](https://github.com/Navigata1/jovra/issues/157) stays open.
