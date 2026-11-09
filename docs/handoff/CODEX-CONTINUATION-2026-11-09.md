# JOVRA continuation · November 9

Start with [Claude's November 8 pipeline handoff](CLAUDE-HANDOFF-2026-11-08.md)
and [issue #382](https://github.com/Navigata1/jovra/issues/382). Refresh main and
open PRs before acting. Preserve Claude's worktrees and the private media.

## Current evidence

- Main `d1f13ab87fb5ac129506de1e8ff5e746cac0fd76`: dedicated iPhone
  simulator CoreFlow passed 1/1 after rendering the 11 sample media files and
  matching their decoded-frame hashes. Independently checked the actual
  synthetic session and export JSON, canonical encoding, corrected scoring
  CSV, stats CSV and one-second 30-frame decoded clip.
- iPhone 15 Pro Max on the same product source: a live-camera recording
  reopened after the test terminated the app, and a separate pause/resume,
  save and replay test passed. The original first save attempt failed because
  the test did not dismiss the camera permission explanation. No loss bound,
  call/alarm interruption, thermal, power-loss or endurance gate has passed.
- iPad Pro simulator CoreFlow on main failed the Replay Pause Dynamic Type
  audit. Proposed source `725c0a3` passed its AX5 transport test; the unchanged
  CoreFlow audit then timed out, leaving the original audit unresolved.
  Receipts remain in `/private/tmp/jovra-nov09/` on this Mac.
- The supplied private media is described in `docs/fixtures/real-footage.md`.
  The original February match and two-minute excerpt matched their recorded
  hashes. A temporary local iPhone build exposes its Documents folder for the
  Files test. The first real-match picker test was interrupted after no import
  staging appeared. The corrected picker-confirmation probe is running.
  Keep video and device diagnostics out of GitHub.

## Review and fixes

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
- [#443](https://github.com/Navigata1/jovra/pull/443) remains blocked on
  stale-plan, privacy and crash consistency. Draft [#447](https://github.com/Navigata1/jovra/pull/447)
  protects the live event-admission seam; 144 StudioCore tests passed on its
  tested source. Automatic subscriptions, privacy exclusions, renderer wiring
  and general multi-file durability remain open.
- Android foundation [#378](https://github.com/Navigata1/jovra/pull/378)
  has owner-gated ADR issues [#375](https://github.com/Navigata1/jovra/issues/375)
  and [#376](https://github.com/Navigata1/jovra/issues/376). Watch foundation
  [#407](https://github.com/Navigata1/jovra/pull/407) has the recorded owner
  review and automation gates, with embedding tracked in #419. S88 #389/#394
  still needs coordination.

## Immediate continuation

1. Finish the real-match Files import and verify saved-original size and SHA-256
   against the guide, plus replay. Preserve the interrupted first attempt.
   Restore the normal app configuration afterward without uninstalling.
2. Run the unchanged iPad CoreFlow audit against the proposed fix without
   concurrent device/build activity. Preserve both earlier failures. Do not
   weaken the audit.
3. Re-query PR heads and gates, finish independent reviews, and integrate
   bounded fixes safely. Keep the original full ticket criteria open.
4. Continue native platform and Studio work through their DAGs. Obtain the
   specified ADR-owner and watch review decisions through their existing gates.
