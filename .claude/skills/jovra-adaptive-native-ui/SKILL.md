---
name: jovra-adaptive-native-ui
description: Design and implement JOVRA native Android and iOS layouts across phones, tablets and foldables while preserving project state and platform conventions.
---

# JOVRA adaptive native UI

Read repo-root `docs/handoff/adaptive-v3/CLAUDE-ADAPTIVE-WATCH-PROMPT.md`, `design-reference/adaptive/brief/platform-and-device-plan.md` and the current app instructions. When kept in the portable pack, the prompt also resolves as `../../CLAUDE-ADAPTIVE-WATCH-PROMPT.md` from this folder. Keep the referenced handoff docs with any installation. Preserve JOVRA’s brand and domain contracts while designing controls natively: SwiftUI on Apple, Kotlin/Compose on Android. Match capabilities and product hierarchy, not pixel-identical controls.

Choose panes from actual window width/height, posture/occlusion and input mode. Use compact sequential flows, expanded list/detail or supporting panes, and a tabletop player above controls when the platform actually supplies that posture. Keep action and touch targets out of a separating hinge. Large diagonal size alone does not imply enough width for three panes.

Preserve selected session, playhead, draft edit and notes, local capture segments and pending command/job IDs across layout transitions and recreation. Test compact→expanded→compact, rotate, split-screen, interruption and process death. A layout change must not resubmit a film job or duplicate a point.

On Android use Material components, adaptive rails/navigation, system pickers, correct back/gesture/inset behaviour and accessible 48dp targets. On Apple preserve native navigation, at least 44-point targets, Dynamic Type and VoiceOver. Large text can require fewer panes. Respect reduced motion and clearly labelled Sample fixtures.

Inspect available SDK/AVD/simulator support before claiming a named hardware profile. Custom window shapes are layout tests, not exact hardware emulation. Current screenshots are references, not runtime evidence. Frame/camera/thermal/hinge continuity needs physical-device validation. Do not assume Android folding APIs exist on iOS; use verified platform capabilities and a generic adaptable layout fallback.

Keep the five phone destinations. Studio workspaces may use rails and contextual tools. Watch UI belongs to the separate watch-companion skill, not a shrunken phone layout. Output the native screen/state mapping, preserved-state contract and measured layout/device verification.
