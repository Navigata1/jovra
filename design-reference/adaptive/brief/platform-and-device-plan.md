# Native platform and device evidence plan

Checked official sources on 2026-10-07. New PNGs are generated references, not screenshots of an installed native app. Exact emulator profiles, system images and physical devices were not booted or tested for this addendum.

## Reference allocation

| Range | Platform/layout | Count |
|---|---|---:|
| 01–20 | Original iOS/product references | 20 |
| 21–40 | Prior Studio: sixteen iOS phone and four expanded workspaces | 20 |
| 41–60 | Android: sixteen phone and four expanded fold/tablet views | 20 |
| 61–65 | watchOS, rectangular watch layout | 5 |
| 66–70 | Wear OS, circular display-safe layout | 5 |
| 71–72 | Expanded iOS foldable layout studies | 2 |
| Total | Cohesive reference collection | 72 |

## Android and foldables

Use current stable Kotlin, Compose and Compose for Wear OS supported by the actual repository toolchain. The native UI uses Android system pickers and permission flows, Material navigation and app bars, native back handling, and window-based adaptive layouts. Choose layouts using available window size and folding posture/occlusion, not device-name tests. Jetpack WindowManager/adaptive APIs must be checked against the project's versions. A rail, list/detail workspace or supporting pane should improve the task rather than simply enlarge phone cards. Compact height may suppress extra panes even in a wide window.

Pixel 10 Pro Fold's official spec lists a 6.4-inch outer display (1080×2364) and an 8-inch inner display (2076×2152). Those pixel dimensions describe aspect targets, not logical density-independent app widths. Pixel 10-class and Galaxy S26-class phone profiles are compact targets; Samsung's official S26 page lists 6.3/6.7/6.9-inch family sizes. An emulator with a similarly shaped custom profile is not Samsung firmware or proof of One UI behaviour. Inspect installed AVD names and images before claiming any named model was tested.

Android tests: compact portrait at representative 360/393/412 dp widths; landscape/compact height; resized tablet windows; outer↔inner fold transition; hinge/occlusion/tabletop where supported; split screen; keyboard; font scaling; talkback; system back; process recreation. Use actual WindowSizeClass values from the SDK rather than hardcoding these example viewport widths into app routing. Tablet references include both a three-pane lesson workspace and a foldable edit/replay layout.

## iOS adaptive and watchOS

SwiftUI targets iPhone/iPad/watchOS. Apple’s September 9 announcement calls its foldable iPhone Duo, with 5.4-inch outer and 7.6-inch expanded screens and retail availability stated for October 23. As of October 7 this handoff does not verify an available simulator profile or hardware. References 71–72 therefore study expanded iOS tasks without claiming a tested hinge API or hardware integration. Inspect the installed Xcode/SDK and real supported size/lifecycle APIs before targeting model-specific behaviour.

Keep playback position, project/angle choice and drafts stable through rotation, resized windows and cover/expanded transitions. Capture continuity is an independent hardware test: save recoverable media segments and show explicit interruption if the platform interrupts capture. Never make a resize duplicate a score, job or purchase.

## Watches

Apple Watch Ultra references use rectangular watchOS surfaces. Galaxy Watch Ultra references respect the round display even though the exterior case is more square. Use SwiftUI watchOS and Compose for Wear OS controls, rotary/scroll behaviour and screen-safe regions. Test both smaller and larger supported watches where possible; a large Ultra-only illustration is insufficient for all supported watches. Provide shape-safe text, bright-light contrast, VoiceOver/TalkBack labels, large targets, reduced-motion behaviour and power-conscious always-on snapshots. Do not bake a rendered watch image into functioning app UI.

The watch bridge is OS-specific. WatchConnectivity serves the paired Apple ecosystem; Wearable Data Layer serves Wear OS and Android. Neither is the cross-platform camera-room transport. A mixed camera room can forward aggregate metadata through the watch's compatible companion phone. Status monitoring, manually entered score, point markers and connection alerts are the first slice. Serve speed is a later phone-produced capability and uncertain bounce review begins with bookmarks.

## Separate acceptance gates

| Gate | Evidence required | What a mockup cannot prove |
|---|---|---|
| Design | All 32 new references, mappings, labelled samples | Running UI or measurements |
| Native UI | Named installed SDK/profile, build, screenshots, accessibility and state restoration | Wireless timing/camera durability |
| Two-phone room | Real capture, permission handling, QR expiry, independent recording, disconnect recovery | Six-camera endurance |
| Watch | Real paired companion, suspension, haptics, retries, stale state and score receipts | Constant background delivery |
| Six cameras | Mixed-OS local network, heat/storage/battery/endurance and loss recovery | Ground-truth analysis accuracy |
| Metric | Annotated footage, calibration, clock error, latency/error/abstention benchmark | Officiating-grade calls |
| Cloud | Tenant authorization, explicit spend, storage/retention, render job receipts | Live backend from a sample screen |

Do not clear caches, install images, terminate emulators or change another project's environment merely to run this matrix. Inventory first and coordinate resource use with the existing Studio work.

## Official sources

- [Compose adaptive apps](https://developer.android.com/develop/ui/compose/build-adaptive-apps)
- [Adaptive canonical layouts](https://developer.android.com/develop/adaptive-apps/guides/canonical-layouts)
- [Window size classes](https://developer.android.com/develop/ui/compose/layouts/adaptive/use-window-size-classes)
- [Pixel 10 Pro Fold specifications](https://store.google.com/gb/product/pixel_10_pro_fold_specs?hl=en-GB)
- [Samsung Galaxy S26 family](https://www.samsung.com/us/smartphones/galaxy-s26/)
- [Apple iPhone Duo announcement](https://www.apple.com/ca/newsroom/2026/09/apple-unveils-iphone-duo/)
- [Apple WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity/wcsession)
- [Wear OS Data Layer](https://developer.android.com/training/wearables/data/overview)
- [Wear OS screen shape/layout guidance](https://developer.android.com/training/wearables/views/layouts)

These sources inform a proposed implementation and current device shapes. Version-specific APIs and SDK availability must be verified during the build.
