# Continue JOVRA Studio: Android, adaptive screens and native watches

Keep the Studio work already underway. This is the next founder-directed extension, not a replacement or a demand to abandon the current ticket. Read `docs/handoff/adaptive-v3/START-HERE.md`, the two included skills and the briefs under `design-reference/adaptive/brief/`. Preserve current repository rules, glossary, point-event scoring, metric provenance, native platform direction and useful reviewed work.

The original Studio references 21–40 contained sixteen iOS phone views and four larger workspaces; none was an Android implementation. New references 41–60 are their native Android counterparts, including four fold/tablet workspaces. References 61–65 are watchOS, 66–70 are Wear OS, and 71–72 are expanded iOS foldable layout studies. Photography, measurements, QR patterns and device status are Sample. These are generated design targets, not emulator captures or verified device capabilities.

## Native and adaptive

Use Kotlin/Jetpack Compose for Android phone/tablet/foldable and Compose for Wear OS for the Galaxy Watch companion. Use SwiftUI for iPhone/iPad and watchOS for Apple Watch. Share JSON contracts and golden fixtures, not UI source. Keep Home, Sessions, Record, Insights and Profile as the five phone destinations, with Studio entry points already chosen.

Android is its own native experience: Material app bars, navigation-bar selected pills, adaptive rails, bottom sheets, system photo/file pickers, permissions, insets, accessible controls, gesture/back behaviour and predictive-back support where applicable. Do not turn iOS screenshots into Android by changing only the status bar. Use window size, available height and folding posture/occlusion, not device-brand strings or fixed physical pixel sizes, to select layouts. Expanded replay/sync/lesson/editor panes should have a purpose. Keep content and controls clear of hinges, display cutouts and gesture areas. Compact height can require fewer panes even at a wide width.

Preserve session/project selection, playhead, unsaved notes, draft cuts, command receipts and local capture through resize, rotation, cover↔inner changes and process recreation. Do not promise that camera recording survives a particular hardware/posture transition until tested: retain saved segments and represent interruption explicitly. Changes of display are never permission to duplicate a job, charge, score event or stop recording silently.

Target Pixel 10-class phones, Pixel 10 Pro Fold cover/inner displays, Galaxy S26-class phones and Android tablets. Inspect installed SDK/system images and available AVD profiles before naming an emulator. Use measured/custom window profiles when the exact branded skin is absent; report that accurately. Android emulator UI, physical camera capture and six-device field evidence are separate gates. Do not install SDK images or clear caches blindly while other projects are testing.

Apple announced iPhone Duo in September 2026, with retail availability stated for October 23. As of this handoff (October 7), treat its hardware and simulator availability as unverified here. Build adaptable iOS windows now; inspect real supported SDK/device APIs before assuming a hinge signal or importing Android folding APIs. Existing iPad workspaces do not automatically prove a good foldable iPhone layout.

## Native watch companion: useful in a glance

Start with five surfaces on each watch:

1. Camera health: actual last-acknowledged recording states and per-camera elapsed duration, last-heard age, low-storage/battery/thermal flags and an explicit Unknown/stale condition. Show summary counts that explain their basis. This is a status panel, not six video feeds.
2. Score: authoritative point-derived score, server when known, manual point buttons, undo/correction, revision and pending/offline state. Opponent input cannot silently overwrite the score. A score is only as correct as its point log; displaying it on a watch does not determine the winner automatically.
3. Latest serve: source-linked phone-produced result, units, provenance, time/point and range when available. The sample 74 mph is layout data. Wrist movement is not ball speed. Current v1 has no live speed on capture; preserve that while an optional later low-latency capability is benchmarked. If unsupported, uncalibrated or delayed, show unavailable/waiting or the last known timestamped result.
4. Mark for review: bookmark a point/serve or uncertain bounce with an acknowledged receipt, then review evidence on the phone. No automatic definitive In/Out decision. Multiple cameras are not proof of officiating accuracy.
5. Connection alert: tell the user a camera or paired phone is stale, when it was heard, and that local recording may continue. Deduplicate/hysteresis alerts and make acknowledgement easy. Do not interrupt a rally with repeated noncritical haptics.

