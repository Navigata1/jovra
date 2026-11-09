# S88 exact-main adoption candidate

The adopted planner package and workflow are byte-identical to [draft #394](https://github.com/Navigata1/jovra/pull/394) at `b9c6bf156f39a6e971e438863587617498eee935`. The package tree is `ecc31a7423b1839b7d828ff8774670dc98937b93`. This branch starts from `d1f13ab87fb5ac129506de1e8ff5e746cac0fd76`. The backend README combines the current Supabase status and the planner row. The original [Claude PR #389](https://github.com/Navigata1/jovra/pull/389) at `14d5b71aa38c52e7751381b957474f259077cba3` and draft #394 retain their branches and prior evidence.

The tested source is `a71f91e17e1e6e973208e4a850a61d1d6dfb65fc` with tree `74ec9fa6c19483638d308a5ec7272847a76a0ca3`. The adoption preserves the test-only fixture patcher, inherited property and path refusals, and canonical Unicode checks. The scoped historical evidence remains under [adoption](../adoption/README.md).

## Fresh local checks

- Node 24.15.0 and npm 11.12.1. A lockfile install, strict typecheck and all 185 tests passed.
- The [parity table](parity-table.md) has 143 byte-identical results (58 director, 46 planner, 39 compile). Seven stored base contexts are separate.
- The current-main Python Studio validator passed. It checked reference records and vectors without regenerating media.
- Scratch commit `bad4b55182faddea94bf805a09018b5e665965eb` changed one expected estimate from 184500 to 184501 ms. The normal Node test command exited 1 with three related failures. The parity command exited 1 with 142 of 143 matches. The scratch change remains local, and rerunning parity on the adoption branch restored 143 of 143. See [results](results.txt) and the [one-line patch](scratch-vector.diff).

```sh
cd backend/planner
npm ci --no-audit --no-fund
npm run typecheck
npm test
npm run --silent parity
# From the repository root
python3 scripts/spec/validate_studio.py
```

## Review boundary

This is a review draft for an inherited package of roughly 4,100 changed non-evidence lines. It needs a split or explicit review scope decision before promotion. The local negative run covers the commands used by the workflow. A hosted negative run from the new scratch branch remains pending. The new draft requires fresh hosted green and review on its published head.

Current main includes S09 Python transition compilation and barcode vectors. The adopted TypeScript S88 request accepts the original S06/S07 fields and emits cuts. S09 transition parity and consumer wiring remain separate, along with S89 model adapters and any live Workflow or provider integration. [Issue #157](https://github.com/Navigata1/jovra/issues/157) stays open.
