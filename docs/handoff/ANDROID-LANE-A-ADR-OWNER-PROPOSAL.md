# Android Lane A ADR proposal for owner review

**Unsigned proposal prepared 2026-11-09.** The ADR owner must review, ratify and merge any adopted
wording into the ADRs. This handoff records the evidence and proposed text. Both ADR tickets stay
open, and A01 stays behind the two owner decisions. [Lane A pins #375](https://github.com/Navigata1/jovra/issues/375) ·
[ADR-0001 header #376](https://github.com/Navigata1/jovra/issues/376) · [A01 #179](https://github.com/Navigata1/jovra/issues/179)

## Proposed ADR-0001 header for #376

Add this line directly below the title of ADR-0001. Keep the rest of the ADR as written.

> Status: amended by ADR-0024 (Android start condition only)

[ADR-0001](../adr/0001-native-per-platform-shared-contracts.md) ·
[ADR-0024](../adr/0024-android-stack-and-module-layout.md)

## Proposed dated ADR-0024 addendum for #375

**Android start and Lane A verification** · Use the ADR owner's actual ratification date.

The founder approved proceeding with the Adaptive/Watch v3 handoff on 2026-10-07. Native Android
work proceeds in parallel with iOS. Both apps share contracts and fixtures. Android capture
durability, 60 fps, thermals and field behavior still require physical Android device evidence.
[Founder handoff, decisions addendum item 4](JON-ORIGINAL-PROMPT.md#decisions-addendum-2026-10-07-third-message)

G-RESOLVE succeeded on 2026-10-11 for the A01 Lane A configuration. This supersedes the earlier
verification status of the selected Lane A configuration. The complete version catalog at the
reviewed A01 head records the remaining pins. G-RESOLVE covers the dependencies exercised by its
tasks. Later Android feature, emulator and device gates remain separate.
[G-RESOLVE result](https://github.com/Navigata1/jovra/blob/4269aa29026d6b3c06b8627425f38d1a7056a2a3/evidence/android/a01-android-build-foundation-lane-a/02-g-resolve.txt) ·
[Lane A catalog](https://github.com/Navigata1/jovra/blob/4269aa29026d6b3c06b8627425f38d1a7056a2a3/android/gradle/libs.versions.toml)

| Area | Lane A |
| --- | --- |
| Build | Gradle 9.3.1 wrapper with `distributionSha256Sum`, AGP 9.1.1 with built-in Kotlin, KGP 2.4.20, Compose and serialization compiler plugins 2.4.20, JDK 17 |
| Phone and tablet SDK | compileSdk 36, targetSdk 36, minSdk 29 |
| Wear OS SDK | compileSdk 36, targetSdk 36, minSdk 30 |
| UI and core | Compose BOM 2026.06.01, Navigation 3 1.1.7, lifecycle 2.10.0, core-ktx 1.18.0 |

Navigation 3 1.1.7 resolved successfully. The Navigation Compose 2.9.8 fallback was unnecessary.
The wrapper pins the distribution hash
`b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06`.
[Wrapper properties](https://github.com/Navigata1/jovra/blob/4269aa29026d6b3c06b8627425f38d1a7056a2a3/android/gradle/wrapper/gradle-wrapper.properties)

The first AAR metadata check on compileSdk 36 failed because
`com.squareup.okhttp3:okhttp-android:5.5.0` declares `minCompileSdk=37`.
Lane A therefore pins OkHttp 5.4.0, which declares `minCompileSdk=36` and passed G-RESOLVE.
Lane B moves OkHttp to 5.5.0 with the catalog update and compileSdk 37 after G-SDK37. Raising
targetSdk to 37 requires the separate G-TARGET37 gate because it affects local-network permissions
and the room transport. [Failed first attempt](https://github.com/Navigata1/jovra/blob/4269aa29026d6b3c06b8627425f38d1a7056a2a3/evidence/android/a01-android-build-foundation-lane-a/01-g-resolve-attempt1-okhttp-5.5.0.txt) ·
[Toolchain gates](../research/android/toolchain-and-devices.md#9-gates-each-is-a-check-that-can-fail-report-separately)

## Evidence for owner review

The exact A01 draft head `4269aa29026d6b3c06b8627425f38d1a7056a2a3` carries the Lane A
catalog and evidence. Its hosted `android-core` job passed on 2026-11-08. The branch's
retained round-seven record reports 35 tests passing, successful phone and Wear debug APK
assembly, and 20 modules passing boundary checks. It records no emulator or physical-device
run. A01 acceptance on main remains pending.
[A01 draft #378](https://github.com/Navigata1/jovra/pull/378) ·
[Hosted android-core](https://github.com/Navigata1/jovra/actions/runs/42511733529/job/128826060799) ·
[Round-seven evidence](https://github.com/Navigata1/jovra/blob/4269aa29026d6b3c06b8627425f38d1a7056a2a3/evidence/android/a01-android-build-foundation-lane-a/18-round7-2026-11-08.txt)

If the designated owner adopts the wording, merge the ADR changes to main and link both
merged decisions on #179 before reconsidering the A01 draft. Keep the later Drive
authorization amendment on its separate A49 path. [Drive ADR #377](https://github.com/Navigata1/jovra/issues/377)
