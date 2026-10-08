# JOVRA Studio screen specification (references 21–40)

Status: implementation-ready draft, 2026-10-07. Scope: the twenty Studio reference screens (`ST21`–`ST40`), their
auxiliary sheets and alternative states, and the design-system additions they need. Product behaviour, modules and
stages are in `docs/spec/studio-v1-spec.md` (cited as "Studio spec", decisions `SD…`); core screens and components are
in `docs/spec/screens.md` (cited as "core"; screens `S01`–`S20`, `N1`–`N12`). Nothing here edits a core screen; the
four Studio entry rows the core screens need are listed in §0.1 for the S0 ticket that adds them.

**Sources, in precedence order.** Studio spec decisions → `CLAUDE.md` hard rules → ADRs → core lead decisions D1–D12 →
`design-reference/studio/brief/screens.json` (exact copy) and `implementation-states.md` (required states and sample
truth) → `story-profiles.json` → the PNG references in `design-reference/studio/screens/` (layout, rhythm, hierarchy
only). The references are generated images of fictional people and data: where an image disagrees with a source
above it, the source wins and the difference is listed under "Deliberate differences". Every reference PNG was viewed
for this spec.

**Component names** are the foundation design system's (`JovraScreen`, `JovraLockup`, `CourtArcMark`,
`EditorialCard`, `.jovraCard()`, `StatTile`, `FilterPills`, `ProvenanceBadge`, `StatusPill`, `SectionHeader`,
`AvatarInitial`, `SettingsRow`, `SettingsChevron`, `JovraButtonStyle` `.jovraAccent` / `.jovraPrimary` /
`.jovraSecondary`, `ComingLaterCard`, `CourtLinesBackdrop`, `JovraTabBar`, `Color.jovra(.role)`, `Space`, `Radius`,
`HitTarget`, `Font.jovra*`) plus the components core §5 defines (`StateCard`, `BannerView`, `Toast`, `UndoBar`,
`DemoBanner`, `InfoCard`, `FocusedHeader`, `FractionPopover`, `VideoSurface`, `VideoScrim`, `ScoreboardOverlay`,
`SampleBadge`, `FixtureBadge`, `TransportBar`, `JogStrip`, `EventTimeline`, `GapChip`, `AnnotationLayer`,
`StageTimeline`, `ProviderRow`, `ToggleRow`, `CourtGeometry`, `CourtDiagram`, `CourtMarker`, `RecordingStatusPill`,
`BatteryPill`, `SaveHeartbeatLabel`, `HeatBanner`, `CaptureControlButton`, `ScorePad`, `CourtModeView`, `SessionCard`,
`CapabilityDetail`). New Studio components are **bold** on first use per screen and defined in §4.

**Evidence labels.** Platform facts are tagged OBSERVED / INFERRED / UNVERIFIED as in the Studio spec. Everything on
these screens is design; nothing is built yet.

---

## 0. Conventions that apply to every Studio screen

### 0.1 Navigation, routes and entry points (no sixth tab)

Studio adds routes to the existing shell (core §0.1); the tab bar stays **Home · Sessions · Record · Insights ·
Profile** and Studio never replaces a tab (SD1). A push route keeps the tab that pushed it selected.

| Entry point (core screen) | New row the S0 ticket adds | Opens |
|---|---|---|
| Home (S03), below the editorial card | **StudioEntryCard**: "JOVRA Studio" · "Your game, made into a story." · chevron | ST21 (push, Home stack) |
| Match overview (S09), action row | "Make a film" (`film.stack` symbol) | ST29 for that session (push, Sessions stack) |
| Insights root (S15), Explore list | "Lesson journal", "Progress Story", "Angle insights" | ST34, ST32, ST28 (push, Insights stack) |
| Profile hub (N11), settings group | "Studio settings" | ST40 (push, Profile stack) |

