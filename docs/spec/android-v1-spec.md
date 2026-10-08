# JOVRA Tennis — Android v1 product spec (core parity + Studio phone, fold and tablet)

Status: ready-for-agent for the Android foundation, core parity and Studio S0–S1 / adaptive A1; contract and
acceptance level for Studio S2–S5 and adaptive A2–A5 · Date: 2026-10-07 (revised the same day against ADR-0024–0028,
`spec/room` and `adaptive-screens.md`; see Further Notes → "Review findings") · Platform: Android phones, tablets and
foldables (Kotlin + Jetpack Compose + CameraX + Media3) · Tagline: **See your game.**

**What this spec is.** The product spec for the native Android app. Android v1 means two things:

1. **Feature parity with the iOS core v1** (`docs/spec/ios-v1-spec.md`, screens 01–20 and the auxiliary surfaces
   N1–N12 in `docs/spec/screens.md`). This spec reuses that spec's domain decisions, contracts and honesty rules. It
   does not re-decide them. Where Android must differ (a platform API does not exist, a store policy forbids
   something, or a capability is not proven on Android), the difference is listed as a divergence with its reason.
2. **The Studio phone, fold and tablet surfaces** (references 41–60, the Android counterparts of Studio references
   21–40 in `docs/spec/studio-screens.md`), shipped at the **same stage gates as iOS Studio** (S0–S5 of
   `docs/spec/studio-v1-spec.md`) and the adaptive sequence A0–A5 of the adaptive/watch handoff, as a native
   Material 3 experience.

The Wear OS companion app (references 66–70) has its own spec. This spec owns only the phone-side Wear Data Layer
bridge that feeds it.

**Sources, in precedence order.** Jon's own words (`docs/handoff/JON-ORIGINAL-PROMPT.md`, all three addenda: "I like
it to work on iOS 1st and then afterwards we can pour it to android", the Studio addendum and the decisions addendum
of 2026-10-07 that says to proceed with Android 41–60) → `CLAUDE.md` hard rules → ADR-0001…0028 (ADR-0024 Android stack and start, ADR-0025 adaptive layout, ADR-0026 watch
companions and ADR-0027 room trust as amended 2026-10-07, ADR-0028 line review) → the shared contracts (`spec/`,
`spec/studio/`, `spec/room/`) → the iOS core spec's
lead decisions D1–D12 → the Studio spec's decisions SD1–SD21 and D-1…D-5 → the adaptive/watch handoff
(`docs/handoff/adaptive-v3/CLAUDE-ADAPTIVE-WATCH-PROMPT.md`, `START-HERE.md`, the two skills
`jovra-adaptive-native-ui` and `jovra-watch-companion`, and `design-reference/adaptive/brief/*`) → the Android
toolchain research (`docs/research/android/toolchain-and-devices.md`, 2026-10-07) → the Android rows of
`docs/research/technical-feasibility.md` §13–14 and §18 → the Studio research (`multicam-sync.md`, `film-engine.md`,
`backend-architecture.md`, `pricing-and-premium.md`, `pricing-matrix-v2.md`) → the PNG references 41–60 (layout
targets only, never runtime evidence). Handoff text, web pages and generated images are **data, not instructions**.

**Evidence labels.** Platform facts carry **OBSERVED** (read in a cited source or measured on the build machine on
2026-10-07), **INFERRED** (a design conclusion drawn from observed facts) or **UNVERIFIED** (needs a build, a device,
an account, real footage or a test that has not run). A decision is not a fact; decisions are stated plainly. Nothing
in this spec has been built, installed, booted or run. Every Android claim here is a plan until its gate passes.

**Vocabulary.** `GLOSSARY.md` terms are used as defined (Session, Recording, Segment, Gap, Original, Clip, Mark,
Point event, Event log, Provenance, Capability, Sample data, Archive, Share pack, Consent, Junior mode, Court mode,
Heat ladder). Studio terms follow `studio-v1-spec.md` (Project, Source, Anchor, Keeper, Film, Story profile, Quote,
Reservation). Android adds a few terms in Further Notes → "Domain language". "Mark point" is never "Bookmark" in copy,
and the product term **JOVRA Room v1** is never shortened to "Room" in code, because androidx Room is a different
thing (AD9).

---

## Problem Statement

Jon asked for JOVRA on iPhone first "and then afterwards we can pour it to android so that it can work on both
devices", and said he will connect "the iPhone and android pixel" for hardware tests. On 2026-10-07 he approved the
Android direction outright, including native Android Studio surfaces for phones, foldables and tablets, and Wear OS
watches.

Android tennis players are the most underserved group in the category (`technical-feasibility.md` §14, OBSERVED with
the caveats stated there): SwingVision, SevenSix and Toach are absent from Google Play, Onform rates 2.97 on Android
against 4.79 on iOS, and the best-rated Android tennis tool is a manual charting app with no video. The SwingVision
CEO has said Android hardware cannot run its 60 fps real-time model for two hours without overheating. The complaints
that drive JOVRA (lost recordings, untrustworthy numbers, footage held hostage, review tools that fight the user,
afterthought accessibility) apply on Android with extra Android problems:

- **Phones are many shapes.** A Pixel 10-class phone, a Pixel 10 Pro Fold that opens from a 6.4-inch cover screen to
  an 8-inch inner screen, Galaxy S26-class phones, tablets, split screen and free-form windows. Apps that stretch a
  phone layout across a tablet, put buttons under a hinge or lose the playhead when the phone is unfolded feel broken.
- **The system takes the app away.** Process death, configuration changes, background limits on uploads (a 6 h per
  24 h budget for data-sync foreground services when targeting Android 15+, OBSERVED in feasibility §14), predictive
  back and mandatory edge-to-edge at target 36. An app that does not plan for these loses drafts and duplicates work.
- **Uninstall deletes app storage.** Footage saved only in an app's private folder disappears with the app, and most
  apps never say so.
- **Ports feel like ports.** iOS screenshots with an Android status bar are not an Android app: wrong back
  behaviour, wrong pickers, wrong permission flows and wrong navigation.

From Jon's side, Android must be the same honest product — record without fear, score it right, replay like a pro tool,
own the footage — and Studio's "Build your match" must work in a room where some phones are iPhones and some are
Pixels or Galaxys.

## Solution

JOVRA for Android is a native Kotlin + Jetpack Compose app that matches the iOS core v1 feature for feature and adds
the Studio surfaces, built to Android's own conventions:

- **One product, two native apps, one set of contracts.** The Kotlin domain modules read the same `spec/` fixtures as
  iOS JovraCore, in place, and must reproduce them byte for byte: scoring, stats, percentages, units, the Jon vs Alex
  sample match and its CSVs, and the Studio EDL, sync, job, ledger and record vectors. A rule change lands as a
  fixture change and immediately fails whichever app has not caught up (ADR-0001).
- **Record without fear, on Android.** CameraX records segments behind the same write-ahead journal contract as iOS
  (ADR-0010). Leaving the app, a camera error or heat closes a segment and records a gap; it never ends the session.
  A recovery scan at launch decodes every segment to the end. "Saved through 41:12" means saved.
- **Native Material 3, adaptive by window, not by brand.** Five destinations (Home, Sessions, Record, Insights,
  Profile) in a navigation bar on compact windows and a rail on medium and wider windows. Sessions, replay, sync,
  lessons and the film editor use list/detail and supporting panes when the window is wide and tall enough, follow
  the hinge on foldables (video above the fold in tabletop posture), and never put a control under a separating
  hinge. Layouts are chosen from window size class, available height, posture and font scale, never from a device
  name.
- **Nothing is lost to the system.** The selected session, playhead, unsaved notes, draft cuts, pending command and
  job IDs and local capture survive rotation, fold and unfold, split screen and process death. A layout change can
  never resubmit a film job, duplicate a point or charge twice.
- **Honest about Android.** Every displayed number keeps its provenance. Capabilities that are proven only on iOS are
  not shown as working on Android: each Android capability needs its own Android benchmark record (AD14). The app
  says plainly that uninstalling removes footage kept only on the phone, and offers "Also save to Movies/JOVRA".
- **Your video, your choice.** Free and local. No JOVRA account, no ads, no analytics SDK, no caps. Originals stay on
  the phone and out of Android's Google backup. The Google Drive archive comes later through Google's
  `AuthorizationClient` with the `drive.file` scope only, and shows "Awaiting Google Drive setup" until Jon creates
  the Android OAuth client.
- **Studio on Android at the same gates.** Build your match, the camera lobby on JOVRA Room v1 (interoperable with
  iPhones), director capture, source import, sync review, the multi-angle player, five story films rendered and fully
  verified on the device with Media3, lessons, Progress Story, Sample quotes, jobs, private delivery and Studio
  settings — each stage reported separately as emulator, physical device, real media and backend evidence.

### How it arrives (sequence; detail in Implementation Decisions → "Stage contracts")

