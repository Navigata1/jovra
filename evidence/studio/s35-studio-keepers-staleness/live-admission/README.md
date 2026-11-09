# S35 bounded live event admission

Base: Claude PR #443, `332082ee912b5a3e53cdec95d602b2f39f16617c`. Tested correction: `2bf6d3d0c31c42e129ef6d753de39d682a07c73c`. No original branch or PR mutation.

A real project's staleness read now checks the authoritative primary session using the existing stable-primary read helper. It projects a saved core edit ahead of the Studio snapshot through the existing staleness rules without writing Studio records. `requireCurrentPlan` uses that same projection; real-project authority must be present, and Sample projects keep their existing isolated snapshot. The ledger's `lastChange` still means its last stored change. This is a point-in-time check; it does not lock the core session for a subsequent render.

`01-red.txt` records three public tests failing with eight assertions before implementation. An old plan was admitted after a saved correction, after reopening, without its core store, and after a deliberately interrupted Studio write. `02-green.txt` has all three focused tests passing. The disconnected-source assertion was refined from any `StudioProjectStoreError` on red to the exact new typed error on green.

The fault test interrupts the real `studio.json` temporary-file checkpoint after the film/ledger writes. It verifies the old project version and already-stamped film, reopens both stores, refuses the old plan, and successfully retries event reconciliation. This is injected write-fault and reopen evidence, not a process-kill or physical power-loss test. The unchanged unrelated project's plan remains admissible; a pre-refresh read leaves the project revision and film record unchanged.

`03-studio-core-full.txt` records exact-source macOS package verification with Swift 6.4.2: 144 tests in 29 suites passed, including all 26 keepers and nine staleness vectors. Original raw logs are in `/tmp/jovra-s35-*.txt.raw`; the tracked logs only strip trailing whitespace and identify the evidence boundary.

No persistence algorithm, privacy policy, keeper ranking, source contract, workflow, or renderer was changed. This is not full issue #104 acceptance: automatic notifications/subscription, match-footage privacy exclusion, durable sync/keeper multi-file reconciliation, fresh current-main integration, and current-head hosted checks remain separate. Keep #443 unmerged. Its original ancestry still needs the repository's public-contact adoption before publication; all new commits use the approved identity.
