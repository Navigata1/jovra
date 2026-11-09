# JOVRA — next Codex session

**Latest implementation handoff:** [Claude → Codex, November 8 evening](CLAUDE-HANDOFF-2026-11-08.md), which follows the [November 8 continuation](CODEX-CONTINUATION-2026-11-08.md). The assessment below is historical.

Assessment: **2026-11-02**, America/Chicago. This is a source/verification handoff, not a production release.

Coordination issue: https://github.com/Navigata1/jovra/issues/382 (kept open for implementation follow-through).

## Start here

1. Read this file, `docs/reports/2026-11-02/README.md`, the enhanced HTML and `ops/mission/state.json`.
2. Read `CLAUDE.md`, `GLOSSARY.md`, `docs/agents/issue-tracker.md`, ADR-0006, `docs/spec/ios-v1-spec.md` and the acceptance criteria of the selected ticket.
3. Requery GitHub before changing code. The assessed default-branch head is `6e46a576240c587511f2f87a15d95507b7280158`. This handoff's publication adds documentation only; a later main may differ.

```sh
# Preserve the original checkout and its untracked planning files.
cd /Users/IDC2.5/jv
git status --short --branch
GH_TOKEN="$(gh auth token --user Navigata1)" git fetch origin
GH_TOKEN="$(gh auth token --user Navigata1)" gh pr list --repo Navigata1/jovra --state open --limit 100 --json number,title,headRefName,baseRefName,isDraft
GH_TOKEN="$(gh auth token --user Navigata1)" gh api repos/Navigata1/jovra/commits/main --jq .sha
```

Use an independently named `codex/` worktree from fresh `origin/main`. Do not reset, clean or fast-forward the original checkout blindly. At audit start it was behind remote with three untracked Android/watch planning files; the committed remote versions also exist. Preserve those local bytes and all `.claude/worktrees/`.

The report checkout is `/Users/IDC2.5/.codex/worktrees/jovra-sotu-2026-11-02`, branch `codex/sotu-signal-2026-11-02`. Its scope is assessment/docs. Do not turn this docs branch into a feature branch.

## Correct the old mental model

- PRs **365–371 are merged**, on October11–12. Do not recreate or remerge them.
- The last recorded main CI, run **38196643491**, actually executed and passed `jovra-core`, `spec`, `l10n`, `media-fixtures`, `native-data-export`. `ios-app (manual)` was skipped and is not a native simulator pass.
- The October9 zero-step billing error is historical evidence, not the current recorded blocker. Billing account settings themselves were not inspected.
- `ops/mission/PLAN.md:14–23` records a later founder step5 green light on October11 and Claude taking the core/expansion track. Preserve the original October9 hold as history. This assessment request authorizes report/GitHub/handoff work, not starting paid/live services or taking over another active branch. Respect the next session's current user scope.
- A reference implementation is real code but not a usable native film engine, Android app, watch app or live backend.

## What is proved

Current-main `ios` tree: `9a925bbca83a7545b40e8053ac0c2b4e8cc62243`, identical to historical tested source `73ce5c2f3627e3a599118d8b44ba66f2928bbd3f`.

Historical dedicated simulator proof: one actual CoreFlow and three viewport accessibility controls, all passed, no skipped/failed/expected failures. Capture → save → real Library row → original decoded frames → Reviewed decisions/correction → one silent clip + JSON/CSV export → relaunch with corrected score intact. Independent actual files verified canonical/schema/history/CSV correctness, unchanged original and a one-second30-frame silent clip. Runtime attribution stays at tested73; byte continuity is not a new main-SHA runtime run.

Fresh November2 checks on assessed main source: **69 Core tests** (12 XCTest +57 Swift Testing; Swift6.3.3), **99 Python tooling tests**, core contracts, Studio contracts, Room232 contract cases, l10n32+12 tool tests/literal lint/copy lint. Retained logs are in the report evidence folder. Historical serial Media90 remains historical; no new full native Media, simulator, physical-device or store test was run during this assessment.

The report QA is separate from product QA. Presentation validation proves nothing about a tennis model's accuracy.

## Recommended next implementation

**First: a bounded T16/T17 startup reconciliation slice.** Full T16 is issue18; full T17 is issue19.

Existing seams: locate `RecoveryScanner.swift`, `SessionStore.applyRecoveredCapture` and `LocalCaptureLibrary` with `rg` before editing. The scanner already handles finished/finalized stale journals and deliberately refuses unfinished journals. The app currently never invokes recovery at startup.

Build only the smallest public path that scans/adopts eligible finished captures, surfaces recovered/refused outcomes, preserves existing original bytes and reviewed edits, and is idempotent on repeated launch. Use the shared local actor/store. Add meaningful interruption/relaunch and custody controls. **Do not close full T16:** unfinished/torn-prefix recovery, bounded frame loss, media-services reset and physical interruption acceptance remain separate.

**Then: a bounded Files-only safe-import slice under T26 / issue28.** Preserve source bytes, validate playable media, store an acknowledged original, show a real Library session and leave no false success on cancellation/refusal. Full T26 also includes Photos, duplicates, batches, iCloud and accessibility; do not silently claim those from a Files-only slice.

Before either slice, compare required seams with their partially implemented blocker tickets. The dependency frontier is issue-level; a full blocker being open does not mean every underlying API is absent, nor does an API's existence close all its criteria. Split/reconcile dependencies explicitly.

## Other work to finish

