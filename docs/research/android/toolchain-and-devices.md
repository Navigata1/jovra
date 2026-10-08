# JOVRA Android: toolchain, versions, repo layout, CI and device plan

Research note, 2026-10-07. Scope: native Android (Kotlin + Jetpack Compose) for phones, tablets and foldables, plus a
Wear OS companion, inside the existing contracts-not-code rule (ADR-0001). Nothing here was built, installed or booted.

**Labels.** **OBSERVED** means read from this machine (command output quoted below) or a primary source (Google Maven
metadata, an AAR's own `aar-metadata.properties`, developer.android.com, kotlinlang.org, the Robolectric and GitHub
runner-image release notes). **INFERRED** means reasoned from observed facts. **UNVERIFIED** means not checked here and
must be proved by the named gate before anyone relies on it. A version is "chosen" here, not "verified": the first
Gradle sync and build is the check that can fail (CLAUDE.md rule 9).

**Rules followed while gathering this.** No `git`, no `sdkmanager --install`, no AVD creation, no emulator boot, no
cache clearing. The commands used were read-only (`ls`, `du`, `cat` on `source.properties`/`config.ini`, `avdmanager
list device`, and `curl` of public Maven metadata and AAR files into the session scratchpad, which were deleted after
reading).

---

## 0. Decisions in one page

1. **Two pinned lanes, one switch.** Lane A builds on the SDK that is installed **today** (platforms 35/36, build-tools
   35/36, JDK 17) with zero installs and zero new Gradle distributions. Lane B is the current-stable stack (Compose BOM
   2026.09.00, Navigation 3 1.2.0, adaptive 1.3.0, Wear Compose 1.7). It needs one 67 MB SDK package
   (`platforms;android-37.0`) behind gate **G-SDK37**. Ship Lane A first; Lane B is one version-catalog edit and one
   `compileSdk` change.
2. **Why two lanes (OBSERVED, decisive).** Every current-stable AndroidX UI artifact now declares
   `minCompileSdk=37` and `minAndroidGradlePluginVersion=9.1.0` in its AAR metadata: Compose UI 1.12.1,
   material3-adaptive 1.3.0, Navigation 3 1.2.0, Navigation Compose 2.10.2, adaptive-navigation3 1.3.0,
   lifecycle 2.11.0's `viewmodel-navigation3`, core 1.19.1, Wear Compose Material 3 1.7.1 and Wear compose-navigation3
   1.7.1 (§3.2). The installed SDK has no android-37 platform, so "latest stable" fails `checkAarMetadata` on this
   machine today. The earlier research row ("Compose BOM 2026.09.00; Navigation 3 1.2.0; compileSdk 37",
   `docs/research/technical-feasibility.md` §14) is therefore **Lane B**, not something the machine can build now.
3. **Build tool pin (Lane A).** AGP **9.1.1**, Gradle **9.3.1** (already in `~/.gradle/wrapper/dists`), Kotlin
   **2.4.20** through AGP 9's built-in Kotlin with the KGP version raised, JDK **17**. KGP 2.4.20 officially supports
   Gradle 7.6.3–9.7.0 and AGP 8.5.2–9.3.1, so the whole triple sits inside the published matrix (OBSERVED,
   kotlinlang.org). AGP 9.1.1 is the first AGP that accepts API 37.0, so Lane B needs no AGP change to compile against 37.
4. **SDK levels.** Phone/tablet/fold app: `compileSdk 36`, `targetSdk 36`, `minSdk 29`. Wear app: `compileSdk 36`,
   `targetSdk 36`, `minSdk 30`. Play requires target 36 for phone apps since 2026-08-31 and 35+ for Wear OS
   (OBSERVED in `technical-feasibility.md` §14).
5. **Navigation.** Navigation 3 (1.1.7 in Lane A, 1.2.0 in Lane B), with `@Serializable` keys in a saveable back
   stack. This is type-safe by construction and puts the back stack in app state, which the "survive fold, rotate and
   process death" contract needs. Navigation Compose 2.9.8 with type-safe routes is the documented fallback.
6. **Persistence.** JSON documents with kotlinx.serialization and atomic temp-then-rename writes (ADR-0002).
   **No androidx Room, no SQLite.** DataStore Preferences only for preferences. Because of this, the multi-phone
   protocol module must **not** be called `:room` (§5.1).
7. **No annotation processing.** No Room and no Hilt (DI is plain constructor injection), so no KSP and no kapt.
   kapt is incompatible with built-in Kotlin anyway (OBSERVED).
8. **Tests.** JUnit Jupiter 6.1.3 for the pure-JVM `:core` conformance suite. JUnit 4 + Robolectric 4.17 +
   Compose UI test + Roborazzi 1.76.0 for Android modules. Maestro 2.11.0 (installed) and instrumented tests run on
   local emulators only. **Robolectric needs JDK 21 to run at SDK 36 (OBSERVED, 4.16 notes)**; the machine has JDK 17
   and 27 only, so local Robolectric runs pin `sdk=34`, and CI runs SDK 36 on the runner's JDK 21 (§6.3).
9. **CI on `ubuntu-latest`.** A new required job `android-core` (JVM only, no SDK) and `android-unit` (Robolectric,
   Roborazzi verify, lint, assemble). The runner image already has android-36, android-37.0, build-tools 36/37,
   JDK 17 (default) and JDK 21 (OBSERVED, runner-images README). Emulator and Maestro runs stay on the build Mac.
10. **Disk is the binding constraint.** The data volume is at **99%: 14 GiB free** (OBSERVED). One phone AVD plus
    the first full Gradle build fits. The Wear OS image, a Play Store phone image (needed for watch pairing) and an
    API 36 phone image do not fit together. They are gated on free space (§8, gate **G-DISK**).

---

## 1. What is installed (OBSERVED, 2026-10-07)

### 1.1 Android SDK (`~/Library/Android/sdk`, 8.2 GB)

| Component | Installed | Evidence |
|---|---|---|
| Platforms | `android-35` (130 MB), `android-36` (134 MB) | `ls platforms`, `du -sh` |
| Build-tools | `35.0.0`, `36.0.0` | `ls build-tools` |
| System images | **one**: `system-images;android-35;google_apis;arm64-v8a`, rev 9, API 35 ext 13, needs emulator ≥ 33.1.24, **3.8 GB** | `source.properties`, `du -sh` |
| Emulator | 36.5.11 (1.1 GB) | `emulator/source.properties`. Latest stable channel offers 37.2.12 |
| cmdline-tools | `latest` = 20.0 | `cmdline-tools/latest/source.properties`. Channel offers 23.0 |
| Platform-tools | 37.0.0 | Channel offers 37.0.1 |
| NDK / CMake | NDK 27.1.12297006 (2.4 GB), CMake 3.22.1 | Not needed: JOVRA has no native code. AGP 9.x default NDK is 28.2.13676358 |
| Not installed | android-37 platform; any Wear OS image; any Play Store image; any API 36/37 phone image; any 16 KB page-size (`_ps16k`) image | `ls` |

### 1.2 AVDs (`~/.android/avd`, 7.3 GB)

One AVD, owned by another project: `OlamyPixel` (device `pixel_7`, `system-images/android-35/google_apis/arm64-v8a/`,
2 GB RAM, 6 GB data partition, quick-boot on). Its folder is **7.3 GB**: `userdata-qemu.img.qcow2` 5.56 GB and
`snapshots/` 2.0 GB. JOVRA must not touch, reuse or boot it.