| Kind | Tab bar | Routes |
|---|---|---|
| Push | visible | `studioHome` (ST21), `studioFilms` (film list from "View all"), `buildMatch(projectId?)` (ST22), `cameraLobby(projectId)` (ST23), `sourceImport(projectId)` (ST25), `syncReview(projectId)` (ST26 on phone), `angleInsights(projectId, observationId?)` (ST28), `storyModes(projectId)` (ST29), `storyProfile(projectId, profileId)` (ST30–ST33; Match Broadcast's options live on ST29 → ST27), `progressStory(scope)` (ST32), `lessonJournal` (ST34), `lesson(lessonId)` (ST35), `storyboardList(planId)` (ST36 on phone), `preflight(jobDraft)` (ST37), `job(jobId)` (ST38), `film(filmId, version?)` (ST39), `studioSettings` (ST40) |
| Full screen (`FullScreenRoute`) | hidden | `directorCapture(projectId)` (ST24), `projectPlayer(projectId, filmId?)` (ST27), `syncDesk(projectId)` (ST26 on iPad), `storyboard(planId)` (ST36 on iPad) |
| Sheet | unchanged | the auxiliary sheets in §2 |

Each full-screen route has a ≥ 44 pt Close at top leading, labelled for VoiceOver ("Close Match Broadcast"), and
system swipe-down only where no gesture conflicts (never during Studio capture). Deep links: `jovra://studio/film/<id>`
opens ST39; the lobby join payload (`jovra-room:1:…`) is accepted **only** by the in-app scanner, never as a URL.

### 0.2 Copy rules (Studio additions to core §0.2)

1. `screens.json` wins over pixels. Generated-image typos are fixed silently ("2--6" → "2–6", "1. Vide" → "Arrival").
   Subtitles and taglines that appear in an image but not in the brief are replaced by brief-sourced lines (each
   screen lists them). The gallery "title" field of a brief entry is used as the screen's subtitle where the image
   shows a different on-screen title.
2. Provenance words only Manual, Estimated, Reviewed, Validated; Sample is a separate label (`ProvenanceBadge(.sample)`);
   undecided values say "Needs review". Sync states use the same words: Estimated, Needs review, Reviewed.
3. Glossary terms: "Mark point" (never "Bookmark"), "point" (never "rally" for a scoring unit; "Rally 18" → "Point 18"),
   "percentage points", "film" (never "highlight reel", a core export).
4. Money: any amount in demo or test reads "Sample quote"; no amount is ever shown as a price until SD4. No payment
   logos, no provider jargon in the normal flow.
5. No model, provider or vendor names in normal player flows. Studio settings → Advanced exists only in Test mode and
   shows the configured planner there; in Live the planner is server configuration set by the founder, and a film's
   receipt names the planner that made it (spec "Design system and copy", story 247).
6. Times: match-clock and film times as `mm:ss` (`h:mm:ss` past an hour) with `Font.jovraTimecode`; precise editing
   times as `mm:ss.SSS` (ST26, ST36). Storage remaining as "2 h 10 min left" (VoiceOver "2 hours 10 minutes of storage
   left"), never a bare "02:10".
7. Contact: only `hello@islanddevcrew.com` as selectable text (hard rule 7), and only in Studio settings → Help.

### 0.3 State vocabulary additions (core §0.3 applies)

| State | Meaning | Default treatment |
|---|---|---|
| **Local demo** | Studio sample with DemoCloudClient | `DemoBanner` "You're exploring the Studio sample."; Sample badges; cloud actions say "Demo mode does not upload or charge" |
| **Cloud unavailable** | CloudMode `unavailable(reason)` or not configured | Cloud rows show the reason; local paths unchanged; never an error colour for an unbuilt feature |
| **Planned** | A provider or capability with no implementation yet | `StatusPill(.neutral)` "Planned"; row not tappable except for an explanation |
| **Stale** | Built from an older event, sync or keeper revision | `StatusPill(.attention)` "Made before a correction" + "Rebuild" |
| **Verifying** | Render finished, verification running | "Checking every frame…" with determinate progress over decoded frames; never "ready" |
| **Needs review (sync)** | Alignment below auto-approval thresholds | `StatusPill(.attention)` "Needs review" + the reason in words |
| **No coverage** | An angle has no media at this match time | Hatched placeholder "No video here" + gap reason; never a frozen frame |
| **Awaiting acknowledgement** | A camera has not confirmed recording | Clay ring symbol + "Not confirmed"; never counted as recording |
| **Unsupported (not yet)** | A Studio stage not shipped in this build (e.g. pairing before S3) | `StateCard` stating the alternative path, not a dead end |

### 0.4 Accessibility baseline

Core §0.4 applies unchanged (44 pt targets, AX5 Dynamic Type without truncated controls, one header per screen,
meaning never by colour alone, Reduce Motion, Increase Contrast, `performAccessibilityAudit` in UI tests). Studio
specifics:

- **Time surfaces are adjustable elements**: the match-clock scrubber (ST27), every sync lane (ST26) and the storyboard
  timeline (ST36) step by point (swipe up/down) and by frame in a "Frame" rotor; the value reads time, point and state
  ("12 minutes 46 seconds, point 42, Camera 2 needs review").
- **Selection** uses fill + check + weight + `.isSelected` (profile cards, angle thumbnails, slot markers).
- **Film text** honours the EDL hold rule (`max(2.0 s, 0.6 s + 0.3 s × words)`), ≤ 3 flashes per second, and the clean
  alternate under Reduce Motion (SD17). In-app previews announce chapter changes to VoiceOver.
- **Capture (ST24)** controls are ≥ 64 pt (Stop 76 pt) as in core S06; acknowledgement changes are announced
  ("Camera 3 confirmed recording").
- **Haptics**: selection on profile/angle/slot changes; success when a film becomes ready or a sync is confirmed;
  warning on a missing acknowledgement, heat or storage warning. All have visible equivalents.

### 0.5 Phone vs iPad

- **Phone (compact width)** is the reference for portrait screens; Studio flows are **sequential**: one decision per
  screen, advanced controls in focused sheets with detents, the player first. Smallest width 320 pt; no horizontal
  scrolling except deliberate carousels (angle strip, chapter cards).
- **iPad (regular width)**: portrait references render in `JovraScreen`'s 720 pt column; the four landscape
  references (ST26 Sync desk, ST27 Match Broadcast, ST35 Lesson workspace, ST36 Storyboard) are **iPad workspaces**
  (multi-pane, keyboard shortcuts: space play/pause, ←/→ frame, ⇧←/⇧→ point, J/K/L rate, ⌘↩ confirm). On iPadOS 18 the
  standard `TabView` draws the five tabs at the top; a workspace may add contextual controls but never a sixth
  destination. The landscape layouts are not a v1 web editor.
- **iPhone landscape** is required for ST24 (capture) and ST27 (player), optional elsewhere.

### 0.6 The Studio sample fixtures (test oracles)

The Studio sample is a separate, removable set (`isSample`), never pooled with the player's data. Each flow has its
own identity (implementation-states "Sample source of truth"); the UI shows these values because the engine computed
them from stored fixture records, except the rows marked *illustrative*, which exist only as Sample metadata.

| Value on screen | Equals | Computed from | Screens |
|---|---|---|---|
| Jon 6 6 / Alex 4 3 · Final · Reviewed | fold of the core Jon vs Alex 124-point sample event log (6–4 6–3) | core `ScoringEngine` | ST21, ST27, ST36 |
| 6 angles: Baseline, Far baseline, Near left, Near right, Far left, Far right | synthetic multi-angle renders of the match sample (Sample video (synthetic)) | `StudioSampleContent` | ST27 |
| Camera 1 Baseline / Camera 2 Far baseline / Camera 3 Corner · 60 min · 3.6 GB each; 3 angles · 10.8 GB | *illustrative* metadata: 8 Mbps × 3,600 s ÷ 8 ÷ 1,000 = 3.6 GB; × 3 = 10.8 GB; excludes audio/container overhead; bytes not bundled | `SourceManifest` sample records | ST25, ST37, ST38 |
| Offset +120 ms, Drift 18 ms/min, Estimated, anchor at 00:12.320 | Camera 2 only (selected source); 18 ms/min = 300 ppm stress fixture. "Estimated" is the fitter's state **before** "Confirm sync" (`syncfit.fit_device` gives `estimated` for these anchors); the stored record `spec/studio/fixtures/records/sync-map.json` is the same map **after** the player confirmed the start, middle and end checkpoints (`reviewed`), which is what the sample films cut from. ST26's default state shows the pre-confirmation map; the "Reviewed" state is the confirmed record | `SyncMap` sample | ST26 |
| JVR-482, expires in 10 min; Camera 1 Jon's iPhone Ready, Camera 2 Alex's phone Ready, Camera 3 Corner left Waiting | fixture room transcript | fixture room | ST23 |
| REC 12:34; Camera 2 still 8 s ago, Camera 3 still 12 s ago; Camera 1 battery 78%, 2 h 10 min left; 3 of 3 recording | fixture room transcript (other devices' values differ per device) | fixture room | ST24 |
| Recovery step · Estimated · Camera 3 · Point 18 · 24:12 | fixture observation with capability `studio.recoveryStep@sample` (no such capability ships) | `Observation` sample | ST28 |
| Lessons: Sep 9 First serve foundation (4 clips, 36 min), Sep 23 Recovery step (2 clips, 42 min), Oct 7 Serve rhythm (3 clips, 28 min); focus lines Find the rhythm / Repeat the routine / Trust the motion; today's focus "Same toss. Calm finish."; drills 10/10, 20/20, review 0/5 → 2 of 3 complete | lesson sample records; durations = linked sample sessions | `LessonJournal` | ST21, ST32, ST34, ST35 |
| 12 / 30 · 40% → 18 / 30 · 60%, +20 percentage points; 2 reviewed sessions | first serves in for the Sep 9 and Oct 7 sample serve-practice sessions (same definition and method); `pct(12,30)=40`, `pct(18,30)=60` | core `StatsEngine` + `ProgressStoryBuilder` | ST30 (18/30), ST32 |
| Coach's Cut sample film 05:00; chapters The pattern / The adjustment / Your next drill | sample plan compiled by `RulesPlanner` from the Oct 7 lesson | EDL | ST30, ST37 |
| Rally Pulse sample film 01:00 | sample plan | EDL | ST31 |
| Court Memories film 04:18 = 258 s; chapters Arrival 00:42 + The match 02:21 + The moment after 01:15 = 04:18; 1080p; 412 MB | chapters from the sample EDL; 412 MB *illustrative* | EDL, `FilmRecord` | ST21, ST33, ST39 |
| Storyboard: Camera 2 in 00:12.400, out 00:18.600, duration 00:06.200; placed 00:12.000–00:18.200 at 1×; beats Arrival 00:00, The match 00:12, Closing moment 03:55 | storyboard sample plan (a different draft arrangement of the same 04:18 target; its beats are not the finished film's chapters) | EDL | ST36 |
| Job: Upload complete (3 sources), Align angles complete (reviewed), Build film 42% (stage progress), Verify export queued | demo job transcript | DemoCloudClient | ST38 |
| Sample quote $4–$8, spending limit $12, temporary media 7 days | *illustrative* | DemoCloudClient | ST37 |
| Providers: On this iPhone Active; iCloud Drive Choose folder; Google Drive Not connected; Box Planned; Dropbox Planned; Cloud processing off; invitations 10 min; uploads 7-day policy | provider sample | `StorageProvider` demo states | ST40 |

Sample media is synthetic (core D8 / ADR-0012 extended with barcode and click tracks); every sample thumbnail is a frame
of a synthetic render, never a photograph.

### 0.7 Modules referenced

StudioCore: `StudioProjectStore`, `KeeperSelector`, `StoryDirector`, `RulesPlanner`, `EDLCompiler`, `EDLValidator`,
`SyncEngine` (fit), `LessonJournal`, `ProgressStoryBuilder`, `QuoteReservation`, `StudioSampleContent`. StudioMedia:
`SourceIngest`, `ProxyNormalizer`, `SyncEngine` (anchors), `LocalFilmRenderer`, `FilmVerifier`, `PrepareForYouTube`,
`DirectorCapture`. Adapters: `RoomTransport` (CameraLobby), `CloudClient` (demo/test/live), `StorageProvider`.
Core: `ScoringEngine`, `StatsEngine`, `pct`, `CapabilityRegistry`, `ImportPipeline`, `MediaLibrary`, `CaptureEngine`,
`ArchiveService`, `PermissionsCenter`, `ClipExporter`, Share Pack builder.

---

## 1. The twenty Studio screens

Each section: Purpose · Route and entry · Layout (phone, top to bottom) · Copy · Data bindings · States · Interactions ·
Accessibility · Phone and iPad · Deliberate differences from the reference image. "Copy" lists strings not already
quoted in Layout.

---

### ST21 Studio Home (`studioHome`, reference 21)

**Purpose.** Where Studio starts: build a match, open the latest film, continue lessons.

**Route and entry.** Push on the Home stack from the Home **StudioEntryCard**; also from a "film ready" notification
(→ ST39) and from Studio settings' back stack. Tab bar visible, Home selected. Back button "Home".

**Layout.**
1. Navigation bar: back "Home"; trailing toolbar button `gearshape` → ST40.
2. `JovraLockup` (40) with a `Font.jovraKicker` "Studio" beneath (the lockup itself is unchanged).
3. Title "Your game, made into a story." (`.jovraDisplayTitle()`).
4. Optional `DemoBanner` (demo) or `BannerView` (cloud unavailable, last job failed) — see States.
5. `EditorialCard` hero with `trailingImage` (a frame of the latest film's opening keeper; in demo a synthetic frame):
   "Build your match." (`Font.jovraEditorial`), `.jovraAccent` "Build your match" with trailing arrow, kicker
   "A better game tomorrow".
6. Two **StudioFactTile**s in a row. The angle tile follows what **this build** can do (`StudioCapabilities.maxAngles`
   and `pairing`), never the long-term vision: S0–S1 builds "1" / "Angle" / "One phone today" (VoiceOver "One camera
   angle in this version"); S2 "6" / "Angles" / "Add angles from files" (VoiceOver "Up to 6 camera angles, added from
   files"); S3 and later "6" / "Angles" / "Up to six phones" (VoiceOver "Up to 6 camera angles"). Symbol `video`.
   Second tile "5" / "Story styles" / "From lessons to memories" (symbol `film`).
7. `SectionHeader` "Latest film" + trailing "View all" chevron.
8. **FilmCard**: 16:9 thumbnail with duration chip "04:18" and play glyph; "Jon vs Alex"; "Court Memories";
   `ProvenanceBadge(.sample)` labelled "Sample project"; optional status line ("Made before a correction",
   "Checking every frame…").
9. `SectionHeader` "Lessons this month" + "View all".
10. **LessonRow** (compact): thumbnail, "Oct 7" kicker, "Serve rhythm", "3 clips", `StatusPill(.positive)` "Reviewed".

**Copy.** Empty and banner strings in States.

**Data bindings.**
| Element | Fixture | Source | Provenance |
|---|---|---|---|
| Hero image | first frame of the Court Memories sample film's opening keeper | newest `FilmRecord` → EDL first `live` segment frame | — (Sample badge in demo) |
| angle tile / 5 | per stage (see Layout 6) | `StudioCapabilities.maxAngles` and `pairing` of the build; profile count of `jovra.story-profiles/2` | not a stat; no badge |
| Latest film | Jon vs Alex · Court Memories · 04:18 | newest `FilmRecord` with state `ready` or `verifying` | Sample in demo |
| Lessons this month | Oct 7 Serve rhythm · 3 clips · Reviewed | `LessonJournal.lessons(inMonthOf: today)` newest first, max 3 | Reviewed when every note is Reviewed |

**States.**
| State | Treatment |
|---|---|
| No films | Rows 7–8 become `StateCard`: "Your first film starts with one match." / "Choose a session you've recorded, or explore the sample project." Actions "Choose a session" (→ session picker sheet → ST29), "Explore the sample" |
| First session | Above the hero, **NextStepRow** "Make a film from Oct 6 · Jon vs Alex" → ST29 |
| Local demo | `DemoBanner` "You're exploring the Studio sample." + "Remove sample" (confirmation sheet; removes only `isSample` records) |
| Cloud unavailable | `BannerView` (neutral) "Cloud production isn't available right now. Films made on this iPhone still work." No action |
| Last job failed | `BannerView` (attention) "Your Court Memories film didn't finish. Your videos are safe." Actions "See what happened" (→ ST38), "Try again" |
| Film verifying / stale | FilmCard status line "Checking every frame…" / `StatusPill(.attention)` "Made before a correction" |
| No lessons | Lessons section shows **NextStepRow** "Start a lesson journal" → ST34 |
| Loading | redacted placeholders after 300 ms (core rule) |

**Interactions.** Build your match → ST22. FilmCard → ST39 (ready) or ST38 (job in progress). View all (films) →
`studioFilms` list of FilmCards grouped by project with version counts. LessonRow → ST35. Lessons View all → ST34. Gear
→ ST40. Long-press FilmCard → context menu (Play, Save film, Show project, Delete film — the last opens the delete-scope
sheet A6).

**Accessibility.** Order: back, settings ("Studio settings"), lockup ("JOVRA Studio"), title (header), banner, hero
(header text + button), tiles (the stage's angle label, e.g. "One camera angle in this version"; "5 story styles"), Latest film header, FilmCard ("Jon versus
Alex, Court Memories film, 4 minutes 18 seconds, sample project"), Lessons header, LessonRow ("October 7, Serve rhythm,
3 clips, reviewed"). Tiles stack at accessibility sizes.

**Phone and iPad.** Phone: single column. iPad: 720 pt column; hero and tiles side by side above AX2.

**Deliberate differences from the reference image.**
- The image's "JOVRA STUDIO" lockup becomes the standard lockup + "Studio" kicker (one brand mark); the trailing JV
  avatar becomes the settings button (Profile is one tab away).
- Subtitle "Capture. Analyze. Share." removed (not in the brief; "Analyze" overstates Studio's analysis).
- Tile captions "Multiple perspectives" / "From highlights to training" → the stage's angle caption ("Up to six
  phones" only once pairing ships in S3) / "From lessons to memories" ("up to" is the truth only when the build can do
  it; "highlights" collides with the core term).
- The lesson card "Footwork Fundamentals / Move better, play longer" contradicts the lesson fixture → Oct 7 Serve rhythm.
- The Sample chip's cloud-upload symbol implies an upload → the Sample badge's dashed square.
- Photographs become synthetic sample frames (demo) or the player's own frames.

---

### ST22 Build your match (`buildMatch(projectId?)`, reference 22)

**Purpose.** Create a Studio project and place one primary plus up to five optional cameras outside the court.

**Route and entry.** Push from ST21 or Home. Tab bar visible. Creates the project on first change (draft until a source
exists; drafts with no source are discarded after 7 days).

**Layout.**
1. Navigation bar: back; trailing `ProvenanceBadge(.sample)` "Sample setup" in demo.
2. Title "Build your match." subtitle "Start with one camera. Add up to six."
3. **CourtPlacementDiagram** (from `CourtGeometry`; top-down doubles court with singles lines, service boxes, centre
   service line and net; surrounding run-off): six **SlotMarker**s outside the lines — 1 near baseline centre, 2 far
   baseline centre, 3 near-left corner, 4 near-right corner, 5 far-left corner, 6 far-right corner — each with its
   number, a view cone, and a shape for state (filled = assigned, outline = empty, ring = needs attention).
4. Legend pill: "1 Primary · 2–6 Optional".
5. `SettingsRow` "Primary angle" · value "Baseline" · leading mini diagram highlighting slot 1 · chevron → slot sheet.
6. `SettingsRow` "Additional angles" · value "5 available" (count of empty optional slots) · chevron → slots sheet.
7. `InfoCard` (neutral, `info.circle`): "Keep cameras outside the playing area."
8. Bottom action (safe-area inset) `.jovraAccent` "Continue" with arrow.

**Copy.** Slot names: "Baseline" (1, Primary), "Far baseline" (2), "Near left" (3), "Near right" (4), "Far left" (5),
"Far right" (6). Continue sheet ("How will you capture?"): "Record now with this iPhone" · "Invite other phones" ·
"Use videos I already have". Placement tip (shown once): "Mount phones high and behind the fence, landscape, the whole
court in view. 60 fps keeps slow replays clean."

**Data bindings.**
| Element | Source | Provenance |
|---|---|---|
| Slot states | `StudioProject.slots` (source assigned, device joined, capability check) | — |
| 5 available | 5 − assigned optional slots | — |
| Capability warnings | joining device `preflight` (S3) or source manifest (import) | — |

**States.**
| State | Treatment |
|---|---|
| One angle | Only slot 1 assigned; "Additional angles · Optional"; Continue enabled |
| Occupied role | Choosing an assigned slot opens A-slot sheet: "Camera 3 is already Alex's phone." Actions "Replace" / "Choose another slot" |
| Unsafe placement hint | When a joined camera's framing still (S3) or an imported source's first frame shows the court cut off: slot ring + "Camera 5 can't see both baselines. Move it back or higher." (advice; framing measures nothing) |
| Camera capability unavailable | Slot row "Can't record 60 fps · 30 fps will work, without clean slow replays" or "Can't record 1080p" |
| Pairing not in this build (before S3) | "Invite other phones" in the Continue sheet shows "Coming in a later update — record on each phone and add the videos here." |
| Sample | Badge; diagram shows the sample setup (slots 1–3) |

**Interactions.** Tap a SlotMarker or row → slot sheet (assign: "This iPhone", "A recording in my library", "Invite a
phone" [S3]; remove). Continue → capture sheet → core S04 (session setup with the Studio project attached; one camera),
ST23 (lobby, S3), or ST25 (import). Haptic selection on slot change.

**Accessibility.** Diagram is one container with six buttons ("Camera 1, primary, near baseline, assigned to this
iPhone"); the court drawing is decorative. Legend read once. Rows are buttons with values.

**Phone and iPad.** Phone: diagram 1:1.2 aspect, full width. iPad: diagram left, rows right in the 720 pt column.

**Deliberate differences from the reference image.**
- Header lockup "JOVRA TENNIS" + "Studio" pill → standard back navigation + Sample badge; Studio context is the screen.
- Legend typo "2--6" → "2–6".
- The "Additional angles" photo of a security camera (not a phone) → mini court diagram; the aerial photo → a
  `CourtGeometry` drawing with exact ITF lines (implementation-states: court geometry from code).
- Players drawn on the court are omitted (decorative and misleading about scale).

---

### ST23 Camera lobby (`cameraLobby(projectId)`, reference 23) [S3; demo from S0]

**Purpose.** Invite phones into camera slots with expiring one-slot codes, approve them, and check readiness before
capture — without making capture depend on the lobby.

**Route and entry.** Push from ST22's capture sheet ("Invite other phones"). Guest phones reach the guest variant by
scanning in JOVRA (Record tab → "Join a match" scanner) or typing a code. Before S3 ships, live builds show the
Unsupported state; demo shows the fixture room.

**Layout (host).**
1. Navigation bar: back; Sample badge "Sample setup" in demo.
2. Title "Camera lobby." subtitle "Bring every angle together."
3. **JoinCodeCard** (`EditorialCard`, `CourtLinesBackdrop`): kicker "Invite a camera"; "Join this match"; body "Scan
   with JOVRA on the other phone, or type the code."; a real generated QR (payload `jovra-room:1:…`, SD10); kicker
   "Match code"; "JVR-482" (`Font.jovraScore`, monospaced, letter groups); "Expires in 10 min" (live countdown);
   slot line "For Camera 3 · Corner left" (menu to change slot); buttons `.jovraSecondary` (on-forest) "New code" and
   text button "Stop inviting".
4. `SectionHeader` "Cameras".
5. **CameraSlotRow** × n: leading thumbnail (latest still with age, or the slot's mini diagram before a still exists),
   "Camera 1", device name as entered ("Jon's iPhone"), slot ("Primary" chip / "Far baseline" / "Corner left"),
   trailing status (`StatusPill`: "Ready" positive · "Waiting" neutral · "Needs attention" attention with the reason
   on the next line), chevron → device sheet.
6. Dashed **AddSlotRow**: "+" "Add another angle" "Camera 4 – 6" → issues a code for the next empty slot.
7. `InfoCard` (`iphone` symbol): "Each phone saves its own video."
8. Bottom action `.jovraAccent` "Check camera setup" (video symbol) → preflight check sheet (A2a: each camera's latest
   still, battery, space, minutes left, heat, microphone) → "Go to capture" → ST24.

**Layout (guest).** Card "You're Camera 2 · Far baseline" with host name, own preflight checklist, "Waiting for Jon to
start", and `.jovraSecondary` "Start recording on this phone" (always available — recording never waits for the host).

**Copy.** Device sheet: "Battery 78%", "2 h 10 min of space", "Microphone allowed / not allowed", "Heat: normal",
actions "Change slot", "Remove from match" (destructive; confirmation "Camera 2 will stop sending status. Anything it
records stays on that phone.").

**Data bindings.**
| Element | Source |
|---|---|
| Code, QR, expiry | `RoomTransport.invite(slot)` (≤ 10 min, one slot, one use) |
| Rows | room roster (approved devices) + `preflight` messages, each with age |
| Ready | preflight passes: camera permission, preset supported, ≥ planned minutes of space, battery ≥ 20% or charging, thermal ≤ fair |

**States.**
| State | Treatment |
|---|---|
| Host / guest | Layouts above |
| Join request | Host sheet "Alex's phone wants to join as Camera 2 · Far baseline." `.jovraAccent` "Allow" / "Decline" (device model shown) |
| QR expired | Code area dims; "This code expired." + `.jovraAccent` "New code"; guest scanning it: "This code expired. Ask Jon for a new one." |
| Invite revoked | Guest: `StateCard` "Jon removed this phone from the match." / "Anything you recorded stays on this phone." Action "Done" |
| Role full | Guest: "Camera 3 already has a phone. Ask Jon for another slot." |
| Reconnect | Row "Reconnecting…" with age; guest banner "Reconnecting to Jon's phone. Recording here isn't affected." |
| Permission denied | Local Network denied (A1): `StateCard` "JOVRA can't find nearby phones." / "Allow Local Network in Settings, or record on each phone and add the videos later." Actions "Open iOS Settings", "Record independently" |
| Storage / thermal warning | Row reason "Low space · 38 min left" / "Phone warming"; Ready withheld until resolved or acknowledged |
| No network | `BannerView` "No shared network. Each phone can still record; add the videos later in Choose the footage." |
| Unsupported (before S3) | `StateCard` "Pairing phones arrives in a later update." / "Record on each phone, then add the videos in Choose the footage." Action "Choose the footage" (→ ST25) |
| Sample | Fixture room; badge |

**Interactions.** Slot menu changes the code's slot (old code invalidated). Row → device sheet. Swipe row → Remove.
"Check camera setup" never starts recording itself.

**Accessibility.** The QR has the label "Join code JVR 482, expires in 10 minutes" and the code is readable text
spelled by character on demand (`.speechSpellsOutCharacters`). Status changes are announced. Countdown updates are not
announced every second (only at 5, 1 and 0 minutes).

**Phone and iPad.** Phone as above. iPad: code card left, camera list right.

**Deliberate differences from the reference image.**
- The decorative QR becomes a real, expiring, one-slot code (implementation-states).
- "Invite players" / "share the code with your friends" → "Invite a camera" / "Scan with JOVRA on the other phone, or
  type the code." (phones join slots, not players; the code is a secret, not a share-sheet link).
- Footer cloud symbol → `iphone` symbol (nothing goes to a cloud).
- Subtitle "Set up your angles. Capture the full game." → brief title "Bring every angle together."
- Row thumbnails are each phone's own still with its age, not stock photos; the trailing JV avatar is removed.

---

### ST24 Director capture (`directorCapture(projectId)`, reference 24) [S3; demo from S0]

**Purpose.** The host records the primary angle with live scoring while seeing honest, aged status from the other
phones; every phone records locally regardless.

**Route and entry.** Full screen from ST23 "Go to capture". Forest in both appearances. Portrait and landscape. The
primary phone's capture is core S06 behaviour (segments, journal, heat ladder, court mode, ScorePad) plus the Studio
panel.

**Layout (portrait).**
1. Compact header (`FocusedHeader`, ivory on forest): `RecordingStatusPill` "● REC 12:34", kicker "Studio capture",
   trailing "More" (`ellipsis`).
2. Primary `VideoSurface` (16:9) with framing corner guides, label chip "Primary · Live" and "Camera 1 · Baseline";
   bottom-right chip "No score" until the first point is scored, then `ScoreboardOverlay` (live, derived).
3. Two **SecondaryStillCard**s (horizontal carousel when more than two): still image, "Camera 2 · Preview", age
   "8 s ago" (`Font.jovraTimecode`); "Camera 3 · Preview", "12 s ago".
4. Header row "Recording on 3 of 3 phones" (count of `recordingStarted` acknowledgements for this intent) with
   `ProvenanceBadge(.sample)` in demo.
5. **DeviceHealthRow** × n: camera symbol, "Camera 1", "Recording · Baseline", `BatteryPill` "78%", storage
   "2 h 10 min left", chevron → device sheet (stop this phone, request a fresh still, details).
6. Bottom controls: `CaptureControlButton` "Mark point" (64 pt), Stop disc (76 pt), `CaptureControlButton` "More"
   (ScorePad toggle, court mode, checkpoint entry). `SaveHeartbeatLabel` "Saved through 12:34" under the controls.

**Copy.** Stop sheet (A3): "Stop this phone" / "Stop all cameras (3)" / "Keep recording". After stop-all: "Waiting for
2 phones to confirm they stopped…" then "All 3 phones stopped. Their videos are on each phone — add them in Choose the
footage, or they'll arrive when the phones reconnect."

**Data bindings.**
| Element | Source |
|---|---|
| REC time | primary CaptureEngine status |
| Recording on n of m | `DirectorCapture` acknowledgement set for the current start intent |
| Still ages | `still` message `monoNs` vs host clock |
| Battery, storage, heat | `heartbeat` (2 s), each with age; storage via the core estimate (bitrate × time × 1.2, then measured slope) |
| Score | core fold of the primary's live events |

**States.**
| State | Treatment |
|---|---|
| Missing acknowledgement | Row "Camera 3 · Not confirmed" (clay ring); `BannerView` attention "Camera 3 hasn't confirmed it's recording. Start it on that phone." Count excludes it |
| Device disconnected | Row "No contact for 0:42 · it may still be recording on its own" (age grows); never "Stopped" |
| No microphone | Row "Video only · no microphone"; primary: core S06 mic-less behaviour |
| Unavailable preview | Still card placeholder "Preview unavailable" + reason ("Phone warming — previews paused") |
| Low battery / space | `HeatBanner` "Camera 2 · 12% battery" / "Camera 1 · 18 min of space left" with detail |
| Interruption | Primary: core interruption handling, banner "Recording resumed · 0:12 gap"; secondary: row "Gap · 0:12 (call)" |
| Host exits | Guests: banner "Jon's phone left the match. Keep recording; stop when the match ends." |
| Court mode | `CourtModeView` with the Studio count line "Recording on 3 of 3 phones" |
| Sample | Fixture room; badge; "Sample capture" chip on the video |

**Interactions.** Mark point → core Mark (match-clock hint broadcast as `mark`). Tapping a still requests a fresh still
from that phone (rate-limited). Stop → A3. Rotation: landscape puts video left, stills and health right.

**Accessibility.** Acknowledgement changes and warnings announced; stills labelled with camera and age; health rows read
"Camera 1, recording, baseline, battery 78 percent, 2 hours 10 minutes of space left". Stop requires a confirm in the
sheet (VoiceOver users never stop all by a single activation).

**Phone and iPad.** iPad capture is allowed but not a design target (core §0.5).

**Deliberate differences from the reference image.**
- Large title "Recording your game / Multiple angles. A better you." and header "Studio · Capture. Improve." removed:
  capture uses a compact header (core S06).
- "LIVE" → "Primary · Live"; "Camera 1 · Overhead" → "Camera 1 · Baseline"; rows' "Overhead / Side view / Baseline"
  → their slot names (Camera 3 is Corner left).
- Identical "02:10 storage remaining" on every row → each phone's own measured value as "2 h 10 min left".
- "Recording locally (3 devices)" → "Recording on 3 of 3 phones" counted from acknowledgements.
- "Bookmark rally" → "Mark point" (glossary). The clay primary court vs hard-court stills inconsistency disappears with
  real frames.

---

### ST25 Source import (`sourceImport(projectId)`, reference 25)

**Purpose.** Choose one to six recordings of the same match (or one old match), see what they are, and keep originals
on the phone.

**Route and entry.** Push from ST22 ("Use videos I already have"), ST21 empty state, or after capture. Tab bar visible.

**Layout.**
1. Navigation bar: back; kicker "Studio".
2. Title "Choose the footage." subtitle "Pick up to six angles of the same match."
3. Two-segment control (`FilterPills`, segmented): "Photos" (`photo`) · "Files" (`doc`). Selecting opens PhotosPicker
   or the document picker; picked files are copied into sessions by the core ImportPipeline (no Photos library
   permission needed).
4. **SourceRow** × n: thumbnail (first decoded frame), "Camera 1", slot "Baseline" (menu), "60 min · 3.6 GB",
   second line "1080p · 60 fps" (and "No audio" when applicable), trailing checkbox (selected).
5. Dashed **AddSlotRow** "Add more angles" · "Include another camera angle".
6. **SourceSummaryCard** (forest): stack symbol, "3 angles · 10.8 GB", "Originals stay on your phone.", Sample badge
   "Sample files".
7. `ToggleRow` "Wi-Fi only" · "Cloud uploads wait for Wi-Fi" (on by default).
8. `SettingsRow` "Use one old match instead" · "Choose a session from your library" (`clock.arrow.circlepath`).
9. Bottom action `.jovraAccent` "Prepare sync" (2+ sources) or "Choose a story" (1 source).

**Copy.** Import progress per row: "Copying… 42%" then "Checking the video…".

**Data bindings.**
| Element | Source |
|---|---|
| Rows | `SourceIngest.ingest` → `SourceManifest` (duration, bytes, dimensions, fps, audio) |
| Total | Σ original bytes of selected sources (decimal GB, one decimal) |
| Wi-Fi only | project upload policy (used only by CloudClient) |

**States.**
| State | Treatment |
|---|---|
| One old match | Session picker sheet (core `SessionCard` list); one row with slot "Baseline (primary)"; button "Choose a story" |
| No audio | Row pill "No audio · video only" |
| Unsupported / invalid media | Row in attention: "Can't use this file — unsupported format" / "This file is damaged" + "Remove" |
| Duplicate | Row "Already added as Camera 2" (content hash) — not added twice |
| Partial source | Row attention "Ends early · no video after 41:12" (coverage recorded as a gap) |
| Mixed dimensions / FPS | Info pill "We'll make editing copies that match. Originals stay as they are." (S2); in S1 builds a non-CFR or rotated source shows "Needs an editing copy — available with multi-angle (coming soon)" |
| Insufficient working space | `BannerView` attention "Preparing these angles needs 6.2 GB free. 3.1 GB is free." Actions "Manage storage" (→ core S19), "Choose fewer angles" |
| Working | Per-row progress; leaving the screen keeps importing (core import behaviour) |
| Sample | Metadata-only rows with Sample badges; selecting them never touches the file system |

**Interactions.** Slot menu per row (conflicts → occupied-slot sheet). Uncheck to exclude. "Prepare sync" → ST26
(iPad) / `syncReview` (phone). "Choose a story" → ST29.

**Accessibility.** Each row: "Camera 1, baseline, 60 minutes, 3.6 gigabytes, 1080p, 60 frames per second, selected".
Summary card is one element. Toggle has its description as hint.

**Phone and iPad.** iPad: rows and summary side by side.

**Deliberate differences from the reference image.**
- Subtitle "Select the camera angles to include in your session." → "Pick up to six angles of the same match." (a
  Studio project is not one session).
- Wi-Fi row description "Use Wi-Fi to sync files" → "Cloud uploads wait for Wi-Fi": importing is local; the toggle only
  governs later cloud uploads.
- Thumbnails show each source's own first frame (the image mixes different players across "the same match").
- Single-source button label changes to "Choose a story" (nothing to sync).

---

### ST26 Sync workspace (`syncDesk(projectId)` on iPad, `syncReview(projectId)` on phone, reference 26) [S2; demo from S0]

**Purpose.** Put every angle on one match clock, show offset, drift, gaps and uncertainty, and let the player review
and confirm.

**Route and entry.** From ST25 "Prepare sync", the project player's "Review sync", or a needs-review banner. iPad:
full-screen workspace. Phone: sequential sheets (below).

**Layout (iPad landscape).**
1. Forest top bar: Close ("Done"), compact `JovraLockup`, "Studio", centre title "Sync desk", trailing project menu
   ("Sample project") and Sample badge.
2. Left pane "Sources" + "+ Add" (→ ST25): **SourceCard** per angle: number badge, thumbnail, slot ("Baseline"),
   "1920 × 1080 · 59.94 fps", state pill ("Reference" for the primary; "Estimated", "Needs review", "Reviewed",
   "No overlap"), Sample badge.
3. Centre: title "One match. One clock." subtitle "Review at start, middle and end." Row of linked `VideoSurface`s
   (one per source, labelled "1 Baseline", "2 Far baseline", "3 Corner"), all driven by the match-clock playhead,
   each showing its own time and "No video here" where it has no coverage.
4. Under them, **SyncTimeline**: one **WaveformLane** per source on the common match clock, drawn from that
   source's **real decoded audio** (a peak envelope computed from the analysis proxy's audio track, so a clap or
   impact is visibly aligned or not; a source with no audio shows "No audio" instead of a waveform; the Sample project
   draws from its synthetic fixture audio) (labels with number and slot), anchor markers (**AnchorMarker**, clay vertical line with time chip "00:12.320"), gap hatching with reason,
   checkpoint chips "Start" "Middle" "End", zoom, "View full timeline".
5. Right inspector **SyncInspector** for the selected source: "Sync details"; "Offset (vs. Camera 1 · Baseline)"
   "+120 ms"; "Drift" "18 ms/min"; "Alignment" state with symbol; checkpoint list (Start ✓, Middle ✓, End —);
   explanatory text "Review at start, middle and end of the match to confirm sync quality."; `.jovraAccent` "Confirm
   sync"; `.jovraSecondary` "Manual align".

**Layout (phone, sequential).** (1) Sources sheet: list of SourceCards with states and "Review" buttons. (2) Review
sheet per source: reference and selected video stacked, each with its time, a `JogStrip`, the checkpoint picker
(Start / Middle / End), nudge buttons "−1 frame" "+1 frame" "−10 ms" "+10 ms", "Add marker here". (3) Summary sheet
with the SyncInspector values and "Confirm sync".

**Copy.** Manual align mode: "Find the same moment in both videos — a serve contact, a bounce, or a clap — and line
them up." Confirm toast: "Sync confirmed for Camera 2." Reasons for Needs review: "Sound reaches the far baseline later;
check a serve by eye." / "Not enough shared moments in the last third." / "The clocks drift more than expected."

**Data bindings.**
| Element | Source | Provenance |
|---|---|---|
| Offset | `SyncMap` piece transform at its first covered instant minus the reference, rounded to whole ms | Estimated → Reviewed after Confirm (Sample in demo) |
| Drift | (rate − 1) × 60,000 ms/min (18 ms/min ⇔ 300 ppm) | as above |
| Alignment state | `SyncMap.pieces[].state` | — |
| Anchors | `SyncMap.pieces[].anchors` (time, modality, residual, reviewed) | — |
| Fps / dimensions | `SourceManifest` | — |

**States.**
| State | Treatment |
|---|---|
| Manual markers | Marker list in the inspector ("Manual marker · 00:12.320 · Camera 2"); markers drawn as diamonds on lanes |
| Failed alignment | Source state "Couldn't line up"; `StateCard` in the inspector "We couldn't line up Camera 3." / "Add a clap or ball drop as a marker, or leave this angle out." Actions "Add marker", "Leave out" |
| No shared coverage | State "No overlap" (a UI label for a `failed` piece whose reason is that nothing could be fitted; the contract has no separate `no-overlap` state); lane shows no shared span; inspector "Camera 3 doesn't overlap Camera 1. It can't be used for cuts." |
| Drift | Inspector shows drift and the end-checkpoint residual; End checkpoint marked "Check" until reviewed |
| Gap / restart | Hatched lane span "Restart · 0:41 gap"; separate piece per side of the gap with its own state |
| Muted source | Lane pattern "No audio"; alignment uses visible events or manual markers only |
| Normalized proxy | SourceCard "Preparing an editing copy · 42%"; review waits for it; note "Originals stay as they are." |
| Needs review | Pill "Needs review" + reason; Confirm enabled only after the player visits all three checkpoints |
| Single source | Not reachable (one source has an identity map) |
| Sample | Badges; Sample values on Camera 2 only |

**Interactions.** Selecting a SourceCard selects its lane and inspector. Dragging an AnchorMarker or using nudge buttons
proposes a manual correction (recomputed fit, residual shown) — nothing is saved until Confirm. Confirm writes a new
`syncRevision`, marks the pieces `reviewed`, and marks dependent plans and films stale (story 88). Keyboard: ←/→ frame,
⌥←/⌥→ 10 ms, ⌘↩ Confirm.

**Accessibility.** Lanes are adjustable elements (point/frame rotors); anchors are listed in the inspector as buttons
("Anchor at 12.320 seconds, serve contact, residual 2 milliseconds"). The waveform pixels come from real source
audio (item 4; the implementation-states production gate requires real stills and waveform data) but are hidden from
VoiceOver, because the anchor list and the numbers carry the same information as text. State never by colour alone (symbols + words).

**Phone and iPad.** As above; no split-screen editing on phone.

**Deliberate differences from the reference image.**
- The image selects source 1 while showing "Offset (vs. 1 Baseline) +120 ms": the offset belongs to the selected
  source, Camera 2 (implementation-states), so Camera 2 is selected and Camera 1 is labelled "Reference".
- Player time readouts "00:12 / 00:28" (a 28-second clip) → match-clock times; the timeline scale is the match clock.
- "Audio timeline (Sample)" typo → "Court audio" + Sample badge; "Sync desk" cloud symbol removed (alignment runs on
  the phone).
- Subtitle "Synchronize multiple angles. See the full picture." → "Review at start, middle and end." (the brief's
  instruction).
- Three identical photos of one serve → real frames of each source at the playhead.

---

### ST27 Match Broadcast and interactive replay (`projectPlayer(projectId, filmId?)`, reference 27)

**Purpose.** Watch the match from any recorded angle on one clock with an event-derived score, and play a Match
Broadcast film — explaining that the film is one flattened edit.

**Route and entry.** Full screen from ST29 (Match Broadcast "Preview my story"), ST39 (Match Broadcast film), a
session overview (S09 "Watch angles" when a Studio project exists), or Studio Home. Forest. Landscape on iPad and
phone; portrait phone supported.

**Layout (iPad landscape).**
1. `FocusedHeader`: Close, compact lockup, title "Match Broadcast", `ProvenanceBadge(.sample)` "Sample project", trailing
   segmented control "Film · Angles" (Film only when a film exists).
2. Main `VideoSurface` (16:9) with **ScoreBug** (top-left, `ScoreboardOverlay` dark variant): columns "Player",
   "Set 1", "Set 2"; rows "Jon 6 6", "Alex 4 3"; footer "Final · Reviewed" only when the playhead is after the last
   point; during play the bug shows sets so far, the current game and the point score at the playhead, with the
   server dot when recorded. Fullscreen button top-right.
3. Right pane **AngleGrid** "Camera angles" + "6 angles": six **AngleThumb**s labelled "Baseline", "Far baseline",
   "Near left", "Near right", "Far left", "Far right"; selected = chartreuse border + check.
4. `TransportBar`: play/pause, "00:42 / 04:18", scrubber (film clock in Film mode, match clock in Angles mode), rate
   chips "0.5×" "1×", frame step (hold to repeat).
5. Row "Points" with **PointChip**s ("Point 1 · 00:42", "Point 2 · 01:15", "Point 3 · 02:08", "Point 4 · 03:21", …,
   horizontally scrolling) and "+ Mark point".
6. Bottom bar: on-forest `.jovraSecondary` "Edit this film" (scissors) → ST36; `.jovraAccent` "Save clip" (download
   symbol) → core clip export sheet for the current angle and point.

**Layout (phone).** Player first (landscape fills the screen with overlays; portrait: video on top, angle strip as a
horizontal carousel, then points list, then the bottom bar). "Angles" opens as a sheet when the carousel is hidden.

**Copy.** Film-mode note under the grid: "This film is one chosen edit. Switch to Angles to watch any view." Export
note (Save clip sheet and ST39): "A downloaded film keeps the angles you chose. Switching angles works here, in the
project."

**Data bindings.**
| Element | Source | Provenance |
|---|---|---|
| Score bug | core fold at the session time mapped from the playhead (film: EDL output frame → session time) | per point (Manual/Reviewed/Estimated); "Final · Reviewed" when all points reviewed and the match is complete |
| Angles | `SyncMap.query(source, matchUs)` per thumb | sync state per angle |
| Points | effective point events, start times on the match clock (film: their output times) | — |
| Duration | film `FilmRecord` frames ÷ fps / match coverage | — |

**States.**
| State | Treatment |
|---|---|
| One angle | No AngleGrid; caption "One angle"; Film/Angles control hidden |
| Missing angle at this time | Thumb hatched "No video here"; selecting it shows "Camera 3 has no video at 12:46 (recording gap)" and stays on the current angle |
| Buffering | After 300 ms a spinner over the video with "Loading Camera 2…" |
| Uncertain sync | Thumb pill "Needs review"; switching shows `BannerView` "This angle isn't confirmed in sync here." + "Review sync" (→ ST26) |
| Score unknown | Bug "Score unknown" with dashed outline when a point's effective outcome is unknown or coverage is incomplete; provisional values per core rules |
| Offline | Unaffected for local sources; a cloud-only artifact shows "Not on this iPhone" + "Download" |
| Stale film after correction | `BannerView` "Made before a correction — the score in this film may be out of date." + "Rebuild" (→ ST36 rebuild) |
| Sample | Badge; synthetic angles labelled "Sample video (synthetic)" via `SampleBadge` on the video |

**Interactions.** Tap a thumb → angle switches at the same match time (cross-fade suppressed under Reduce Motion). Point
chip → seek to point start (pre-roll). Rate chips change playback rate (not the film). Keyboard per §0.5.

**Accessibility.** Video adjustable by point; ScoreBug readable ("Jon 6, 6; Alex 4, 3; final, reviewed" or "Set 1, Jon
leads 4–3, 30–15, Alex serving"); AngleGrid is a group of selectable buttons with coverage and sync state in the
label. 44 pt minimum for chips.

**Phone and iPad.** As above.

**Deliberate differences from the reference image.**
- The image's top navigation "Home · Sessions · JOVRA Studio · Insights · Profile" makes Studio a tab and drops
  Record; this is a full-screen route with no tab bar (SD1).
- Subtitle "Relive. Analyze. Improve." and the "A better game tomorrow" kicker removed (chrome over the player).
- The score bug shows "Final · Reviewed" only after the final point; at 00:42 it shows the score at that moment.
- "Point bookmarks" / "Add bookmark" → "Points" / "Mark point" (glossary).
- Thumbnails are each angle's real frame at the playhead (the image's near-left/near-right thumbs are inconsistent
  views of one player).

---
### ST28 Angle insights (`angleInsights(projectId, observationId?)`, reference 28)

**Purpose.** Show an observation in context from two synchronized angles, with its source and provenance, and let the
player review it or keep it for a lesson. No unvalidated 3D, speed or accuracy claims.

**Route and entry.** Push from the Insights root ("Angle insights"), from a point in the project player ("Notes for this
point"), or from a lesson cue. Tab bar visible, Insights selected.

**Layout.**
1. Navigation bar: back; kicker "Studio".
2. Title "Angle insights." subtitle "More context. Clearer feedback."
3. Project chip (folder symbol) "Sample project" with chevron → project switcher sheet.
4. **ComparisonPair**: two paused `VideoSurface`s side by side at the same match time, labels "Baseline · Camera 1"
   and "Near left · Camera 3"; optional `AnnotationLayer` showing at most one user-drawn or reviewed 2D line; tap
   opens that moment in the project player.
5. **ObservationCard** (`EditorialCard`): kicker "Selected cue"; "Recovery step."; "Your first recovery step starts
   after the follow-through."; `ProvenanceBadge(.provenance(.estimated))` with the label "Estimated observation"
   (Manual: "Your note"; Reviewed: "Reviewed cue"); divider; source line (video symbol) "Source · Camera 3 · Point 18 ·
   24:12".
6. Two buttons side by side: `.jovraAccent` "Review cue" (arrow), `.jovraSecondary` "Keep for lesson" (arrow).
7. `InfoCard` (clay camera symbol): "Additional angles add context." / "Measurements depend on calibration."
8. `SectionHeader` "Other notes in this project" with `FilterPills` "All · Needs review · Reviewed"; list of compact
   observation rows.

**Copy.** Review sheet: "Does this match what you see?" · "Looks right" (→ Reviewed) · "Not right" (→ Rejected) ·
"Edit wording" (user text; provenance Manual). Lesson picker: "Keep for which lesson?" list + "New lesson".

**Data bindings.**
| Element | Source | Provenance |
|---|---|---|
| Frames | `SyncMap.query` for both sources at the observation's match time | sync state shown if not Reviewed |
| Cue text | user text, or a catalog template ID filled from stored values | Manual / Estimated / Reviewed |
| Source line | observation's source ID → slot, session point number, match time | — |
| Capability | `CapabilityRegistry` entry and version (tap → `CapabilityDetail`) | registry status |

**States.**
| State | Treatment |
|---|---|
| Manual note | Badge Manual, label "Your note"; button "Edit note" instead of "Review cue" |
| Reviewed cue | Badge Reviewed; "Review cue" → "Change review" |
| Unsupported capability | `StateCard` "Automatic notes aren't available for this view yet." / "Add your own note — it works the same in lessons and films." Action "Add a note". No capability in S1–S4 produces Studio cues automatically; the sample observation is a labelled fixture |
| Occluded body or ball | The pair still shows; card "Camera 3 can't see the player's feet here." — no observation offered |
| No calibration | Row "Needs court calibration for Camera 3" → core calibration flow (S05) on that source; calibration-dependent values hidden |
| Rejected observation | Hidden from the default list; under "All" shown struck with "Rejected · kept in history" |
| One angle | ComparisonPair shows one video full width; InfoCard says "Add another angle for more context." |
| Sample | Badges; capability detail says "Sample — no such capability ships" |

**Interactions.** Review cue → sheet → new provenance written as an event (never mutating the original observation).
Keep for lesson → lesson picker → `LessonJournal.linkCue`; Toast "Kept in Oct 7 · Serve rhythm". Pair tap → ST27 at
that time.

**Accessibility.** Pair is one group ("Baseline and near-left views at 24 minutes 12 seconds, point 18"); annotation
described in words ("Line from hip to knee drawn by you"). Card reads kicker, title, body, provenance, source.

**Phone and iPad.** iPad: pair larger, list in a right column.

**Deliberate differences from the reference image.**
- Subtitle "See more. Play better." → brief "More context. Clearer feedback."
- "Rally 18 · 00:24:12" → "Point 18 · 24:12" (glossary; match-clock format).
- "Baseline view / Near-side view" → slot names with camera numbers (Camera 3 is the near-left corner).
- The hip–knee line overlay is shown only as a user-drawn or reviewed annotation, never an automatic pose skeleton or
  angle.
- Trailing JV avatar removed.

---

### ST29 Story modes (`storyModes(projectId)`, reference 29)

**Purpose.** The simple path's only required choice: one of five story profiles, plus an optional length.

**Route and entry.** Push from S09 "Make a film", ST21, ST25 ("Choose a story"), ST26 (after confirm), a lesson
("Make a film from this lesson"). Tab bar visible.

**Layout.**
1. Navigation bar: back; kicker "Studio"; trailing `ProvenanceBadge(.sample)` "Sample project".
2. Title "Choose your story." subtitle "Same match. Five ways to remember it."
3. Five **ProfileCard**s (radio group): thumbnail (a real frame chosen by `KeeperSelector` for that profile), name,
   line, and an optional readiness line:
   - "Coach's Cut" / "Learn from every point."
   - "Match Broadcast" / "Your match, beautifully covered."
   - "Rally Pulse" / "Feel the energy."
   - "Progress Story" / "See how far you've come."
   - "Court Memories" / "Keep the moments that matter."
   Selected: forest border, chartreuse check, `.isSelected`.
4. `SectionHeader` "Story length"; `FilterPills` "3 min" · "5 min" · "Full" (default 5 min when the profile allows;
   options outside the profile's range are disabled with a reason; "Full" = the profile maximum bounded by coverage).
5. Footnote line (lock symbol): "Made on this iPhone. Nothing uploads." (or the cloud availability note, States).
6. Bottom action `.jovraAccent` "Preview my story" with arrow.

**Copy.** Disabled-length reasons: "Rally Pulse films are up to 3 min." / "Match Broadcast needs at least 5 min."
Readiness lines: "Needs a lesson note or a reviewed cue" (Coach's Cut), "Needs two dated sessions with the same stat"
(Progress Story), "Mark a few moments first" (any profile with no keepers).

**Data bindings.**
| Element | Source |
|---|---|
| Thumbnails, readiness | `KeeperSelector.candidates` + `StoryDirector.brief` dry run per profile |
| Length options | profile `recommendedDurationSeconds` ∩ coverage |

**States.**
| State | Treatment |
|---|---|
| No relevant keepers | Card readiness "Mark a few moments first"; selecting it and continuing opens the player with a "Mark point" coach mark; Preview disabled for that profile |
| Profile needs notes | Coach's Cut / Progress Story readiness lines; continuing offers the fallback ("Your examples" / lesson chronology) with an explanation |
| Quote unavailable | Footnote "Cloud production isn't available. Your iPhone makes the film." |
| Local draft | Default footnote "Made on this iPhone. Nothing uploads." |
| No music rights | Rally Pulse line "Court sound (no licensed track)" |
| Sample | Badge |

**Interactions.** Preview my story → `storyProfile(projectId, profileId)` (ST30, ST31, ST32, ST33) or, for Match
Broadcast, ST27 in Film mode with a profile options sheet; the local draft render starts immediately (RulesPlanner,
preview quality) and its progress shows on the next screen.

**Accessibility.** Radio group "Story style, 1 of 5"; each card reads name, line, readiness. Length pills are a
segmented control with disabled reasons as hints.

**Phone and iPad.** iPad: two-column card grid.

**Deliberate differences from the reference image.**
- The Sample chip's cloud symbol → dashed Sample badge.
- "Sample lengths" label removed (lengths are options, not sample data).
- Progress Story thumbnail with "Higher consistency" bars removed (an unearned claim) → a dated before/after frame.
- Stock photos → frames from the project's own keepers.

---

### ST30 Coach's Cut (`storyProfile(projectId, coach-cut)`, reference 30)

**Purpose.** An instructional film: goal, original-speed examples, a reviewed cue, a labelled replay, a next drill —
with checkable numbers.

**Route and entry.** Push from ST29; from a lesson ("Make a Coach's Cut"). Tab bar visible.

**Layout.**
1. Navigation bar: back; trailing "Options" (`slider.horizontal.3`) → film options sheet (length, Sound, replays
   ½× / ¼× / off, captions [S5]).
2. Title "Coach's Cut" subtitle "Understand the moment. Practice the change."
3. Preview `VideoSurface` (16:9) of the local draft with `SampleBadge` "Sample film", native-style controls (play,
   "00:38 / 05:00", scrubber, mute, fullscreen). The cue text "Recover toward the center." and its arrow are rendered
   into the film from a reviewed annotation and the catalog template — not UI overlays.
4. Three **ChapterCard**s: "01 The pattern", "02 The adjustment", "03 Your next drill" (current chapter forest-filled
   with chartreuse chevron; tap seeks).
5. **MetricFractionCard**: `ProvenanceBadge` "Reviewed"; "18 of 30" (`Font.jovraMetric`); "first serves in"; ring
   with "60%"; tap → `FractionPopover` (definition, both counts, contributing points, session date).
6. Bottom row: `.jovraSecondary` "Original speed" (speedometer symbol; plays the current example's original-speed
   keeper) and `.jovraAccent` "Save to lesson" (bookmark symbol).
7. Below the row: text button "Create film without a lesson".

**Copy.** Sound row inside Options (required before Save, SD5): "Sound · Choose" → "Natural court audio" / "No audio".
Draft progress: "Building your preview on this iPhone · 40%".

**Data bindings.**
| Element | Source | Provenance |
|---|---|---|
| Preview, duration | local draft render of the compiled EDL | Sample in demo |
| Chapters | EDL chapter markers from the profile beats | — |
| 18 of 30 · 60% | `StatsEngine` first serves in over the lesson's session; `pct(18,30)` | Reviewed (weakest input) |
| Cue | reviewed `Observation` / lesson note | Reviewed or Manual |

**States.**
| State | Treatment |
|---|---|
| Unknown stat | Metric card "First serves in · —" / "No reviewed serves in this session yet"; the film omits the metric (finding listed in Options → "Left out") |
| Manual cue | Cue chip in the film reads "Your note"; card provenance Manual |
| Rejected cue | Omitted; `BannerView` "1 cue was left out because you marked it not right." |
| No drill | Chapter 03 becomes "Next checkpoint"; card "Add a drill to finish the film" → lesson drill editor |
| Labelled replay | Film shows "Replay · ½×"; preview scrubber marks replay ranges |
| Original-speed fallback | When source fps × ½ < output fps: `InfoCard` "Slow replays need 60 fps video. This film shows the examples at original speed." |
| No reviewed cue at all | Title card becomes "Your examples"; no instruction titles (grammar fallback) |
| Draft rendering / failed | Progress overlay on the preview; failure `StateCard` "The preview didn't finish. Your videos are safe." + "Try again" |
| Stale | Banner "Made before a correction" + "Rebuild" |

**Interactions.** Save to lesson → lesson picker → final render + verification in the background → Toast "Saving your
film to Oct 7 · Serve rhythm" → ST38 (local job) → ST39 when ready. "Create film without a lesson" → same without
attaching. Options → sheet; changes re-plan and re-render the draft.

**Accessibility.** Ring is decorative; the value is text. Chapter cards are buttons ("Chapter 1 of 3, The pattern,
current"). Preview controls are standard `AVPlayerViewController`-equivalent controls with labels.

**Phone and iPad.** iPad: preview left, chapters/metric/actions right.

**Deliberate differences from the reference image.**
- "Original speed" dropdown → a button that plays the original-speed keeper (replay speed lives in Options), so the
  original-speed evidence is one tap away.
- A Sound choice is required (SD5); the image has none.
- Trailing JV avatar removed.

---

### ST31 Rally Pulse (`storyProfile(projectId, rally-pulse)`, reference 31)

**Purpose.** An energetic highlight film that keeps each shown rally intact, with optional, bounded effects and a clean
version.

**Route and entry.** Push from ST29. Forest screen in both appearances (`EditorialCard` surfaces); tab bar visible.

**Layout.**
1. Navigation bar: back (ivory).
2. Title "Rally Pulse" subtitle "Feel the energy."
3. Preview `VideoSurface` with `SampleBadge` "Sample film", play, "00:14 / 01:00", scrubber, fullscreen. The title
   accent "The rally" is film content from the catalog template, placed outside the action-safe box.
4. **TreatmentChips** (read-only summary of the treatment, not toggles): "Fast cuts" · "Court sound" · "Key points".
5. Options card (ivory `.jovraCard()` on forest):
   - "Effects intensity" slider with three detents "Subtle" · "Medium" · "High" (default Subtle).
   - `ToggleRow` "Camera shake" · "Adds movement between rallies, never during play." (default off).
   - `SettingsRow` "Music" · "Choose a licensed track" (chevron).
   - `ToggleRow` "Keep full rallies" · "Include complete points, not just highlights." (default on).
   - `SettingsRow` "Sound" · "Choose" (SD5).
6. Bottom action `.jovraAccent` "Generate preview" (re-renders the draft with the chosen options); after a preview
   exists, a second `.jovraAccent` "Create film" replaces it and "Generate preview" becomes a text button.
7. Footnote with dashed symbol "Sample data" in demo.

**Copy.** Keep full rallies off: each shown rally may start at the first shot of its key exchange and still runs
uncut to the point's end; the in-film point chip reads "Joined mid-rally".

**Data bindings.** Treatment chips from the profile grammar; durations from the EDL; options stored in the project's
profile settings.

**States.**
| State | Treatment |
|---|---|
| Reduce Motion | Slider disabled at Subtle with caption "Clean version — Reduce Motion is on"; shake hidden; clean alternate is the default output |
| Clean alternate | Segmented "With effects · Clean" above the preview to watch both; both are rendered and verified when effects are used |
| No licensed music | Music row value "Court sound" and disabled with "Licensed music arrives in a later update" (S1–S4) |
| Clip too short | `BannerView` "Only 2 rallies are long enough — the film will be 0:40." Under the 30 s minimum: `StateCard` "Not enough rallies for Rally Pulse." / "Try Match Broadcast, or mark more points." |
| Contact frames protected | Always-visible caption under the slider: "Effects stay off during contact." |
| Sample | Badges |

**Interactions.** Slider detents give selection haptics; changing options marks the preview outdated ("Preview is out of
date · Generate preview"). Create film → ST38 → ST39.

**Accessibility.** Slider is adjustable with three named values; toggles have descriptions as hints; preview controls
labelled. Flash and shake limits are enforced by the validator, not by the player.

**Phone and iPad.** iPad: preview left, options right.

**Deliberate differences from the reference image.**
- Subtitle "Turn your sessions into highlight reels." → "Feel the energy." (brief line; "highlight reel" is a core term).
- Default intensity Subtle, not the image's Medium (`story-profiles.json`: `effectIntensity: low`); Medium is a user
  choice in fixtures.
- Camera shake description changed to state where shake is allowed.
- Footnote cloud symbol → Sample's dashed square; Sound row added (SD5).

---

### ST32 Progress Story (`progressStory(scope)`, reference 32)

**Purpose.** Show learning across dated, comparable sessions and lessons, with denominators and percentage points, and
build a reflective film.

**Route and entry.** Push from Insights ("Progress Story"), ST34 ("Create film"), ST35 ("Add to Progress Story"), ST29.
Tab bar visible (Home or Insights, whichever pushed it).

**Layout.**
1. Navigation bar: back; kicker "Studio"; trailing `ProvenanceBadge(.sample)` "Sample data".
2. Title "Progress Story" subtitle "Four weeks. A game that's growing." (the duration phrase is computed from the two
   dates: 28 days → "Four weeks."; otherwise "Sep 9 to Oct 7.").
3. **ComparisonPair** (before/after): two frames from comparable examples synced at contact (core Comparison sync
   point), date chips "Sep 9" and "Oct 7", captions "Before" and "Now".
4. **ComparisonStatCard** (`EditorialCard`): trend symbol; `ProvenanceBadge` "Reviewed"; "First serves in"; trailing
   "Source: 2 reviewed sessions."; "12 / 30" with "40%" → arrow → "18 / 30" with "60%"; "+20 percentage points".
5. **JourneyTimeline** card "The journey": three nodes — "Lesson 1 · Find the rhythm", "Lesson 2 · Repeat the
   routine", "Today · Trust the motion" (done = filled check, current = ring with dot; shapes, not only colour).
6. Film card: thumbnail with "03:00", kicker "Your progress film", title "Progress Story · Sep 9 – Oct 7" (editable),
   `.jovraAccent` "Build my progress film" (video symbol, arrow).

**Copy.** Comparison footnote (tap card): "Same stat definition and counting method on both dates. Two sessions show a
change; they can't show why it happened."

**Data bindings.**
| Element | Fixture | Source | Provenance |
|---|---|---|---|
| 12 / 30 · 40% | Sep 9 | `ProgressStoryBuilder.compare(firstServeIn, Sep 9, Oct 7)` → `Fraction`, `pct` | Reviewed |
| 18 / 30 · 60% | Oct 7 | same | Reviewed |
| +20 percentage points | 60 − 40 | difference of the two displayed integers | — |
| Journey | lessons in scope | `ProgressStoryBuilder.journey(lessons)`: node title "Lesson n" or "Today" (only when the lesson date is today; otherwise the date), caption = the lesson's focus line | — |
| Four weeks | Oct 7 − Sep 9 = 28 days | date difference | — |

**States.**
| State | Treatment |
|---|---|
| No earlier evidence | `StateCard` "Progress needs an earlier session with the same stat." / "Choose sessions, or make a lesson chronology instead." Actions "Choose sessions", "Make a chronology" |
| Method change | Stat card replaced by `BannerView` "Sep 9 was counted by hand; Oct 7 from reviewed estimates. These can't be compared." Film becomes a chronology with a method-change note |
| Differing sample selection | Examples labelled "Examples you chose"; the stat appears only if both sides use the same selection rule |
| No measurable change | Card shows "+0 percentage points" and "No change yet" — never hidden |
| Manual reflection only | No stat card; journey + "Your reflections" list; film is a lesson chronology |
| Sample | Badges |

**Interactions.** Stat card → `FractionPopover` for each date. Journey node → ST35 for that lesson. Build my progress
film → options sheet (length 2–6 min within 120–360 s, Sound) → local render → ST38 → ST39.

**Accessibility.** Stat card reads "First serves in, reviewed. September 9: 12 of 30, 40 percent. October 7: 18 of 30,
60 percent. Plus 20 percentage points. Source: 2 reviewed sessions." Journey is a list with position ("Step 3 of 3,
today, Trust the motion, current").

**Phone and iPad.** iPad: comparison and stat side by side.

**Deliberate differences from the reference image.**
- Film title "Four Weeks in Focus" and tagline "Same effort. A clearer you." → an editable default title and no
  tagline (the tagline asserts a causal story).
- Journey captions come from each lesson's focus line (the brief's text is the fixture value); lesson titles stay
  those in the journal (ST34).
- "Four weeks" is computed, not fixed copy.

---

### ST33 Court Memories (`storyProfile(projectId, court-memories)`, reference 33)

**Purpose.** A cinematic memory of a real day on court: arrival, the match, the moment after — real B-roll, natural
sound if chosen, optional caption, private location.

**Route and entry.** Push from ST29. Tab bar visible.

**Layout.**
1. Navigation bar: back; trailing "Options".
2. Title "Court Memories" subtitle "Keep the moments that matter."
3. Hero preview `VideoSurface` with the film's title card "A good day on court." (editable film title; rendered into
   the film), play, "04:18 · 16:9", `SampleBadge` "Sample film".
4. `SectionHeader` "Chapters" + trailing "3 chapters"; three **ChapterCard**s with thumbnails (real B-roll/keeper
   frames) and number badges: "Arrival 00:42", "The match 02:21", "The moment after 01:15".
5. `SectionHeader` "Narrative" + Sample badge; **NoteRow** (document symbol): "A match to remember." and the
   player's caption, or "Add a few words (optional)" when empty; chevron → caption editor.
6. `SectionHeader` "Sound"; **ChoiceRow** (waveform symbol) "Natural court audio" · "Court sounds, voices and
   atmosphere" with trailing state ("Choose" until chosen; then "Selected" + check); second option "No audio" in the
   same sheet.
7. `ToggleRow` "Show the venue" · "Off keeps your location private." (default off).
8. Bottom action `.jovraAccent` "Create this memory" (disabled with hint "Choose the sound first" until Sound is chosen).

**Copy.** Caption editor: "Write a caption or dedication. It appears as you type it." (max 120 characters).

**Data bindings.**
| Element | Source |
|---|---|
| Chapters and durations | EDL chapter markers; chapters sum to the film duration (asserted in tests) |
| Thumbnails | BrollCatalog / KeeperCatalog frames |
| Caption | user text (Manual) |
| Sound availability | primary source has audio |

**States.**
| State | Treatment |
|---|---|
| One source | Works as designed; Options shows "One angle" |
| No B-roll | `BannerView` "No arrival clips marked. Mark some in the player, or the film starts with the match." Action "Mark B-roll" (→ ST27 with a B-roll marking mode); "Arrival" chapter shrinks to the first real frames |
| Venue hidden | Default; no venue text anywhere in the film or the YouTube draft |
| Personal caption omitted | NoteRow empty state; no caption card in the film |
| No natural audio | Sound row "This video has no sound" with only "No audio" available |
| Sample | Badges; the sample caption is a fixture written as user text |

**Interactions.** Chapter card → seek. Create this memory → final render → ST38 → ST39.

**Accessibility.** Chapters list ("Chapter 1, Arrival, 42 seconds"); the Sound choice is a radio group with its effect
explained in the hint ("Voices recorded on court will be in the film").

**Phone and iPad.** iPad: hero left, chapters and choices right.

**Deliberate differences from the reference image.**
- Subtitle "Your matches. More than scores." → the brief's profile line "Keep the moments that matter."
- The narrative body "Great rallies, good company…" is invented copy → the player's own caption (empty by default).
- "Natural court audio · Selected" pre-selected → unchosen until the player picks (SD5).
- The fist-bump photo is fictional; real films use real moments only.

---

### ST34 Lesson journal (`lessonJournal`, reference 34)

**Purpose.** Dated lessons with notes, linked clips and practice, and the bridge to a Progress Story.

**Route and entry.** Push from the Insights root. Tab bar visible, Insights selected.

**Layout.**
1. Navigation bar: back; trailing "+" (new lesson); kicker "October 2026" (current month); trailing
   `ProvenanceBadge(.sample)` "Sample journal".
2. Title "Your lesson journal." subtitle "Every lesson stays with you."
3. **TodayFocusCard** (light card with a trailing frame of the lesson's first clip): kicker "Today's focus"; "Serve
   rhythm"; focus line "Same toss. Calm finish." in the system italic serif; "2 of 3 drills complete" with a
   determinate bar.
4. `SectionHeader` "Recent lessons" + "View all".
5. **LessonRow** × 3: thumbnail, date kicker ("Oct 7"), title ("Serve rhythm"), "3 clips", `StatusPill(.positive)`
   "Reviewed" when every note is reviewed, chevron.
6. CTA `EditorialCard`: "Turn these lessons into a Progress Story." / "Your lessons, in order." / `.jovraAccent`
   "Create film" with arrow.

**Copy.** New-lesson sheet: "Date", "Title", "Focus line (optional)", "Coach (optional, as you'd write it)".

**Data bindings.**
| Element | Source |
|---|---|
| Today's focus | lesson dated today, else the most recent lesson; focus line; drills completed / total |
| Rows | `LessonJournal.lessons` newest first; clip count = linked clip refs |
| Reviewed | all notes have provenance Reviewed (or Manual by the player) |

**States.**
| State | Treatment |
|---|---|
| Empty | `StateCard` "Your first lesson goes here." / "Add notes, link clips and set a drill." Actions "Add a lesson", "Explore the sample" |
| Offline | No change (local); with cloud sync on (S4) a caption "Changes will sync when you're online." |
| Missing / deleted clip | Row line "1 clip missing" (attention) → ST35 repair |
| Private coach share | Row pill "Shared with coach" (S4) or "Exported for coach" (S1 export) |
| Export | Lesson context menu "Export for coach" → A-export sheet (Share Pack scoped to that lesson) |
| Manual lesson | Row "No clips yet" |
| Sample | Badges |

**Interactions.** Row → ST35. Today's focus → ST35 for that lesson. Create film → ST32 scoped to the journal's lessons.
"+" → new-lesson sheet.

**Accessibility.** Focus card is one element ("Today's focus, Serve rhythm, Same toss. Calm finish. 2 of 3 drills
complete"). Rows read date, title, clip count, review state.

**Phone and iPad.** iPad: journal is the list column of ST35's workspace.

**Deliberate differences from the reference image.**
- Subtitle "Track. Review. Improve." → brief "Every lesson stays with you."; CTA line "Your improvement, in motion." →
  "Your lessons, in order." (no improvement claim before a comparison exists).
- Handwritten script → system italic (no third font family; core typography).
- The JV avatar removed; photos → lesson clip frames.

---
### ST35 Lesson workspace (`lesson(lessonId)`, reference 35)

**Purpose.** Revisit one lesson: clip-linked notes, cues, the practice checklist and links to films and Progress
Story.

**Route and entry.** Push from ST34, ST32's journey, ST21's lesson row. On iPad regular width it renders as a
three-pane workspace (`NavigationSplitView`: lessons · lesson · notes) under the standard tab bar; on phone it is a
lesson detail screen.

**Layout (iPad landscape).**
1. Standard iPadOS tab bar at the top (Home · Sessions · Record · Insights · Profile; Insights selected).
2. Left column "Lessons" + "+": LessonRows with full dates ("Sep 9, 2026 · First serve foundation · 4 clips · 36 min",
   "Sep 23, 2026 · Recovery step · 2 clips · 42 min", "Oct 7, 2026 · Serve rhythm · 3 clips · 28 min"); selected row
   chartreuse-tinted with border.
3. Centre: title "Serve rhythm"; "October 7, 2026 · Sample lesson"; clip `VideoSurface` with rate pill "1×",
   "0:02 / 0:08", mute, fullscreen, and the lesson's reviewed annotation (cue arrow) via `AnnotationLayer`; "Clips from
   this lesson": three clip thumbnails with durations and names ("1. Toss and rhythm 0:08", "2. Contact 0:10",
   "3. Follow through 0:10"), each with a menu (Play, Open in session, Remove from lesson).
4. Right column: "Notes" + `StatusPill(.positive)` "Reviewed"; numbered **NoteItem**s — "1 Calm setup" / "Relax the
   shoulders, find your rhythm before the toss." and "2 Finish balanced" / "Land inside the court, stay tall and
   balanced."; source row (camera symbol) "Source · Camera 1 · Clip 3". "Practice checklist": **ChecklistRow**s
   "10 shadow serves 10 / 10" ✓, "20 target serves 20 / 20" ✓, "Review 5 clips 0 / 5" ☐.
5. Actions: `.jovraAccent` "Save lesson" (enabled when there are unsaved edits), `.jovraSecondary` "Add to Progress
   Story".

**Layout (phone).** Title and date; clip player; horizontal clip strip; Notes (edit in a sheet); Practice checklist;
bottom bar "Save lesson" / "Add to Progress Story"; "More" menu (Export for coach, Attach film, Delete lesson).

**Copy.** Note editor: "Who wrote this? You / Your coach (as you'd write their words)". Drill editor: "Drill", "Target",
"Done". Leave guard: "Save changes to this lesson?" · "Save" · "Discard" · "Keep editing".

**Data bindings.**
| Element | Source | Provenance |
|---|---|---|
| Lesson facts | `jovra.lesson/1` record | — |
| Durations | linked sessions' durations | — |
| Notes | lesson notes with author and provenance | Manual / Reviewed |
| Checklist | drill targets and counts (a 5-clip review target may exceed the 3 saved clips) | — |
| Source row | the note's clip reference → camera slot and clip number | — |

**States.**
| State | Treatment |
|---|---|
| Unreviewed note | Note pill "Not reviewed" + "Mark reviewed"; header pill shows "1 not reviewed" instead of Reviewed |
| Unsaved edits | Save enabled; leave guard sheet |
| Source unavailable | Clip thumb "Video not on this iPhone" + "Find the video" (core missing-file repair) |
| Permission revoked | (S4, coach view) `StateCard` "Your access to this lesson ended." |
| Conflicted sync | (S4) `BannerView` "This lesson changed on another device." Actions "Keep both", "Choose a version" |
| Manual lesson | Clip area `StateCard` "No clips yet" + "Link a clip" (→ session picker → range) |
| Sample | Badge "Sample lesson" in the date line |

**Interactions.** Tap a clip → plays it; drag a clip to reorder; checklist rows are steppers on tap (target/done) with
`UndoBar`. Add to Progress Story → ST32 with this lesson added to scope.

**Accessibility.** Three panes are separate landmarks; checklist rows are adjustable ("10 shadow serves, 10 of 10,
done"); notes read number, title, body, author, provenance.

**Phone and iPad.** As above.

**Deliberate differences from the reference image.**
- The header's "JOVRA Studio · A better game tomorrow" and JV avatar are removed: the workspace sits under the
  standard tab bar, which the image draws correctly (no sixth tab).
- Lesson durations come from linked sessions rather than fixed text.

---

### ST36 Film storyboard (`storyboard(planId)` on iPad, `storyboardList(planId)` on phone, reference 36)

**Purpose.** Optional advanced review of a versioned, source-bound plan: beats, segments with exact source windows,
continuous court audio, derived score, template titles — approve, adjust or rebuild. Approval never spends or shares.

**Route and entry.** From ST27 "Edit this film", a profile screen's Options → "Review the plan", ST38 job details
("Review the plan") when a job awaits review. iPad: full-screen workspace. Phone: push with sheets.

**Layout (iPad landscape).**
1. `FocusedHeader`: Close, compact lockup, "Studio", title "Shape the story", subtitle "Court Memories · Sample
   project", plan state pill ("Draft · not approved" / "Approved" / "Built from older scores").
2. Left "Sources" + "4 items": **SourceBinCard**s "Camera 1 · 2:14", "Camera 2 · 1:32", "B-roll 1 · 0:48",
   "B-roll 2 · 1:06" (usable keeper/B-roll time per source), selected = chartreuse border.
3. Centre preview `VideoSurface` "00:15 / 04:18", mute, fullscreen, picture-in-picture.
4. Right inspector with tabs "Story" · "Details". Story: "Court Memories", "Sample project", **StoryBeatList**
   ("1 Arrival 00:00", "2 The match 00:12", "3 Closing moment 03:55"; each with thumbnail and a menu: Change clip,
   Move, Remove); "Selected clip" **ClipInspector**: thumbnail, "Camera 2", "In 00:12.400", "Out 00:18.600",
   "Duration 00:06.200", "Placed 00:12.000 – 00:18.200 · 1×", "Audio · Court audio from Camera 1". Details: profile
   and revision, output (1080p · 30 fps · H.264), event/sync revisions, planner ("Made on this iPhone"), findings.
5. `.jovraAccent` "Approve film plan" (arrow) and `.jovraSecondary` "Rebuild draft".
6. Bottom **StoryboardTimeline**: "00:15.000 / 04:18.000", zoom in/out, scale slider, "Fit"; a ruler 00:00 – 04:18
   scaled exactly from frames; lanes — "Video" (segments labelled from keeper/B-roll names with their output range and
   an angle tag "1", "2" or "B"; fills distinguished by source with pattern + tag, not colour alone), "Court audio"
   (one continuous waveform bed), "Score" (event-derived score changes, e.g. set ends "6–4", "6–3"; the score bug is
   off by default in Court Memories), "Titles" (title cards from templates: the film title, an optional chapter title,
   the closing card).

**Layout (phone).** Beat list of **BeatCard**s (thumbnail, beat name, output range, source and window); tap → segment
sheet (angle picker limited to synchronized coverage, `JogStrip` trim inside the keeper window, speed fixed at 1× for
`live`, Remove); findings banner at top; bottom bar "Approve film plan" / "Rebuild draft".

**Copy.** Findings use plain reasons: "Goes past the end of Camera 2's video.", "Crosses a recording gap at 41:12.",
"Shake isn't part of Court Memories.", "No licence recorded for this track.", "A title would cover a contact moment."

**Data bindings.**
| Element | Source |
|---|---|
| Segments, times | compiled EDL (exact rational times shown to the millisecond; source window vs output placement shown separately) |
| Beats | StoryPlan beats → EDL chapters |
| Score lane | core fold at each segment's session times |
| Titles | template IDs + slots (user text, dates, names as entered) |
| Findings | `EDLValidator` + `StoryDirector.lint` |

**States.**
| State | Treatment |
|---|---|
| Invalid window | Segment outlined with a warning symbol; finding in the inspector; Approve disabled |
| Gap | Hatched lane span "Recording gap · 0:41"; a segment cannot be dragged across it |
| Unsupported effect | Finding; the effect control is not offered for this profile |
| Missing audio rights | Music lane (S5) finding; Approve disabled until removed or a rights record exists |
| Older point revision | Header pill "Built from older scores"; `BannerView` "Points changed since this plan was made." Action "Rebuild draft"; Approve disabled |
| Pending plan approval | Default "Draft · not approved"; after Approve: "Approved · not yet made" then "Create film" (local) or "Continue to quote" (cloud) |
| Rebuild | Progress "Rebuilding from your current points…" then a summary "3 beats changed" with a diff list |
| Sample | Badges |

**Interactions.** Edits produce a new plan version; every edit re-validates before preview. Approve records the
approval on that plan version only. Keyboard: ←/→ frame, ⇧←/⇧→ segment, ⌘Z / ⇧⌘Z, ⌘↩ approve.

**Accessibility.** Timeline is adjustable by segment and by frame; each segment reads "Segment 2, Close, Camera 2,
output 12.0 to 18.2 seconds, source 12.4 to 18.6 seconds". Lanes are separate containers. Phone beat list is the
accessible equivalent of the timeline.

**Phone and iPad.** As above.

**Deliberate differences from the reference image.**
- Contextual nav "Edit · Projects · Library" → a `FocusedHeader` and inspector tabs (projects and films are reached
  from Studio Home; no parallel navigation).
- The "JOVRA" logo painted on the court windscreen in the preview is removed: no brand inside footage.
- Segment "1. Vide" truncation → its beat name; "5. Reactions" → the player's own keeper name (no implied reaction
  shots); title cards "A better game tomorrow" / "Great rally" / "See you on court" → the film title and template
  cards the player chose.
- The cloud symbol on the project menu removed (the plan is local).

---

### ST37 Cloud preflight quote (`preflight(jobDraft)`, reference 37) [S4; demo from S0]

**Purpose.** Before anything leaves the phone: what uploads, what it costs (estimate and cap), how long copies stay,
and an explicit consent — with the local path always beside it.

**Route and entry.** From a profile screen's Options → "Make it in the cloud" (shown only when CloudMode is demo, test
or live), or ST36 "Continue to quote". Push; tab bar visible.

**Layout.**
1. Navigation bar: back.
2. Title "Ready to create?" subtitle "Know before you create."
3. Film summary card: thumbnail with "5:00" chip; "Coach's Cut"; "5 min · 3 angles"; chevron → plan summary.
4. **QuoteCard** (forest, two panels): left decorative panel (`CourtLinesBackdrop`, kicker "JOVRA Studio"); right:
   "Sample quote" (or "Quote · expires in 28 min"), "$4 – $8", "Estimated processing", divider, "Spending limit"
   "$12", footnote "Illustrative pricing. Final quote appears before payment."
5. `SettingsRow`s (with chevrons → detail sheets):
   - "Cloud processing" · "Private upload" (cloud-upload symbol) → A5 consent detail: the selected sources, bytes and
     an estimated upload time ("3 angles · 10.8 GB · about 1 h 12 min on this Wi-Fi", from the last measured upload
     rate; "Upload time depends on your connection" when none is measured; six 60-min angles are 21.6 GB, at least
     144 min at 20 Mbps), Wi-Fi only state, and what the planning step receives ("Sampled frames and your point events,
     not your full videos"; note text only as ticked in the consent: "Your notes" on, "Your coach's notes" off by
     default).
   - "Originals" · "Kept on device" (iPhone symbol).
   - "Temporary media" · "Delete after 7 days" (clock symbol) → retention sheet (1 / 7 / 30 days).
6. **ConsentRow**: checkbox (44 pt) "I agree to upload these selected videos" — unchecked by default.
7. `.jovraAccent` "Create film" (disabled, grey, until consent is ticked, the quote is valid and the identity allows);
   `.jovraSecondary` "Use local replay" (→ back to the local film path for the same profile).

**Copy.** Demo footnote: "Demo mode does not upload or charge." Cap explanation (tap limit): "The job stops here and
asks you before using more."

**Data bindings.**
| Element | Source |
|---|---|
| Quote, cap, expiry | `CloudClient.quote` (server-computed from actual bytes, profile, output, current rates); Sample in demo/test |
| Sources and bytes | the job draft's source manifests |
| Upload time | bytes ÷ the last measured upload rate on the current network (an estimate, labelled so); absent when unmeasured |
| Retention | job draft policy (default 7 days) |
| Consent | `QuoteReservation` state `consented` (local until accepted) |

**States.**
| State | Treatment |
|---|---|
| Demo — charge disabled | QuoteCard "Sample quote"; Create film runs the demo job (no upload, no charge) |
| Real quote expired | QuoteCard "This quote expired." + `.jovraAccent` "Get a new quote"; Create disabled; consent cleared |
| Not signed in | QuoteCard replaced by `StateCard` "Sign in to make films in the cloud." Action "Connect account" (A12); "Use local replay" stays |
| Cost above cap | QuoteCard attention "The estimate is above your limit." Actions "Change limit" (A8; the player raises it explicitly), "Choose fewer angles" |
| No cloud consent | Create disabled; helper "Tick the box to upload these videos." |
| Retention choice | Sheet; changing retention re-quotes |
| Local replay | Secondary button always available |
| Wi-Fi only on cellular | Row note "Upload will wait for Wi-Fi." |
| Cloud unavailable | `StateCard` "Cloud production isn't available right now." + "Use local replay" |

**Interactions.** Create film → `CloudClient.accept(quote, consent, cap, idempotencyKey)` → ST38. A second tap or a
retry reuses the idempotency key (one job, one reservation).

**Accessibility.** Quote card reads "Sample quote. Estimated processing 4 to 8 dollars. Spending limit 12 dollars.
Illustrative pricing; the final quote appears before payment." Disabled Create explains why in its hint.

**Phone and iPad.** iPad: summary and quote side by side.

**Deliberate differences from the reference image.**
- Decorative opening quotation mark and quoted "A better game tomorrow." removed (it reads as a quotation); the left
  panel keeps only the kicker over the court backdrop.
- Subtitle "Turn your tennis into a story." → brief title "Know before you create."
- Clay-court stock photo → the film's own thumbnail.

---

### ST38 Render queue (`job(jobId)`, reference 38)

**Purpose.** A durable job's honest progress — real stages with independent states — that the player can leave,
pause, cancel or retry without losing anything.

**Route and entry.** Push after creating a film (local or cloud), from ST21's banner, a notification, or ST39 when a
film is still verifying. Tab bar visible.

**Layout.**
1. Navigation bar: back.
2. Title "Your story is taking shape."
3. Job card: thumbnail with `ProvenanceBadge(.sample)` "Sample"; kicker "JOVRA Studio"; "Court Memories"; "3 angles ·
   Created Oct 7, 2026"; chevron → job details sheet.
4. **JobStageList** (`StageTimeline` extension; symbol + word per state, connector line):
   - "Upload" · "Complete" · "3 camera sources uploaded" (upload symbol)
   - "Align angles" · "Complete" · "Alignment reviewed" (film-strip symbol)
   - "Build film" · "In progress" · "Building your private preview" (scissors symbol)
   - "Verify export" · "Queued" · "Checks every frame before it's ready" (checkmark-shield symbol)
   Local single-angle jobs show "Plan story · Build film · Verify export". The contract states `normalizing`,
   `syncing` map to "Align angles"; `analyzing` (which in v1 runs no vision analysis: it gathers the bound points,
   keepers and existing notes for the plan) and `planning`, `preview_rendering`, `final_rendering` map to "Build film";
   no stage is ever labelled "Analyzing".
5. **StageProgressCard** (`EditorialCard`): kicker "Build film"; "Rendering your private preview"; "42%" with the
   caption "of this step"; decorative static waveform; determinate bar; "You can leave this screen. We'll keep your
   place." Sample badge in demo.
6. Bottom row: "View job details" (list symbol), "Pause upload" (disabled with the reason "Upload finished" once the
   upload is complete; hidden for local jobs), `.jovraSecondary` "Cancel job".

**Copy.** Job details sheet: each stage with start/end times, attempts ("Attempt 2 of 3"), reservation and receipt
(S4: "Estimate · Cap · Used so far"), and "What's kept: your originals stay on this iPhone." Cancel sheet: "Cancel this
film?" / "Temporary copies will be removed. Your originals stay on this iPhone." · "Cancel film" · "Keep going".

**Data bindings.** `CloudClient.job` stream (cloud) or the local `RenderJob` (local); stage progress only from stages
that report a real fraction (decoded frames rendered / planned frames; bytes uploaded / bytes); no total-job percentage
is ever computed.

**States.**
| State | Treatment |
|---|---|
| Paused | Upload stage "Paused · 2.1 of 10.8 GB"; button "Resume upload" |
| Resumed | Stage returns to In progress; Toast "Upload resumed" |
| Retryable failure | Stage "Trying again · attempt 2 of 3" (attention symbol, not red alarm) |
| Terminal failure | `StateCard` "This film couldn't be finished." / "Your videos are safe on this iPhone. Nothing is charged for an unfinished film." Actions "See details", "Try again" (new reservation in S4) |
| Canceled | "Film canceled" → "Removing temporary copies…" → "Temporary copies removed" |
| Budget exhausted | `BannerView` attention "Stopped at your $12 limit." / "Raise the limit to continue, or keep the preview." (Sample in S4 test) |
| Notification unavailable | Footnote "Turn on notifications to hear when it's ready." (→ iOS Settings); the in-app badge always works |
| App suspended | Local job on iOS 18: banner "Rendering pauses if you leave JOVRA."; iOS 26: system progress via continued processing |
| Verifying | Verify stage In progress "Checking every frame · 61%" |
| Sample | Badges; demo transcript |

**Interactions.** Leaving and returning restores the screen from the durable job. Stages are not tappable except
"Build film" when a draft exists ("Watch the draft"). Cancel → sheet.

**Accessibility.** Stage list reads "Step 3 of 4, Build film, in progress, 42 percent of this step". Progress
announcements every 10% at most.

**Phone and iPad.** iPad: stages left, progress card right.

**Deliberate differences from the reference image.**
- Subtitle "From your sessions to something more." removed (not in the brief).
- "Verify export" upload-arrow symbol → checkmark-shield; "Creating your personalized edit" → "Building your private
  preview"; "Preparing final file" → "Checks every frame before it's ready" (what verification actually does).
- "42%" is captioned as this step's progress (implementation-states: not a total-job percentage).
- The card's cloud symbol on "Sample" → dashed Sample badge.

---

### ST39 Film delivery (`film(filmId, version?)`, reference 39)

**Purpose.** The finished, verified private film: play it, keep it, attach it to a lesson, prepare it for YouTube,
share privately — never published by JOVRA.

**Route and entry.** Push from ST38 (on ready), ST21's FilmCard, `studioFilms`, a "film ready" notification. Tab bar
visible.

**Layout.**
1. Navigation bar: back; trailing "More" (Versions, Show plan, Delete film).
2. Title "Your film is ready." subtitle "Keep the match. Share the story."
3. Hero `VideoSurface` poster with a centred play button, the film's title "A good day on court" (from the film),
   meta "Court Memories · 04:18 · 1080p", `SampleBadge` "Sample film".
4. **DeliveryPanel** (`EditorialCard`): checkmark-circle symbol, "Private preview", "Export verified · 412 MB",
   chevron → verification sheet (frames, duration, audio route, hashes, event revision, where it was made).
5. `.jovraAccent` "Download film" (cloud artifact) or "Save film" (local film) — download symbol.
6. Rows: "Save to lesson" (bookmark); "Prepare for YouTube" with the helper "Preparing for YouTube creates a video,
   cover and description. You choose when to upload." (play-rectangle symbol); "Shared link" · "Expires in 24 hours"
   with a refresh button (and Revoke in its detail) — no raw URL shown.
7. Version row when older versions exist: "Version 2 of 2 · current" → A14.

**Copy.** Save sheet: "Save to Photos" / "Save to Files" and the audio line ("Court audio" or "No audio" — the film's
chosen route). YouTube package sheet: editable "Title", "Description" (draft from the template; mentions any
generated or stock element), cover picker (real frames), chapters list, "Save package to Files". Footer: "JOVRA never
uploads for you."

**Data bindings.**
| Element | Source |
|---|---|
| Title, profile, duration, resolution | `FilmRecord` (duration from frames ÷ fps) |
| 412 MB | measured file size (Sample: illustrative) |
| Export verified | `FilmRecord.verification.passed` |
| Shared link | `CloudClient.shareLink` (S4; demo fixture) |
| Version | film versions for this plan lineage |

**States.**
| State | Treatment |
|---|---|
| Still verifying | Panel "Checking every frame… 61%"; Download/Save and Prepare disabled |
| Failed full decode | Panel attention "This film didn't pass its checks, so it isn't marked ready." Actions "Rebuild", "See details" |
| Expired link | Row "Link expired" + "Create a new link" |
| Access revoked | Owner: row "Link revoked"; viewer: `StateCard` "This film is no longer shared with you." |
| Partial download | Panel "Download paused · 212 of 412 MB" + "Resume"; completed downloads are re-verified by size and hash |
| Old version | `BannerView` "Version 1 · made before a correction." Action "Watch current version" |
| Archive disconnected | Optional row "Save to Google Drive" shows "Needs reconnect" (core archive state) |
| Junior mode | Shared link and Prepare for YouTube hidden; Save offers No audio only |
| Local film (S1) | Shared link row hidden (cloud only); "Save film" primary |
| Sample | Badges; the film's frames carry the Sample badge |

**Interactions.** Play → full-screen playback (or ST27 Film mode for Match Broadcast). Save to lesson → lesson picker.
Prepare for YouTube → package sheet → saved to Files; no network.

**Accessibility.** Hero reads "Play A good day on court, Court Memories film, 4 minutes 18 seconds, 1080p, sample".
Panel reads "Private preview, export verified, 412 megabytes".

**Phone and iPad.** iPad: hero left, actions right.

**Deliberate differences from the reference image.**
- Lockup "JOVRA STUDIO" → standard navigation (consistent with ST21).
- Subtitle "Relive it. Share it. Keep getting better." → brief title "Keep the match. Share the story."
- Primary button label depends on where the film lives (Download for a cloud artifact, Save for a local film).

---

### ST40 Studio settings (`studioSettings`, reference 40)

**Purpose.** Identity mode, storage providers with truthful states, privacy and retention, and export/delete controls.

**Route and entry.** Push from the Profile hub (Profile stack) or ST21's gear (Home stack). Tab bar visible.

**Layout.**
1. Navigation bar: back.
2. Title "Studio settings" subtitle "Your footage. Your choices."
3. **IdentityCard** (`EditorialCard` with `CourtLinesBackdrop`): kicker "Demo profile"; "Jon"; "Local demo · Cloud not
   connected"; `.jovraAccent` "Connect account" with arrow; kicker "A better game tomorrow".
4. `SectionHeader` "Storage" + Sample badge; `ProviderRow`s: "On this iPhone" · "Active" (iPhone symbol, filled);
   "iCloud Drive" · "Choose folder"; "Google Drive" · "Not connected"; "Box" · "Planned"; "Dropbox" · "Planned" — each
   with a state symbol + word and a chevron.
5. `SectionHeader` "Privacy": `ToggleRow` "Cloud processing" · "Off until you choose to upload" (off);
   `SettingsRow` "Camera invitations" · "Expire in 10 min"; `SettingsRow` "Temporary uploads" · "7-day policy".
6. Data group: `SettingsRow` "Export project" (share symbol); "Delete cloud copies" (trash, `destructiveInk`);
   "Download my data" (download symbol).
7. Footer `InfoCard` (info symbol): "Demo mode does not upload or charge."
8. "Advanced" (Test mode only): planner configuration ("On this iPhone · rules" or the pinned cloud planner), test
   backend status, "Help · hello@islanddevcrew.com" as selectable text.

**Copy.** Provider detail sheets (A17) explain scope: iCloud Drive — "Saves a project folder you choose in Files. It
isn't used to make films." Google Drive — the core archive copy ("Uses the same Google Drive connection as your
backups."). Box/Dropbox — "Planned. Not connected to anything yet." Cloud processing explainer (on toggle on): what
uploads, when, and that each film still needs its own consent.

**Data bindings.**
| Element | Source |
|---|---|
| Identity | `CloudClient.mode()` + `identity()` |
| Providers | `StorageProvider.capability` (Google Drive mirrors the core `ArchiveService` state and copy) |
| Cloud processing | project default upload policy (still per-job consent) |
| Invitations | room default expiry (5 or 10 min; never longer) |
| Temporary uploads | default retention (1 / 7 / 30 days) |

**States.**
| State | Treatment |
|---|---|
| Real auth — test / live | Identity card "Jon · Test backend" (test) or "Jon · Connected" (live) with "Sign out"; sign-out keeps local projects and films (A12) |
| Disconnect / reconnect | Provider detail "Disconnect" (confirmation: archives stay where they are) / "Reconnect" |
| Token expired | "Google Drive · Needs reconnect" (attention) |
| Provider planned / unavailable | "Planned" (neutral) / "Not available on this device" |
| Deletion running / failed | Row "Deleting cloud copies · 3 of 5" / attention "Deletion didn't finish." + "Retry" — never touches originals |
| Data export | Row "Preparing your data · 42 MB" → share sheet when ready |
| No configuration | "Connect account" disabled with "Cloud accounts aren't available in this version." |
| Junior mode | Cloud processing locked off with the reason |
| Sample | Badges |

**Interactions.** Connect account → A12. Provider row → A17 detail. Cloud processing toggle → explainer → on. Delete
cloud copies → A6 scope sheet → `CloudClient.deleteCloudCopies` with progress. Download my data → `exportMyData` (cloud)
plus the local data export.

**Accessibility.** Provider rows read name and state ("Box, planned, not connected"); toggles with descriptions as
hints; destructive rows have the destructive trait.

**Phone and iPad.** iPad: 720 pt column.

**Deliberate differences from the reference image.**
- Section "Cloud storage" → "Storage" (On this iPhone is not cloud; providers are archive providers, glossary).
- Subtitle "Manage your data, privacy and account." → brief title "Your footage. Your choices."
- The tab bar is visible (a push screen); the image omits it.
- Real Google Drive states use the core copy ("Awaiting Google Drive setup", "Connected", "Needs reconnect");
  "Not connected" appears only in demo.

---

## 2. Auxiliary sheets and alerts (implementation-states "beyond the twenty references")

All are sheets with detents (never imitation system dialogs), built from existing components.

| ID | Sheet | Opened from | Content and rules |
|---|---|---|---|
| A1 | Permission explainers: camera, microphone, Photos/Files, local network | ST22, ST23, ST24, ST25 | Explanation first, then the system prompt; denied state with consequence + "Open iOS Settings" (core PermissionsCenter). Microphone denial never blocks recording |
| A2 | Recording acknowledgement detail / camera check | ST23, ST24 | Per camera: acknowledged at (time), segment, preset, fps; "Not confirmed" with "Ask Alex to tap Start on that phone" |
| A3 | Stop one vs stop all | ST24 | "Stop this phone" / "Stop all cameras (n)" / "Keep recording"; stop-all waits for stop acknowledgements and reports counts |
| A4 | Missing-file repair | ST25, ST35, ST27 | Core missing-file flow: locate by hash in Files/Photos; never re-link a different file |
| A5 | Consent per selected source | ST37 | Lists each source with bytes and a per-source include switch; what the planner receives; retention |
| A6 | Delete scope | ST21, ST39, ST40 | Choices: "Delete this film" · "Delete editing copies (proxies)" · "Delete cloud copies" — originals are never in this sheet; deleting an original stays the core's explicit action |
| A7 | Quote expiry / reprice | ST37 | "This quote expired" → new quote shown side by side with the old; consent cleared |
| A8 | Spending limit | ST37, ST38 | Explicit new limit entry; never raised automatically |
| A9 | Partial upload retry | ST38 | Which sources/parts remain; "Retry upload"; confirmed parts are not resent |
| A10 | Manual sync markers | ST26 | Place a marker on both sources at the same visible/audible moment; preview the resulting offset and residual before saving |
| A11 | Invite / access expiry | ST23, ST35, ST39 | Expired code, revoked grant, expired share link: what still works and how to get a new one |
| A12 | Cloud sign-in and sign-out | ST37, ST40 | Sign in with Apple (system button) and email code (test/live); demo shows "Use demo profile"; sign-out keeps local data |
| A13 | Preview feedback | ST30–ST33, ST27 | "What would you change?" — swap an example, remove a beat, change length; produces a new plan version |
| A14 | Film version selection | ST39, ST27 | Versions with dates, revisions and "made before a correction" labels; choose to watch, save or delete |
| A15 | Caption correction [S5] | ST39 | Only for real speech; edits stored as Manual |
| A16 | Account export and deletion [S4] | ST40 | Export first; deletion revokes Sign in with Apple and removes cloud data; local data kept unless separately chosen |
| A17 | Provider scope explanation | ST40 | What each provider is used for and not used for; archive is not processing |
| A18 | Download recovery | ST39 | Resume, verify by size and hash, or discard a broken partial |
| A19 | YouTube channel and privacy confirmation [S5, when wired] | ST39 | Deliberate channel choice, privacy (Private default), final confirmation tap; until wired the package sheet saves files only |
| A20 | Sound choice | ST30–ST33 | "Natural court audio" / "No audio" with "Voices recorded on court will be in the film." Required before creating (SD5); junior mode forces No audio |
| A21 | Slot sheet | ST22 | Assign / replace / remove a slot; capability notes |
| A22 | Capture method | ST22 | Record now with this iPhone · Invite other phones · Use videos I already have |
| A23 | Lesson picker | ST28, ST30, ST39 | Recent lessons + "New lesson" |
| A24 | Session picker | ST21, ST25 | Core `SessionCard` list filtered to sessions with video |
| A25 | Film options | ST30–ST33 | Length, aspect (16:9; 9:16 letterboxed), Sound, replays (Coach's Cut), venue, caption |

---

## 3. State coverage map

Every state below is reachable in demo by a launch argument `-studioState <screen>.<state>` (for UI tests and
screenshots) and has an XCUITest with an accessibility audit. "Ref" states are from `implementation-states.md`; the
rest are additions this spec needs.

| Screen | Normal | Ref alternatives | Additional |
|---|---|---|---|
| ST21 | latest film, lessons, Build your match | noFilms, firstSession, localDemo, cloudUnavailable, lastJobFailed | filmVerifying, filmStale, noLessons, loading, anglesOneInThisBuild, anglesFromFilesOnly |
| ST22 | 1 primary + optional | oneAngle, occupiedRole, unsafePlacement, capabilityUnavailable | pairingNotInBuild |
| ST23 | 2 ready, 1 waiting | host, guest, qrExpired, inviteRevoked, roleFull, reconnect, permissionDenied, storageWarning, thermalWarning | joinRequest, noNetwork, unsupportedBeforeS3 |
| ST24 | primary live, aged stills | missingAck, deviceDisconnected, noMicrophone, previewUnavailable, lowBattery, lowSpace, interruption, hostExits | courtMode |
| ST25 | 3 × 3.6 GB | oneOldMatch, noAudio, unsupportedMedia, duplicate, partialSource, mixedFormats, insufficientSpace | working |
| ST26 | estimated offset/drift | manualMarkers, failedAlignment, noOverlap, drift, gapRestart, mutedSource, normalizingProxy, needsReview | — |
| ST27 | multi-angle, final score | oneAngle, missingAngle, buffering, uncertainSync, scoreUnknown, offline, staleFilm | filmMode |
| ST28 | estimated observation | manualNote, reviewedCue, unsupportedCapability, occluded, noCalibration, rejected | oneAngle |
| ST29 | five profiles + length | noKeepers, needsNotes, quoteUnavailable, localDraft, noMusicRights | — |
| ST30 | reviewed example + drill | unknownStat, manualCue, rejectedCue, noDrill, labelledReplay, originalSpeedFallback | noReviewedCue, draftFailed, stale |
| ST31 | full rallies, optional effects | reduceMotion, cleanAlternate, noLicensedMusic, clipTooShort, contactProtected | — |
| ST32 | 12/30 → 18/30 | noEarlierEvidence, methodChange, differingSelection, noChange, reflectionOnly | — |
| ST33 | real B-roll, original sound | oneSource, noBroll, venueHidden, captionOmitted, noNaturalAudio | soundUnchosen |
| ST34 | dated lessons | empty, offline, missingClip, coachShare, export, manualLesson | — |
| ST35 | notes + checklist | unreviewedNote, unsavedEdits, sourceUnavailable, permissionRevoked, conflictedSync | manualLesson |
| ST36 | versioned plan | invalidWindow, gap, unsupportedEffect, missingAudioRights, olderPointRevision, pendingApproval, rebuild | — |
| ST37 | sample quote, consent unchecked | demoChargeDisabled, quoteExpired, notSignedIn, aboveCap, noConsent, retentionChoice, localReplay | wifiOnlyCellular, cloudUnavailable |
| ST38 | upload/align done, build active | paused, resumed, retryableFailure, terminalFailure, canceled, budgetExhausted, notificationUnavailable, appSuspended | verifying, localJob |
| ST39 | private film, download, lesson, YouTube | stillVerifying, failedDecode, expiredLink, accessRevoked, partialDownload, oldVersion, archiveDisconnected | juniorMode, localFilm |
| ST40 | local demo, providers, privacy | realAuthTest, realAuthLive, disconnect, reconnect, tokenExpired, providerPlanned, providerUnavailable, deletionRunning, deletionFailed, dataExport | noConfiguration, juniorMode |

---

## 4. Component inventory (Studio additions)

Reused without change: everything listed in the header. Extensions to existing components:

| Component | Extension | Used by |
|---|---|---|
| `StageTimeline` | → **JobStageList**: per-stage symbol + word, detail line, attempt count | ST38 |
| `ScoreboardOverlay` | compact set table variant (**ScoreBug**) with "Final · Reviewed" footer and playhead-driven values | ST27 |
| `EditorialCard` | two-panel layout (QuoteCard), QR slot (JoinCodeCard) | ST23, ST37 |
| `ProviderRow` | states Active, Choose folder, Not connected, Needs reconnect, Planned, Unavailable | ST40 |
| `FilterPills` | disabled options with reasons (length pills) | ST29 |

New components:

| Component | Purpose | Notes | Used by |
|---|---|---|---|
| **StudioEntryCard** | Studio entry row on core screens | "JOVRA Studio" + line + chevron | S03 (core) |
| **StudioFactTile** | Non-stat number tile (no provenance); the angle tile's value follows the build's stage | StatTile look; VoiceOver per stage (ST21 Layout 6) | ST21 |
| **FilmCard** | Film thumbnail, title, profile, duration, Sample/stale/verifying lines | compact and full | ST21, film list |
| **LessonRow** / **TodayFocusCard** | Lesson list row; focus card with drills progress | | ST21, ST34, ST35 |
| **NextStepRow** | One suggested next action | (named in core S03, defined here) | ST21 |
| **CourtPlacementDiagram** + **SlotMarker** | Top-down court with six numbered camera slots and view cones | draws from `CourtGeometry`; adjustable group | ST22 |
| **JoinCodeCard** | Real QR, grouped code, countdown, slot | code spelled on demand | ST23 |
| **CameraSlotRow** / **AddSlotRow** | Camera, device name, slot, readiness with reason | dashed add row | ST23, ST25 |
| **SecondaryStillCard** | A camera's still with its age | never labelled live | ST24 |
| **DeviceHealthRow** | Recording state, battery, storage left, heat per camera | ages shown | ST24 |
| **SourceRow** / **SourceSummaryCard** | Import item with facts and slot; totals with "Originals stay on your phone." | | ST25 |
| **SourceCard** | Sync source with state pill | | ST26 |
| **SyncTimeline** + **WaveformLane** + **AnchorMarker** | Common match-clock lanes, gaps, checkpoints, anchors; waveforms drawn from each source's real decoded audio (peak envelope of the analysis proxy) | adjustable; waveform pixels hidden from VoiceOver (data given as text) | ST26 |
| **SyncInspector** | Offset, drift, alignment state, checkpoints, Confirm / Manual align | | ST26 |
| **AngleGrid** + **AngleThumb** | Selectable angles with coverage and sync state | hatched "No video here" | ST27 |
| **PointChip** | Point jump chip ("Point 4 · 03:21") | 44 pt | ST27 |
| **ComparisonPair** | Two synchronized frames/videos with labels | contact-synced in ST32 | ST28, ST32 |
| **ObservationCard** | Cue with provenance and source line | | ST28 |
| **ProfileCard** | Selectable story profile with thumbnail, line, readiness | radio group | ST29 |
| **ChapterCard** | Numbered chapter with thumbnail/duration, current state | | ST30, ST33 |
| **MetricFractionCard** | Fraction, label, provenance, ring | ring decorative | ST30 |
| **TreatmentChips** | Read-only treatment summary | not toggles | ST31 |
| **ComparisonStatCard** | Before → after fractions, percentages, percentage points, source | | ST32 |
| **JourneyTimeline** | Ordered lesson milestones with done/current shapes | | ST32 |
| **NoteRow** / **ChoiceRow** | Caption entry row; single-choice row with state | | ST33 |
| **NoteItem** / **ChecklistRow** | Numbered note with author/provenance; drill with target/done | adjustable | ST35 |
| **SourceBinCard**, **StoryBeatList**, **BeatCard**, **ClipInspector**, **StoryboardTimeline** | Storyboard pieces | timeline adjustable; beat list is the phone equivalent | ST36 |
| **QuoteCard** / **ConsentRow** | Quote, cap, expiry, sample label; explicit consent checkbox | 44 pt checkbox | ST37 |
| **StageProgressCard** | Current stage's real progress | "of this step" caption | ST38 |
| **DeliveryPanel** / **ShareLinkRow** | Verification summary; expiring link with refresh/revoke, no URL text | | ST39 |
| **IdentityCard** | Demo / Test / Connected identity with action | | ST40 |

Token additions: colour role `anchor` (clay #C47752 in both appearances, graphic ≥ 3:1 on `surface` and forest) for
sync anchors; `gapHatch` (separator at 60% with a 45° pattern) for no-coverage spans; `sourceTint1…6` (forest, clay,
ivory-outline, chartreuse-outline, forest-panel, clay-outline) always paired with a number tag. No new font families;
`Font.jovraTimecode` (core) covers all times.

---

## 5. Open questions

1. **Sound default (SD5 / D5).** The spec makes Sound an explicit, unchosen choice on every profile screen. Confirm,
   or allow "Natural court audio" as a default for Court Memories and Match Broadcast.
2. **Studio Home placement.** Push from a Home card (this spec) vs a sheet. Push keeps back navigation simple.
3. **"Use local replay" (ST37).** The brief's label routes to the local film path; "Make it on this iPhone" would be
   clearer. Kept as the brief says until Jon decides.
4. **Effects default.** Subtle per `story-profiles.json`, while the reference shows Medium. Confirm.
5. **Photography.** As in core: generated photos are concept art; Studio ships synthetic sample frames and the
   player's own frames.
6. **Coach shares before S4.** A private lesson export (Share Pack scoped to a lesson) is the v1 path; cloud coach
   grants arrive with S4.
