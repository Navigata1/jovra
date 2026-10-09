# Native process-death control

App source: unchanged T07 PR head f42a88b86793f44db465f26da32ad4594530cafe integrated with main 15bc44a60c61d81b1abf8e4abae30093c71e2061 at 41e8cc7c70f4d0a0128d20ac9ce15ecd6b5c2151. Later review-only test rename does not alter app source. No manifest or restoration workaround was retained.

Owned simulator: JOVRA-Codex-T07 / 4265ADFD-39A3-4E71-8482-1945DDB5F899 / iPhone 17 Pro / iOS 26.5.

1. Build unchanged app with xcodebuild build, install fresh with simctl on owned simulator. No XCTest app launch.
2. simctl openurl jovra://record/doubles. Simulator native Open confirmation was accepted using cua_repl in the verified JOVRA-Codex-T07 window. AX and screenshot confirmed Capture, Session kind: Doubles match.
3. Launch com.apple.mobilesafari on the same simulator, wait 3 seconds for backgrounding. No app-switcher discard action.
4. Resolve exactly the owned launchctl UIKitApplication:com.islanddevcrew.jovra label, assert one process, SIGKILL PID 4815.
5. simctl launch com.islanddevcrew.jovra, new PID 10347, no XCTest launch or activate. Screenshot native-after-relaunch.png shows Capture and Doubles payload preserved.

Result: PASS. Read native-only-process-death.log and the before/background/after PNGs. Native state restoration is operational on this simulator; the initial apparent app defect was refuted.

XCTest contrast control: when the initial app launch itself is performed by XCUIApplication, restoration loses state after terminate or external SIGKILL, even when the subsequent launch is native simctl. Both Data and String scene-storage controls remained absent. This is an observed harness difference; its private platform mechanism was not established. The rb-legacy launchctl label is not evidence that the app lacks scene lifecycle. Empty/explicit scene configs, enabling multiple scenes, and an NSUserActivity experiment did not fix harness persistence. All were reverted. One debug watcher failed due to a stale marker/no process; that run is recorded as harness setup error, not app failure.

The committed SceneContinuityUITests checks background/foreground and presenting-tab continuity honestly. It does not claim to test process-death restoration. The temporary host-dependent ProcessDeathProbeUITests.swift.txt is preserved here outside the test target for diagnostic reproducibility. Do not add it to the default suite without a native-start driver and an independent preservation control.

Primary reference for proper testing: https://developer.apple.com/documentation/swiftui/restoring-your-app-s-state-with-swiftui — do not discard the scene through app switcher; suspend, stop process, relaunch. The API also makes no guarantee about persistence timing.