### 1.3 JDK, Gradle and tools

| Item | Value | Evidence |
|---|---|---|
| JDK 17 | `openjdk 17.0.19 2026-04-21` (Homebrew) at `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home` | `java -version` |
| Other JDK | Homebrew `openjdk` = **27** (2026-09-15). No JDK 21. `/usr/libexec/java_home -V` finds no registered JDK, so `JAVA_HOME` must be set explicitly | `java -version`, `java_home -V` |
| Gradle on PATH | none (`gradle not found`). Projects use the wrapper | `which gradle` |
| Wrapper distributions | `gradle-8.14.3-bin` (146 MB), `gradle-9.3.1-bin` (145 MB) | `ls ~/.gradle/wrapper/dists` |
| `~/.gradle` | 8.4 GB in total: `caches/8.14.3` 3.8 GB, `caches/9.3.1` 2.5 GB, `modules-2` 1.8 GB, `build-cache-1` 43 MB | `du -sh` |
| Cached artifacts worth noting | AGP 9.1.0 and 9.2.0, KGP 2.2.10, CameraX 1.6.0, Media3 1.9.0, WindowManager 1.5.1, coroutines 1.10.2 (from other projects) | `ls modules-2/files-2.1` |
| Maestro | 2.11.0 at `/opt/homebrew/bin/maestro` | `maestro --version` |
| Disk | `/System/Volumes/Data`: 926 GiB, **14 GiB free, 99% used** | `df -h` |

### 1.4 Device profiles available to `avdmanager` (OBSERVED)

All the profiles named in the brief exist. Dimensions come from `sdklib.core.jar` `devices/*.xml`; dp = px × 160 / dpi.

| Profile id | Panel (px) | Density | Logical size (dp) | Notes |
|---|---|---|---|---|
| `pixel_9` | 1080 × 2424, 6.24" | 420 | 411 × 923 | Compact phone |
| `pixel_9_pro` | 1280 × 2856, 6.3" | xxhdpi (480) | 427 × 952 | Compact phone |
| `pixel_9_pro_xl` | 1344 × 2992, 6.8" | 480 | 448 × 997 | Compact phone (large) |
| `pixel_9_pro_fold` | inner 2076 × 2152, 8"; folded 1080 × 2424 | 390 | inner ≈ 852 × 883; outer ≈ 443 × 994 | Hinge postures 1,2,3 = 0–30°, 30–150°, 150–180° |
| `pixel_fold` | inner 2208 × 1840, 7.58"; folded 1080 × 2092 | 420 | inner ≈ 841 × 701; outer ≈ 411 × 797 | Landscape-first inner |
| `pixel_tablet` | 2560 × 1600, 10.95" | xhdpi (320) | 1280 × 800 | Expanded tablet |
| `medium_phone` / `medium_tablet` | 1080 × 2400 / 2560 × 1600 | 420 / 320 | 411 × 914 / 1280 × 800 | Generic |
| `small_phone` | 720 × 1280 | xhdpi | 360 × 640 | Generic 360 dp |
| `resizable` (Experimental) | 1080 × 2400 | 420 | switchable | Phone / foldable / tablet / desktop modes in one AVD |
| `7.6in Foldable` | 1768 × 2208; folded 884 × 2208 | 420 | ≈ 674 × 841 / 337 × 841 | Generic fold-in |
| `8in Foldable` | (fold-out) | — | — | Postures 3,4 at 180–330°, 330–360° |
| `6.7in Foldable` | horizontal fold-in (flip) | — | — | Postures 1,2,3 |
| `wearos_xl_round` | 480 × 480, 1.5" | xhdpi | 240 × 240 | Closest to Galaxy Watch Ultra panel |
| `wearos_large_round` | 454 × 454, 1.39" | xhdpi | 227 × 227 | |
| `wearos_small_round` | 384 × 384, 1.2" | xhdpi | 192 × 192 | Smallest round target |
| `wearos_square` | 360 × 360, 1.2" | xhdpi | 180 × 180 | Shape sanity |
| `wearos_rect` | 402 × 476, 1.2" | xhdpi | 201 × 238 | Shape sanity |

**No `pixel_10*`, no Samsung and no Galaxy Watch profiles exist** (OBSERVED: absent from `avdmanager list device -c`).

---

## 2. Version selection method

For each library I took the newest **stable** version from Google Maven or Maven Central `maven-metadata.xml`
(OBSERVED on 2026-10-07). I then opened that AAR's `META-INF/com/android/build/gradle/aar-metadata.properties`. If
`minCompileSdk` was above 36, I walked back to the newest stable version whose `minCompileSdk ≤ 36` for Lane A. Two
compatibility matrices were then applied: AGP ↔ Gradle (developer.android.com) and KGP ↔ Gradle/AGP (kotlinlang.org).

What this does **not** prove: transitive resolution. A Lane A artifact could still pull a newer transitive version
(lifecycle and Compose use version-alignment constraints). The proving check is gate **G-RESOLVE**:
`./gradlew :app:checkDebugAarMetadata :wear:checkDebugAarMetadata :app:dependencies` passes on compileSdk 36 (§9).

---

## 3. Build toolchain

### 3.1 Choice and evidence

| Item | Lane A (now) | Lane B (after G-SDK37) | Evidence |
|---|---|---|---|
| JDK | 17 (`JAVA_HOME` above); Kotlin `jvmToolchain(17)` | 17 | AGP 9.1–9.4 require JDK 17 (OBSERVED, AGP notes) |
| Gradle | **9.3.1** (on disk) | 9.3.1, or 9.5.1 with AGP 9.3.x | AGP 9.1 needs Gradle ≥ 9.3.1; 9.2 ≥ 9.4.1; 9.3 ≥ 9.5.0; 9.4 ≥ 9.6.0 (OBSERVED, about-agp). Gradle 9.8.1 is current (OBSERVED, services.gradle.org) but outside KGP 2.4.20's tested max of 9.7.0 |
| AGP | **9.1.1** | 9.1.1, optionally 9.3.3 | AGP 9.1.1 is the minimum for API 37.0 (OBSERVED). Latest AGP is 9.4.1, but KGP 2.4.20's fully supported AGP range ends at 9.3.1 (OBSERVED). 9.1.1 keeps Gradle 9.3.1, so no new ~145 MB distribution and no new per-version cache (§8) |
| Kotlin / KGP | **2.4.20** (2026-09-07) | 2.4.20 | KGP 2.4.20 supports Gradle 7.6.3–9.7.0 and AGP 8.5.2–9.3.1 (OBSERVED, kotlinlang compatibility table). Kotlin 2.4 needs AGP ≥ 8.5.2 / R8 9.1.29 (OBSERVED, AGP Kotlin-support page). 2.4.21-RC and 2.5.0-Beta1 are not stable |
| Kotlin wiring | AGP 9 built-in Kotlin: do **not** apply `org.jetbrains.kotlin.android`. Raise KGP from the bundled 2.2.10 to 2.4.20 per "Upgrade to a higher KGP version" | same | AGP 9.0 has a runtime dependency on KGP 2.2.10 and auto-upgrades lower versions; a higher KGP is declared explicitly (OBSERVED, AGP 9.0 notes). Built-in Kotlin replaces kotlin-android only (OBSERVED) |
| Compose compiler | `org.jetbrains.kotlin.plugin.compose` 2.4.20 | same | Ships with Kotlin. Still applied, because built-in Kotlin replaces only kotlin-android (INFERRED from that quote; **G-RESOLVE** confirms) |
| Serialization plugin | `org.jetbrains.kotlin.plugin.serialization` 2.4.20 | same | Same version line as Kotlin |
| JVM module plugin | `org.jetbrains.kotlin.jvm` 2.4.20 for `:core`, `:studio-core`, `:room-protocol` | same | Pure Kotlin/JVM, no AGP |
| KSP / kapt | none | none | No Room, no Hilt. kapt is incompatible with built-in Kotlin (OBSERVED). If a processor is ever needed: KSP 2.3.12 (OBSERVED latest) |
| compileSdk | **36** | **37** (`platforms;android-37.0`, 67 MB zip) | Installed: 35/36 only (OBSERVED) |
| build-tools | 36.0.0 (installed; AGP default) | 36.0.0 | AGP 9.1–9.4 default 36.0.0 (OBSERVED) |
| targetSdk | 36 (phone), 36 (wear) | same | Play: phone target 36 since 2026-08-31; Wear 35+ (OBSERVED in feasibility §14) |
| minSdk | 29 phone; 30 wear | same | Phone 29: thermal status API 29, scoped storage (feasibility §14). Wear 30 = Wear OS 3, the oldest line still shipping on Galaxy Watch 4 (INFERRED); Wear Compose M3 1.6.2 itself allows 25 (OBSERVED manifest) |
| 16 KB pages | No native code of our own. Prebuilt `.so` from ML Kit/MediaPipe must be 16 KB aligned before 2027-02-01 | same | Feasibility §14 (OBSERVED there). Gate **G-16K** |

