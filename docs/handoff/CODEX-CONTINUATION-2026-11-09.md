# JOVRA continuation · November 9

Start with [Claude's November 8 pipeline handoff](CLAUDE-HANDOFF-2026-11-08.md)
and [issue #382](https://github.com/Navigata1/jovra/issues/382). Refresh main and
open PRs before acting. Preserve Claude's worktrees and the private media.

## Current evidence

- On app source `97319ca2101add644fb0b07bcb7d5fa839f14986`: full CoreFlow passed 1/1 on the owned iPhone simulator, including Replay and Export audits and relaunch. The actual synthetic session and export passed schema, references, canonical JSON and exact points/stats CSV checks. The pre/post original hash matched and both original and export decoded through their ends; export has 30 ordered frames. Full Core 12 XCTest and 122 Swift Testing, 209 shared spec documents, 82 native conformance outputs, two exports and two bundles passed. Private SSD receipts are in `JOVRA-Review-97319ca.PxV5Ep` and `JOVRA-Core-97319ca-hahwlrk7` under `/Volumes/JovraA02-F46A6DA7`. Signed physical tests on this new source remain open.
- On product source `0706e4c1f031a6648b48b13d5fbbd5aec2b56c76`: dedicated iPhone
  simulator CoreFlow passed 1/1 after rendering the 11 sample media files and
  matching their decoded-frame hashes. Its iOS and spec trees match the tested
  checkout; the later recovery change was re-tested on main as noted above. Independently checked the actual
  synthetic session and export JSON, canonical encoding, corrected scoring
  CSV, stats CSV and one-second 30-frame decoded clip.
- iPhone 15 Pro Max on earlier main product source `d1f13ab`: a live-camera recording
  reopened after the test terminated the app, and a separate pause/resume,
  save and replay test passed. The original first save attempt failed because
  the test did not dismiss the camera permission explanation. No loss bound,
  call/alarm interruption, thermal, power-loss or endurance gate has passed.
- iPhone 15 Pro Max / iOS 27.0.1 on product source `0706e4c`: live capture
  passed a Home-background, return, resume, save and Replay test (1/1).
  Saved metadata shows two camera segments, an `interruption` gap and
  `savedWithGaps`; both segments decoded through the end (279 and 360 frames).
  The signed test build used unchanged product source with a separate XCTest.
  Private receipt: `device-background-main.xcresult` under the local evidence
  directory below. Calls, alarms, resets, crash-loss bounds and endurance remain open.
- iPad Pro simulator CoreFlow on main failed the Replay Pause Dynamic Type
  audit. Proposed source `725c0a3` passed its AX5 transport test; the unchanged
  CoreFlow audit then timed out twice on iOS 27.2, including an isolated rerun.
  On iOS 26.5 it passed Replay but failed an unbound Export accessibility
  finding. The Replay fix [#453](https://github.com/Navigata1/jovra/pull/453)
  plus Export backdrop [#456](https://github.com/Navigata1/jovra/pull/456)
  then passed the complete unchanged iPad CoreFlow audit on iOS 26.5. The
  combined iOS 27.2 run timed out at Replay. A contrast-first probe passed,
  but an all-types-first probe timed out at the same geometry. Seven named
  iOS audit types passed individually and the remaining `.all` mask timed out.
  The per-type legacy record/log reports failure; the modern summary is
  incomplete after a duplicate result-path invocation. Raw receipts are retained locally in
  `/Users/IDC2.5/JOVRA-media/codex-evidence/2026-11-09`.
- The supplied private media is described in `docs/fixtures/real-footage.md`.
  The original February match and two-minute excerpt matched their recorded
  hashes. The full match imported through Files and opened in Replay on iPhone.
  The actual retained file copied back from the device matches the original
  and session SHA-256 and byte count. The importer records a practice video.
  A temporary Files-enabled build was used and the standard build restored.
  One picker probe was interrupted and a second failed to start import before
  selecting the actual file cell succeeded. The temporary Documents source
  copy was hash-checked and removed from Documents. The imported original
  remains in the JOVRA session. Keep video and device diagnostics out of GitHub.

## Review and fixes

- Synthetic partial-recovery cold-relaunch harness `1d329a3` passed all three isolated simulator phases. After a token-owned two-segment capture and verified app termination, only the first synthetic segment was damaged. The first fresh launch showed the partial notice and playable Sample row; the next launch reopened it without another notice or storage rewrites. The retained capture mark and session schema/references passed, and the kept segment decoded through 149 frames. Private evidence is under `/Volumes/JovraA02-F46A6DA7/JOVRA-ColdRelaunch-1d329a3.aMB9UV`. This is not physical crash-loss or power-loss proof.
- Partial startup recovery [#463](https://github.com/Navigata1/jovra/pull/463), merged as `97319ca`, adopts verified playable footage when another segment is damaged or missing. On tested source `176db13`, 78 Media and 45 benchmark tests passed, along with 2/2 app-hosted startup tests using an isolated simulator host ID. The hosted test exercises the recovery summary and Library model; a later isolated synthetic UI run verified cold relaunch as noted above. The damaged original, journal, marks and edits are preserved; recovery may truncate a verified torn segment to its playable prefix. An external writer after the witness check and physical crash-loss remain open. The full current-main Core and CoreFlow gates passed afterward; signed-device gates remain open.
- The tested cold-relaunch harness is split into reviewed [#468](https://github.com/Navigata1/jovra/pull/468) (host custody), merged as `2bc30a6`, and [#469](https://github.com/Navigata1/jovra/pull/469) (UI phases), merged as `d51d952` after retargeted review and fresh CI. The assembled tree matches tested `1d329a3`; these test-only merges leave the app source, existing CoreFlow runner and spec unchanged.
- Fresh watch simulator matrix on reviewed source `59e89ed`: Ultra 3 passed 19/19; Series 11 42 mm and SE 3 40 mm each passed 18/19, with different health-surface harness failures. No actual test was retried; a separate Series invocation rejected a CLI argument before any test. All test-owned pairs were removed after custody verification. Private matrix receipts: `/Volumes/JovraA02-F46A6DA7/JOVRA-W03-small-watch.9zJIgNws`. Physical watches, WatchConnectivity, companion embed and owner gates remain open.
- The earlier local Android A03 helper remains on hold after fake-SDK directory-redirection and late-lock races; do not run it on real AVDs. Reviewed fake-only acquisition draft [#471](https://github.com/Navigata1/jovra/pull/471) passes eight tests but has no real SDK adapter or operational CLI, and #181 remains open.
- Match-import opt-in [#457](https://github.com/Navigata1/jovra/pull/457)
  merged as `0706e4c`. Reviewed head `6926587` passed six hosted and two UI
  tests on the iPhone simulator and every required hosted check. It requires explicit match setup and per-video
  confirmation and begins with an empty score log. The first UI run failed
  on a clipped tap, retained as evidence. Real-provider match opt-in and AX5
  are still unverified.
- Watch simulator safety follow-up [#455](https://github.com/Navigata1/jovra/pull/455)
  is a reviewed draft. The prior alert acknowledgment test passed 1/1 on a
  newly created Apple Watch Ultra 3 / iPhone simulator pair. A subsequent
  full watch suite was interrupted at the disk floor. A later fresh Ultra 3 /
  iPhone pair ran the full suite on `59e89ed` and passed 19/19 (9 fake-bridge,
  10 harness); its private receipt is under `/Volumes/JovraA02-F46A6DA7/JOVRA-W03-59e89ed-ay6eq_2o`. Only test-owned pairs and simulators were removed. Companion install, live WatchConnectivity, real watches, Series/SE matrix and W03 owner decisions stay open.
- Studio demo boundary follow-up [#454](https://github.com/Navigata1/jovra/pull/454)
  has passed 171 macOS package tests and its corrected-head Linux Studio job.
  Full S14 acceptance and parent integration remain open.
- [#441](https://github.com/Navigata1/jovra/pull/441) remains blocked on the
  failed 0.10 m calibration criterion and persisted validity. Bounded
  validity correction [#448](https://github.com/Navigata1/jovra/pull/448)
  is a draft against its branch, independently reviewed, 18 focused tests
  passed. Full T13 stays open.
- [#442](https://github.com/Navigata1/jovra/pull/442) remains blocked on
  playback and acceptance findings. Draft [#449](https://github.com/Navigata1/jovra/pull/449)
  corrects stale frames, shifted loops and close-vs-proxy publication. The
  final correction has 15 focused tests and one timing test. Full T14 remains
  open for wider acceptance and integration.
- Lesson relationship fence [#459](https://github.com/Navigata1/jovra/pull/459)
  and actual-media custody draft [#461](https://github.com/Navigata1/jovra/pull/461)
  have independent bounded reviews. #461 checks on-disk originals and the recording
  snapshot (157 StudioCore and six StudioMedia tests). The proof is point-in-time;
  cross-store atomicity, native wiring and full S36 acceptance remain open.
- [#443](https://github.com/Navigata1/jovra/pull/443) remains blocked on
  stale-plan, privacy and crash consistency. Draft [#447](https://github.com/Navigata1/jovra/pull/447)
  protects the live event-admission seam; 144 StudioCore tests passed on its
  tested source. Automatic subscriptions, privacy exclusions, renderer wiring
  and general multi-file durability remain open.
- The verified S88 planner continuation [#452](https://github.com/Navigata1/jovra/pull/452)
  remains draft. S06/S07 parity is covered; reviewed S09 transition tracer
  [#458](https://github.com/Navigata1/jovra/pull/458) matches all six shared
  compiler results. Renderer parity and oversized inherited scope remain open.
- The unsigned Android owner proposal is draft [#451](https://github.com/Navigata1/jovra/pull/451).
- A02 shell work is underway in an isolated APFS image on Extreme SSD.
  A first guarded Gradle attempt stopped before tests at the 9 GiB safety
  buffer protecting the 8 GiB floor. Its last sample was about 8.75 GiB; the
  separately observed system free space subsequently fell below 8 GiB. That
  initial attempt is not a product result. The resumed [A02 draft #460](https://github.com/Navigata1/jovra/pull/460)
  passed 18 Android and 8 JVM tests. Its verified debug APK installed without
  replacement, launched, and opened five placeholder tabs on Pixel 6 Pro.
  Foldable hardware, accessibility, full product features and owner gates remain open.
- Files duplicate service [#466](https://github.com/Navigata1/jovra/pull/466) and UX [#470](https://github.com/Navigata1/jovra/pull/470) are reviewed drafts. The late-cancellation race was fixed with 5/5 hosted tests; native simulator picker selection and cancellation attempts failed, so do not claim provider acceptance. A guarded physical v4 probe imported a synthetic video and used Open Existing to reopen the same session, then failed before cancel/second-copy testing when retry picker navigation differed. A separately isolated v5 probe again reopened the same session and reached native Cancel, but failed when the picker did not dismiss. Both runs are failed overall. A separate, single focused wrong-file/explicit-copy physical test passed 1/1: session counts 0→1→1→2 and the original session stayed unchanged, with two final copies matching the intended synthetic video. It does not clear native Cancel. A separate swipe-dismiss physical attempt also failed: the picker stayed open and re-opening was not reached; only C0/C1 and one current session ID were confirmed, with no post-swipe content-digest proof. V3, v4, v5, wrong-copy, swipe and two manual-test alternate apps and runners remain installed; v4/v5 each retain two synthetic fixtures and one session, wrong-copy retains two fixtures and two sessions, and swipe/manual tests each retain two fixtures and one session. Original JOVRA and real footage were untouched. Retain all failures; the broad Media run was interrupted.
- User-assisted Files dismissal: the first isolated attempt timed out without observing picker dismissal. At the user’s request, a second isolated attempt observed the user-confirmed first picker dismissal and a same-live native picker reopening, then failed exact folder verification. The user separately reported touching the phone again; timing relative to the failure and causation are unverified. It has C0/C1 only; no REOPENED marker or C2. Do not infer causation or a full pass. Private receipts are under `/Volumes/JovraA02-F46A6DA7/JOVRA-T26-manual-dismiss-build.Jh1kAl/physical-run.1dOVoW` and `/Volumes/JovraA02-F46A6DA7/JOVRA-T26-manual-retry-build.mE40UR/physical-run.Hk6JTH`.
- The separate swipe-dismiss physical test failed 0/1; the verified in-sheet drag did not dismiss Files. Native Cancel and swipe dismissal remain open; do not interpret this as the wrong-file/copy result. Private receipt is under `/Volumes/JovraA02-F46A6DA7/JOVRA-T26-swipe-dismiss-build.nz7MMN/physical-run.iGz0Ec`.
- The separate physical wrong-file/explicit-copy test uses test-only alternate composition `c15451a`; private evidence is under `/Volumes/JovraA02-F46A6DA7/JOVRA-T26-wrong-copy-build.ibeiiS/physical-run.vxVnDq`. The earlier Cancel failure, external providers, match import and full T26 acceptance remain open.
- The three-call iPad Replay audit-prefix diagnostic `b28c4c8` passed with no issue callbacks. It did not reproduce the clipped callback seen before the full CoreFlow timeout and does not close that gate. Its private receipt is under `/Volumes/JovraA02-F46A6DA7/JOVRA-iPad-prefix-b28c4c8-US0A5M2Q`.
- Fresh iPad diagnostics `d3a13e7` passed remainder-only at top and the recorded two-swipe viewport; a separate first-only `.all` diagnostic `bd3a8d7` passed at the same position. A subsequent fresh full unchanged CoreFlow on candidate `8a0c5e0` still failed in Replay with audit Code -56 before Export. The full iOS 27.2 gate remains open. Private receipts are under `/Volumes/JovraA02-F46A6DA7/JOVRA-iPad-d3a13e7-k7qcvxi6`, `/Volumes/JovraA02-F46A6DA7/JOVRA-iPad-all-bd3a8d7-0rq56v3m`, and `/Volumes/JovraA02-F46A6DA7/JOVRA-iPad-CoreFlow-8a0c5e0-a4fzet4a`.
- Android foundation [#378](https://github.com/Navigata1/jovra/pull/378)
  has owner-gated ADR issues [#375](https://github.com/Navigata1/jovra/issues/375)
  and [#376](https://github.com/Navigata1/jovra/issues/376). Watch foundation
  [#407](https://github.com/Navigata1/jovra/pull/407) still requires a recorded
  core-owner review and full automation verification, with embedding tracked in #419. S88 #389/#394
  still needs coordination.

## Immediate continuation

1. Finish diagnosing iOS 27.2 Replay audit timeouts. CoreFlow on product source
   `97319ca` passed on the iPhone simulator after recovery integration. The contrast-first probe
   passed and the all-types-first probe timed out. Preserve all prior failures
   and keep the original full audit as the acceptance gate.
2. Continue T26 Photos, batches, duplicate handling, provider and interruption
   criteria. The full match is already imported as a practice video and verified.
3. Re-query PR heads and gates, finish independent reviews, and integrate
   bounded fixes safely. Keep the original full ticket criteria open.
4. Continue native platform and Studio work through their DAGs. Obtain the
   specified ADR-owner and watch review decisions through their existing gates.