- Recording: optional microphone, video-only fallback, interruptions, low disk, heat, endurance and physical capture.
- Ownership: real Storage/Trash/restore/deletion/data export controls and session eraser registration; do not leave accumulated recordings unmanageable.
- Everyday iOS: onboarding/profile, actual-session Home/overview, useful review/timeline tools, supported match modes, actual share/save destinations.
- Analysis: real estimators, scheduler/processing/calibration/lab UI and independent real-footage benchmarks. Oracle/null benchmark self-tests are not tennis detectors. Keep disabled/unsupported capabilities honest.
- Studio: integrate foundations, native contract parity, project/media custody, deterministic single-camera film+FilmVerifier before multi-camera expansion.
- Room/watch: native transport/QR approval, acknowledgements, reconnect/freshness, paired watch bridges/UI and real two-/six-phone gates. No live serve-speed or line-call promise from watch specs.
- Cloud: remaining DB/RLS, gateway, uploads, bounded spend/consent, planning/render/cancel/retry, delivery/retention/deletion, account/provider flows and separate G1–G9 activation evidence.
- Android/adaptive: actual native shell/domain/media behavior and state-preserving phone/fold/tablet layouts; separate emulator and device evidence.
- Release: iOS18 fallback runtime, real-match accuracy, accessibility/privacy/performance, signing, hardware and store submission gates.

Complete index of **278 open mapped tickets plus19pre-existing supplemental open issues**: `docs/reports/2026-11-02/REMAINING-TICKETS.md`. Counts are ticket workflow status, not completion percentages. T63/S107/A99/W26 =295 mapped full tickets;17 are closed. W includes22 watch/Room and4 iOS-adaptive tickets. The19supplemental issues are16verification/ADR follow-ups and3umbrella specs; the new coordination issue382 is not part of that snapshot.

## Preserve current PR ownership

At the assessment snapshot, four pre-existing PRs were open:

| PR | Head | State | Next gate |
|---|---|---|---|
| 374 | `c9e2fc9…` | Open, successful automatic checks | Independent review of pane vectors; not native layout completeness |
| 378 | `d8dcd542a59f5633cf2528342e6985f173bf9c77` | Draft, successful automatic checks | ADR gates #375/#376 before A01; foundation review; empty application, first activity later |
| 379 | `1ff9cafdd0f3e124d306408b5b5b1676d3477a1c` | Open, successful automatic checks | Studio package/project wiring; renderer/verifier are later |
| 380 | See fresh `evidence/ci-audit.json` or live query | Draft, backend-db RED | Explicit test-first migration state; finish migration/pgTAP negative cases, never merge red |

Requery exact current heads and owner activity. Do not merge, force-push, close or rewrite another session's PR during an assessment. Implementation merges must follow ADR-0006 and current required checks, plus independent review. Keep author/committer `IDC <hello@islanddevcrew.com>` and never change global GitHub auth.

## Validation and resource custody

```sh
python3 scripts/spec/validate.py
python3 -m unittest discover -s scripts/spec -p 'test_*.py'
python3 scripts/spec/validate_studio.py
python3 scripts/spec/validate_room.py
scripts/l10n/check.sh
swift test --package-path ios/Packages/JovraCore --jobs 2
# Media requires fixtures first; serialize actual AVFoundation tests:
# swift test --package-path ios/Packages/JovraMedia --no-parallel
```

For a fresh real native gate, use a newly owned simulator and owned derived directory after checking disk and installed runtimes. Never infer the old simulator UDID is available or idle today. The historical owned simulator was4265ADFD-39A3-4E71-8482-1945DDB5F899; preserve it and its evidence unless ownership is confirmed.

```sh
SIMULATOR_ID=<owned-udid> DERIVED_DATA=<owned-path> scripts/ios/core-flow-test.sh
# Negative viewport controls are a separate focused UI run:
SIMULATOR_ID=<owned-udid> DERIVED_DATA=<owned-path> scripts/ios/ui-test.sh \
  -only-testing JovraUITests/ScrollViewportAuditTests core-viewport
```

These last two commands are templates, **not commands executed during this assessment**. Do not paste angle-bracket values literally. Fail-closed `xcresult-summary.py` must report genuine tests, no empty/skipped-only/incomplete pass. Preserve raw failures. Validate the new run's actual exported JSON, CSVs, original hash and decoded video separately.

Free disk at audit start was about3GiB; the small owned Core scratch build used about261MiB. No Xcode, full fixture render, Docker stack or other project's simulator/cache was touched. The audit scratch build is outside the published packet; other sessions' caches and originals must never be deleted for convenience.

## Stop and report when

There is inadequate owned disk, another session owns the target files/PR/simulator, media custody cannot be proved, a check fails, a real-footage/device requirement cannot run, or a paid/hosted/signing action lacks its separate authorization. Label the exact gap and preserve evidence. Do not fill the UI with invented metrics or turn schema/reference tests into device claims.

At session end: update mission state/journal and regenerate the ordinary heartbeat. If producing a full enhanced report, use flagship-report; the heartbeat does not satisfy it. Preserve old reports; supersede them with new dates and a source-bound handoff.

## Supplemental follow-ups

The index includes all pre-existing unmapped open issues. In particular, #375 and #376 are A01 merge-gate ADR work; #377 is the later Android Drive/A49 amendment. #381 records known S07 follow-ups (rounding/contact-protection/omission/refusal vectors, future multi-angle/NTSC cases, input hardening and fixture/acceptance wording). Review their actual scopes before claiming broader compiler coverage; do not turn the out-of-scope future NTSC case into a current release regression.