### 3.2 minCompileSdk evidence (OBSERVED, from each AAR's metadata)

| Artifact | Version | minCompileSdk | min AGP | Lane |
|---|---|---|---|---|
| compose ui-android | 1.12.1 | **37** | 9.1.0 | B |
| compose ui-android / foundation-android | 1.11.4 | 35 | 8.6.0 | **A** |
| compose runtime-android | 1.11.4 | 34 | 8.1.1 | A |
| material3-android | 1.4.0 | 35 | 8.6.0 | A, B |
| material3-adaptive-navigation-suite-android | 1.4.0 | 35 | 8.6.0 | A, B |
| adaptive-layout-android | 1.3.0 | **37** | 9.1.0 | B |
| adaptive-layout-android / adaptive-navigation-android | 1.2.0 | 35 | 8.6.0 | **A** |
| adaptive-navigation3-android | 1.3.0 (only stable) | **37** | 9.1.0 | B |
| navigation3-ui-android | 1.2.0 | **37** | 9.1.0 | B |
| navigation3-ui / runtime-android | 1.1.7 | 36 | 8.9.1 | **A** |
| navigation-compose-android | 2.10.2 | **37** | 9.1.0 | — |
| navigation-compose-android | 2.9.8 | 35 | 8.6.0 | A fallback |
| lifecycle-runtime-android | 2.11.0 / 2.10.0 | 34 / 34 | — | B / **A** |
| lifecycle-viewmodel-navigation3-android | 2.11.0 / 2.10.0 | **37** / 36 | — | B / **A** |
| core (core-ktx) | 1.19.1 / 1.18.0 | **37** / 36 | 9.1.0 / 8.9.1 | B / **A** |
| activity / activity-compose | 1.13.0 | 36 | 8.9.1 | A, B |
| window / window-core-android | 1.5.1 | 34 | 8.1.1 | A, B |
| camera-core / camera-video / camera-compose | 1.6.2 | 36 | 8.9.1 | A, B |
| media3-exoplayer / -transformer / -ui-compose | 1.11.1 | 36 | — | A, B |
| work-runtime | 2.12.0 | 35 | 8.6.0 | A, B |
| credentials | 1.6.0 | 35 | 8.6.0 | A, B |
| datastore-android | 1.2.1 | 34 | 8.1.1 | A, B |
| core-splashscreen | 1.2.0 | 35 | 8.6.0 | A, B |
| wear compose-material3 / -navigation | 1.7.1 | **37** | 9.1.0 | B |
| wear compose-material3 / -foundation / -navigation | 1.6.2 | 35 | 8.6.0 | **A** |
| wear compose-navigation3 | 1.7.1 (only stable) | **37** | 9.1.0 | B |
| wear tiles | 1.6.2 | 35 | 8.6.0 | A, B |
| play-services-wearable | 20.0.1 | 1 | — | A, B |
| play-services-auth | 22.0.0 | 1 | — | A, B |

The **lifecycle** rows matter. Lifecycle artifacts are version-aligned, so mixing `lifecycle-runtime 2.11.0` with
`lifecycle-viewmodel-navigation3 2.10.0` would pull the latter up to 2.11.0, which needs compileSdk 37 (INFERRED from
the alignment constraint). Lane A therefore pins **all** lifecycle artifacts to 2.10.0.

---

## 4. Library choices (Lane A pins; Lane B in brackets)

### 4.1 UI and adaptive layout

| Need | Choice | Why |
|---|---|---|
| Compose | BOM **2026.06.01** (ui/foundation/runtime 1.11.4, material3 1.4.0, adaptive 1.2.0) [2026.09.00: ui 1.12.1, adaptive 1.3.0] | Newest BOM whose members accept compileSdk 36 (§3.2). BOM 2026.06.01 maps material3 1.4.0 and adaptive 1.2.0 (OBSERVED, BOM POM) |
| Top-level nav chrome | `material3-adaptive-navigation-suite` 1.4.0: `NavigationSuiteScaffold` | Bottom bar on compact, rail on medium/expanded, from `currentWindowAdaptiveInfo()`. Five destinations: Home, Sessions, Record, Insights, Profile |
| Panes | `adaptive-layout` / `adaptive-navigation` 1.2.0: `NavigableListDetailPaneScaffold` (Sessions → session → replay), `NavigableSupportingPaneScaffold` (replay + notes/stats; Studio editor + inspector) | 1.2.0 adds Large/Extra-large width classes, `PaneExpansionState` drag-to-resize, reflow/levitate strategies and `preferredHeight` (OBSERVED, release notes). 1.3.0 adds margins/edge-to-edge and the Nav3 scene strategies |
| Window and posture | `currentWindowAdaptiveInfo().windowPosture` (`isTabletop`, `hingeList` with `isSeparating`/`isOccluding`) for layout. `androidx.window:window` 1.5.1 `WindowInfoTracker` → `FoldingFeature` (state, orientation, `occlusionType`) where the raw feature is needed | Brief: choose by window size, height and posture, never by device name. Compact height suppresses panes even when the window is wide |
| Test seams for folds | `androidx.window:window-testing` 1.5.1 (`TestWindowLayoutInfo`, `FoldingFeature(...)` builder, publisher rule) | Lets Robolectric and instrumented tests inject separating/occluding hinges without a fold emulator |
| Navigation | **Navigation 3 1.1.7** (`navigation3-runtime`, `navigation3-ui`) + `lifecycle-viewmodel-navigation3` 2.10.0. Back stack = `rememberNavBackStack` of `@Serializable` `NavKey`s [Nav3 1.2.0 + `adaptive-navigation3` 1.3.0 `ListDetailSceneStrategy` / `SupportingPaneSceneStrategy`] | Nav3 is stable since 2025-11-19, and 1.1.0 (2026-04-08) added scene decorators, multiple strategies and shared elements (OBSERVED, release notes). The back stack is plain saveable state, which is what "preserve selection, playhead and drafts through recreation" needs. Lane A has no stable Nav3 scene strategy for list/detail, so panes come from the Navigable*Scaffold inside a Nav3 entry. Lane B moves that into scene strategies. Fallback: Navigation Compose 2.9.8 type-safe routes |
| Activity / insets / back | `activity-compose` 1.13.0 (`enableEdgeToEdge`, `PredictiveBackHandler`), `core-ktx` 1.18.0 [1.19.1], `core-splashscreen` 1.2.0 | Target 36 makes edge-to-edge mandatory and predictive back default (OBSERVED, feasibility §14) |
| Lifecycle | 2.10.0 everywhere (`lifecycle-runtime-compose`, `-viewmodel-compose`, `-viewmodel-savedstate`, `-process`) [2.11.0] | Alignment, see §3.2 |
| Design system | Own `:designsystem` module: Material 3 theme with JOVRA colour roles mirrored from iOS `ColorRole` (light, dark, increased contrast), 48 dp minimum targets, type scale that honours font scale | Contract is semantic parity with iOS, not shared UI code (ADR-0001) |