Use watch-specific layouts: short text, large targets, readable bright-sunlight contrast, scroll/rotary navigation and native watch safe regions. Galaxy Watch Ultra has a round display inside its case; keep text inside circular bounds. Apple Watch uses rectangular watchOS layout. Use matched capabilities, not identical geometry. Tiles/complications are optional entry points or snapshots; they are not continuous network monitors. Always-on state is a low-power snapshot with a time stamp, not an always-live promise. Do not create a fake workout session solely to bypass background restrictions. HealthKit/Health Services are optional, separately consented training features.

## Pairing and communication

Implement phone-camera pairing before watch control. QR/code joins a specific JOVRA session with an expiring scoped invitation, not an OS Bluetooth pairing or access to every original video. A host assigns primary/optional roles; each participant consents, saves independently and reports actual capture acknowledgements. The host aggregates metadata; one failed host/network does not erase or stop other local captures. A QR start button is coarse coordination, not frame synchronization.

Read `design-reference/adaptive/brief/session-connectivity.md` for the proposed protocol. Separate cross-platform phone-session transport from the paired-watch transport. Use Apple WatchConnectivity for the watchOS↔paired iPhone bridge and Wearable Data Layer for Wear OS↔paired Android. Those APIs are not a native cross-OS watch pairing system. A Galaxy Watch can see an iPhone camera in the same mixed session by receiving the aggregate through its Android companion; an Apple Watch can see Android camera status through its iPhone companion. This depends on working session transport, not direct watch-to-every-camera connections.

Use schema/versioned envelopes with session ID, host epoch, per-device capture instance/segment and sequence, receiver-owned freshness, event revision, capabilities and explicit command receipts. Reject old/out-of-order/replayed messages. Use snapshot channels for latest state and acknowledged idempotent commands for actions. Background delivery/reachability is not guaranteed. Retain a visible last-updated value and never animate a remote duration as though it were confirmed fresh.

Permissions matter: scoring/viewer, marker and capture-controller roles differ. Watch pairing does not grant a stop-all privilege. Start requests can require a foreground unlocked phone and OS permission; a command is Pending until actual per-device acknowledgement. Stop one vs request all-stop must be explicit, deliberate and confirmed; preserve failed/unknown results. No automatic remote stop on disconnect. Score commands include base revision and command ID; conflicting stale writes need reconciliation, and offline actions remain pending rather than an authoritative silent update.

## Analysis and line-review roadmap

Keep Manual / Estimated / Reviewed / Validated labels and the capability registry. Four/six views can improve evidence coverage, but 3D position, serve speed and bounce/line classification need measured clock alignment, lens/court calibration, occlusion handling, representative annotated footage and uncertainty/latency tests. A planar court homography does not measure an airborne ball’s 3D velocity.

Begin with source-linked review requests and manual call notes. If later proposing automated hints, add a scoped ADR and benchmark plan, false-call/abstention criteria and a user-visible “Review needed” fallback before implementing any In/Out badge. Do not turn hints into automatic score changes. No officiating-grade, injury, spin or professional-accuracy promise. Preserve the current v1 prohibition on line calls while the later research capability remains separate.

## Sequence the work

A0: reconcile the addendum and schema/fixture contracts without blocking the existing Studio film slice.

A1: Android compact Studio UI and adaptive state restoration; render fixtures on available phone, foldable and tablet emulators.

A2: local cross-platform two-phone room, invitations, independent capture, acknowledged/stale health, disconnect recovery; real devices required for camera/background/thermal evidence.

A3: watchOS + Wear OS native read-only health, point bookmarks and timestamped score snapshots using native companion bridges; then add acknowledged manual score/undo commands and optional safe camera controls.

A4: six-device health/endurance and mixed-OS field tests; keep upload and frame synchronization as separate processes. Do not claim UI tests validate wireless timing.

A5: later benchmarked low-latency metric delivery, review-only bounce hints, richer complications/training integration and commercial cloud options after their own gates.

Use the existing ticket/PR skills and current merge policy. Do not overwrite other agents’ work or the installed six production skills. The two new skills can be loaded directly or added under their own names. Screens 41–72 belong in the reference manifest and implementation state map, not baked into app assets as functioning UI.

Acceptance evidence must include fold/rotation/split-screen continuity, accessibility, expired/insecure invites, stale and out-of-order snapshots, reconnect/restart, duplicate commands, score conflict/undo, denied permissions, companion app suspension, different watch shapes and real camera capture. Report emulator, real phone, real watch, field network, analysis benchmark and backend activation separately. Continue authorized local work, and request real device/media access only at the corresponding gate.
