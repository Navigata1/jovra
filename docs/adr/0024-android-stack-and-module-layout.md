# Android: Kotlin + Compose on a pinned two-lane toolchain, JVM domain modules and a conformance harness in `:core`

Status: accepted (2026-10-07) for the architecture, module layout and rules below. The version pins are **chosen, not
verified**: nothing has been synced or built, and transitive resolution is UNVERIFIED until gate G-RESOLVE passes
(CLAUDE.md rule 9). Amends ADR-0001 (Android start condition only); ADR-0001's owner should add the matching note
"Status: amended by ADR-0024 (Android start condition only)". The rest of ADR-0001 stands.

ADR-0001 chose native apps per platform with shared **contracts**, not code, and put Android "after the iOS capture
gates pass". On 2026-10-07 Jon approved proceeding with the Adaptive/Watch v3 handoff, which includes native Android
phone, tablet and foldable screens (references 41–60) and a Wear OS companion (66–70)
(`docs/handoff/JON-ORIGINAL-PROMPT.md`, decisions addendum item 4, OBSERVED). Android work therefore starts now, in
parallel with iOS. What does **not** change: Android capture durability, 60 fps, thermals and field behaviour still
need their own physical-device gate, and nothing about Android capture may be claimed from iOS evidence or emulators.

## Decision

**Stack.** Kotlin with Jetpack Compose (Material 3, material3-adaptive), CameraX for capture, Media3 for playback,
frame extraction and export, Navigation 3 with `@Serializable` keys in a saveable back stack, Compose for Wear OS for
the watch. Domain logic is written again in Kotlin and held to the shared fixtures; no code is shared with iOS.