### 4.2 Capture, media and analysis

| Need | Choice | Notes |
|---|---|---|
| Capture | CameraX **1.6.2** (`camera-core`, `camera-camera2`, `camera-lifecycle`, `camera-video`, `camera-compose`) | `SessionConfig` + `setFrameRateRange`, `GroupableFeature.FPS_60`, `isSessionConfigSupported`, `HighSpeedVideoSessionConfig` (since 1.5.0). 1.6.0 records through the Media3 muxer by default, with crash resilience (OBSERVED in feasibility §14). 1.7.0 is alpha. 60 fps is device-dependent and must be queried. The emulator cannot prove fps, thermals or encoder throughput |
| Segments and journal | Our `:media` `RecordingEngine` maps ADR-0010 onto CameraX `Recording` + `VideoRecordEvent.Finalize`, always checking the output URI | Durability bar is hardware-only (ADR-0010) |
| Fixture camera | Emulator `-camera-back videofile:<synthetic court>.mp4` (feasibility §14) plus an in-app fixture source for Robolectric | ADR-0012 equivalent; label simulator evidence as such |
| Playback / scrubbing | Media3 **1.11.1**: `media3-exoplayer`, `media3-ui-compose`, `SeekParameters.EXACT`, `setScrubbingModeEnabled(true)` | No frame-step API: pause + exact seek ± 1 frame (feasibility §14) |
| Frames / thumbnails | `media3-inspector-frame` 1.11.1 `FrameExtractor` | |
| Export / proxies | `media3-transformer` + `media3-effect` 1.11.1 (`ClippingConfiguration`, `OverlayEffect`, `TextOverlay`, HDR→SDR tone-map) | Also produces the Studio render proxies of `multicam-sync.md` §5 (CFR, rotation-baked, SDR) |
| Muxer | `media3-muxer` 1.11.1 (transitively through CameraX 1.6 and Transformer) | |
| Pose (optional, capability-gated) | ML Kit `pose-detection` 18.0.0-beta5 (beta: one person, face visible) or MediaPipe `tasks-vision` 0.10.26 | Off by default in the capability registry. Native libs need the 16 KB check (G-16K). Neither fits behind-baseline match footage (feasibility §14) |

### 4.3 Data, background work, identity, network

| Need | Choice | Notes |
|---|---|---|
| Documents | kotlinx-serialization-json **1.11.0** (1.12.0 is RC); writes through `androidx.core.util.AtomicFile` or temp + `fsync` + `Files.move(ATOMIC_MOVE)` | ADR-0002. Same JSON as `spec/schemas`. **androidx Room is out of scope** (ADR-0002 rejected SQLite/Room for v1; feasibility §13 confirms) |
| Preferences | `datastore-preferences` 1.2.1 | Appearance, units, last tab. Never session data |
| Coroutines | kotlinx-coroutines **1.11.0** (core, android, test) | |
| Background upload / render polling | WorkManager **2.12.0** for automatic, constraint-based work; `JobScheduler` user-initiated jobs (API 34+) for "Back up now" | WorkManager has no UIDT API. `dataSync` FGS has a 6 h / 24 h budget when targeting 35+ (feasibility §14) |
| Sign-in (backend-ready, ADR-0022) | Credential Manager `credentials` 1.6.0 (+ `credentials-play-services-auth` 1.6.0) for passkeys and the native Google option after its review. Email codes and the tester profile go through our own adapter | Tester credentials come from configuration, never source (CLAUDE.md rule 5) |
| Drive (later) | `play-services-auth` 22.0.0 `AuthorizationClient` for the Drive scope | Feasibility §13/§14. Tokens never stored as refresh tokens on device |
| HTTP | OkHttp **5.5.0** | Streaming upload bodies, MockWebServer in tests |
| JOVRA Room v1 carrier (Android) | Platform APIs only: `NsdManager` (DNS-SD; `registerServiceInfoCallback` API 34+), `SSLSocket` TLS 1.3 with a pinned SPKI via a custom `X509TrustManager`, `WifiManager.startLocalOnlyHotspot` (API 26) for the court network | Carriers and security are defined in `docs/research/studio/multicam-sync.md` §2. This note adds no new protocol; see §5.2 |

### 4.4 Wear OS companion

| Need | Choice [Lane B] | Notes |
|---|---|---|
| UI | Compose for Wear OS **Material 3 1.6.2** (`androidx.wear.compose:compose-material3`, `compose-foundation`) [1.7.1] | `ScreenScaffold`, `TransformingLazyColumn`, `EdgeButton`, rotary scrolling. Round-safe padding from the library. Large targets |
| Navigation | `androidx.wear.compose:compose-navigation` 1.6.2 (`SwipeDismissableNavHost`) [`compose-navigation3` 1.7.1] | Five surfaces only: health, score, latest serve, mark for review, connection alert |
| Tiles / complications (optional) | `androidx.wear.tiles:tiles` 1.6.2, `androidx.wear.protolayout` 1.4.2, `watchface-complications-data-source-ktx` 1.3.0 | Snapshots with timestamps, not live monitors (adaptive brief) |
| Phone ↔ watch | Wearable Data Layer, `play-services-wearable` **20.0.1**: `DataClient` for the latest snapshot (latest-state replacement), `MessageClient` for commands with receipts, `CapabilityClient` for node discovery | Session-connectivity brief. The Data Layer is not the cross-OS camera transport |
| Horologist | **Not in Lane A.** Latest is 0.8.4-alpha (alpha-only line; OBSERVED). Most of its layout helpers now exist in Wear Compose M3. Revisit `horologist-datalayer` only if its graph resolves on compileSdk 36 | Keep the dependency surface small |
| Health Services | `androidx.health:health-services-client` 1.1.0, **off by default** | Separate consent. Never start an exercise session to keep the radio alive (brief) |
| Ongoing activity | `androidx.wear:wear-ongoing` only if a real foreground recording-control session exists | No fake workouts |

### 4.5 Test stack