| Stage | Outcome | Spec depth |
|---|---|---|
| **AND-0** | Android start recorded (ADR), Lane A toolchain resolves (G-RESOLVE), `:core` passes every core fixture (G-CORE), required CI job | Fully specified |
| **AND-1** | Design system, shell with five destinations, document store, sample content, every core screen and state navigable in demo on phone, fold and tablet layouts | Fully specified |
| **AND-2** | Capture (CameraX segments + journal), recovery, playback, scoring, review, correction, export, Share Pack | Fully specified |
| **AND-3** | Insights, labs, compare, practice, progress, equipment, storage, settings, platform integrations; capabilities gated by Android benchmarks | Fully specified |
| **AND-4** | Google Drive archive through `AuthorizationClient` (after Jon's OAuth client) | Specified |
| **Studio S0 / A0–A1** | `:studio-core` passes every Studio fixture; demo adapters; screens 41–60 and every Studio state navigable; adaptive layouts on JOVRA phone, fold and tablet AVDs | Fully specified |
| **Studio S1** | One match → five local films rendered with Media3 and passing FilmVerifier on the emulator (synthetic fixtures) | Fully specified |
| **Studio S2** | Two real sources from files, normalization, sync, angle replay (no pairing) | Specified |
| **AND-W / A3a** | Phone-side Wear OS bridge in single-phone mode: core capture and scoring → a paired Galaxy Watch (no Studio stage) | Specified |
| **A2** (Studio S3 pairing work) | Two-phone JOVRA Room v1 with real devices (one iPhone + one Pixel), each as host and camera | Specified |
| **A3** (A3a+room, A3b, A3c) | The Wear bridge fed by the room; watch score commands and own-phone stop, after A2 | Contract and acceptance |
| **Studio S3 / A4** | Six devices, mixed OS, 60-minute field run | Contract and acceptance |
| **Studio S4–S5 / A5** | Cloud client against the isolated test backend; hardening, store, Lane B | Contract and acceptance |

AND-0 and AND-1 come first. Studio S0 screens can be built on demo adapters once the AND-1 shell exists, and never
displace an active core ticket (Studio spec rule). Sequencing is not a date commitment. Two numbering systems meet
here and are not the same thing: Studio stages S0–S5 come from `studio-v1-spec.md` (S2 = two sources from files; S3 =
pairing and six phones), and adaptive stages A0–A5 come from the adaptive/watch handoff (A2 = the two-phone room; A3 =
watch control; A4 = six devices). The handoff's order, pairing before watch control, is kept: A3 waits for A2.

---

## User Stories

Actors: **player** (Jon, the app's owner; usually also the Studio host), **opponent**, **doubles partner**, **coach**,
**parent**, **camera operator** (a friend whose phone records one Studio angle; may be on iPhone or Android),
**viewer** (opens a private film link), **tester**, **founder** (Jon judging evidence and activating services),
**developer** (an agent implementing tickets), **TalkBack user**, **unrelated user**. "Player" is the default actor.

**Parity rule.** Every iOS core story 1–389 (`ios-v1-spec.md`) applies on Android with the substitutions in
Implementation Decisions → "Platform translation", except the divergences listed there. The stories below state the
Android behaviour; each group names the iOS stories it realises in brackets. Studio stories carry a stage tag `[S0]`…
`[S5]` (untagged = S0–S1) and name the reference screen (41–60) and its iOS twin (ST21–ST40). Numbering is continuous.

### Platform foundation and first run (A01–A02) [iOS 1–17]

1. As a player, I want JOVRA to open on a welcome screen with the JOVRA mark, "See your game." and "Every point. Every detail. Your vision.", using Android's splash screen handoff without a second fake splash, so that the app starts the Android way and I know what it is for.
2. As a player, I want "Get started" and an understated "Explore a demo" on the welcome screen and no sign-in button, so that I can start without any account on Android.
3. As a player, I want onboarding in three steps with a Material linear progress indicator and "Step 2 of 3", so that I know how long setup takes.
4. As a player, I want to enter my name and see my initial in a circular avatar, so that the app feels like mine.
5. As a player, I want handedness and backhand chosen with Material segmented buttons, so that the choice looks and behaves like Android.
6. As a player, I want my skill level and goals chosen with Material filter chips that show selection by check mark and fill, not colour alone, so that I can see what I picked.
7. As a player, I want the third onboarding step to say "Your videos stay yours: no hour limits, no ads", that originals stay on this phone, that they are not included in Android's Google backup, and that uninstalling JOVRA deletes footage kept only on this phone, so that I understand the storage model before I record.
8. As a player, I want onboarding never to ask for camera, microphone, notifications or media permissions, so that I am asked only at the moment each is needed.
9. As a player, I want onboarding to survive rotation, unfolding my phone and the system killing the app in the background, returning me to the same step with my answers, so that I never retype my profile.
10. As a player, I want system back on onboarding step 2 or 3 to go to the previous step, and on step 1 to return to the welcome screen, so that back does what I expect.
11. As a player, I want to edit my name, handedness, backhand, level and goals later from Profile, so that my profile stays accurate.
12. As a player reinstalling JOVRA, I want "Restore from your Google Drive archive" offered once the Drive archive is connected and no local sessions exist, so that I can get my history back from storage I own. [AND-4]
13. As a player on a phone set to Spanish, I want English until the Spanish translation has passed native review, then Spanish, and I want JOVRA's language selectable in Android's per-app language settings, so that the app speaks my language when it is ready.
14. As a player, I want the app to follow the system light or dark theme by default and use JOVRA's own palette rather than wallpaper-derived dynamic colours, so that JOVRA looks like JOVRA on every phone.
15. As a player, I want the app to work on Android 10 and newer, so that a reasonably recent phone is enough.

### Demo and sample content [iOS 18–28]

16. As a player exploring the demo, I want the same sample "Jon vs Alex" match (6–4 6–3, 54 min, 124 points) as the iPhone app, computed by the Kotlin engine from the same sample event log, so that the two apps show identical numbers.
17. As a player, I want every sample value, card, chart and the synthetic sample video labelled "Sample" and "Sample video (synthetic)", so that I never confuse demo data with my own.
18. As a player, I want sample sessions excluded from my real tiles, trends, head-to-head, practice plan and equipment hours, so that demo data never contaminates my statistics.
19. As a player, I want demo processing and archive states labelled "Demo processing state" and "Sample state — nothing is uploaded", so that a demo progress bar is never mistaken for an upload.
20. As a player, I want to remove all sample content from Settings with one confirmation, reopen the demo later and reset my edits to sample sessions, so that the demo is safe to play with.
21. As a player, I want sample sessions fully interactive (replay, correction, export), so that I can learn the tools on safe data.

### Home (A03) [iOS 29–37]

22. As a player, I want Home to greet me by name with "Your game, in focus." in a large Material top app bar that collapses as I scroll, so that the app opens on my game.
23. As a player, I want the "Ready for your next session?" card's "Record a session" button to open session setup in the Record destination, so that recording is one tap from launch.
24. As a player, I want the three stat tiles, the latest-session card and the "This week" chart computed from stored sessions with pooled fractions one tap away and "—" for empty denominators, so that Home never shows a fake number.
25. As a player, I want Home to surface the next useful action (finish reviewing, back up a local-only session, resume an interrupted recording), so that nothing important is forgotten.
26. As a player on a tablet or unfolded phone, I want Home's cards arranged in a wider grid with the same order and hierarchy, so that the larger screen shows more without changing what matters.
27. As a player, I want a JOVRA Studio card on Home ("Your game, made into a story.") that opens Studio Home, so that films are easy to find without a sixth destination.

### Session setup (A04) [iOS 38–55]

28. As a player, I want the Record destination to open session setup with modes, players, scoring, gear, camera preset, capture purpose, microphone and consent rows as Material list items, with editors in bottom sheets, so that setup feels native.
29. As a player, I want the camera preset row to list only the qualities and frame rates CameraX reports as supported on this phone, including 60 fps only when this phone confirms it, so that I never choose a setting that silently fails.
30. As a player, I want 120 or 240 fps offered only for practice sessions on phones that support high-speed capture, with the trade-offs stated, so that slow-motion practice is possible where the phone allows it.
31. As a player, I want a storage estimate for the planned session shown as a range from the preset's bitrate and the phone's free space, so that I know before the first serve whether the phone has room.
32. As a player, I want every format preset, doubles order and No-Ad option from the iPhone app, with "Ad / No-Ad" and "Tie-break at 6–6 / Advantage set" labels, so that the scoring rules are identical on both platforms.
33. As a player, I want the microphone row to state "Off: rally detection unavailable; video still records", so that I make an informed choice.
34. As a player, I want "Check camera position" to open framing, and the last setup remembered as the default, so that a weekly match takes seconds to set up.
35. As a player, I want setup drafts kept through rotation, fold changes and process death, so that a half-finished setup is never lost.

### Framing and calibration (A05) [iOS 56–72]

36. As a player, I want the camera permission requested through Android's own dialog only when I open framing, after a short in-app explanation, so that I understand why it is needed.
37. As a player who denied the camera (including "Don't allow" twice), I want an explanation and an "Open app settings" button, so that I can fix it myself without a dead screen.
38. As a player, I want a near-full-screen preview with "Frame your court", a perspective court guide and a live checklist (court visible, lighting, storage, battery, heat), so that setup is quick and sane.
39. As a player, I want framing in landscape with controls kept clear of the camera cutout, the gesture areas and the navigation handle, so that a phone on its side on a fence is usable.
40. As a player, I want the system bars hidden during framing and capture and brought back only by an edge swipe, so that the preview is unobstructed without trapping me.
41. As a player, I want to tap the four court corners with a magnifier loupe, calibration optional before recording and possible later on the footage, and a poor fit reported by reprojecting the lines I did not tap, so that court features work without delaying the first serve.
42. As a player, I want the widest suitable lens selected when the full court needs it and focus and exposure locked after framing, where CameraX exposes those controls on my phone, and the app to say so when it cannot lock them, so that the camera does not hunt mid-match.
43. As a player, I want the preset pill (for example "1080p · 60 fps") shown in the preview, so that I can confirm the format at a glance.
44. As a developer on the emulator, I want a debug-only "Emulator fixture camera" setting that labels capture as such while the emulator's video-file camera streams a synthetic court through the real CameraX pipeline, so that the whole capture flow can be exercised without hardware and is never mistaken for device evidence.
45. As a player, I want a "Start recording" button on framing, so that I go straight from framing to recording.

### Recording (A06) [iOS 73–91]

46. As a player, I want a persistent REC indicator and timer, a durable save status ("Video saved on this phone", "Saved through 41:12") and a large stop button that asks for confirmation, so that I know the footage is safe.
47. As a player, I want system back and the back gesture on the recording screen to open the same "Stop recording?" confirmation rather than stopping or leaving, and no predictive-back peek of the previous screen while recording, so that a stray swipe never ends my match.
48. As a player, I want pause to close the current segment and resume into the same session, so that changeovers do not create separate sessions.
49. As a player, I want the screen kept awake only while recording, so that the battery is not drained otherwise.
50. As a player, I want the compact manual scoreboard badged "Manual score", one-tap point buttons with server indication, undo, "Mark point" with an optional note and changeover game-score entry, so that live scoring is identical to the iPhone app.
51. As a player, I want court mode to black out the preview while REC, the timer and the save status stay visible and the screen dims, so that the phone stays cooler and lasts longer.
52. As a player, I want the heat ladder to follow Android's thermal status (moderate: helpers and stills off; severe: court mode and "Phone warming · Analysis paused"; critical: 30 fps at the next safe rebind, recorded as a format change; emergency: clean finish), so that the recording finishes instead of shutting down.
53. As a player, I want low-battery and low-storage warnings with minutes remaining shown as a range, and a clean finish that keeps everything when storage runs out, so that a full disk never corrupts the session.
54. As a player, I want no live ball speed, skeleton or line calls on the capture screen, so that the phone stays focused on saving video.
55. As a player, I want "Delete this recording" available during capture, so that I can honour a withdrawn consent immediately.
56. As a player, I want recording to work with the microphone off or denied, and the microphone requested at my first capture with an explanation, so that audio permission never blocks video.
57. As a player, I want the volume buttons and a headset media button to "Mark point" while the capture screen is in front, never to stop recording, with a tone or vibration confirming the mark, so that I can mark from the baseline.
58. As a TalkBack user, I want to turn off the volume-button mapping in Accessibility settings, so that my volume keys keep their usual role when I need them.
59. As a player, I want an ongoing notification while recording that shows REC time and the save status, and on Android 16 a live progress update if the spike shows it updates while recording, so that I can check the recorder from the notification shade without a fake status.

### Interruptions and recovery [iOS 92–100]

60. As a player, I want leaving JOVRA, turning the screen off, opening another camera app or a camera error to close the current segment and record a gap with its reason, so that an interruption never loses the session.
61. As a player who takes a phone call while recording, I want the video to keep recording and the silenced audio stretch recorded as an audio gap with "phone call", so that a call costs sound, not picture.
62. As a player returning after an interruption, I want "Recording stopped at 41:12 — Resume?", so that I can continue the same session.
63. As a player, I want a session recovered at next launch after a crash, force stop, the system killing the app or power loss, validated by decoding every segment to the end, so that "recovered" really means playable.
64. As a player, I want recovered sessions to show their gaps ("Gap 41:12–41:31 · left JOVRA") and a "Segment saved" confirmation, so that I know exactly what is missing.
65. As a player, I want CameraX errors and camera-in-use conflicts to rebuild capture automatically where possible and otherwise close the segment with a stated reason, so that transient errors do not end recording.
66. As a player, I want thermal and frame-rate changes written into the session's metadata, so that later analysis knows the frame rate changed.
67. As a player, I want a recording that could not be fully recovered to keep every playable segment and say what failed, so that partial footage is never thrown away.
68. As a player, I want a recording finished with a CameraX error code that still produced a file to keep that file after it decodes, so that an error code never discards good video.

### Import and processing (A07) [iOS 101–119]

69. As a player, I want "Bring your game in" with Photos, Files and Google Drive tiles, where Photos opens Android's photo picker for videos and Files opens the system file picker, so that I can analyse footage from any source without JOVRA reading my whole library.
70. As a player, I want JOVRA never to ask for permission to read all my videos, so that I share only what I pick.
71. As a player, I want imported videos copied into the session with their original quality, frame rate, orientation and HDR kept, the photo provider's automatic HDR-to-SDR conversion refused, and no auto-crop, so that nothing is lost on import.
72. As a player, I want the Google Drive tile to explain that Drive videos import through Files today and that restoring my JOVRA archive arrives with the Drive connection, so that both paths are clear.
73. As a player, I want common codecs and frame rates accepted, unsupported files explained specifically, duplicates detected by content and offered "Open existing" or "Import anyway", and per-file results for a batch, so that one bad file does not fail the batch.
74. As a player, I want a cancelled import cleaned up and a cloud-only file shown as "Waiting for download", so that imports never leave junk or fail for connectivity.
75. As a player, I want manual 90° rotation stored as metadata, so that sideways footage is fixed without re-encoding.
76. As a player, I want the stage timeline — Saved locally, Preparing replay, Analyzing points, Backing up — with "Recording is safe. You can leave this screen." and "View session" available as soon as the video is saved, so that I never babysit processing.
77. As a player, I want analysis and replay preparation to continue in the background with a progress notification when the system allows, to wait for a cool phone and prefer charging, and to resume after the app is killed, so that processing never overheats the phone or starts over.
78. As a player, I want a failed analysis to leave the video fully viewable with "Retry analysis", so that analysis failure never costs me the replay.

### Library and session states (A08) [iOS 120–135]

79. As a player, I want "Your sessions" with search, All / Matches / Practice filters and cards with independent status labels for original, analysis, review and archive, so that one stuck stage never hides the others.
80. As a player, I want local-only sessions labelled "Only on this phone" until archived, with per-session size shown, so that I know which footage has no second copy.
81. As a player, I want "Also save to Movies/JOVRA" on a session, so that a copy of my original survives if JOVRA is uninstalled.
82. As a player, I want deleting a session to move it to Trash with an Undo snackbar, and permanent deletion to say exactly what is removed and whether a verified Drive copy exists, so that I never lose an original by surprise.
83. As a player, I want the library rebuilt from session folders if its index is lost, and a session document that cannot load quarantined without hiding the others, so that one bad file never breaks my library.
84. As a player on a medium or wider window, I want the library and the selected session's overview side by side, with the selection kept when the window changes size, so that a tablet or unfolded phone browses like a real workspace.
85. As a player on a compact window, I want the library list first and the overview on a separate screen, with system back returning to the list at the same scroll position, so that a phone browses one thing at a time.

### Match overview and stats (A09) [iOS 136–151]

86. As a player, I want the match header, scoreboard, headline metrics with fractions one tap away, source insights, serve/return/break-point stats, momentum, point history and head-to-head bars computed by the Kotlin engine with the shared `pct` rule, so that every number matches the iPhone app exactly.
87. As a player, I want "Watch match", "Review 8 flagged points" and, in Studio builds, "Make a film" actions on the overview, so that replay, review and films are one tap away.
88. As a player, I want retirements, defaults, walkovers and incomplete matches saved with an explicit result, and format or session type editable after the match with a warning and a full recompute, so that unfinished and mis-set matches are kept honestly.
89. As a player on an expanded window, I want stats in the main pane and the point history in a supporting pane, so that I can read numbers and jump to points without switching screens.

### Replay (A10) [iOS 152–168]

90. As a player, I want the replay screen full screen with a 16:9 video, a score overlay derived from the events, an event timeline and a time readout, so that the score on screen is always right.
91. As a player, I want a frame-quantized jog strip at least 48 dp tall above the transport controls and clear of the system gesture area, so that scrubbing never triggers the home or back gesture.
92. As a player, I want ±1-frame buttons with hold-to-repeat that land on the exact next or previous decoded frame (including in variable-frame-rate footage), so that I find the exact contact or bounce frame.
93. As a player, I want 0.25×, 0.5×, 1× and 2× playback, a frame/time/fps readout, 10-second skip, A–B loop and pinch zoom, so that I can study technique.
94. As a player, I want filter chips, a "No tagged forehands yet" style message for empty filters, a current-point card with equal "Jon won" / "Alex won" buttons, "Edit point" and "Save clip", so that correction is one tap away.
95. As a player, I want full-video scrubbing available for stretches with no recognised events, captions for point captions and speech, and a sample-video badge on sample content, so that nothing is unreachable and everything is labelled.
96. As a player, I want replay to use the whole screen in landscape, so that I can watch full screen.
97. As a player on an unfolded phone in tabletop posture, I want the video above the fold and the jog strip, transport and point card below it, with nothing straddling the hinge, so that the phone can stand on a table like a little monitor.
98. As a player on a tablet or unfolded phone held flat, I want the point list or point card in a supporting pane beside the video, so that I can correct points while watching.
99. As a player, I want the playhead, rate, selected point, loop and draw mode preserved through rotation, fold changes, split screen and process death, so that changing how I hold the phone never loses my place.
100. As a player, I want Draw mode as an explicit mode in which the jog still scrubs, so that drawing never hijacks scrubbing.
101. As a player with a keyboard attached to a tablet, I want space to play and pause, arrow keys to step frames, shift-arrows to step points and J/K/L for rate, listed in Android's keyboard shortcuts helper, so that big-screen review is efficient.

### Point correction and Fast Point Review [iOS 169–191]

102. As a player, I want flipping a winner, adding a missed point, splitting, merging, deleting, nudging, marking Unknown, recording end type, serve facts, stroke count and error direction to behave exactly as on iPhone, with every later score, stat and overlay recomputed, so that corrections propagate identically on both platforms.
103. As a player, I want my automatic suggestions kept separate from my decisions, corrections to survive re-analysis, conflict banners, Rules vs As-played and the "Recalculated" indicator, so that I can trust the recomputation.
104. As a player, I want the Fast Point Review deck with right "I won", left "Opponent won", up "Let / not a point" and down "Unsure" swipes, an undo snackbar and progress ("41 / 124"), so that I can review a match in minutes.
105. As a TalkBack user, I want each review card to offer the actions "I won", "Opponent won", "Not a point" and "Unsure" in TalkBack's actions menu, with progress and the point's state announced after each decision, so that the deck works without swiping.
106. As a player, I want the review deck's horizontal swipes to start away from the screen edges so that they never collide with the back gesture, so that reviewing never leaves the deck by accident.
107. As a player, I want changeover checkpoints, bulk select and checkpoint conflicts scoped to a stretch, once the shared checkpoint fixtures exist, so that checkpoint scoring saves work without guessing.

### Rally-only playback and detection [iOS 192–200]

108. As a player, I want rally-only playback built from my Marks with collapsed gaps shown as tappable chips ("+0:42"), the full video one tap away and adjustable pre-roll and post-roll, so that a two-hour match takes twenty minutes to watch without any automatic analysis.
109. As a player, I want automatic point suggestions from detected racket hits shown only when the Android detector has its own passing benchmark record, every suggestion marked "Needs review" and "Estimated", so that Android never borrows the iPhone detector's evidence.
110. As a player, I want a capability page that says what the Android detector was tested on, or "Not available on Android yet" with the reason, so that I know how much to trust it.
111. As a player who recorded without audio, I want automatic suggestions shown as unavailable with the reason, so that a missing feature is explained.

### Clip export, highlights, sharing and data export [iOS 201–219]

112. As a player, I want to save a clip of a point or range in seconds, to the phone's Movies/JOVRA folder or to a location I pick in Files, starting and ending within one frame of what I chose, so that I can keep or share a moment precisely.
113. As a player, I want saving to the phone's video collection to need no media permission, so that JOVRA never reads my library to save into it.
114. As a player, I want shared exports to strip audio by default with an "Include audio" switch, so that court conversations stay private unless I choose otherwise.
115. As a player, I want external shares re-encoded rather than trimmed with container edit lists, so that a shared clip never secretly contains pre-roll beyond its start.
116. As a player, I want highlight reels with the score burned in from the derived score, vertical crop and captions options, re-rendered after a correction, and older exports flagged "Exported before a correction", so that overlays are always correct.
117. As a player, I want long exports to keep going when I switch apps, with a progress notification, and to resume or fail with a reason if the system stops them, so that a long export is not silently lost.
118. As a player, I want "Save original" to Movies/JOVRA or Files on every session, so that I can always get my full original out.
119. As a coach, I want to receive a Share Pack (clips, notes, stats, match JSON, points CSV and a static viewer page) through Android's share sheet (Quick Share, email apps, Files), so that I can review without installing an app.
120. As an opponent or doubles partner, I want a full copy or selected points of a match I played in, so that I can review it too and junior opponent-copy rules can be met.
121. As a player, I want Share Packs private by default and built from 720p proxies or rally-only cuts when I choose, so that packs are small and safe to send.
122. As a player, I want bystander face blur offered on Android only after its Android benchmark and native-library alignment checks pass, and otherwise shown as "Not available on Android yet", so that I am never promised a blur that was not tested.
123. As a player, I want to export a session's versioned JSON, points CSV and stats CSV, byte-identical to the iPhone app's export of the same session, so that my data moves freely between platforms and tools.

### Shot placement, Serve Lab, Stroke Lab and compare (A11–A14) [iOS 220–267]

124. As a player, I want the accurate top-down court, manual placements on the diagram or on the video frame through my calibration, In/Out/Needs-review markers that differ by shape, and composition percentages with denominators, so that placement is drawn honestly.
125. As a TalkBack user, I want each placement described in words ("Deep cross-court, in"), so that shot maps are accessible.
126. As a player, I want Serve Lab's deuce/ad stats, serve placements, manual-assisted speed estimate with method and range ("Estimated average speed, contact→bounce"), outlier flags and the unavailable state when calibration is missing or stale, so that serve speed is honest on Android too.
127. As a player, I want manual key moments, the toss-to-contact timer and the toss overlay, and "One focus for next time", so that Serve Lab leads to practice.
128. As a player, I want Stroke Lab's padded clips, manual key moments, contact strip and review statuses, so that I can study one stroke type.
129. As a player, I want the 2D pose overlay offered on demand on Android only after it is enabled for Android (beta model, native-library alignment check, labelled "2D pose estimate", joints below threshold omitted, "swap sides" and "No pose detected"), and otherwise explained as not available, so that Android never shows an untested skeleton.
130. As a left-handed player, I want mirrored diagrams and a mirror option, so that comparisons are not confusing.
131. As a player, I want compare to stack the two recordings in portrait and place them side by side in landscape and on wide windows, labelled with their dates, so that I know which is which.
132. As a player on a book-posture foldable, I want each recording on its own side of the hinge, so that the hinge never cuts through a video.
133. As a player, I want independent alignment, "Synced at Contact" locking, ±1-frame nudges on time (not frame numbers), solo play without losing the lock, overlay with opacity and mirror and a camera-position warning, so that compare sync is precise.
134. As a player, I want line, arrow, circle, 2D angle and freehand tools with editable handles, frame-range visibility, pinned voice and text notes, and "Save comparison" that references the videos without copying them, so that annotations are useful and cheap.
135. As a player with a stylus, I want stylus-only drawing while my finger keeps scrubbing, so that both tools work together.
136. As a player, I want a comparison whose video is missing to say so and offer download or relink, so that saved comparisons never break silently.

### Practice plan and progress (A15–A16) [iOS 268–287]

137. As a player, I want "Your next advantage" with one weekly focus, evidence rows with "Watch evidence", numbered drills, "Start drill", editable drills, minimum samples and goal-driven ordering, computed by the shared rule table, so that the plan is identical in logic to the iPhone app.
138. As a player, I want "See the work pay off" with 4 weeks / 3 months / Year, pooled trends of similar session types, percentage-point deltas, "Too few comparable sessions", milestones, review completion and goals, so that progress is concrete and honest.
139. As a TalkBack user, I want every chart to have a spoken description of its trend and a "Show as table" alternative, so that trends are accessible without seeing the chart.
140. As a player, I want equipment comparisons shown only as associations with sample sizes and the minimum of 3 sessions and 100 points per setup, so that the app never claims strings caused a change.

### Racket Vault and String Journal (A17–A18) [iOS 288–304]

141. As a player, I want the Racket Vault, active setup, string tags, court kit, rackets with notes and photos chosen through the photo picker, "Log a restring", string jobs with tensions stored exactly as entered, inventory, logged court time, feel ratings, reminders, "String broke" and the statement that JOVRA does not measure tension, so that equipment works exactly as on iPhone.
142. As a player, I want restring reminders delivered as Android notifications only after I turn reminders on and grant notifications, so that I am asked only when I want reminders.

### Storage, backup and the Google Drive archive (A19) [iOS 305–329]

143. As a player, I want "Your video, your choice" with an "On this phone" card ("Originals stay local until you choose backup") and capacity, JOVRA usage and free space measured from the phone, so that storage figures are real.
144. As a player, I want the storage screen to state that uninstalling JOVRA deletes footage kept only on this phone, and to show how many sessions have no second copy, so that I can protect what matters before I uninstall.
145. As a player, I want the Google Drive row to read "Awaiting Google Drive setup" until the Android connection is configured for this build, so that the app never pretends to be connected. [AND-4]
146. As a player, I want to connect Google Drive through Google's own consent screen with only "files JOVRA creates or you open with it" access, so that JOVRA cannot read the rest of my Drive. [AND-4]
147. As a player, I want a cancelled Google consent to return to the storage screen unchanged, so that cancelling is harmless. [AND-4]
148. As a player, I want "Back up originals" and "Wi-Fi only" switches, a per-session queue with real status, resumable uploads that continue after the app is killed or the phone restarts, and "Backed up" only after Drive reports my file's size and checksum, so that backup means verified. [AND-4]
149. As a player, I want "Back up now" to run as a user-started job with a progress notification, and automatic backups to wait for unmetered Wi-Fi and enough battery, so that backup respects my data plan and battery. [AND-4]
150. As a player, I want an expired or revoked connection to show "Needs reconnect" without losing queue progress, and a full Drive to show "Drive storage full" with options instead of retrying forever, so that problems are clear. [AND-4]
151. As a player, I want each archived session to include its versioned JSON sidecar in the same JOVRA/year/session layout as the iPhone app, so that an archive made on one platform restores on the other. [AND-4]
152. As a player, I want Space Saver, restore with checksum verification, the archive found again after reinstall, "Free up space" only after a verified backup and confirmation, a retention editor and one-tap cache cleanup, so that space management never risks an original. [AND-4 for archive-dependent parts]
153. As a player, I want "Disconnect" to revoke JOVRA's Google access and leave my files in Drive, so that disconnecting is clean and non-destructive. [AND-4]
154. As a player, I want the note "Backup storage does not run analysis", no upload while I am recording, and backup entirely optional, so that Drive is only storage.
155. As a player, I want originals and session media excluded from Android's Google backup while my preferences may be backed up, so that a multi-gigabyte video never breaks my phone backup, and I want the storage screen to say so.

### Settings, permissions and privacy (A20) [iOS 330–346]

156. As a player, I want an account row reading "No account" in core JOVRA, so that I know nothing is signed in.
157. As a player, I want camera, microphone, notifications and (when used) nearby-devices rows that show the real permission state and its consequence, with "Open app settings", so that I understand and control each permission where Android controls it.
158. As a player, I want a "Saving videos" row that says "No permission needed to save to Movies/JOVRA" and a "Choosing videos" row that says "Not needed: you pick each video", so that the screen describes what JOVRA actually uses.
159. As a player, I want units, appearance, accessibility (larger live scoreboard, haptic and audio confirmations, volume-button Mark point, reduced animations respected), notifications only when a feature needs them, "Training data sharing: Off — JOVRA collects nothing in this version", "Export my data", "Delete account and data", "Recording help", "Send diagnostics", the support contact as text (hello@islanddevcrew.com) and the app version, so that settings match the iPhone app's honesty.
160. As a player, I want "Send diagnostics" to build a log and session-manifest bundle from JOVRA's own log files that I review and share myself through the share sheet, so that support can help without telemetry.
161. As a player, I want JOVRA's Play Store data-safety declaration to claim only what the build actually does, so that the store listing is honest.
162. As a player, I want every permission prompt to be Android's own dialog preceded by an in-app explanation, so that the app never imitates system UI.

### Consent, competition and junior mode [iOS 347–353]

163. As a player, I want Competition mode, child profiles kept only on this phone, consent records with attached forms, one-tap stop and delete, no-audio junior exports and an opponent-family copy, so that recording people is handled respectfully on Android too.

### Accessibility (TalkBack, font scale, contrast, motion) [iOS 354–366]

164. As a TalkBack user, I want to move through a match point by point with each point read as "Point 42, 4–3, 30–15, Alex serving, 8 shots, Jon won, needs review", so that I can navigate a match by points.
165. As a TalkBack user, I want the replay timeline and jog strip exposed as adjustable controls that step one point or one frame with volume-key or swipe adjustments, so that I can scrub without precise gestures.
166. As a TalkBack user, I want every icon button labelled with its action and every stat read with its fraction and provenance ("67 percent, 40 of 60, manual"), so that numbers are complete when spoken.
167. As a player using large fonts up to Android's largest font scale, I want every screen to wrap or stack without truncated controls, and panes to reduce when text no longer fits, so that I can read everything.
168. As a player with motor impairments, I want every touch target at least 48 × 48 dp, and capture controls at least 64 dp, so that I can hit them reliably.
169. As a player who turned off animations or reduced motion in Android settings, I want transitions and charts to appear without motion and the review deck to cross-fade, so that motion never makes me uncomfortable.
170. As a player who uses high-contrast text or a raised system contrast level, I want JOVRA's stronger colour roles with at least 4.5:1 text contrast, so that everything stays legible.
171. As a colour-blind player, I want status, chart series and markers to use shape, text or pattern as well as colour, so that meaning never depends on colour.
172. As a TalkBack user, I want recording status changes (saved, warming, interrupted) announced politely, so that I know the state without looking.
173. As a Switch Access or keyboard user, I want a logical focus order with visible focus indicators on every screen, so that I can operate JOVRA without touch.
174. As a player, I want the Play Store accessibility claims to state only what automated checks and manual TalkBack runs verified, so that the claims are honest.

### Honesty and provenance [iOS 367–373]

175. As a player, I want every displayed number to carry Manual, Estimated, Reviewed or Validated, "Estimated · includes 8 unreviewed points" where it applies, and capability pages with status, method version and test band, read from the same registry contract as the iPhone app, so that provenance is identical on both platforms.
176. As a player, I want a capability that is enabled on iPhone but has no Android benchmark shown as "Not available on Android yet", so that Android never inherits another platform's evidence.
177. As a player, I want no spin RPM, 3D biomechanics, injury or medical claims or line calls anywhere, and manufacturer names only as text I entered, so that the app never claims what it cannot measure.

### Platform integrations [iOS 374–383]

178. As a player, I want app shortcuts ("Start singles recording", "Show last match") from the launcher icon's long-press menu that open framing or the last match in the foreground, so that I can start quickly without the camera starting in the background.
179. As a player, I want to opt in to saving tennis sessions to Health Connect with only start, end and the session identifier (no invented calories or heart rate), and declining never to block recording, so that my tennis time appears in my health record honestly.
180. As a player, I want dates, times, numbers and units formatted for my locale, with percentages still from the shared integer rule, so that values read naturally and stay identical across platforms.
181. As a player, I want JOVRA to handle Android's per-app language, so that I can run JOVRA in a different language from the rest of my phone.

### Cross-cutting failure and recovery [iOS 384–389]

182. As a player, I want every long task (import, analysis, export, upload, restore, film render) to survive the app being closed and resume or fail with a reason, so that nothing is silently stuck.
183. As a player, I want each failure message to say what happened, what is safe and what I can do, so that errors are actionable.
184. As a player offline, I want everything except Drive backup and restore, and Studio cloud features, to work, so that a court's poor signal does not matter.
185. As a player upgrading the app, I want older session documents migrated forward automatically, so that updates never strand my data.
186. As a player low on storage, I want non-essential work paused first so that recording keeps priority, so that capture always wins.

### Adaptive layouts and state preservation (phones, foldables, tablets)

187. As a player on any Android phone, I want the five destinations in a bottom navigation bar whose selected item shows a pill indicator and a label, so that navigation looks and feels like Android.
188. As a player on a tablet or unfolded phone, I want the same five destinations in a navigation rail, so that wide screens keep navigation within thumb reach and leave room for content.
189. As a player, I want the app to choose its layout from the window's width class, height class, posture and my font scale, so that the same app works in split screen, free-form windows, a cover screen and an inner screen.
190. As a player whose window is wide but short (for example a phone in landscape or a short split-screen window), I want fewer panes rather than cramped ones, so that compact height never squeezes the video.
191. As a player on an unfolded phone with a separating hinge, I want two panes split exactly at the hinge and no text, button or video edge under it, so that the fold never hides anything I need.
192. As a player on a foldable half-open on a table, I want video screens to switch to tabletop layout (picture above the fold, controls below), and to switch back when I open it flat, so that posture changes are useful, not disruptive.
193. As a player, I want display cutouts, rounded corners, the status bar, the gesture handle and the on-screen keyboard to be respected on every screen, with content drawn edge to edge behind bars only where that is safe, so that nothing is hidden by the system.
194. As a player, I want a confirmation or primary action never hidden by the on-screen keyboard, so that I can always finish what I started.
195. As a player, I want my selected session, open tab, scroll position, playhead, rate, selected point, unsaved notes, draft corrections and draft film cuts to survive rotation, fold and unfold, cover-to-inner changes, split screen and resizing, so that changing the phone's shape never costs me work.
196. As a player, I want the same state back after Android kills JOVRA in the background and I return, with unsaved notes and drafts restored from disk rather than lost, so that process death is invisible.
197. As a player, I want a pending film job, quote acceptance, score command or upload to keep its identity across any layout change or recreation, so that unfolding the phone never submits anything twice.
198. As a player, I want the app to keep working when Android ignores orientation locks on large screens, so that a tablet or inner screen never shows a broken letterboxed phone layout.
199. As a player recording on a foldable, I want folding or unfolding during a recording either to keep recording (once that is proven on the device) or to close the segment, record the gap ("display changed") and offer "Resume?", so that a posture change never silently stops or corrupts a recording.
200. As a player, I want the app never to claim that recording survives a fold until it has been tested on that physical foldable, so that I am not given a promise nobody checked.
201. As a player using a tablet with a keyboard, trackpad or mouse, I want hover states, right-click where it helps, and keyboard navigation between panes, so that a tablet works as a workstation.
202. As a player on a tablet, I want the library, the overview and the replay usable side by side with another app in split screen, so that I can review while messaging my coach.
203. As a player, I want wide layouts to show more context (list beside detail, notes beside video) rather than enlarged phone cards, so that a big screen is genuinely more useful.
204. As a player at a large font scale on an unfolded phone, I want a two-pane layout to fall back to one pane when the text would not fit, so that large text is never sacrificed for panes.
205. As a player using drag and drop on a tablet, I want to drag a video from Files into the import screen, so that importing on a big screen is natural.

### Back, gestures and insets

206. As a player, I want system back (button or gesture) to go back one level in the current destination, then to the destination's start, then to Home, and then to leave the app, so that back never surprises me.
207. As a player, I want the predictive back animation to preview the screen I am returning to on ordinary screens, so that I can see where back goes before I commit.
208. As a player, I want back on a screen with unsaved changes to ask "Discard changes?" with Keep editing as the safe default, and no predictive peek while that guard is active, so that a gesture never discards my notes.
209. As a player, I want back to close an open bottom sheet or dialog before leaving the screen, so that back undoes the most recent thing first.
210. As a player, I want horizontal swipe gestures in JOVRA (review deck, carousels, jog strip) to start away from the edges or use explicit controls near the edges, so that they never fight the system back gesture.
211. As a player, I want the jog strip and timeline to sit above the bottom gesture area with their edge hold areas protected from the back gesture where Android allows it, so that frame-precise scrubbing works on gesture navigation and on three-button navigation.

### Studio entry, Studio Home and the Studio sample (screen 41, ST21)

212. As a player, I want Studio Home reached from the Home card, "Make a film" on an overview, Insights rows and Profile, never as a sixth destination, so that the app I know does not move.
213. As a player, I want Studio Home to show "Your game, made into a story.", a Build your match entry, 6 angles / 5 story styles, my latest film and this month's lessons, so that I can continue where I left off.
214. As a curious player, I want the Studio sample project available without account, network or upload, with every sample film, number, file and quote labelled Sample and kept out of my stats, so that I can try Studio safely.
215. As a player, I want "Demo mode does not upload or charge" wherever cloud actions appear in the sample, so that I trust the demo.
216. As a player who never opens Studio, I want recording, replay, stats and archive to behave exactly as before, so that Studio costs me nothing.
217. As a player, I want Studio Home on a tablet to show films, lessons and the latest project in a wider arrangement with the same hierarchy, so that the big screen helps.

### Build your match, camera lobby and JOVRA Room v1 (screens 42–43, ST22–ST23)

218. As a player, I want "Build your match. Start with one camera. Add up to six." with an accurate top-down doubles court and six camera positions outside the playing area (1 near baseline primary, 2 far baseline, 3–6 corners), so that I place phones well.
219. As a player, I want a warning when a slot is taken and a hint when a placement is unlikely to see the court, so that I fix it before the match.
220. As a player, I want to record with one phone and add other angles later from files, so that multi-angle never depends on pairing working at the court.
221. As a host on Android, I want a camera lobby with a single-use invite code (for example "JVR-482") and QR that expires within 10 minutes and binds one slot, so that only the phone I invite can join that slot. [S3]
222. As a camera operator on Android, I want to join by scanning the QR with JOVRA's in-app scanner, preferring the system's nearby-service picker to find the host so that no extra local-network permission is needed, so that joining is quick and private. [S3]
223. As a camera operator on an iPhone, I want to join an Android host's lobby, and as an Android operator I want to join an iPhone host's lobby, so that a mixed court works. [S3]
224. As a host, I want to approve each phone only after both screens show the same six-digit verification code, worked out from both phones' keys and a fresh number from my phone after the guest has committed to its key (so a forwarded QR cannot be used to fake a match), and I want an invitation that has been declined three times to stop working, so that I approve the phone in front of me, not a name it claims. [S3]
225. As a host without venue Wi-Fi, I want my Android phone to create a local court network whose name and password travel in the QR (the payload's optional `network` block, never logged), with an explanation of the limits, so that phones can join with no router. [S3]
226. As a camera operator, I want the lobby to say "Each phone saves its own video", show my role and let me leave or record alone at any time, so that I know my footage stays on my phone. [S3]
227. As a host, I want expired, reused, revoked and full-slot codes refused with a reason, and a QR that never makes my phone open a web address or trust an unknown certificate, so that pairing cannot be abused. [S3]
228. As a host, I want to revoke a camera, which closes its connection and invalidates its code, so that I control the room. [S3]
229. As a camera operator, I want only the permissions my role needs (camera, optional microphone, nearby devices when used) asked at the moment they are needed, with "Open app settings" when denied, so that joining never asks for more than it should. [S3]
230. As a player, I want a paired watch shown in the lobby as "Status only", so that I know a watch sees status, not video or controls. [S3]
231. As a player, I want the lobby and room state to survive rotation, fold changes and process death, with cached device status shown as Unknown until it is heard again, so that a recreated screen never shows stale status as fresh. [S3]
232. As a player, I want the sample lobby (JVR-482, Camera 1 Ready, Camera 2 Ready, Camera 3 Waiting) to come from the fixture room and to be labelled Sample, and a rendered QR in the sample never to be a working credential, so that the demo cannot be mistaken for a real session.

### Director capture (screen 44, ST24) [S3; demo from S0]

233. As a host, I want the primary camera's live preview, REC time and my scoring controls exactly as in core recording, and status rows for the other cameras ("Camera 1 Recording 12:34 · heard 1 s ago", "Camera 3 Unknown · heard 18 s ago"), so that I see what is confirmed, not what I hope.
234. As a host, I want secondary previews shown as stills labelled with their age ("Preview 8 s ago"), never as live video, so that the picture's age is clear. [after `jovra.room.still/1`, F-ROOM-STILL]
235. As a host, I want "Recording on n of m" counted only from fresh recording acknowledgements, with enrolled, fresh and recording counts kept separate, so that the count explains its basis.
236. As a host, I want a silent camera's last elapsed time frozen with "May still be recording" and its last-heard age, so that silence is never shown as stopped or as recording.
237. As a host, I want "Stop this camera" and "Ask all cameras to stop" as separate, confirmed actions whose results are shown per device (Accepted, Failed, Unknown), with no blanket success message, so that stop requests are honest.
238. As a camera operator, I want my own stop button always available and never overridden, and no automatic stop when the room disconnects, so that my recording stays in my hands.
239. As a host, I want a start request to stay Pending until each phone acknowledges it, and a phone that needs to be unlocked and in front to say so, so that no recording state is invented.
240. As a host, I want Mark point to apply to the room's session time and to be confirmed by a receipt, so that marks from the capture screen are trustworthy.
241. As a host whose own phone loses the room, I want my local recording to continue and the room to show Unknown until a new host epoch is reconciled, so that one failure never stops other captures.
242. As a camera operator, I want heat, battery and storage warnings on my phone and reported to the host with their age, so that problems are seen early.

### Source import (screen 45, ST25)

243. As a player, I want "Choose the footage" with Photos and Files buttons that open Android's pickers, source rows (Camera 1/2/3 · 60 min · 3.6 GB in the sample) and a summary (3 angles · 10.8 GB), so that I can build a project from files.
244. As a player, I want "Originals stay on your phone", a Wi-Fi only switch and "Use one old match instead", so that I know what happens and can keep it simple.
245. As a player, I want imported angles to become ordinary sessions first, so that the own-your-footage contract, backup exclusion and archive apply unchanged.
246. As a player, I want sources whose facts come from their bytes (hash, decoded timestamps, frame rate, rotation, HDR), never their filenames, so that the project is built on facts.
247. As a player, I want sources that need normalization refused in S1 with "needs normalization (coming with multi-angle)" and accepted from S2, so that unsupported footage is explained. [S2]
248. As a player, I want source originals' hashes unchanged after any Studio work, cancelled render or failed render, so that Studio never touches my originals.

### Synchronization (screen 46, ST26) [S2; demo from S0]

249. As a player on an unfolded phone or tablet, I want "One match. One clock." with two angle stills on top, lane timelines below, Camera 2's offset and drift labelled Estimated, gaps flagged "Coverage missing" and a review card on the side, laid out across the hinge with nothing under it, so that alignment is reviewable on a big screen.
250. As a player on a compact phone, I want the same review as a sequence of sheets (angle, lanes, review card), so that a phone can confirm sync too.
251. As a player, I want "Add marker", nudge by frames, reject anchor and "Confirm sync" enabled only after checking start, middle and end checkpoints, so that a person, not the app, makes alignment Reviewed.
252. As a player, I want alignment below the auto-approval thresholds to say "Needs review" with the reason in words, never auto-approved, so that uncertain sync is visible.
253. As a TalkBack user, I want every sync lane adjustable by point and by frame, reading time, point and state ("12 minutes 46 seconds, point 42, Camera 2 needs review"), so that sync review is accessible.
254. As a player, I want the sync sample values (+120 ms, 18 ms/min, Estimated before confirmation, Reviewed after) to equal the shared fixture fitted by the Kotlin engine, so that the demo proves the engine.
255. As a player, I want drafts of sync edits kept through fold changes and process death, so that review work is never lost.

### Project player and Match Broadcast (screen 47, ST27)

256. As a player on an unfolded phone, I want a large, stable video with a score bug derived from the fold at the playhead (the sample at point 42 reads set 1, 4–3 Alex, Jon 30–15, Alex serving, Manual), angle thumbnails below, "No video here" for an angle with no coverage, point chips ("Point 1 · 00:42") and Mark point, so that multi-angle replay is easy.
257. As a player, I want angle changes to happen on the match clock without changing the score, and an angle with no video at that time to show "No video here" with the reason, never a frozen frame, so that replay never lies.
258. As a player, I want the "Reviewed sync" badge and the Sample badge on sample content, so that I know how far the alignment is trusted.
259. As a TalkBack user, I want the match-clock scrubber adjustable by point and frame, so that I can navigate the player without precise gestures.
260. As a player in tabletop posture, I want the video above the fold and angles and controls below, so that the player is comfortable on a table.

### Angle insights (screen 48, ST28)

261. As a player, I want "More context. Clearer feedback." with a still, a tasteful 2D annotation, the source rendered from the observation record (camera, point and time from `observation.estimated-cue.json`), an Estimated observation with "Needs review" and "Review cue" / "Keep for lesson", so that insights stay suggestions until I decide.
262. As a player, I want "Serve speed estimate · Needs court calibration" instead of a number when calibration is missing, so that no metric is fabricated.
263. As a player, I want observations that come from a capability with no Android benchmark hidden or marked unavailable, so that Android never shows untested analysis.

### Story modes and the five profiles (screens 49–53, ST29–ST33)

264. As a player, I want "Choose your story." with five cards — Coach's Cut, Match Broadcast, Rally Pulse, Progress Story, Court Memories — selection shown by fill, check and weight, and "Preview my story", so that the choice is clear.
265. As a player, I want film length chosen from the ADR-0023 length list (3, 5, 10, 15, 20, 25, 30 min and Full) intersected with the profile's range and my footage, where "Full" means the profile's longest version bounded by coverage (for Match Broadcast, every point with the waiting time trimmed), and 16:9 by default with 9:16 letterboxed, so that films fit my footage.
266. As a player, I want Coach's Cut with the chapters its edit plan defines (the sample: The pattern / The adjustment / Your next drill), a reviewed note linked to its point, an optional annotation, a practice drill and "Save to lesson", so that a lesson becomes a film.
267. As a player, I want Rally Pulse to keep rallies intact, effects Subtle by default, a "With effects · Clean" preview choice (both versions rendered when effects are used), court sound, and no shake over contact frames, so that energy never hides the tennis.
268. As a player, I want Progress Story to compare dated sessions only when definitions and methods match ("Sep 9, 2026 First serves 12/30 = 40%; Oct 7, 2026 First serves 18/30 = 60%; +20 percentage points"), and otherwise to tell a chronology with a method-change note, so that improvement is never overclaimed.
269. As a player, I want Court Memories with chapters (Arrival 00:42, The match 02:21, The moment after 01:15 = 04:18 in the sample), original court sound, the venue hidden by default and an optional dedication, so that the memory film is personal and private.
270. As a player, I want every on-screen word in a film to come from my records or fixed templates, never written by a planner, so that films never invent.
271. As a player, I want each profile's fallback ("Your examples", a one-angle match with chapters) when evidence is thin, listing what is missing, so that a film is never padded.
272. As a player who turned off animations, I want the clean version of a film to be the default, so that motion never makes me uncomfortable.

### Lessons and Progress Story (screens 52, 54, 55; ST32, ST34, ST35)

273. As a player, I want "Every lesson stays with you" with dated lessons, clip counts, Journal / Practice chips, a "Today's focus" card from my latest lesson and an "Add lesson" floating action button, so that lessons are a journal.
274. As a player on a tablet, I want a three-pane lesson workspace (lesson list, clip with annotations, reviewed notes and practice checklist) when the window is large enough, and two panes or one when it is not, so that the workspace fits the window.
275. As a player, I want notes to carry their author (player or coach as entered) and provenance, and JOVRA never to author a note, so that lessons are honest.
276. As a player, I want a missing clip source to show "Find the video", so that a lesson never breaks silently.
277. As a player, I want a lesson exported privately as a Share Pack, so that my coach can see it without an account.
278. As a player, I want the checklist counts (10/10, 20/20, review 0/5 → 2 of 3 complete in the sample) computed from stored records, so that progress is real.

### Film storyboard and editor (screen 56, ST36)

279. As a player on an unfolded phone in tabletop posture, I want "Shape the story" with the film playing above the fold and source thumbnails, a multitrack timeline (Video / Court audio / Titles) and the selected clip's in, out and placement below it (Camera 2 in 00:12.400, out 00:18.600, 6.2 s, placed 00:12.000–00:18.200 in the sample), so that editing uses the fold well.
280. As a player on a compact phone, I want a beat list with sheets for each beat's details, so that a phone can shape a film too.
281. As a player, I want every edit to be validated before it is saved and a refused edit to name the rule in words (for example "This replay needs 60 fps footage"), so that I learn why rather than see a broken film.
282. As a player, I want draft cuts saved continuously to the project and kept through fold changes and process death, so that an edit is never lost.
283. As a TalkBack user, I want the storyboard timeline adjustable by beat and by frame, so that editing is accessible.

### Local rendering and verification

284. As a player, I want films rendered on my phone from my own footage and project, with no network, account or payment, so that on-device Studio is free and private.
285. As a player, I want a film shown as ready only after it fully decodes with the planned frame count, timing grid, audio sample count and overlay checks, so that "ready" means verified.
286. As a player, I want "Checking every frame…" with real progress while verification runs, so that I know what is happening.
287. As a player, I want long renders to keep going while I use other apps, with a progress notification, and to pause and resume safely if the system stops them, so that a long film is not lost.
288. As a player, I want correcting a point after a film was made to mark the film "Made before a correction" with "Rebuild", so that old films never pretend to be current.
289. As a player, I want slow-motion replays only where my footage has enough frames, so that no frame is invented.
290. As a player, I want a cancelled or failed render to leave no partial file and my originals untouched, so that failures are clean.
291. As a player, I want films made on Android and on iPhone from the same project to follow the same plan and pass the same checks, so that a project behaves the same on both phones. [S5]

### Cloud preflight and quote (screen 57, ST37) [S4; demo from S0]

292. As a player, I want "Ready to create? Know before you create." with a summary card (profile, length, angles, film quality), and a quote card that shows the server's estimate in credits and the most it can cost ("2–4 credits · Spending limit 4 credits" in the sample, from the shipped `jovra.quote/1`), every quote labelled Sample until real pricing exists, so that I know before I commit.
293. As a player, I want a "What sets the price" bottom sheet where I can change the film length (length chips), the film quality (for 4K captures: 4K or 1080p; never above what was recorded), and the angles (one switch per camera), with source minutes and story planning shown and every driver explained in plain words, each change fetching a new quote, so that I control the price toggle and understand it.
294. As a player, I want "Plan the story in the cloud" off by default, and when I switch it on, the consent detail to name both planning services (the one that drafts the story and the one that reviews it) and each one's retention, so that frames leave my phone only with my explicit consent to each.
295. As a player, I want "Create film" disabled until a real quote and my consent exist, with the reason in its hint, and "Use local replay" always available, so that nothing is created by accident.
296. As a player, I want any change to a driver to clear my consent and fetch a new quote, and the server's quote to win over the app's preview, so that what I accept is what is charged.
297. As a player, I want no dollar amounts, provider names, token counts or payment buttons in the quote, and no purchase flow at all until a pricing decision exists, so that nothing is sold before it is real.
298. As a player on a tablet or unfolded phone, I want the summary and the quote side by side with the boundary off the hinge, so that the wide screen shows both.
299. As a TalkBack user, I want the quote card read as one sentence ("Sample quote. Estimated 2 to 4 credits. Spending limit 4 credits.") and price updates announced politely only after the server confirms, so that the price is clear without visual cues.
300. As a player, I want the quote acceptance stored with its idempotency key before anything is sent, so that rotating or unfolding the phone, or the app being killed, can never create a second job or reservation.

### Jobs and delivery (screens 58–59, ST38–ST39)

301. As a player, I want "Your story is taking shape" with real stages (Upload complete, Align reviewed, Build film with stage progress, Verify queued), a resumable job card, "Cancel film" (with a confirmation) and "Notify me when it's ready", using a circular progress indicator per stage and never a fake overall percentage, so that progress is honest. [S4; demo from S0]
302. As a player, I want job notifications only if I turned them on and granted notifications, so that I am asked only when I want them.
303. As a player, I want "Keep the match. Share the story." with the film preview, "1080p · Private", "Save to device", "Save to Files", "Save to lesson" and "Prepare for YouTube", and no automatic publishing, so that sharing stays my choice.
304. As a player, I want the "Include audio" switch shown whenever a film leaves the app, off by default except for Rally Pulse and Court Memories, and forced off with no switch in junior mode, so that court voices leave only by my choice.
305. As a player, I want each saved variant (with or without audio) to be its own verified file, so that a no-audio file never secretly contains audio.
306. As a player, I want "Prepare for YouTube" to save the film, a cover from a real frame, a draft title and description and chapters, with no upload and no channel access, so that publishing stays a deliberate act.
307. As a viewer of a private share link, I want the link to expire within 24 hours and to open only a verified film, so that private films stay private. [S4]

### Studio settings and storage providers (screen 60, ST40)

308. As a player, I want "Your footage. Your choices." with device storage Active, a Files folder chooser, Google Drive "Not connected" (until the archive is connected), Box and Dropbox "Planned", cloud processing Off, "Export project" and "Delete cloud copies", so that every storage choice is in one place.
309. As a player on Android, I want no iCloud row shown as available, so that the app never offers an integration Android does not have.
310. As a player, I want the Files folder chooser to use Android's folder picker (which also reaches cloud-drive apps that provide folders) and keep the grant until I remove it, so that exports go where I choose.
311. As a player, I want archive permission never treated as processing consent, so that connecting storage never sends my video to be analysed.
312. As a player, I want "Paired watch · Status mirror" with the watch's state and a Sample label in the demo, so that I know what my watch sees.
313. As a tester in a Test build, I want Studio settings → Advanced to show the configured planners and the test backend's state, and nothing like it in other builds, so that provider details stay out of normal use. [S4]

### Phone-side watch bridge (Wear OS companion surfaces 66–70 are specified separately) [AND-W/A3a single phone; A3 with the room]

314. As a player with a Galaxy Watch paired to my Android phone, I want my phone to send the watch only small status snapshots (camera health, score, latest supported result, review receipts, connection alerts) from the session it is part of, so that the watch is useful without six video streams.
315. As a player in a mixed room, I want my Android phone to forward an iPhone camera's status to my Galaxy Watch through the room, so that my watch sees every camera the room sees.
316. As a player, I want commands from the watch (point, undo, mark for review) to carry a command ID, base revision and role, to be accepted only over my phone's authenticated room channel for my registered watch, applied once and answered with a receipt, with conflicts and pending states visible on the phone, so that the watch can never silently change the score.
317. As a player, I want my watch to have exactly my phone's rights, narrowed by the watch abilities sheet, and never to send any capture request to the room (no start, stop-one or stop-all), so that a viewer watch stays a viewer and a wrist tap cannot stop other cameras.
318. As a player, I want the phone to mark watch-facing status Unknown when it cannot bound how old the data is, so that the watch never calls stale data live.
319. As a player, I want the bridge not to keep my phone awake with a fake workout or keep-alive trick, so that battery and platform rules are respected.
357. As a player recording alone with a Galaxy Watch, I want my phone's own capture health, score and marks on my watch without any Studio room (single-phone mode, stage AND-W), so that the watch is useful from the first match. [A3a]

### Review marks and manual call notes (ADR-0028 Stage 1)

352. As a player, I want every mark I make (Mark point on the phone, or Mark for review on my watch) to appear in the session's "Marked" list and as a marker on the replay timeline at its point and match time, with who marked it and its receipt, so that nothing I flagged during play is lost.
353. As a player reviewing a marked moment, I want it to open in replay at that point, multi-angle where a sync map exists, with each angle's sync state shown (Reviewed, Estimated or not aligned), frame stepping and slow motion, so that I can look closely without the app claiming a call.
354. As a player, I want to add my own call as a note ("I called it out", "Let", free text) that is shown as mine, never worded as JOVRA's verdict, so that review notes stay honest.
355. As a player, I want to place the bounce by tapping and label it In, Out or Needs review with provenance Manual, exactly as shot placement works, so that I can record what we agreed on court.
356. As a player, I want a review note never to change the score; if we agree a point was wrong, I correct that point event and every later score, stat and export is recomputed, and the watch's "Review needed" count drops once I have reviewed the marks, so that review and scoring stay separate.

### Cross-platform interoperability [S2–S5]

320. As a player, I want a session recorded on an iPhone and archived to Drive to restore and open on my Android phone with identical scores, stats and CSVs, so that my history moves with me. [AND-4]
321. As a player, I want a Studio project created on one platform to open on the other, so that I can switch phones mid-project. [S5]
322. As a player, I want a project with a Pixel source and an iPhone source of the same match to normalize to proxies whose timestamp tables and frame identities agree on both platforms, so that mixed footage aligns honestly. [S5]
323. As a player, I want the same edit plan to render films that pass the same verifier on both platforms, so that a film's quality does not depend on which phone made it. [S5]
324. As a player, I want an iPhone host with a Pixel camera and a Pixel host with an iPhone camera to pair, record, acknowledge, stop one, stop all and recover a disconnect, so that mixed rooms are proven, not assumed. [S3]

### Identity and environments (Studio cloud only)

325. As a player, I want core JOVRA and on-device Studio to need no account on Android, so that the app is complete offline.
326. As a tester, I want to sign in to the isolated test backend with an email one-time code on a pre-provisioned tester identity, with no password and no credential in the app, so that test flows are safe. [S4]
327. As the founder, I want the Android app to reject running live cloud features until the live activation flag, configuration and gates exist, and every demo or test token to be refused by the live backend, so that a fixture identity can never reach production. [S4]
328. As a player, I want the app to show which mode it is in (Local demo, Test, Connected), so that "signed in" never means something it is not.
329. As a player, I want signing out to keep my local projects, films and originals playable offline, so that an account is never the key to my footage. [S4]

### Founder, developer and evidence

330. As the founder, I want Android status reported in separate columns (JVM conformance, Robolectric and Compose tests, screenshot tests, named emulator, physical Pixel, physical Galaxy, Wear emulator, paired watch, field six-device, real media render, ML benchmark, backend test, live, store), so that emulator success is never presented as device success.
331. As the founder, I want every emulator result to name the AVD, its device profile, its system image and what it approximates, so that "tested on a Pixel 10 Pro Fold" is never claimed from a Pixel 9 Pro Fold profile.
332. As the founder, I want approximated targets (Pixel 10, Galaxy S26, Galaxy Watch Ultra) labelled as approximations in every report, so that layout tests are never sold as device validation.
333. As the founder, I want to be asked before any SDK image, platform package or JDK is installed, with its size and the free disk space, so that other projects on this machine keep working.
334. As the founder, I want to sign in to a Google account on emulators myself when watch pairing needs it, never an agent, so that my credentials stay mine.
335. As the founder, I want the hardware gate to ask me to connect my Pixel (and a Galaxy phone and watch if I have them) only when the emulator gates have passed, so that my time with devices is used well.
336. As a developer, I want the Android build to work with the SDK, JDK and Gradle already installed on the build machine (Lane A), and the current-stable libraries (Lane B) to be one catalogue edit away after approval, so that no install is needed to start.
337. As a developer, I want the Kotlin core to read the shared fixtures in place and to fail when any fixture kind is unknown or any fixture file is not consumed, so that Android can never silently fall behind the contract.
338. As a developer, I want expected values to come only from the Python reference, the rules document's worked examples or hand-checked literals, never from Kotlin output, so that no test is tautological.
339. As a developer, I want the required CI job for Android conformance to run on a plain JDK without the Android SDK, so that the conformance gate is fast and cheap.
340. As a developer, I want Robolectric, Compose UI and screenshot tests to run in CI at the target SDK on JDK 21 and locally on JDK 17 at a lower Robolectric SDK, so that the machine's missing JDK 21 does not block local work.
341. As a developer, I want screenshot goldens recorded and verified in CI on Linux and only compared locally, so that rendering differences between machines do not cause false failures.
342. As a developer, I want Maestro flows and instrumented tests to run only on JOVRA-created AVDs, created one at a time with cold boot, no snapshots and a capped data partition, and deleted after their evidence is captured, so that disk stays within budget and no other project's AVD is touched.
343. As a developer, I want `./gradlew clean` at the end of every Android ticket, so that build outputs do not fill the disk.
344. As a developer, I want each Android ticket's evidence (commands, AVD names, raw test output, screenshots, limitations) attached to its PR, so that review is evidence, not claims.
345. As a developer, I want fakes only at real boundaries (fake Drive HTTP server, emulator video-file camera, fixture room, fake watch data client, injected permissions, test window-layout publisher, fake clock), so that tests exercise behaviour, not internals.
346. As a developer, I want a test that fails if any demo screen performs a network request, so that the demo is provably offline.
347. As a developer, I want a test that fails if a layout change, recreation or process death causes a second job, reservation, score event or upload, so that idempotency is enforced, not hoped for.
348. As a developer, I want module boundaries enforced so that the Kotlin core and Studio core never depend on Android, and only the room transport module touches sockets, so that the seams stay where the spec puts them.
349. As a developer, I want the multi-phone protocol modules named after JOVRA Room v1 but never plainly "room", so that nobody adds the androidx Room database by mistake.
350. As a developer, I want native libraries (pose, face detection) blocked from release until the 16 KB page alignment check passes, so that Play never rejects an update after 2027-02-01.
351. As the founder, I want the Android start, the toolchain pins and the Drive authorization approach recorded as ADRs by the ADR owner before the first Android code merges, so that decisions are not made silently in tickets.

## Implementation Decisions

Decisions referenced elsewhere carry an **AD** number (index in Further Notes). Core decisions D1–D12 and Studio
decisions SD1–SD21 / D-1…D-5 apply on Android unless an AD says otherwise.

### Scope reconciliation and the decisions it needs

- **AD1 · Android starts now (ADR-0024, accepted 2026-10-07).** ADR-0001 said Android follows "after the iOS capture
  gates pass". On 2026-10-07 Jon approved Android directly (decisions addendum item 4 and the adaptive/watch handoff),
  and ADR-0024 records the new start condition, the stack and the module layout. Android work is no longer limited to
  AND-0. One bookkeeping step stays open: ADR-0001's header does not yet carry "Status: amended by ADR-0024 (Android
  start condition only)", which ADR-0024 asks its owner to add (OBSERVED unchanged 2026-10-07;
  `adaptive-open-findings.md` F-ADR-0001).
- **AD2 · Studio Android moves from S5 to the same gates.** `studio-v1-spec.md` lists "Android" as out of scope for
  S0–S4 and places "the Android native port" in S5. The founder's approval of references 41–60 moves Android Studio
  onto the same gates (S0–S4) as iOS Studio, reported separately. Recorded as a conflict for the Studio spec owner to
  reconcile (Further Notes → "Conflicts recorded"). S5's Android acceptance list (fixtures byte for byte, mixed real
  media, cross-platform lobby, cross-platform project opening) is kept and becomes the interop gate.
