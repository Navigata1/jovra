# T07 independent review

Published PR #321 head: `f42a88b86793f44db465f26da32ad4594530cafe` (the independent review input; still open before authorized publication).

Isolated review worktree: `/Users/IDC2.5/.codex/worktrees/jovra-core-continuation/reviews/t07`, branch `codex/review-t07`. No changes to `/Users/IDC2.5/jv`, Claude worktrees, or shared simulators. Initial independent review was read-only toward GitHub. The parent subsequently authorized publishing the review corrections to the existing PR321; merging remains the parent’s action. No GitHub comment was posted.

## Tested revisions

- Initial integration: published PR + main `6de361a5ef8d6afb33257634c50f3d65c8ea0882` = `03c2106f450d00f285af25192dff6941e1cb8c30`.
- Native restart control: app source at integration `41e8cc7c70f4d0a0128d20ac9ce15ecd6b5c2151`, with main `15bc44a60c61d81b1abf8e4abae30093c71e2061`.
- Final unit integration: `132f1950994452016014b8532d7ba1fe10b18bfa`, including main `1b4b481e473630f2920186529d1cc3c008979391` (T03).
- Interrupted UI revision: `cdb2845097905428fbc0f18e225663c386096a21`. The long focused run lost its receipt to disk exhaustion; not a pass.
- Final focused revision: `c5826377cc447d6a0b51177ddbf1dd7d2422e1c8`, including the fail-closed summary correction. App/package source still matches the final unit integration.
- Publication preparation integrates current main `7fd68a5` at `f291fd8a358fa10379064670c2c7f71944159cf8`. This adds independently reviewed T04 order contracts and T06 catalog prefix support. T07 app source is unchanged; 164 units and 7 focused UI results above remain bound to their listed tested revisions, not silently rebound to later package changes. Fresh publication CI covers the current package/contracts. All 12 iOS tool tests and the l10n gate passed after this integration.

Simulator: **JOVRA-Codex-T07**, `4265ADFD-39A3-4E71-8482-1945DDB5F899`, iPhone 17 Pro, iOS 26.5. Newly created for this reviewer, with own `.derivedData`.

## Standards axis

Read CLAUDE.md, docs/DEVELOPING.md, docs/agents/issue-tracker.md, .claude/skills/code-review/SKILL.md, and exact published source diff. No confirmed T07 app standards defect. A genuine shared test-harness defect was corrected separately: an empty unknown receipt could exit 0. Permissions request at the moment of need after the in-app explanation; no prompt at launch. Preferences reset only JOVRA-owned keys. Erasure registry runs later stores without a central list. Catalog copy uses owning String Catalogs. Placeholders disclose future ticket ownership. `git diff --check origin/main...HEAD` passed.

## Spec axis

Read issue #9 and the T07 route/permission/preferences/erasure acceptance criteria. Typed route and sheet payloads round-trip through JSON; full-screen close returns to the presenting tab; every current destination resolves. The newest-match deep link excludes samples and practice; the live library remains the declared T20 seam. Services declare own environment keys and live/fake defaults. Permission explanations, consequence states and Settings link are covered.

The apparent scene-restoration defect was **refuted** by a launch entirely outside XCTest. Normal native launch -> Doubles Capture -> background to Safari -> SIGKILL only the owned app PID -> native simctl relaunch restores Capture plus Doubles payload. Read native-process-death.md, native-only-process-death.log and the before/after PNGs. XCTest-started launches behaved differently even with external kill/native relaunch; the private mechanism is not established. Temporary manifest, String-control, logging and NSUserActivity experiments were reverted. No app fix was necessary or retained.

## Commands and results

All native commands used `SIMULATOR_ID=4265ADFD-39A3-4E71-8482-1945DDB5F899 DERIVED_DATA=$PWD/.derivedData` in the isolated checkout.

| Check | Revision | Result |
|---|---|---|
| `scripts/ios/test.sh` baseline | 03c2106 | Core 15, Media 63, hosted 70 passed |
| `scripts/ios/ui-test.sh codex-t07-independent` full suite | 03c2106 | **31 passed, 1 failed, 1 expected failure** |
| Full-suite system-light / system-dark passes | 03c2106 | 1 passed each |
| Focused AX5 `JovraSmokeUITests/testEveryTabAtLargestAccessibilityTextSize` | 0cf2c77 | **1 passed**, all five tabs audited |
| Added restart test / SIGKILL harness probes | review diagnostics | failed restoration under XCTest; retained, not called green |
| Fully native process-death control | unchanged app at 41e8cc7 | **PASS**, Capture + Doubles payload restored |
| `scripts/ios/test.sh` final | 132f195 | **Core 31, Media 63, hosted 70 passed** |
| Long final 14-test UI attempt | cdb2845 | **INCOMPLETE**, disk failure writing result; no accepted count |
| Final short route/deep-link/prompt/continuity pass | c582637 | **6 passed, 0 failed** (DeepLink 2, NavigationRoutes 2, PermissionsCenter 1, SceneContinuity 1) |
| Final denied permission light/dark/AX5 pass | c582637 | **1 passed, 0 failed**, all three appearances audited |
| Summary gate correction | c582637 | red 5 failures / green 7 tests; all iOS tool tests 12 passed; broken real receipt exit 1, valid real 70-unit receipt exit 0 |
| `BRANCH=ticket/t07-navigation-routes-permissions BASE=origin/main scripts/l10n/check.sh` | final integration | literals 0, copy 0, 3 changed catalogs / 0 ownership problems; tool tests passed |

