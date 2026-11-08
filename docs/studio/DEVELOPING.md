# Developing JOVRA Studio (iOS)

JOVRA Studio is the film and multi-camera layer (spec: `docs/spec/studio-v1-spec.md`; tickets:
`docs/spec/studio-tickets.md`). It builds on the core app and follows everything in `docs/DEVELOPING.md` (toolchain,
simulator hygiene, derived data inside your worktree). This page covers only what is different for Studio. It was set
up by ticket S04.

## Packages

| Package | Holds | Depends on | Tested |
|---|---|---|---|
| `ios/Packages/JovraStudioCore` | Foundation-only Studio domain modules: contracts, EDL, ledger, project, cloud client, room records, planner and the rest | `JovraCore` | macOS and Linux (CI job `jovra-studio-core`) |
| `ios/Packages/JovraStudioMedia` | AVFoundation / CoreMedia Studio code: ingest, proxies, anchors, the film renderer and verifier | `JovraStudioCore`, `JovraMedia`, `JovraCore` | macOS |

The spec names "a Studio area of JovraMedia". Studio uses a sibling package instead, because core ticket T10 is the
only ticket that edits JovraMedia's manifest, and so Studio media tickets never touch core-owned folders.

**JovraStudioCore must never import an Apple-only framework** (AVFoundation, UIKit, SwiftUI, CoreMedia, ...). The
Linux job proves it on every pull request by building the package graph in a `swift:6.1` container, and a grep step
fails first with a clear message. Anything that needs AVFoundation goes in JovraStudioMedia.

A Studio ticket adds a folder per module (`Sources/JovraStudioCore/<Module>`, `Tests/JovraStudioCoreTests/<Module>`,
and the same in JovraStudioMedia). Neither manifest needs an edit for that.

### Shared fixtures

Tests read the shared Studio conformance fixtures in place, never a copy: `spec/studio/fixtures` (records, invalid
cases and vectors), validated by `scripts/spec/validate_studio.py` and shared with Android. Each package's test target
has `Support/StudioFixtures.swift`, which finds the folder from its own `#filePath`, a fixed number of folders below the
repository root, and never searches upwards:

```swift
let data = try StudioFixtures.data("records/project-lock.json")
let url = try StudioFixtures.url("vectors/<file>.json")
```

A moved or renamed fixtures folder makes the locator throw ("spec/studio/fixtures not found at ..."), so a test fails
instead of reading something else. Expected values come from the fixtures (the Python reference), never from the
Swift code under test.

## App, project and configuration

S04 is the only Studio ticket that edits `ios/project.yml`. It added, once, everything later Studio tickets need:

| What | Value | For |
|---|---|---|
| Packages | `JovraStudioCore`, `JovraStudioMedia` | linked into the app (`Jovra`) and into `JovraUITests` |
| `JovraTests` | declares `JovraStudioCore` | hosted unit tests in `ios/JovraTests/Studio` import both Studio packages (see below) |
| `NSLocalNetworkUsageDescription` | "JOVRA Room uses your local network to find and connect the phones filming your match together." | JOVRA Room on the LAN (spec SD10, ADR-0027) |
| `NSBonjourServices` | `_jovra-room._tcp` | the Room service type (`spec/room`); the service carries only an opaque room hint |
| `BGTaskSchedulerPermittedIdentifiers` | adds `com.islanddevcrew.jovra.continued.studio-render` | Studio film rendering as a user-started continued-processing task on iOS 26 (foreground with resumable checkpoints on iOS 18). Register it through core T27's scheduler adapter, never a second registration |
| `JovraStudioEnvironment` | `$(STUDIO_ENVIRONMENT)` | the Studio cloud mode the app was built for |

`JovraTests` declares only `JovraStudioCore`. Declaring `JovraStudioMedia` as well pulls `JovraMedia` into the test
bundle's link and leaves JovraMedia symbols that core tests use undefined (observed linker failure, S04). Hosted tests
still `import JovraStudioMedia`: the app links it, and its symbols reach the test bundle through the test host, the same
way `JovraMedia` already does for the core tests.