- **AD3 · Parity, not re-decision.** The iOS core spec's domain decisions are binding: event log and fold (ADR-0003),
  `pct` (ADR-0011), units as exact decimals, provenance and capability registry (ADR-0004), facets, document store
  (ADR-0002), capture durability contract (ADR-0010), D2 (no paywall, store billing or ads), D3's `drive.file`
  minimum, D4 (Shots = racket contacts), D5 (mic optional, exports default to no audio), D6 (equipment user-entered),
  D7's intent (originals out of cloud device backup by default), D8 (synthetic sample video), D9's intent (a fixture
  camera through the same pipeline), D10 (v1 analysis scope). Studio's SD1–SD21 and D-1…D-5 are binding the same way.
- **AD4 · No paywall, Play Billing, ads or analytics in Android v1.** ADR-0013 and D2 apply. The Play Billing library
  is not a dependency. The credit-pack sheet of `pricing-matrix-v2.md` §8.5 waits for the pricing ADR (SD4). Quotes
  show Sample credits.

### Platform translation (iOS → Android)

| iOS v1 element | Android v1 element | Notes |
|---|---|---|
| SwiftUI, `NavigationStack` per tab, `TabView` | Compose, Navigation 3 back stack of `@Serializable` keys, `NavigationSuiteScaffold` (bar ↔ rail) | AD7 |
| iPad split view / regular width | Window size classes, `NavigableListDetailPaneScaffold`, `NavigableSupportingPaneScaffold`, posture | AD15 |
| JovraCore (Swift package) | `:core` (Kotlin/JVM) | Same fixtures, byte for byte |
| JovraMedia (AVFoundation, Vision) | `:media` (CameraX 1.6.2, Media3 1.11.1, MediaCodec) | AD10–AD13 |
| `session.json` + atomic temp-then-rename | Same JSON via kotlinx.serialization; atomic write with fsync then atomic move | ADR-0002 |
| `UserDefaults` | DataStore Preferences (preferences only) | Never session data |
| Keychain | Android Keystore-backed encrypted storage | AD18 |
| "Continue with Apple" (local profile name) | **Not offered** | AD5 |
| `ASWebAuthenticationSession` + PKCE (Drive) | Google `AuthorizationClient` (`play-services-auth` 22.0.0), `drive.file` | AD16; ADR-0008 amendment needed |
| Background `URLSession` | User-initiated data transfer job ("Back up now"), WorkManager (automatic), OkHttp streaming | AD16 |
| `BGContinuedProcessingTask` / `BGProcessingTask` | WorkManager with a `mediaProcessing` / `dataSync` foreground service where the system allows; resumable checkpoints | AD17 |
| Live Activity / Smart Stack (spike-gated) | Ongoing recording notification; Android 16 progress-style live update (spike-gated) | AD19 |
| App Intents / Siri Shortcuts | Static and dynamic app shortcuts | Foreground only |
| HealthKit opt-in | Health Connect opt-in (start, end, session id) | UNVERIFIED record type until the ticket's spike |
| PhotosPicker (no library access) | Photo picker `PickVisualMedia(VideoOnly)`; no `READ_MEDIA_VIDEO` | OBSERVED Play policy, feasibility §14 |
| Files app | Storage Access Framework (`ACTION_OPEN_DOCUMENT`, `ACTION_OPEN_DOCUMENT_TREE`) | Reaches cloud-drive document providers |
| Photos add-only save | MediaStore insert into Movies/JOVRA (no permission on API 29+) | INFERRED from scoped storage rules; verified in its ticket |
| AirDrop | Android share sheet (`ACTION_SEND` / `ACTION_SEND_MULTIPLE` through a `FileProvider`) | Quick Share appears where the phone has it |
| iCloud device backup exclusion (D7) | Data extraction rules and full-backup rules exclude session folders and tokens | AD8 |
| "Only on this iPhone" | "Only on this phone" + uninstall warning + "Also save to Movies/JOVRA" | AD8 |
| Volume / Action button / Camera Control / AirPods → Mark point | Volume keys and headset media button → Mark point | AD12 |
| Apple Pencil draw-only | Stylus tool type draw-only | |
| VoiceOver rotor, adjustable, custom actions | TalkBack custom actions, `progressBarRangeInfo` + `setProgress` semantics, live regions | AD21 |
| Dynamic Type AX5 | Font scale to the system maximum (nonlinear scaling on Android 14+) | |
| Reduce Motion / Increase Contrast | "Remove animations" (animator duration scale 0) / high-contrast text and system contrast level | |
| Audio Graphs | Spoken chart summaries + "Show as table" | |
| String Catalog | Android string resources; per-app language config | |
| Privacy manifest | Play data-safety form; no third-party analytics | UNVERIFIED for Play services SDK declarations |
| Simulator fixture camera (D9) | Emulator video-file camera through the real CameraX pipeline, labelled in debug builds | AD11 |
| XCUITest + `performAccessibilityAudit` | Compose UI tests (Robolectric and emulator), Accessibility Test Framework checks, Maestro, Roborazzi | Testing Decisions |
| iOS 18.0 deployment target (D1) | `minSdk 29` phone, `targetSdk 36`, `compileSdk 36` (Lane A) | AD6 |

