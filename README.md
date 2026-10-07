# JOVRA Tennis

**See your game.** JOVRA records your tennis, finds the points that matter, shows metrics you can
trust, and keeps your video yours. Every number says where it came from (manual, estimated, reviewed or
validated), originals are saved on your device first, and recording never waits on analysis, the
network or an account.

iOS comes first (SwiftUI, AVFoundation, Vision), then Android (Kotlin, Jetpack Compose, CameraX,
Media3). The two apps share contracts, not code (see `docs/adr/0001`).

## Status

Early development. Ticket #1 (foundation) provides:
- the generated Xcode project
- the `JovraCore` and `JovraMedia` packages
- the JOVRA design system and the redrawn Court Arc mark and app icon
- the five-tab shell (Home, Sessions, Record, Insights, Profile), with placeholder screens
- a full-screen route mechanism for capture, replay and compare
- a UI smoke test with accessibility audits, and CI

Recording and analysis are not built yet. Placeholder screens say so.

## Run it

Requirements: Xcode 26 with an iOS 26 simulator, and XcodeGen (`brew install xcodegen`).

```sh
scripts/ios/generate.sh      # creates ios/Jovra.xcodeproj
open ios/Jovra.xcodeproj     # run the Jovra scheme on an iPhone simulator
scripts/ios/test.sh          # package tests + app unit tests
scripts/ios/ui-test.sh       # UI smoke test, screenshots to evidence/ios/<ticket>/
```

See `docs/DEVELOPING.md` for the toolchain, simulator choice and derived-data hygiene, and
`CLAUDE.md` for the project's hard rules.

## Contact

hello@islanddevcrew.com

© Island Development Crew
