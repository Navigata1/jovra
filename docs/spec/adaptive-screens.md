# JOVRA adaptive screen specification (references 41–72)

Status: implementation-ready draft for A1 (Android Studio screens 41–60) and A3 (watch screens 61–70); layout study
(iOS foldable 71–72) · Date: 2026-10-07 (revised the same day against ADR-0024–0028, `spec/room`, `android-v1-spec.md`
and `pricing-matrix-v2.md`; see §7a) · Companions: `docs/spec/studio-screens.md` (ST21–ST40, the iOS Studio screens
these Android screens mirror), `docs/spec/screens.md` (core S01–S20), `docs/spec/watch-v1-spec.md` (watch behaviour and
protocol), `docs/spec/studio-v1-spec.md` (Studio behaviour, SD decisions).

**What this is.** One section per adaptive reference: the twenty Android Studio screens (41–60, sixteen phone views
and four fold/tablet workspaces), the ten watch surfaces (61–65 watchOS, 66–70 Wear OS) and the two iOS foldable layout
studies (71–72). Each section gives platform, route and entry, window-class and posture variants, layout, exact copy
(generated-image errors fixed), data bindings with provenance, every state, interactions, accessibility, and the
deliberate differences from the image. §4 maps every Android Studio screen to its iOS counterpart and every iOS core
screen to its Android equivalent. Nothing here edits a core or Studio screen; where this spec recommends a change to a
shared screen it says so and records it in §7.

**Sources, in precedence order.** Jon's words (`docs/handoff/JON-ORIGINAL-PROMPT.md`, all addenda) → `CLAUDE.md` hard
rules → ADRs (ADR-0001 native per platform with shared contracts; 0015–0023 Studio; 0024 Android stack; 0025 adaptive
layout policy; 0026 watch companions and 0027 room trust, both as amended 2026-10-07; 0028 line review) → the shared
contracts (`spec/room` for the room and the watch bridge; `spec/studio`) → Studio decisions (SD…) and core
decisions (D1–D12) → `docs/spec/studio-screens.md` (behaviour, copy and states of ST21–ST40, which the Android screens
share) → the adaptive handoff (`docs/handoff/adaptive-v3/`) and the two skills (`jovra-adaptive-native-ui`,
`jovra-watch-companion`) → the adaptive brief (`design-reference/adaptive/brief/`: `screen-specs.json`,
`implementation-states.json`, `acceptance-matrix.md`, `platform-and-device-plan.md`, `session-connectivity.md`,
`visual-review.md`, `watch-snapshot.sample.json`) → shared fixtures (`spec/studio/fixtures/records/*`, core
`spec/fixtures/sample/*`) → the PNG references in `design-reference/adaptive/screens/` (layout, rhythm and hierarchy
only). Every one of the 32 PNGs was viewed for this spec. They are generated images of fictional people and data; where
an image disagrees with a source above it, the source wins and the difference is listed.

**Evidence labels.** OBSERVED (read in a cited source or measured on this machine on 2026-10-07), INFERRED (a design
conclusion, or documented API behaviour not re-read today), UNVERIFIED (needs a device, emulator run, account or test
that has not happened). Every screen here is design. `implementation-states.json` gives all 32 the same state:
"Generated reference; native implementation unverified" — gate A1 for 41–60, A3 for 61–70, "A1 adaptive study" for
71–72; metric gate A5 for 48, 63 and 68.

---

## 0. Conventions for every adaptive screen

### 0.1 Android shell, destinations and routes

- **Five destinations, always**: Home · Sessions · Record · Insights · Profile. Studio never becomes a destination and
  no workspace renames, replaces or adds a destination (SD1; implementation-states note for 47, 55, 56).
- **Chrome comes from the window, not the device.** `NavigationSuiteScaffold` (material3-adaptive-navigation-suite)
  draws a bottom `NavigationBar` when the window width class is Compact, and a `NavigationRail` at Medium width and
  above, using `currentWindowAdaptiveInfo()` (`toolchain-and-devices.md` §4.1). The selected item uses the Material
  tonal pill indicator. The Record item's icon is the brand's chartreuse "+" disc (parity with the core iOS tab glyph,
  core S04 note), rendered as the item's icon inside the bar or rail — never a floating action button straddling the
  bar, which would not survive the bar→rail switch.
- **Selected destination** = the stack that pushed the screen (Home for Studio Home flows, Insights for lessons and
  insights, Profile for settings), as on iOS.
- **Navigation 3 back stack.** One `@Serializable NavKey` per route, mirrored from the iOS route names so the two apps
  share vocabulary: `StudioHome`, `StudioFilms`, `BuildMatch(projectId?)`, `CameraLobby(projectId)`,
  `DirectorCapture(projectId)`, `SourceImport(projectId)`, `Sync(projectId)`, `ProjectPlayer(projectId, filmId?)`,
  `AngleInsights(projectId, observationId?)`, `StoryModes(projectId)`, `StoryProfile(projectId, profileId)`,
  `ProgressStory(scope)`, `LessonJournal`, `Lesson(lessonId)`, `Storyboard(planId)`, `Preflight(jobDraftId)`,
  `Job(jobId)`, `Film(filmId, version?)`, `StudioSettings`.
- **One key per task, layout chosen at render time.** iOS has separate phone and iPad routes for sync and storyboard
  (`syncReview`/`syncDesk`, `storyboardList`/`storyboard`). On Android a window can change class mid-task (unfold, split
  screen, rotate), so `Sync(projectId)`, `Storyboard(planId)`, `ProjectPlayer(...)` and `Lesson(lessonId)` are single
  back-stack entries whose layout is chosen from the current window on every composition. Changing layout never
  changes the back stack.
- **Focused routes** hide the navigation suite in every window class: `DirectorCapture` (44) and `Storyboard` (56).
  `ProjectPlayer` (47) hides it at Compact width (full screen, as iOS) and keeps the rail at Medium+ unless the player
  is in its own fullscreen mode. Focused routes have a top-start Close/Up control ≥ 48 dp with a content description
  ("Close Match Broadcast").
- **System back and predictive back.** Back pops the Nav3 stack; sheets close first; a guarded screen intercepts back
  with `PredictiveBackHandler` and opts out of the preview: editors with unsaved edits (55, 56) show "Discard
  changes?", and a recording screen (44, and core capture) shows "Stop recording?" with "Keep recording" as the default
  (android-v1-spec AD13). Target 36 enables predictive back by default (OBSERVED in `toolchain-and-devices.md` §4.1).
  There is no background recording in v1: leaving the app (home, recents, screen off) closes the segment with a gap,
  exactly as on iOS (android-v1-spec "Capture"; ST24 is core S06 behaviour).
- **Edge to edge.** `enableEdgeToEdge()`; content respects `WindowInsets.safeDrawing`; bottom actions sit above the
  gesture inset; video surfaces may draw behind the status bar only on focused routes.
- **System pickers only.** Video: Photo Picker (`PickMultipleVisualMedia`, video only, up to 6) and the document picker
  (`OpenMultipleDocuments` for `video/*`); folders: `OpenDocumentTree`. No storage permission is requested for import.
  Files are copied in by the core ImportPipeline.
- **Permissions** are requested in context with an explainer first (ST §2 A1): camera, microphone, notifications
  (`POST_NOTIFICATIONS`, API 33+), and nearby-devices/local-network only when joining or hosting a room
  (`NEARBY_WIFI_DEVICES` on Android 16 opt-in; `ACCESS_LOCAL_NETWORK` only if targetSdk moves to 37, gate G-TARGET37;
  the NSD system picker path needs neither — `multicam-sync.md` §2.4). Denied → the consequence in words and "Open
  settings" (app details).

### 0.2 Window classes, panes and posture

Width classes (dp): Compact < 600 · Medium 600–839 · Expanded 840–1199 · Large 1200–1599 · Extra-large ≥ 1600. Height
classes: Compact < 480 · Medium 480–899 · Expanded ≥ 900. Values come from the resolved `WindowSizeClass` API at runtime
(material3-adaptive 1.2.0 adds Large/Extra-large, OBSERVED in its release notes per the toolchain research); the
numbers here are for reasoning and tests, never hardcoded into routing.

| Condition (evaluated on every window change) | Panes | Notes |
|---|---|---|
| Width Compact | 1 | Sequential flow; secondary content in bottom sheets |
| Height Compact, width Medium or wider | at most 2 (ADR-0025 §3) | The player keeps priority: video screens use 1 pane with supporting panels as sheets; other screens may use 2. A wide-but-short landscape phone (923 × 411 dp) is up to two panes plus rail |
| Width Medium/Expanded and height ≥ Medium | 2 | list/detail or content + supporting pane (Medium width: 1, or list/detail 2) |
| Width ≥ Large and height ≥ Medium | up to 3 | Only screens that list three (46, 55) |
| Font scale ≥ 1.5 (or Dynamic text equivalent) | one fewer pane than above, minimum 1, unconditionally (ADR-0025 §3) | Large text needs width |
| Separating vertical hinge (book posture or flat with `isSeparating`) | split exactly at the hinge bounds | No text, control or video edge inside the hinge rectangle |
| Horizontal hinge, half-opened (tabletop: `windowPosture.isTabletop`) | video/player in the top half, controls in the bottom half | Only screens with a player (44, 47, 56); others treat it as a gutter |
| Occluding hinge | gutter of the hinge width | Panes never span it |

Reference profiles (OBSERVED in the installed SDK device definitions, `toolchain-and-devices.md` §2): `pixel_9` 411 ×
923 dp (Pixel 10-class approximation); `pixel_9_pro_fold` outer ≈ 443 × 994, inner ≈ 852 × 883 (the inner panel matches
the Pixel 10 Pro Fold inner 2076 × 2152 px exactly; the outer differs by 60 px); `pixel_tablet` 1280 × 800;
`jovra_compact360` 360 × 780 (smallest compact; Galaxy S26-class shape, not Samsung firmware). Widths 393 and 412 dp
are density-override checks, labelled as such.

### 0.3 Preserved-state contract (Android; the iOS fold studies follow the same table)

| State | Owner and mechanism | Survives | Never |
|---|---|---|---|
| Back stack, selected destination | `rememberNavBackStack` of serializable keys | rotation, fold/unfold, split screen, process death | reset to a destination root on resize |
| Selected project, session, lesson, source, angle, profile, plan version | NavKey arguments + `SavedStateHandle` | all of the above | inferred from the layout |
| Playhead (match clock µs), rate, Film/Angles mode | ViewModel + `SavedStateHandle`, written on pause, on `onStop` and every 1 s while playing | all; after process death the player restores **paused** at the saved time | auto-play after restore |
| Unsaved text and edits (lesson notes, caption, drill counts, storyboard edits, slot choices) | draft documents in the project store (atomic JSON, ADR-0002), debounced 500 ms, plus `rememberSaveable` for the focused field | all, including process death | discarded by a layout change |
| Scroll position, open sheet, expanded section, tab within a screen | `rememberSaveable` / `rememberLazyListState` | rotation, fold, split screen | — |
| Command and job identities (quote acceptance idempotency key, render job id, room command ids, watch command ids) | written to the job store / CommandLedger **before** the network call | all | re-sent because of recomposition; a layout change only re-renders |
| Local capture segments | CaptureEngine journal (ADR-0010); the capture screen handles size, orientation and posture changes without Activity recreation, so the camera is not torn down by a resize (android-v1-spec "Capture") | resize, rotation, fold/unfold while the screen stays in front; process death leaves closed segments the recovery scan decodes | claimed to survive a camera or display switch, leaving the app, or process death: if the platform interrupts capture, the segment is finalized, a Gap is recorded and the UI says so (§1 A44). UNVERIFIED until hardware |
| Remote status (room devices, watch bridge) | last snapshot with its acceptance time | shown after restore **as Unknown** until renewed | shown as fresh after process death |
| Consent checkboxes on a quote | `SavedStateHandle` keyed by quote id | rotation, fold | carried to a new quote or past expiry |

A layout change must never submit a job, add a point, place a charge or stop a recording (acceptance matrix row 1).

### 0.4 Copy rules

`studio-screens.md` §0.2 applies unchanged (brief wins over pixels; provenance words; "Mark point", "point", "film";
money; no model names; time formats; contact only as text). Android substitutions, applied wherever ST copy is reused:

| iOS wording | Android wording |
|---|---|
| this iPhone / on this iPhone | this phone / on this phone |
| Open iOS Settings | Open settings |
| Photos (PhotosPicker) | Photos (the system photo picker) |
| Files (document picker) | Files |
| Save to Photos | Save to device |
| On this iPhone (provider) | On this phone |
| iCloud Drive (provider) | not shown (fixture `platforms.android: false`) |
| Sign in with Apple | the Credential Manager sign-in sheet (A12 equivalent; tester profile in demo) |
| Live Activity / Smart Stack | an ongoing notification while the capture screen records in front (AD19), progress-style where available; never a background recording |

