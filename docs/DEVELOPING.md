# Developing JOVRA (iOS)

## Toolchain

| Tool | Version used for ticket #1 | Notes |
|---|---|---|
| Xcode | 26.6 (iOS 26.5 simulator SDK) | Deployment target is iOS 18.0 (ADR-0007). |
| Swift | 6.2+ (packages declare `swift-tools-version: 6.0`) | App target builds in Swift 6 language mode with complete concurrency checking. |
| XcodeGen | 2.46 | `brew install xcodegen` |
| Simulator | iPhone 17 Pro, iOS 26.5 (`83223876-0F7B-4B30-A051-AD9F08BD3C5E` on the build Mac) | Override with `SIMULATOR_ID=<udid>`. |

## Deployment target (ADR-0007)

The app targets **iOS 18.0**. iOS 26-only APIs sit behind `#available` checks with a stated iOS 18 fallback. The build
Mac has only the iOS 26.5 Simulator runtime, so **iOS 18 runtime behaviour is UNVERIFIED locally**: every simulator
run and CI job proves the iOS 26 code path only. Report each `#available` fallback as `unverified` until it has run on
an iOS 18 simulator or device.

## Layout (ADR-0005)

```
ios/
  project.yml                 XcodeGen spec (Jovra.xcodeproj is generated, never committed)
  Jovra/
    App/                      entry point, AppRoot (pre-shell / shell), AppShell (tabs), AppRouter, typed routes,
                              deep links, route catalog, placeholders, the ServiceKey seam, tab bar
    DesignSystem/
      Tokens/                 ColorRole (semantic light/dark/Increase Contrast colours), spacing, type
      Components/             buttons, cards, stat tile, filter pills, provenance badge, status pill, rows
      Brand/                  BrandGeometry (Court Arc mark + JOVRA wordmark vectors), SwiftUI shapes, lockup
    Features/<Tab>/           one folder per feature (Home, Sessions, Record, Insights, Profile, Capture)
    Platform/LaunchConfiguration/  launch arguments (shared with the UI tests), Drive client configuration
    Platform/Permissions/     PermissionsCenter (live, fake, injected), guidance copy, the explanation sheet
    Platform/Preferences/     AppPreferences: every v1 preference key
    Platform/DataEraser/      the registry behind "Delete all JOVRA data"
    Resources/                Info.plist and Jovra.entitlements (both generated from project.yml),
                              Assets.xcassets, Localization/ (String Catalogs, JovraFormat)
  Config/                     Jovra.xcconfig (+ optional, git-ignored Drive.xcconfig)
  JovraTests/                 hosted unit tests (contrast, router, launch configuration, Drive config, formatting)
  JovraUITests/               XCUITest suites; Support/ holds the shared helpers, Harness/ the harness's own tests
  Packages/
    JovraCore/                Foundation-only domain layer; builds and tests on Linux (CI required check)
    JovraMedia/               AVFoundation/CoreMedia adapters over JovraCore; tested on macOS
```

ADR-0005 names the domain package "JovraKit" with two libraries. It is implemented as two sibling
packages (`JovraCore`, `JovraMedia`) so the Linux CI job can build JovraCore without ever resolving
a package that imports Apple frameworks.

Sources are globbed by folder: adding a file never needs a `project.yml` edit. Re-run
`scripts/ios/generate.sh` after adding or removing files.

## Commands

All scripts live in `scripts/ios/` and keep derived data in `.derivedData/` at the repo root.

