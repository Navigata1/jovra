# A02 launcher and adaptive shell tracer

[Issue #180](https://github.com/Navigata1/jovra/issues/180) remains open. This local branch is stacked on draft [#378](https://github.com/Navigata1/jovra/pull/378) at `4269aa29026d6b3c06b8627425f38d1a7056a2a3`. The tested source is `1de5441933bc1cf2ad7e1fa85263c22979b01e93`. A01 and its ADR owner decisions remain separate.

The launcher opens a lightweight edge-to-edge JOVRA shell with a system light or dark palette and saveable tab selection. It uses the installed Lane A Compose dependencies and chooses the navigation bar or rail from the Android window width class. All five destinations are labelled and show placeholder content. The app manifest adds the launcher activity and theme. Full manifest permissions and services, Wear, high contrast, the Court Arc and adaptive launcher icon, resource lint, goldens, and release alignment remain open.

## Verification

The public launcher/Compose tests compiled against A01 and failed at the missing `MainActivity`. On the frozen implementation, both SDK 34 Robolectric tests passed. They check five labelled clickable destinations, selected state and corresponding content, and actual control geometry at 360 and 840 dp. They are local layout tests.

The frozen Gradle run built the phone debug APK and passed 18 Android unit tests, eight JVM tests and the 20-module boundary check. Android Build Tools 36 verified the APK v2 signature and found the exported launcher activity. The APK is `52602091` bytes with SHA-256 `296502c892943cf5c0dec6583ed4fcde6ba99c5a7fccba2bd05b93f637f4cfa0`. It is retained on the SSD in `/Volumes/JovraA02-F46A6DA7/jv/android/app/build/outputs/apk/debug/app-debug.apk`.

```sh
android/gradlew -p android --offline --no-daemon --max-workers=1 --no-parallel \
  testDebugUnitTest :app:assembleDebug checkModuleBoundaries \
  :core:test :studio-core:test :room-protocol:test :testing:test
```

The SSD workspace used a dedicated 24 GiB APFS sparse bundle and its own Gradle cache, debug Android user directory and temporary paths. The first attempt stopped at the proactive 9 GiB buffer before the compiler ran. After free space recovered, the lowest sampled internal free space was 16.65 GiB and the run finished with 17 GiB free. Build outputs are retained for review. [Receipts](results.txt) summarize the local logs, which are in `/Volumes/JovraA02-F46A6DA7/receipts`.

## Pixel launch and navigation

The APK with the SHA-256 above was tested on a Pixel 6 Pro running Android API 37. The test operator verified that
`com.islanddevcrew.jovra` was absent and used an explicit no-replacement install (`-R`) for the selected Android user.
Android reported `Status: ok` when launching `MainActivity`. Device UI taps opened Home, Sessions, Record, Insights
and Profile, and the expected placeholder title appeared after each tap.

This verifies install, launch and five-destination navigation on one phone. The 360 and 840 dp bar and rail results
come from the separate Robolectric tests. Recording, analysis, adaptive hardware, full accessibility, Wear,
emulator and hosted checks remain open. [A01](https://github.com/Navigata1/jovra/issues/179) and
[A02](https://github.com/Navigata1/jovra/issues/180) remain open, with owner ADR decisions
[#375](https://github.com/Navigata1/jovra/issues/375) and [#376](https://github.com/Navigata1/jovra/issues/376)
still pending.
