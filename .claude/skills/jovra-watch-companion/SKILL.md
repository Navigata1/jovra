---
name: jovra-watch-companion
description: Build JOVRA watchOS and Wear OS companions for fresh camera health, event-derived scoring, bookmarks and capability-gated phone metrics with acknowledged commands.
---

# JOVRA watch companion

Read repo-root `docs/handoff/adaptive-v3/CLAUDE-ADAPTIVE-WATCH-PROMPT.md` and `design-reference/adaptive/brief/session-connectivity.md`. When reading the unchanged portable pack, the prompt also resolves as `../../CLAUDE-ADAPTIVE-WATCH-PROMPT.md` from this folder. Keep the referenced handoff docs with any installation. Begin with native paired-phone snapshots, health and bookmark receipts. The watch mirrors the session aggregate; it does not connect independently to every camera or process six videos.

Use WatchConnectivity for watchOS↔iPhone and Wearable Data Layer for Wear OS↔Android. Share a schema but adapt transport/lifecycle. Cross-OS camera status arrives through a mixed-session phone coordinator. Native watch bridges do not directly pair the two ecosystems.

A snapshot binds session/host epoch, event revision, capture instance and source sequence. Freshness adds the phone's camera age to watch-side elapsed time using receiver-owned monotonic clocks. Unbounded queued transit or a lost process baseline makes state Unknown until renewed; arrival alone cannot establish freshness. Cross-device wall clocks are hints. Retain timestamped elapsed values without pretending they advance while no fresh message arrives. Distinguish recording acknowledged, paused/stopped, warning, stale and unknown.

Scores come from accepted point events. Point/undo commands include command ID, base revision, role and explicit receipt. Duplicates apply once; stale revisions conflict; offline commands remain pending. Permission to view is not permission to score or stop all cameras. Capture start/stop depends on actual OS permissions/foreground conditions and per-device acknowledgement.

Make camera health, score, latest supported metric, bookmark/review and connection alert the five initial surfaces. Show source, provenance and age for serve data; wrist motion is not ball speed. Bounce/line review is an evidence marker, not a definitive call or automatic score update. Unknown/calibration/latency states are first-class.

Design a rectangular watchOS experience and a round-safe Wear OS experience. Use short readable content, native scrolling/rotary input, large touch targets and sparse consented haptics. Tiles/complications/always-on screens are low-power snapshots. Never use a fake workout solely for execution privileges. Optional actual training/health data needs separate permission and handling.

Test stale/reordered snapshots, host/capture restarts, disconnects, duplicate commands, score conflicts, ambient mode, denied notifications/permissions, app suspension and unavailable capability fallback. Simulator UI is separate from actual watch/phone transport and court evidence. Output native UI plus protocol receipts and the real measured verification level.
