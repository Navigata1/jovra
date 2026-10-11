# SPEC review — bounded native ReplayPlaybackModel

HOLD exact6a226b9496b07061c1feb1a65c7532968086e1fe. Read104-line native model and66-line public controls. Read-only reviewer; no compiler/simulator.

Concrete transport finding: frame is initialized to decoded index0 and updated only by step. AVPlayer play/pause or seek advances the actual transport without updating frame. A user at1s who pauses then steps forward computes last-still0+1 and seeks back to1/30s, rather than frame31. Current step does not implement frame stepping relative to the current playhead. Root confirmed and is adding actual seek1s→pause→step31 public runtime RED before minimal verified-CFR anchoring. Current build-only proof is not runtime acceptance.

Other bounded model semantics are appropriate: existing authoritative library actor/session, no writes, original file resolved through custody seam, actual full decode frame count rather than duration×fps, decodable verified CFR gate for exact stepping, ordinary AVPlayer playback with honest unavailable exact-frame state, generation guards for stale asynchronous completions, explicit no-original state preserving session data. Full segment/gap UI, VFR index/transport, playhead-observed score and fullT28 remain open. Current failure control/corrective exact-head rebind pending.

## Corrective final SPEC acceptance — 2ee0d0ae6ea32f75865c3f5da9e7c6de51093211

ACCEPT frozen corrected bounded transport. The initial stale-still stepping finding is closed: step pauses the actual player, anchors from its current numeric playhead using verified CFR integer frameIndex, clamps to decoded frame bounds, then asks FramePlayback for the actual next image/time. Existing no-data/source fallback and generation cleanup remain.

Read genuine05 hosted RED1passed/1failed: exact Optional(1) vsOptional(31) after actual1s paused seek. Corrective06 build and07 hosted validPassed2/0/0 receipts inspected on dedicated4265 iPhone17Pro/iOS26.5; controls preserve original bytes, actual120 decoded frames,0→1→0 bounds, actual seek1s→31 and no-original state retaining document. Recomputed both source/test hashes matching final source-custody.json. No reviewer compiler/simulator.

No continuous playhead-derived score/readout, segment/gap UI, VFR index, missing-video recovery, fullT28 or finalCoreFlow claim. Any changed publication head requires explicit rebind; no remaining SPEC finding in frozen tested bounded model.