| Command | What it does |
|---|---|
| `scripts/ios/generate.sh` | Generates `ios/Jovra.xcodeproj` from `ios/project.yml`. |
| `scripts/ios/test.sh` | `swift test` for JovraCore and JovraMedia, then `xcodebuild test` for `JovraTests` on the simulator (renders the media fixtures with `render.py --check` first); prints per-class counts and the `.xcresult` path. |
| `scripts/ios/ui-test.sh [-only-testing JovraUITests/<Class>[/<test>]]... [ticket]` | With `-only-testing` (repeatable), runs only those classes or tests, so a ticket shows exactly its own. Without it, runs all of `JovraUITests`, then a system-appearance pass with the simulator in light and in dark (restored afterwards). Prints per-class counts and the `.xcresult` path, and exports every named screenshot to `evidence/ios/<ticket>/` (default: branch name minus `ticket/` and the `t` before the number, so `ticket/t06-x` gives `06-x`). |
| `scripts/ios/check-build-config.sh` | Builds the app unsigned (no team) without and with a test Drive xcconfig; checks the entitlements in the binary, every v1 Info.plist key, that every URL type registers one valid (non-empty) scheme, the unconfigured (placeholder) and the configured Drive client, and that the unsigned build installs and runs. |
| `scripts/ios/side_by_side.py evidence/ios/<ticket>` | Pairs `sNN-*` screenshots with reference PNG NN and writes `side-by-side.html`; exits non-zero until every pair has a reviewer line in `reviews.txt`. |
| `scripts/ios/xcresult-summary.py <bundle.xcresult>` | Per-class passed/failed/skipped/expected-failure (XCTExpectFailure) counts, so every test case is counted; the device and the bundle path. |
| `scripts/l10n/check.sh` | The localization tools' tests, the literal-string lint, the copy lint and (with `BRANCH` and `BASE`) the String Catalog ownership check. CI job `l10n`. |
| `python3 scripts/media/render.py [--check]` | Renders the media fixtures (frame counters, fixture camera, import set, harness clips) into `.cache/media/` and writes their ground truth; `--check` fails unless the committed ground truth and decoded-frame hashes are reproduced. Needs ffmpeg. See `scripts/media/README.md`. `test.sh` runs `--check` first (it never rewrites committed truth). |
| `swift run --package-path ios/Packages/JovraMedia jovra-benchmark run ...` | Runs a registered estimator through the benchmark harness and writes a benchmark record (`scripts/media/README.md`). |
| `scripts/ios/render-app-icon.sh [proof.png]` | Re-renders `AppIcon-1024.png` from `BrandGeometry.swift` (and optionally a brand proof sheet). Run after changing the mark. |

Single package directly: `swift test --package-path ios/Packages/JovraCore`.

Every script takes `SIMULATOR_ID=<udid>` (use your own simulator; see "Simulator hygiene") and
`DERIVED_DATA=<path inside your worktree>`.

## The project file is frozen

T06 landed every v1 Info.plist key and capability in `ios/project.yml`, so feature tickets never edit
the project. **After T06, only the Live Activity follow-up ticket (if the T60 spike says ship) may touch
`ios/project.yml`.** If a feature needs something the project lacks, raise it with the lead instead.

| What | Value | For |
|---|---|---|
| `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryAddUsageDescription` | usage strings | capture, optional audio, saving exports (add-only) |
| `NSHealthUpdateUsageDescription` | usage string | opt-in tennis workouts (start, end, session reference only) |
| `BGTaskSchedulerPermittedIdentifiers` | `com.islanddevcrew.jovra.processing.overnight`, `com.islanddevcrew.jovra.continued.*` | the overnight processing task (iOS 18+) and user-started continued-processing tasks (iOS 26+; submit as `com.islanddevcrew.jovra.continued.<job>`) |
| `UIBackgroundModes` | `processing` | the overnight processing task |
| `CFBundleURLTypes` | `jovra` (deep links) and `$(JOVRA_DRIVE_REVERSED_CLIENT_ID)` (Drive OAuth redirect; the inert placeholder `com.islanddevcrew.jovra.drive-unconfigured` until Drive.xcconfig exists) | App Intents / Shortcuts deep links; ADR-0008 |
| `JovraDriveClientID`, `JovraDriveRedirectScheme`, `JovraDriveXcconfigLoaded` | from the xcconfig chain | `DriveClientConfiguration` |
| `JovraAppleSignInEnabled` | `$(JOVRA_APPLE_SIGN_IN_ENABLED)`, `YES` by default | the "Continue with Apple" switch (screen spec open question 1) |
| Entitlements | `com.apple.developer.applesignin = [Default]`, `com.apple.developer.healthkit = true`, `healthkit.access = []` | Sign in with Apple, HealthKit |

Not added, deliberately: `NSHealthShareUsageDescription` (JOVRA never reads Health data), the
`workout-processing` background mode, and the continued-processing GPU entitlement
(`com.apple.developer.background-tasks.continued-processing.gpu`, device-specific and not needed for the
CPU path). Each is a lead decision if a ticket needs it.