| Layer | Choice | Where it runs |
|---|---|---|
| `:core`, `:studio-core`, `:room-protocol` (pure JVM) | JUnit Jupiter **6.1.3** (`junit-bom` 6.1.3; JUnit 6 needs Java 17), `@TestFactory` dynamic tests, one per fixture file | CI `android-core` (required) and locally |
| Android unit | JUnit 4 (`junit:junit` 4.13.2) + `androidx.test.ext:junit` 1.3.0 + **Robolectric 4.17** (2026-09-10, supports SDK 37) + Turbine 1.2.1 + `kotlinx-coroutines-test` | CI `android-unit`; locally at `sdk=34` (see §6.3) |
| Compose UI | `androidx.compose.ui:ui-test-junit4` (from the BOM) + `ui-test-manifest`, run under Robolectric for logic and on the emulator for real rendering | CI (Robolectric) + local emulator |
| Screenshots | **Roborazzi 1.76.0** (Gradle plugin `io.github.takahirom.roborazzi`) on Robolectric Native Graphics. Size, font-scale, dark and fold-posture variants via `RoborazziComposeOptions` | Goldens are recorded on CI Linux and verified there. Mac renders can differ, so local runs use `compare`, not `verify` (INFERRED) |
| Instrumented | `androidx.test:runner` 1.7.0, `espresso-device` 1.1.0 (fold/posture and rotation actions on emulators that support them), UI Automator 2.4.0 | Local emulator only |
| Flows | Maestro 2.11.0 (installed) YAML flows: capture fixture → session → replay → export; fold/unfold state continuity | Local emulator only |
| JUnit 5 on Android | Not used. `android-junit5` plugin 2.0.1 exists, but Robolectric, Roborazzi and the Compose rules are JUnit 4 rule-based | Keeps one runner per module type |

---

## 5. Repository layout (`/Users/IDC2.5/jv/android/`)

### 5.1 Modules

```
android/
  settings.gradle.kts            includes, repository mode, version catalog
  build.gradle.kts               plugins apply false
  gradle.properties              org.gradle.jvmargs, android.useAndroidX, configuration-cache on
  gradle/libs.versions.toml      Lane A pins (§5.4); Lane B is a diff of this one file + compileSdk
  gradle/wrapper/                Gradle 9.3.1 (+ SHA-256 distributionSha256Sum)
  build-logic/convention/        jovra.jvm.library, jovra.android.library, jovra.android.compose,
                                 jovra.android.application, jovra.android.test (one place for SDK levels)
  core/                          JVM. Session model, scoring fold, stats, units (BigDecimal), CSV, schema-shaped
                                 serialization. Twin of iOS JovraCore. NO Android, NO coroutines-android
  studio-core/                   JVM. Studio records: EDL, SyncMap/syncfit, render-job state, credit ledger,
                                 story profiles. Twin of spec/reference/studio
  room-protocol/                 JVM. "JOVRA Room v1" envelopes, roles, invites, freshness, receipts,
                                 replay/epoch rejection, watch snapshot codec. No sockets
  testing/                       JVM test fixtures: repo-root resolver for ../spec, FakeMonotonicClock, JSON diff
  designsystem/                  Android lib. Theme, colour roles, type, 48 dp components, provenance badge
  data/                          Android lib. Document store (AtomicFile), library index rebuild, DataStore prefs,
                                 archive queue items as JSON (ADR-0002)
  media/                         Android lib. CameraX RecordingEngine (segments + journal, ADR-0010), fixture
                                 camera, thermal ladder, Media3 player/transformer/frame adapters
  room-transport/                Android lib. NSD advertise/browse, TLS socket carrier with SPKI pin, QR payload,
                                 LocalOnlyHotspot host. Implements room-protocol's Carrier interface
  wear-bridge/                   Android lib shared by :app and :wear. Data Layer paths, capability names,
                                 snapshot/command (de)serialization (types come from :room-protocol)
  feature/home|sessions|record|insights|profile/   one module per phone destination
  studio/build-match/            multi-phone "Build your match" (room UI, roles, health, invites)
  studio/films/                  five story films: profile pick, quote, job receipts, delivery
  studio/editor/                 sync review and cut editing panes (supporting-pane workspace)
  studio/cloud/                  backend adapters, off by default (ADR-0014/0019); local adapter is the default
  app/                           phone/tablet/foldable application: NavigationSuiteScaffold, Nav3 back stack,
                                 DI wiring, manifest, FileProvider
  wear/                          Wear OS application: five surfaces, tiles (optional), Data Layer listener
```

The Studio module names line up with the Studio specs. If `docs/spec/studio-screens.md` groups screens differently
when it lands, rename the modules to match. Those files are owned by concurrent workflows and were not edited here.

**Naming decision:** the multi-phone protocol modules are `:room-protocol` and `:room-transport`, never `:room`.
A module called `:room` in an Android repo reads as androidx Room. ADR-0002 forbids that library in v1, and an agent
could "helpfully" add it. The product term stays "JOVRA Room v1" (multicam-sync.md §0.2).

### 5.2 Reconciliation with "JOVRA Room v1" (do not duplicate)

`docs/research/studio/multicam-sync.md` §2 defines the carriers (LAN TLS/TCP + DNS-SD + QR, optional Apple-only
MultipeerConnectivity, opt-in Supabase Realtime room), the QR payload (`hostKeySha256`, 32-byte secret, nonce),
the message set (§2.5) and the framing: 4-byte length-prefixed JSON over TLS. The adaptive brief's
`session-connectivity.md` adds the watch-facing envelope: `hostEpoch`, `snapshotSeq`, `eventRevision`,
`ageAtBridgeMs`, receipts and the freshness thresholds 5 s / 15 s. **This note adds no protocol.** The Android
modules implement whichever contract lands in `spec/studio/` (owned by a concurrent workflow):

- `:room-protocol` holds pure state machines (epoch/sequence rejection, freshness from receiver-owned monotonic time,
  command idempotency by `commandId` + payload hash, per-device receipt fan-out). It runs the same golden vectors as
  the Python reference once they exist. `design-reference/adaptive/brief/watch-snapshot.sample.json` is a
  layout-only Sample until then.
- `:room-transport` is the only module that touches sockets, NSD or Wi-Fi. Android-specific constraints to honour
  (OBSERVED in multicam-sync §2.4): `NEARBY_WIFI_DEVICES` local-network protection on Android 16, `ACCESS_LOCAL_NETWORK`
  becoming mandatory for apps targeting 37+, and the NSD picker path preferred over a QR IP. **Moving to targetSdk 37
  is therefore a protocol-affecting change, not a version bump** (gate G-TARGET37).
- Clocks: Android uses `SystemClock.elapsedRealtimeNanos()` as the monotonic base (multicam-sync §3.1). Wall clock is
  informational only.

### 5.3 Conformance contract (same as iOS JovraCore)

`spec/README.md` is the contract. The Android twin must:

1. Read fixtures **in place** from `<repo>/spec/fixtures` (core) and `<repo>/spec/studio/fixtures` (Studio), never
   copied. `:testing` resolves the repo root from a Gradle-provided system property:
   `systemProperty("jovra.repoRoot", rootProject.projectDir.parentFile.absolutePath)`, plus
   `inputs.dir("../spec")` so a fixture change invalidates the test task's up-to-date check.
