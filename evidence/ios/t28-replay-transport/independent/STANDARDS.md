# Standards — bounded native Replay model

Read-only exact6a226b9496b07061c1feb1a65c7532968086e1fe, two source/test files newly added against its parent. Applied CLAUDE.md, GLOSSARY.md, DEVELOPING Swift6 concurrency conventions, code-review documented rules and Fowler smell baseline.

0 documented-standard breaches;0 Fowler heuristic findings in source104/test66 lines. MainActor Observable presentation state is separate from the existing library/media actors. Generation tokens reject stale completions after close/open; local errors preserve ordinary-player fallback, frame count/rate come from probe/full decode, and exact stepping explicitly declines VFR. No original writes, network/account changes, fake decoded count or device-validation claims appear. Public tests create actual FixtureCamera/AVAssetWriter saved media and assert decoded120frames and exact0→1→0 stepping without source mutation, plus missing-original state.

Static disposition: ACCEPT source design only. Evidence records intended absent-model compiler RED and a repaired build error, but native2 focused runtime is still pending; no execution, full T14/T28, UI, playback seek timing, VFR index or product acceptance inferred. Final exact-head/source binding and runtime owner receipt required before publication acceptance.

## Corrective transport rebind

ACCEPT bounded exact2ee0d0ae6ea32f75865c3f5da9e7c6de51093211. Root/Spec identified the actual transport defect: stepping used cached still0 after a player seek1s. Independently read05 actual1PASS/1FAIL (observed1 vs expected31), source correction and07 actualnative2PASS/0failure/0skip summary; reviewer did not rerun native tests. Source now stores the verified CFR rate, pauses and anchors stepping to numeric finite current playhead with decoded bounds, resets that rate when closing/changing source, and still guards stale async completions. Added meaningful actualAVPlayer seek/pause/step control; prior static-only receipt remains historical, not full transport acceptance.

0 new documented-standard breaches;0 Fowler heuristic findings. Native UI, full T14/T28, timing/proxy/VFR indexing remain pending. Runtime proof belongs to author's exact source/custody receipt; no physical-device or product readiness inferred.