**Unsigned simulator builds carry both entitlements.** The app builds with no development team and an
ad-hoc signature; Xcode writes the entitlements into the executable's `__TEXT,__entitlements` section,
which the simulator grants. `scripts/ios/check-build-config.sh` reads them back and launches the app.
Device builds need a team with both capabilities enabled (not exercised yet: UNVERIFIED on device).
An unsigned device-SDK compile does work (`xcodebuild build -destination generic/platform=iOS
CODE_SIGNING_ALLOWED=NO`, an arm64 `iphoneos` binary with `MinimumOSVersion` 18.0, see
`evidence/ios/06-ui-harness-l10n-plist/device-sdk-build.log`), but it proves only that the code compiles
for hardware. It cannot be installed: the build Mac has no signing identity.

### Google Drive client configuration (ADR-0008)

`ios/Config/Jovra.xcconfig` sets `JOVRA_DRIVE_CLIENT_ID` to empty and `JOVRA_DRIVE_REVERSED_CLIENT_ID` to
the inert placeholder `com.islanddevcrew.jovra.drive-unconfigured` (`DriveClientConfiguration.unconfiguredScheme`;
the Drive URL type always exists and an empty `CFBundleURLSchemes` entry is invalid), and then
`#include?`s `ios/Config/Drive.xcconfig`, which is git-ignored. Without it the built Info.plist has an
empty client id and the placeholder scheme, `DriveClientConfiguration.bundled` is `.notConfigured`, and
the UI says "Awaiting Google Drive setup". To configure a build, copy `Drive.xcconfig.example` to `Drive.xcconfig`
and fill in the iOS OAuth client; never commit it (CLAUDE.md rule 5). A client id whose redirect scheme
is not its reversed form reads as `.misconfigured`, never as configured.

## Launch configuration

`ios/Jovra/Platform/LaunchConfiguration/LaunchConfiguration.swift` is compiled into the app and into
`JovraUITests`: the tests build arguments from a `LaunchConfiguration` value and the app parses the same
type, so the two cannot drift. A value the app cannot parse is logged as a problem, never silently
ignored (`LaunchConfiguration.reportedProblems`, including a `-startRoute` that names no
destination; the app then opens on Home). With no arguments, everything is live.

| Argument | Values | Meaning |
|---|---|---|
| `-appearance` | `system`, `light`, `dark` | also the `appearance` UserDefaults key behind Profile → Appearance |
| `-demo` | `off`, `sample` | sample library installed (always badged "Sample") |
| `-fixtureCamera` | a fixture clip id | the simulator fixture camera's source (ADR-0012) |
| `-permissions` | `camera=denied,microphone=notDetermined,...` | injected states for `camera`, `microphone`, `photosAdd`, `notifications`, `health`: `notDetermined`, `denied`, `restricted`, `authorized` |
| `-archiveState` | `awaitingSetup`, `notConnected`, `connecting`, `connected`, `needsReconnect` | injected archive account state |
| `-reduceMotion` | `YES`, `NO` | forces Reduce Motion on (read it from `\.launchConfiguration` together with the system setting) |
| `-pseudoLocale` | `accented`, `doubleLength`, `rightToLeft` | also adds the matching Foundation pseudolanguage arguments |
| `-startRoute` | any destination's launch name (`AppDestination.catalog`): a tab (`home` … `profile`), `welcome`, `onboarding`, a push (`sessions.matchOverview`, `profile.settings`, …), a full-screen route (`capture`, `replay`, …) or a sheet (`sheet.pointEditor`, `sheet.permission.camera`, …) | where the app opens (example payloads) |

In UI tests: `XCUIApplication.launchJovra(contentSize: .accessibility5) { $0.appearance = .dark; $0.permissions = [.camera: .denied] }`.
Services read `@Environment(\.launchConfiguration)`; the fake/live switch is the `ServiceKey` seam below.

## Navigation and services (T07)