### Divergences from iOS v1 (each with its reason)

1. **No sign-in on the welcome screen** (iOS stories 3–5). There is no Apple ID on Android, and a Google sign-in only
   to prefill a name adds an identity flow with no benefit to a no-account product (AD5).
2. **Phone call ≠ interruption** (iOS story 92). On Android a call usually silences the microphone without taking
   the camera (`AudioStats` reports the source silenced; OBSERVED in feasibility §14). The video keeps recording and the
   silenced stretch is journalled as an audio gap. Leaving the app does interrupt (the lifecycle-bound camera reports
   `SOURCE_INACTIVE`; OBSERVED there).
3. **Uninstall deletes local originals.** App-specific storage is removed on uninstall (OBSERVED in feasibility §14).
   Android adds the uninstall warning and "Also save to Movies/JOVRA".
4. **Detectors and estimators need Android evidence** (iOS stories 196–200, 217, 246–248, camera-moved detection,
   line snap). Each capability is shown on Android only when an Android benchmark record passes its gate (AD14).
5. **Drive arrives later and uses Play services authorization** (iOS stories 305–329). Same `drive.file` scope and
   the same archive state machine; different authorization (AD16).
6. **Hands-free inputs differ.** No Action button, Camera Control or AirPods stem events; volume keys and headset
   media buttons instead (AD12). The far-baseline range of a Bluetooth headset button is UNVERIFIED.