Final hosted unit classes: AppRouter 21, PermissionsCenter 7, Preferences/DataEraser 10, ServiceRegistration 3, contrast 7, Drive config 7, formatting 8, launch config 7 = 70.

The original full-suite failure was NSError domain `com.apple.xcode.xctest.accessibilityAudit`, code `-56`, “Audit failed to complete in time” in AX5 tab audit (first Home audit succeeded; next scroll audit timed out). No audit finding was reported. The exact test passed in the focused rerun. The original failure remains preserved: this is not a claim that the first full suite was uniformly green. No retry helper or suppression was added.

One intermediate final command misspelled two class filters, so it ran only the continuity test (1 passed); it is preserved as such. The corrected final command explicitly names NavigationRoutesUITests, PermissionsCenterUITests, DeepLinkUITests and SceneContinuityUITests. No missing-class invocation is counted as route/permission coverage.

PR321 automatic checks: jovra-core, l10n, media-fixtures passed; manual iOS job skipped. Local native results supply simulator evidence, not a claim of hosted native CI.

## Incomplete receipt and corrective commit

At the end of the 17-minute final attempt, Xcode reported `FileBackedCASDatabase: rename failed: No space left on device`. The receipt reports `result: unknown`, zero test cases. The old summary helper exited 0 because it only rejected the literal Failed status. This was a genuine false-positive gate; the run is not counted as passing.

Corrective commit `c582637` requires an explicit Passed completion, at least one executed passed/expected-failure case, recognized case statuses, and zero row/summary failures. Meaningful negative controls reproduce empty unknown, nonempty unknown, empty Passed, all skipped, inconsistent reported failures, and unknown case status. The existing expected-failure negative control remains accepted. No audit issue suppression or retry was introduced. Read summary-gate-red.log, summary-gate-green.log, summary-gate-all-tools.log, broken-receipt-gate.log and valid-receipt-gate.log.

All 19 receipts through that failure were archived with SHA-256 and verified tar listing before own .derivedData was removed. Only the dedicated simulator was shut down. Free space recovered to 13 GiB, demonstrating substantial transient usage. Final dynamic checks use short separate receipts to reduce that pressure; the first full-suite coverage remains separately reported. Both final receipts are Passed: 7 tests total, zero failures/skips/expected failures. They are separately preserved in xcresults-final.tar.gz with SHA-256 ee7abbbfcaea2852fbc0f11c5c9302d3708844bcd9da332b4d15e38c43151342, verified tar integrity, and xcresults-final-manifest.json. After preservation, only this isolated checkout’s .derivedData was removed and the dedicated simulator was shut down and retained. Final free space is 12 GiB.

## Visual review

Inspected inherited AX5 point editor, dark replay and light microphone explanation; fresh Home light, AX5 Home, Shot map push, dark Match overview, Welcome, denied camera AX5, system-dark Home; native restart before/background/after; final live String journal push, final Photos add-only Allowed sheet, final Capture/Doubles continuity after foreground, and fresh final denied-camera AX5 sheet. Styles are cohesive and Close/back/tab behavior is visible. The inherited AX5 Home Sample pill hyphenates “Sam-ple”, a T19 readability polish item outside T07. Future screens remain openly labelled placeholders; they are not finished feature evidence.

## Migration and remaining limits

Read placeholder-migration.md: the first real feature needs an owning-file static metadata flag and stable screen identity. Scaffold ticket/payload assertions must become real-feature assertions, not fake placeholder markup. No growing central exemption list was added in T07 baseline review. T20 owns the live SessionLookupKey adapter; T03 domain contracts should be adapted at the boundary instead of duplicating domain models.

The added SceneContinuityUITests honestly verifies background/foreground plus presenting-tab continuity. Host-dependent diagnostic code is retained as text outside the build target. It must not become a default “process-death” test without a native-start driver and preservation control.

Simulator only: no physical-device camera, iOS 18 runtime, live session store, Store submission, Android, Studio, tablet/foldable or watch claim. Step 5 remains held. **Verdict: ACCEPT the T07 app scope on this simulator.** No demonstrated T07 app defect remains. The original full-suite AX timeout and the incomplete disk-exhausted receipt remain visible limitations; focused reruns are green, and no audit finding is waived. The genuine receipt gate fix is isolated in c582637 and included in the parent-authorized publication. This verdict does not claim all application features are implemented or production/device readiness. No merge or GitHub comment was performed; publishing the review corrections is authorized by the parent.