- **Routes.** `App/Routes/Routes.swift` types every destination of screen spec §0.1: `PreShellRoute`, per-tab pushes
  (`SessionsRoute`, `InsightsRoute`, `ProfileRoute`), `FullScreenRoute` and `SheetRoute`, all `Codable` for state
  restoration (`RouterState`, kept in scene storage; a launch with harness arguments never restores). Feature code
  calls `AppRouter.show(_:)`, `present(_:)`, `present(sheet:)` or pushes a route value.
- **Placeholders.** `App/Destinations.swift` maps each route to a type in its owning feature folder; `RouteCatalog`
  names the ticket and file. A feature ticket replaces that one file, keeping the type name and initializer, and never
  edits the router. Placeholder copy lives in the `App` table.
- **Deep links.** `jovra://record/singles` (Start singles recording), `jovra://sessions/last-match` (Show last match:
  the newest real match, else the library) and `jovra://share-pack/<session>` (`App/Routes/DeepLink.swift`).
- **Services.** Each service declares a `ServiceKey` in its own file (`App/Services/ServiceKey.swift`): a `live()` and a
  `fake(for:)`, chosen from `LaunchConfiguration.current` (the demo flag by default). No ticket edits `JovraApp.swift`.
- **Permissions.** Read `@Environment(\.permissionsCenter)`; present `.permission(<p>)` (the in-app explanation, then
  Apple's prompt) at the moment of need, never at launch or in onboarding. `PermissionGuidance` holds the status and
  consequence copy for every state; `-permissions camera=denied` injects states.
- **Preferences and erasers.** `AppPreferences` declares every v1 preference key; each store registers a `DataEraser`
  in `DataEraserRegistry.shared` when its live instance is created.

## Localization

English ships; Spanish is the first translation and ships after native review (story 382).

- **One String Catalog table per owned area**, in `ios/Jovra/Resources/Localization/<Table>.xcstrings`.
  The table is named after the area's folder with dots: `Capture.Framing` for
  `ios/Jovra/Features/Capture/Framing`, `Replay.RallyOnly`, `DesignSystem.Components` for
  `ios/Jovra/DesignSystem/Components`, `App` for `ios/Jovra/App`. `InfoPlist` holds the usage strings.
- **Reference the table explicitly**: `Text("Frame your court", tableName: "Capture")`,
  `String(localized: "Done", table: "Capture")` for `String` parameters,
  `.accessibilityLabel(Text("Close", tableName: "Capture"))`. Text that is never translated (the brand
  name, `hello@islanddevcrew.com`) uses `Text(verbatim:)`. Never build a sentence from fragments: use
  one key with interpolation (`"\(label): \(value), sample data"`).
- **Format numbers, dates, durations, timecodes and speeds with `JovraFormat`** (FormatStyle, locale
  aware). Percentages come from `pct(n, d)` and are only formatted there.
- **Do not commit auto-extracted changes to other tables.** Building in Xcode can add or mark keys in
  any catalog; commit only your own table's changes. The `l10n` CI job fails a PR that changes, deletes
  or renames a table outside the ticket's owned areas (a rename counts as deleting the old table) (`scripts/l10n/catalog_ownership.py`: the most specific owned area
  in `docs/spec/tickets.json` owns a table; the branch `ticket/tNN-slug` names the ticket; the
  localization owner, T06, may edit any table).
- **Literal-string lint** (`scripts/l10n/literal_lint.py`): flags string literals passed to SwiftUI text
  views and controls (`NavigationLink` included), `.accessibilityLabel`/`Hint`/`Value`, `.navigationTitle`,
  `.help`, `.alert`, `.confirmationDialog` and `.badge`, display arguments (`title:`, `message:`, …),
  display properties, `LocalizedStringKey("…")`, and `String(localized:)` without a table. Only a
  `tableName:`/`table:` that is a top-level argument of the call counts, never one inside a nested call,
  closure or interpolation: `Text("Shots \(String(localized: "rally", table: "Home"))")` is flagged. `#Preview` blocks are skipped. A line may end in
  `// l10n-lint: ignore (reason)`; a preview-only file may start with
  `// l10n-lint: ignore-file (reason)`.
