# Developing JOVRA (iOS)

## Toolchain

| Tool | Version used for ticket #1 | Notes |
|---|---|---|
| Xcode | 26.6 (iOS 26.5 simulator SDK) | Deployment target is iOS 17. |
| Swift | 6.2+ (packages declare `swift-tools-version: 6.0`) | App target builds in Swift 6 language mode with complete concurrency checking. |
| XcodeGen | 2.46 | `brew install xcodegen` |
| Simulator | iPhone 17 Pro, iOS 26.5 (`83223876-0F7B-4B30-A051-AD9F08BD3C5E` on the build Mac) | Override with `SIMULATOR_ID=<udid>`. |

## Layout (ADR-0005)

```
ios/
  project.yml                 XcodeGen spec (Jovra.xcodeproj is generated, never committed)
  Jovra/
    App/                      entry point, AppShell (tabs), AppRouter (tab + full-screen routes), tab bar
    DesignSystem/
      Tokens/                 ColorRole (semantic light/dark/Increase Contrast colours), spacing, type
      Components/             buttons, cards, stat tile, filter pills, provenance badge, status pill, rows
      Brand/                  BrandGeometry (Court Arc mark + JOVRA wordmark vectors), SwiftUI shapes, lockup
    Features/<Tab>/           one folder per feature (Home, Sessions, Record, Insights, Profile, Capture)
    Resources/                Info.plist (generated from project.yml), Assets.xcassets (AppIcon, colours)
  JovraTests/                 hosted unit tests (colour-role contrast, router)
  JovraUITests/               XCUITest smoke suite with accessibility audits and screenshots
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
| `scripts/ios/test.sh` | `swift test` for JovraCore and JovraMedia, then `xcodebuild test` for `JovraTests` on the simulator. |
| `scripts/ios/ui-test.sh [ticket]` | Runs `JovraUITests`, then a system-appearance pass with the simulator in light and in dark; exports the named screenshots to `evidence/ios/<ticket>/` (default: branch name minus `ticket/`). Restores the simulator's appearance. |
| `python3 scripts/media/render.py [--check]` | Renders the media fixtures (frame counters, fixture camera, import set, harness clips) into `.cache/media/` and writes their ground truth; `--check` fails unless the committed ground truth and decoded-frame hashes are reproduced. Needs ffmpeg. See `scripts/media/README.md`. `test.sh` runs `--check` first (it never rewrites committed truth). |
| `swift run --package-path ios/Packages/JovraMedia jovra-benchmark run ...` | Runs a registered estimator through the benchmark harness and writes a benchmark record (`scripts/media/README.md`). |
| `scripts/ios/render-app-icon.sh [proof.png]` | Re-renders `AppIcon-1024.png` from `BrandGeometry.swift` (and optionally a brand proof sheet). Run after changing the mark. |

Single package directly: `swift test --package-path ios/Packages/JovraCore`.

## What the UI smoke test checks

`JovraSmokeUITests` launches the app with `-appearance light|dark|system` (the Profile → Appearance
preference, read from `UserDefaults`), visits every tab, asserts the heading, the selected state and
44 pt targets, attaches a screenshot, and runs `performAccessibilityAudit()` on each tab and on the
full-screen capture route. `testEveryTabAtLargestAccessibilityTextSize` repeats the tour at the
largest accessibility text size (AX5, launched with `-UIPreferredContentSizeCategoryName
UICTContentSizeCategoryAccessibilityXXXL`). It asserts that the tab bar stays one compact row with
every title on one line, and that the Sessions filter pills stack instead of breaking words. It
attaches `ax5-*` screenshots and audits every tab.

Each audit runs on the screen as first shown, then again one, two, and more slow swipes further
down, until the end of the screen. Content first seen cut off at the bottom is therefore audited
fully visible at a later step.

There are two documented audit exceptions, and the test logs every issue it ignores:

- **Dynamic Type on tab bar titles.** Like the system tab bar, `JovraTabBar` caps its titles at
  `xxxLarge` and offers the Large Content Viewer (touch and hold) beyond that. Only text inside the tab
  bar's frame is exempt.
- **Contrast on clipped content.** This covers a non-tab-bar element under the status-bar backdrop, or
  one reaching into the tab bar or within 16 pt of it. The audit's sampling there takes in the bar
  and the chartreuse Record circle, not the element. SwiftUI keeps off-screen scroll content in the
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

## Disk hygiene

The build Mac is short on disk. Always build with `-derivedDataPath .derivedData` (the scripts do),
never into `~/Library/Developer/Xcode/DerivedData`, keep a single derived-data directory, and delete
it when you finish a ticket: `rm -rf .derivedData`.

## CI (`.github/workflows/ci.yml`)

- `jovra-core` (required): `swift test` in `ios/Packages/JovraCore` inside the `swift:6.1` container on Ubuntu.
- `media-fixtures`: on Ubuntu, `render.py --check` (renders with apt's ffmpeg and requires the committed
  decoded-frame hashes) and `scripts/spec/validate.py`.
- `ios-app (manual)`: `workflow_dispatch` only. On macOS it runs both package test suites, generates
  the project, builds the app and runs `JovraTests`. Simulator UI suites run on the build Mac, and
  their evidence goes on the PR (ADR-0006).

## Evidence

A ticket is done when a check that could fail has passed (CLAUDE.md rule 9). Attach command output,
test counts, the simulator id and the screenshots from `evidence/ios/<ticket>/` to the PR. Report
simulator results, device results and store readiness separately.
