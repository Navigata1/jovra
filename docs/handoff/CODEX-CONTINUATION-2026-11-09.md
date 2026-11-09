# JOVRA continuation · November 9

Start with [Claude's November 8 pipeline handoff](CLAUDE-HANDOFF-2026-11-08.md)
and [issue #382](https://github.com/Navigata1/jovra/issues/382). Refresh main and
open PRs before acting. Preserve Claude's worktrees and the private media.

## Current evidence

- Main `0706e4c1f031a6648b48b13d5fbbd5aec2b56c76`: dedicated iPhone
  simulator CoreFlow passed 1/1 after rendering the 11 sample media files and
  matching their decoded-frame hashes. Its iOS and spec trees match the tested
  checkout. Independently checked the actual
  synthetic session and export JSON, canonical encoding, corrected scoring
  CSV, stats CSV and one-second 30-frame decoded clip.
- iPhone 15 Pro Max on earlier main product source `d1f13ab`: a live-camera recording
  reopened after the test terminated the app, and a separate pause/resume,
  save and replay test passed. The original first save attempt failed because
  the test did not dismiss the camera permission explanation. No loss bound,
  call/alarm interruption, thermal, power-loss or endurance gate has passed.
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

- Match-import opt-in [#457](https://github.com/Navigata1/jovra/pull/457)
  merged as `0706e4c`. Reviewed head `6926587` passed six hosted and two UI
  tests on the iPhone simulator and every required hosted check. It requires explicit match setup and per-video
  confirmation and begins with an empty score log. The first UI run failed
  on a clipped tap, retained as evidence. Real-provider match opt-in and AX5
  are still unverified.
- Watch simulator safety follow-up [#455](https://github.com/Navigata1/jovra/pull/455)
  is a reviewed draft. The prior alert acknowledgment test passed 1/1 on a
  newly created Apple Watch Ultra 3 / iPhone simulator pair. A subsequent
  full watch suite was interrupted at the disk floor. The test-owned pair and
  iPad simulators were removed after receipts were retained. Companion install,
  real watch validation and W03 owner decisions stay open.
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
  is independently reviewed. Real media custody and transaction durability remain open.
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
- Android foundation [#378](https://github.com/Navigata1/jovra/pull/378)
  has owner-gated ADR issues [#375](https://github.com/Navigata1/jovra/issues/375)
  and [#376](https://github.com/Navigata1/jovra/issues/376). Watch foundation
  [#407](https://github.com/Navigata1/jovra/pull/407) still requires a recorded
  core-owner review and full automation verification, with embedding tracked in #419. S88 #389/#394
  still needs coordination.

## Immediate continuation

1. Finish diagnosing iOS 27.2 Replay audit timeouts. CoreFlow on current main
   `0706e4c` has passed on the iPhone simulator. The contrast-first probe
   passed and the all-types-first probe timed out. Preserve all prior failures
   and keep the original full audit as the acceptance gate.
2. Continue T26 Photos, batches, duplicate handling, provider and interruption
   criteria. The full match is already imported as a practice video and verified.
3. Re-query PR heads and gates, finish independent reviews, and integrate
   bounded fixes safely. Keep the original full ticket criteria open.
4. Continue native platform and Studio work through their DAGs. Obtain the
   specified ADR-owner and watch review decisions through their existing gates.
