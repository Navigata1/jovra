# W03 simulator ownership

Base: `b815e6b2dbb698ad61e1cc78f62bfc937ba52cc0` (PR #407). Tested source: `335c8cc44f22774a3be0ae3703f624a61c3b0372`.

The shell tests run the public `watch-sim.sh` command in a temporary checkout with a synthetic `xcrun`. No real simulator was queried, created, booted, shut down, paired or deleted.

| Check | Observed result |
| --- | --- |
| Exact-base negative control | Nine failures across create, delete and UUID lookup. For each collision, the old script adopted the foreign UUID, mutated the synthetic inventory on create and delete, or returned the foreign UUID on lookup. The collisions were an iOS device, an older watchOS runtime and a watch with the requested runtime and type. |
| Corrected negative control | All nine cases refuse and leave the synthetic inventory and mutation log untouched. |
| Checkout-owned lifecycle | Creates three expected watches, resolves their UUIDs, reuses only those recorded UUIDs, then shuts down and deletes only those UUIDs. The unrelated synthetic device remains unchanged. |
| Recorded identity drift | Substituted UUID, changed type and changed runtime each block lookup and deletion. |
| Paired watch | Delete refuses before any mutation and replaces a prior PASS receipt with FAIL. |
| Before/after comparator | Fails when a foreign UUID disappears, including one with a reserved name. |

```sh
bash -n scripts/ios/watch-sim.sh
python3 -m unittest discover -s scripts/ios/tests -t scripts/ios -p 'test_watch_sim*.py' -v
scripts/l10n/check.sh
```

The focused run passed 13 tests. Localization checks passed 32 localization tool tests and 25 iOS script tests, with zero literal violations and zero copy findings. The exact-base failures and final outputs are retained locally in `.scratch/03-exact-head-ownership-red.log`, `.scratch/06-watch-final-l10n.log` and `.scratch/07-watch-final-controls.log`.

This evidence covers script behavior with synthetic inventories. The real simulator lifecycle and the clean alert acknowledgement rerun are still pending. The core-owner review of the project configuration and the decision on companion embedding (#419) remain open.

## Cross-checkout custody

This correction was tested at `d66e1a40e3989355f198b46b903fc5f471490b17` against `110fb1b9d4007558560f3873637b78f9c3547270`. The control creates two Git worktrees in a temporary repository and uses one fake simulator inventory. With a symlinked cache, the previous source let the second worktree resolve the first worktree's UUIDs, reuse them during create, and delete them. Copying the first checkout's receipt into an ordinary local directory also let the second checkout delete them. All four expectations failed on the previous source.

The helper now rejects shared custody paths and checks that the receipt belongs to the canonical checkout that allocated the watches. The corrected test verifies that the second worktree cannot reuse a shared or copied receipt. The original worktree can still resolve its watches, and the inventory and original receipt remain byte-for-byte unchanged after the refusals.

The final focused gate passed 14 tests. Localization checks passed 32 localization tool tests and 26 iOS script tests, with zero literal violations and zero copy findings. Shell syntax and diff checks passed. The raw pre-fix and final output is retained in `.scratch/08-watch-shared-custody-red.log`, `.scratch/11-watch-shared-custody-final.log` and `.scratch/12-watch-shared-custody-final-l10n.log`. All simulator calls were synthetic.

## Safe receipt publication

This correction was tested at `1fe54da58c280db7577c7e24c1e1d43dbef289bd` against `1b26ffcd4420b0ff1d6484879afcf47125340808`. A public `watch-sim.sh create` with fake `xcrun` previously returned PASS while overwriting an external sentinel through a stale `owned.tmp` symlink. An independent control blocked the receipt destination and found that the old source leaked its temporary file.

The corrected helper writes through the file descriptor of an exclusively allocated temporary file in the receipt directory. It atomically replaces the receipt and cleans up its temporary path on failure. The final create control preserved both the external sentinel bytes and the stale symlink, committed all three synthetic device identities, and left no new temporary file. The blocked-destination control preserved the blocker, removed the newly allocated temporary file, and returned failure.

The final focused gate passed 16 tests. Localization checks passed 32 localization tool tests and 28 iOS script tests, with zero literal violations and zero copy findings. Shell syntax and diff checks passed. The raw pre-fix and final output is retained in `.scratch/13-watch-receipt-temp-red.log`, `.scratch/14-watch-receipt-temp-cleanup-red.log`, `.scratch/15-watch-receipt-temp-final.log` and `.scratch/16-watch-receipt-temp-final-l10n.log`. All simulator calls were synthetic.

## Pair recheck and safe evidence reports

The final script and tests are bound to `e74c4f2771bce6c3628582085824972b7947547a`, based on `312cc34eb4494bec42aab464f42cb74993736415`. The fake simulator adds a pair during shutdown. The previous helper still issued delete and returned PASS. The corrected helper observes the new pair, refuses deletion, and preserves all recorded identities and receipt bytes.

The report control covers both successful create and refused delete. The previous helper followed the report symlink in both paths and overwrote the external sentinel. The corrected helper uses the existing exclusive temporary-file and atomic replacement pattern for both reports and ownership receipts. A stale final report symlink is replaced by a regular report and its external target stays byte-identical. The existing test still verifies that a refused delete replaces a regular prior PASS report with FAIL.

Cleanup checks identity and pairing again after shutdown. The checkout lock cannot coordinate external pairing commands, so a pair change between the final query and delete remains possible. A simulator allocated before a failed ownership receipt publication remains an unrecorded collision. This evidence covers synthetic calls only.

[Command excerpts](pair-report-synthetic-results.txt) record three expected failures across two new controls on the previous source, then 18 focused tests passing on the corrected source. The repository script gate passed 32 localization tool tests and 30 iOS script tests, with zero literal, copy, or catalog-ownership findings. Shell syntax and diff checks passed. Full local receipts are in `/tmp/jovra-w03-pair-report.Jte0bE`.
