# SPEC review — bounded exact decoded frame primitive

ACCEPT source head `1ba070e7916cd1ad56164247646ed802f6039506` against its actual base `3ae5caa`. Read-only review of FramePlayback.swift, public tests, T14/PlaybackController spec, and retained red/green receipts; no local native build by this reviewer.

The adapter supplies actual decoded CGImage frames, zero requested-time tolerances, preferred transform, normalized track-start time, decoded-index verification, typed range/unsupported-clock refusal, and cancellation checks. Public seeded controls decode 100 actual burned counters at each of 60/240 fps and assert exact index/time; retained full Media receipt reports 74 tests passed. Unsupported-clock control is an actual behavioral red followed by guarded green; earlier malformed-test compiler receipts are explicitly nonqualifying.

No bounded-scope SPEC finding. Caller-provided frame rate/count must be verified constant-rate values; imported variable-rate media requires a presentation index. Full PlaybackController chase seeks, speed controls, loops, proxy timing, video/jog UI and accessibility acceptance remain pending. This acceptance does not transfer the historical native receipt to a later merge head; fresh combined CI remains required. Reconcile latest main before publication so the already merged ClipExporter is retained.

## Integrated source rebind

SPEC ACCEPT `6b5515d` source rebind: exact FramePlayback production/test directory diff from accepted 1ba070e is empty. Root reports the integrated 78-Media gate includes merged Stats351/Clip352; this reviewer does not rerun it. Historical first frame receipt remains separately head-bound.

## Final exact publication head

SPEC ACCEPT `2c17fe11440249171e1105af0ce7223f3a07971b`. Production/tests remain byte-identical to accepted1ba070e; independently checked both retained SHA256 entries against the current source files. Read integrated07 receipt: 78 tests/15 suites passed after7.147s. No new execution by this reviewer; exact evidence provenance and bounded pending scope remain explicit.