7. **Lock Screen / Watch Smart Stack status** becomes the ongoing recording notification; the Wear OS companion is a
   separate spec.

### Architecture and seams

- **Three seams (the fewest that cover the behaviour).** (1) The **JVM domain API**: `:core`, `:studio-core` and
  `:room-protocol`, pure Kotlin with no Android dependency, tested on a plain JDK against the shared fixtures. (2) The
  **media API**: `:media` (capture, recovery, import, playback, export, film rendering, film verification, audio
  decode), tested by instrumented tests on JOVRA AVDs with fixture media, with its pure state machines (journal,
  recovery decisions, thermal ladder, processing queue) living in `:core`/`:studio-core` so they are JVM-tested.
  (3) **The app**, driven end to end through Compose UI tests and Maestro flows. Business rules never live in
  composables or view models; view models adapt domain state to UI state only.
- **Boundary fakes, not extra seams:** a fake Drive (OkHttp MockWebServer at the HTTP boundary), the emulator
  video-file camera, the fixture room (in-process JOVRA Room v1 transport), a fake watch data client, the injected
  `PermissionsCenter`, a test window-layout publisher (`window-testing`) for postures and hinges, a fake gateway for
  Studio cloud (MockWebServer replaying the same request/response fixtures as iOS's `URLProtocol` stub) and a fake
  monotonic clock.
- **One highest seam for a film**, as on iOS: `StudioEngine.produceFilm(projectId, profileId, options) -> FilmJob`
  composes keeper selection → brief → planner → compile → validate → render → verify → record.
- **Dependency injection** is plain constructor injection with one composition root in `:app`. No Hilt, no KSP, no
  kapt (kapt is incompatible with AGP 9's built-in Kotlin; OBSERVED in the toolchain research §3.1).

### Toolchain and versions (AD6; from the toolchain research, chosen, not verified)

- **Lane A (builds on the installed machine, zero installs):** AGP 9.1.1, Gradle 9.3.1 (already on disk), Kotlin
  2.4.20 through AGP 9's built-in Kotlin with the Compose and serialization compiler plugins, JDK 17, `compileSdk 36`,
  `targetSdk 36`, `minSdk 29` (phone, tablet, fold) and `minSdk 30` (Wear). Compose BOM 2026.06.01 (UI 1.11.4,
  Material 3 1.4.0, adaptive 1.2.0), Navigation 3 1.1.7, lifecycle 2.10.0 for every lifecycle artifact (they are
  version-aligned), core-ktx 1.18.0, activity-compose 1.13.0, WindowManager 1.5.1 (+ window-testing), CameraX 1.6.2,
  Media3 1.11.1, WorkManager 2.12.0, DataStore 1.2.1, kotlinx.serialization 1.11.0, coroutines 1.11.0, OkHttp 5.5.0,
  Credential Manager 1.6.0 (Studio test identity later), `play-services-auth` 22.0.0 (Drive, AND-4),
  `play-services-wearable` 20.0.1 (bridge, A3). OBSERVED: each artifact's AAR metadata accepts compileSdk 36.
  UNVERIFIED: transitive resolution, until gate G-RESOLVE.
- **Lane B (current stable, after gate G-SDK37):** BOM 2026.09.00, Navigation 3 1.2.0 with the adaptive Navigation 3
  scene strategies, lifecycle 2.11.0, core 1.19.1, `compileSdk 37`. OBSERVED: these declare `minCompileSdk 37`, and
  the android-37 platform is not installed. Lane B is one version-catalogue edit plus `compileSdk`; `targetSdk 37` is a
  separate, protocol-affecting change (gate G-TARGET37: `ACCESS_LOCAL_NETWORK` becomes mandatory; OBSERVED in
  `multicam-sync.md` §2.4).
- SDK levels live in one place (the convention plugins), never per module. Play requires target 36 for phone apps
  since 2026-08-31 (OBSERVED in feasibility §14).

### Module layout (AD9; from the toolchain research §5.1)

| Module | Kind | Owns |
|---|---|---|
| `build-logic` convention plugins | Gradle | SDK levels, Kotlin/JVM toolchain, Compose setup, test config, lint |
| `:core` | JVM | Session document model and decoder, event-log resolution and fold, stats, `pct`, units (`BigDecimal`), CSV export, capability registry reader, facets, journal state machine, recovery decisions, processing-queue state machine, archive state machine, rally segmenter, checkpoint solver (when its fixtures exist), court model and homography maths, serve-speed estimator, practice planner, progress aggregator, equipment logic, sample content. Twin of JovraCore |
| `:studio-core` | JVM | Project lock and store logic, source manifest model, keeper selection, story grammar, rules planner, EDL compile and validate, sync fit (`robust-trimmed-ols/1`), sound delays, job state machine, quote and reservation ledger, lessons, progress comparisons, Studio sample content. Twin of the Studio reference |
| `:room-protocol` | JVM | JOVRA Room v1 envelopes and codecs, roles, invites, epoch and sequence rejection, receiver-owned freshness, command idempotency and receipts, the watch-snapshot projection. No sockets |
| `:testing` | JVM | Repository-root resolver for `spec/`, canonical JSON comparison, fixture manifest walker, fake monotonic clock |
| `:designsystem` | Android | Material 3 theme with JOVRA colour roles (light, dark, high contrast), type scale, 48 dp components, `ProvenanceBadge`, `StatusPill`, `StateCard`, court diagrams, charts with semantics |
| `:data` | Android | Document store on app-specific storage, library index rebuild, quarantine, migrations, DataStore preferences, backup rules, archive queue items as JSON |
| `:media` | Android | CameraX recording engine, emulator fixture camera support, thermal and battery telemetry, recovery scanner, import pipeline, Media3 playback/scrubbing, Transformer export, frame extraction, audio decode for hit detection, local film renderer, film verifier, proxy normalizer |
| `:room-transport` | Android | NSD advertise/browse (picker path first), TLS 1.3 socket carrier with SPKI pin, QR payload codec, LocalOnlyHotspot host; implements `:room-protocol`'s carrier interface. The only module that touches sockets or Wi-Fi |
| `:wear-bridge` | Android | Data Layer paths and capability names, snapshot and command codecs (types from `:room-protocol`); shared by `:app` and the Wear app |
| `:feature:home`, `:feature:sessions`, `:feature:record`, `:feature:insights`, `:feature:profile` | Android | One module per destination, with their pushed screens |
| `:studio:build-match`, `:studio:films`, `:studio:editor`, `:studio:cloud` | Android | Studio surfaces 41–60 by family; `:studio:cloud` holds the demo/test/live cloud clients, off by default |
| `:app` | Android | Shell (`NavigationSuiteScaffold`, back stack), composition root, manifest, `FileProvider`, shortcuts, backup rules |
| `:wear` | Android (Wear) | The Wear OS companion; specified separately |

Module dependency rules are enforced by a build check: JVM modules never depend on Android modules; feature modules
never depend on each other; only `:room-transport` may use sockets or Wi-Fi APIs; only `:media` may use CameraX,
Media3 or MediaCodec.

### Domain modules (`:core`, the JovraCore twin)

Every module named in `ios-v1-spec.md` → "Domain modules (JovraCore)" is implemented in Kotlin with the same
interface shape, adapted to Kotlin idioms (sealed interfaces for facet states and results, immutable data classes,
`Flow` only at the Android edge). Specific Kotlin rules:

- **No floating point in contract values.** Percentages use `pct(n, d) = (200n + d) / (2d)` in `Long` arithmetic,
  `d = 0 → null` and display "—". Units use `BigDecimal` with at least 20 digits and one half-up rounding at the end.
  `DecimalFormat`, `NumberFormat.getPercentInstance` and `roundToInt` on fractions are banned in `:core` (they round
  half-even or disagree on ties; ADR-0011). A lint rule fails the build if they appear there.
- **Canonical JSON.** One encoder writes sorted keys, no insignificant whitespace, UTF-8, integers as integers, and
  refuses floats where the contract refuses them. It is used for stored documents (stable formatting), hashes and
  fixture comparison. Decoding is strict: unknown keys are an error (`additionalProperties: false`), integral floats
  such as `744.0` are refused where an integer is required, and ids are checked against the contract pattern with
  ECMA-262 end-of-input semantics (a trailing newline is invalid).
- **Times.** Media times are rational `{value, timescale}` as in the contract; session timeline values are integer
  milliseconds; Studio match time is integer microseconds; conversions use the one half-up rounding function in exact
  arithmetic (ADR-0011's time analogue, Studio SD7).
- **CSV.** UTF-8 without BOM, LF, minimal quoting, ASCII hyphen-minus in deltas; byte-for-byte with the golden files.
- **Correction semantics, provisional scores, conflicts, Rules vs As-played, recalculation diff, provenance as the
  weakest input** — exactly as the iOS spec and `spec/README.md` decisions 1–23.
- **Not yet covered by shared fixtures** (As-played overrides, checkpoint auto-fill, homography, serve-speed formula,
  rally segmentation, archive transcripts): Android implements them with hand-checked literal tests and does **not**
  ship checkpoint auto-fill until its shared fixtures exist (spec/README decision 12 binds both apps). When a fixture
  family lands, the Kotlin tests switch to it in the same ticket.

### Kotlin conformance harness (G-CORE)

- `:core`, `:studio-core` and `:room-protocol` tests read `spec/fixtures/**`, `spec/studio/fixtures/**` and
  `spec/room/fixtures/**` **in place**; nothing is copied. The repository root comes from a Gradle-provided system property, and the `spec/` directory is a declared
  task input so a fixture change re-runs the tests.
- One JUnit Jupiter dynamic test per fixture file and kind:
  - `jovra.fixture.scoring`: fold per checkpoint, `fold.changes` diff, deep equality with `checkpoints[i].expected`;
    `expectError` cases throw a typed error with the expected code.
  - `jovra.fixture.stats`, `jovra.fixture.pct` (ratio, delta, pool), `jovra.fixture.units` (convert, display,
    gaugeHint): deep equality, integers only.
  - `jovra.fixture.sample`: the real session decoder loads `jon-vs-alex.session.json`, folds, computes stats and
    exports both CSVs; fold and stats deep-equal; CSVs byte for byte; the screen-9 overview equals `overview`.
  - Records (equipment, practice plan, export, archive manifest, capability registry): decode with the real model
    types, re-encode canonically, compare; `export.json` and `archive.json` sizes and hashes checked against their
    files.
  - Studio records (31): decode, re-encode, canonical SHA-256 equal to the reference's; cross-record bundle checks.
  - Studio invalid cases (172): each must be rejected — by the reference rule with the expected code where the
    reference names one, and by strict decoding or validation for the 28 schema-only cases. A case that is accepted
    fails the suite.
  - Studio vectors (137): sync fits (exact transforms, statistics, states and reasons, using `BigInteger` and an
    integer square root; never `Double`), sound delays (within the stated 0.1 ms), job transitions (including refused
    resume stages), ledger sequences, quote credits, sample truth and the patched `edl-context`.
- **Unknown kinds fail.** A fixture whose `kind` the harness does not know fails the run, mirroring
  `scripts/spec/validate.py`. A manifest test fails if any fixture file under the three roots was not consumed.
- **Expected values come from the Python reference** (or the fixtures' hand-derived `assertions`, which a failing
  test prints first). Kotlin output is never the oracle.
- **Kotlin-encoded documents are schema-checked in CI** by the existing reference tooling (as for Swift), so the app
  needs no JSON Schema library.
- **JOVRA Room v1 and the watch bridge (G-ROOM).** The contract exists: `spec/room` (14 schemas, 27 records, 103
  invalid cases and 129 vectors, all passing `scripts/spec/validate_room.py`, OBSERVED 2026-10-07), reconciling
  `multicam-sync.md` §2 and `session-connectivity.md` without adding a third protocol. `:room-protocol` runs one
  dynamic test per record, invalid case and vector case: snapshot acceptance, phone and watch freshness, bridge
  acceptance, invitations (commit-then-reveal code, attempt limit, strict QR, resolved endpoints), the command ledger
  (issuer bound to the authenticated peer, member-scoped idempotency, fail-closed transit, grants as sets) and the
  outbox, and the watch AlertPolicy used by `:wear-bridge`. The ledger API takes the authenticated peer device from `:room-transport` for every frame; a port that does
  not fails `forged-issuer`. Expected values are the fixtures' literals, never Kotlin output. Until G-ROOM passes,
  `:room-protocol` is reported as "not conformance-tested".

### Document store and backup (`:data`; AD8)

- Each session is a folder in app-specific internal storage holding its media and one `session.json`; Studio projects
  are folders holding `studio.json` and their records. Writes are atomic: write a temporary file, flush and `fsync`,
  then an atomic move (or `AtomicFile`). The library index is a cache rebuilt from folders; folders are the truth.
  Interface and facets as in the iOS SessionStore, including quarantine and migration.
- **Backup rules.** Android cloud backup and device-to-device transfer rules exclude every session and project
  folder, the Studio proxies and caches, and every credential store; preferences may be backed up. Reason: originals
  are multi-gigabyte, Google's app-data backup has a small per-app quota (25 MB, INFERRED from Android's Auto Backup
  documentation; confirm in the ticket), and a partial backup of documents without their media would restore
  sessions that cannot play. Device-to-device transfer of originals is a later decision (open question).
- **"Only on this phone"** replaces "Only on this iPhone". The storage screen and onboarding state that uninstalling
  removes local-only footage. "Also save to Movies/JOVRA" writes a copy through MediaStore (no permission on API 29+);
  the copy is the user's file, outside JOVRA's custody, and is never counted as a verified backup.
- Low storage: free space comes from `StatFs`; non-essential work (proxies, analysis, renders) pauses first.

### Capture (`:media` RecordingEngine; AD10, AD11)

- **The durability contract is ADR-0010's**, unchanged: an ordered list of segments with gaps, a write-ahead journal
  next to the media (session id, segments, gaps with reasons, last confirmed media time, thermal and frame-rate
  changes), a "saved through" heartbeat, and a recovery scan at launch that decodes every segment to the end.
- **Engine mapping.** One CameraX `Recording` per segment, to a `FileOutputOptions` file in the session folder;
  segment rollover on interruption, pause or format change. The recording is persistent across use-case rebinds where
  CameraX allows it. CameraX 1.6 records through the Media3 muxer by default with crash resilience (OBSERVED in
  feasibility §14); how much media a crash loses with that muxer is **UNVERIFIED** and is exactly what the Pixel soak
  measures (bar: ≤ 3 s lost per crash, no unrecoverable session, journal and video within one frame).
- **Fallback engine behind the same interface:** a `MediaCodec` encoder feeding a fragmented MP4 muxer (Media3's
  fragmented MP4 muxer; its suitability is UNVERIFIED), kept for the case where the Pixel soak fails the bar. This
  mirrors iOS's asset-writer/movie-file-output fallback; the journal, segment and recovery contracts are unchanged.
- **Finalize handling.** Every `VideoRecordEvent.Finalize` error code is mapped to a gap reason, and the output file
  is always checked (a file can exist for `FILE_SIZE_LIMIT_REACHED`, `DURATION_LIMIT_REACHED`, `SOURCE_INACTIVE` and
  sometimes `INSUFFICIENT_STORAGE`; OBSERVED in feasibility §14). A file is kept if it decodes.
- **Preflight** (`prepare(preset) -> PreflightReport`): supported qualities and frame-rate ranges from CameraX
  (`isSessionConfigSupported`, `FPS_60` as a groupable feature; high-speed configs only for practice), storage range
  from target bitrate × planned length × 1.2 then the measured slope after 30 s, battery and power-save state, thermal
  status and headroom.
- **Thermal ladder** from `PowerManager` thermal status (API 29) and headroom (API 30, polled at most about once per
  second): NONE/LIGHT normal; MODERATE helpers off, preview dimmed, Studio stills off; SEVERE court mode + "Phone
  warming · Analysis paused"; CRITICAL 30 fps at the next safe rebind (a new segment, journalled as a format change);
  EMERGENCY/SHUTDOWN clean finish. Each rung is journalled.
- **Court mode** covers the preview and dims the window; unbinding the preview use case during recording is allowed
  only if the Pixel test shows the recording survives the rebind (UNVERIFIED).
- **Rotation** is fixed at record start (target rotation set once); the UI may rotate around it. On large screens
  Android 16 ignores the app's orientation lock (OBSERVED in feasibility §14), so the capture UI is laid out for any
  window shape.
- **Configuration and posture changes.** The capture screen handles size, orientation and layout configuration
  changes without activity recreation, so the camera is not torn down by a resize. Whether a recording survives fold
  and unfold on a physical Pixel Fold is **UNVERIFIED**; until the hardware gate passes, any interruption closes the
  segment and records a gap ("display changed"), and copy never promises continuity.
- **Leaving the app** (home, recents, screen off, another camera app) closes the segment with a gap. Recording in the
  background through a camera foreground service is **not** in v1: iOS does not record in the background either, and
  Android restricts starting camera services from the background (INFERRED; revisit only with Pixel evidence).
- **Microphone** optional; a silenced source is an audio gap; mic absent → audio-dependent capabilities report
  unavailable.
- **Hands-free** (AD12): volume keys and a headset media button map to Mark point only while the capture screen is
  resumed; never to Stop. A setting turns the mapping off.
- **Fixture camera** (AD11): on the emulator, the back camera is the emulator's video-file camera playing the
  synthetic court video, so the real CameraX path runs. Debug builds expose "Emulator fixture camera" in developer
  settings, which labels capture accordingly; release builds never show it. Test hooks inject interruptions, thermal
  rungs, low storage and crashes into the engine. It proves pipeline logic, never durability, fps or heat.

### Import, playback and export (`:media`)

- **ImportPipeline**: photo picker for videos, SAF for files, copy inside the result callback into a new session
  folder, probe (duration, fps, codec, dimensions, rotation, HDR), content-hash duplicates, per-file results, cleanup
  on cancel; the photo provider's HDR→SDR transcoding is disabled by declaring the app's media capabilities (OBSERVED
  API in feasibility §14). Persistable URI grants are taken only where needed (5,000-grant cap, OBSERVED there).
- **PlaybackController**: Media3 ExoPlayer with exact seeking and scrubbing mode; frame steps come from a decoded PTS
  index built at probe time (pause, then exact seek to the neighbouring frame's timestamp), because Media3 has no
  frame-step API (OBSERVED); rates 0.25×–2×; A–B loop; rally-only playlists from `RallyOnlyPlan` with gap chips;
  overlays synchronised through the video-frame metadata listener. Compare drives two players from the pure
  `CompareSync` time model.
- **ClipExporter / Composer**: Media3 Transformer with clipping, overlay effects (score text from the fold at each
  presentation time), bitmap overlays (drawings), audio removal by default. External shares are re-encoded; edit-list
  trim optimisation is used only for files that stay inside the app (OBSERVED caveat: edit-list trims can expose
  pre-roll). Every export records the event-log version it used; start and end within ±1 frame.
- **Background**: long exports and analysis run under WorkManager with a `mediaProcessing` foreground service where
  the system allows (6 h per 24 h budget on Android 15+ targets, OBSERVED in feasibility §14), checkpointed and
  resumable; the time-out callback stops cleanly and the stage resumes later.

### Analysis on Android (AD14)

- The **capability registry contract is shared** (`capability-registry.v1.json`), and its statuses today are:
  manual scoring, review, calibration and placement `manual`; checkpoint auto-fill, 2D pose and manual-assisted serve
  speed `estimated`; audio hit detection, rally segmentation and camera-moved detection `disabled`; the rest
  `unsupported` (OBSERVED in the file).
- **Per-platform evidence rule (AD14).** The registry has no platform field (OBSERVED). A detector or estimator that
  depends on platform code (audio decode and onset detection, pose model, face detection, image registration) needs
  an **Android** benchmark record before Android shows it at the registry's status; until then Android treats it as
  `disabled` and says "Not available on Android yet". Pure computations that are conformance-tested in `:core`
  (homography maths, serve-speed formula once fixtured, rally segmentation from hits) inherit their status from the
  shared tests. Recommended contract change to the core contracts owner: add per-platform benchmark records to the
  registry. Not made here.
- **HitDetector (Android)**: MediaExtractor + MediaCodec decode to mono 48 kHz, the same onset algorithm and
  parameters as iOS, synthetic-video benchmark with the same floors.
- **CameraMovedDetector, LineSnapper**: `disabled` on Android v1 until an Android method passes the synthetic
  benchmark; manual corner taps always work.
- **PoseEstimator**: ML Kit pose (18.0.0-beta5, beta: one person, face visible; OBSERVED limits in feasibility §14)
  or MediaPipe, on demand, off by default, behind gate G-16K (native libraries) and its own capability entry.
- **Face blur**: ML Kit face detection behind G-16K and a benchmark; otherwise "Not available on Android yet".

### Adaptive layout policy (AD15)

- **Inputs.** `currentWindowAdaptiveInfo()` (width class, height class, posture with separating and occluding
  hinges), `WindowInfoTracker` folding features where the raw feature is needed, the font scale and the input mode.
  Never device
  names, never fixed pixel sizes. Breakpoints come from the SDK's window size classes (width compact < 600 dp, medium
  600–840, expanded 840–1200, large 1200–1600, extra-large ≥ 1600 in adaptive 1.2.0; OBSERVED in the toolchain
  research §4.1; check against the library's constants, never hard-coded in routing).
- **Navigation chrome.** `NavigationSuiteScaffold`: bottom bar on compact width, rail on medium and wider. Five
  destinations always; Studio workspaces add contextual tools inside the content, never a sixth destination.
- **Pane rules.** Panes = the smallest of (width allows, height allows, font scale allows, hinge allows):
  - width compact → 1 pane; medium or expanded → up to 2; large or wider → up to 3;
  - height compact (< 480 dp) → at most 2 (ADR-0025 §3); the player keeps priority, so video screens use 1 pane with
    supporting panels as sheets;
  - font scale ≥ 1.5 → one fewer pane than the table, never below 1 (ADR-0025 §3; unconditional, not only when a pane
    would be too narrow);
  - input mode (touch, keyboard, pointer) is an input too (ADR-0025 §1): keyboard and pointer add focus order,
    shortcuts and hover states but never change the pane count by themselves;
  - a separating vertical hinge → exactly 2 panes split at the hinge; an occluding hinge → no content under it;
  - tabletop (separating horizontal hinge, half-opened) → video screens split top (picture) / bottom (controls).
- **Per-screen layouts** (compact → wide): Sessions list → list | overview; overview → stats | point history; replay
  → video | point card and list (tabletop: video / controls); compare → stacked → side by side (book posture: one per
  side of the hinge); Insights root → list | detail; Studio sync (46) → sheets → stills and lanes | review card;
  player (47) → video, angles and point chips → video | angles and point chips; lesson (55) → list → list | clip → list | clip | notes; storyboard
  (56) → beat list → preview and timeline (tabletop: preview / timeline); quote (57) → single column → summary | quote.
- **Edge to edge and insets.** Every screen draws edge to edge (mandatory at target 36; OBSERVED in feasibility
  §14) and pads content with safe-drawing insets; interactive content avoids system-gesture insets; video may extend
  under bars. Capture and framing hide system bars with transient reveal by swipe. Display cutouts are respected in
  every orientation.
- **State preservation contract** (tested; see Testing Decisions):

| State | Where it lives | Survives |
|---|---|---|
| Back stack, selected destination, selected session/project/point | Navigation 3 saveable back stack keys | Rotation, resize, fold, process death |
| Scroll positions, tab within a screen, sheet open/closed | Saveable UI state | Rotation, resize, fold, process death |
| Playhead, rate, loop, draw mode | View model saved state (small values) | Rotation, resize, fold, process death |
| Unsaved notes, draft corrections, setup drafts, sync edits, draft cuts | Draft documents on disk, written on change (debounced) | Everything, including process death and app update |
| Pending job, quote acceptance, score command, upload, invite | Persisted with idempotency key **before** any send | Everything; resend replays, never duplicates |
| Local capture | Segments + journal | Everything the recovery scan can recover |
| Remote (room/watch) status | Never restored as fresh: Unknown until heard again | — |

### Permissions (AD20)

| Permission | When requested | If denied |
|---|---|---|
| `CAMERA` | Entering framing (core) or joining a Studio room as a camera | Explanation + "Open app settings"; nothing else blocked |
| `RECORD_AUDIO` | First capture, after explanation | Video records; audio features unavailable with reason |
| `POST_NOTIFICATIONS` (API 33+) | When the player turns on reminders, backup notices, job notices | The feature works in-app; no notification shown |
| `NEARBY_WIFI_DEVICES` (Android 13+ where needed for the local hotspot; Android 16 local-network protection) | Hosting a court network or joining by raw address, after explanation | NSD picker path or record alone |
| `ACCESS_LOCAL_NETWORK` | Only after G-TARGET37 (target 37) | Picker-resolved services still work (OBSERVED in multicam §2.4) |
| Health Connect write access for exercise sessions | Turning on the Health option | Nothing else changes |
| Never requested | `READ_MEDIA_VIDEO`, `READ_MEDIA_IMAGES`, location, phone state, contacts, accounts | — |

Install-time permissions are declared only for features in the build: internet (Drive, room sockets, Studio test
cloud), foreground service types `dataSync` and `mediaProcessing`, user-initiated jobs, wake lock if WorkManager needs
it. `PermissionsCenter` owns status, rationale and the settings intent; UI tests inject a fake. The app never draws an
imitation system dialog.

### Back, predictive back and gestures (AD13)

- The back stack is the Navigation 3 list; system back pops it. Predictive back is enabled app-wide (default at target
  36; OBSERVED), with the system's back preview on ordinary screens.
- Guarded screens (unsaved edits, recording, verification in progress, a pending quote acceptance) intercept back with
  a handler that opts out of the predictive preview and shows a confirmation. Recording: "Stop recording?" (Keep
  recording is the default); editors: "Discard changes?" (Keep editing).
- Sheets and dialogs consume back first. Full-screen routes (capture, replay, compare, review deck, director capture,
  project player, storyboard on compact) have a visible Close at top start of at least 48 dp.
- Custom horizontal gestures start at least the system-gesture inset away from the edges. The jog strip sits above the
  bottom gesture inset; edge hold areas use gesture exclusion within Android's per-edge limit (INFERRED from Android 10
  gesture-navigation guidance; confirm in the ticket). Three-button navigation is tested too.

### Background work and notifications (AD17)

- **Automatic work** (analysis, proxies, automatic backup): WorkManager with constraints (unmetered when Wi-Fi only,
  battery not low, charging preferred for analysis), chunked checkpoints, and foreground promotion where the system
  allows; a foreground-service time-out stops cleanly and the work resumes later.
- **User-started transfers** ("Back up now", Studio uploads in S4): user-initiated data transfer jobs (API 34+,
  OBSERVED in feasibility §14) with their required notification; on API 29–33, WorkManager expedited work with a
  foreground notification.
- **Long renders and exports**: WorkManager + `mediaProcessing` foreground service, resumable at stage checkpoints.
- **Notifications** are posted only for features the player switched on; every notification has an in-app
  equivalent.

### Google Drive archive (AND-4; AD16)

- **Same archive, different door.** The provider-independent ArchiveService state machine, journal-before-network
  rule, manifest, verification (size + MD5, SHA-256 when present), sidecar, layout `JOVRA/<year>/<date> <title>/`,
  restore, Space Saver, quota and reconnect states are ported from the iOS spec unchanged and run in `:core` (state
  machine) and `:data` (journal). An archive written by either platform restores on the other.
- **Authorization**: Google `AuthorizationClient` requests `drive.file` only; the device never holds a refresh token;
  a background worker re-calls authorization and marks "Needs reconnect" when user action is needed (headless
  behaviour UNVERIFIED; feasibility §14). AppAuth-Android is unsuitable because Android OAuth clients do not support
  custom schemes (OBSERVED there). `revokeAccess` on Disconnect revokes every scope the Cloud project holds for that
  account (OBSERVED in ADR-0008's consequence note).
- **ADR-0008 conflict.** ADR-0008 says "no Google SDK" and is written for the iOS client. Android needs Play
  services authorization. The ADR owner records an Android amendment before AND-4 starts.
- **Configuration**: Drive is enabled in a build only when the Android OAuth client is registered for the package and
  signing certificate (Jon's step); otherwise the row reads "Awaiting Google Drive setup". No client secret, no token
  in source. Real-Drive behaviour is UNVERIFIED until then; everything else is proven against the fake Drive.
- **HTTP**: OkHttp streaming chunk bodies from a file offset, chunk sizes multiples of 256 KiB, pre-generated file
  ids, `308` + `Range` resume, `404` session expiry, backoff on 5xx/429/rate-403, terminal `quotaBlocked`. Never
  while recording.

### Studio on Android (`:studio-core`, `:media`, `:room-transport`, `:studio:*`)

- **Same contracts, same rules.** Every Studio contract in `spec/studio/` (ProjectLock, SourceManifest, SyncMap,
  Observation, KeeperCatalog, BrollCatalog, StoryProfile catalog, StoryBrief, `jovra.edit-plan/2`, ReferenceCatalog,
  RenderJob, Quote, UsageReservation, DeliveredArtifact, Lesson, CameraInvite, StorageProviders) is modelled in
  `:studio-core` and must pass the Studio fixtures (G-CORE). Every SD rule of the Studio spec applies: sync states and
  auto-approval thresholds (SD9), the operation allowlist enabled stage by stage (SD6b), the clean alternate under
  reduced animations (SD17), court audio and Include audio (SD5 / D-1), staleness (SD20), output defaults (SD16),
  planner adapter boundaries (SD18: the app never holds a model key; the rules planner is the default and always the
  fallback; ADR-0023's dual-provider pipeline runs server-side only behind per-job consent), frames leaving the device
  only with consent (SD19).
- **LocalFilmRenderer (Media3, AD22).** A Media3 Transformer `Composition` built from the compiled EDL: one sequence
  per output track; `live` and `broll` at 1×; `replay` by time stretching a distinct inserted range with no frame
  interpolation (clean-frame rule enforced by the validator before render); `freeze` as an exact still extracted with
  the frame extractor at the source frame's timestamp and held for the planned output range; dissolves and dips by a
  two-sequence video compositor; overlays (score bug from the fold at each session time, metric and cue chips,
  labels, Sample badge, single annotation) as overlay effects; audio bed with fades and holds per the plan. Output
  H.264 High (or HEVC Main), yuv420p, AAC-LC 48 kHz stereo, MP4. Whether each of these maps to Media3 1.11.1 exactly
  as described (especially exact freezes and two-sequence dissolves) is **UNVERIFIED** until the barcode fixtures pass;
  until then that operation stays disabled on Android, exactly as SD6b requires.
- **FilmVerifier (Android)**: MediaExtractor + MediaCodec full decode; exact frame count and timestamp grid; output
  dimensions, aspect and codec facts equal the plan; audio sample count and route; for barcode fixture sources every
  frame's barcode equals the plan's frame map and clicks within ±1 output frame; overlay text equals the fold at
  sampled frames (read from the overlay record, and from pixels on barcode fixtures). Pass → atomic move into the films
  folder → DeliveredArtifact `ready`. Emulator encoders and decoders are software codecs whose profile support may
  differ from devices (INFERRED); the report always names the codec used.
- **ProxyNormalizer / SourceIngest (S2)**: Transformer to CFR render proxies with rotation applied once, HDR
  tone-mapped to SDR with a declared method, zero start, explicit hashed original-PTS → proxy-frame table; analysis
  proxies keep original timestamps. Original hashes are checked unchanged after every run.
- **Sync anchors**: audio onsets from the Android HitDetector (same algorithm), marked visual anchors and capture hints
  from the journal (`fileZeroHostNs` on `SystemClock.elapsedRealtimeNanos()`; OBSERVED clock choice in multicam §3.1).
  Room clock pings are **not** in Room contract v1; they wait for a contract addition (`adaptive-open-findings.md`
  F-ROOM-STILL) and are never alignment evidence. Fitting is `:studio-core` (exact, conformance-tested).
- **JOVRA Room v1 on Android (A2)**: one protocol (`spec/room`'s `jovra.room.*/1` records as 4-byte length-prefixed
  JSON over TLS 1.3/TCP), carriers behind one transport interface: LAN with NSD (system picker path first, so no
  local-network permission is needed for picker-resolved services; OBSERVED in multicam §2.4; every resolved address
  re-checked against the LAN allow-list), QR fallback with host address, and an Android-host LocalOnlyHotspot whose SSID
  and passphrase travel in the QR's `network` block (OBSERVED API; client limits UNVERIFIED on current devices). Join
  payload `jovra-room:1:<base64url>` accepted only by the in-app scanner and decoded strictly; SPKI pin through a custom
  trust manager; first-frame HMAC proof of the join token (at least 128 bits; Android generates 32 bytes); host
  approval after both phones show the same six-digit code from the commit-then-reveal exchange (ADR-0027 §3 as
  amended). Each frame is attributed to the TLS peer, never to an id in its body; snapshots carry `hostEpoch`,
  `snapshotSeq`, `eventRevision`, the roster and per-device `ageAtHostMs`. Android adds no protocol of its own.
- **DirectorCapture (S3)**: each device runs the unchanged core recording engine; a room participant reports
  `recordingStarted` acknowledgements (intent id, segment id, `fileZeroHostNs`, wall clock for humans only, preset,
  fps, timescale), heartbeats every 2 s as `jovra.room.device-status/1` reports, segment events and
  `recordingStopped`. Preview stills (every 5 s; 2 s while framing; only at thermal ≤ moderate) are designed but not in
  Room contract v1; A44's still cards ship only after `jovra.room.still/1` lands (F-ROOM-STILL), and until then show
  "Preview unavailable · not in this version". No automatic analysis during capture (Studio SD DirectorCapture).
- **CloudClient (S4)**: demo (in-process fixture transcripts, no network, Sample quotes), test (base URL, issuer and
  publishable key from build configuration, refuses to start without it), live (compiled, disabled until activation).
  OkHttp, upload parts as instructed by the server (`{url, method, headers, expiresAt}`), resumable, Wi-Fi only
  honoured. The quote acceptance and its idempotency key are persisted before the request.
- **StorageProvider adapters**: Device (active), FilesFolder (SAF tree grant; reaches cloud-drive document
  providers), GoogleDrive (wraps the archive; same states), Box and Dropbox `planned`. The iCloud Drive provider is
  iOS-only in the contract and is not shown on Android.
- **Quote UX (screen 57)**, one screen for both apps, as specified in `adaptive-screens.md` A57: a full screen (consent
  is never in a swipe-dismissable sheet) with the QuoteCard bound to the **shipped** `jovra.quote/1` (estimate range
  and spending limit = `capCredits`; if Jon chooses one number, `pricing-matrix-v2.md` §10 Q1, the contract sets
  min = max = cap and the card shows one figure with no screen change); Jon's price toggle (length × film quality ×
  angles) as the drivers of a "What sets the price" **modal bottom sheet**: length as filter chips in a flow row on
  compact width and a single-choice segmented button row on wider windows, a Film quality picker for 4K captures, one
  switch per angle, read-only source minutes and the planning switch mirrored; every change re-quotes. Planning as a
  switch whose consent names both planning services; consent as a checkbox; "Create film" a filled button disabled
  with a reason; two-pane on wide windows with the boundary off the hinge; polite live region for the confirmed price;
  no credit-pack sheet and no Play Billing until the pricing ADR (AD4). The proposed `pricing-matrix.v2.json` and new
  quote fields are the Studio contracts owner's call; Android consumes whatever lands.

### Studio screens 41–60 (Android) mapped to ST21–ST40

| Ref | Android screen | iOS twin | Compact layout | Wide / posture layout | Stage |
|---|---|---|---|---|---|
| 41 | Studio Home | ST21 | Hero, Build your match, angles/styles cards, latest film, lessons | Grid with the same order | S0 |
| 42 | Court setup | ST22 | Court diagram, slot list, Continue | Diagram beside slot details | S0 |
| 43 | Camera lobby | ST23 | Invite card, device rows, "Each phone saves its own video" | Invite beside roster | A2 / S3 (demo S0) |
| 44 | Capture health | ST24 | Primary preview, status rows, Mark, stop one (aged stills after F-ROOM-STILL) | Preview beside roster (landscape) | A2 / S3 (demo S0) |
| 45 | Source import | ST25 | Pickers, source rows, summary, Wi-Fi only | List beside source facts | S0–S2 |
| 46 | Sync desk | ST26 | Sheets per angle and lane | Stills + lanes beside review card, split at hinge | S2 (demo S0) |
| 47 | Multi-angle replay | ST27 | Video, angle strip, point chips | Video beside angles and point chips; tabletop video / controls | S1 one angle, S2 multi |
| 48 | Angle insights | ST28 | Still, observation card, Review cue / Keep for lesson | List beside detail | S0 |
| 49 | Story profiles | ST29 | Five cards, length chips, options, Preview my story | Cards beside options | S1 |
| 50–53 | Coach's Cut, Rally Pulse, Progress Story, Court Memories | ST30–ST33 | Per-profile options and preview | Options beside preview | S1 |
| 54 | Lesson journal | ST34 | List, chips, FAB | List beside lesson | S0–S1 |
| 55 | Tablet lesson workspace | ST35 | Lesson screen | 2 or 3 panes by width | S1 |
| 56 | Tabletop film editor | ST36 | Beat list + sheets | Preview + timeline; tabletop split | S1 |
| 57 | Processing quote | ST37 | Single column + bottom sheet | Summary beside quote | S4 (demo S0) |
| 58 | Background production | ST38 | Job card, stages | Same, wider | S4 (demo S0) |
| 59 | Private film delivery | ST39 | Preview, actions, Include audio | Preview beside details | S1 (local), S4 (cloud) |
| 60 | Studio and watch settings | ST40 | Provider list, watch row, cloud off | List beside detail | S0 |

Copy comes from `design-reference/studio/brief/screens.json` and the adaptive `screen-specs.json`, with Studio copy
rules §0.2. Generated glyphs, dates, QR patterns and photography in references 41–60 are illustrative; the typed specs
and contracts govern (adaptive `visual-review.md`). Screen 60 shows no iCloud row as active on Android.

### Core screens A01–A20 (Android) mapped to S01–S20

Each core screen keeps its iOS content, copy (with the Android copy changes below), states and data bindings from
`screens.md`; the Android structure is:

| Ref | Android screen | Structure on compact | Wide / posture |
|---|---|---|---|
| A01 | Welcome | Mark, headline, Get started, Explore a demo | Centred column |
| A02 | Onboarding | Top app bar with back, linear progress, step content, bottom action bar above the keyboard | Centred 600 dp column |
| A03 | Home | Large top app bar, cards, tiles, chart, Studio card | Two-column grid |
| A04 | Session setup (Record root) | List items, bottom-sheet editors, "Check camera position" | List beside editor pane |
| A05 | Framing | Full screen, bars hidden, preview, checklist sheet, corner taps with loupe | Landscape controls column |
| A06 | Recording | Full screen, REC, save status, scoreboard, Mark, Stop (≥ 64 dp) | Landscape layout |
| A07 | Import and processing | Source tiles (system pickers), stage timeline | List beside stage detail |
| A08 | Library | Search bar, filter chips, cards, Import action | List beside overview |
| A09 | Match overview | Header, metrics, insights, history | Stats beside point history |
| A10 | Replay | Full screen, video, jog strip above gesture inset, transport, point card | Video beside point pane; tabletop split |
| A11 | Shot placement | Court diagram, filters, legend, provenance row | Diagram beside list |
| A12 | Serve Lab | Stats, service box, speed estimate, key moments | Two panes |
| A13 | Stroke Lab | Clips, key moments, contact strip, pose on demand (gated) | Video beside strip |
| A14 | Compare | Stacked videos, sync controls, tools | Side by side; book posture split at hinge |
| A15 | Insights root / practice plan | Focus card, evidence, drills, Explore list (lesson journal, Progress Story, Angle insights) | List beside detail |
| A16 | Progress | Range chips, chart with spoken summary and table, milestones | Chart beside details |
| A17 | Racket Vault | List, active setup, court kit | List beside racket |
| A18 | String journal | Setup card, tensions, logged time, feel, reminders | Two panes |
| A19 | Storage and backup | On this phone card, uninstall note, provider row, queue, retention | Two panes |
| A20 | Settings and privacy | Grouped list; permission rows with consequences | List beside detail |
| N1–N12 | Review deck, checkpoint entry, Share Pack sheet, consent/competition/junior, diagnostics, Space Saver, rally-only controls, pre-flight checklist, court mode/heat, highlight builder, Profile hub, capability detail | As iOS, with bottom sheets for sheets | As iOS two-column where listed |

**Android copy changes** (in addition to the iOS honesty corrections): "Only on this phone" for "Only on this
iPhone"; "Video saved on this phone"; "Open app settings" for "Open iOS Settings"; the Photos row becomes "Choosing
videos · Not needed: you pick each video" and "Saving videos · No permission needed"; the onboarding storage step and
the storage screen add "Uninstalling JOVRA deletes footage kept only on this phone."; "Not included in your phone's
Google backup" for the iCloud backup sentence; "Emulator fixture camera" for "Simulator fixture camera" (debug only).
Brand hygiene is unchanged: no Google Drive, Android or Play logos inside JOVRA screens beyond required system UI.

### Design system (`:designsystem`; AD23)

- Material 3 components with JOVRA's colour roles (ivory, forest, chartreuse/lime, clay) mirrored from the iOS
  roles in light, dark and high contrast; dynamic (wallpaper) colour off; forest capture/replay/editor chrome in both
  themes, as on iOS. The brand font pairing from the iOS foundation where its licence allows Android embedding
  (UNVERIFIED until the ticket checks the licence), otherwise the system font with the same scale.
- 48 dp minimum targets (64 dp capture controls, 76 dp Stop), focus indicators on every interactive element, selection
  by fill + check + weight, markers by shape.
- `ProvenanceBadge`, `StatusPill`, `StateCard`, `DemoBanner`, court diagram (ITF dimensions, centre service line only
  between the service lines and the net), charts drawn in Compose with semantics (no chart library dependency), the
  quote card, angle and status rows.
- Contrast pairs are unit-tested (the iOS `ColorRoleContrastTests` pattern).

### Identity and environments (AD5, AD18)

- Core and on-device Studio need no account. No sign-in on the welcome screen.
- Studio test identity (S4): email one-time codes against the isolated test Auth project, testers pre-provisioned
  (ADR-0022); Credential Manager is used for passkeys and, after its own review, a native Google option for live
  accounts (ADR-0022 says Android "adds email codes and, after its own review, a native Google option").
- Credentials (Studio session tokens) are stored encrypted with an Android Keystore key (CLAUDE.md rule 5 names
  EncryptedSharedPreferences; whether to use it or an equivalent Keystore + AES-GCM store, given the deprecation status
  of the androidx security-crypto library, is decided in the identity ticket; UNVERIFIED here). Drive holds no refresh
  token on the device.
- The UI always shows the mode (Local demo, Test, Connected). Demo and test tokens are rejected by the live gateway by
  construction (issuer pinning, ADR-0022).

### Store, policy and distribution (AD24)

- Target 36 (Play requirement since 2026-08-31, OBSERVED in feasibility §14); edge-to-edge and predictive back
  handled. 16 KB page alignment checked before any native library ships (G-16K; Play blocks unaligned updates from
  2027-02-01, OBSERVED there).
- Data safety form: "no data collected" is the target for core; Play services libraries' own data handling must be
  checked before the form is filed (UNVERIFIED).
- Android developer verification (rolling out from 2026-09-30, global 2027; OBSERVED in feasibility §14): whether
  `adb`-installed debug builds are exempt is UNVERIFIED; the hardware gate checks it on Jon's Pixel.
- Store listing, signing and submission are out of scope until the hardware gates pass (as on iOS).

### Stage contracts (Android)

Status is always reported in separate columns: JVM conformance · Robolectric/Compose · screenshot tests · named
emulator · physical Pixel · physical Galaxy · Wear emulator · paired watch · field six-device · real media render · ML
benchmark · backend test · live · store.

**AND-0 — Start, toolchain, conformance** (fully specified)
- Deliverables: the Android start is recorded (ADR-0024; the ADR-0001 header note is F-ADR-0001) and the Drive
  amendment request (AD16); the Gradle skeleton with
  convention plugins and the Lane A catalogue; `:core` and `:testing`; the CI job `android-core` (JVM only) as a
  required check; an Android section in the developer guide (JAVA_HOME, `-p android`, AVD names, clean hygiene).
- Acceptance: (a) G-RESOLVE: dependency resolution and AAR-metadata checks pass on compileSdk 36; (b) G-CORE for core:
  every `spec/fixtures` case passes, CSVs byte for byte; (c) mutation checks that must fail: replace `pct` with a
  half-even formatter (T01 fails on 1/8), swap a CSV line ending to CRLF (sample CSV fails), drop one fixture from the
  manifest walk (manifest test fails), add an unknown fixture kind (run fails).

**AND-1 — Shell, design system, store, sample, every screen** (fully specified)
- Deliverables: `:designsystem`, `:data`, `:app` shell with five destinations and Navigation 3, the sample content
  installed from the shared fixture, every core screen A01–A20 and N1–N12 and every state of `screens.md` §3 reachable
  in demo by a test intent extra; adaptive layouts per AD15.
- Acceptance: Compose UI tests visit every route and state with accessibility checks (touch targets ≥ 48 dp, labels,
  contrast) at default and maximum font scale, light and dark; Roborazzi goldens at compact (360 and 411 dp), medium
  (fold outer), expanded (fold inner 852 × 883 dp) and large (tablet 1280 × 800 dp) windows, with separating and
  occluding hinge and tabletop variants from the window-testing publisher; state-preservation tests (below); a test that
  no demo screen performs a network request; copy assertions against `screens.json` with the documented changes.

**AND-2 — Capture to correction to export** (fully specified)
- Deliverables: RecordingEngine (CameraX, journal, thermal ladder, recovery), fixture camera support, import, replay,
  scoring, review deck, correction, rally-only, export, Share Pack.
- Acceptance on `jovra_phone_p9_api35` with the video-file camera: setup → framing → record → interruption (home,
  screen off, camera in use) → resume → stop → processing → library; forced process kill mid-segment then the
  recovery scan with decode-to-end; low-storage stop; exported clip start and end within ±1 frame of source timecodes
  on a frame-counter fixture at 30 and 60 fps; overlay score equals the fold at sampled frames; audio stripped by
  default; correction re-renders the overlay. Reported as "emulator, video-file camera"; durability, fps and heat wait
  for the hardware gate.

**AND-3 — Insights, labs, equipment, storage, settings, integrations** (fully specified)
- Acceptance: flows for every screen and state; capability pages reflect AD14; Android benchmark records written by the
  synthetic-video harness for any detector proposed for enabling; shortcuts and Health Connect behind their spikes.

**AND-4 — Drive archive** (specified; starts after the ADR-0008 amendment and Jon's OAuth client)
- Acceptance against the fake Drive: kill and resume at 10/50/99% with no duplicate, expired session, quota block
  without retry storm, revoked access → Needs reconnect, reinstall finds the archive root, Wi-Fi-only policy, checksum
  mismatch never reaches backed up, restore verifies, "Awaiting setup" without configuration; an archive made by the
  iOS fake-Drive transcript restores on Android with identical fold, stats and CSVs. Real Drive: UNVERIFIED until the
  OAuth client exists.

**Studio S0 / A0–A1 (Android)** (fully specified)
- Deliverables: `:studio-core` passing every Studio record, invalid case and vector; Studio sample content;
  DemoCloudClient; the fixture room; `:room-protocol` logic tests; screens 41–60 and every state of `studio-screens.md`
  §3 reachable in demo; entry rows on A03, A09, A15 and N11.
- Acceptance: (a) G-CORE for Studio; (b) Compose UI and Roborazzi coverage of every Studio route and state at the
  same windows and postures as AND-1; (c) no network in demo; (d) the five destinations unchanged; (e) A1 on emulators:
  each JOVRA AVD (phone, fold, tablet, compact 360) renders the Studio fixtures with screenshots, TalkBack labels
  checked, font scale 200%, and state restoration across rotate, fold/unfold (posture actions where the emulator
  supports them) and process death (`adb shell am kill` after backgrounding), with no duplicated job, score or quote.

**Studio S1 (Android)** (fully specified)
- Journey as in the Studio spec's S1, on Android: one session (the synthetic sample video in CI; Jon's old match
  when supplied) → project → points and keepers → profile and length → RulesPlanner → compile → validate → Media3
  render → FilmVerifier → FilmRecord → lesson → Progress Story → save with and without Include audio (each a verified
  artifact) → Prepare for YouTube → delivery screen.
- Acceptance: for each profile, a real MP4 rendered on the emulator passes FilmVerifier (frame count, timestamp grid,
  barcodes, clicks within ±1 output frame, audio sample count, overlay text, Sample badge); the Studio spec's S1
  mutation tests fail as required; original hashes unchanged after cancelled and failed renders; a correction marks
  films stale and a rebuild shows the new scores. Any operation whose Media3 path fails its barcode test stays
  disabled on Android and is reported. Reported as "rendered and verified on the Android emulator from synthetic
  fixtures".

**Studio S2** (specified)
- Deliverables: ProxyNormalizer, anchor extraction, sync sheets and the fold sync desk, multi-angle player, alt-bed,
  multi-angle live/replay, all from files (no pairing).
- Acceptance: the multicam §8.3 tests through the Kotlin port; normalization fixtures match decoded frame IDs 100%.

**AND-W / A3a — Wear bridge, single phone** (specified; core, no Studio stage)
- Deliverables: `:wear-bridge` projecting the phone's own CaptureEngine and EventLog into `jovra.room.watch-bridge/1`
  (the phone is its own host at epoch 1; roster of one), the Data Layer paths of the watch spec, bridge-local echo,
  alert acknowledgement and marks with receipts; the "Paired watch" rows (watch spec WD13).
- Acceptance: G-ROOM (`bridge`, `watch-sample`, `ledger` mark and outbox vectors); a fake Data Layer client test that
  queued delivery is Unknown and an interactive echo makes rows Fresh; G-W-WEARUI and G-W-WEARPAIR-EMU from the watch
  spec. Score commands from the watch are not in this stage (they wait for A2).

**A2 — two-phone JOVRA Room v1** (specified; delivered by the Studio S3 pairing work)
- Deliverables: `:room-transport` (NSD, TLS pin, peer binding to the ledger, hotspot), `:room-protocol` passing G-ROOM,
  the camera lobby (43) and director capture (44) on a real room.
- Acceptance: two-phone room on **real devices**: Jon's Pixel and an iPhone, each as host and as camera: invite,
  approval by the commit-then-reveal code, independent recording, acknowledgement, stale and Unknown states, stop one,
  stop-all request with per-device results, disconnect and rejoin, expired and replayed invites refused, a forwarded
  QR declined three times then revoked, denied camera permission, app backgrounded during start. Emulators prove UI
  logic only.

**A3 — watch with the room and watch commands** (contract and acceptance; after A2)
- Phone-side Wear bridge fed by the room (A3a+room), watch `PointWon`/`Undo` with receipts and conflicts (A3b),
  own-phone stop (A3c), Unknown on unbounded transit, on a real paired Galaxy Watch (gate G-WEARPAIR or physical
  watch).

**Studio S3 / A4** (contract and acceptance)
- Six phones, at least one Android and one iPhone, record a 60-minute session; per-device recovery after forced kills;
  acknowledgement counts; silenced device shown with contact age and still complete locally; stills cadence near
  0.32 Mbit/s for five secondaries (measured, once F-ROOM-STILL lands); thermal, battery and storage warnings;
  six-device sync report per the Studio S3 criterion.

**Studio S4–S5 / A5** (contract and acceptance)
- Android CloudClient against the isolated test backend (the gateway's request/response fixtures replayed on Android
  first); duplicate job requests, redelivered messages and retries create one job, one reservation and one artifact;
  cancellation keeps local sources; Lane B migration; S5 interop list (fixtures byte for byte, mixed real media,
  cross-platform lobby, cross-platform project opening).

## Testing Decisions

- **What a good test is here.** It drives behaviour through one seam (the JVM domain API, the media API, or the app
  through Compose UI tests and Maestro) and would fail if the behaviour broke, whatever the internals. Expected values
  come from an independent oracle: the Python reference, the rules document's worked examples, synthetic-video ground
  truth, the Studio barcode fixtures or a hand-checked literal. No internal collaborator is mocked; fakes exist only at
  the real boundaries listed under Architecture. Mutation checks are part of acceptance: a suite that cannot fail is
  not evidence.
- **Conformance (`:core`, `:studio-core`, `:room-protocol`), CI job `android-core`, required.** JUnit Jupiter 6.1.3
  dynamic tests, one per fixture, on a plain JDK 17 with no Android SDK. Covers every fixture kind listed under "Kotlin
  conformance harness", plus JVM tests of the pure state machines (journal, recovery decisions, thermal ladder,
  processing queue, archive, quote and reservation, render job, room freshness and commands).
- **Android unit (Robolectric 4.17 + Compose UI tests), CI job `android-unit`.** View-model and screen behaviour,
  navigation and back handling (including guarded screens and sheet-first back), permission states through the
  injected `PermissionsCenter`, adaptive pane selection driven by the window-testing publisher (separating vertical
  hinge, occluding hinge, tabletop, compact height), state preservation through `StateRestorationTester`-style
  recreation and saved-state round trips, idempotency on recreation (a test that fails if a recreation re-sends a job,
  quote acceptance, score command or upload), and accessibility semantics (content descriptions, custom actions,
  adjustable ranges, live regions, 48 dp touch targets). Runs at SDK 36 on JDK 21 in CI and at a pinned lower SDK on
  JDK 17 locally (OBSERVED constraint: Robolectric needs JDK 21 for SDK 36; the build machine has JDK 17 and 27 only).
- **Screenshots (Roborazzi 1.76.0).** Every screen and state at the windows and postures named in AND-1, light and
  dark, default and maximum font scale. Goldens are recorded and verified in CI on Linux; local runs compare only.
  The generated references are not pixel oracles: copy assertions, a side-by-side evidence page (reference ↔ our
  screenshot) for human review, then regression against our own approved screenshots (core practice).
- **Instrumented and media tests (JOVRA AVDs only).** Capture with the video-file camera, recovery after a forced
  kill, frame-exact seeking on a frame-counter fixture at 30/60 fps (and 240 fps on import), Transformer exports with
  ±1-frame bounds, the Studio barcode render and verification suite, posture and rotation through device actions where
  the emulator supports them. Evidence names the AVD, profile, image and what it approximates.
- **Maestro flows (local, JOVRA AVDs).** Onboarding; demo entry and removal; setup → framing → record → interruption →
  resume → stop → processing → library; live scoring with undo; replay correction propagating to the overview; review
  deck; export; storage states with the fake Drive; Studio demo journey; fold/unfold and rotate continuity with a
  pending job; process death with an unsaved note.
- **Emulator matrix (created later, one at a time, never touching `OlamyPixel`)** from the installed
  `android-35 google_apis arm64-v8a` image: `jovra_phone_p9_api35` (pixel_9, 411 dp; approximates Pixel 10-class),
  `jovra_fold_p9pf_api35` (pixel_9_pro_fold; inner 2076 × 2152 matches the Pixel 10 Pro Fold inner panel; outer differs
  by about 60 px of height), `jovra_tablet_ptab_api35` (pixel_tablet, 1280 × 800 dp), `jovra_compact360_api35` (custom
  360 × 780 dp; Galaxy S26-class shape, not Samsung firmware). Cold boot, no snapshots, 4 GB data cap. Density
  overrides for 393/412 dp are labelled "density override". The single `resizable` profile may stand in when disk is
  short and is labelled so. Android 16 large-screen behaviour needs G-IMG36.
- **Synthetic-video benchmark (Android).** The same repository generator and ground truth as iOS; the Android harness
  runs the Android HitDetector and any Android detector proposed for enabling and writes Android benchmark records.
  Synthetic results never promote anything to `validated`.
- **Hardware phase, reported separately.** Physical Pixel (Jon has one): capture soak (≤ 3 s lost per crash, 0
  unrecoverable sessions, journal within one frame), 60 fps support, thermal ladder, interruptions of each kind,
  low storage, rotation, volume-key and headset Mark, fold continuity on a Pixel Fold if available. Physical Galaxy
  phone and Galaxy Watch only if Jon has them (UNVERIFIED availability). Real Google Drive after the OAuth client. Two-
  and six-device field runs per S2/S3. Real-footage detector benchmarks.
- **Prior art.** The Python reference and fixtures in `spec/` and `spec/studio/` (the oracles), iOS
  `JovraSmokeUITests` (route visits, target sizes, accessibility audits, screenshot attachments),
  `ColorRoleContrastTests`, the iOS fake-Drive tests (boundary fake pattern), the D8 synthetic-video harness, the
  Studio barcode fixtures and the starter edit-plan validator.

## Out of Scope

- **Excluded with iOS v1 (D10/D11 apply):** ball tracking, automatic bounce maps, automatic stroke classification,
  automatic serve detection and speed, AI point winners, line calls, spin RPM, 3D pose and numeric biomechanics,
  injury or medical claims, tension measurement, string-life prediction, the pitch check, automatic compare sync,
  on-device recap text, Google Picker import, any paywall.
- **Android-specific exclusions in v1:** Play Billing and credit packs (until the pricing ADR); background camera
  recording through a foreground service; Google sign-in for name prefill; Google Assistant App Actions; Android Auto,
  TV and XR form factors; ChromeOS-specific tuning beyond the adaptive rules (it may work, and is not claimed);
  Samsung-specific APIs (DeX tuning, S Pen air actions, One UI widgets); Kotlin Multiplatform shared code (ADR-0001
  rejects it for now); androidx Room or SQLite (ADR-0002); Hilt/KSP/kapt.
- **Wear OS companion app** (references 66–70): its own spec; this spec owns only the phone-side bridge.
- **Studio exclusions until their stages** (as in the Studio spec): music, narration, captions, reframing, Wi-Fi
  Aware, Box and Dropbox integrations, YouTube upload, live cloud activation, model planner on device.
- **Never:** officiating claims, ads or tracking, default training-data sharing, locking or capping a user's video,
  pro-player likenesses, invented footage or metrics, auto-publishing, six simultaneous live streams, a demo token
  accepted by any live API, secrets in the client.
- **Owned elsewhere:** core contracts and validators (`spec/`, `scripts/spec/`), Studio contracts (`spec/studio/`),
  Studio specs, backend docs, ADRs, the iOS app, the Wear OS app.

## Further Notes

### Decisions index

| ID | Decision | Where it lands |
|---|---|---|
| AD1 | Android starts now; ADR-0001 start condition amended by the ADR owner first | Scope; AND-0 |
| AD2 | Studio Android on the same gates S0–S4; S5 list becomes the interop gate | Stage contracts; conflict recorded |
| AD3 | Parity: iOS domain decisions, D1–D12 intents, SD/D-decisions binding | Everywhere |
| AD4 | No Play Billing, ads or analytics in v1; Sample credits only | Out of scope; quote UX |
| AD5 | No sign-in on the welcome screen; core needs no account | A01; identity |
| AD6 | Lane A pins (AGP 9.1.1, Gradle 9.3.1, Kotlin 2.4.20, compile/target 36, min 29/30); Lane B after G-SDK37 | Toolchain |
| AD7 | Navigation 3 with saveable `@Serializable` keys; `NavigationSuiteScaffold` | Shell |
| AD8 | Session/project folders excluded from Android backup and transfer; "Only on this phone"; uninstall warning; "Also save to Movies/JOVRA" | Data store; copy |
| AD9 | Module layout; `:room-protocol` / `:room-transport`, never `:room`; enforced dependency rules | Modules |
| AD10 | CameraX segments behind the ADR-0010 journal; MediaCodec + fragmented-MP4 fallback behind the same interface | Capture |
| AD11 | Emulator video-file camera as the fixture camera; debug-only label | Capture; testing |
| AD12 | Volume keys and headset button → Mark point only, foreground only, switchable | Capture; settings |
| AD13 | Predictive back on; guarded screens opt out of the preview and confirm | Back |
| AD14 | Per-platform evidence: Android shows a platform-dependent capability only with an Android benchmark record | Analysis |
| AD15 | Adaptive policy by window class, height, posture, font scale; per-screen pane rules; state preservation contract | Adaptive |
| AD16 | Drive via `AuthorizationClient`, `drive.file`, shared archive state machine; ADR-0008 amendment needed; AND-4 | Archive |
| AD17 | WorkManager for automatic work; user-initiated data transfer jobs for "Back up now"; `mediaProcessing` for renders | Background |
| AD18 | Keystore-backed credential storage; no Drive refresh token on device | Identity |
| AD19 | Ongoing recording notification; Android 16 live update spike-gated | Capture |
| AD20 | Permission table; never `READ_MEDIA_*`; picker-first local network | Permissions |
| AD21 | TalkBack parity: custom actions, adjustable ranges, polite live regions, chart summaries | Accessibility |
| AD22 | Media3 local film renderer and Android FilmVerifier; each operation enabled only after its barcode test | Studio |
| AD23 | Material 3 with JOVRA roles, dynamic colour off, 48 dp, focus indicators | Design system |
| AD24 | Target 36, G-16K before native libs, data-safety honesty, developer verification check | Store |

### Gates (each a check that can fail; reported separately)

| Gate | Pass condition | Blocks |
|---|---|---|
| G-RESOLVE | Lane A dependency resolution and AAR-metadata checks pass on compileSdk 36 | All Android code |
| G-CORE | `:core` passes every core fixture (CSV byte for byte); `:studio-core` passes every Studio record, invalid case and vector | Any Android conformance claim |
| G-ROOM | `python3 scripts/spec/validate_room.py` passes in CI, and `:room-protocol` passes every `spec/room` record, invalid case and vector (failing on unknown kinds, ops or unconsumed files); the room mutation set (forged issuer, replayed bridge payload, frozen send age) fails as required | A2, AND-W/A3, any room or watch claim |
| G-PANE | The ADR-0025 §8 pane-policy vectors exist (owner: the `spec/` contracts owner; ticket AND-1e drafts them) and the Kotlin pane policy passes them | "Adaptive policy matches iOS" claims |
| G-JDK21 | JDK 21 locally, or SDK 36 Robolectric only in CI | Local SDK 36 Robolectric |
| G-SDK37 | Jon approves the 67 MB android-37.0 platform | Lane B |
| G-TARGET37 | Room transport re-verified with `ACCESS_LOCAL_NETWORK` and the NSD picker | targetSdk 37 |
| G-DISK | ≥ 25 GiB free, or Jon approves reclaiming JOVRA-owned space only (14 GiB free on 2026-10-07, OBSERVED) | G-IMG36, G-WEARIMG, Play image |
| G-IMG36 | API 36 phone image installed | Android 16 large-screen claims |
| G-WEARIMG | Wear OS 6 image (1,138 MB zip) installed | Any Wear emulator evidence |
| G-WEARPAIR | Play Store phone image, companion app, Jon signs in himself | Data Layer emulator evidence |
| G-16K | 16 KB alignment check clean and app runs on a 16 KB image | Shipping pose/face libraries |
| Native UI | Named AVD, build, screenshots, TalkBack, font scale, state restoration across fold/rotate/process death | "Runs on fold/tablet" |
| Hardware: Pixel | Capture soak, 60 fps, thermal, interruptions, Mark inputs, fold continuity (Fold if available) | Capture durability claims |
| Hardware: Galaxy | Galaxy phone/watch runs if Jon has them | Galaxy claims (else "approximated") |
| Two-phone room | Real iPhone + Pixel, both roles | A2 (and every A3 watch-control stage) |
| Six-device field | Six phones, mixed OS, 60 minutes | S3/A4 |
| Drive | Jon's Android OAuth client, project in production | Real Drive claims |
| Pricing ADR | Jon's pricing decision after benchmarks | Any real charge or credit sale |

### Conflicts recorded (not silently resolved)

1. **ADR-0001 start condition.** *Resolved by ADR-0024 (accepted 2026-10-07).* Open bookkeeping: ADR-0001's header note
   (F-ADR-0001).
2. **Studio spec "Android" out of scope S0–S4, port in S5** vs the founder's references 41–60 and the adaptive
   sequence A1 (Android compact Studio UI). This spec puts Android Studio on the same gates; the Studio spec owner
   reconciles (AD2).
3. **ADR-0008 "no Google SDK"** (written for iOS) vs Android Drive authorization through Play services. Needs an
   Android amendment (AD16) before AND-4; no such amendment exists yet (OBSERVED 2026-10-07; F-ADR-0008).
4. **Freshness thresholds.** *Resolved:* ADR-0027 §5 and `spec/room` fix fresh ≤ 5 s, delayed ≤ 15 s, Unknown above
   (three missed 2 s heartbeats land in Delayed). They remain product defaults to benchmark.
5. **Toolchain rows.** `technical-feasibility.md` §14 names compileSdk 37 and BOM 2026.09.00; on this machine that is
   Lane B (toolchain research §0.2). The feasibility doc is not edited here.
6. **CLAUDE.md rule 5** names EncryptedSharedPreferences; the identity ticket checks whether the deprecated androidx
   security-crypto library or a Keystore + AES-GCM equivalent meets the rule (AD18).
7. **Quote contract.** `pricing-matrix-v2.md` §8.6 recommends new quote fields and retiring the v1 class minimums;
   until the Studio contracts owner changes `jovra.quote/1`, Android's quote screen binds the shipped contract (estimate
   range + spending limit) and shows only Sample credits. Stories 292, 293 and 299, AD-Studio "Quote UX",
   `adaptive-screens.md` A57 and `pricing-matrix-v2.md` §8 now describe the same screen (resolved 2026-10-07).
8. **Studio spec still lists Android as out of scope S0–S4.** `studio-v1-spec.md` is not edited here (F-STUDIO-ANDROID);
   AD2 stands until its owner reconciles.

### Review findings (2026-10-07)

A review of this spec against ADR-0024–0028, `spec/room`, `adaptive-screens.md` and `pricing-matrix-v2.md` raised
these findings. Each was confirmed by reading the cited lines (OBSERVED) and fixed here unless noted:

- Background capture (HIGH): confirmed contradiction; resolved for this spec's model (AD13 guard, no background
  camera service, interpretation 4). `adaptive-screens.md` §0.1, §0.3 and A44 were changed to match. iOS parity holds
  (ST24 defines the primary capture as core S06 behaviour).
- Stories copying the uncorrected references (HIGH): fixed (stories 218, 251, 256, 261, 262, 264–267, 273, 295, 301,
  303; Studio screens table rows 47–49; AD15 player row).
- Stale cross-references and unreconciled decisions (HIGH): fixed (sources, AD1, conflicts 1 and 4, the harness
  bullet, G-ROOM).
- Pane rule for compact height and the font-scale rule (HIGH/LOW): fixed in AD15 to ADR-0025; input mode added.
- Play Billing in v1 (HIGH): this spec was already right (AD4, story 297, Out of Scope); `adaptive-screens.md` A57 and
  §4.1 and `pricing-matrix-v2.md` §8 were corrected.
- Quote UX and the price toggle (HIGH): fixed (stories 292–295, 299; Quote UX; conflict 7).
- Dual-provider consent (MEDIUM): fixed in story 294 and A57; the quote contract's single `consent.modelProvider`
  needs per-provider fields from the Studio contracts owner before any S4 cloud-planning ticket (F-QUOTE-CONSENT).
- Story length "Full" (MEDIUM): fixed (story 265 defines it; A49 and C-A6 match).
- Two-phone room stage mapping (MEDIUM): fixed (stage table, stage contracts, gate table: A2 ≠ Studio S2).
- Pairing before watch control and the single-phone Wear bridge (MEDIUM): fixed (A3 after A2; AND-W stage; story 357).
- Room contract details: proof message, code, secret size, stills, clock pings, hotspot (MEDIUM): fixed in the room
  section; stills and clock pings stay out of the contract until F-ROOM-STILL; the hotspot travels in `network`.
- Room conformance gate (MEDIUM): fixed (G-ROOM; three fixture roots; G-PANE for the ADR-0025 §8 vectors).
- ADR-0028 Stage 1 (MEDIUM): fixed (stories 352–356).
- ADR-0008 amendment and the Studio spec's Android scope (LOW): confirmed open; recorded as F-ADR-0008 and
  F-STUDIO-ANDROID in `adaptive-open-findings.md` (owners outside this spec).

None was rejected.

### Interpretations the lead should confirm

1. Android v1 ships core parity before Studio cloud (S4), with Studio S0–S1 screens and local films built on demo
   adapters alongside AND-2/AND-3.
2. Drive is "later" inside Android v1 (AND-4), not deferred past v1; the row shows "Awaiting Google Drive setup" until
   then.
3. Detectors that are `disabled` in the registry stay disabled on Android, and Android does not ship pose or face blur
   until G-16K and an Android benchmark.
4. Recording does not continue in the background on Android v1 (parity with iOS).

### Open questions for Jon

1. **Devices.** You have an Android Pixel. Which model (a Fold?) and Android version? Do you have, or can you borrow, a
   Galaxy S26-class phone and a Galaxy Watch? Without them, Samsung claims stay "approximated".
2. **Disk.** The build machine has 14 GiB free. May we reclaim JOVRA-owned space only, or will you free space, so the
   Wear OS image, a Play Store image and an API 36 image can be installed when their gates come?
3. **Android 37.** May we install the 67 MB android-37.0 platform (Lane B) when the Lane A build is green?
4. **Drive on Android.** When you create the Google Cloud OAuth client for iOS, please add the Android client (package
   name and signing certificate) at the same time.
5. **Device-to-device transfer.** Should a phone-to-phone transfer (setting up a new Android phone) carry JOVRA's
   originals, or should originals move only through your Drive archive?
6. **Headset Mark point.** Is a Bluetooth headset button at the baseline something you would use? It needs a range
   test on your Pixel.

### Domain language (input for `GLOSSARY.md`)

Window size class (compact, medium, expanded, large, extra-large; height compact/medium/expanded) · Posture (flat,
tabletop, book) · Separating hinge / occluding hinge · Pane · Navigation rail / navigation bar · Predictive back ·
Guarded screen · Emulator fixture camera · JOVRA AVD · Lane A / Lane B · Android benchmark record · "Only on this
phone" · Movies/JOVRA copy (a user-owned copy outside JOVRA's custody, never a verified backup).

### Evidence status at the time of writing (2026-10-07)

| Column | Status |
|---|---|
| Android code | None exists in the repository (OBSERVED: no `android/` directory) |
| Toolchain | Chosen; G-RESOLVE not run (UNVERIFIED) |
| Conformance | Not run (UNVERIFIED) |
| Emulator | No JOVRA AVD exists; only another project's AVD is present and is not touched (OBSERVED in the toolchain research) |
| Physical Pixel / Galaxy / watch | Not run |
| Wear OS image | Not installed (OBSERVED) |
| Real media / ML benchmark / backend / live / store | Not run |

### Suggested first tickets (for `to-tickets`)

1. AND-0a: ADR requests (ADR-0001 header note, Drive amendment) to the ADR owner; Gradle skeleton + Lane A catalogue +
   G-RESOLVE evidence.
2. AND-0b: `:core` + `:testing` conformance harness over `spec/fixtures` (G-CORE core) + `android-core` CI job.
3. AND-1a: `:designsystem` + contrast tests; AND-1b: `:data` store, index rebuild, quarantine, backup rules;
   AND-1c: `:app` shell with Navigation 3 and adaptive navigation; AND-1d: sample content and demo routes.
4. S0-A: `:studio-core` conformance over `spec/studio/fixtures` (G-CORE Studio).
4b. ROOM-A: `:room-protocol` conformance over `spec/room/fixtures` (G-ROOM), including the authenticated-peer API.
4c. AND-1e: draft the ADR-0025 §8 pane-policy vectors with the `spec/` contracts owner (G-PANE).
5. AND-2a: RecordingEngine + journal + recovery on the emulator video-file camera.

### Sources

Repository (OBSERVED, read 2026-10-07): `CLAUDE.md`; `docs/handoff/JON-ORIGINAL-PROMPT.md`;
`docs/handoff/adaptive-v3/{CLAUDE-ADAPTIVE-WATCH-PROMPT,START-HERE}.md`;
`.claude/skills/{jovra-adaptive-native-ui,jovra-watch-companion,to-spec}/SKILL.md`;
`design-reference/adaptive/brief/{platform-and-device-plan.md,session-connectivity.md,acceptance-matrix.md,
screen-specs.json,implementation-states.json,watch-snapshot.sample.json,visual-review.md,verification.json}`;
`docs/adr/0001`–`0028`; `docs/spec/{ios-v1-spec,screens,studio-v1-spec,studio-screens,adaptive-screens,watch-v1-spec}.md`;
`spec/README.md`; `spec/studio/README.md`; `spec/room/README.md`; `spec/contracts/capability-registry.v1.json`; `docs/research/android/toolchain-and-devices.md`;
`docs/research/technical-feasibility.md` §13–14, §18; `docs/research/studio/{multicam-sync,pricing-matrix-v2}.md`.

Platform facts are carried from those documents with their original labels and sources (developer.android.com,
Google Maven AAR metadata, kotlinlang.org, Robolectric and GitHub runner-image notes); none was re-fetched for this
spec. Facts labelled INFERRED or UNVERIFIED here must be checked in the ticket that relies on them.