Recurring image errors fixed on every Android screen (listed once here; each section lists only its own extras):
iOS-style status bars on Android references (43, 44, 45, 48, 53 draw iOS signal/battery glyphs — the system draws the
real status bar); taglines not in the brief ("Capture. Analyze. Share.", "A better game tomorrow" kickers, "Play.
Analyze. Improve.") are removed; "JOVRA TENNIS" / "JOVRA STUDIO" lockups become the standard lockup with a "Studio"
kicker where a lockup appears at all; the brand never appears painted inside footage (court windscreens in 44, 46, 47,
48, 50, 51, 56, 57); the Sample chip's cloud-upload glyph becomes the dashed Sample badge; trailing JV avatars are
removed (Profile is a destination); photographs become synthetic sample frames in demo and the player's own frames in
use (ADR-0012); Record drawn as a raised FAB becomes the standard destination item (§0.1).

### 0.5 State vocabulary

Core §0.3 and Studio §0.3 apply (Local demo, Cloud unavailable, Planned, Stale, Verifying, Needs review, No coverage,
Awaiting acknowledgement, Unsupported (not yet)). Adaptive additions:

| State | Meaning | Treatment |
|---|---|---|
| **Layout changed** | window class, posture or hinge changed while on the screen | same content and selection in the new layout; no toast; focus moves to the same element |
| **Restored** | process recreated | drafts and playhead restored; remote status Unknown until renewed; video paused |
| **Fresh / Delayed / Unknown** | receiver-derived freshness of a remote device (watch spec, FreshnessClock) | Fresh: age only ("heard 1 s ago"); Delayed: "Delayed · heard 9 s ago"; Unknown: "Unknown · heard 18 s ago" + "May still be recording" |
| **Interrupted** | the OS interrupted local capture (call, camera switch, thermal) | "Recording interrupted · 0:03 gap" + "Resume"; saved segments kept |

### 0.6 Accessibility baseline (Android)

- Touch targets ≥ 48 × 48 dp (`minimumInteractiveComponentSize`); capture controls ≥ 64 dp, Stop 76 dp (parity with
  core S06).
- TalkBack: every control has a content description; values use `stateDescription`; groups merge descendants where the
  iOS spec makes one element; headings marked with `semantics { heading() }`; one heading per pane.
- Font scale to 200 % without truncated controls; panes reduce per §0.2.
- Time surfaces (scrubbers, sync lanes, storyboard timeline) are adjustable via custom accessibility actions "Next
  point", "Previous point", "Next frame", "Previous frame"; the value reads time, point and state.
- Live regions: polite for status changes (acknowledgements, receipts, stage changes, price updates); never per-second
  countdowns (only at 5, 1, 0 minutes).
- Reduced motion: when animator duration scale is 0 or "Remove animations" is on, no cross-fades, number rolls or
  shake previews; Rally Pulse previews the clean version (SD17).
- Meaning never by colour alone: state words and shapes everywhere (Studio §0.4).
- Keyboard and mouse on tablets/folds: arrow keys, Space play/pause, J/K/L rate, Enter to confirm in focused dialogs,
  visible focus indicators.

### 0.7 Sample data on Android

Android renders the same Studio sample records as iOS (`spec/studio/fixtures/records/*`, ST §0.6) so both apps show the
same oracle values. Values that appear in an Android image but not in a fixture are illustrative and are corrected per
section. All sample surfaces carry a visible Sample label; sample media is synthetic.

---

## 1. Android Studio screens (references 41–60)

Each section: Mirrors · Platform and window · Route and entry · Window variants · Layout · Copy · Data bindings ·
States · Interactions · Accessibility · Deliberate differences from the image. Where a state's copy is identical to
the mirrored ST section (after §0.4 substitutions) the table says "as STnn" and names the state.

---

### A41 Studio Home (reference 41; mirrors ST21)

**Platform and window.** Android phone, compact portrait; all classes supported.

**Route and entry.** `StudioHome` pushed on the Home stack from the Home screen's StudioEntryCard; also from a "film
ready" notification (→ A59) and from A60's Up. Home selected.

**Window variants.**
- Compact: single column, bottom bar.
- Medium/Expanded: rail; content in a 720 dp max column; hero and fact tiles side by side; Latest film and Lessons as
  two columns at Expanded.
- Fold inner (≈ 852 × 883): two columns split at the hinge when separating (hero + tiles start pane; Latest film +
  Lessons end pane).
- Compact height (landscape phone): one column with rail; hero image height capped at 40 % of the window.

**Layout (compact).**
1. Top app bar: Up arrow ("Home"), title area empty, action icon "Studio settings" (gear) → A60.
2. Lockup (40 dp) with a "Studio" kicker.
3. Headline (display style): "Your game, made into a story."
4. Optional banner (demo / cloud unavailable / last job failed; States).
5. EditorialCard hero with the latest film's opening frame: "Build your match." and a filled chartreuse button "Build
   your match" with trailing arrow.
6. Two StudioFactTiles: the angle tile per build stage ("1" / "Angle" / "One phone today"; S2 "6" / "Angles" / "Add
   angles from files"; S3+ "6" / "Angles" / "Up to six phones"); "5" / "Story styles" / "From lessons to memories".
7. Section header "Latest film" + text button "View all".
8. FilmCard: 16:9 frame with duration "04:18" and play glyph, "Jon vs Alex", "Court Memories", Sample badge "Sample
   project", optional status line.
9. Section header "Lessons this month" + "View all".
10. LessonRow: frame, "Oct 7", "Serve rhythm", "3 clips", status pill "Reviewed".

**Copy.** As ST21 (Layout, States) with §0.4 substitutions.

**Data bindings.**

| Element | Fixture | Source | Provenance |
|---|---|---|---|
| Hero frame | opening keeper frame of the Court Memories sample film | newest `FilmRecord` → EDL first live segment | Sample in demo |
| Angle tile | per stage | `StudioCapabilities.maxAngles`, `pairing` | not a stat |
| 5 story styles | 5 | profile count of `story-profiles.v1.json` | not a stat |
| Latest film | Jon vs Alex · Court Memories · 04:18 | newest ready/verifying `FilmRecord` | Sample in demo |
| Lesson | Oct 7 · Serve rhythm · 3 clips · Reviewed | `LessonJournal.lessons(inMonthOf: today)` (`lesson.2026-10-07.json`) | Reviewed when all notes reviewed |

**States.** As ST21: No films (StateCard "Your first film starts with one match." / "Choose a session you've recorded,
or explore the sample project." · "Choose a session" · "Explore the sample"), First session (NextStepRow "Make a film
from Oct 6 · Jon vs Alex"), Local demo (banner "You're exploring the Studio sample." + "Remove sample"), Cloud
unavailable ("Cloud production isn't available right now. Films made on this phone still work."), Last job failed
("Your Court Memories film didn't finish. Your videos are safe." · "See what happened" · "Try again"), Film verifying
("Checking every frame…"), Stale ("Made before a correction"), No lessons (NextStepRow "Start a lesson journal"),
Loading (placeholders after 300 ms), angle-tile stage variants. Adaptive: Layout changed, Restored (scroll position
kept).

**Interactions.** Build your match → A42. FilmCard → A59 (ready) or A58 (in progress). View all → `StudioFilms`.
LessonRow → A55 (`Lesson`). Long-press FilmCard → dropdown menu: Play, Save film, Show project, Delete film (→ delete
scope sheet). Gear → A60.

**Accessibility.** Reading order as ST21; tiles read their stage label ("One camera angle in this version", "5 story
styles"); FilmCard "Jon versus Alex, Court Memories film, 4 minutes 18 seconds, sample project"; tiles stack at font
scale ≥ 1.5.

**Deliberate differences from the image.**
- Tagline "Capture. Analyze. Share." removed; "A better game tomorrow" kicker removed (§0.4).
- Tile captions "Multiple perspectives" / "From highlights to training" → the stage caption / "From lessons to
  memories" (ST21).
- Lesson card "Footwork Fundamentals · Move better, play longer" → the fixture lesson Oct 7 · Serve rhythm · 3 clips.
- Raised Record FAB and trailing avatar → standard destination item and settings action (§0.1, §0.4).

---

### A42 Build your match (reference 42; mirrors ST22)

**Platform and window.** Android phone, compact portrait; forest surface in both themes (the reference's dark
treatment is kept).

**Route and entry.** `BuildMatch(projectId?)` pushed from A41 or Home. Home selected (the image's Record selection is
corrected). Creates a draft project on first change (discarded after 7 days without a source, ST22).

**Window variants.**
- Compact: diagram full width (aspect 1 : 1.2), legend and rows below, bottom action.
- Medium+: diagram in the start pane, rows and action in the end pane.
- Fold inner: the same two panes split at the hinge.
- Compact height: diagram scaled to fit the height beside the rows (two panes even at compact height, because the
  diagram is a picture, not a reading pane).

**Layout (compact).**
1. Top app bar: Up; trailing Sample badge "Sample setup" in demo.
2. Headline "Build your match." Supporting text "Start with one camera. Add up to six."
3. CourtPlacementDiagram from `CourtGeometry` (exact ITF doubles court: baselines, doubles alleys, singles sidelines,
   service lines, centre service line only between the service lines and the net, net), with six SlotMarkers outside
   the lines: 1 near baseline centre, 2 far baseline centre, 3 near-left corner, 4 near-right corner, 5 far-left
   corner, 6 far-right corner; view cones; state by shape (filled = assigned, outline = empty, ring = needs attention).
4. Legend: "1 Primary · 2–6 Optional".
5. List item "Primary angle" · "Baseline" · mini diagram · chevron.
6. List item "Additional angles" · "5 available" · chevron.
7. Info card: "Keep cameras outside the playing area."
8. Bottom action (filled, chartreuse): "Continue" with arrow.

**Copy.** As ST22: slot names "Baseline" (1, Primary), "Far baseline" (2), "Near left" (3), "Near right" (4), "Far
left" (5), "Far right" (6); capture sheet "How will you capture?" · "Record now with this phone" · "Invite other
phones" · "Use videos I already have"; placement tip "Mount phones high and behind the fence, landscape, the whole court
in view. 60 fps keeps slow replays clean."

**Data bindings.** Slot states ← `StudioProject.slots`; "5 available" = 5 − assigned optional slots; capability
warnings ← joining device `preflight` (S3) or source manifest. No provenance (not a stat).

**States.** As ST22: One angle; Occupied role ("Camera 3 is already Alex's phone." · "Replace" · "Choose another
slot"); Unsafe placement hint ("Camera 5 can't see both baselines. Move it back or higher."); Camera capability
unavailable ("Can't record 60 fps · 30 fps will work, without clean slow replays" / "Can't record 1080p"); Pairing not
in this build ("Coming in a later update — record on each phone and add the videos here."); Sample. Adaptive: Layout
changed (slot selection kept), Restored (draft slots kept).

**Interactions.** Tap a SlotMarker or list item → slot bottom sheet (A21: "This phone", "A recording in my library",
"Invite a phone" [S3], Remove). Continue → capture bottom sheet (A22) → core Session setup (Record), A43 (S3) or A45.
Selection haptic on slot change.

**Accessibility.** Diagram is one container with six buttons ("Camera 1, primary, near baseline, assigned to this
phone"); court drawing decorative; legend read once.

**Deliberate differences from the image.**
- "JOVRA TENNIS" lockup → Up arrow + Sample badge; Record destination selected → Home.
- Subtitle "One camera is enough." → "Start with one camera. Add up to six." (ST22 brief line; same meaning, matches iOS).
- Two-column legend "Primary camera · Required / Optional cameras · For more angles" → the single legend line plus the
  two list items (the list items carry the actions; "Required" reads as a rule when one camera is the whole point).
- Clay court fill → neutral court drawing (surface is not known; colour is not data).

---

### A43 Camera lobby (reference 43; mirrors ST23) [S3; demo from S0]

**Platform and window.** Android phone; host and guest variants.

**Route and entry.** `CameraLobby(projectId)` pushed from A42's capture sheet ("Invite other phones"). Guests reach the
guest variant from Record → "Join a match" scanner or by typing a code. Home selected. Before S3, live builds show the
Unsupported state; demo shows the fixture room.

**Window variants.**
- Compact: code card above the camera list.
- Medium+: code card start pane, camera list end pane.
- Fold inner: same split at the hinge.
- Compact height: two panes with the QR scaled to ≥ 160 dp (scannable) or the code text only, with "Show QR" button.

**Layout (host, compact).**
1. Top app bar: Up, title "Camera lobby"; Sample badge "Sample setup" in demo.
2. Supporting headline "Bring every angle together."
3. JoinCodeCard (EditorialCard, forest): kicker "Invite a camera"; "Join this match"; body "Scan with JOVRA on the other
   phone, or type the code."; a real generated QR (payload `jovra-room:1:…`, handled only by the in-app scanner);
   kicker "Match code"; "JVR-482" (monospaced, letter groups); "Expires in 10 min" (live countdown); slot line "For
   Camera 3 · Corner left" (dropdown to change slot); tonal button "New code" and text button "Stop inviting".
4. Section header "Cameras".
5. CameraSlotRow × n: thumbnail (latest still with its age, or the slot's mini diagram), "Camera 1", device name as
   entered ("Jon's iPhone"), slot chip ("Primary" / "Far baseline" / "Corner left"), status ("Ready" / "Waiting" /
   "Needs attention" + reason), chevron.
6. Dashed AddSlotRow "Add another angle" · "Camera 4 – 6".
7. Section header "Watch" (shown only when this phone has a paired watch with the JOVRA app): row "Paired watch" ·
   role "Status only" (or "Status and marks" / "Status, marks and score") · "Last updated 2 s ago" (watch bridge
   freshness, Fresh / Delayed / Unknown words) · chevron → watch abilities sheet.
8. Info card (phone symbol): "Each phone saves its own video."
9. Bottom action "Check camera setup" → preflight bottom sheet (A2a) → "Go to capture" → A44.

**Layout (guest).** Card "You're Camera 2 · Far baseline" with the host's name, the guest's own preflight checklist,
"Waiting for Jon to start", and tonal button "Start recording on this phone" (always available).

**Copy.** As ST23 (device sheet, remove confirmation, join request with 6-digit device code "Check this code on that
phone: 482 913" · "Codes match · Allow" · "Decline"). Watch abilities sheet (new): title "Your watch in this match";
switches "Show camera status" (on, locked on), "Mark for review" (on when this phone may mark, i.e. it holds marker,
scorer or capture-controller; hidden for a viewer), "Score from watch" (off; enabled only when this phone is the
scorer), helper "Your watch can never stop other cameras." The sheet only narrows this phone's own rights (ADR-0026 §6
as amended; `participant.watchCommandTypes` in the bridge payload). The join request's code is the commit-then-reveal
verification code (ADR-0027 §3 as amended); after three declines the invitation stops working ("This code was declined
too many times. Make a new code.").

**Data bindings.**

| Element | Source |
|---|---|
| Code, QR, expiry | `RoomTransport.invite(slot)` (≤ 10 min, one slot, one use; `camera-invite.json` in demo) |
| Rows | room roster + `preflight` messages, each with its age |
| Ready | preflight passes (camera permission, preset supported, space ≥ planned minutes, battery ≥ 20 % or charging, thermal ≤ fair) |
| Watch row | WatchBridge pairing state + last successful echo age (watch spec) |

**States.** As ST23: Host / Guest; Join request; QR expired ("This code expired." + "New code"; guest "This code
expired. Ask Jon for a new one."); Invite revoked; Role full; Reconnect ("Reconnecting…" with age; guest banner
"Reconnecting to Jon's phone. Recording here isn't affected."); Permission denied (StateCard "JOVRA can't find nearby
phones." / "Allow nearby devices in settings, or record on each phone and add the videos later." · "Open settings" ·
"Record independently"); Storage / thermal warning; No network; Unsupported (before S3); Sample. Acceptance-matrix
states: Expired/replayed invite → refused, nothing exposed; Wrong host/session/epoch or arbitrary QR endpoint →
refused ("This code isn't for this match."). Watch states (new): watch paired but app not installed ("Install JOVRA
on your watch" → opens the watch's companion store page via the OS); watch Unknown ("Watch not updated for 40 s").
Adaptive: Layout changed (code and countdown continue), Restored (an unexpired code is shown again only if the room
service still holds it; otherwise "This code expired.").

**Interactions.** Slot dropdown changes the code's slot (old code invalidated). Row → device bottom sheet. Swipe row →
Remove (with confirmation). "Check camera setup" never starts recording. Watch row → watch abilities sheet.

**Accessibility.** QR content description "Join code J V R 4 8 2, expires in 10 minutes"; code text spelled by
character on request; countdown announced at 5, 1 and 0 minutes; status changes polite.

**Deliberate differences from the image.**
- "Connect and start recording." / "Scan this code on your other devices to join this session." → ST23 copy (phones
  join camera slots; joining does not start recording).
- "SESSION CODE" → "Match code"; decorative QR → real expiring one-slot code.
- "Connected devices" → "Cameras"; row slots "Corner" → "Corner left" (slot name).
- "Paired accessories · Paired watch · Status only · Conneced" → section "Watch" with the role and a freshness age
  instead of "Connected" (typo fixed; "Connected" is replaced because a bridge can be paired yet stale). This row is
  new relative to ST23; recommended for ST23 too (§7 C-A3).
- "Check setup" → "Check camera setup"; footnote "Sample setup." becomes the Sample badge.
- iOS status bar and Home-selected FAB → system bar and standard Home item.

---

### A44 Director capture (reference 44; mirrors ST24) [S3; demo from S0]

**Platform and window.** Android phone, portrait and landscape; focused route (navigation suite hidden); forest in
both themes.

**Route and entry.** `DirectorCapture(projectId)` from A43 "Go to capture". The primary phone's capture is core Live
capture behaviour (segments, journal, heat ladder, court mode, ScorePad) owned by the core CaptureEngine while this
screen is in front, plus the Studio panel. There is no background recording in v1.

**Window variants.**
- Compact portrait: video on top, stills carousel, device rows, controls at the bottom.
- Landscape / compact height: video start (fills height), stills and rows in an end column, controls on the end edge.
- Fold tabletop (`isTabletop`): video in the top half, rows and controls in the bottom half; nothing in the hinge band.
- Fold inner flat / tablet: video start pane, rows end pane.
- Capture continuity across fold/unfold or rotation: the screen handles the change without Activity recreation, so the
  camera keeps its session; if the OS switches or interrupts the camera, the segment is finalized, a Gap is recorded
  and the Interrupted state shows (UNVERIFIED until hardware; never promised).

**Layout (portrait).**
1. Compact header (ivory on forest): recording pill "● REC 12:34", kicker "Studio capture", overflow "More".
2. Primary video surface (16:9) with framing guides, chip "Primary · Live" and "Camera 1 · Baseline", bottom-end chip
   "No score" until the first point, then the live derived scoreboard overlay.
3. SecondaryStillCards (horizontal carousel when more than two): still image, "Camera 2 · Preview", "8 s ago";
   "Camera 3 · Preview", "12 s ago". **Only after `jovra.room.still/1` lands** (stills are not in Room contract v1;
   `adaptive-open-findings.md` F-ROOM-STILL); until then each card reads "Preview unavailable · not in this version"
   and the device rows carry the status.
4. Header line "Recording on 3 of 3 phones" (acknowledged `recordingStarted` for this start intent) and, beneath, the
   freshness basis "Status heard in the last 5 s: 2 of 3" when any device is Delayed or Unknown; supporting text
   "Last-known status; recordings may continue."
5. DeviceHealthRow × n: camera icon, "Camera 1", "Recording · Baseline", battery "78%", storage "2 h 10 min left",
   heard age ("heard 1 s ago"), chevron → device bottom sheet (Stop this phone, Details; "Request a fresh still" only
   after F-ROOM-STILL).
6. Bottom controls: "Mark point" (64 dp), Stop disc (76 dp), "More" (ScorePad, court mode, checkpoint).
   "Saved through 12:34" under the controls.

**Copy.** As ST24 (Stop bottom sheet A3: "Stop this phone" / "Stop all cameras (3)" / "Keep recording"; "Waiting for 2
phones to confirm they stopped…"; "All 3 phones stopped. Their videos are on each phone — add them in Choose the
footage, or they'll arrive when the phones reconnect."). Freshness rows use the shared vocabulary: "Recording 12:33 ·
heard 2 s ago"; "Delayed · heard 9 s ago"; "Unknown · heard 18 s ago · may still be recording" (§7 C-A1 aligns ST24).

**Data bindings.** REC time ← primary CaptureEngine; Recording on n of m ← acknowledgement set (only fresh Recording
reports count; enrolled = the room roster, so a camera with no row counts as Unknown); still ages ← the future
`jovra.room.still/1` chained age (F-ROOM-STILL); battery/storage/heat ← `heartbeat` (2 s) with age; freshness ← host-side age (Fresh ≤
5 s, Delayed ≤ 15 s, Unknown above; proposal defaults); score ← core fold of the primary's live events (Manual).

**States.** As ST24: Missing acknowledgement ("Camera 3 · Not confirmed"; banner "Camera 3 hasn't confirmed it's
recording. Start it on that phone."; count excludes it); Device disconnected (row "Unknown · heard 0:42 ago · may still
be recording"; never "Stopped"); No microphone ("Video only · no microphone"); Unavailable preview ("Preview
unavailable" + reason); Low battery / space; Interruption (primary banner "Recording resumed · 0:12 gap"; secondary row
"Gap · 0:12 (call)"); Host exits (guests: "Jon's phone left the match. Keep recording; stop when the match ends.");
Court mode ("Recording on 3 of 3 phones"); Sample ("Sample capture" chip). Acceptance-matrix states: camera reports
Recording but receiver hears nothing (elapsed frozen, Unknown label with age); stop one/all partial failure (per-device
"Stopped" / "Didn't confirm" / "Unknown" lines, no blanket success); start with permission denied or phone backgrounded
(that row "Not recording · needs the phone unlocked" — never a fictitious Recording); host/network lost (local
recording continues; "New room · reconnecting" on recovery with a new epoch). Adaptive: Interrupted by display or
camera switch ("Recording interrupted · 0:03 gap" + "Resume"); Restored after process death (the recording stopped when
the process died; the recovery scan decodes the closed segments, the screen shows "Recording ended · saved through
12:34" from the journal, a Gap is recorded, and the player starts a new recording deliberately; the room shows this
phone Unknown until it reports again).

**Interactions.** Mark point → core Mark (a `MarkForReview` room command with a receipt). Tap a still → request a
fresher still (rate-limited; after F-ROOM-STILL). Stop → Stop bottom sheet (stop-all needs a second, deliberate tap).
System back → the guard "Stop recording?" ("Keep recording" default; "Stop this phone" stops only this phone; leaving
without stopping is not offered, because leaving would close the segment). While the screen records in front, an
ongoing notification "Recording · 12:34 · Saved 4 s ago" with "Open" (AD19). Rotation and fold change layout only.

**Accessibility.** Acknowledgement and freshness changes announced politely ("Camera 3 status unknown"); rows read
"Camera 1, recording, baseline, battery 78 percent, 2 hours 10 minutes of space left, heard 1 second ago"; Stop
requires the sheet's confirmation (no single-activation stop-all).

**Deliberate differences from the image.**
- Headline "Capture your game." / "Multiple angles. A fuller story." and the tab bar removed (focused route, compact
  header, ST24).
- The big chartreuse "Stop recording" bar → the 76 dp Stop disc that opens the explicit stop-one / stop-all sheet (the
  image's unlabelled stop is not target-specific; implementation-states: "one-device Stop action").
- The bookmark button on the video → "Mark point" control (glossary).
- "Camera devices" header → "Recording on 3 of 3 phones" + freshness basis; rows gain battery, storage and slot.
- "Camera 1 · Sample capture" chip → "Camera 1 · Baseline" + "Sample capture" chip; settings gear → "More".
- Brand painted on the windscreen removed; iOS status bar removed.

---

### A45 Source import (reference 45; mirrors ST25)

**Platform and window.** Android phone.

**Route and entry.** `SourceImport(projectId)` pushed from A42 ("Use videos I already have"), A41's empty state, or
after capture. Home selected.

**Window variants.** Compact: single column. Medium+: source rows start pane; summary, switches and action end pane.
Fold inner: split at the hinge. Compact height: two panes with the action pinned in the end pane.

**Layout (compact).**
1. Top app bar: Up; title "Choose the footage"; Sample badge "Sample files" in demo.
2. Supporting text "Pick up to six angles of the same match."
3. Two-segment `SegmentedButton`: "Photos" · "Files". Each opens the system picker (Photo Picker video-only, max 6; or
   the document picker for `video/*`). Picked files are copied by the ImportPipeline; no storage permission requested.
4. SourceRow × n: checkbox (selected), first-frame thumbnail with duration "60:00", "Camera 1", slot dropdown
   "Baseline", "60 min · 3.6 GB", "1080p · 60 fps" (and "No audio" when applicable), overflow (Change slot, Remove).
5. Dashed AddSlotRow "Add more angles" · "Include another camera angle".
6. SourceSummaryCard (forest): stack icon, "3 angles · 10.8 GB", "Originals stay on your phone.", Sample badge.
7. Switch row "Wi-Fi only" · "Cloud uploads wait for Wi-Fi" (on).
8. List item "Use one old match instead" · "Choose a session from your library".
9. Bottom action "Prepare sync" (2+ sources) or "Choose a story" (1 source).

**Copy.** As ST25 ("Copying… 42%", "Checking the video…").

**Data bindings.**

| Element | Fixture | Source |
|---|---|---|
| Rows | Camera 1 Baseline / Camera 2 Far baseline / Camera 3 Corner · 60 min · 3.6 GB each (illustrative metadata, ST §0.6) | `SourceIngest.ingest` → `SourceManifest` (`source-manifest.json`) |
| Total | 3 angles · 10.8 GB | Σ original bytes, decimal GB, one decimal |
| Wi-Fi only | on | project upload policy (CloudClient only) |

**States.** As ST25: One old match (session picker sheet; button "Choose a story"); No audio ("No audio · video only");
Unsupported / invalid media ("Can't use this file — unsupported format" / "This file is damaged" + "Remove");
Duplicate ("Already added as Camera 2"); Partial source ("Ends early · no video after 41:12"); Mixed dimensions / FPS
("We'll make editing copies that match. Originals stay as they are."); Insufficient working space ("Preparing these
angles needs 6.2 GB free. 3.1 GB is free." · "Manage storage" · "Choose fewer angles"); Working (per-row progress;
leaving keeps importing via WorkManager); Sample (metadata only). Android-specific: picker cancelled (no change);
more than six picked ("JOVRA uses up to six angles. The first six are added."); a document provider that streams from
the network ("Copying from Drive… keep this phone online"); persisted URI permission lost before copy ("This file is no
longer available. Choose it again."). Adaptive: Layout changed / Restored (selection and slot choices kept; copying
continues in WorkManager).

**Interactions.** Slot dropdown per row (conflict → occupied-slot sheet). Uncheck to exclude. Prepare sync → A46
(`Sync`). Choose a story → A49.

**Accessibility.** Row reads "Camera 1, baseline, 60 minutes, 3.6 gigabytes, 1080p, 60 frames per second, selected";
summary card one element; switch has its description.

**Deliberate differences from the image.**
- App bar "Prepare footage" with a hero card "Jon vs Alex · Court Memories · May 12, 2024 · 1 court · 3 angles · Sample
  match" → title "Choose the footage" without a hero (the story is not chosen yet; the 2024 date contradicts the Oct
  2026 sample).
- "Select the source files from your device." → "Pick up to six angles of the same match."
- The image has no Photos / Files buttons; they are restored (adaptive brief and ST25).
- Row labels "Baseline view / Side view / Overhead view" → slot names "Baseline / Far baseline / Corner left"; each row
  gains format and fps.
- "We only make a copy for your project." dropped (the summary says "Originals stay on your phone.").
- "Use Wi-Fi to save mobile data." → "Cloud uploads wait for Wi-Fi" (importing is local).
- "Use one old match instead" restored; "Prepare and sync" → "Prepare sync".

---

### A46 Sync workspace (reference 46, open-fold synchronization desk; mirrors ST26) [S2; demo from S0]

**Platform and window.** Android foldable inner display (reference) and tablets; the same `Sync(projectId)` entry
renders the sequential phone flow at Compact width.

**Route and entry.** `Sync(projectId)` from A45 "Prepare sync", the player's "Review sync", or a needs-review banner.
Home selected (or the stack that pushed it). Medium+: navigation rail visible.

**Window variants.**
- Compact (phone, fold outer): sequential flow as ST26 phone: (1) Sources list with states and "Review" buttons, (2)
  per-source review (reference and selected video stacked, each with its time, jog strip, checkpoint picker Start /
  Middle / End, nudges "−1 frame" "+1 frame" "−10 ms" "+10 ms", "Add marker here"), (3) summary with the inspector
  values and "Confirm sync". Each step is a pushed pane within the same entry (inner back stack saved).
- Medium / Expanded with a separating vertical hinge (fold inner, book or flat): two panes split at the hinge — start
  pane: linked videos + SyncTimeline; end pane: SyncInspector (review card, alignment details, anchors) and the source
  list below it.
- Large (tablet landscape 1280 × 800): three panes — Sources list, videos + timeline, inspector.
- Tabletop: videos in the top half, timeline and inspector in the bottom half.
- Compact height (any width): sequential flow.

**Layout (fold inner, two panes).**
1. Top app bar: Up; title "Sync"; subtitle "Court Memories · Sample project"; Sample badge; overflow (project menu).
2. Start pane: headline "One match. One clock." supporting "Review at start, middle and end."; two linked video
   surfaces labelled "1 Baseline" and "2 Far baseline" driven by one match-clock playhead, each showing its own time and
   "No video here" where it has no coverage; SyncTimeline: one WaveformLane per source (drawn from each source's real
   decoded audio; "No audio" when none), labels "Camera 1 · Reference" and "Camera 2", AnchorMarker with time chip
   "00:12.320", hatched gap "Coverage missing · 0:41" with reason, checkpoint chips "Start" "Middle" "End", zoom; tonal
   button "Add marker".
3. End pane: review card (when Needs review): warning icon + "Needs review" + the reason in words (e.g. "Not enough
   shared moments in the last third."), buttons "Confirm sync" (filled; enabled only after all three checkpoints are
   visited) and "Review later" (text); SyncInspector "Sync details": "Offset (vs. Camera 1 · Baseline)" "+120 ms",
   "Drift" "18 ms/min", "Alignment" state with icon and word ("Estimated"), checkpoint list (Start ✓, Middle ✓, End —);
   anchor list; "Manual align" (tonal); Sources list (SourceCards: number badge, frame, slot, "1920 × 1080 · 59.94 fps",
   state pill "Reference" / "Estimated" / "Needs review" / "Reviewed" / "No overlap", Sample badge).

**Copy.** As ST26 (manual align instruction; toast "Sync confirmed for Camera 2."; Needs-review reasons "Sound reaches
the far baseline later; check a serve by eye." / "Not enough shared moments in the last third." / "The clocks drift
more than expected.").

**Data bindings.**

| Element | Fixture | Source | Provenance |
|---|---|---|---|
| Offset | +120 ms (Camera 2 only, selected) | `SyncMap` piece transform − reference, whole ms | Estimated → Reviewed after Confirm (Sample in demo) |
| Drift | 18 ms/min (= 300 ppm stress fixture) | (rate − 1) × 60,000 | as above |
| Anchor | 00:12.320 | `SyncMap.pieces[].anchors` | — |
| Alignment state, gap | Estimated; coverage gap | `sync-map.json` pre-confirmation map | — |
| Fps / dimensions | 1920 × 1080 · 59.94 fps | `SourceManifest` | — |

**States.** As ST26: Manual markers (diamonds; list "Manual marker · 00:12.320 · Camera 2"); Failed alignment ("We
couldn't line up Camera 3." / "Add a clap or ball drop as a marker, or leave this angle out." · "Add marker" · "Leave
out"); No shared coverage ("Camera 3 doesn't overlap Camera 1. It can't be used for cuts."); Drift (End checkpoint
"Check"); Gap / restart ("Restart · 0:41 gap", one piece per side); Muted source ("No audio"; visible or manual anchors
only); Normalized proxy ("Preparing an editing copy · 42%" / "Originals stay as they are."); Needs review; Single
source (unreachable); Sample. Adaptive: Layout changed (playhead, selected source, unsaved nudges kept — nothing is
saved until Confirm); Restored (unsaved manual nudges restored from the draft; video paused).

**Interactions.** Selecting a source selects its lane and inspector. Dragging an anchor or nudging proposes a manual
correction (recomputed fit and residual shown); Confirm writes a new `syncRevision`, marks pieces `reviewed` and marks
dependent plans and films stale. Keyboard: ←/→ frame, Alt+←/→ 10 ms, Ctrl+Enter confirm. "Review later" returns
without saving.

**Accessibility.** Lanes are adjustable (custom actions next/previous point and frame) reading "12 minutes 46 seconds,
point 42, Camera 2 needs review"; anchors listed as buttons ("Anchor at 12.320 seconds, serve contact, residual 2
milliseconds"); waveform pixels hidden from TalkBack; states by icon + word.

**Deliberate differences from the image.**
- Rail labels and Home selection kept; the image's breadcrumb "< Court Memories" → Up + subtitle; "One match" dropdown
  → title "Sync" + project overflow.
- "Jon vs Alex · May 12, 2025 · Riverside Tennis Club · Clay" removed: invented venue and a 2025 date; venue is private
  by default.
- "Sync & audio" → SyncTimeline with "Court audio" lane labels; anchor time "00:12.340" → fixture "00:12.320".
- Review-card text "We detected a gap in Camera 2 coverage. Confirm alignment or add a manual marker." → the reason
  copy above; "Confirm alignment" enabled immediately → "Confirm sync" enabled after the three checkpoints.
- "Last checked May 12, 2025 16:04" removed (no such field; checkpoints carry the review state).
- "Sample moment · 00:12.340 · Forehand · Camera 1" removed: "Forehand" is a stroke classification v1 does not make.
- Sources "Camera 1 — Baseline Right · 2025-05-12 16:02 · 4K 60fps · 1.2 GB" → fixture slot names, 1920 × 1080 ·
  59.94 fps and the source manifest's sizes.
- Notes card "Add a note…" removed (notes belong to marks and lessons, not sync).
- Player times "00:12 / 04:18" → match-clock times (a sync desk has no film duration).
- Brand painted on windscreens removed; cloud glyph on the Sample chip → dashed Sample badge.

---

### A47 Match Broadcast and multi-angle replay (reference 47, open fold; mirrors ST27)

**Platform and window.** Android foldable inner display (reference), tablets, phones (portrait and landscape).

**Route and entry.** `ProjectPlayer(projectId, filmId?)` from A49 (Match Broadcast "Preview my story"), A59 (Match
Broadcast film), the session overview ("Watch angles"), or A41. Compact: focused (no bar); Medium+: rail visible
unless the player's fullscreen mode is on.

**Window variants.**
- Compact portrait: video on top, angle carousel, points list, bottom actions.
- Compact landscape / compact height: video fills the window with overlays; angles and points in a bottom sheet.
- Fold inner flat (≈ 852 × 883): video in the upper area across the start pane; angles grid + points in the end pane
  when the hinge is vertical and separating; otherwise angles below the video.
- Tabletop: video in the top half; transport, angles and points in the bottom half; nothing in the hinge band.
- Tablet landscape: video start, AngleGrid end pane, points row under the video.

**Layout (fold inner).**
1. Header row: Close (compact) or Up; title "Match Broadcast"; Sample badge "Sample project"; segmented "Film · Angles"
   (Film only when a film exists); overflow (Review sync, Versions).
2. Main video surface (16:9) with ScoreBug top-start (columns "Player", "Set 1", "Set 2"; rows with names and games;
   during play the bug shows sets so far, the current game and the point score at the playhead with the server dot);
   provenance badge on the bug ("Manual" / "Reviewed"; "Final · Reviewed" only after the last point); fullscreen
   toggle top-end.
3. TransportBar: play/pause, time ("12:34 / 48:17" match clock in Angles mode; film clock in Film mode), scrubber,
   rate chips "0.5×" "1×", frame step (hold to repeat), mute.
4. AngleGrid "Camera angles · 3 angles": AngleThumbs "Camera 1 · Baseline" (selected: chartreuse border + check),
   "Camera 2 · Far baseline", "Camera 3 · Corner left" hatched "No video here" when uncovered at the playhead.
5. "Points" row: PointChips ("Point 1 · 00:42", …, current point highlighted) and "+ Mark point".
6. Bottom actions: tonal "Edit this film" (→ A56), filled "Save clip" (→ core clip export sheet).

**Copy.** As ST27 ("This film is one chosen edit. Switch to Angles to watch any view."; "A downloaded film keeps the
angles you chose. Switching angles works here, in the project.").

**Data bindings.**

| Element | Source | Provenance |
|---|---|---|
| ScoreBug | core fold at the session time mapped from the playhead (film: EDL output frame → session time) | per point; "Final · Reviewed" only when complete and all reviewed |
| Angles | `SyncMap.query(source, matchUs)` per thumb | sync state per angle |
| Points | effective point events on the match clock (film: output times) | — |
| Duration | `FilmRecord` frames ÷ fps / match coverage | — |
| Badge "Reviewed sync" | `sync-map.json` confirmed (`reviewed`) | Reviewed |

**States.** As ST27: One angle (no grid; "One angle"); Missing angle ("Camera 3 has no video at 12:46 (recording
gap)"); Buffering ("Loading Camera 2…" after 300 ms); Uncertain sync (thumb "Needs review"; banner "This angle isn't
confirmed in sync here." + "Review sync"); Score unknown (dashed bug "Score unknown"); Offline (local unaffected; cloud
artifact "Not on this phone" + "Download"); Stale film ("Made before a correction — the score in this film may be out
of date." + "Rebuild"); Sample ("Sample video (synthetic)"); Film mode. Adaptive: Layout changed (playhead, angle,
mode, rate kept; playback continues across a resize, pauses on fold→unfold only if the surface is recreated and then
resumes from the same frame); Restored (paused at the saved time).

**Interactions.** Tap a thumb → switch angle at the same match time (no cross-fade under reduced motion). Point chip →
seek to point start (pre-roll). Rate chips change playback rate only. Keyboard: Space, ←/→ frame, Shift+←/→ point,
J/K/L.

**Accessibility.** Video adjustable by point; ScoreBug "Set 1, Alex leads 4–3, Jon 30, Alex 15, Alex serving";
AngleGrid a group of selectable buttons with coverage and sync state; chips ≥ 48 dp.

**Deliberate differences from the image.**
- Rail item "Matches" → "Sessions" (five fixed destinations); the image's "Matches" selection → Home (or the pushing
  stack).
- The "Manual" dropdown with a camera icon on the video → a provenance badge on the ScoreBug (provenance is not an
  angle mode); angle choice lives in the grid.
- ScoreBug "Jon 5 30 / Alex 4 15" → the fold at the playhead (the Jon vs Alex sample at point 42 is set 1, 4–3 to Alex,
  Jon 30–15, Alex serving; `spec/fixtures/sample/jon-vs-alex.expected.json`); the image's 5–4 is layout data.
- "Camera 2 · Net View" → "Camera 2 · Far baseline"; "Camera 3 · Unavailable here" → hatched "No video here" with the
  reason on selection.
- Chapters "Match start / Rally – forehand / Break point / Current point / Serve +1 / Great rally" → PointChips "Point n
  · time" (stroke and quality labels are classifications v1 does not make; "Break point" is a derived flag shown only
  inside the chip's detail when the fold says so).
- "Add chapter", "Share" → removed (chapters are film output; sharing a film happens in A59); "Mark point" kept.
- "Reviewed sync • Sample match" chip with a cloud icon → Sample badge + per-angle sync state; brand on windscreens and
  "A better game tomorrow / Play analyze improve" signage removed.

---

### A48 Angle insights (reference 48; mirrors ST28)

**Platform and window.** Android phone.

**Route and entry.** `AngleInsights(projectId, observationId?)` pushed from Insights ("Angle insights"), the player
("Notes for this point") or a lesson cue. Insights selected. Metric gate A5 applies to any measured value.

**Window variants.** Compact: single column. Medium+: ComparisonPair start pane, observation card and list end pane.
Fold: split at the hinge. Compact height: the pair as one video with an angle switch.

**Layout (compact).**
1. Top app bar: Up; kicker "Studio"; overflow.
2. Headline "Angle insights." supporting "More context. Clearer feedback."
3. Project chip "Sample project" → project switcher sheet.
4. ComparisonPair: two paused video surfaces at the same match time, labelled with slot and camera ("Baseline · Camera
   1", "Near left · Camera 3"), optional AnnotationLayer showing at most one user-drawn or reviewed 2D line; tap opens
   the player at that time.
5. ObservationCard: kicker "Selected cue"; title and body from the observation (template text filled from stored
   values); provenance badge "Estimated observation" (Manual: "Your note"; Reviewed: "Reviewed cue"); status "Needs
   review" when proposed; source line "Source · Camera n · Point n · mm:ss".
6. Buttons: filled "Review cue", tonal "Keep for lesson".
7. Info card: "Additional angles add context." / "Measurements depend on calibration."
8. Measurement row (capability-gated): "Serve speed estimate" · "Needs court calibration" (or "Not available in this
   version") · chevron → capability detail. Never a number in v1 without the capability and calibration.
9. Section "Other notes in this project" with filter chips "All · Needs review · Reviewed" and compact rows.

**Copy.** As ST28 (review sheet "Does this match what you see?" · "Looks right" · "Not right" · "Edit wording"; lesson
picker "Keep for which lesson?" + "New lesson"; toast "Kept in Oct 7 · Serve rhythm").

**Data bindings.**

| Element | Fixture | Source | Provenance |
|---|---|---|---|
| Frames | the observation's match time on both sources | `SyncMap.query` | sync state shown if not Reviewed |
| Cue | `observation.estimated-cue.json` (obs-01, capability `analysis.serveRhythm@0.1.0`, camera-1, point p-041, status proposed) | user text or catalog template filled from stored values | Estimated (Sample; no such capability ships) |
| Source line | slot, point number and match time of obs-01 | observation `sourceId`, `eventRef`, `sessionTimeUs` | — |
| Measurement row | none in v1 | `CapabilityRegistry` (serve speed estimate requires calibration) | registry status |

ST28's prose fixture ("Recovery step · Camera 3 · Point 18 · 24:12") and the record above disagree today; Android
renders the record, exactly as iOS will once the Studio owner reconciles them (§7 C-A5). Android never renders the
image's "Contact point appears forward · Camera 2 · Point 42" unless a fixture says so.

**States.** As ST28: Manual note; Reviewed cue; Unsupported capability ("Automatic notes aren't available for this view
yet." / "Add your own note — it works the same in lessons and films." · "Add a note"); Occluded ("Camera 3 can't see the
player's feet here."); No calibration ("Needs court calibration for Camera 3"); Rejected (struck, "Rejected · kept in
history"); One angle ("Add another angle for more context."); Sample ("Sample — no such capability ships"). Adaptive:
Layout changed (selected observation and filter kept); Restored.

**Interactions.** Review cue → review bottom sheet → new provenance written as an event (the original observation is
never mutated). Keep for lesson → lesson picker (A23) → `LessonJournal.linkCue` → snackbar. Pair tap → A47 at that
time. Measurement row → capability detail ("How this was measured").

**Accessibility.** Pair is one group ("Baseline and near-left views at 20 minutes 16 seconds, point 41"); annotation
described in words ("Line drawn by you"); card reads kicker, title, body, provenance, source.

**Deliberate differences from the image.**
- Kicker "SERVE ANALYSIS" and subtitle "Turn your practice into progress." removed; headline kept.
- Single video with the "Contact point appears forward" callout drawn from the ball → ComparisonPair with only a
  user-drawn or reviewed annotation (no automatic overlay).
- Body "Your contact point looks slightly in front of your ideal strike zone. This can affect consistency and power."
  → the observation's own template text (the image's sentence asserts an ideal and a causal effect).
- "Keep cue / Dismiss" → "Review cue / Keep for lesson" (dismissing is "Not right" inside review, which keeps
  history).
- "KEY METRIC · Serve speed · Calibration needed · Connect a compatible device to see metrics." → "Serve speed estimate
  · Needs court calibration" (glossary term; no device is involved; calibration is a court step).
- "Source Camera 2 · Point 42" → the fixture's source line.

---

### A49 Story modes (reference 49; mirrors ST29)

**Platform and window.** Android phone.

**Route and entry.** `StoryModes(projectId)` pushed from the match overview "Make a film", A41, A45 ("Choose a story"),
A46 (after confirm) or a lesson. Home selected (or the pushing stack).

**Window variants.** Compact: single column of five cards. Medium+: two-column card grid, options in an end pane. Fold:
split at the hinge (cards start, options end). Compact height: cards as a horizontal pager, options below.

**Layout (compact).**
1. Top app bar: Up; kicker "Studio"; Sample badge "Sample project".
2. Headline "Choose your story." supporting "Same match. Five ways to remember it."
3. Five ProfileCards (radio group; selected: forest border, chartreuse check, `selected` semantics): frame, name, line,
   optional readiness line —
   "Coach's Cut" / "Learn from every point."; "Match Broadcast" / "Your match, beautifully covered."; "Rally Pulse" /
   "Feel the energy."; "Progress Story" / "See how far you've come."; "Court Memories" / "Keep the moments that matter."
4. Section "Story length": filter chips for the lengths this profile allows — from the ADR-0023 length list 3, 5, 10, 15,
   20, 25, 30 min and "Full", intersected with the profile's `recommendedDurationSeconds` (`story-profiles.v1.json`:
   Coach's Cut 3–10 min, Match Broadcast 5 min–2 h, Rally Pulse 30 s–3 min, Progress Story 2–6 min, Court Memories 2–8
   min) and the match's coverage. Lengths outside the range are shown disabled with the reason. Default 5 min where
   allowed. **"Full"** means this profile's longest version: the profile's maximum, bounded by the footage (ST29). For
   Match Broadcast, whose maximum spans a whole match, Full is every point in order with the waiting time trimmed,
   which is also ADR-0023's "Full match". For Rally Pulse Full is at most 3 min; for Court Memories at most 8 min. The
   length list is shared with ADR-0023's cloud pricing tiers, but a local film is never priced: the footnote below
   holds.
5. List item "Format" · "Landscape 16:9" (dropdown: Landscape 16:9 · Portrait 9:16 letterboxed) (A25 option surfaced).
6. List item "Footage" · "3 angles" · chevron → A45.
7. Footnote (lock icon): "Made on this phone. Nothing uploads."
8. Bottom action: "Preview my story" with arrow.

**Copy.** As ST29 (disabled-length reasons "Rally Pulse films are up to 3 min." / "Match Broadcast needs at least 5
min."; readiness lines "Needs a lesson note or a reviewed cue", "Needs two dated sessions with the same stat", "Mark a
few moments first").

**Data bindings.** Frames and readiness ← `KeeperSelector.candidates` + `StoryDirector.brief` dry run per profile;
length chips ← ADR-0023 tiers ∩ profile range ∩ coverage; footage ← project sources.

**States.** As ST29: No relevant keepers; Profile needs notes; Quote unavailable ("Cloud production isn't available.
Your phone makes the film."); Local draft; No music rights ("Court sound (no licensed track)"); Sample. Adaptive: Layout
changed / Restored (selected profile and length kept).

**Interactions.** Preview my story → `StoryProfile(projectId, profileId)` (A50, A51, A52, A53) or, for Match Broadcast,
A47 in Film mode with a profile options sheet; the local draft render starts immediately.

**Accessibility.** Radio group "Story style, 1 of 5"; cards read name, line, readiness; length chips with disabled
reasons as descriptions.

**Deliberate differences from the image.**
- "Choose how your game feels." / "Same footage. Different stories." → ST29 brief lines "Choose your story." / "Same
  match. Five ways to remember it." (one wording across platforms).
- Profile lines ("Technical insights and key moments.", "A cinematic match experience.", "Fast-paced highlights set to
  the rhythm.", "Track your improvement over time.", "A personal film of your tennis journey.") → the profile lines
  above ("Technical insights" overstates; "highlights" collides with the core term).
- "Length · 4 min" dropdown → length chips from the ADR-0023 tiers (4 min is not a tier); "Landscape" switch → "Format"
  dropdown (portrait is letterboxed, not a toggle of meaning).
- "Sample project · Sample" row → the Sample badge in the app bar; "Review film plan" → "Preview my story" (the plan
  review is the optional storyboard, A56).
- Stock photographs (including a coach and a second player) → frames from the project's own keepers.

---

### A50 Coach's Cut (reference 50; mirrors ST30)

**Platform and window.** Android phone.

**Route and entry.** `StoryProfile(projectId, coach-cut)` from A49 or a lesson ("Make a Coach's Cut"). Home selected
(or Insights from a lesson).

**Window variants.** Compact: single column. Medium+: preview start, chapters/metric/actions end. Fold tabletop: preview
top half, chapters and actions bottom half. Compact height: preview fills, content in a sheet.

**Layout (compact).**
1. Top app bar: Up; title "Coach's Cut"; action "Options" (tune icon) → film options sheet (A25: length, replays ½× / ¼×
   / off, sound line).
2. Supporting text "Understand the moment. Practice the change."
3. Preview video surface (16:9) of the local draft: Sample badge "Sample film", play, "00:38 / 05:00", scrubber, mute,
   fullscreen. Cue text and arrow are rendered into the film from a reviewed annotation and the template, not drawn as
   UI.
4. Chapter tabs (`PrimaryScrollableTabRow`, each tab seeks): "01 The pattern" · "02 The adjustment" · "03 Your next
   drill" — the film's chapters from the profile beats.
5. Cue card: kicker "Coach's note" (or "Your note"), the reviewed cue ("Calm setup"), provenance badge "Reviewed",
   linked point "Point 41" (tap → A47).
6. MetricFractionCard: badge "Reviewed"; "18 of 30" "first serves in"; ring "60%" (decorative); tap → fraction popover.
7. Practice card: "Practice drill" · "Target serves" · "20 serves" (from the lesson's practice item).
8. Bottom row: tonal "Original speed" (plays the current example's original-speed keeper), filled "Save to lesson".
9. Text button "Create film without a lesson".

**Copy.** As ST30 (sound line in Options: "Court audio plays in the app. When you save or share, you choose whether the
file includes it (off unless you turn it on)."; draft progress "Building your preview on this phone · 40%").

**Data bindings.**

| Element | Fixture | Source | Provenance |
|---|---|---|---|
| Preview, duration | 05:00 | local draft render of the compiled EDL (`edit-plan.coach-cut-serve.json`) | Sample |
| Chapters | The pattern / The adjustment / Your next drill | EDL chapter markers | — |
| 18 of 30 · 60% | Oct 7 session | `StatsEngine` first serves in; `pct(18,30)` | Reviewed |
| Cue | "Calm setup" (cue-03, obs-02) | `lesson.2026-10-07.json` cues | Reviewed |
| Drill | Target serves · 20 | lesson practice item l3-p2 | — |

**States.** As ST30: Unknown stat ("First serves in · —" / "No reviewed serves in this session yet"); Manual cue;
Rejected cue ("1 cue was left out because you marked it not right."); No drill ("Next checkpoint" + "Add a drill to
finish the film"); Labelled replay ("Replay · ½×"); Original-speed fallback ("Slow replays need 60 fps video. This film
shows the examples at original speed."); No reviewed cue ("Your examples"); Draft rendering / failed ("The preview
didn't finish. Your videos are safe." + "Try again"); Stale; No natural audio; Junior mode. Adaptive: Layout changed
(playhead, chapter, options kept; the draft render is not restarted); Restored (the draft job resumes from the job
store; never a second job).

**Interactions.** Save to lesson → lesson picker → final render + verification in WorkManager → snackbar "Saving your
film to Oct 7 · Serve rhythm" → A58 → A59. Options changes re-plan and re-render the draft.

**Accessibility.** Ring decorative, value as text; tabs read "Chapter 1 of 3, The pattern, selected"; Media3 player
controls labelled.

**Deliberate differences from the image.**
- Subtitle "Build a better you on court." → "Understand the moment. Practice the change."; "JOVRA TENNIS" lockup
  removed.
- Title block "The Serve: A Higher Start / A simple cue to add height and consistency to your serve." removed (an
  invented lesson title and a causal claim).
- Tabs "Goal / Example / Cue / Practice" → the film's chapters (the adaptive brief's four labels are profile beat
  names; the chapter names come from the EDL so the tabs and the film agree).
- "Coach's note · Relax into the rhythm. · Tension kills fluidity — stay loose…" → the fixture's reviewed cue; "Linked
  Point #42" → "Point 41" (the cue's point; "#" removed).
- "Practice this skill / Hit 20 target serves and focus on a relaxed motion. / Aim for control, not power." → the
  lesson's drill label and target only.
- Preview "0:00 / 0:12" → the film duration 05:00; "Original speed" badge on the video → the "Original speed" button.
- MetricFractionCard and "Create film without a lesson" restored (ST30).

---

### A51 Rally Pulse (reference 51; mirrors ST31)

**Platform and window.** Android phone; forest screen in both themes.

**Route and entry.** `StoryProfile(projectId, rally-pulse)` from A49. Home selected (the image's Profile selection is
corrected).

**Window variants.** Compact: single column. Medium+: preview start, options end. Fold tabletop: preview top, options
bottom. Compact height: preview fills; options in a sheet.

**Layout (compact).**
1. Top app bar: Up (ivory); overflow.
2. Headline "Rally Pulse" supporting "Feel the energy."
3. Preview video surface: Sample badge "Sample film", play, "00:14 / 01:00", scrubber, fullscreen.
4. TreatmentChips (read-only assist chips, not toggles): "Fast cuts" · "Court sound" · "Key points".
5. Options card:
   - "Effects intensity": `Slider` with three steps "Subtle" · "Medium" · "High" (default Subtle); caption always
     visible "Effects stay off during contact."
   - Switch "Camera shake" · "Adds movement between rallies, never during play." (off).
   - List item "Music" · "Choose a licensed track" (disabled in S1–S4 with "Licensed music arrives in a later update").
   - Switch "Keep full rallies" · "Include complete points, not just highlights." (on).
   - List item "Sound" · "Court audio" with "Saved and shared files include it too, unless you turn it off when you
     save."
   - Segmented "With effects · Clean" above the preview when effects are used.
6. Bottom action "Generate preview"; after a preview exists, filled "Create film" and text button "Generate preview".
7. Footnote: Sample badge "Sample data" in demo.

**Copy.** As ST31 ("Joined mid-rally" chip when Keep full rallies is off; "Preview is out of date · Generate
preview").

**Data bindings.** Treatment chips ← profile grammar; durations ← EDL (`edit-plan.rally-pulse-portrait.json` /
`.clean.json`); options ← project profile settings; intensity default ← `story-profiles.v1.json` `effectIntensity:
low` (shown as "Subtle").

**States.** As ST31: Reduce motion (slider locked at Subtle, "Clean version — Remove animations is on"); Clean alternate;
No licensed music; Clip too short ("Only 2 rallies are long enough — the film will be 0:40." / under 30 s StateCard
"Not enough rallies for Rally Pulse." / "Try Match Broadcast, or mark more points."); Contact frames protected; No
natural audio; Junior mode; Sample. Adaptive: Layout changed / Restored (options and preview position kept; an
in-flight preview render is not duplicated).

**Interactions.** Slider steps give selection haptics; changing options marks the preview out of date. Create film →
A58 → A59.

**Accessibility.** Slider reads "Effects intensity, Subtle, 1 of 3"; switches with descriptions; preview controls
labelled; flash and shake limits enforced by the validator.

**Deliberate differences from the image.**
- Subtitle "See the details. Feel the flow." → "Feel the energy." (brief line).
- "Keep the rally intact. · Sample film." card → the "Keep full rallies" switch and the Sample badge (the image's
  sentence is a promise only true with the switch on).
- "Effect intensity · Low" dropdown → three-step slider labelled Subtle / Medium / High (default Subtle; the contract's
  "low").
- "Clean version · On" switch → the With effects / Clean segmented preview (both versions are rendered when effects are
  used; the clean one is not an off switch).
- "No shake over contact frames · On" switch → an always-on rule stated as a caption (it is not optional).
- "Music · Court sound" dropdown → disabled Music row + Sound row; "Review highlights" → "Generate preview" /
  "Create film" ("highlights" is a core term).
- Preview "00:24 / 01:12" → the sample film's 01:00; Profile destination selected → Home.

---

### A52 Progress Story (reference 52; mirrors ST32)

**Platform and window.** Android phone.

**Route and entry.** `ProgressStory(scope)` from Insights ("Progress Story"), A54 ("Create film"), A55 ("Add to Progress
Story") or A49. Insights selected (or Home when pushed from Home).

**Window variants.** Compact: single column. Medium+: comparison and stat start pane; journey and film card end pane.
Fold: split at the hinge. Compact height: two panes with the frames reduced.

**Layout (compact).**
1. Top app bar: Up; kicker "Studio"; Sample badge "Sample data" (prominent).
2. Headline "Progress Story" supporting "Four weeks. A game that's growing." (computed from the two dates).
3. ComparisonPair (before/after frames synced at contact): date chips "Sep 9" and "Oct 7", captions "Before" / "Now".
4. ComparisonStatCard: trend icon; badge "Reviewed"; "First serves in"; "Source: 2 reviewed sessions."; "12 / 30" with
   "40%" → "18 / 30" with "60%"; "+20 percentage points".
5. JourneyTimeline "The journey": "Lesson 1 · Find the rhythm", "Lesson 2 · Repeat the routine", "Today · Trust the
   motion" (done = filled check; current = ring with dot).
6. Film card: frame with "03:00", kicker "Your progress film", editable title "Progress Story · Sep 9 – Oct 7", filled
   "Build my progress film" with arrow.

**Copy.** As ST32 (footnote "Same stat definition and counting method on both dates. Two sessions show a change; they
can't show why it happened.").

**Data bindings.**

| Element | Fixture | Source | Provenance |
|---|---|---|---|
| 12 / 30 · 40% | Sep 9 | `ProgressStoryBuilder.compare(firstServeIn, Sep 9, Oct 7)`; `pct(12,30)` | Reviewed |
| 18 / 30 · 60% | Oct 7 | same; `pct(18,30)` | Reviewed |
| +20 percentage points | 60 − 40 | difference of the two displayed integers | — |
| Journey | three lessons (`lesson.2026-09-09/09-23/10-07.json`) | `ProgressStoryBuilder.journey`; captions = focus lines | — |
| Four weeks | 28 days | date difference | — |

**States.** As ST32: No earlier evidence ("Progress needs an earlier session with the same stat." / "Choose sessions, or
make a lesson chronology instead."); Method change ("Sep 9 was counted by hand; Oct 7 from reviewed estimates. These
can't be compared."); Differing sample selection ("Examples you chose"); No measurable change ("+0 percentage points",
"No change yet"); Manual reflection only; No natural audio; Junior mode; Sample. Adaptive: Layout changed / Restored
(edited film title kept as a draft).

**Interactions.** Stat card → fraction popover per date. Journey node → A55 for that lesson. Build my progress film →
options sheet (length 2–6 min) → local render → A58 → A59.

**Accessibility.** Stat card reads "First serves in, reviewed. September 9: 12 of 30, 40 percent. October 7: 18 of 30,
60 percent. Plus 20 percentage points. Source: 2 reviewed sessions."; journey is a list with positions.

**Deliberate differences from the image.**
- Headline "Small steps. Bigger matches." / "Same work. A stronger you." → "Progress Story" / computed duration line
  (the image's lines assert a causal story).
- "Same reviewed sample." → "Source: 2 reviewed sessions." plus the method footnote (same definition, same method).
- Two separate fraction cards → one ComparisonStatCard with the arrow (one comparison, one provenance).
- "Lesson milestone · Serve rhythm · Your next practice goal." → JourneyTimeline (the goal line belongs to the lesson's
  `nextGoal`, shown in A55).
- Film thumbnail "04:18" → the progress film default 03:00; missing Sample badge added prominently; "JOVRA TENNIS"
  lockup removed.

---

### A53 Court Memories (reference 53; mirrors ST33)

**Platform and window.** Android phone.

**Route and entry.** `StoryProfile(projectId, court-memories)` from A49. Home selected.

**Window variants.** Compact: single column. Medium+: hero start pane; chapters and choices end pane. Fold tabletop:
hero top half. Compact height: hero fills; content in a sheet.

**Layout (compact).**
1. Top app bar: Up; title "Court Memories"; action "Options".
2. Supporting text "Keep the moments that matter."
3. Hero preview with the film's title card "A good day on court." (editable; rendered into the film), play, "04:18 ·
   16:9", Sample badge "Sample film".
4. Section "Chapters" + "3 chapters": ChapterCards with frames and number badges: "Arrival · 00:42", "The match ·
   02:21", "The moment after · 01:15" (tap seeks).
5. Section "Narrative" + Sample badge: NoteRow "A match to remember." or "Add a few words (optional)" → caption editor.
6. Section "Sound": ChoiceRow "Natural court audio" · "Court sounds, voices and atmosphere" · "In your film", caption
   "When you save or share, Include audio starts on. You can turn it off there."
7. Switch "Show the venue" · "Off keeps your location private." (off).
8. Bottom action "Create this memory".

**Copy.** As ST33 (caption editor "Write a caption or dedication. It appears as you type it." max 120 characters).

**Data bindings.** Chapters and durations ← EDL chapter markers (`edit-plan.court-memories-final.json`; chapters sum to
04:18 = 258 s, asserted in tests); frames ← BrollCatalog / KeeperCatalog; caption ← user text (Manual); sound
availability ← primary source has audio.

**States.** As ST33: One source; No B-roll ("No arrival clips marked. Mark some in the player, or the film starts with
the match." · "Mark B-roll"); Venue hidden (default); Personal caption omitted; No natural audio; Junior mode; Sample.
Adaptive: Layout changed / Restored (caption draft and venue choice kept).

**Interactions.** Chapter card → seek. Create this memory → final render (WorkManager) → A58 → A59. Options → film
options sheet.

**Accessibility.** Chapters list ("Chapter 1, Arrival, 42 seconds"); Sound row reads "Sound, natural court audio, in
your film. When you save or share, include audio starts on."

**Deliberate differences from the image.**
- Subtitle "Your game. Real moments. Lasting stories." → "Keep the moments that matter."; "JOVRA TENNIS" lockup and iOS
  status bar removed.
- Chapter names "Arrival · Getting ready / Match · The game / After the match · Reflections" → the EDL chapter names
  "Arrival / The match / The moment after" (the adaptive brief's "Match" and "After the match" are corrected to the
  fixture so film and screen agree), without invented sublines.
- Hero "Sample Film · Court Memories · 04:18 · Original court sound" → the film's title card + "04:18 · 16:9" + Sample
  badge.
- "Original court sound · The real atmosphere, just as it happened" → the Sound ChoiceRow with the export caption
  (SD5, D-1).
- "Venue · Hidden for privacy" row → the "Show the venue" switch; "Personal dedication · None added" → the Narrative
  NoteRow.
- "Preview story" → "Create this memory" (the draft preview already plays in the hero; the bottom action makes the
  final film, as ST33).

---

### A54 Lesson journal (reference 54; mirrors ST34)

**Platform and window.** Android phone.

**Route and entry.** `LessonJournal` pushed from the Insights root. Insights selected.

**Window variants.** Compact: single column with an extended FAB. Medium+: becomes the list pane of A55's list-detail
workspace (`ListDetailPaneScaffold`): selecting a lesson opens it in the detail pane instead of pushing. Fold: list and
detail split at the hinge.

**Layout (compact).**
1. Top app bar: Up; title "Lesson journal"; kicker "October 2026"; Sample badge "Sample journal".
2. Headline "Your lesson journal." supporting "Every lesson stays with you."
3. Filter chips: "Journal" (selected) · "Practice" (Practice lists drills across lessons with done/target).
4. TodayFocusCard: kicker "Today's focus"; "Serve rhythm"; focus line "Same toss. Calm finish." (system italic);
   "2 of 3 drills complete" with a determinate bar; trailing frame of the lesson's first clip.
5. Section "Recent lessons" + "View all".
6. LessonRow × 3: frame with clip count, date kicker, title, "n clips", status pill "Reviewed" when every note is
   reviewed, overflow (Export for coach, Delete), chevron.
7. CTA EditorialCard: "Turn these lessons into a Progress Story." / "Your lessons, in order." / filled "Create film".
8. Extended FAB "Add lesson" (above the navigation bar; collapses to an icon on scroll).

**Copy.** As ST34 (new-lesson sheet "Date", "Title", "Focus line (optional)", "Coach (optional, as you'd write it)").

**Data bindings.**

| Element | Fixture | Source |
|---|---|---|
| Today's focus | Oct 7 · Serve rhythm · "Same toss. Calm finish." · 2 of 3 drills | lesson dated today else most recent; practice items done/total |
| Rows | Sep 9 First serve foundation · 4 clips; Sep 23 Recovery step · 2 clips; Oct 7 Serve rhythm · 3 clips | `LessonJournal.lessons` newest first; clip count = linked clip refs |
| Reviewed | all notes Reviewed or the player's own Manual | lesson notes |

**States.** As ST34: Empty ("Your first lesson goes here." / "Add notes, link clips and set a drill." · "Add a lesson"
· "Explore the sample"); Offline (no change; with cloud sync on "Changes will sync when you're online."); Missing clip
("1 clip missing"); Private coach share ("Shared with coach" / "Exported for coach" / "Pending your approval" with the
masked verified email); Export; Manual lesson ("No clips yet"); Sample. Available offline is the default and is not
labelled (everything is local). Adaptive: Layout changed (selected lesson becomes the detail pane at Medium+, and is
pushed again at Compact), Restored.

**Interactions.** Row → A55. Today's focus → A55 for that lesson. Create film → A52 scoped to the journal's lessons.
FAB → new-lesson bottom sheet.

**Accessibility.** Focus card one element ("Today's focus, Serve rhythm, Same toss. Calm finish. 2 of 3 drills
complete"); rows read date, title, clip count, review state; FAB labelled "Add lesson".

**Deliberate differences from the image.**
- App bar "Insights · Your progress, your story." → "Lesson journal" (this is a pushed screen, not the Insights root).
- Hero "Every lesson stays with you. · Practice. Reflect. Play better." → supporting line only; tagline removed.
- "Current goal · 20 target serves · Build consistency and control." → TodayFocusCard (the target-serves drill is done
  20/20 in the fixture; the next goal lives in the lesson).
- Row categories "Technique / Movement / Timing" removed (invented classifications; titles are the player's).
- "Latest journal · Sep 9, 2024 · Solid start · Felt good today…" removed (invented entry; wrong year); "Available
  offline" chip removed (local is the default, not a feature badge).
- "Add lesson" FAB kept as an extended FAB; the CTA card to Progress Story restored.

---

### A55 Lesson workspace (reference 55, tablet; mirrors ST35)

**Platform and window.** Android tablet landscape (reference), foldables and phones.

**Route and entry.** `Lesson(lessonId)` from A54, A52's journey or A41's lesson row. Insights selected. Rail at
Medium+.

**Window variants.**
- Compact: lesson detail screen (title, clip player, clip strip, notes, checklist, bottom bar "Save lesson" / "Add to
  Progress Story", overflow).
- Medium / Expanded (fold inner, small tablets): two panes — lessons list | lesson (player, clips, notes and checklist
  below the player).
- Large (tablet landscape 1280 × 800): three panes — lessons list | lesson player and clips | notes and practice
  checklist. Pane boundaries never fall inside a separating hinge.
- Compact height: two panes at most; the player shrinks to 40 % height.
- Pane widths are user-resizable at Large (`PaneExpansionState`, adaptive 1.2.0) and the chosen split is saved.

**Layout (Large, three panes).**
1. Rail (five destinations, Insights selected).
2. Lessons pane: title "Lessons" + "Add lesson" icon button; LessonRows with full dates: "Sep 9, 2026 · First serve
   foundation · 4 clips · 36 min", "Sep 23, 2026 · Recovery step · 2 clips · 42 min", "Oct 7, 2026 · Serve rhythm · 3
   clips · 28 min" (selected: chartreuse tint + border + `selected` semantics).
3. Lesson pane: title "Serve rhythm"; "October 7, 2026 · Sample lesson"; actions filled "Save lesson" (enabled with
   unsaved edits) and overflow (Export for coach, Attach film, Delete lesson); clip player with rate chip "1×", time
   "0:02 / 0:08", mute, fullscreen, and the reviewed annotation (AnnotationLayer, system font); "Clips from this
   lesson": three clip cards with numbers, names and durations, each with a menu (Play, Open in session, Remove from
   lesson); previous/next clip buttons; tonal "Add to Progress Story".
4. Notes pane: "Notes" + status pill "Reviewed"; numbered NoteItems "1 Calm setup" and "2 Finish balanced" with author
   ("Coach (Sample)") and provenance; source row "Source · Camera 1 · Clip 3"; "Practice checklist": ChecklistRows
   "Shadow serves 10 / 10" ✓, "Target serves 20 / 20" ✓, "Review clips 0 / 5" ☐; "Next goal: Keep the toss in front for a
   full set".

**Copy.** As ST35 (note editor "Who wrote this? You / Your coach (as you'd write their words)"; drill editor "Drill",
"Target", "Done"; leave guard "Save changes to this lesson?" · "Save" · "Discard" · "Keep editing").

**Data bindings.**

| Element | Fixture | Source | Provenance |
|---|---|---|---|
| Lesson facts | Oct 7, 2026 · Serve rhythm | `lesson.2026-10-07.json` | — |
| Durations | 36 / 42 / 28 min | linked sessions' durations | — |
| Notes | Calm setup; Finish balanced (author coach) | lesson notes | Reviewed |
| Checklist | 10/10, 20/20, 0/5 | lesson practice items | — |
| Clip names | as stored (labels or numbered "Clip 1–3") | lesson clips | — |
| Next goal | "Keep the toss in front for a full set" | lesson `nextGoal` | Manual |

**States.** As ST35: Unreviewed note ("Not reviewed" + "Mark reviewed"; header "1 not reviewed"); Unsaved edits (Save
enabled; leave guard via predictive back); Source unavailable ("Video not on this phone" + "Find the video"); Permission
revoked (S4); Conflicted sync (S4: "This lesson changed on another device." · "Keep both" · "Choose a version"); Manual
lesson ("No clips yet" + "Link a clip"); Sample. Adaptive: Layout changed (selected lesson, selected clip, playhead,
unsaved note text kept when going 3 → 2 → 1 panes and back; focus stays on the edited field); Restored (unsaved edits
restored from the draft; leave guard still applies); split-screen with another app (one or two panes by width;
keyboard does not cover Save — the bottom bar rises with the IME inset).

**Interactions.** Tap a clip → plays; long-press-drag to reorder (with accessible "Move up/down" actions); checklist
rows are steppers with undo snackbar; "Add to Progress Story" → A52 with this lesson in scope. Keyboard: Space, ←/→,
Ctrl+S save.

**Accessibility.** Three panes are separate headings/landmarks; checklist rows adjustable ("Shadow serves, 10 of 10,
done"); notes read number, title, author, provenance.

**Deliberate differences from the image.**
- Rail item "Lessons" (replacing Sessions, selected) → the five destinations with Insights selected; lessons are a
  pane, not a destination.
- "Lessons · Build your game step by step." → "Lessons"; durations "24 / 12 / 18 min" → linked-session durations
  (36 / 42 / 28 min).
- Notes tabs "My notes / Coach tips" and the paragraph "Focus on a consistent rhythm…" → the lesson's numbered notes
  with author and provenance.
- Checklist sublines ("Focus on rhythm and balance", …) removed; labels from the fixture.
- Clip names "The toss 0:20 / Loading 0:18 / Rhythm and contact 0:12" and "Clip 3 of 3 · Rhythm and contact · Smooth
  up, explode up…" → stored clip labels and durations; no coaching sentence the lesson does not contain.
- Handwritten "Toss in front" annotation → the reviewed annotation in the system font (no third font family).
- Motivational card "Keep going · Small details create big progress." removed; "Add to Progress Story" restored.

---

### A56 Film storyboard (reference 56, tabletop fold; mirrors ST36)

**Platform and window.** Android foldable inner display in tabletop posture (reference); also flat folds, tablets and
phones. Focused route (navigation suite hidden in all classes; Up/Close in the app bar).

**Route and entry.** `Storyboard(planId)` from A47 "Edit this film", a profile screen's Options → "Review the plan", or
A58 job details ("Review the plan").

**Window variants.**
- Tabletop (`isTabletop`, horizontal hinge): top half = preview video (playback only, no small controls near the
  hinge); a gutter equal to the hinge bounds; bottom half = source bin, StoryboardTimeline, selected-clip inspector,
  actions.
- Flat fold / tablet (Expanded+): preview start pane + inspector end pane above a full-width timeline.
- Compact (phone): beat list of BeatCards; tap → segment bottom sheet (angle picker limited to synchronized coverage,
  jog trim inside the keeper window, speed fixed at 1× for live, Remove); findings banner at top; bottom bar "Approve
  film plan" / "Rebuild draft".
- Compact height (landscape phone): preview start, beat list end.

**Layout (tabletop).**
1. Top app bar (top half): Up/Close; title "Shape the story"; subtitle "Court Memories · Sample project"; plan state
   pill "Draft · not approved"; undo / redo icon buttons; overflow (Details: profile and revision, output 1080p · 30 fps ·
   H.264, event and sync revisions, planner "Made on this phone", findings).
2. Preview video "00:15 / 04:18", play/pause, mute, fullscreen.
3. Hinge gutter (no content).
4. Source bin (horizontal list): SourceBinCards "Camera 1 · 2:14", "Camera 2 · 1:32", "B-roll 1 · 0:48", "B-roll 2 ·
   1:06" (usable keeper/B-roll time), selected with chartreuse border.
5. StoryboardTimeline: "00:15.000 / 04:18.000", zoom out/in, "Fit"; ruler 00:00–04:18 scaled from frames; lanes
   "Video" (segments named by keeper/B-roll with angle tags "1", "2", "B"; pattern + tag, not colour alone), "Court
   audio" (one continuous bed), "Score" (event-derived changes; off by default for Court Memories), "Titles" (the film
   title card, optional chapter title, closing card).
6. Selected clip inspector (popover anchored to the segment, or end column when wide): "Camera 2", "In 00:12.400", "Out
   00:18.600", "Duration 00:06.200", "Placed 00:12.000 – 00:18.200 · 1×", "Audio · Court audio from Camera 1".
7. Story beats strip: "1 Arrival 00:00", "2 The match 00:12", "3 Closing moment 03:55" (menus: Change clip, Move,
   Remove).
8. Actions: filled "Approve film plan", tonal "Rebuild draft".

**Copy.** As ST36 (findings: "Goes past the end of Camera 2's video.", "Crosses a recording gap at 41:12.", "Shake isn't
part of Court Memories.", "No licence recorded for this track.", "A title would cover a contact moment.").

**Data bindings.** Segments and times ← compiled EDL (`edit-plan.court-memories-storyboard.json`; exact rational times
shown to the millisecond; source window and output placement separate); beats ← StoryPlan beats; score lane ← core
fold at each segment's session times; titles ← template ids + slots; findings ← `EDLValidator` + `StoryDirector.lint`.

**States.** As ST36: Invalid window (outlined segment, finding, Approve disabled); Gap ("Recording gap · 0:41"; drag
cannot cross); Unsupported effect; Missing audio rights (S5 music lane only); Older point revision ("Built from older
scores"; banner "Points changed since this plan was made." + "Rebuild draft"; Approve disabled); Pending plan approval
→ "Approved · not yet made" → "Create film" (local) or "Continue to quote" (cloud); Rebuild ("Rebuilding from your
current points…" then "3 beats changed" with a diff list); Sample. Adaptive: Layout changed (tabletop ↔ flat ↔ folded
keeps the playhead, selected segment, zoom and unsaved edits; every edit is already a draft plan version); Restored
(draft plan version and undo history restored); leave guard on back when the current version has unsaved edits.

**Interactions.** Edits create a new plan version and re-validate before preview; Approve records approval on that
version only and never spends or shares. Drag handles trim within the keeper window; keyboard ←/→ frame, Shift+←/→
segment, Ctrl+Z / Ctrl+Shift+Z, Ctrl+Enter approve.

**Accessibility.** Timeline adjustable by segment and by frame; each segment reads "Segment 2, The match, Camera 2,
output 12.0 to 18.2 seconds, source 12.4 to 18.6 seconds"; lanes are separate containers; the compact beat list is
the accessible equivalent.

**Deliberate differences from the image.**
- The bottom half's local rail "Home / Edit / Media / Audio / Titles / More" removed: it renames global navigation.
  Focused route; lane and bin selection replace those tabs.
- "Lime Review film plan ✎" (a prompt word leaked into the title) → app-bar title "Shape the story" and the actions
  "Approve film plan" / "Rebuild draft".
- "Share" and "Export" buttons removed: a plan is approved, not shared; making and saving the film happen in A58/A59.
- "1080p" dropdown and "16:9" dropdown → read-only output details (output is chosen before planning, A25).
- Source bin "Camera 2 · B-Roll 1 · Net Close · Footwork · Sunset · Reaction" → the bin cards above; "Reaction" was an
  implied reaction shot.
- "Music" lane removed until S5 (no licensed music in S1–S4); title clips "Build your match" / "A better game tomorrow"
  → the film's own title and template cards.
- Brand watermark inside the video and windscreen signage removed (no brand inside footage); the tooltip's "6.2s" →
  "00:06.200".

---

### A57 Cloud preflight quote (reference 57; mirrors ST37) [S4; demo from S0]

**Platform and window.** Android phone; the quote is a full screen (not a sheet over a player), because consent must
not be dismissed by a swipe. This is the one quote screen for both apps (ST37 is recommended to match, §7 C-A4); the
"What sets the price" breakdown is the native Material bottom sheet that `implementation-states.json` 57 names.

**Route and entry.** `Preflight(jobDraftId)` from a profile screen's Options → "Make it in the cloud" (only when
CloudMode is demo, test or live) or A56 "Continue to quote". Home selected.

**Window variants.** Compact: single column. Medium+: film summary + quote start pane; settings rows, consent and
actions end pane. Fold: split at the hinge; the consent checkbox and the Create button are always in the same pane.
Compact height: two panes. The IME never covers the Create button (the action row follows the IME inset).

**Layout (compact).**
1. Top app bar: Up.
2. Headline "Ready to create?" supporting "Know before you create."
3. Film summary card: frame with "5:00", "Coach's Cut", "5 min · 3 angles · 1080p", chevron → plan summary.
4. QuoteCard (forest): label "Sample quote" (or "Quote · expires in 28 min"); "2–4 credits" (estimate); divider;
   "Spending limit" "4 credits"; footnote "Sample pricing. Real prices appear here once they're set." The card binds the
   shipped `jovra.quote/1` (`estimate`, `capCredits`); if Jon chooses one number (pricing-matrix-v2 §10 Q1) the contract
   sets min = max = cap and the card shows one figure ("4 credits · Most it can cost") with no other change.
4a. Length chips under the card (the same list as A49: 3 · 5 · 10 · 15 · 20 · 25 · 30 min · Full, disabled with a
   reason when the profile or the footage does not allow them).
4b. Row "What sets the price" · chevron → **modal bottom sheet** (Jon's price toggle, pricing-matrix-v2 §8.2): Film
   length (the chips again), Film quality (for 4K captures a picker "4K" / "1080p"; for lower captures read-only
   "Captured as 1080p60"; never above the capture; "Full match films are made in 1080p" when that policy is adopted),
   Angles (one switch per camera with its thumbnail; at least one on), Source minutes (read-only), Story planning (the
   switch, mirrored). Each driver has an info button with the §8.2 explainer. Any change re-quotes ("Updating quote…";
   Create disabled) and clears consent; the server's quote is what counts.
5. List items with chevrons:
   - "Cloud processing" · "Private upload" → consent detail (A5: selected sources and bytes, "3 angles · 10.8 GB ·
     about 1 h 12 min on this Wi-Fi" or "Upload time depends on your connection", Wi-Fi only state, what the planning
     step receives).
   - Switch "Plan the story in the cloud" · "Off: your phone's rules plan it, as in a local film." (off; hidden when no
     model planner is configured). When on, the consent detail names **both** planning services by their configured
     display names (one drafts the story, one reviews it; ADR-0023's drafter–critic pair) and each one's retention.
   - "Originals" · "Kept on device".
   - "Temporary media" · "Delete after 7 days" → retention sheet (1 / 7 / 30 days; re-quotes).
   - "Finished film" · "Kept until you delete it".
6. ConsentRow: checkbox (48 dp) "I agree to upload these selected videos" (unchecked). With cloud planning on, a
   second required checkbox "I agree to send sampled frames, my point events and the notes I ticked to the two planning
   services named above".
7. Filled "Create film" (disabled until every shown checkbox is ticked, the quote is valid and identity allows;
   supporting text says why); outlined "Use local replay".

**Copy.** As ST37 (demo footnote "Demo mode does not upload or charge."; cap explanation "The job stops here and asks
you before using more."; states). Money amounts never appear on this screen, and v1 has no purchase flow: no credit
packs, no Play Billing and no "Get credits" until the pricing ADR (ADR-0013; android-v1-spec AD4).

**Data bindings.**

| Element | Fixture | Source |
|---|---|---|
| Estimate, cap, expiry | 2–4 credits, cap 4 credits (`quote.sample-illustrative.json` `estimate`, `capCredits`) | `CloudClient.quote` (server-computed); Sample in demo/test |
| Sources and bytes | 3 sources, 10.8 GB | job draft source manifests |
| Upload time | measured rate, else none | last measured upload rate on this network |
| Retention | 7 days | job draft policy |
| Plan in the cloud | off (`plannerChoice: heuristic` default; the sample record shows `model` for the cloud-planning state) | job draft |
| Drivers (length, film quality, angles) | 5 min · 1080p · 3 angles | job draft; each change re-quotes |
| Consent | unchecked | `QuoteReservation` consent fields (`jovra.quote/1`) |

**States.** As ST37: Demo — charge disabled; Real quote expired ("This quote expired." + "Get a new quote"; consent
cleared); Not signed in ("Sign in to make films in the cloud." + "Connect account"); Cost above cap ("The estimate is
above your limit." · "Change limit" · "Choose fewer angles"); No cloud consent ("Tick the box to upload these
videos."); Retention choice; Local replay always available; Wi-Fi only on cellular ("Upload will wait for Wi-Fi.");
Cloud planning on (A5 names both planning services and each one's retention; consent text version recorded; the
quote's single `consent.modelProvider` field cannot yet record per-service consent, open finding F-QUOTE-CONSENT, so
the cloud-planning state ships only after it closes); Updating quote (figure dimmed, Create disabled); Tier unavailable
(chip disabled with a hint); Cloud unavailable
("Cloud production isn't available right now." + "Use local replay"). Adaptive: Layout changed (consent state kept for
the same quote id); Restored (consent kept only if the quote is still valid; otherwise cleared with "This quote
expired."); double-tap or retry after rotation reuses the idempotency key (one job, one reservation).

**Interactions.** Create film → `CloudClient.accept(quote, consent, cap, idempotencyKey)` → A58. A length chip or any
driver in the "What sets the price" sheet re-quotes (preview from the versioned price table when it exists; the
server's quote is what counts) and clears consent.

**Accessibility.** Quote card reads "Sample quote. Estimated 2 to 4 credits. Spending limit 4 credits. Sample pricing;
real prices appear here once they're set."; price updates announced politely; no animated numbers; the
disabled button's reason is its supporting text and state description.

**Deliberate differences from the image.**
- Video player above a bottom sheet with "00:12 / 03:28" → a full screen with the film summary card (consent must not be
  swipe-dismissable; the duration was inconsistent with the 5:00 film).
- "Cloud film estimate" → "Ready to create?" / "Know before you create."
- "$4 – $8", "$12" → credits from the quote contract, Sample (ADR-0023 prices in credits; pricing-matrix-v2 recommends
  showing credits only on the quote). ST37's dollar copy predates ADR-0023; §7 C-A4.
- The reference's bottom sheet holds the quote; here the quote is a full screen and the native Material bottom sheet
  holds "What sets the price" (implementation-states 57 "Native Material bottomsheet" kept, for the breakdown).
- Rows "Estimated cost / Spending cap / Quote: Sample only / Cloud processing: Off" → QuoteCard + the ST37 list items;
  "Cloud processing: Off" is not a toggle here (this screen exists to opt in to cloud production for one film).
- Consent "I understand this is a sample estimate only. I agree to proceed with cloud processing." → the ST37 consent
  text (consent is to upload these selected videos; a sample notice is not consent).
- Retention "7 days" restored (the revision note lists it); "Keep reviewing locally" → "Use local replay" (ST37 brief
  label; §7 notes the open naming question).
- Player imagery with "Better Players Brighter Days" signage and brand removed.

---

### A58 Render queue (reference 58; mirrors ST38)

**Platform and window.** Android phone.

**Route and entry.** `Job(jobId)` after creating a film (local or cloud), from A41's banner, a notification, or A59 when
still verifying. Home selected.

**Window variants.** Compact: single column. Medium+: job card and stages start pane; progress card and actions end
pane. Fold: split at the hinge. Compact height: two panes.

**Layout (compact).**
1. Top app bar: Up; overflow (View job details).
2. Headline "Your story is taking shape." supporting "Jon vs Alex · 3 angles · Oct 7, 2026".
3. Job card: frame with Sample badge, kicker "JOVRA Studio", "Court Memories", "3 angles · Created Oct 7, 2026",
   chevron → job details sheet.
4. JobStageList (icon + word per state, connector): "Upload · Complete · 3 camera sources uploaded"; "Align angles ·
   Complete · Alignment reviewed"; "Build film · In progress · Building your private preview"; "Verify export · Queued ·
   Checks every frame before it's ready". Local jobs show only "Build film · Verify export" (plus "Align angles" with
   more than one angle). No "Plan story" or "Analyzing" stage.
5. StageProgressCard: kicker "Build film"; "Rendering your private preview"; `CircularProgressIndicator` (determinate)
   "42%" with the caption "of this step"; linear bar; "You can leave this screen. We'll keep your place."
6. Switch "Notify me when it's ready" (requests `POST_NOTIFICATIONS` in context when turned on).
7. Bottom row: "View job details", "Pause upload" (disabled "Upload finished" after upload; hidden for local jobs),
   text button "Cancel film" (destructive colour).

**Copy.** As ST38 (job details: start/end times, attempts "Attempt 2 of 3", reservation and receipt "Estimate · Cap ·
Used so far", "What's kept: your originals stay on this phone."; cancel sheet "Cancel this film?" / "Temporary copies
will be removed. Your originals stay on this phone." · "Cancel film" · "Keep going").

**Data bindings.** `CloudClient.job` stream (cloud) or the local `RenderJob` (WorkManager); `render-job.queue-sample.json`
in demo (`state preview_rendering`, `stageProgress 42`); stage progress only from stages that report a real fraction;
no total-job percentage.

**States.** As ST38: Paused ("Paused · 2.1 of 10.8 GB" + "Resume upload"); Resumed (snackbar "Upload resumed");
Retryable failure ("Trying again · attempt 2 of 3"); Terminal failure ("This film couldn't be finished." / "Your videos
are safe on this phone. Nothing is charged for an unfinished film." · "See details" · "Try again"); Canceled ("Film
canceled" → "Removing temporary copies…" → "Temporary copies removed"); Budget exhausted ("Stopped at your 4-credit
limit." / "Raise the limit to continue, or keep the preview."); Notification unavailable ("Turn on notifications to
hear when it's ready." → app notification settings); App in background (local render continues as a WorkManager
foreground worker with a progress notification; if the OS stops it, the job resumes from its last stage on return —
never restarted as a new job); Verifying ("Checking every frame · 61%"); Sample. Adaptive: Layout changed / Restored
(the screen re-reads the durable job; nothing is resubmitted).

**Interactions.** Leaving and returning restores from the durable job. "Build film" is tappable only when a draft exists
("Watch the draft"). Cancel → bottom sheet.

**Accessibility.** Stages read "Step 3 of 4, Build film, in progress, 42 percent of this step"; announcements at most
every 10 %.

**Deliberate differences from the image.**
- Stage names "Upload complete · Video files received / Align reviewed · Angles synced and ready / Build film ·
  Creating your story… / Verify · Quality check and final prep" → ST38 stage names and details (what each stage
  actually does).
- Timestamps per stage moved into job details.
- "42%" inside the ring kept, with the caption "of this step" (never a total-job percentage).
- Switch "Wi-Fi reconnect enabled · If your connection drops, we'll automatically resume this job." removed as a
  control: resuming after a drop is always on; the Wi-Fi-only policy belongs to the project (A45) and shows as a
  status line "Upload waits for Wi-Fi" when relevant.
- "Notify me after verification" → "Notify me when it's ready" (ready means verified).
- "Cancel request" → "Cancel film" with the confirmation sheet; "A better game tomorrow" overlay removed.

---

### A59 Film delivery (reference 59; mirrors ST39)

**Platform and window.** Android phone.

**Route and entry.** `Film(filmId, version?)` from A58 (ready), A41's FilmCard, `StudioFilms`, a "film ready"
notification, or the deep link `jovra://studio/film/<id>` (App Links are not used for private films). Home selected.

**Window variants.** Compact: single column. Medium+: hero start pane; actions and details end pane. Fold: split at the
hinge; tabletop puts the hero in the top half while playing.

**Layout (compact).**
1. Top app bar: Up; overflow (Versions, Show plan, Delete film).
2. Headline "Your film is ready." supporting "Keep the match. Share the story."
3. Hero poster with play: the film's title "A good day on court", meta "Court Memories · 04:18 · 1080p", Sample badge
   "Sample film".
4. DeliveryPanel: check icon, "Private preview", "Export verified · 412 MB", chevron → verification sheet.
5. Filled "Download film" (cloud artifact) or "Save film" (local film).
6. List items: "Save to device" (MediaStore Movies) and "Save to Files" (document create); "Save to lesson"; "Prepare
   for YouTube" with "Preparing for YouTube creates a video, cover and description. You choose when to upload.";
   "Shared link" · "Expires in 24 hours" with refresh (Revoke in detail); no raw URL shown.
7. Version row when older versions exist: "Version 2 of 2 · current".

**Copy.** As ST39 (save sheet with the Include audio switch A20 "Include audio" · "Voices recorded on court will be in
the file." — on by default for Court Memories and Rally Pulse, off for the others, always shown when the film has
audio; "Preparing a version without sound… checked"; YouTube package sheet fields; footer "JOVRA never uploads for
you.").

**Data bindings.** Title, profile, duration, resolution ← `FilmRecord` (duration = frames ÷ fps); 412 MB ← measured size
(Sample illustrative); Export verified ← `FilmRecord.verification.passed` (`delivered-artifact.film.json`); shared link
← `CloudClient.shareLink` (24 h); Include audio default ← profile; versions ← plan lineage.

**States.** As ST39: Still verifying ("Checking every frame… 61%"; save and prepare disabled); Failed full decode ("This
film didn't pass its checks, so it isn't marked ready." · "Rebuild" · "See details"); Expired link ("Link expired" +
"Create a new link"); Access revoked; Partial download ("Download paused · 212 of 412 MB" + "Resume"; re-verified by
size and hash); Old version ("Version 1 · made before a correction." + "Watch current version"); Archive disconnected
("Save to Google Drive · Needs reconnect"); Junior mode (shared link and YouTube hidden; no audio); No-audio variant
preparing; Local film (shared link hidden; "Save film" primary); Include audio on/off; Sample. Adaptive: Layout
changed / Restored (playback position kept; an in-progress download continues in WorkManager and is not duplicated).

**Interactions.** Play → full-screen Media3 playback (or A47 Film mode for Match Broadcast). Save to device / Files →
save sheet → verified file. Prepare for YouTube → package sheet → saved to Files; no network. Share link → Android
share sheet with the link only after the player creates it.

**Accessibility.** Hero reads "Play A good day on court, Court Memories film, 4 minutes 18 seconds, 1080p, sample";
panel "Private preview, export verified, 412 megabytes".

**Deliberate differences from the image.**
- Supporting line "Relive key moments, analyze your game, and turn your footage into progress." → "Keep the match.
  Share the story." only (brief title; "analyze" overstates).
- Hero overlay "Court Memories · Jon vs Alex · 04:18 | 1080p | Private" → the film's title card and meta; "Private"
  is the DeliveryPanel's "Private preview".
- Three outlined buttons "Save to Files / Add to lesson / Prepare for YouTube" → list items (with Save to device) so
  long labels wrap at 200 % font scale.
- "Private link access · Only people with the link can view this film. · Review" → "Shared link · Expires in 24 hours"
  with refresh/revoke (links are private grants that expire, not open links).
- "Details · Created Aug 24, 2024 · 9:12 AM …" → verification sheet; the 2024 date is wrong; Export verified panel and
  Sample badge added.

---

### A60 Studio settings (reference 60; mirrors ST40)

**Platform and window.** Android phone.

**Route and entry.** `StudioSettings` from the Profile hub (Profile selected) or A41's gear (Home selected).

**Window variants.** Compact: single column. Medium+: 720 dp column, or list-detail (sections list | section detail)
at Expanded. Fold: list-detail split at the hinge.

**Layout (compact).**
1. Top app bar: Up; title "Studio settings".
2. Supporting text "Your footage. Your choices."
3. IdentityCard (forest): kicker "Demo profile"; "Jon"; "Local demo · Cloud not connected"; filled "Connect account".
4. Section "Storage" + Sample badge: ProviderRows "On this phone" · "Active" (export folder: "Choose a folder for
   exports" → system folder picker); "Google Drive" · "Not connected"; "Box" · "Planned"; "Dropbox" · "Planned" — each
   with a state icon + word and a chevron.
5. Section "Watch": "Paired watch" · the watch's device name as reported by the OS · "Status mirror" (role) · freshness
   ("Last updated 2 s ago" / "Not updated for 40 s") · chevron → watch settings (abilities defaults, "Watch haptics"
   switch, "Install JOVRA on your watch" when missing). Hidden when no watch is paired.
6. Section "Privacy": switch "Cloud processing" · "Off until you choose to upload" (off); "Camera invitations" · "Expire
   in 10 min"; "Temporary uploads" · "7-day policy"; "Cloud films" · "Kept until you delete them"; "Shared links" ·
   "Last 24 hours".
7. Data: "Export project", "Delete cloud copies" (destructive), "Download my data".
8. Info card: "Demo mode does not upload or charge."
9. "Advanced" (test mode only): planner configuration lines and "Help · hello@islanddevcrew.com" as selectable text
   (never a mailto link).

**Copy.** As ST40 (provider detail sheets: Google Drive "Uses the same Google Drive connection as your backups.", Box /
Dropbox "Planned. Not connected to anything yet."; export folder "Saves a project folder you choose. It isn't used to
make films."; cloud processing explainer).

**Data bindings.** Identity ← `CloudClient.mode()` + `identity()`; providers ← `storage-providers.json` filtered by
`platforms.android` (device, google-drive, box, dropbox; iCloud is iOS-only); watch ← WatchBridge state; privacy and
data rows as ST40.

**States.** As ST40: Real auth test/live (Credential Manager sign-in; "Sign out" keeps local data); Disconnect /
reconnect; Token expired ("Google Drive · Needs reconnect"); Provider planned / unavailable; Deletion running / failed;
Data export ("Preparing your data · 42 MB"); No configuration ("Cloud accounts aren't available in this version.");
Junior mode (cloud processing locked off); Sample. Watch states: none paired (section hidden); paired, app missing;
Unknown freshness. Adaptive: Layout changed / Restored.

**Interactions.** Connect account → sign-in sheet (A12 equivalent; demo "Use demo profile"). Provider row → scope
sheet (A17). Delete cloud copies → delete scope sheet (A6). Export folder → `OpenDocumentTree`.

**Accessibility.** Provider rows read name and state ("Box, planned, not connected"); destructive rows announced as
such; switches with descriptions.

**Deliberate differences from the image.**
- "Profile" header with an invented player name, "Sample Player", an invented personal email address and a portrait
  removed: the address is credential-like and violates hard rule 7 (it is deliberately not reproduced here); the
  identity card shows the demo profile only.
- "A better game tomorrow. · Capture. Analyze. Share." banner removed.
- "Your footage · Device storage · Active · Choose folder" → "On this phone · Active" with the export-folder action;
  "Files & cloud · Keep your projects safe, on your terms." → "Storage" (providers are archive targets).
- "Paired watch · Galaxy Watch · Status mirror · Sample" → section "Watch" with the OS-reported device name as data
  (brand hygiene: app copy never names a manufacturer) and a freshness age.
- "Processing & data · Cloud processing · Off" → the Privacy section switch with its description; "Export project ·
  Save a copy to your device" and "Delete cloud copies · Remove your data from connected services" → ST40 labels.
- Profile destination selected is kept when entered from Profile (Home when entered from A41).

---

## 2. Watch surfaces (references 61–70)

Behaviour, protocol, roles, freshness, haptics and gates are in `docs/spec/watch-v1-spec.md`; this section specifies
each surface as a screen. All ten are gate A3 (`implementation-states.json`); 63 and 68 also carry metric gate A5.

**Conventions for both watches.**
- **Data** comes only from the latest validated `jovra.watch-snapshot/1` (seed fixture
  `design-reference/adaptive/brief/watch-snapshot.sample.json`: session `sample-jon-alex`, host epoch 3, snapshot 8,
  event revision 42; six cameras, C3 at 18 s; score Jon 5 Alex 4, 30–15, Manual; `liveServeSpeed: false`;
  `illustrativeLaterResult` 74 mph Estimated, `enabledInV1: false`; one Accepted MarkForReview receipt). The watch
  sample is its own Sample set; it is not a state of the core Jon vs Alex log (watch spec C7).
- **Freshness words** (watch spec FreshnessClock): Fresh shows only the age ("1 s"); Delayed shows "Delayed · 9 s";
  Unknown shows "Unknown · 18 s" with a clay ring. Remote elapsed times are shown exactly as last reported and never
  advance on the watch clock.
- **Navigation.** watchOS: vertical-page `TabView` (Health → Score → Latest serve → Mark) with `NavigationStack` for
  "View all" and confirmations; the alert as a full-screen sheet or notification. Wear OS: `HorizontalPagerScaffold`
  with a page indicator for the same four pages, `SwipeDismissableNavHost` for detail and confirmations, swipe to
  dismiss (no back button). The app opens on Health, or on the alert when launched from it.
- **Ambient / always-on.** Last values dimmed, "Updated 9:41", no animation, ages rounded to minutes ("over 1 min").
- **Sizes.** watchOS: SE 3 40 mm to Ultra 3 49 mm (both device types installed, OBSERVED). Wear OS: 192 dp
  (`wearos_small_round`) to 240 dp (`wearos_xl_round`), plus `wearos_rect` (OBSERVED profiles). Text and targets must
  pass at the smallest size and the largest font scale.
- **Every surface shows "Sample"** when `sample: true`.
- **Removed from every watch image.** Photographic backgrounds and inset photos (63, 64, 67, 68, 69), the "JOVRA
  TENNIS" lockup (63, 66, 67, 70), custom-drawn system time and battery (64, 68, 69 show "10:24 · 92%"; the system
  draws time), Hawk-Eye-like ball-on-line imagery (64, 69).

---

### W61 Camera health — Apple Watch (reference 61)

**Platform and window.** watchOS, rectangular; first vertical page.

**Route and entry.** App launch, the complication, or the Health page in the vertical `TabView`.

**Variants.** 40 mm: count + basis + 2 rows visible, scroll for the third and the button. 49 mm: count + basis + 3 rows +
button. AX text: count shrinks one step, rows wrap to two lines, page scrolls with the Crown. Ambient: dimmed snapshot.

**Layout.**
1. Navigation title "JOVRA" (system time top-trailing, drawn by the system).
2. Headline "5/6" (large, chartreuse) + "fresh" (ivory).
3. Basis line "Recording · heard ≤ 5 s".
4. "Primary · 12:34" with "Last-known".
5. Up to three rows, worst first: "C3 · Unknown · 18 s" (clay ring), "C1 · 12:34 · 1 s", "C2 · 12:33 · 2 s"; flags as
   icons + words on a second line when present ("Low space · 18 min", "Battery 12%", "Warm").
6. Button "View all 6" → list of all enrolled cameras with slot, state word, last-reported elapsed and age.
7. "Sample".

**Data bindings.** Headline = `freshRecording / enrolled` (HealthSummary: Fresh and `captureState == Recording` over
approved roster) — sample 5/6; Primary elapsed = primary's `lastReportedElapsedMs` (754,000 ms → 12:34); rows =
devices by severity; ages = FreshnessClock (sample C1 1 s, C2 2 s, C3 18 s → Unknown). Not a stat; no provenance badge.

**States.** All fresh ("6/6 fresh"); some Delayed ("Delayed · 9 s"; not counted); Unknown (frozen elapsed in detail
"Last reported 12:26", "May still be recording"); camera Ready / Starting / Paused / Finalizing / Saved / Failed (state
words; only Recording + Fresh counts); single-phone mode ("1/1 fresh", "This phone · 12:34"); not recording ("Ready ·
not recording"); no match ("No match in progress" + "Start on your phone"); phone not reachable (banner "Phone not
reachable · last update 18 s ago"; all rows Unknown); queued snapshot after wake ("Refreshing…" with all rows Unknown
until an echo succeeds); watch app restarted ("Last updated 9:41", all Unknown); room host lost ("Room host not heard ·
20 s"; all rows Unknown; "Recordings continue on each phone"); room restarted (new epoch: "Room restarted ·
reconnecting"); wrong session / older sequence (ignored, no visual change); large text; ambient; Sample.

**Interactions.** Tap a row → camera detail (slot, state, elapsed, age, flags; no controls in A3a; A3c adds "Request a
fresh still" for any camera and "Stop this phone" only for the wearer's own phone). Crown scrolls. Raising the wrist
into the app triggers an echo refresh.

**Accessibility.** "5 of 6 cameras fresh and recording. Primary recording, 12 minutes 34 seconds, last known." Rows:
"Camera 3, near left, status unknown, last heard 18 seconds ago, may still be recording." Unknown uses a ring shape and
the word; ages are not announced on every update.

**Deliberate differences from the image.**
- "5/6" alone → "5/6 fresh" + basis line (the visual review: five freshly acknowledged Recording cameras of six
  enrolled).
- "Recording 12:34 · Last-known." → "Primary · 12:34 · Last-known" (whose time it is).
- The ring with a ball icon removed (it reads as progress or sync, and implies nothing true).
- Rows ordered worst first (the image orders by camera number).

---

### W62 Score and undo — Apple Watch (reference 62)

**Platform and window.** watchOS; second vertical page.

**Variants.** Viewer role: score only, with "Scoring on Jon's phone". Scorer role (A3b): point buttons and Undo.
40 mm: buttons stacked vertically, Undo scrolls into view. 49 mm: buttons side by side. AX text: stacked buttons,
score one step smaller, never truncated.

**Layout (scorer, 49 mm).**
1. Names "Jon" and "Alex" with the server dot beside the server's name (only when the snapshot knows the server).
2. Point score "30–15" (very large; leading side unstyled — no winner colouring).
3. "Games 5–4" (and "Set 2" when beyond the first set; "Tie-break 4–3" in a tie-break).
4. Chip "Manual · Synced" (provenance · sync state).
5. Buttons "Jon point" and "Alex point" (equal visual weight, ≥ 44 pt tall).
6. Button "Undo last" (separated by at least 8 pt).
7. "Sample".

**Data bindings.** `score` from the snapshot: names as entered, points/games/sets from the phone's fold at
`eventRevision`, provenance (weakest point provenance; live entry = Manual), `isProvisional`, server; sync chip from
the CommandLedger and freshness ("Synced" = fresh snapshot and no pending commands).

**States.** Synced; Pending ("Jon point · sending", score unchanged); Accepted (light haptic, score updates with the next
snapshot); Offline ("Offline · 1 pending"); Expired ("Not sent · enter it on the phone"); Conflicted ("Score changed
on the phone. Now 30–15. Send Jon point again?" · "Send again" · "Cancel"); Rejected (role) ("Scoring is off for this
watch"); duplicate retry (one point, original receipt); Undo confirmation ("Undo Jon's point? Score goes back to 15–15."
· "Undo" · "Keep"); provisional ("Provisional · check point 37 on the phone"); tie-break; match complete ("Final score
· 6–4 6–3", no winner wording); bridge Unknown (score dimmed, "Last known · 18 s ago"; buttons still create pending
drafts); viewer; no score yet ("No score yet"); Sample.

**Interactions.** Point button → `PointWon` command (Pending until receipt). Undo last → confirmation → `Undo`
with `baseEventRevision`. No optimistic increment.

**Accessibility.** "Jon 30, Alex 15. Games 5 4. Manual score, synced." Buttons "Point to Jon", "Point to Alex", "Undo
last point". Pending and receipts announced politely.

**Deliberate differences from the image.**
- The unlabelled dot between the names → a server dot beside the server's name (shown only when known).
- The lime "30" vs white "15" colouring removed (colour must not imply who is winning or which side is "you").
- "Jon point" lime and "Alex point" forest → equal tonal buttons (equal weight; no accidental preference).
- The sync icon in the chip kept, with the word.

---

### W63 Latest serve — Apple Watch (reference 63; metric gate A5)

**Platform and window.** watchOS; third vertical page.

**Variants.** v1, no estimate (default): explanation state. v1 with a post-capture estimate (room capability
`serveSpeedResults` on and a `latestServe` in the bridge payload; `serveSpeed.manualAssisted` is `estimated` in the
registry): value state, always labelled Estimated, with its own point and age, never "live". A5 adds only lower-latency
delivery after its own benchmark gate. 40 mm: value one step smaller; age line wraps.

**Layout (v1).**
1. Heading "Latest serve".
2. "Not measured live" (large).
3. "Serve speed estimates are made on the phone after you mark contact and bounce."
4. Button "Mark this serve".
5. "Sample".

**Layout (value state; Sample fixture `spec/room/fixtures/records/watch-bridge.with-serve.json`, from the design
sample's `illustrativeLaterResult`).** Heading "Latest serve"; "74" + "mph"; "Estimated
average speed, contact→bounce" (two lines); "Point 42 · Camera 1 · 8 s ago"; range "70–78 mph" when provided; button
"Mark this serve"; "Sample".

**Data bindings.** `capabilities.serveSpeedResults` (and `liveServeSpeed: false`, always); `latestServe` from
ServeResultGate (`spec/room` `analysis.present`): value, units (player's units
setting), low/high, label (Estimated / Reviewed; Validated only with a benchmark record), point number, source camera,
age (FreshnessClock). Provenance badge shown with the value.

**States.** Not measured live (v1 default); needs calibration ("Needs court calibration on the phone"); waiting for the
phone ("Waiting for the phone"); capability off ("Serve speed estimates are off"); result older than the current point
("Point 38 · 4 min ago" + "Not the latest serve"); bridge Unknown (age "Unknown"; value dimmed); Reviewed label; km/h;
Sample.

**Interactions.** "Mark this serve" → `MarkForReview` with reason `serve` and the point (receipt as W64).

**Accessibility.** v1: "Latest serve. Not measured live. Serve speed estimates are made on the phone after you mark
contact and bounce." A5: "Latest serve, estimated average speed contact to bounce, 74 miles per hour, point 42, camera
1, 8 seconds ago."

**Deliberate differences from the image.**
- The 74 mph value is shown only as a post-capture estimate with its point and age when the phone has made one (never
  live; capture v1 has no live serve speed; visual-review.md); otherwise "Not measured live", the one string for this
  state on every surface (ADR-0026 §3.3 and watch story 42 now use it too).
- "Estimated" → "Estimated average speed, contact→bounce" (glossary "Serve speed estimate"; never a radar or peak).
- "Bookmark serve" → "Mark this serve" (glossary).
- The serving-player photograph and "TENNIS" lockup removed; the camera icon "1" → "Camera 1" in the source line.

---

### W64 Mark for review — Apple Watch (reference 64)

**Platform and window.** watchOS; fourth vertical page; also reachable from the complication.

**Layout.**
1. "Point 42" (the current point: last scored point + 1, or the phone's resolved point after the receipt).
2. "No call yet."
3. Reason chips (optional, single choice): "Bounce uncertain" · "Check the score" · "Good moment".
4. Button "Mark for review" (dominant).
5. "Review video on phone" (phone icon).
6. "Sample".

After acceptance: "Marked for review · Point 42" + the chosen reason ("Bounce uncertain") + "Review video on phone".
While marks wait on the phone: a line "Review needed · 2 marks" under the button (from the bridge's `reviewNeeded`
alert; ADR-0028 Stage 1); it clears when the marks are reviewed on the phone. It never shows In/Out, a result or a
score change.

**Data bindings.** Current point number from the snapshot score; the command carries the reason, the point number seen
and the watch's monotonic issue time; the receipt carries `markId` and the phone-resolved point.

**States.** Ready; Pending ("Marking… · sends when your phone is back"); Accepted ("Marked for review · Point 42",
light haptic); Review needed ("Review needed · n marks"); Rejected ("Marks are off for this watch"); Expired after 12 h ("Not sent · mark it on the phone"); duplicate (one mark);
no match ("No match in progress"); bridge Unknown (pending still allowed); Sample.

**Interactions.** Chip selects a reason (tap again to clear). Mark for review → command. Never changes the score; never
shows In/Out.

**Accessibility.** "Point 42. No call yet. Mark for review, button." Chips read "Reason, bounce uncertain, not selected".
Receipt announced.

**Deliberate differences from the image.**
- "Bounce uncertain." as a headline → a reason the player chooses (v1 detects no bounces; a later review-only hint is
  A5 and must abstain visibly).
- Ball-on-line photograph removed (no officiating imagery); play-triangle icon on the button → mark icon.
- "Sample" chip at the top → footer label; custom "10:28" time and battery removed (system time).

---

### W65 Connection alert — Apple Watch (reference 65)

**Platform and window.** watchOS; full-screen alert (in-app) or notification (app not foreground).

**Layout.**
1. Clay warning icon.
2. "Camera 3 · Near left" (slot label from the snapshot).
3. "Status unknown".
4. "Last heard 18 s ago."
5. "May still be recording."
6. Button "Check on phone".
7. Button "Acknowledge" (secondary).
8. "Sample".

**Alert kinds and copy.** Camera Unknown (above). Room host lost: "Room host not heard · 20 s" / "Recordings continue on
each phone." Phone not reachable (raised on the watch): "Your phone isn't reachable" / "Last update 40 s ago." / "It may
still be recording." Own recording failed (critical): "Jon's phone stopped recording" / "12:34 saved." Own storage
critical (critical): "Jon's phone · 4 min of space left". Recovery clears silently ("Camera 3 heard again" in the list,
no haptic).

**Data bindings.** `alerts[]` from the phone's AlertPolicy (`jovra.room.watch-bridge/1`: stable `alertId`, kind,
device, age, `severity`, which is `critical` only for `ownRecordingFailed` and `ownStorageCritical`; a camera gone
Unknown is always deferred, ADR-0026 §8 as amended); the phone-unreachable alert from the watch's own echo state.

**States.** Raised (once per outage after ≥ 3 s Unknown); deferred haptic (non-critical, until the next point or 45 s);
critical (immediate, once); acknowledged (cleared on watch and phone); recovered (auto-clear after ≥ 4 s Fresh);
re-alert cap (same camera at most once per 5 min); notifications denied on the phone (in-app alert only; the phone's
settings show "Turn on notifications"); haptics off (visual only); ambient (dimmed, timestamped); Sample.

**Interactions.** Check on phone → hands off to the phone (Handoff user activity to the iPhone app's capture or lobby
screen; the watch says "Open JOVRA on your phone" — it cannot unlock or open the phone itself). Acknowledge →
`ackAlert`. No stop control, ever.

**Accessibility.** "Alert. Camera 3, near left, status unknown. Last heard 18 seconds ago. May still be recording.
Check on phone, button. Acknowledge, button."

**Deliberate differences from the image.**
- "Status stale" → "Status unknown" (one state word with W61's row; watch spec C6).
- "Camera 3" gains its slot label; the chevron on "Check on phone" kept.

---

### W66 Camera health — Wear OS (reference 66)

**Platform and window.** Wear OS, round; first pager page. Same data, states and interactions as W61.

**Variants.** 192 dp: count + basis + two rows; rotary scroll for the third and the button. 240 dp (Galaxy Watch
Ultra-class approximation): count + basis + three rows + EdgeButton. Rect sanity profile: same column, no curved text.
Largest font scale: rows wrap; page scrolls; no text in the corners.

**Layout.** Curved top label "JOVRA" with the system time text (`ScreenScaffold` time text); chip "Last-known"; "5/6"
large + "fresh"; basis "Recording · heard ≤ 5 s"; "Primary · 12:34"; rows in a `TransformingLazyColumn` (worst first):
"C3 · Unknown · 18 s" (clay ring), "C1 · 12:34 · 1 s", "C2 · 12:33 · 2 s"; `EdgeButton` "View all 6"; "Sample"; scroll
indicator on the right arc; page indicator at the bottom.

**Copy, data, states, accessibility.** As W61 (TalkBack wording identical).

**Deliberate differences from the image.**
- "Fresh recording" under the count → "fresh" + basis line (same words as watchOS).
- "JOVRA TENNIS" lockup → curved "JOVRA" label; the court-scene background and square case are not part of the UI.
- The orange "Unknown" text kept with a ring icon (meaning not by colour alone; visual-review revision for 66).

---

### W67 Score and undo — Wear OS (reference 67)

**Platform and window.** Wear OS, round; second pager page. Same data, states and interactions as W62.

**Layout.** Curved "JOVRA"; names with the server dot; "30 | 15" large; "Games 5–4"; chip "Manual · Synced"; two
vertically stacked full-width pill buttons "Jon point" / "Alex point" (≥ 48 dp, equal tonal style); compact chip "Undo
last"; "Sample"; right-arc scroll indicator. 192 dp: buttons stay stacked; "Undo last" scrolls into view with rotary
input.

**Deliberate differences from the image.**
- Players' photographs behind the score removed (contrast in sunlight, power, and nothing to show).
- "Manual | Synced" drawn as a two-segment toggle → a read-only chip (it is a status, not a control).
- "Alex point" clay → the same tonal style as "Jon point" (clay means attention in JOVRA's palette).
- Ball icons on the buttons removed (text labels suffice; icons crowd 192 dp).

---

### W68 Latest serve — Wear OS (reference 68; metric gate A5)

**Platform and window.** Wear OS, round; third pager page. Same data, states and copy as W63, laid out centrally:
heading "Latest serve"; v1 "Not measured live" + explanation (wraps within the circle); `EdgeButton` "Mark this serve";
"Sample". Value state (a post-capture estimate, as W63): "74 mph", "Estimated average speed, contact→bounce",
"Point 42 · Camera 1 · 8 s ago".

**Deliberate differences from the image.** As W63, plus: the ball-and-clay photograph and custom "10:24 · 92%"
removed; the value stays inside the round-safe centre.

---

### W69 Mark for review — Wear OS (reference 69)

**Platform and window.** Wear OS, round; fourth pager page. Same data, states and copy as W64: "Point 42", "No call
yet.", reason chips in a `TransformingLazyColumn`, `EdgeButton` "Mark for review", "Review video on phone", "Sample";
"Marked for review · Point 42" and "Review needed · n marks" as in W64.

**Deliberate differences from the image.**
- The on-screen back button "<" removed (Wear uses swipe to dismiss and the hardware back).
- The ball-on-line photograph removed; "Bounce uncertain." becomes a chosen reason (as W64).
- "Review on phone · Sample." drawn as a button → helper text "Review video on phone" + footer "Sample" (there is
  nothing to press: review happens on the phone).
- The pager dots kept as the page indicator.

---

### W70 Connection alert — Wear OS (reference 70)

**Platform and window.** Wear OS, round; full-screen in-app alert or the bridged phone notification. Same data, states
and copy as W65: clay warning icon, "Camera 3 · Near left", "Status unknown", "Last heard 18 s ago.", "May still be
recording.", `EdgeButton` "Check on phone" (opens the JOVRA phone app via the remote-activity helper — INFERRED API,
verify at G-WEARPAIR), button "Acknowledge", "Sample". Line breaks are chosen so every line fits the circle at 192 dp.

**Deliberate differences from the image.**
- "Camera 3 stale" → "Camera 3 · Near left" + "Status unknown" (watch spec C6).
- No stop control (kept from the image, which has none).

---

## 3. iOS foldable layout studies (references 71–72)

**Status.** Layout studies for an expanded iOS canvas (`implementation-states.json`: "A1 adaptive study"). Apple's
foldable iPhone was announced in September 2026 with retail availability stated for October 23; its hardware and
simulator are **UNVERIFIED** here. OBSERVED today: Xcode 26.6 with the iOS 26.5 runtime has no foldable iPhone device
type (`simctl list devicetypes`). No hinge or crease API is assumed and no Android folding API is imported. The
layouts respond only to SwiftUI size classes and the actual window size; they are tested on iPad simulators (iPad mini
A17 Pro, iPad Air 11-inch M4; installed, OBSERVED) in portrait and Split View widths, labelled "iPad stand-in", until a
foldable simulator or device exists. No hinge or crease precaution is applied: ADR-0025 §5 forbids hinge avoidance on
iOS until a verified API exists, so column boundaries follow the ordinary split-view layout, and a crease API, if
Apple ships one, is added by an ADR-0025 amendment after inspection.

---

### I71 Studio workspace on an expanded iPhone (reference 71; combines ST21, ST27 Film mode and ST34/35)

**Platform and window.** iOS (SwiftUI), expanded near-square canvas (regular width). Folded (compact width) it is the
ordinary phone Studio Home (ST21).

**Route and entry.** `studioHome` on the Home tab. At regular width it renders as a `NavigationSplitView`: sidebar
"Films" (projects and their films), content = the selected film's player, detail = the related lesson.

**Window variants.** Compact width (folded, or Split View narrow): ST21 unchanged; selecting a film pushes ST39.
Regular width: panes follow ADR-0025 §2–§3 applied to the scene size in points: three columns only at width Large
(≥ 1,200 pt) with height at least Medium (≥ 480 pt); two columns at Medium and Expanded width (600–1,199 pt; the
sidebar collapses to a toolbar button); height Compact allows at most two. AX text sizes: one column fewer than that,
never below one (ADR-0025 §3). Fold ↔ unfold: the selected film, playhead and lesson selection are preserved through
`SceneStorage` / restored navigation path; playback continues if the player view is retained, otherwise resumes paused
at the same time.

**Layout (expanded).**
1. Lockup with "Studio" kicker; headline "Your game, made into a story."; settings button.
2. Sidebar "Films" + "Build your match" button: FilmRows grouped by project — "Jon vs Alex · Court Memories · 04:18 ·
   Sample project" (selected) — from `studioFilms`.
3. Content: film player (VideoSurface) "01:24 / 04:18"; title "A good day on court"; "Court Memories · 04:18 · 1080p";
   actions "Save film", "Edit this film" (→ ST36), "More"; Sample badge; section "Points" with PointChips of the
   film's keepers.
4. Detail: "Lesson" → LessonRow "Oct 7 · Serve rhythm · 3 clips · Reviewed"; TodayFocusCard "Same toss. Calm finish." ·
   "2 of 3 drills complete"; clip list with stored labels; "Open lesson" (→ ST35).
5. Standard `TabView` (Home, Sessions, Record, Insights, Profile; placement as the system draws it at this size —
   UNVERIFIED on a foldable).

**Copy.** ST21, ST39 and ST34 strings; no new copy.

**Data bindings.** As ST21 (films, lessons) and ST39 (film record), Sample in demo.

**States.** ST21's states (no films, demo, cloud unavailable, last job failed, verifying, stale, no lessons) plus:
Layout changed (selection kept); Restored; no lesson linked (detail shows "Lessons this month" instead).

**Interactions.** Selecting a film updates content and detail; double-tap the player for full screen (ST27 Film mode for
Match Broadcast). 44 pt minimum targets throughout.

**Accessibility.** Three columns are separate containers with headers; VoiceOver order sidebar → content → detail;
Dynamic Type reduces columns.

**Deliberate differences from the image.**
- Header tagline "Capture. Analyze. Share." and the JV avatar removed.
- Invented projects ("Morning Practice", "Serve Session", "Rally Highlights", "Footwork Drill", "Evening Match"), 2024
  dates and filter chips "All / Matches / Training / Favorites" removed: the sidebar lists real films only.
- Film description "A great match with long rallies, smart shot selection…", tags "Match / Highlights / Rally /
  Strategy" and "Key moments · Rally winner / Key point / Set up the finish" with their captions removed (invented
  assessments and classifications) → PointChips of the film's keepers.
- Lesson clip names "Toss & timing / Racket path / Follow through" with durations → stored clip labels; lesson subtitle
  "Find a smooth and repeatable rhythm…" → the lesson's focus line.
- Quote card "Small changes create big progress." removed; the Record "+" raised disc → the standard tab item.

---

### I72 Camera desk on an expanded iPhone (reference 72; ST24 at regular width plus the watch panel)

**Platform and window.** iOS, expanded canvas; full-screen capture route (tab bar hidden), forest in both appearances.
Folded it is ST24.

**Route and entry.** `directorCapture(projectId)` from ST23 "Go to capture".

**Window variants.** Compact (folded): ST24 portrait. Expanded portrait-square: preview in the upper area, device rows
lower-start, watch panel lower-end. Landscape: preview start, rows and watch panel end. Capture continuity across fold
/ unfold is a hardware test: saved segments are kept and an interruption is shown explicitly ("Recording interrupted ·
0:03 gap"); nothing is promised before a device run.

**Layout (expanded).**
1. Compact header: "● REC 12:34", kicker "Studio capture", "More".
2. Primary preview "Primary · Live", "Camera 1 · Baseline", chip "Sample capture", score chip or "No score".
3. Header "Recording on 3 of 3 phones" with "Status heard in the last 5 s: 2 of 3".
4. DeviceHealthRows: "Camera 1 · Recording 12:34 · heard 1 s ago"; "Camera 2 · Recording 12:33 · heard 2 s ago";
   "Camera 3 · Unknown · heard 18 s ago · may still be recording"; each with battery and storage; "View all 6".
5. Watch panel: "Paired watch" · "Status and marks" · "Last updated 2 s ago" (bridge freshness; "Not updated for 40 s"
   when stale).
6. Controls: "Mark point" (64 pt), Stop disc (76 pt) → stop-one / stop-all sheet, "More". "Saved through 12:34".

**Data bindings.** As ST24 / A44 plus the WatchBridge state.

**States.** All ST24 states with the freshness vocabulary (§7 C-A1), plus watch states (none paired: panel hidden; app
missing: "Install JOVRA on your watch"; Unknown bridge), Layout changed, Interrupted, Restored.

**Interactions.** As ST24. The watch panel opens the watch abilities sheet (A43 copy).

**Accessibility.** As ST24; the watch panel reads "Paired watch, status and marks, last updated 2 seconds ago".

**Deliberate differences from the image.**
- Status bar "9:41 Mon Jun 10" (an iPad-style date that is also wrong) → the system status bar, hidden on the capture
  route where appropriate.
- Headline "Your game, made into a story." / "Capture. Analyze. Share." removed (this is capture, not Studio Home).
- "Sample capture. · Clay Court · Rear View" → chips "Sample capture" and "Camera 1 · Baseline" (surface and view
  names are not data).
- Audio-level glyphs beside "Heard 1s" removed (they imply live audio); row thumbnails (a ball on a line, a net) →
  each phone's own still with its age once `jovra.room.still/1` exists (F-ROOM-STILL); until then the slot's mini
  diagram.
- "Add Marker" → "Mark point"; "Start Capture" and "View Sessions" removed (recording is already running; navigation
  leaves capture through Close); the tab bar removed (focused route).

---

## 4. Platform mappings

### 4.1 Android Studio screens 41–60 ↔ iOS Studio screens 21–40

| Android | iOS | Shared route vocabulary | Android-specific differences |
|---|---|---|---|
| A41 Studio Home | ST21 | `studioHome` / `StudioHome` | NavigationSuiteScaffold; fold two-pane |
| A42 Build your match | ST22 | `buildMatch` | slot sheets as bottom sheets; Home selected |
| A43 Camera lobby | ST23 | `cameraLobby` | NSD picker / nearby-devices permission; new Watch row (recommended for ST23) |
| A44 Director capture | ST24 | `directorCapture` | guarded back ("Stop recording?"); ongoing notification while recording in front; tabletop variant; freshness vocabulary; stills after F-ROOM-STILL |
| A45 Source import | ST25 | `sourceImport` | Photo Picker and document picker; WorkManager copying |
| A46 Sync workspace (fold) | ST26 | `syncReview`/`syncDesk` → one `Sync` key | layout by window class; two panes at the hinge, three at Large |
| A47 Match Broadcast replay (fold) | ST27 | `projectPlayer` | rail kept at Medium+; tabletop video-over-controls |
| A48 Angle insights | ST28 | `angleInsights` | measurement row named "Serve speed estimate" |
| A49 Story modes | ST29 | `storyModes` | ADR-0023 length chips; Format dropdown |
| A50 Coach's Cut | ST30 | `storyProfile(coach-cut)` | chapter tab row |
| A51 Rally Pulse | ST31 | `storyProfile(rally-pulse)` | stepped Slider |
| A52 Progress Story | ST32 | `progressStory` | — |
| A53 Court Memories | ST33 | `storyProfile(court-memories)` | — |
| A54 Lesson journal | ST34 | `lessonJournal` | extended FAB; becomes A55's list pane at Medium+ |
| A55 Lesson workspace (tablet) | ST35 | `lesson` | ListDetailPaneScaffold / three panes at Large; resizable panes |
| A56 Film storyboard (tabletop fold) | ST36 | `storyboardList`/`storyboard` → one `Storyboard` key | tabletop posture; focused route |
| A57 Cloud preflight quote | ST37 | `preflight` | full screen, not a sheet; credits; breakdown in a modal bottom sheet; no purchase flow in v1 |
| A58 Render queue | ST38 | `job` | WorkManager foreground worker; notification permission in context |
| A59 Film delivery | ST39 | `film` | Save to device (MediaStore) and Save to Files (document create) |
| A60 Studio settings | ST40 | `studioSettings` | no iCloud; export folder via `OpenDocumentTree`; Watch section |

### 4.2 iOS core screens 01–20 → Android core equivalents (by name; no Android 01–20 references exist)

The Android core app is specified now, in parallel with iOS (`docs/spec/android-v1-spec.md`, ADR-0024; its screens
A01–A20 map to S01–S20); this table fixes the names so Studio entry points and shared routes line up.

| iOS core | Android core equivalent | Route key | Android-specific notes |
|---|---|---|---|
| S01 Welcome | Welcome | `Welcome` (pre-shell) | splash API; edge-to-edge forest; "Look around first" → demo |
| S02 Player onboarding | Onboarding | `Onboarding(step)` | pager with predictive back between steps; no permissions requested here |
| S03 Home | Home | Home root | StudioEntryCard; avatar → Profile destination |
| S04 Session setup | Record | Record root | segmented buttons / exposed dropdowns for format; Start → `Capture` |
| S05 Court framing and calibration | Capture · framing | `Capture(sessionDraft)` | CameraX preview, focused route, landscape; tabletop variant |
| S06 Live capture | Capture · recording | `Capture` | CaptureEngine while the screen is in front (no background recording in v1); ongoing notification in place of the Live Activity (core N9); guarded back; thermal from `PowerManager` |
| S07 Import and processing | Import | `Import` (Sessions) | Photo Picker / document picker; WorkManager with progress notification |
| S08 Session library | Sessions | Sessions root | `ListDetailPaneScaffold` (library list ∣ match overview) at Medium+ |
| S09 Match overview | Match overview | `MatchOverview(sessionId)` | detail pane at Medium+; "Make a film" → A49 |
| S10 Smart replay and point correction | Replay | `Replay(sessionId, pointId?)` | Media3 exact seek and frame step; supporting pane (event timeline, corrections) at Expanded; tabletop |
| S11 Shot placement | Shot placement | `ShotPlacement` (Insights) | court diagram from shared geometry |
| S12 Serve Lab | Serve Lab | `ServeLab` | serve speed estimate stays capability-gated |
| S13 Stroke Lab | Stroke Lab | `StrokeLab` | pose capability off by default (ML Kit beta) |
| S14 Video comparison | Compare | `Compare(...)` | two panes split at the hinge; one pane at Compact |
| S15 Coaching plan (Insights home) | Insights | Insights root | entries to A48, A52, A54 |
| S16 Progress | Progress | `Progress` | — |
| S17 Racket Vault | Racket Vault | `RacketVault` (Profile) | brand names only as user text |
| S18 String journal | String journal | `StringJournal` | — |
| S19 Storage and backup | Storage and backup | `StorageBackup` | MediaStore / app storage; Google Drive later via AuthorizationClient; no iCloud |
| S20 Settings and privacy | Settings | `Settings` | per-app language, notification settings, data export and deletion; contact text only |

### 4.3 Watch parity

| watchOS | Wear OS | Shared surface | Shape-specific differences |
|---|---|---|---|
| W61 | W66 | Camera health | rectangular rows vs round column with EdgeButton and curved label |
| W62 | W67 | Score and undo | side-by-side vs stacked point buttons |
| W63 | W68 | Latest serve | — |
| W64 | W69 | Mark for review | Crown scroll vs rotary + swipe-to-dismiss |
| W65 | W70 | Connection alert | Handoff vs remote activity for "Check on phone" |

### 4.4 iOS foldable studies

I71 ↔ ST21 + ST39/ST27 Film mode + ST34/ST35 (expanded composition). I72 ↔ ST24 at regular width + the watch panel
(also A44's watch information and A43's Watch row).

### 4.5 iOS core and Studio screens on ADR-0025's table (iPhone, iPad, expanded iPhone canvas)

ADR-0025 applies one breakpoint table to both platforms (iOS in points from the scene's container size; never
`userInterfaceIdiom`). The two iOS studies (I71, I72) do not prove the rest of the app adapts, so every iOS core and
Studio screen is mapped here. Pane counts are maxima: "C" compact width, "M/E" medium and expanded width, "L" large and
wider with height at least Medium; height Compact allows at most two (the player keeps priority); accessibility text
sizes remove one pane, never below one. This is a layout plan for the iOS owners (`screens.md`, `studio-screens.md`),
not an edit of those specs; differences they choose are recorded there.

| iOS screens | C | M/E | L | Preserved across resize, rotation, Split View and terminate/relaunch (IDs in the restored navigation path or `SceneStorage`; drafts on disk) |
|---|---|---|---|---|
| S01 Welcome, S02 Onboarding | 1 | 1 (readable width) | 1 | onboarding step |
| S03 Home | 1 | 1 (wider card grid) | 1 | scroll position |
| S04 Session setup | 1 | 1 | 1 | setup draft (disk) |
| S05 Framing, S06 Live capture | 1 (full screen) | 1 | 1 | none beyond the capture journal; relaunch runs the recovery scan and shows "Saved through" |
| S07 Import and processing | 1 | 2 (queue ∣ item) | 2 | job ids (persisted before work starts) |
| S08 Library, S09 Overview | 1 | 2 (list ∣ overview) | 2 | selected session |
| S10 Replay and correction | 1 (+ sheets) | 2 (video ∣ points and corrections) | 2 | session, point, playhead (rational time; restored paused), correction draft |
| S11 Shot placement, S12 Serve Lab, S13 Stroke Lab | 1 | 2 (court or video ∣ detail) | 2 | selection, filter |
| S14 Compare | 1 (stacked) | 2 (side by side) | 2 | both clips, both playheads |
| S15 Insights, S16 Progress | 1 | 2 (list ∣ detail) | 2 | selected item |
| S17 Racket Vault, S18 String journal | 1 | 2 (list ∣ detail) | 2 | selected item, edit draft |
| S19 Storage and backup, S20 Settings | 1 | 2 (sections ∣ detail) | 2 | selected section; archive job ids |
| ST21 Studio Home | 1 | 2 | 3 (I71) | selected film and lesson |
| ST22 Build your match | 1 | 2 (diagram ∣ slot details) | 2 | slot choices (draft) |
| ST23 Camera lobby | 1 | 2 (invite ∣ roster) | 2 | invite id; remote status restored **Unknown** |
| ST24 Director capture | 1 | 2 (preview ∣ rows) (I72) | 2 | as S06; remote rows restored **Unknown** |
| ST25 Source import | 1 | 2 (list ∣ source facts) | 2 | selected sources, import job ids |
| ST26 Sync review / desk | 1 (sheets) | 2 (stills and lanes ∣ review card) | 3 | anchor edits (draft), checkpoint progress |
| ST27 Project player | 1 | 2 (video ∣ angles and points) | 2 | project, film, angle, playhead, mode, rate |
| ST28 Angle insights | 1 | 2 (pair ∣ observation) | 2 | observation |
| ST29–ST33 Story modes and profiles | 1 | 2 (cards ∣ options) | 2 | profile, length, options |
| ST34 Lesson journal, ST35 Lesson workspace | 1 | 2 (list ∣ lesson) | 3 (list ∣ clip ∣ notes) | lesson, clip, note draft |
| ST36 Storyboard | 1 (beat list + sheets) | 2 (preview ∣ timeline) | 2 | plan version, selected beat, draft cut |
| ST37 Quote | 1 | 2 (summary ∣ quote) | 2 | quote id, consent (only while that quote is valid), idempotency key |
| ST38 Job, ST39 Delivery, ST40 Studio settings | 1 | 2 | 2 | job id, film id |

**iOS preserved-state test plan** (each a check that can fail; reported per simulator profile, labelled "iPad stand-in"
for any foldable claim): for every row, on an iPhone 17-family simulator and an iPad simulator in Split View, (1) drive
compact → expanded → compact by resizing the Split View and assert the same selection and no network side effect;
(2) rotate; (3) background, `xcrun simctl terminate`, relaunch, and assert the restored path, a paused playhead at the
saved rational time, drafts reloaded from disk and remote status shown Unknown; (4) repeat at the largest accessibility
text size and with VoiceOver on; (5) assert that no job, quote acceptance, score command, upload or invite was sent
twice (ADR-0025 §7). Owners: the iOS core and Studio screen specs adopt or amend this table; until they do it is the
default for iOS tickets.

---

## 5. State coverage and the acceptance matrix

Every state named in §1–§3 is reachable in demo by a launch argument (`-adaptiveState <screen>.<state>` on Android via
an intent extra in debug builds; `-studioState` / `-watchState` on Apple) for screenshots and accessibility audits.

| Acceptance-matrix scenario (`acceptance-matrix.md`) | Screens | Required result here |
|---|---|---|
| Phone↔fold inner/outer; rotation; split screen | all A41–A60, I71, I72 | §0.3 contract; no duplicate render, score or charge |
| Hinge/occlusion/compact height | A46, A47, A55, A56, A57 | panes per §0.2; consent and confirm never hidden by the IME |
| Process death | all | drafts restored; remote status Unknown; pending commands reconcile |
| Expired/replayed invite | A43 | refused; nothing exposed |
| Wrong host/session/epoch; arbitrary QR endpoint | A43 | refused |
| Camera reports Recording but receiver hears nothing | A44, I72, W61, W66 | elapsed frozen; Unknown with age; may still record |
| Phone fresh but watch bridge stale | W61–W70 | Unknown on the watch |
| Queued watch snapshot after suspension | W61–W70 | Unknown until echo |
| Duplicate identical command | A57 (idempotency), W62, W64 | original receipt; one effect |
| Same command ID, different payload | W62, W64 | Rejected |
| Two scores against one revision | W62, W67 | one update, one conflict |
| Undo/correct earlier point | W62, A47 (score bug), A56 (score lane) | recompute from the event log |
| Offline score/marker | W62, W64 | pending draft visible |
| Viewer attempts stop-all/score | W62, W65, A44 | denied |
| Start with permission denied / phone backgrounded | A44, I72 | explicit Not recording state |
| Stop one/all partial failure | A44, I72 | per-device results |
| Host/network disappears | A43, A44, W61, W65 | local originals survive; new epoch reconciles |
| Watch rectangular vs round; large fonts | W61–W70 | no clipping; reachable controls; labels |
| Haptics/always-on/low power | W61–W70 | deduplicated, quiet during play, timestamped |
| Serve capability absent/calibration missing | W63, W68, A48 | explanation; no number |
| Result older than current point | W63, W68 | shown as old with point and age |
| Bounce ambiguous/occluded/uncalibrated | W64, W69, A48 | review marker only; no score change |
| Six-device endurance | A44, W61 (field gate) | measured separately (A4) |

---

## 6. Verification plan and what was measured

**Measured layout/device verification: none.** No build, emulator, simulator, watch or device was run for this spec.

**Inventory (read-only, OBSERVED on 2026-10-07).**
- Android: platforms 35 and 36, one system image (android-35 google_apis arm64), device profiles `pixel_9`,
  `pixel_9_pro_fold`, `pixel_tablet`, `medium_phone`, Wear round/rect profiles; no Wear, Play-Store or API 36 image;
  the only AVD belongs to another project (`toolchain-and-devices.md` §2; not re-run today).
- Apple: Xcode 26.6; iOS 26.5 and watchOS 26.5 runtimes; iPhone 17 / 17 Pro / Air, iPad mini (A17 Pro), iPad Air 11"
  (M4) and others; Apple Watch SE 3 (40/44 mm), Series 11, Ultra 3 (49 mm); no foldable iPhone device type. Two iPhone
  simulators were booted by other work and were not touched.

**Gates for these screens (each reported separately).**

| Gate | Screens | Evidence | Blocked by |
|---|---|---|---|
| Native UI (Android) | A41–A60 | build on Lane A; Roborazzi screenshots per state at 360, 411, 852 × 883 (fold inner), 1280 × 800; Compose UI tests including `window-testing` injected hinges (separating vertical, tabletop horizontal, occluding); TalkBack semantics assertions; font scale 2.0; state restoration via `StateRestorationTester` and process-death recreation | G-RESOLVE |
| Native UI on emulators | A41–A60 | the four proposed AVDs (`jovra_phone_p9_api35`, `jovra_fold_p9pf_api35`, `jovra_tablet_ptab_api35`, `jovra_compact360_api35`), created one at a time; posture changes on the fold AVD; split screen; predictive back | disk (14 GiB free), coordination with other projects |
| Android 16 large-screen behaviour | A46, A47, A55, A56 | orientation/resizability override on an API 36 image | G-IMG36 |
| Watch UI | W61–W65 / W66–W70 | watchOS simulator SE 3 40 mm and Ultra 3 49 mm; Wear Roborazzi at 192/240 dp and rect, then Wear emulator | G-WEARIMG for the emulator |
| Watch transport | W61–W70 | simulator pair (watchOS); Play-image phone + Wear emulator pairing (Jon signs in himself) | G-WEARPAIR |
| iOS expanded study | I71, I72 | iPad stand-in screenshots at Split View widths; foldable simulator when available | foldable SDK availability (UNVERIFIED) |
| Hardware | A44, I72, W-all | physical Pixel / Galaxy phones and fold, iPhone, Apple Watch, Galaxy Watch: capture continuity across fold, thermals, haptics, background delivery | physical devices |

Approximated profiles (Pixel 10-class, Pixel 10 Pro Fold outer, Galaxy S26-class, Galaxy Watch Ultra) are labelled
approximations in every report; they are not device validation.

---

## 7. Conflicts and recommendations (not silently resolved)

- **C-A1 · Stale-device wording.** ST24 "No contact for 0:42 · it may still be recording on its own" vs the adaptive
  vocabulary "Unknown · heard 18 s ago · may still be recording". Android (A44), the watches and I72 use the adaptive
  vocabulary; recommended for ST24 so all surfaces agree (watch spec C2).
- **C-A2 · One route key per adaptive task on Android.** iOS keeps separate phone/iPad routes for sync and storyboard;
  Android uses one key each because windows change mid-task. Not a behaviour difference; recorded so route tests do not
  expect four keys.
- **C-A3 · Watch row in the lobby.** A43 adds a "Watch" section (role + freshness); recommended for ST23 and ST40 so the
  iPhone shows the same information. *Owner since 2026-10-07:* the watch spec (WD13) owns the phone-side bridge and the
  "Paired watch" rows on both OSes.
- **C-A4 · Quote units.** ST37's copy shows "$4 – $8" / "$12" (Sample); ADR-0023 prices films in credits and
  pricing-matrix-v2 recommends showing only credits on the quote. A57 shows credits from `quote.sample-illustrative.json`;
  recommended for ST37 (owner: the Studio screens workflow). A58's budget-exhausted copy follows the same unit.
- **C-A5 · ST28 fixture text vs the observation record.** ST28 §0.6 says "Recovery step · Estimated · Camera 3 · Point
  18 · 24:12"; `observation.estimated-cue.json` is a serve-rhythm cue on camera-1 at point p-041, 20:16. Both apps
  should render the record; the Studio owner reconciles the prose.
- **C-A6 · Story lengths.** ST29 and story 119 offer "3 min · 5 min · Full"; ADR-0023 sets tiers 3, 5, 10, 15, 20, 25, 30
  min and Full. A49 uses the ADR tiers intersected with each profile's range; recommended for ST29. *"Full" defined
  2026-10-07:* the profile's maximum bounded by coverage (ST29's meaning); for Match Broadcast it coincides with
  ADR-0023's "Full match" (every point, dead time trimmed). android-v1-spec story 265 uses the same definition.
- **C-A7 · Court Memories chapter names.** The adaptive brief says "Match" / "After the match"; the EDL fixture and ST33
  say "The match" / "The moment after". A53 follows the fixture.
- **C-A8 · "Preview story" vs "Create this memory".** Reference 53's bottom action is "Preview story"; ST33's is "Create
  this memory". A53 follows ST33 (one behaviour across platforms).
- **C-A9 · Sample score at point 42.** The watch sample and reference 47 show 5–4, 30–15; the core sample at point 42 is
  set 1, 4–3 Alex, Jon 30–15, Alex serving. The player (A47) always renders the fold; the watch sample stays a separate
  Sample set (watch spec C7).
- **C-A10 · Slot names.** ST22 names slot 3 "Near left"; ST23's lobby fixture labels Camera 3 "Corner left". Android
  uses the slot name from data in each place; recommended to the fixture owner to pick one.

## 7a. Review findings (2026-10-07)

A review of this spec against ADR-0024–0028, `spec/room`, `android-v1-spec.md`, `watch-v1-spec.md` and
`pricing-matrix-v2.md` raised these findings. Each was confirmed by reading the cited lines (OBSERVED) and fixed here
unless noted:

| Finding | Severity | Result |
|---|---|---|
| Back leaves capture while a foreground `RecordingService` keeps recording (§0.1, §0.3, A44) vs android-v1-spec AD13 and "Capture"; "process death: the service still records" | HIGH | Fixed: guarded back "Stop recording?", no background recording, process death ends the recording and the recovery scan restores it (§0.1, §0.3, A44, §4.1, §4.2, platform table) |
| §0.2 made height Compact one pane | HIGH | Fixed to ADR-0025 §3 (at most two; the player keeps priority); font scale unconditional |
| I71 three columns at ≥ 1,000 pt and a crease precaution | HIGH | Fixed: ADR-0025 breakpoints; no hinge or crease precaution on iOS (§3 status, I71) |
| Sources omitted ADR-0024–0028; §4.2 said Android core waits for the iOS gates | HIGH | Fixed (header, §4.2) |
| Play Billing on A57 and §4.1 | HIGH | Fixed: no purchase flow in v1 |
| Three quote screens; Jon's price toggle absent from A57 | HIGH | Fixed: one screen (A57 = android-v1-spec Quote UX = pricing-matrix-v2 §8 as revised): shipped range + cap, length chips, Film quality and per-angle drivers in a modal bottom sheet |
| Dual-provider consent was singular | MEDIUM | Fixed in copy (both services and their retention); the quote contract's per-provider consent is open (F-QUOTE-CONSENT) |
| A49 "Full" undefined; C-A6 incomplete | MEDIUM | Fixed (A49 item 4, C-A6) |
| Watch abilities sheet granted marks by default | MEDIUM | Fixed: the sheet narrows the phone's own rights (A43) |
| Stills, still requests and clock pings not in Room contract v1 | MEDIUM | Gated: A44 and I72 show stills only after F-ROOM-STILL |
| iOS adaptive coverage beyond I71/I72; iOS phone-side bridge owner | MEDIUM | Fixed: §4.5 table and test plan; C-A3 owner (watch spec WD13) |
| Watch "Review needed" state (ADR-0028) | MEDIUM | Fixed (W64, W69) |
| Latest serve in v1 and three strings for one state | HIGH/LOW | Fixed (W63, W68: post-capture estimate when it exists; "Not measured live" otherwise) |

None was rejected.

## 8. Open questions

1. **Rail on workspaces.** Android keeps the navigation rail on the sync, player and lesson workspaces at Medium+ (the
   references draw it) while iOS hides the tab bar on its full-screen routes. Keep the platform difference?
2. **"Use local replay" naming** (ST37 open question 3) applies to A57 too.
3. **Watch section placement.** Lobby (A43) and Studio settings (A60) both show the paired watch; should the core
   Profile → Settings also list it once a watch app exists?
4. **Default length** on A49 when the profile allows 5 min and the match is short: 3 min or the longest that fits?

## 9. Sources

- `design-reference/adaptive/screens/41…72-*.png` (all 32 viewed), `design-reference/adaptive/brief/*`
- `docs/handoff/adaptive-v3/CLAUDE-ADAPTIVE-WATCH-PROMPT.md`, `START-HERE.md`; `.claude/skills/jovra-adaptive-native-ui`,
  `.claude/skills/jovra-watch-companion`
- `docs/spec/studio-screens.md`, `docs/spec/studio-v1-spec.md` (SD1, SD5, SD10, SD17), `docs/spec/screens.md` (§0.1,
  S01–S20), `docs/spec/watch-v1-spec.md`
- `spec/studio/contracts/story-profiles.v1.json`, `credit-classes.v1.json`; `spec/studio/fixtures/records/*`
  (observation, lesson, quote, render-job, storage-providers, camera-invite, sync-map, edit plans);
  `spec/fixtures/sample/jon-vs-alex.expected.json`
- ADR-0001, ADR-0002, ADR-0003, ADR-0010, ADR-0012, ADR-0019, ADR-0023, ADR-0024–0028; `GLOSSARY.md`
- `spec/room` (README, schemas, `fixtures/records/watch-bridge.*.json`); `docs/spec/android-v1-spec.md`
- `docs/research/android/toolchain-and-devices.md`, `docs/research/studio/multicam-sync.md`,
  `docs/research/studio/pricing-matrix-v2.md`
- Read-only inventory on 2026-10-07: `xcodebuild -version`, `xcrun simctl list runtimes|devicetypes|devices|pairs`