**Two pinned lanes** (OBSERVED in each AAR's own `aar-metadata.properties`, `docs/research/android/toolchain-and-devices.md`
§3.2). Every current-stable AndroidX UI artifact (Compose UI 1.12.1, adaptive 1.3.0, Navigation 3 1.2.0, core 1.19.1,
lifecycle 2.11.0's Navigation 3 artifact, Wear Compose 1.7.1) declares `minCompileSdk=37`, and the build Mac has only
platforms 35 and 36. So:

| | Lane A (build now, zero installs) | Lane B (after gate G-SDK37) |
|---|---|---|
| Build | AGP 9.1.1, Gradle 9.3.1 (already on disk), Kotlin/KGP 2.4.20 via AGP 9 built-in Kotlin, JDK 17 | same AGP/Gradle/Kotlin |
| SDK | compileSdk 36, targetSdk 36, minSdk 29 (Wear: 36/36/30) | compileSdk 37; targetSdk stays 36 until G-TARGET37 |
| UI | Compose BOM 2026.06.01 (UI 1.11.4, Material 3 1.4.0, adaptive 1.2.0), Navigation 3 1.1.7, lifecycle 2.10.0 everywhere, core 1.18.0, Wear Compose 1.6.2 | BOM 2026.09.00, Navigation 3 1.2.0 + adaptive-navigation3 1.3.0, lifecycle 2.11.0, core 1.19.1, Wear Compose 1.7.1 |
| Shared | CameraX 1.6.2, Media3 1.11.1, WindowManager 1.5.1 (+ window-testing), WorkManager 2.12.0, kotlinx.serialization 1.11.0, coroutines 1.11.0, DataStore 1.2.1, Credential Manager 1.6.0, play-services-wearable 20.0.1, Tiles 1.6.2 | same |

Lane B is one version-catalog diff plus `compileSdk`. Raising **targetSdk** to 37 is not a version bump: it makes
`ACCESS_LOCAL_NETWORK` mandatory, which changes the room transport (ADR-0027), so it has its own gate (G-TARGET37).
All lifecycle artifacts move together, because they are version-aligned and a single 2.11.0 artifact would pull the
rest above compileSdk 36 (INFERRED from the alignment constraint).

**Persistence (ADR-0002 unchanged).** Each session and Studio project is a folder with its versioned JSON document,
written atomically (temp then rename, `AtomicFile` or `Files.move(ATOMIC_MOVE)`), serialized with kotlinx.serialization
to the same `spec/schemas` shapes as iOS. **No androidx Room and no SQLite.** DataStore holds preferences only, never
session data. No Hilt and no annotation processing (KSP or kapt): dependencies are wired by plain constructor
injection, and kapt does not work with AGP 9 built-in Kotlin anyway (OBSERVED, toolchain research §0.7).

**Module layout** (`android/`, one Gradle build, SDK levels set once in `build-logic` convention plugins):

| Kind | Modules | Rule |
|---|---|---|
| Pure JVM (no Android) | `:core`, `:studio-core`, `:room-protocol`, `:testing` | Domain twins of iOS JovraCore, `spec/reference/studio` and the room state machines. Testable with only a JDK |
| Android libraries | `:designsystem`, `:data`, `:media`, `:room-transport`, `:wear-bridge`, `:feature:{home,sessions,record,insights,profile}`, `:studio:{build-match,films,editor,cloud}` | One module per phone destination; `:room-transport` is the only module that touches sockets, NSD or Wi-Fi |
| Applications | `:app` (phone, tablet, foldable), `:wear` | `:wear` uses the **same applicationId and signing key** as `:app` (see below) |

The multi-phone protocol modules are named `:room-protocol` and `:room-transport`, **never `:room`**: in an Android
repository `:room` reads as androidx Room, which ADR-0002 rules out, and an agent could add it "helpfully". The product
term stays "JOVRA Room v1" (ADR-0017, ADR-0027).

`:wear` shares `:app`'s package name and signing key because the Wearable Data Layer only connects apps whose
"package name must match across devices" and whose signature matches (OBSERVED, developer.android.com Data Layer
overview). The two ship as separate APKs from one applicationId; flavours or a renamed watch package would silently
break the bridge.

**Conformance harness in `:core`.** The Kotlin domain is held to `spec/` exactly as JovraCore is:

1. Fixtures are read **in place** from `<repo>/spec/fixtures` and `<repo>/spec/studio/fixtures` through a Gradle system
   property (`jovra.repoRoot`), with `inputs.dir("../spec")` so a fixture change reruns the tests. Never copied.
2. One JUnit Jupiter dynamic test per fixture file and kind; an **unknown fixture kind fails** the run, mirroring
   `scripts/spec/validate.py`, so a new fixture can never be skipped silently.
3. JSON is compared by deep equality with integers only; CSV is compared **byte-for-byte** (UTF-8, no BOM, LF, minimal
   quoting, ASCII hyphen-minus). Percentages use ADR-0011's integer `pct(n, d) = (200n + d) div (2d)`; unit
   conversions use `BigDecimal` with at least 20 digits, rounded half-up once (`spec/README.md`). `DecimalFormat`
   (half-even) is forbidden.
4. A required CI job `android-core` runs `:core:test :studio-core:test :room-protocol:test` on a plain JDK 17 with no
   Android SDK. A spec change that Android has not caught up with fails there, which is the point of ADR-0001.

**Tests and evidence.** JUnit Jupiter 6.1.3 for the JVM modules; JUnit 4 with Robolectric 4.17, Compose UI tests and
Roborazzi 1.76.0 for Android modules; espresso-device, UI Automator and Maestro 2.11.0 on local emulators only.
Robolectric needs JDK 21 to run at SDK 36 (OBSERVED, Robolectric 4.16 notes) and the build Mac has JDK 17 and 27
only, so local Robolectric pins SDK 34 and CI runs SDK 36 on the runner's JDK 21 (gate G-JDK21). Roborazzi goldens are
recorded and verified on CI Linux. Emulator, Maestro and Wear pairing evidence is local and attached to the PR.

**Machine rules.** Agents do not install SDK packages or images, create AVDs, boot emulators or clear caches while
other projects share the machine; the data volume is at 99% with 14 GiB free (OBSERVED 2026-10-07). The existing
`OlamyPixel` AVD belongs to another project and is never touched. Each install is a named gate that Jon approves:
G-SDK37, G-DISK (at least 25 GiB free first), G-IMG36, G-WEARIMG, G-WEARPAIR (Jon signs in to the emulator's Google
account himself; agents do not enter credentials) and G-16K. The full gate table is §9 of the toolchain research.

## Considered Options

- **Current-stable only (BOM 2026.09.00, compileSdk 37).** Correct as "latest" (it is what
  `technical-feasibility.md` §14 lists), but `checkAarMetadata` fails on the installed SDK today. Kept as Lane B.
- **Kotlin Multiplatform for the domain.** Rejected again for now (ADR-0001): it ties the iOS build to Gradle. The
  conformance suite is the drift guard; revisit only if it shows real duplication pain.
- **androidx Room / SQLite.** Rejected by ADR-0002 (two schemas for one record). An in-memory index over JSON folders
  is ample at hundreds of sessions.
- **Hilt.** Needs annotation processing; constructor injection is enough for an app of this size.
- **Navigation Compose 2.10.** Needs compileSdk 37. Navigation Compose 2.9.8 type-safe routes is the documented
  fallback if Navigation 3 1.1.7 fails G-RESOLVE.
- **JUnit 5 on Android** (`android-junit5`). Rejected: Robolectric, Roborazzi and Compose test rules are JUnit 4.

## Consequences

- Every rule change lands first as a fixture change and must pass in Swift and Kotlin. Two domain implementations is
  the accepted cost of ADR-0001.
- Lane A ages: when Jon approves G-SDK37 the catalog moves to Lane B, and Lane A becomes history, not a fork.
- Emulator runs prove layout and logic only. Named hardware without an installed profile (Pixel 10, Galaxy S26,
  Galaxy Watch Ultra) is reported as an approximation, never as device validation. Capture, fps, thermals and
  Data Layer timing need a physical Pixel and Galaxy Watch.

Sources: `docs/research/android/toolchain-and-devices.md` §§0–9 (local inventory OBSERVED 2026-10-07; Google Maven
AAR metadata; AGP, KGP, Robolectric and runner-image notes); `docs/adr/0001`, `0002`, `0011`, `0017`;
`docs/handoff/JON-ORIGINAL-PROMPT.md` decisions addendum; `spec/README.md`; `spec/studio/README.md`;
https://developer.android.com/training/wearables/data/overview (package name and signature must match, accessed
2026-10-07); https://developer.android.com/build/releases/about-agp ;
https://kotlinlang.org/docs/gradle-configure-project.html ; https://github.com/robolectric/robolectric/releases .