2. Run one dynamic test per fixture file and kind: `jovra.fixture.scoring` (fold per checkpoint, `fold.changes`
   diff), `expectError` codes, `stats`, `pct`, `units`, `sample` (real decoder → fold → stats → **CSV
   byte-for-byte**), and the records round-trip.
3. Compare parsed JSON by deep equality, with integers only. Use `pct(n, d) = (200n + d) / (2d)` in integer
   arithmetic. Use `BigDecimal` with ≥ 20 digits and half-up once for units. **Never use `DecimalFormat`** (half-even).
   Write CSV as UTF-8 without BOM, LF, minimal quoting. Use ASCII hyphen-minus in deltas.
4. Fail if any fixture `kind` is unknown, so new fixtures cannot be silently skipped. This mirrors
   `scripts/spec/validate.py`.
5. Keep `:core` free of Android so the required CI job needs only a JDK.

### 5.4 Version catalog for Lane A (proposal; the first sync is the check)

```toml
[versions]
agp = "9.1.1"                 # Lane B: unchanged (or 9.3.3 + Gradle 9.5.1)
kotlin = "2.4.20"
composeBom = "2026.06.01"     # Lane B: 2026.09.00
navigation3 = "1.1.7"         # Lane B: 1.2.0 (+ adaptive-navigation3 1.3.0)
lifecycle = "2.10.0"          # Lane B: 2.11.0
coreKtx = "1.18.0"            # Lane B: 1.19.1
activityCompose = "1.13.0"
window = "1.5.1"
camerax = "1.6.2"
media3 = "1.11.1"
work = "2.12.0"
datastore = "1.2.1"
credentials = "1.6.0"
playServicesAuth = "22.0.0"
playServicesWearable = "20.0.1"
wearCompose = "1.6.2"         # Lane B: 1.7.1
wearTiles = "1.6.2"
wearProtolayout = "1.4.2"
serialization = "1.11.0"
coroutines = "1.11.0"
okhttp = "5.5.0"
junitBom = "6.1.3"
junit4 = "4.13.2"
androidxTestExt = "1.3.0"
androidxTestRunner = "1.7.0"
espressoDevice = "1.1.0"
robolectric = "4.17"
roborazzi = "1.76.0"
turbine = "1.2.1"
mlkitPose = "18.0.0-beta5"    # optional, capability-gated
```

`compileSdk = 36`, `targetSdk = 36`, `minSdk = 29` (wear 30) live in `build-logic`, not in each module.

---

## 6. CI (GitHub `ubuntu-latest`)

### 6.1 What the runner has (OBSERVED, runner-images Ubuntu 24.04 README)

Android SDK at `/usr/local/lib/android/sdk` with platforms android-34 through android-37.2 (incl. 36 and 37.0),
build-tools 34.0.0–37.0.0, platform-tools 37.0.1, cmdline-tools 12.0, NDK 27.3/28.2/29.0. JDK 17.0.20 is the default,
and 21.0.12 is at `JAVA_HOME_21_X64`. Gradle 9.8.0 is on the image, but the wrapper decides. So **CI can build Lane A
and Lane B without any `sdkmanager` step.**

### 6.2 Proposed jobs (add to `.github/workflows/ci.yml` in a ticket; this note does not edit CI)

| Job | Required? | Steps | Why |
|---|---|---|---|
| `android-core` | **Required** (like `jovra-core`) | `actions/setup-java` (temurin 17), `gradle/actions/setup-gradle`, `./gradlew -p android :core:test :studio-core:test :room-protocol:test` | Pure JVM, no SDK. This is the cross-platform conformance gate. A spec change that Android has not caught up with fails here |
| `android-unit` | Required once `:app` exists | JDK 17 for Gradle; `./gradlew -p android testDebugUnitTest verifyRoborazziDebug lintDebug assembleDebug :wear:assembleDebug -Pjovra.robolectricJdk=21` (test workers on `JAVA_HOME_21_X64` via a toolchain launcher) | Robolectric at SDK 36 needs JDK 21. Lint catches missing permissions, edge-to-edge and predictive-back issues |
| `android-lane-b` | Optional, `workflow_dispatch` | Same with `-Pjovra.lane=B` (catalog overrides + compileSdk 37) | Proves the upgrade path before the local G-SDK37 install |

Emulator, Maestro, connected tests and Wear pairing are **local only**, with evidence attached to the PR under
`evidence/android/<ticket>/` (ADR-0006 pattern). GitHub's Linux runners can run x86_64 emulators with KVM, but that
adds minutes and flakiness for no device truth. Not proposed.

### 6.3 The JDK 17 / Robolectric constraint (OBSERVED)

Robolectric 4.16 release notes: "you need to use JDK 21 if running tests with SDK 36 target". 4.17 adds SDK 37. The
build Mac has JDK 17 and 27, not 21. Options, in order:

1. Locally put `sdk=34` in `src/test/resources/robolectric.properties` (Robolectric runs that SDK on JDK 17;
   INFERRED from the per-SDK requirement) and run SDK 36 in CI on JDK 21. Tests stay behaviour-level, and the
   SDK 36-only behaviours (Android 16 large-screen orientation override) are covered on the emulator gate instead.
2. Install a JDK 21 locally (gate **G-JDK21**, about 0.3 GB; INFERRED) and point the test launcher at it.
3. JDK 27 for test workers: **UNVERIFIED**. Do not rely on it.

---

## 7. Emulator and device matrix

### 7.1 AVDs to create later, from the installed image only

Image: `system-images;android-35;google_apis;arm64-v8a` (rev 9, OBSERVED installed). The installed emulator 36.5.11
meets the image's requirement of ≥ 33.1.24 (OBSERVED). Names are JOVRA-prefixed so they never collide with
`OlamyPixel`.

| AVD (proposed) | Device profile | Window it gives (dp) | Approximates | Purpose |
|---|---|---|---|---|
| `jovra_phone_p9_api35` | `pixel_9` | 411 × 923 | Pixel 10-class phone (Pixel 10 profile absent) | Compact portrait/landscape, five destinations, capture fixture camera, Maestro flows |
| `jovra_fold_p9pf_api35` | `pixel_9_pro_fold` | outer ≈ 443 × 994; inner ≈ 852 × 883; postures closed/half/flat | Pixel 10 Pro Fold: the brief lists outer 1080 × 2364 and inner 2076 × 2152. The inner panel matches this profile exactly; the outer differs by 60 px of height | Outer↔inner continuity, tabletop posture, hinge-separated panes, state restoration |
| `jovra_tablet_ptab_api35` | `pixel_tablet` | 1280 × 800 | Android tablets | Expanded three-pane lesson/editor workspaces, split screen, keyboard |
| `jovra_compact360_api35` | base `medium_phone`, then `hw.lcd.width=1080`, `hw.lcd.height=2340`, `hw.lcd.density=480` in its `config.ini` | 360 × 780 | Smallest supported compact phone; Galaxy S26-class shape (Samsung firmware and One UI not emulated) | Clipping, large font, 48 dp target checks |

Commands for the agent that runs the matrix later (**not run here**):

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
SDK=~/Library/Android/sdk
$SDK/cmdline-tools/latest/bin/avdmanager create avd -n jovra_phone_p9_api35 \
  -k "system-images;android-35;google_apis;arm64-v8a" -d pixel_9