- **Copy lint** (`scripts/l10n/copy_lint.py`) over every catalog key and value and every string literal in
  the app's Swift sources (`ios/Jovra`, so `Text(verbatim:)` and accessibility labels too; comments and
  the test targets are not copy): no spin rate or RPM, line calls, injury, calories, "Fastest serve" (say
  "Fastest marked serve"), "Advantage" as a format label, "Reference concept", `mailto:` or the sample
  "3.2 GB". A string that states what JOVRA does *not* do may carry `copy-lint: allow <rule> — <reason>`
  in its catalog comment, or as a trailing `// copy-lint: allow <rule> — <reason>` on its Swift line.
- **Pseudo-locale**: `-pseudoLocale accented` wraps every catalog string in `[# … #]` with accents;
  anything that bypassed the catalogs shows up unchanged. `PseudoLocaleUITests` runs all five tabs this
  way and asserts the textClipped audit (tab bar titles included) and that every visible text with
  words in it is bracketed (FormatStyle output such as "6h 42m" is localized by Foundation and exempt).
  It also checks the tab titles with `-pseudoLocale doubleLength` and at AX5: the textClipped audit on
  the tab bar, and (double length) each title read back from the screen with on-device text
  recognition, which fails on "…" or a missing word. A long tab title wraps onto up to three lines and
  only then shrinks (to 75 % at most); it is never truncated.

## UI-test support (`ios/JovraUITests/Support`)

| Helper | Use |
|---|---|
| `XCUIApplication.launchJovra(contentSize:_:)` | launch with a `LaunchConfiguration` and an optional Dynamic Type size |
| `auditScreen(app, for:)` | `performAccessibilityAudit` over the whole scrolling screen with the documented exceptions below |
| `assertHitTargets(in:exempt:)` | every hittable control at least 44 × 44 pt |
| `attachScreenshot(app, name:)` | a named screenshot, exported by `ui-test.sh`; name reference pairs `sNN-<appearance>-<what>`; a bad name is a recorded test failure, not a crash |
| `assertBriefCopy(screen:in:corrections:excluding:)`, `BriefCopy.expected(screen:)` | copy from `design-reference/brief/screens.json` with the spec's honesty corrections (Photos "Not needed for import" / "Add-only", "Best of 3 · Ad · Tie-break at 6–6", "+4 percentage points", "Fastest marked serve", provider "Demo", no "Reference concept", no "3.2 GB", no "Estimated from calibrated video"); add a screen's own deliberate differences through `corrections` |

### Side-by-side evidence

The references are AI-generated rasters, so pixel diffs mean nothing. Name screenshots that match a
reference `sNN-…`, run `scripts/ios/side_by_side.py evidence/ios/<ticket>`, compare each pair, and add
one line per screenshot to `evidence/ios/<ticket>/reviews.txt`:
`s03-light-home: <reviewer> — <verdict and notes>`. The page is written only when every pair has one.
Screen numbers pick the folder: 01–20 `design-reference/screens`, 21–40 `design-reference/studio/screens`,
41 and up `design-reference/adaptive/screens` (Android, watchOS, Wear OS and the iOS fold screens 71–72).

## What the UI smoke test checks

`JovraSmokeUITests` launches the app with `-appearance light|dark|system` (the Profile → Appearance
preference, read from `UserDefaults`), visits every tab, asserts the heading, the selected state and
44 pt targets, attaches a screenshot, and runs `performAccessibilityAudit()` on each tab and on the
full-screen capture route. `testEveryTabAtLargestAccessibilityTextSize` repeats the tour at the
largest accessibility text size (AX5, launched with `-UIPreferredContentSizeCategoryName
UICTContentSizeCategoryAccessibilityXXXL`). It asserts that the tab bar stays one compact row, that each
English tab title is one line high (an item shorter than icon, gaps, dot and 1.5 caption lines at the
xxxLarge cap; a second line would add a whole line), and that the Sessions filter pills stack instead of
breaking words. Long translations may wrap a tab title onto up to three lines; `PseudoLocaleUITests`
covers those. It attaches `ax5-*` screenshots and audits every tab.

Each audit runs on the screen as first shown, then again one, two, and more slow swipes further
down, until the end of the screen. Content first seen cut off at the bottom is therefore audited
fully visible at a later step.

