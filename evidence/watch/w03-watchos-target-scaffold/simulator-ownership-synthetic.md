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