# then in ~/.android/avd/jovra_phone_p9_api35.avd/config.ini:
#   disk.dataPartition.size=4G   fastboot.forceColdBoot=yes   hw.ramSize=4096
$SDK/emulator/emulator -avd jovra_phone_p9_api35 -no-snapshot -no-boot-anim \
  -camera-back videofile:<abs path to synthetic court mp4>
```

Width checks at 393 and 412 dp (brief) need no extra AVDs. Run `adb shell wm density <n>` on the phone AVD and reset
afterwards. Label those runs "density override", not a device. The `resizable` profile can stand in for the phone,
fold and tablet in **one** AVD when disk is short. Its evidence must be labelled "resizable emulator mode", and the
named-profile runs above remain the Native UI gate evidence.

### 7.2 What the API 35 image cannot show (INFERRED, important)

Android 16 (API 36) ignores app orientation and resizability restrictions at sw ≥ 600 dp for apps targeting 36
(feasibility §14). That is **runtime** behaviour of an API 36 system, so the installed API 35 image does not
exercise it. Pixel 10-class devices ship Android 16. Gate **G-IMG36**: `system-images;android-36;google_apis;arm64-v8a`
(zip 1,873 MB; about 4 GB unpacked, INFERRED from the installed 35 image's 1,779 MB zip → 3.8 GB) before claiming
large-screen behaviour on Android 16.

### 7.3 Wear OS (gated: no Wear image is installed)

| Item | Value |
|---|---|
| Package to install at gate **G-WEARIMG** | `system-images;android-36;android-wear-signed;arm64-v8a`, "Wear OS 6.0 ARM 64 v8a System Image (signed)", rev 1, zip **1,138 MB** (OBSERVED, `sys-img/android-wear/sys-img2-4.xml`). About 2.4 GB unpacked (INFERRED, same ratio as above) |
| Alternatives | `android-36.1;android-wear-signed` (Wear OS 6.1, 1,259 MB), `android-37.0;android-wear-signed` (Wear OS 7.0, 1,257 MB), `android-33;android-wear` (Wear OS 4, 1,063 MB) for minSdk-side checks |
| Why Wear OS 6 | Galaxy Watch Ultra (2025) ships Wear OS 6 / One UI 8 Watch, with a 1.5" 480 × 480 round panel (secondary sources: GSMArena, Vodafone device guides; UNVERIFIED against Samsung). It matches the compileSdk 36 lane |
| AVDs | `jovra_wear_xlround_api36` (`wearos_xl_round`, 480 × 480, Galaxy Watch Ultra panel approximation), `jovra_wear_smallround_api36` (`wearos_small_round`, 384 × 384, small watches), plus one `wearos_rect` run for shape sanity. The Apple Watch (rectangular) is a watchOS concern, not this matrix |
| Pairing gate **G-WEARPAIR** | The Wear OS emulator pairing assistant needs a phone on API 30+ **with the Google Play Store and a companion app** (OBSERVED, developer.android.com "connect-phone"). The installed phone image is `google_apis` without Play, so phone↔watch Data Layer tests on emulators need `system-images;android-35;google_apis_playstore;arm64-v8a` (zip 1,789 MB) or the API 36 Play image (1,887 MB). Pairing also needs a Google account signed in on the emulator. **Jon does that step; agents do not enter credentials** |
| Without pairing | Wear UI can still be built, screenshotted and Roborazzi-tested against a fake `DataClient`. Bridge behaviour is then "unverified on transport" |

### 7.4 Named hardware the matrix only approximates

| Target | Closest profile | What is not emulated |
|---|---|---|
| Pixel 10 | `pixel_9` | Tensor G5 camera stack, real 60 fps support, thermals |
| Pixel 10 Pro Fold | `pixel_9_pro_fold` (inner exact; outer ≈ 60 px taller) | Real hinge sensor timing, camera continuity across fold |
| Galaxy S26 / S26+ / Ultra | `jovra_compact360` + `pixel_9_pro_xl` | One UI, Samsung camera HAL, DeX, Samsung density defaults |
| Android tablets | `pixel_tablet`, `medium_tablet` | OEM multi-window variations |
| Galaxy Watch Ultra | `wearos_xl_round` on Wear OS 6 | One UI Watch, Samsung Health, the physical bezel/rotary feel |

These approximations are layout tests, never device validation (adaptive skill). Device gates: physical Pixel
(Jon has one, per the founder prompt) for capture/60 fps/thermal/durability, and a physical Galaxy Watch for
Data Layer timing.

### 7.5 16 KB pages

Gate **G-16K** before any build ships native libraries (ML Kit, MediaPipe): `zipalign -c -P 16 -v 4` on the APK plus
a run on a `_ps16k` image (`system-images;android-35;google_apis_ps16k;arm64-v8a`, zip 1,779 MB, OBSERVED listing).
Play blocks unaligned updates from 2027-02-01 (feasibility §14).

---

## 8. Disk budget (14 GiB free today)

| Item | Estimate | Basis |
|---|---|---|
| New Gradle distribution | **0** in Lane A (9.3.1 already present). About 145 MB per new version | OBSERVED dist sizes |
| Per-Gradle-version cache | 2.5–3.8 GB per version here (`caches/9.3.1` 2.5 GB, `caches/8.14.3` 3.8 GB), mostly transforms. JOVRA's first build adds roughly **1.5–2.5 GB** under `caches/9.3.1` | OBSERVED sizes; increment INFERRED |
| New artifacts in `modules-2` | about **0.8–1.5 GB** (Compose, CameraX, Media3, Play services, Robolectric) | INFERRED |
| Robolectric `android-all-instrumented` | about **0.2–0.3 GB per SDK level** used | INFERRED |
| Build outputs `android/**/build` | about **1–2 GB** for debug + unit tests + Roborazzi outputs across ~20 modules | INFERRED. Delete with `./gradlew clean` at the end of a ticket, matching the iOS `.derivedData` rule |
| **First full build, total** | **about 3.5–6 GB** | Sum |
| One phone AVD (cold boot, no snapshots, 4 GB data cap) | **about 1.5–4 GB**, growing with media | The Olamy AVD reached 7.3 GB with quick-boot snapshots (2.0 GB) and a 6 GB data partition (OBSERVED). Capping data and disabling snapshots is what keeps ours smaller (INFERRED) |
| Wear OS 6 image + 1 Wear AVD | about 2.4 GB + 1–2 GB | INFERRED from the zip size |
| Play Store phone image (pairing) | about 3.8 GB + AVD | INFERRED |
| API 36 phone image | about 4 GB | INFERRED |
| android-37 platform (Lane B) | about 0.14 GB | OBSERVED zip 67 MB; unpacked like android-36's 134 MB |

**Plan under 14 GiB:** Lane A build (about 5 GB) plus **one** JOVRA phone AVD (about 3 GB) leaves about 6 GB, which
is the minimum safe headroom on macOS (INFERRED). Fold and tablet AVDs are created **sequentially** and deleted
after their evidence is captured. Since `avdmanager delete avd` removes only JOVRA's own AVDs, that is allowed. The
alternative is the single `resizable` AVD. The Wear image, Play image and API 36 image need gate **G-DISK**: at least
**25 GiB free**, or Jon's approval to reclaim space, before any of them is installed. Nobody clears other projects'
caches to get there.

---

## 9. Gates (each is a check that can fail; report separately)

| Gate | Pass condition | Blocks |
|---|---|---|
| **G-RESOLVE** | `./gradlew -p android help :app:dependencies :app:checkDebugAarMetadata :wear:checkDebugAarMetadata` succeeds on compileSdk 36 with the §5.4 catalog; built-in Kotlin + KGP 2.4.20 + compose plugin accepted by AGP 9.1.1 | Everything Android |
| **G-CORE** | `:core:test` passes every `spec/fixtures` case, including CSV byte-for-byte; `:studio-core:test` passes the `spec/studio/fixtures` vectors | Claiming Android conformance |
| **G-JDK21** | JDK 21 available locally, or CI-only SDK 36 Robolectric accepted | Local SDK 36 Robolectric runs |
| **G-SDK37** | Jon approves `sdkmanager "platforms;android-37.0"` (67 MB zip) | Lane B |
| **G-TARGET37** | Room transport re-verified with `ACCESS_LOCAL_NETWORK` / NSD picker before targetSdk 37 | Raising targetSdk |
| **G-DISK** | ≥ 25 GiB free, or approved reclaim of JOVRA-owned space only | G-IMG36, G-WEARIMG, G-WEARPAIR images |
| **G-IMG36** | `system-images;android-36;google_apis;arm64-v8a` installed | Android 16 large-screen behaviour claims |
| **G-WEARIMG** | `system-images;android-36;android-wear-signed;arm64-v8a` installed | Any Wear emulator evidence |
| **G-WEARPAIR** | Play phone image + companion app + Jon signs in; paired assistant succeeds | Data Layer emulator evidence |
| **G-16K** | `zipalign -c -P 16` clean and app runs on a `_ps16k` image | Shipping pose/native libs |
| **Native UI** (brief) | Named installed profile, build, screenshots, TalkBack labels, font scale, state restoration across fold/rotate/process death | Saying "runs on fold/tablet" |
| **Hardware** | Physical Pixel and Galaxy Watch per the adaptive acceptance matrix | Capture durability, fps, thermal, transport timing |

---

## 10. Reconciliation notes for other documents (no edits made)

- `docs/research/technical-feasibility.md` §14 lists `compileSdk 37`, Compose BOM 2026.09.00 and Navigation 3 1.2.0.
  These are correct as current stable but are **Lane B** on this machine (§0.2). Its CameraX 1.6.2, Media3 1.11.1,
  WorkManager 2.12, ML Kit 18.0.0-beta5 and `play-services-auth` 22.0.0 match what this note observed in Maven
  metadata.
- `docs/DEVELOPING.md` is iOS-only. An Android section (JAVA_HOME, the `-p android` Gradle invocation, AVD names,
  `./gradlew clean` hygiene) belongs in the first Android ticket.
- ADR-0001 says Android follows "after the iOS capture gates pass", and the founder has now approved Android
  directly (adaptive v3 handoff). An ADR amendment or a new ADR should record the Android start condition and the
  Lane A/B pins. That is the ADR owner's call, not this note's.
- Today `scripts/spec/validate.py` walks `spec/fixtures/**`. Android's conformance runner must apply the same
  "unknown kind fails" rule so the two stay in lockstep.

---

## Sources

Local (OBSERVED, 2026-10-07): `~/Library/Android/sdk/**/source.properties`; `~/.android/avd/OlamyPixel.avd/config.ini`;
`avdmanager list device`; `sdklib.core.jar` `com/android/sdklib/devices/{nexus,devices,wear}.xml`; `du`/`df`;
`/opt/homebrew/opt/openjdk@17` `java -version`; `maestro --version`; `~/.gradle/wrapper/dists`, `~/.gradle/caches`.

Repo: `CLAUDE.md`; `docs/adr/0001`, `0002`, `0006`, `0010`, `0012`, `0014`, `0017`, `0022`;
`docs/handoff/JON-ORIGINAL-PROMPT.md`; `docs/handoff/adaptive-v3/{CLAUDE-ADAPTIVE-WATCH-PROMPT,START-HERE}.md`;
`.claude/skills/jovra-adaptive-native-ui/SKILL.md`; `.claude/skills/jovra-watch-companion/SKILL.md`;
`design-reference/adaptive/brief/{platform-and-device-plan,session-connectivity,acceptance-matrix,visual-review}.md`,
`watch-snapshot.sample.json`; `spec/README.md`; `spec/studio/README.md`; `docs/research/technical-feasibility.md`
§13–14, §18; `docs/research/studio/multicam-sync.md` §0, §2, §3; `docs/DEVELOPING.md`; `.github/workflows/ci.yml`.

Primary web (accessed 2026-10-07):
- Google Maven metadata and AAR `aar-metadata.properties`: `https://dl.google.com/android/maven2/<group>/<artifact>/maven-metadata.xml` and `.../<version>/<artifact>-<version>.aar` (every row of §3.2)
- Maven Central metadata for Kotlin, KSP, kotlinx, Robolectric, Roborazzi, Horologist, JUnit, OkHttp, Turbine: `https://repo1.maven.org/maven2/...`
- [AGP 9.4 release notes](https://developer.android.com/build/releases/gradle-plugin) (max API 37, Gradle 9.6.0, build-tools 36.0.0, JDK 17)
- [AGP 9.3](https://developer.android.com/build/releases/past-releases/agp-9-3-0-release-notes) and [9.2](https://developer.android.com/build/releases/past-releases/agp-9-2-0-release-notes) release notes
- [About AGP: AGP ↔ Gradle and API-level tables](https://developer.android.com/build/releases/about-agp)
- [AGP 9.0 release notes: runtime dependency on KGP 2.2.10](https://developer.android.com/build/releases/past-releases/agp-9-0-0-release-notes)
- [Migrate to built-in Kotlin](https://developer.android.com/build/migrate-to-built-in-kotlin)
- [AGP, D8 and R8 Kotlin support](https://developer.android.com/build/kotlin-support)
- [Kotlin Gradle plugin compatibility table](https://kotlinlang.org/docs/gradle-configure-project.html)
- [Compose BOM mapping](https://developer.android.com/develop/ui/compose/bom/bom-mapping) and BOM POM `compose-bom-2026.06.01.pom`
- [Navigation 3 releases](https://developer.android.com/jetpack/androidx/releases/navigation3)
- [Material 3 adaptive releases](https://developer.android.com/jetpack/androidx/releases/compose-material3-adaptive)
- [Connect a Wear OS emulator to a phone](https://developer.android.com/training/wearables/get-started/connect-phone)
- SDK repository XML: `https://dl.google.com/android/repository/repository2-4.xml`, `sys-img/android-wear/sys-img2-4.xml`, `sys-img/google_apis/sys-img2-4.xml`, `sys-img/google_apis_playstore/sys-img2-4.xml`
- [Robolectric releases](https://github.com/robolectric/robolectric/releases) (4.16: JDK 21 for SDK 36; 4.17: SDK 37) and [getting started](https://robolectric.org/getting-started/)
- [Roborazzi releases](https://github.com/takahirom/roborazzi/releases) (1.76.0, 2026-09-29)
- [GitHub runner image, Ubuntu 24.04](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md)
- [Gradle versions service](https://services.gradle.org/versions/current)
- Galaxy Watch Ultra (2025) panel and OS, secondary sources: [GSMArena](https://m.gsmarena.com/samsung_galaxy_watch_ultra-13127.php), [Vodafone device guide](https://deviceguides.vodafone.co.uk/samsung/galaxy-watch-ultra-2025-wear-os-6/specifications/)