The audit scrolls the page by itself (in the T06 run by 22 pt to 2,017 pt; at AX5 it often returns to
the top). A contrast or element-detection issue found while it moved the page was sampled from pixels
that no longer sit under the reported frames: on `JOVRA-T06`, Home's "This week", the stat tiles and
Profile's "Preferences" all failed contrast this way (`evidence/ios/06-ui-harness-l10n-plist/ui-test-full-suite.log`).
So when the page moved during an audit, those issues are set aside, logged, and the audit is repeated
once at the settled position, where every issue counts. Limitation: a set-aside element is judged again
only where that repeat finds it; it may be clipped there (and so exempt), in which case its verdict comes
from another step's audit.

There are two documented audit exceptions, and the test logs every issue it ignores:

- **Dynamic Type on tab bar titles.** Like the system tab bar, `JovraTabBar` caps its titles at
  `xxxLarge` and offers the Large Content Viewer (touch and hold). The audit reports the cap as a Dynamic
  Type issue. Only the dynamicType audit, and only inside the tab bar's frame, is exempt: text clipping
  on a tab title always fails.
- **Contrast and element detection on clipped content.** This covers a non-tab-bar element under the
  status-bar backdrop, or one reaching into the tab bar or within 16 pt of it. The audit's sampling
  there takes in the backdrop, the bar and the chartreuse Record circle, not the element, and its text
  recognition reports text it cannot match to an element ("Potentially inaccessible text", as on Home's
  "Your game, in focus." under the status bar). Every other audit type fails wherever the element is. SwiftUI keeps off-screen scroll content in the
  tree. Tab bar items are always checked. Each slow swipe moves the page by more than 16 pt and by
  less than the visible height, and every screen ends with 32 pt of padding. So every element is
  audited clear of the bar at some step.

Text contrast for every colour role is also enforced independently by `ColorRoleContrastTests`
(≥ 4.5:1 in light, dark and Increase Contrast).

## Simulator hygiene

UI tests need the simulator to themselves. Evidence screenshots show the simulator's real status bar.
If another app on a shared simulator opened ours, a stray "◀ <other app>" back-link can appear in it.
Check the exported screenshots before posting them. If another session (for example a Maestro driver) is using
the default simulator, create a dedicated one and point the scripts at it:

```sh
UDID=$(xcrun simctl create "Jovra iPhone 17 Pro" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5)
SIMULATOR_ID=$UDID scripts/ios/ui-test.sh
xcrun simctl delete "$UDID"   # when done
```

Resolved in T06: on a freshly created iPhone 17 Pro / iOS 26.5 simulator (`JOVRA-T06`),
`performAccessibilityAudit` reported contrast failures on high-contrast text such as Home's "This week"
after a scroll step, on `main` as well. The audit had scrolled the page itself while sampling; the
repeat-after-move rule above removes those false failures (evidence: `main-baseline-smoke.log`, the
full class on `main`, against `ui-test-full-suite.log`).

## Disk hygiene

The build Mac is short on disk. Always build with `-derivedDataPath .derivedData` (the scripts do),
never into `~/Library/Developer/Xcode/DerivedData`, keep a single derived-data directory, and delete
it when you finish a ticket: `rm -rf .derivedData`.

## CI (`.github/workflows/ci.yml`)

- `jovra-core` (required): `swift test` in `ios/Packages/JovraCore` inside the `swift:6.1` container on Ubuntu.
- `l10n`: `scripts/l10n/check.sh` on Ubuntu: the localization and side-by-side tools' own tests
  (negative tests included), the literal-string lint, the copy lint, and on pull requests the String
  Catalog ownership check against the base branch.
- `media-fixtures`: on Ubuntu, `render.py --check` (renders with apt's ffmpeg and requires the committed
  decoded-frame hashes) and `scripts/spec/validate.py`.
- `ios-app (manual)`: `workflow_dispatch` only. On macOS it runs both package test suites, generates
  the project, builds the app and runs `JovraTests`. Simulator UI suites run on the build Mac, and
  their evidence goes on the PR (ADR-0006).

## Evidence

A ticket is done when a check that could fail has passed (CLAUDE.md rule 9). Attach command output,
test counts, the simulator id and the screenshots from `evidence/ios/<ticket>/` to the PR. Report
simulator results, device results and store readiness separately.