`NSLocalNetworkUsageDescription` is not yet in `ios/Jovra/Resources/Localization/InfoPlist.xcstrings`. That table
belongs to the localization owner (T06), so the string is added there by that owner, not by a Studio ticket.

### Studio.xcconfig

`ios/Config/Studio.xcconfig` is committed and is included from `ios/Config/Jovra.xcconfig` with one optional
`#include? "Studio.xcconfig"` line (a core-owned file, reviewed by the core owner). It sets:

```
STUDIO_ENVIRONMENT = demo
```

`demo` is the default: in-process Sample content, no network, no account, no charge. It must never hold a URL, a key or
a secret (CLAUDE.md rule 5, user story 245). Check with
`grep -nEi "https?://|key *=" ios/Config/Studio.xcconfig` (no output). Test and Live configuration, when they arrive,
come from configuration outside source control.

## Commands

| Command | What it does |
|---|---|
| `swift test --package-path ios/Packages/JovraStudioCore` | Studio domain tests (macOS; the same suite runs on Linux in CI) |
| `swift test --package-path ios/Packages/JovraStudioMedia` | Studio media tests (macOS) |
| `python3 scripts/spec/validate_studio.py [-v \| --list]` | Studio contracts, fixtures, reference, module pages and determinism |
| `scripts/ios/generate.sh` | regenerate the Xcode project after adding or removing files |
| `xcodebuild test -project ios/Jovra.xcodeproj -scheme Jovra -only-testing:JovraTests/<StudioSuite> -destination id=<your simulator> -derivedDataPath <worktree>/.derivedData` | hosted Studio unit tests (`ios/JovraTests/Studio`) |
| `scripts/ios/ui-test.sh -only-testing JovraUITests/<StudioClass> studio/<ticket>` | Studio UI tests (`ios/JovraUITests/Studio`), screenshots exported to `evidence/ios/studio/<ticket>/` |

Every script takes `SIMULATOR_ID=<your simulator>` and `DERIVED_DATA=<path inside your worktree>`; always pass your own
simulator (the scripts' default belongs to another project).

## Folders

```
ios/Packages/JovraStudioCore/      Sources/JovraStudioCore/<Module>, Tests/JovraStudioCoreTests/<Module>, .../Support
ios/Packages/JovraStudioMedia/     Sources/JovraStudioMedia/<Module>, Tests/JovraStudioMediaTests/<Module>, .../Support
ios/Jovra/Features/Studio/<Area>/  Studio screens, one folder per screen family
ios/Jovra/Platform/Studio{Cloud,Room,Providers,Background}/   app-side adapters
ios/Jovra/DesignSystem/Studio/     cross-family Studio components (Sheets/ for shared sheets)
ios/JovraTests/Studio/             hosted Studio unit tests
ios/JovraUITests/Studio/           Studio UI tests (see its README)
```

## CI

`.github/workflows/studio.yml` runs on every pull request and on pushes to `main`, with no path filter so either job
can be made a required check:

- `studio-contracts` (Ubuntu): `python3 scripts/spec/validate_studio.py`.
- `jovra-studio-core` (Ubuntu, `swift:6.1` container): the Apple-only import grep, then `swift test` for
  JovraStudioCore.

JovraStudioMedia and the app are tested on the build Mac; attach that evidence to the pull request. The core
`ci.yml` is never edited by a Studio ticket.

## Evidence

Each Studio ticket keeps its evidence in `evidence/ios/studio/<ticket>/` (for example
`evidence/ios/studio/s04-studio-packages-ci/`): test logs, `plutil -p` output, CI links and screenshots as JPEG
(`sips -s format jpeg -s formatOptions 70 -Z 1400`). Screenshots and fixtures use synthetic or visibly labelled Sample
data only, never real footage.
