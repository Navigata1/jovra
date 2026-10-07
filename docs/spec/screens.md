# JOVRA screen specification (iOS v1)

Status: implementation-ready draft, 2026-10-07. Owner: spec author for the lead. Scope: the 20 reference screens,
their auxiliary sheets and states, the new surfaces the research backlog adds, and the design-system inventory they
need. Android gets its own spec after the iOS gates (D11); the Studio expansion (`design-reference/studio/`, screens
21–40) is out of this spec.

**Sources, in precedence order.** Lead decisions D1–D12 (binding) → `CLAUDE.md` hard rules → ADR-0001…0006 →
`design-reference/brief/screens.json` (exact copy) and `implementation-states.md` → `docs/research/*` (backlog IDs such
as P0-11 refer to `feature-backlog.md`; rules and stat definitions to `tennis-rules-and-stats.md`, cited as "Rules §x")
→ the PNG references (layout, rhythm, palette, hierarchy only). Where a reference image disagrees with any source
above it, the source wins and the difference is listed under "Deliberate differences" for that screen.

**Component names** are the foundation design system's (`ios/Jovra/DesignSystem/` in ticket #1): `JovraScreen`,
`JovraLockup`, `CourtArcMark`, `EditorialCard`, `.jovraCard()` (`CardSurface`), `StatTile`, `FilterPills`,
`ProvenanceBadge`, `StatusPill`, `SectionHeader`, `AvatarInitial`, `SettingsRow`, `SettingsChevron`,
`JovraButtonStyle` (`.jovraAccent`, `.jovraPrimary`, `.jovraSecondary`), `ComingLaterCard`, `CourtLinesBackdrop`,
`JovraTabBar`, `.jovraDisplayTitle()`, colour roles `Color.jovra(.role)`, `Space`, `Radius`, `HitTarget`, and the
`Font.jovra*` styles. Components that do not exist yet are written in **bold** the first time they appear in a section
and are defined in §5 (inventory).

**Domain names** (modules and derived values) follow §0.7. `GLOSSARY.md` and the domain-model spec own the final
names; if they differ, rename here, do not fork.

---

## 0. Conventions that apply to every screen

### 0.1 Navigation model and routes

The app has two roots: a **pre-shell** (Welcome and onboarding, shown until a profile exists or the demo is chosen)
and the **shell** (`AppShell`: five tabs, each with its own `NavigationStack`, plus full-screen routes that remove
the tab bar). Tabs: **Home · Sessions · Record · Insights · Profile** (`AppTab`, foundation order and symbols).

| Kind | Tab bar | How presented | Routes |
|---|---|---|---|
| Pre-shell | none | root view swap (cross-fade; no animation with Reduce Motion) | `welcome` (S01), `onboarding(step)` (S02) |
| Tab root | visible | `TabRoot` | Home (S03), Sessions = library (S08), Record = setup (S04), Insights = coaching plan (S15), Profile = Profile hub (N11) |
| Push | visible | `NavigationLink` in the tab's stack | Sessions → import (S07), match overview (S09), practice overview (S09 variant); Insights → shot map (S11), Serve Lab (S12), Stroke Lab (S13), progress (S16), drill detail (S15 aux); Profile → Racket Vault (S17), string journal (S18), storage (S19), settings (S20), Space Saver (N6), diagnostics (N5), recording rules (N4) |
| Full screen | hidden | `FullScreenRoute` via `AppRouter.present(_:)` | `capture(sessionDraft)` = framing (S05) → recording (S06) → saved; `replay(session, point?)` (S10); `compare(projectOrPair)` (S14); `pointReview(session, filter)` (N1); `highlightReel(session)` (N10); `drillSession(drill)` (S15 aux) |
| Sheet | unchanged | `.sheet` with detents; never a fake system dialog | every editor, picker and confirmation listed per screen |

`FullScreenRoute` grows from the foundation's single `capturePreview` case to: `capture`, `replay`, `compare`,
`pointReview`, `highlightReel`, `drillSession`. Each full-screen route has a visible Close (or Done) control at top
leading, ≥44 pt, labelled for VoiceOver ("Close replay"), and supports the system swipe-down only where no gesture
conflicts (never on S06 while recording; see S06).

Deep links and App Intents (P1-26) resolve to these routes: "Start singles recording" opens S04 preset to Singles
and immediately presents `capture` in framing (the camera never starts in the background); "Show last match" pushes
S09 for the newest match.

### 0.2 Copy rules

1. `screens.json` wins over pixels. Image-generation typos are fixed silently; changes of meaning are listed per
   screen.
2. Scoring labels: games are **"Ad"** or **"No-Ad"**; sets are **"Tie-break at 6–6"** or **"Advantage set"**. The bare
   word "Advantage" never appears as a format label (Rules §0.9). "Advantage" in prose headlines ("Your next
   advantage") is fine.
3. Rate changes are **percentage points**, written out ("+4 percentage points"); VoiceOver reads the same words.
   Deltas come from the two displayed integers (Rules §7 rule 4).
4. Every percentage comes from `pct(n, d)` on integer counts (Rules §7). `d = 0` shows "—" (VoiceOver: "no data").
   The fraction ("28 of 40") is always one tap away and is part of the VoiceOver value.
5. "Shots" means **racket contacts** (`strokeCount`, D4); rally length is a separate value. Wherever "Shots" appears,
   its definition is one tap away: "Shots: every racket contact in play, including the serve that started the
   point. Faults and lets are not counted."
6. Provenance words are only: **Manual**, **Estimated**, **Reviewed**, **Validated**, and **Sample** for demo data
   (`ProvenanceBadge`). Automatic results that need a decision say **"Needs review"**. Unbuilt or unvalidated
   capabilities say what is true ("Not available yet", "Off until it passes testing"), never a fake number.
7. Brand hygiene (hard rule 6): manufacturer and product names appear only as user-entered text. No third-party logos
   (including Google Drive's and Apple's beyond the system Sign in with Apple button), no generated photos that show
   a manufacturer mark.
8. Public contact (hard rule 7): only `hello@islanddevcrew.com`, as selectable text, never a `mailto:` link.
9. Dashes: score separators use an en dash with no spaces ("6–4"); metadata separators use " · ".
10. Sentence case for everything except the wordmark and letter-spaced kickers (`Font.jovraKicker`, rendered
    uppercase by the style, stored in sentence case so VoiceOver reads words, not letters).
11. All strings live in the String Catalog from day one (P1-24); no string is concatenated from fragments that
    would block translation. Numbers, dates, durations and units use `FormatStyle`s, except percentages (`pct`).

### 0.3 State vocabulary

Every screen section lists its states with these names. "Parent" states from `implementation-states.md` are folded
into the screen they belong to.

| State | Meaning | Default treatment |
|---|---|---|
| **Empty** | Nothing stored yet | **StateCard** with one primary action and, where useful, "Explore the sample" |
| **Loading** | Reading local data (normally <100 ms) | No spinner under 300 ms; then redacted placeholders (`.redacted(reason: .placeholder)`), never fake numbers |
| **Working** | A long task with real progress (import, analysis, upload, export) | Determinate progress with the stage name; indeterminate only when the API reports none |
| **Error** | A task failed | **StateCard** or inline **BannerView** stating what failed, what is still safe ("Your video is safe"), and Retry |
| **Offline** | No network | Only network features change (Drive); everything else is local and unaffected. Copy says what waits |
| **Permission denied** | Camera / microphone / Photos add-only / Drive authorization refused | Explain the consequence, offer "Open iOS Settings" (`UIApplication.openSettingsURLString`); never draw a fake system dialog |
| **Sample** | Demo data | `ProvenanceBadge(.sample)` on every block of sample numbers; sample media labelled "Sample video (synthetic)" (D8) |
| **Needs review** | Automatic or auto-filled result awaiting the player | `StatusPill(.attention)` "Needs review" + clay ring marker; counts in "Review completion" |
| **Estimated** | Value from an `estimated` capability or checkpoint auto-fill | `ProvenanceBadge(.estimated)` + range/denominator; tapping opens the capability detail (N12) |
| **Unsupported** | Capability `unsupported` or `disabled` in the registry, or the device lacks the hardware | The control is replaced by a short explanation; never hidden silently if the reference shows it |
| **Recalculated** | A correction changed derived values | **Toast** "Score and stats updated" + a "Recalculated" marker on changed tiles for the session's next view |
| **Provisional** | A point with outcome `unknown` precedes this value | Value shown with "Provisional" caption; the scoreboard after the unknown point is drawn with a dashed outline |

### 0.4 Accessibility baseline (hard rule 8; P0-21)

- Every control ≥44×44 pt (`HitTarget.minimum`); capture controls on S06 ≥64 pt because they are used at arm's length.
- Dynamic Type to AX5 without truncating controls: rows wrap, tile grids stack (`ViewThatFits` or
  `dynamicTypeSize.isAccessibilitySize` switches, as `FilterPills` already does), and nothing uses
  `minimumScaleFactor` below 0.7 for text other than the large metric numerals in `StatTile`.
- VoiceOver: one header per screen (the display title has `.isHeader`), section headers are headers, each card is one
  element with a full sentence label unless it contains several actions (then `.contain`). Reading order is listed per
  screen. Decorative imagery (`CourtLinesBackdrop`, hero art) is hidden.
- Meaning never by colour alone: markers use shape (circle In, triangle Out, ring Needs review, diamond Bookmark),
  statuses use symbol + text, selection uses fill + check/weight + the `.isSelected` trait.
- Reduce Motion: no scale/slide transitions; the swipe deck (N1) animates with cross-fades; charts draw without
  animation. Increase Contrast: colour roles already switch (`ColorRole.highContrastOverride`); video overlays gain a
  solid backing.
- Charts use Swift Charts with `accessibilityChartDescriptor` (Audio Graphs) and a "Show as table" alternative.
- Video surfaces expose an **adjustable** element: swipe up/down steps by point (timeline) or by frame (jog strip).
- UI tests run `performAccessibilityAudit(for:)` on every screen and state listed here (P0-21).

### 0.5 Size classes and orientation

- **Compact width, portrait** is the reference layout. Smallest supported width: 320 pt (iPhone SE/mini at Zoomed);
  content uses `Space.screenMargin` (20 pt) and never scrolls horizontally except deliberate carousels.
- **iPhone landscape** is required for S05, S06 (P0-04), S10, S14 and N1/N10; other screens simply reflow inside
  `JovraScreen` (max content width 720 pt, centred).
- **iPad (regular width)**: tab screens use `JovraScreen`'s 720 pt column; S09, S10, S14 and N1 use two columns
  (P1-23); keyboard shortcuts on video screens (space play/pause, ←/→ frame, ⇧←/⇧→ point, J/K/L rate). iPad camera
  capture is allowed but not a design target. Stage Manager / Split View: video screens must handle
  `videoDeviceNotAvailableWithMultipleForegroundApps` (S06).
- Appearance: light and dark both use colour roles; editorial cards and video chrome are always forest
  (`EditorialCard` forces dark). Screens marked "dark" in `screens.json` (S01, S05, S06) are forest in both appearances.

### 0.6 The sample fixture (what every sample number must equal)

The demo library ("Explore a demo", S01) is one coherent dataset. These are **test oracles**: the UI must show these
values because the engine computed them from the sample events, never because they were typed into a view.

| Value on screen | Equals | Computed from | Screens |
|---|---|---|---|
| 6–4 6–3, Jon wins | fold of the 124 sample point events (Rules §8.4 construction, Case A: Jon serves first, D4) | `ScoringEngine` | 3, 8, 9 |
| 124 points | count of completed points | `MatchStats.points` | 9 |
| 58% points won | `pct(72, 124)` | `MatchStats.totalPointsWon(Jon)` | 9 |
| 67% first serves (in) | `pct(40, 60)` | `MatchStats.firstServeIn(Jon)` | 3, 9, 12, 16 |
| 70% first-serve points won; "28 of 40" | `pct(28, 40)` | `MatchStats.firstServePointsWon(Jon)` | 9, 12, 15 |
| 386 shots | Σ `strokeCount` over 124 points | `MatchStats.shots` | 9 |
| 54 min | session video duration 54:00 (match 3,240 s, Rules C12) | `SessionDocument.duration` | 3, 7, 8, 9 |
| 8 flagged / 116 of 124 reviewed | 8 points with `needsReview`; `pct(116,124)` = 94% if a rate is shown | `ReviewState` | 9, 16 |
| Point 42 · 8 shots, Set 1 · Game 8, Alex serving, 4–3, Jon 30–15 | sample event 42 (Rules C15, state clauses) | fold + event | 6, 10 |
| Point 42 "12:46" ("REC 12:46", "12:46 / 54:00") | illustrative moment on the synthetic sample video's clock (D8), waived by D4; **not** the event time: sample event 42 starts at `tStartMs` 1,103,730 (18:23.7) and C15 is `partial` in `spec/fixtures/sample` | sample video clip metadata, never fold + event | 6, 10 |
| 8 sessions · 6h 42m on court | 8 sample sessions between Sep 9 and Oct 6, 2026; Σ durations = 402 min | `TrendPool` over the 4-week window | 3, 16 |
| First serves in by week: 48%, 55%, 63%, 67%; "+4 percentage points" | Jon's match first-serve-in pooled per week: 24/50, 33/60, 38/60, 40/60 (one singles match per week; week 4 = Jon vs Alex) | `TrendPool` | 3, 16 |
| Forehand placement 62% deep / 24% short / 14% out | 50 placed forehands: 31 / 12 / 7 (Rules §8.5) | manual placements | 11, 16 |
| Deuce first-serve placement 52% wide / 32% body / 16% T | 25 placed deuce first serves: 13 / 8 / 4 | manual placements | 12 |
| 104 mph fastest marked serve; "Review 12 serves" | 12 serves with marked contact/bounce in the **Serve practice · Oct 4** session; `estimated`; never derived from the match (Rules C16) | `ServeSpeedEstimator` | 12 |
| 6h 42m since restring | Σ durations of sessions linked to the Head Prestige string job dated Sep 9, 2026 (all 8) | `LoggedCourtTime` | 18 |
| Library: Jon vs Alex (Oct 6, 54 min), Serve practice (Oct 4, 22 min), Forehand session (Oct 2, 38 min) + 5 older sessions (288 min total; 3 singles matches in weeks 1–3, all reviewed, all backed up, no placements) | sample library | `SessionLibrary` | 8 |
| Archive: Jon vs Alex uploading 62%; Serve practice queued; Forehand session "Retry backup"; older five backed up | demo archive queue (fake Drive, D3) | `ArchiveQueue` | 7, 8, 19 |
| 12.4 GB used by JOVRA; 243.6 GB free; 256 GB capacity | demo device numbers, shown only in demo; real values are measured | `DeviceBudget` | 19 |
| Comparison clips "Oct 6" and "Sep 28" | serve clip from Jon vs Alex and from the week-3 match on Sep 28 | `CompareProject` | 14 |

The sample video is the synthetic render from D8 (perspective court, simple figures, physically plausible ball, hit
clicks). Every sample thumbnail is a frame of that video, not a photograph.

### 0.7 Domain modules and derived values referenced below

JovraCore (Foundation-only): `SessionLibrary` (index rebuilt from folders), `SessionDocument` (`session.json`),
`ScoringEngine` (pure fold, ADR-0003), `MatchState` (per-point derived score, server, side, flags), `MatchStats`
(Rules §6), `pct`, `ReviewState`, `Conflict` (Rules §4.4), `CheckpointSolver` (Rules §4.5), `CapabilityRegistry`
(ADR-0004), `TrendPool` (pooled cross-session aggregation, Rules §6.10), `PracticeRules` (deterministic suggestions),
`EquipmentStore` + `LoggedCourtTime`, `UnitPreferences` + `UnitConverter`, `StorageEstimator`, `ArchiveQueue` (state
machine, technical-feasibility §13), `ExportManifest`, `ConsentRecord`, `CompareProject`, `Annotation`.

JovraMedia / app adapters: `RecordingEngine` + `CaptureJournal`, `DeviceBudget` (free space, battery, Low Power,
thermal/system pressure), `PermissionsStatus`, `ImportPipeline`, `ReplayController` (seek/step/rate), `RallyComposition`
(rally-only `AVMutableComposition`), `ClipExporter`, `HighlightRenderer`, `AudioHitDetector` + `RallySegmenter`
(gated), `CourtCalibration` (4-tap homography), `PoseEstimator` (Vision 2D, on demand), `ServeSpeedEstimator`
(manual-assisted, D10), `DriveAuth` (OAuth 2.0 + PKCE via `ASWebAuthenticationSession`, D3) + `DriveClient`,
`DiagnosticsBundle`, `FixtureCamera` (simulator, D9).

---

## 1. The twenty reference screens

Each section uses the same headings: Purpose · Route · Layout (top to bottom) · Copy · Data bindings · States ·
Interactions · Accessibility · Landscape and iPad · Deliberate differences from the reference image. "Copy" lists
strings not already quoted in Layout.

---

### S01 Welcome (`welcome`, reference 01)

**Purpose.** First impression and the three ways in: start your own profile, optionally sign in with Apple, or look
around with sample data. States the ownership promise (P0-18) before anything else is asked.

**Route.** Pre-shell root, shown when no player profile exists and the demo has not been chosen. Full screen, no tab
bar, forest in both appearances. Never shown again once a profile exists (S02 handles edits).

**Layout.**
1. **CourtHeroArt** (upper ~55% of the height, full bleed under the status bar): vector court in perspective with net,
   warm low-sun gradient, a charcoal racket silhouette with chartreuse mains and ivory crosses, a plain ball.
   `JovraLockup` (ivory mark, chartreuse "TENNIS", chartreuse ball) centred in the top safe area, height 56.
2. Forest panel (`.editorial` role), content left-aligned on compact, centred on regular:
   - Headline "See your game." — display size, ivory (`.textOnEditorial`).
   - Subhead "Every point. Every detail. Your vision." — `Font.jovraSubtitle`, `.textOnEditorial`.
   - Promise line (`Font.jovraCaption`, `.textSecondaryOnEditorial`): "Your videos stay yours. No account needed, no
     hour limits, no ads."
   - "Get started" — `.jovraAccent`, full width.
   - "Continue with Apple" — system `SignInWithAppleButton(.continue)`, style `.white`, height 52, corner radius 26.
   - "Explore a demo" with trailing arrow — plain text button, `.textOnEditorial`, ≥44 pt tall.

**Data bindings.** None on screen. On "Continue with Apple": `ASAuthorizationAppleIDProvider` with scope `.fullName`
only (no email: nothing uses it); the user identifier is stored in Keychain; the given name pre-fills S02.

**States.**
| State | Treatment |
|---|---|
| First launch | As laid out |
| Sign in with Apple cancelled | No message; the screen stays as it was |
| Sign in with Apple failed / offline | Inline **BannerView** (attention) above the buttons: "Sign in with Apple didn't finish. You can continue without an account." The banner never blocks "Get started" |
| Returning user after reinstall (Apple credential found, no local data) | After sign-in, S02 opens pre-filled if a name is known; a one-time note on S03: "Your sessions live on each iPhone. Restore archived sessions from Google Drive in Profile › Storage." |
| Demo chosen | Shell opens on Home with sample data and the **DemoBanner** (see S03) |

**Interactions.** "Get started" → S02 at step 2 (step 1 "Account" shows as done, meaning "no account needed"). "Continue
with Apple" → system sheet → S02 step 2 with the name pre-filled. "Explore a demo" → shell with the sample library and a
sample profile "Jon" (labelled Sample); the profile is replaced when the user completes S02 later.

**Accessibility.** Order: lockup ("JOVRA Tennis", image), headline (header), subhead, promise, Get started, Continue
with Apple, Explore a demo. The hero art is hidden. Dynamic Type: the hero shrinks first (minimum 120 pt band at AX
sizes) and the panel scrolls; buttons wrap; the headline never truncates.

**Landscape and iPad.** iPhone landscape: hero art left 45%, panel right 55% (scrolls). iPad: full-bleed hero art with
the panel as a 520 pt wide forest card anchored bottom-centre.

**Deliberate differences from the reference image.**
- The photograph is replaced by vector **CourtHeroArt**: the generated photo is concept art with no usage clearance
  and puts the JV mark on a ball and racket throat (product marks we do not ship). Production photography is an open
  item for Jon (§6).
- The Apple button uses Apple's required system style (`.white`) instead of the drawn ivory outline.
- Added the ownership promise line (P0-18).

---

### S02 Player onboarding (`onboarding(step)`, reference 02)

**Purpose.** Capture the player facts every stat and filter depends on (handedness and backhand type are hard inputs
for stroke logic, P0-19), plus level, goals, name, units and usual format. Everything is optional and editable later.

**Route.** Pre-shell, after S01. Three steps on a **StepRail**: "1. Account" (done: no account needed, or Apple),
"2. Profile" (this layout), "3. Play" (defined below). Back swipes to the previous step. The same Profile form is
reused from Profile hub (N11) › "Player profile" as a pushed screen titled "Your player profile" with "Save".

**Layout — step 2 "Profile".**
1. `JovraLockup` (height 40, centred).
2. **StepRail**: three numbered nodes joined by a line; done = forest fill + check; current = chartreuse fill + number;
   upcoming = sunken fill + number. Labels under nodes.
3. Title "Make it your game" (`.jovraDisplayTitle()`), subtitle "Tell us a bit about your tennis game."
4. Row: `AvatarInitial` (size 96, the name's first letter; none → person symbol) + "Name" label + text field
   (placeholder "First name", `.textContentType(.givenName)`, submit = next field).
5. "Playing hand": **ChoiceSegment** with two options, each icon + text: "Right-handed" / "Left-handed".
6. "Backhand style": **ChoiceSegment** "One-handed backhand" / "Two-handed backhand" (stroke silhouettes mirror for
   left-handers).
7. "Skill level": `FilterPills` "Beginner" / "Club player" / "Competitive".
8. "Your goals (select up to 3)": **GoalChip** grid, two columns: "Serve consistency", "Win more matches", "Improve
   fitness", "Match strategy", "Play with better players", "Enjoy the game more".
9. Caption "Change these anytime."
10. "Continue" `.jovraPrimary` with trailing arrow, in a bottom safe-area inset so it is always reachable.

**Layout — step 3 "Play".** Title "How you play", subtitle "Two quick choices, then you're on court."
- "Usually play": `FilterPills` "Singles" / "Doubles" / "Both" (sets the S04 default mode).
- "Units": `FilterPills` "mph · lb" / "km/h · kg" (default from the device's measurement system).
- **InfoCard** "How JOVRA records", three rows with symbols: "Video is saved on this iPhone first." / "We ask for the
  camera when you first record." / "The microphone is optional. We'll explain before asking."
- "Record your first session" `.jovraAccent` → shell, Record tab (S04). "Look around first" `.jovraSecondary` → shell,
  Home. Text link "Explore the sample" → shell with sample data added alongside (labelled Sample).

**Data bindings.** `Player(self)`: `name`, `handedness ∈ {right, left, unset}`, `backhand ∈ {oneHanded, twoHanded,
unset}`, `level`, `goals` (≤3, ordered), `usualFormat`; `UnitPreferences`. Goals only reorder `PracticeRules` output
(S15); they never change a stat.

**States.**
| State | Treatment |
|---|---|
| Nothing chosen | Valid. No option is preselected; "Continue" is always enabled. Unset handedness shows "Not set" in Profile and Stroke Lab asks before mirroring |
| Fourth goal tapped | The tap is refused, a caption appears under the grid and is announced: "Up to 3 goals. Deselect one to choose another." |
| Name empty | Greeting on S03 becomes "Good morning." |
| Edit mode (from Profile) | Title "Your player profile", no StepRail, button "Save"; changing handedness shows "Forehand and backhand filters will update for all sessions." |
| Demo profile | Fields pre-filled with the sample "Jon" and a Sample badge next to the title |

**Accessibility.** Order: lockup, step rail ("Step 2 of 3, Profile"), title, subtitle, name field, each group (group
label is the header: "Playing hand"), goals, caption, Continue. ChoiceSegment options are buttons with `.isSelected`
and "1 of 2" position hints; GoalChips are toggle buttons ("Serve consistency, selected"). Dynamic Type: ChoiceSegment
and FilterPills stack vertically at accessibility sizes; GoalChip grid becomes one column; avatar shrinks to 64.

**Landscape and iPad.** One scrolling column, max width 560 pt, centred.

**Deliberate differences from the reference image.**
- The avatar shows the initial on the forest fill, not a court photograph (no photo access is requested for a profile).
- Nothing is preselected (the reference preselects; defaults would silently mislabel left-handers).
- Step 3 "Play" is specified here (the reference only names it).

---

### S03 Home (`AppTab.home`, reference 03)

**Purpose.** The next action (record), the latest session, three honest headline numbers and one trend. Safe recording
entry is always one tap away.

**Route.** Home tab root. Tab bar visible.

**Layout.**
1. Header row: `JovraLockup` (40) leading; `AvatarInitial` (52) trailing → Profile tab.
2. Optional **DemoBanner** (demo mode only): "You're exploring sample data." + "Make it yours" (→ S02).
3. Optional **BannerView** (positive) when a recording was recovered at launch: "Recovered 41:12 of your Oct 6
   recording." + "Review" (→ S09/S10 of that session).
4. Title: greeting "Good morning, Jon." (05:00–11:59 morning, 12:00–17:59 afternoon, otherwise evening; no name →
   "Good morning."), subtitle "Your game, in focus."
5. `EditorialCard`: "Ready for your next session?" (`Font.jovraEditorial`), "Record a session" `.jovraAccent` with
   trailing arrow, kicker "A better game tomorrow" (dropped when it would crowd the button, as the foundation does).
6. Three `StatTile`s in a row, each with symbol and a new **scope** caption: "8" / "Sessions" / "Last 4 weeks";
   "6h 42m" / "On court" / "Last 4 weeks"; "67%" / "First serves in" / "Latest match". `ProvenanceBadge(.sample)` on
   each in demo.
7. `SectionHeader` "Latest session" with trailing "View all" + chevron.
8. **SessionCard** (compact): thumbnail (poster frame), "Jon vs Alex", score "6–4 6–3" (`Font.jovraHeadline`,
   monospaced digits), "54 min · Singles", chevron. Status line only if something needs attention ("Needs review · 8
   points", "Backing up · 62%").
9. `SectionHeader` "Last 4 weeks" with trailing `ProvenanceBadge(.sample)` in demo.
10. **TrendCard**: label "First serves in", value "67%", delta "+4 percentage points" with an up arrow and the words
    "vs last week", **TrendChart** of weekly pooled values W1–W4 (points with markers, y axis 0–100 with 3 gridlines,
    x labels "Wk 1"… "Wk 4" or dates at larger widths).

**Copy.** Empty-state and banner strings are in States.

**Data bindings.**
| Element | Fixture | Source | Provenance |
|---|---|---|---|
| Sessions | 8 | `TrendPool.sessionCount(window: 28 days)` | Sample in demo; otherwise none (a count is not a measurement) |
| On court | 6h 42m | Σ `SessionDocument.duration` in window, `DurationLabel` format | as above |
| First serves in | 67% (40/60) | `MatchStats.firstServeIn(self)` of the newest singles or doubles match | `Manual` or `Reviewed` per the match's points (badge shown in the fraction popover; tile shows Sample in demo) |
| Latest session | Jon vs Alex 6–4 6–3, 54 min · Singles | newest `SessionDocument` + `ScoringEngine` final state | — |
| Trend | 48, 55, 63, 67; +4 | `TrendPool.weekly(firstServeIn, sessionType: same as latest match)`; delta from displayed integers | per-point provenance mix; "Includes estimated points" caption if any auto-filled point is unreviewed |

**States.**
| State | Treatment |
|---|---|
| Empty (no sessions) | Tiles, latest session and trend are replaced by one **StateCard**: "Your first session shows up here." / "Record a match or practice, or import a video you already have." Actions: "Import a video" (→ S07), "Explore the sample" |
| One session only | Tiles show; TrendCard says "Play matches in two different weeks to see a trend." |
| No match yet (practice only) | First-serves tile shows "—" and scope "No match yet" |
| Latest session working | SessionCard status line: "Preparing replay…" / "Analyzing · 62%" / "Backing up · 62%" |
| Needs review | SessionCard status "Needs review · 8 points" (clay ring symbol) and a **NextStepRow** under it: "Review 8 flagged points" (→ N1) |
| Sample | Badges as above; DemoBanner |
| Recovered recording | Banner as in Layout 3 |

**Interactions.** Record a session → selects the Record tab (S04). Tiles → S16 with that metric. Latest session → S09
pushed on the Sessions tab (tab switches). View all → Sessions tab. TrendCard → S16. Long-press SessionCard → context
menu (Watch, Review points, Share pack, Show in library).

**Accessibility.** Order: lockup, Profile button ("Profile, Jon"), banners, greeting (header), subtitle, editorial card
(header text + button), tiles ("8 sessions, last 4 weeks"; "6 hours 42 minutes on court, last 4 weeks"; "67 percent
first serves in, 40 of 60, latest match, sample data"), Latest session header, card ("Jon versus Alex, Jon won 6–4,
6–3, 54 minutes, singles, October 6"), trend header, TrendCard (value and delta, then the chart as an Audio Graph).
Dynamic Type: tiles stack at accessibility sizes (foundation behaviour); the chart keeps a 160 pt minimum height and
labels thin to first/last.

**Landscape and iPad.** Same single column (720 pt max). iPad: tiles stay in one row at all sizes up to AX2.

**Deliberate differences from the reference image.**
- "This week" daily chart (Mon–Sun) becomes a "Last 4 weeks" weekly chart: the reference chart is a composition
  sketch (implementation-states.md) and daily first-serve percentages would rarely have data.
- "+4 pts" becomes "+4 percentage points vs last week".
- Tiles gain scope captions so the three numbers' windows are explicit.
- The header avatar shows the player's initial, not the brand mark. The hero photo becomes `CourtLinesBackdrop`
  (foundation) and the latest-session thumbnail is a frame of the session's own video.

---

### S04 Session setup (`AppTab.record`, reference 04)

**Purpose.** Choose what you are recording and make the few decisions that change recording or scoring, with a
computed storage and battery budget before the first serve.

**Route.** Record tab root (Home's "Record a session" selects this tab). Tab bar visible. The primary action presents
`capture` full screen (S05).

**Layout.**
1. `JovraLockup` (40) leading. No back chevron (tab root).
2. Title "Set up your session", subtitle "Choose a mode and configure your recording settings."
3. Four **ModeRow**s (radio group): illustration (**ModeArt**, vector), symbol, title, description, radio. Selected =
   forest fill with ivory text and a chartreuse radio dot (`EditorialCard` colours); unselected = `.jovraCard()`.
   - "Singles match" — "One vs one. Record the full match and keep score."
   - "Doubles match" — "Two vs two. Keep score with serving and receiving order."
   - "Serve practice" — "Focus on your serve. Log placement and consistency, and estimate speed from marked frames."
   - "Stroke practice" — "Record groundstrokes, volleys and overheads."
4. **SetupRow** list (symbol, small label, value, optional detail line, chevron), in one `.jovraCard()` group:
   - "Players" — "Jon · Alex"; detail "Right-handed · Left-handed". Practice modes: "Jon".
   - "Scoring" (match modes) — "Best of 3 · Ad · Tie-break at 6–6".
   - "Live scoring" (match modes) — "Every point" / "Changeover scores only" (N2) / "Score later".
   - "Gear" — "Head Prestige · Hyper-G / Ghost Wire" (active racket and its current string job) or "Add your racket"
     (optional).
   - "Camera" — "1080p · 60 fps · Ultra-wide"; detail "Estimated space: 4.6–6.5 GB for 1 h · 231 GB free".
   - "Microphone" — "Ask when recording starts" / "On · Used to find rallies" / "Off · Video records without sound".
   - "Recording consent" (N4) — "Not set" / "Everyone on court agreed" / "Written consent attached" / "Recording
     only me".
   - "Camera position" — "Fence" / "Tripod" (changes framing guidance on S05).
   - Practice modes only: "Camera angle" — "Side-on (technique)" / "Behind the baseline".
5. Competition mode toggle row (match modes): "Competition mode" / "No live suggestions. Follow your event's
   rules." (N4).
6. **PreflightStrip** (N8, compact): three chips "Storage ready", "Battery 78%", "Phone cool" — each tappable for detail.
7. Bottom inset: "Check camera position" `.jovraPrimary` with trailing chevron; under it a text link "Import a
   recording instead" (→ S07 on the Sessions tab).

**Data bindings.**
| Element | Source | Notes |
|---|---|---|
| Players, handedness | `Player` records (self + recent opponents) | opponent handedness is P0-19 |
| Scoring | `FormatPreset` + overrides | label generator per §0.2 rule 2 |
| Gear | `EquipmentStore.activeRacket`, `currentStringJob` | association saved into `SessionDocument.equipment` at record start |
| Camera | supported `AVCaptureDevice.Format`s of the physical ultra-wide (else wide) camera, `FrameRate` | only formats the device supports are listed |
| Estimated space | `StorageEstimator.range(preset, plannedLength)`: low = 0.85 × bitrate × length, high = 1.2 × bitrate × length; bitrate from the measured MB/min of this device's previous recordings at that preset, else the documented table (technical-feasibility §1) | always a range; never a constant |
| Free space | `DeviceBudget.freeBytes` (`volumeAvailableCapacityForImportantUsageKey`) | |
| Microphone | `PermissionsStatus.microphone` + preference | D5 |
| Pre-flight | `DeviceBudget` battery level/state, Low Power Mode, `ProcessInfo.thermalState` | N8 |

**Auxiliary sheets** (implementation-states "Setup").
- **Players sheet**: me (fixed) + opponent picker (recent players, "New player": name, handedness, backhand). Doubles:
  two teams of two ("Your team", "Opponents"), each player with handedness. "Who serves first?" — a player, or "Decide
  on court" (then S06 asks before the first point). Doubles serving and receiving order is asked at the start of each
  set on S06 (Rules §2.4), not here.
- **Format sheet**: preset list with one-line plain descriptions — "Best of 3 · Ad · Tie-break at 6–6" (default),
  "Best of 3 · Ad · 10-point match tie-break for the third set", "Best of 3 · No-Ad · 10-point match tie-break",
  "Best of 5 · Ad · 10-point tie-break at 6–6 in the fifth", "Pro set to 8 · Tie-break at 8–8", "Short sets to 4 ·
  No-Ad", "Tie-break only (to 7 / to 10)", "Practice set (no match end)". Then overrides: games Ad / No-Ad; sets
  "Tie-break at 6–6" / "Advantage set"; lets on/off. Fast4 is not listed until its rules are confirmed (Rules §1.4).
- **Racket sheet**: rackets with current string job; "None"; "Add a racket" (→ S17 form).
- **Camera sheet**: supported presets with "MB per minute" and "about N h M min fits"; lens (Ultra-wide recommended,
  Wide); "Planned length" stepper 15 min–3 h (default 1 h for matches, 30 min for practice); "Space Saver practice
  preset: 1080p · 30 fps" (N6). Unsupported formats are not shown at all.
- **Consent sheet**: N4.

**States.**
| State | Treatment |
|---|---|
| First visit | Singles match preselected only if "Usually play" is Singles/Both; Doubles if Doubles |
| Not enough space | Camera row detail turns attention ink with symbol: "Not enough space for 1 h. About 38 min fits." + BannerView with "Use 1080p · 30 fps (about 1 h 05 min)" and "Manage storage" (→ N6). Recording is still allowed; S06 warns before space runs out |
| No racket | Gear row "Add your racket · Optional" (neutral, never attention) |
| Camera access denied earlier | PreflightStrip chip "Camera off" (attention) → explanation + "Open iOS Settings"; the primary button still opens S05, which shows the denied state |
| No ultra-wide lens | Camera row detail "This iPhone has no ultra-wide lens. Stand further back to fit the court." |
| Simulator | Camera row value "Simulator fixture camera" with a **FixtureBadge** (D9) |
| Practice mode | Scoring, Live scoring, Competition rows hidden; Camera angle row shown |
| Junior / parent mode on | Consent row shows attention until set; primary button asks to set consent first (can be overridden only for "Recording only me") |
| Sample (demo) | Rows show the sample players and gear; Sample badge beside the title |

**Interactions.** Tapping a ModeRow selects it (haptic selection feedback). Rows open their sheets. "Check camera
position" stores a `SessionDraft` and presents `capture` (S05). The draft survives app relaunch until recording starts
or the user changes mode.

**Accessibility.** ModeRows form a radio group ("Singles match, One vs one. Record the full match and keep score.
Selected. 1 of 4"). SetupRows read label + value + detail ("Camera, 1080p, 60 frames per second, ultra-wide. Estimated
space 4.6 to 6.5 gigabytes for 1 hour, 231 gigabytes free"). Order: title, modes, rows, competition toggle, pre-flight,
primary button, import link. Dynamic Type: ModeArt hides at accessibility sizes; row values wrap under labels.

**Landscape and iPad.** Width ≥ 700 pt: two columns (modes left, rows + pre-flight right), button spans both. Narrower
landscape: single column.

**Deliberate differences from the reference image.**
- "Best of 3 · Advantage" → "Best of 3 · Ad · Tie-break at 6–6" (Rules §0.9).
- "Estimated space: 3.2 GB" → computed range with planned length and free space (implementation-states.md).
- Mode descriptions no longer promise "analysis", "tactics" or measured speed (D10: speed is a manual-assisted estimate).
- Photos in mode rows → vector **ModeArt**; back chevron removed (tab root).
- Added rows: Live scoring, Microphone (D5), Recording consent (P1-10), Camera position, Competition mode, pre-flight.
- The reference's Record tab glyph (a video camera) stays the foundation's chartreuse "+" for consistency with the
  other 19 references.

---

### S05 Court framing and calibration (`capture` phase `framing`, reference 05)

**Purpose.** Get the phone in a position that records the whole court, tell the player exactly what to move, confirm
storage/battery/heat, and optionally mark the four court corners (manual calibration) so placement and speed tools
work later. Calibration never blocks recording: it can be done afterwards on the footage.

**Route.** Full-screen `capture` route, phase `framing`. Tab bar hidden. Forest chrome over the live preview in both
appearances. Close (top leading, "Close camera") returns to S04 with the draft kept. Camera permission is requested
here, on entry, and nowhere earlier.

**Layout (portrait).**
1. Live preview, full bleed (`AVCaptureVideoPreviewLayer`, `.resizeAspect` so the recorded frame is exactly what is
   shown; letterbox bars are forest).
2. Top bar over a **VideoScrim** gradient: Close button; small `JovraLockup` (28, ivory); trailing **FormatPill**
   "1080p · 60 fps" with a chevron (menu of supported formats; changing it re-checks storage).
3. Title "Frame your court" (ivory, `Font.title.bold`), subtitle "Position behind the baseline and align the court in
   the frame."
4. **PerspectiveCourtGuide** overlay: four chartreuse **CornerHandle** brackets on the doubles-court corners. Before
   the player marks anything, the handles sit at a default quadrilateral for the chosen camera position; dragging a
   handle shows a 2× **Loupe** above the finger. When all four are placed, the guide draws the full court model
   (singles and doubles sidelines, service lines, centre service line only between the service lines, centre marks,
   net) projected through the homography, in ivory at 70% opacity, so the player can see whether it matches.
5. Bottom sheet (**GuidanceSheet**, forest, opaque, grabber; collapsible to a single status line):
   - Status headline with symbol, from the guidance rules below. Ready state: chartreuse check disc + "All four
     corners visible" / "Keep the phone steady and the net centered."
   - **ChecklistRow** of three items: "Court visible", "Lighting good", "Storage ready" — each a symbol + text; failing
     items switch to an attention symbol and different text ("Corners not marked", "Lighting low", "Storage low").
   - Second row (N8): "Battery 78%", "Phone cool" — shown when not nominal or on tap of "More checks".
   - "Start recording" `.jovraAccent`, full width, with trailing arrow.
   - Text button "Skip corners · Mark them later" (only while corners are not placed).

**Guidance rules** (headline/subline pairs; first failing rule wins; all are from measured values, never from
pretend court detection):
| Condition (measured) | Headline / subline |
|---|---|
| Corners not placed | "Mark the four court corners" / "Drag each bracket onto a corner of the doubles court, or skip and mark them later." |
| A handle within 2% of the frame edge or outside it | "Move back or zoom out" / "The [near left] corner is at the edge of the frame." |
| Projected net line not between 30% and 60% of frame height | "Raise the phone" / "Raise it about 30 cm so the far service line is above the net." (direction flips when too high) |
| Court centre more than 10% off frame centre | "Turn the phone [left/right]" / "Centre the net in the frame." |
| Device tilt (CoreMotion gravity) changes >1° in 2 s | "Hold still" / "Keep the phone steady while you check the frame." |
| Mean scene luminance below threshold (exposure duration/ISO at limit) | "Lighting is low" / "Recording works. Finding rallies may miss shots." (still allows Start) |
| All pass | "All four corners visible" / "Keep the phone steady and the net centered." |

The 30% / 60% / 10% thresholds are starting values to tune in the hardware phase; they live in one place
(`FramingGuidance`), not in views.

**Data bindings.** `CourtCalibration` (4 image points in video pixels, from `captureDevicePointConverted(fromLayerPoint:)`
and the rotation; homography with the RMSE self-check of technical-feasibility §8), `DeviceBudget` (free space vs
`StorageEstimator.high`, battery, thermal), `PermissionsStatus.camera`, active format. Calibration is stored with
lens, format and zoom; status `manual` in the registry.

**States** (implementation-states "Calibration").
| State | Treatment |
|---|---|
| Camera not yet asked | On entry the system prompt appears over a forest placeholder with the explanation "JOVRA needs the camera to record your session. Video stays on this iPhone." Nothing custom imitates the prompt |
| Camera denied / restricted | Preview replaced by **StateCard** (dark): "Camera access is off" / "Turn on Camera for JOVRA in iOS Settings to record. You can still import videos you already have." Actions: "Open iOS Settings", "Import a video". Restricted (Screen Time/MDM) omits the Settings button and says "Camera access is restricted on this iPhone." |
| Microphone, first capture (D5) | After camera access, a one-time **MicExplainerSheet**: "Use the microphone?" / "Sound helps JOVRA find rallies after you record. Video records either way, and shared clips leave sound out unless you include it." Buttons "Allow microphone" (→ system prompt) and "Record without sound". Never shown again; changeable in S20 |
| Simulator / no camera (D9) | Preview streams the fixture video through the same pipeline; a **FixtureBadge** "Simulator fixture camera" sits under the format pill; the guide defaults to the fixture's true corners so UI tests are deterministic |
| Corners unclear | Handles placed but the projected untapped lines miss the visible lines (RMSE check fails, only when line pixels are measurable) → "Check the corners" / "The court lines don't match. Drag the brackets onto the outer corners." |
| Unsuitable angle | Quadrilateral nearly degenerate (far baseline shorter than 15% of near baseline, or near corners above far corners) → "This angle won't show the whole court" / "Record from behind the baseline, as high as you can." Start remains enabled |
| Low light | Checklist "Lighting low"; headline per the rule table |
| Low storage | "Storage low" chip; headline "About 38 min of space" / "Choose 1080p · 30 fps or free up space." with actions "Change format" and "Manage storage" |
| Low battery (<20%, not charging) | "Battery 18%" attention chip: "About 50 min at this rate. Plug in if you can." (rate from `DeviceBudget`) |
| Thermal fair/serious at start | "Phone warm" chip: "Recording works. JOVRA will turn the preview off if it gets hotter." (N9) |
| Format unsupported after change | The pill reverts and shows "Not supported on this iPhone" |
| Camera interrupted (another app, call) | Preview dims with "Camera paused by [a call / another app]. It resumes when you're back." |

**Interactions.** Drag handles (snap-to-edge never automatic; P1-17 auto-snap is `disabled`). Double-tap a handle to
reset it. "Start recording" begins recording immediately (no countdown by default; optional 3-second countdown in S20),
locks focus/exposure/white balance and the rotation angle, and transitions in place to S06 (no navigation animation;
the preview never restarts). "Skip corners" hides the guide and marks calibration "not set" — S11/S12 then offer
"Mark corners on the recording".

**Accessibility.** Order: Close, format pill, title, subtitle, status headline and subline, checklist items (each
"Court visible, passed"), Start recording, Skip corners. Each CornerHandle is an adjustable element ("Near left corner
bracket. Swipe up or down to move vertically, use the rotor for horizontal") with a custom action "Place at default".
VoiceOver announces guidance changes (`.announcement`, debounced to one per 3 s). Haptic and optional spoken cues for
"All four corners visible" (P0-05) so the player can set up without looking.

**Landscape and iPad.** Landscape is the recommended capture orientation (full court needs a 16:9 frame from behind
the baseline): the preview fills the screen and the GuidanceSheet becomes a trailing panel 320 pt wide (forest,
opaque); title and pill stay top leading/trailing. In portrait, a one-line tip under the title reads "Tip: turn the
phone sideways to fit the whole court." iPad: same as landscape, panel 360 pt.

**Deliberate differences from the reference image.**
- The reference implies automatic court detection ("All four corners visible" appears by itself). v1 has no validated
  court detector, so the player places the corners (or skips) and the check reports what was measured.
- The checklist adds battery and heat (N8); landscape is the primary layout (P0-04).
- The court in the reference shows a centre service line running into the backcourt and mis-scaled alleys; the guide
  draws ITF geometry (technical-feasibility §8).
- The JV mark on the windscreen is part of the generated photo, not an app element.

---

### S06 Live capture (`capture` phase `recording`, reference 06)

**Purpose.** Record the session reliably and make its safety visible from the baseline: REC and elapsed time, "saved n
s ago", the manual score, Mark point, pause and stop, and honest heat/battery/storage warnings.

**Route.** Same full-screen `capture` route, phase `recording`. Tab bar hidden. Swipe-to-dismiss is disabled; Close is
replaced by Stop. The idle timer is disabled only while recording. The screen stays in the orientation locked at
record start.

**Layout (portrait; landscape below).**
1. Live preview, full bleed (or court mode, N9).
2. Top row over VideoScrim: **RecordingStatusPill** "● REC 12:46" (red dot + text, timer `Text(timerInterval:)` style
   with monospaced digits); small `JovraLockup` (28); **BatteryPill** "78%" (+ bolt when charging, + Low Power symbol).
3. **ScoreboardOverlay** (ivory card, top leading): rows "Jon 4 30" / "Alex 3 15" — name, games in the current set,
   points; the server's row shows a small ball symbol; the most recent point's winner cell is highlighted chartreuse
   with a bold weight (not colour alone). Footer: calendar-checkmark symbol + "Manual score". In tie-breaks the points
   column shows tie-break points and a "Tie-break" caption. Completed sets appear as small columns before the current
   games when space allows.
4. Bottom control panel (forest, opaque):
   - **SaveHeartbeatLabel**: check symbol + "Video saved on this iPhone · 2 s ago" (updates from the journal heartbeat;
     "Saved through 12:44" in VoiceOver).
   - **HeatBanner** (only when the ladder is above nominal): attention symbol + text per N9, chevron → detail sheet.
   - **ScorePad** row (when Live scoring is "Every point"): two equal buttons "Point Jon" / "Point Alex" (≥64 pt tall)
     and an "Undo" button (≥44 pt) with the last action in its label ("Undo point to Alex"). Hidden for practice modes
     and "Score later"; "Changeover scores only" shows the checkpoint prompt instead (N2).
   - **CaptureControlButton** ×3: "Mark point" (bookmark symbol, ring, label under), Stop (red disc, 76 pt, white
     square, label hidden visually but read as "Stop recording"), "Pause" (pause symbol, ring, label under; becomes
     "Resume").
   - Overflow "•••" (top trailing of the panel): "Court mode", "Add a note to the last mark", "Delete this recording"
     (N4), "Recording help".

**Data bindings.**
| Element | Source |
|---|---|
| REC timer | `RecordingEngine.recordedDuration` over all segments (gaps excluded) |
| Saved n s ago | `CaptureJournal.lastDurableFragment` (fragment interval ≈2 s, P0-01) |
| Battery | `UIDevice.batteryLevel/State`, `isLowPowerModeEnabled` |
| Scoreboard | `ScoringEngine.fold(liveEvents)` → `MatchState` at the live edge; provenance `manual` |
| Undo | `Void(lastEvent)` + refold (Rules §4.3) |
| Mark point | `Bookmark(t)` mapped to media time from the recording start PTS (technical-feasibility §1 timing) |
| Heat / storage / battery warnings | `DeviceBudget` (system pressure, thermal state, free bytes slope, battery slope) |

**States** (implementation-states "Recording").
| State | Treatment |
|---|---|
| Recording | As laid out; light haptic on start |
| First point not yet assigned a server ("Decide on court") | ScorePad replaced by "Who serves first?" two buttons; recording already running |
| Paused (iOS 18 `pauseRecording`, D1) | Pill turns "❙❙ Paused 12:46" (no red dot), a full-width banner "Paused · Not recording" in the panel, Pause becomes "Resume". Stop still available |
| Stop confirmation | Sheet: "Stop recording?" / "Your video is saved on this iPhone." Buttons "Stop and review" (primary) and "Keep recording". Hands-free inputs never stop |
| Interruption (call, Siri, alarm, another camera app, side button, Split View) | Segment closes; on return a sheet: "Recording stopped at 41:12" / "A [phone call] interrupted the camera. Everything up to 41:12 is saved." Buttons "Resume recording" (new segment) and "Finish session". The gap is recorded |
| Relaunch after crash / jetsam / power loss | On next launch (Home banner, S03) recovery decodes to the end and reports the saved length; never claims more than decoded |
| Thermal ladder | N9: fair → "Phone warming · Recording safe"; serious → court mode + "Phone hot · Preview off to keep recording"; critical → "Phone hot · Recording at 30 fps"; shutdown → segment saved, interruption sheet with "Your phone got too hot. Everything up to mm:ss is saved." |
| Low battery | ≤20%: HeatBanner slot shows "Battery 18% · about 25 min left" (rate-based, shown as "about"); ≤5%: "Battery 4% · JOVRA will save and stop at 2%" and the engine finalizes at 2% |
| Low storage | When projected space < 15 min: "Space for about 12 min"; < 3 min: engine finalizes cleanly before `minFreeDiskSpaceLimit` and says "Storage full. Everything up to mm:ss is saved." |
| Microphone off/denied | Small chip in the top row "No sound" (mic.slash symbol); no other change |
| Mark point | Bookmark symbol pulses (cross-fade with Reduce Motion), success haptic, toast "Point marked · 12:46" with "Add note"; hands-free marks (P1-12) play a tone and say "Marked by volume button" |
| Bookmark note | Sheet with a text field and quick chips ("Great point", "Check this", "Line call"); never pauses recording |
| Score undo | Toast "Undid point to Alex · Score 4–3, 30–15" |
| Competition mode | ScoreboardOverlay shows only the score; no suggestions or prompts beyond checkpoints |
| Simulator fixture camera | FixtureBadge in the top row; all states reachable by debug controls in UI tests |

**Interactions.** Point buttons append `PointOutcome(winner, endType: unknown)` with the bookmark time. Mark point
creates a bookmark (used for rally-only playback and Fast Point Review). Stop → confirmation → finalize → S09 for the
new session with S07-style stage rows at the top ("Saved locally", "Preparing replay"). Hardware buttons (P1-12) map to
Mark point only.

**Accessibility.** Order: REC status ("Recording, 12 minutes 46 seconds"), battery, scoreboard ("Jon 4 games, 30.
Alex 3 games, 15. Alex serving. Manual score"), save status, warnings, Point Jon, Point Alex, Undo, Mark point, Stop
recording, Pause, More. Stop is not the first focused element after layout changes (focus lands on the scoreboard).
Score changes are announced. Dynamic Type: the panel grows upward; capture buttons keep their size; labels limited to
`.accessibility2` with Large Content Viewer beyond.

**Landscape and iPad.** Landscape (primary): preview full screen; ScoreboardOverlay top leading; RecordingStatusPill
and BatteryPill top trailing; a trailing vertical control rail (forest, 112 pt) holds Mark point, Stop (centre),
Pause; ScorePad sits as a translucent-free forest strip along the bottom leading half; status/warnings in a single line
above it. Controls are reachable with the thumb from the trailing edge. iPad: same as landscape.

**Deliberate differences from the reference image.**
- "Phone warming · Analysis paused" becomes "Phone warming · Recording safe": v1 runs no analysis on court, so there is
  nothing to pause; the heat ladder text says what actually changes (N9).
- "Video saved on this iPhone" gains a live age ("· 2 s ago") so safety is verifiable (P0-03).
- A ScorePad and Undo are added (the reference has no way to enter the "Manual score" it shows), plus a server
  indicator; "Delete this recording" for withdrawn consent lives in the overflow menu (P1-10).
- Landscape is the primary layout (P0-04).

---

### S07 Import and processing (`Sessions` push, reference 07)

**Purpose.** Bring existing footage in from Photos or Files (Google Drive is reachable through Files), save it locally
first, and show the independent stages — saved, replay ready, rally finding, backup — so the player knows the video is
safe even while other stages run or fail.

**Route.** Pushed on the Sessions stack from S08's "+ Import" (also from S04's link, S03's empty state and the Record
tab's "Import a recording instead", which switch to Sessions first). Tab bar visible. Also shown as the header of S09
right after recording stops (stage rows only).

**Layout.**
1. `JovraLockup` (40); title "Bring your game in", subtitle "Import your footage. JOVRA keeps the original safe."
2. Three **SourceTile**s (selectable card, symbol, title, subtitle): "Photos" / "Videos from your library"; "Files" /
   "From your iPhone or cloud drives"; "Google Drive" / "Through the Files app". Tapping a tile opens the picker
   immediately (the selected-state ring is shown only while that picker's import is active).
3. `SectionHeader` "Selected video" → **ImportItemCard**: poster frame with play glyph and duration "54:00"; title
   (editable, defaults to the file's creation date "Oct 6, 2026"), "54 min · 1080p · 60 fps", date, and "Sample
   session" + Sample badge in demo. Multiple selections show a list of compact cards.
4. `SectionHeader` "Processing" → **StageTimeline** (vertical, each stage: state symbol, title, one-line detail, value):
   - "Saved locally" / "Video copied to this iPhone" / "100%".
   - "Preparing replay" / "Reading frames and sound for smooth scrubbing" / "100%".
   - "Finding rallies" / detail per capability status (below) / "62%".
   - "Backing up" / "Queued for your Google Drive archive" / "—".
5. **InfoCard** (positive, shield-check symbol): "Recording is safe." / "You can leave this screen." On iOS 18–25 the
   detail reads "You can leave this screen. Finding rallies pauses while JOVRA is closed and continues when you
   return." (`BGContinuedProcessingTask` is iOS 26 only.)
6. "View session" `.jovraPrimary` with arrow; "Pause analysis" `.jovraSecondary` (becomes "Resume analysis").
7. Footer status row (two halves, each symbol + two lines): "Wi-Fi only" / "Backup waits for Wi-Fi" (only when that
   setting is on), and in demo: "Demo processing state" / "Analysis takes a few minutes".
8. Choice row under the buttons (gap-finder #6): "Find rallies: Now · When charging".

**Stage detail by capability status** (`CapabilityRegistry.rallySegmentation`):
| Registry status | Stage row |
|---|---|
| `estimated` (gate passed) | "Finding rallies" / "Listening for racket hits · results need your review" / percent |
| `disabled` (gate not passed; initial) | "Finding rallies" / "Off until it passes testing. Mark points in replay instead." / "Off" + "Why?" (→ N12) |
| microphone off for this recording | "Finding rallies" / "This recording has no sound, so rallies can't be found automatically." / "—" |
| Practice session | "Finding rallies" / "Counting hits" (same gating) |

Backing up row by archive state: "Off · Turn on in Storage" (backup disabled); "Awaiting Google Drive setup" (D3: no
client ID configured); "Not connected · Connect in Storage"; "Queued for your Google Drive archive"; "Uploading ·
62%"; "Verifying"; "Backed up · verified"; "Needs reconnect"; "Google Drive is full".

**Data bindings.** `ImportPipeline` (copy inside the picker handler, content hash for duplicates, `preferredTransform`
respected, no crop), `SessionDocument` stage states (video / replay index / analysis / archive are separate axes, P0-07),
`CapabilityRegistry`, `ArchiveQueue`, `PermissionsStatus`. Percentages are real progress values; when a stage has no
progress API the value column shows a spinner and no number.

**States** (implementation-states "Import/queue").
| State | Treatment |
|---|---|
| Picker cancelled | Nothing changes; no message |
| Copying | "Saved locally" row working with percent; "Recording is safe" card hidden until the copy completes (it would be false before) |
| iCloud-only original | "Downloading from iCloud · 34%" in the Saved locally row |
| Unsupported file | Row error: "This video can't be played on iPhone ([codec])." Item removed from the queue; nothing partial left behind |
| Partial import (interrupted copy) | "Import stopped at 62%. Nothing was saved." + Retry |
| Duplicate | ImportItemCard shows "Already in your library (Oct 6, Jon vs Alex)" with "Open it" and "Import anyway" |
| Not enough space | "Not enough space to import this 4.9 GB video. 2.1 GB free." + "Manage storage" |
| Analysis failed | Finding rallies row: "Couldn't finish. Your video is safe and plays normally." + Retry |
| Analysis cancelled / paused | "Paused · Resume" |
| Offline | Backup row "Waiting for a connection"; all other stages unaffected |
| Wi-Fi only on cellular | Backup row "Waiting for Wi-Fi" |
| Demo | All stages animate from a scripted demo state and say so in the footer |

**Interactions.** Tiles → `PhotosPicker` (`preferredItemEncoding: .current`, videos only, no library authorization)
or `UIDocumentPickerViewController` (movie UTTypes). "View session" → S09 (works as soon as "Saved locally" is done).
"Pause analysis" toggles. "Find rallies: When charging" schedules a `BGProcessingTaskRequest(requiresExternalPower:
true)`.

**Accessibility.** Order: title, source tiles ("Photos, videos from your library, button"), selected video, stage rows
(each one element: "Finding rallies, 62 percent, in progress"), safe card, buttons, footer. Progress changes are
announced at 25% steps only. Dynamic Type: source tiles become a vertical list at accessibility sizes.

**Landscape and iPad.** Single column; iPad: source tiles and the selected video side by side above the stage timeline.

**Deliberate differences from the reference image.**
- The Google Drive tile uses a generic cloud-folder symbol, not Google's logo (hard rule 6), and states that it works
  through Files (the in-app Google Picker, P1-08, is out of v1 per D11).
- "Analyzing points / Detecting shots, rallies and key moments" becomes "Finding rallies" with copy that matches the
  registry status (D10: rally finding is benchmark-gated and its results always need review; there is no shot or
  key-moment detection in v1).
- Subtitle "let JOVRA do the rest" is replaced by a promise the app can keep.
- The heading drops the trailing period to match `screens.json`.
- Added: iOS-version-specific background wording, the "Now · When charging" choice.

---

### S08 Session library (`AppTab.sessions`, reference 08)

**Purpose.** Every session on this iPhone (and archived-only ones), searchable and filterable, each showing its
independent states: where the video is, whether it is backed up, and whether points need review.

**Route.** Sessions tab root. Tab bar visible.

**Layout.**
1. Header: `JovraLockup` (40) leading; trailing "+ Import" pill (`.jovraAccent` compact, ≥44 pt) → S07.
2. Title "Your sessions", subtitle "Review. Improve. Keep going."
3. **SearchField** "Search players, courts, notes" (`.searchable`-equivalent inline field; searches titles, player
   names, court/location text, notes, bookmark notes, equipment).
4. `FilterPills` "All" / "Matches" / "Practice". A trailing "Sort and filter" icon button opens a sheet (sort: newest,
   oldest, longest; filters: needs review, not backed up, only on this iPhone, in Drive only, sample).
5. **SessionCard** list (full variant): thumbnail (poster frame, 16:10, `Radius.control`), title, score line for matches
   ("6–4 6–3"; doubles "6–4 3–6 [10–8]"), metadata "Oct 6 · 54 min · Singles", then up to two **StatusPill**s in
   priority order: review > archive problem > location. Sample sessions add `ProvenanceBadge(.sample)` beside the title.
6. Section "Recently deleted" at the bottom when non-empty (collapsed row "Recently deleted · 2").

**Status pill text** (one axis per pill; symbol + text, never colour alone):
| Axis | Values |
|---|---|
| Location (D7) | "Only on this iPhone" (neutral, iphone symbol) · "On this iPhone · Backed up" (positive) · "In Google Drive only" (neutral, cloud symbol) · "Restored from Google Drive" (neutral, first week only) · "Video missing" (attention) |
| Archive | "Backing up · 62%" · "Queued for backup" · "Waiting for Wi-Fi" · "Retry backup" (attention) · "Needs reconnect" (attention) |
| Review | "Needs review · 8" (attention, clay ring) · "Analyzing · 62%" (neutral) |

**Data bindings.** `SessionLibrary` (index rebuilt from folders if missing, ADR-0002), `SessionDocument` (title,
players, type, duration, final score from `ScoringEngine`), `ReviewState.flaggedCount`, `ArchiveQueue` item state,
original file presence. Per-session size (`SessionLibrary.sizeOnDisk`) appears in the context menu and N6.

**States** (implementation-states "Library").
| State | Treatment |
|---|---|
| Empty | **StateCard**: "No sessions yet" / "Record a match or practice, or import a video you already have." Actions "Record a session" (→ Record tab), "Import a video", text link "Explore the sample" |
| Search, no results | "No sessions match "[query]"" + "Clear search"; filters stay visible |
| Filter, no results | "No practice sessions yet" (per filter) |
| Loading / rebuilding index | First launch after an update or a missing index: redacted cards and the caption "Rebuilding your library from this iPhone…" |
| Archived only | Card thumbnail from the sidecar's poster (or a court placeholder), pill "In Google Drive only"; tapping offers "Download to watch (4.9 GB)" or "View stats" (stats come from the sidecar JSON and work without the video) |
| Video missing (file deleted outside JOVRA, corrupt) | Pill "Video missing"; S09 still shows stats; replay shows the missing-file state |
| Delete | Swipe or context menu "Delete…" → confirmation sheet stating scope: "Delete "Jon vs Alex"?" / "The video (4.9 GB) and its points move to Recently deleted for 30 days. Your Google Drive copy is not affected." Buttons "Move to Recently deleted" (destructive) / "Cancel". Then an **UndoBar** "Moved to Recently deleted · Undo" for 8 s |
| Recently deleted | List with "Restore" and "Delete now" per item; "Delete now" confirms: "Delete the original video permanently? This can't be undone. Backed-up copies in Google Drive are kept." Items purge after 30 days |
| Working sessions | Pills show live progress |
| Sample | Sample badge per card; a footer row "Sample sessions · Remove" (→ S20 confirmation) |

**Interactions.** Tap card → match overview (S09) or practice overview (S09 variant). Context menu: Watch, Review
points, Share pack (N3), Rename, Change session type (P1-18, recomputes), Storage (size, "Archive rallies only"),
Save original to Photos, Delete. Pull to refresh re-scans folders (useful after Files-app changes).

**Accessibility.** Each card is one element: "Jon versus Alex, Jon won 6–4, 6–3, October 6, 54 minutes, singles. Only
on this iPhone. Backing up, 62 percent. Sample" with custom actions (Watch, Review points, Share, Delete). Order:
Import, title, search, filters, cards. A VoiceOver rotor "Needs review" jumps between flagged sessions. Dynamic Type:
thumbnail moves above the text at accessibility sizes.

**Landscape and iPad.** iPad and wide landscape: two-column card grid. iPad split view later (P1-23) may show S09 beside
the list.

**Deliberate differences from the reference image.**
- "On device · Backed up" for Jon vs Alex becomes "Only on this iPhone" + "Backing up · 62%": the sample archive state
  is one coherent dataset (§0.6) and D7 requires "Only on this iPhone" until a verified backup exists.
- Sample badges added (the reference has none); thumbnails are video frames, not photographs.
- Added sort/filter sheet, Recently deleted and per-axis status pills.

---

### S09 Match overview (`Sessions` push, reference 09)

**Purpose.** The match at a glance — final score, the four headline numbers with their fractions, the match story, one
evidence-linked insight — and the two next actions: watch, or review the flagged points.

**Route.** Pushed on the Sessions stack from S08, S03 (switches tab) or right after recording stops. Tab bar visible.

**Layout.**
1. Nav row: back chevron; `JovraLockup` (32) centred; trailing toolbar: share (N3), "•••" (Edit format, Change session
   type, Rename, Head-to-head, Export data, Delete).
2. Title "Jon vs Alex" (`.jovraDisplayTitle()`), subtitle "Oct 6 · Singles · Sample session" (demo) or "Oct 6 ·
   Singles · Central Park Court 3" (user's location text, if entered).
3. Optional stage strip (right after recording/import): compact StageTimeline rows (S07) until all are done.
4. Optional **BannerView**: provisional/conflict/recalculated states (below).
5. **ScoreboardCard** (`EditorialCard` variant with forest fill and a video frame at trailing side): table header
   "Player · Set 1 · Set 2" (columns per set, tie-break superscript "7⁶" rendered as "7–6(4)" style per Rules §1.6),
   rows "Jon" + **WinBadge** "WIN" (chartreuse fill, forest text) and "Alex"; clock symbol + "54 min"; kicker "A
   better game tomorrow" (dropped at large sizes).
6. Four `StatTile`s in one row (2×2 below 360 pt width, stacked at accessibility sizes): "124" Points; "58%" Points won;
   "67%" First serves in; "386" Shots. Tiles show a provenance badge only when it is not all-Manual ("Estimated" if
   any contributing point is auto-filled and unreviewed; "Sample" in demo).
7. `SectionHeader` "Match story" → **MomentumChart** card: line of the rolling 10-point balance (points Jon won minus
   points Alex won over the last 10 points, range −10…+10), shaded above zero in chartreuse tint and below zero in
   clay tint, plus a pattern difference (solid vs hatched fill) so it reads without colour; y labels "Jon leads",
   "0", "Alex leads"; vertical set dividers with set labels "Set 1 · 6–4", "Set 2 · 6–3"; x axis "Point 1 … 124" with
   time labels "0" and "54 min"; caption "Rolling balance of the last 10 points".
8. **InsightCard**: kicker "Insight", headline from `PracticeRules` ("Win more behind your first serve"), evidence
   "28 of 40 first-serve points won.", chevron → S15 with that suggestion expanded.
9. "Watch match" `.jovraAccent` with play symbol → S10 (rally-only when points exist).
10. "Review 8 flagged points" `.jovraSecondary` with list symbol → N1 (filter: needs review).
11. Below the fold: `SectionHeader` "All stats" → **ButterflyStatList** (Jon left, Alex right, label centre, each row
    "Value · fraction"): First serves in, First-serve points won, Second-serve points won (incl. double faults), Aces,
    Double faults, Service points won, Return points won, Break points saved, Break points converted, Total points
    won, Longest point streak; then "Rally length" buckets 0–4 / 5–8 / 9+ (Rules §6.6); then `SectionHeader` "Point
    by point" → list of points grouped by game (score before the point, server, "How it ended", shots, play button);
    then **HeadToHeadCard** (P1-20): "You vs Alex · 3–1 in matches · Last: Oct 6".

**Data bindings.**
| Element | Fixture | Source | Provenance |
|---|---|---|---|
| Set scores, WIN | 6–4, 6–3, Jon | `ScoringEngine.fold(points).sets`, `.winner` | Manual / Reviewed |
| 54 min | 54:00 | `SessionDocument.duration` (match duration from first serve to last point is in All stats as "Match time 54 min") | — |
| Points | 124 | `MatchStats.points` | — |
| Points won | 58% (72/124) | `MatchStats.totalPointsWon(self)` | mix of point provenances |
| First serves in | 67% (40/60) | `MatchStats.firstServeIn(self)` | Manual (serve results entered in review) |
| Shots | 386 | Σ `strokeCount` (§0.2 rule 5) | Manual; Estimated where counted from audio hits |
| Match story | — | `MatchStats.rollingBalance(k: 10)` | — |
| Insight | "28 of 40" | `PracticeRules` firing on `firstServePointsWon` with its evidence fraction | — |
| Flagged count | 8 | `ReviewState.needsReview.count` | — |
| Head-to-head | — | `SessionLibrary` query over matches with the same opponent | — |

**States** (implementation-states "Match/replay").
| State | Treatment |
|---|---|
| No score recorded (video only) | Scoreboard replaced by **StateCard**: "No score yet" / "Mark who won each point in about five minutes." Primary "Score this match" (→ N1 over bookmarks or detected rallies, or "Score from the start" in S10); tiles show "—"; Watch match still works |
| Provisional (unknown outcomes) | BannerView: "3 points have no winner yet. Scores after point 57 are provisional." + "Review"; affected set cells drawn with a dashed outline and "Provisional" in VoiceOver |
| Conflicts | BannerView per conflict type (Rules §4.4), e.g. `serverMismatch`: "Correcting point 12 changed who serves in games 3–19." + "Use rules" / "Keep as played" |
| Recalculated | Toast on return from S10/N1: "Score and stats updated"; tiles that changed show a small "Updated" marker until the next visit |
| Match incomplete / retired | Score shows "6–4 3–1 ret." / "Incomplete"; WIN badge only when the engine declares a winner |
| Analysis working | Stage strip at top; nothing else waits |
| Video missing / archived only | "Watch match" becomes "Download to watch (4.9 GB)" or is disabled with "Video missing"; stats still shown |
| Practice session variant | Title = session title; tiles: "Serves" / "In" / "Marked speeds" (serve practice) or "Swings" / "Key moments set" / "Clips" (stroke practice); no Points won anywhere (Rules §6.8); Match story replaced by a per-set or per-5-minute in/out bar chart |
| Doubles | Rows show team names ("Jon & Sam"); All stats adds per-server serve stats |
| Sample | Subtitle "Sample session", badges on tiles and chart |

**Interactions.** Tap a tile → **FractionPopover** (value, fraction, plain definition, provenance badge, "Show
points" → S10 filtered). Tap the chart → S10 at that point. Insight → S15. Point-by-point play buttons → S10 at that
point. "•••" › "Edit format" → Format sheet (S04) with a warning when results would change ("Changing to No-Ad
changes 6 games. Recalculate?").

**Accessibility.** Order: back, title, subtitle, banners, scoreboard ("Jon won 6–4, 6–3 in 54 minutes"), tiles
(values with fractions), Match story (Audio Graph + "Show as table"), insight, Watch match, Review 8 flagged points,
All stats rows ("First serves in: Jon 67 percent, 40 of 60; Alex 59 percent, 38 of 64"), points list (rotor "Points").
Dynamic Type: scoreboard drops the photo panel and kicker; tiles 2×2 then stacked.

**Landscape and iPad.** iPad: two columns — left: scoreboard, tiles, story, actions; right: All stats and point list.
iPhone landscape: single column.

**Deliberate differences from the reference image.**
- The scoreboard's photo panel is a frame from the session's own video (sample: synthetic frame).
- "First serves" tile label becomes "First serves in" (what the number measures).
- The momentum chart's definition and window are printed (Rules §6.7); the reference's x axis in minutes is kept only
  as end labels because points are not evenly spaced in time.
- Added: All stats, point-by-point list, head-to-head, provenance badges, provisional and conflict states.

---

### S10 Smart replay and point correction (`replay`, reference 10)

**Purpose.** The review loop: watch the whole video or only the rallies, jump between points, step frame by frame,
correct who won a point (and everything after it recomputes), and save a clip. Full-video scrubbing is always
available, even where no point was recognized.

**Route.** Full-screen `replay(session, point?)`. Tab bar hidden. Close (top leading) returns to the presenter.
Opened from S09 (Watch match, chart, point list), N1 ("Open in replay"), S15 ("Watch evidence", as a filtered
playlist), S08 context menu.

**Layout (portrait).**
1. Compact header: Close; `JovraLockup` (28); title "Match replay" (`Font.jovraHeadline`); trailing share (clip export
   / N3) and "•••" (Highlight reel N10, Draw, Captions when a caption track exists, Playback settings, Calibration).
   The reference's large title and subtitle "Review. Learn. Play better." appear only in regular height and are
   dropped first when space is short.
2. **VideoSurface** 16:9 (`Radius.card`), containing: **ScoreboardOverlay** (dark variant, top leading: "Jon 4 30" /
   "Alex 3 15", server ball symbol, score *before* the current point, derived from the fold at the playhead);
   **SampleBadge** "Sample video (synthetic)" top trailing in demo; bottom bar over VideoScrim: play/pause, a thin
   progress line, "12:46 / 54:00", full-screen toggle.
3. **EventTimeline** (whole session, ≥44 pt tall touch area): point markers by shape — filled circle (point, outcome
   set), ring (needs review), diamond (bookmark without a point), square outline (unscored footage block); the current
   point is an enlarged chartreuse ring with a playhead line; time labels at 0:00 and every 10 min. In rally-only mode,
   collapsed gaps appear as **GapChip**s "+0:42" (N7).
4. **JogStrip** (frame-quantized, 48 pt tall, ≥16 pt below the timeline, never at the screen's bottom edge): ticks per
   frame at high zoom, per second when zoomed out; drag to scrub with chase-time seeking; vertical drag-down enters
   single-frame precision. **FrameReadout** at its trailing end: "f 46,000 · 12:46.67 · 60 fps" (tappable to toggle
   time/frames).
5. **TransportBar** (5 round buttons, 56 pt): rate menu "0.5×" (0.25×, 0.5×, 1×, 2×; disabled options when the asset
   can't play slow forward), "Previous frame", Play/Pause (forest disc, 72 pt), "Next frame", and a fifth slot:
   "Rally only" toggle (N7). Hold on frame buttons repeats; double-tap previous/next frame jumps to the previous/next
   point.
6. `FilterPills` (scrolling chips): "All points", "Serves", "Forehands", "Backhands", "Needs review", "Bookmarks", "More…"
   (my points, opponent's points, break points, ≤5 shots, by set). Chips with no matches show their count "(0)" and
   stay tappable to explain why ("No forehands tagged yet. Tag strokes in Point details.").
7. **PointCard** (`.jovraCard()`):
   - "Point 42 · 8 shots" (`Font.jovraHeadline`), detail "Set 1 · Game 8 · Alex serving · 4–3, 15–30".
   - Status: `StatusPill(.attention)` "Needs review" or `ProvenanceBadge` (Manual / Estimated / Reviewed).
   - **OutcomeSegment**: two equal buttons "Jon won" / "Alex won". The effective winner is filled forest with a check;
     an unreviewed suggestion is drawn with a dashed outline and "Suggested" caption; no winner yet = both outlined.
   - "Edit point" (`.jovraSecondary` compact, pencil) → Point editor sheet; "Save clip" (`.jovraAccent` compact, share
     symbol) → Clip range sheet.
   - Disclosure "Point details" (collapsed by default): How it ended (chips: Ace, Service winner, Double fault, Winner,
     Forced error, Unforced error, Unknown), Serve (1st in / 2nd in / Double fault; side Deuce/Ad derived), Shots
     stepper (strokeCount), Stroke tags per shot (optional), Placement ("Mark where it landed" → S11 entry), Error
     direction (Net / Long / Wide), Note, and "Detected vs your decision" (both stored, ADR-0003).

**Data bindings.**
| Element | Source |
|---|---|
| Video, time, frame readout | `ReplayController` over the original (or `RallyComposition` in rally-only mode); fps from the track's nominal frame rate (`FrameRate`) |
| Scoreboard at playhead | `MatchState` of the point containing the playhead (pre-point score); between points, the score after the previous point |
| Timeline markers | `SessionDocument.points` (start/end times), bookmarks, unscored ranges, `ReviewState` |
| Point card | point event + derived `MatchState` (set, game, server, pre-point score); `strokeCount` |
| Outcome buttons | `PointOutcome` `detected` vs `reviewed` (ADR-0003); writing creates a `Supersede` event |
| Filters | point end types, serve facts, manual stroke tags (stroke classification is `disabled`, D10) |

**Correction behaviour (hard rule 4).** Choosing a winner, changing a serve fact or editing an end type appends an
edit event and refolds. Within 300 ms the scoreboard overlay, point card detail, timeline markers and every later
point update; a **Toast** says "Score updated for points 43–124" (or "Score and stats updated"). If the edit creates a
conflict (Rules §4.4) a **BannerView** under the header explains it with "Use rules" / "Keep as played". The original
detected value stays visible under "Detected vs your decision".

**Auxiliary sheets** (implementation-states "Match/replay").
- **Point editor** (medium/large detents): winner (incl. "Unknown"), how it ended, server override ("Alex served
  this point" → `ServerOverride`, with a note on what changes), serve attempts, shots, start/end nudge (±0.1 s
  buttons and a mini jog), "Split point here", "Merge with next", "Add a missed point before/after", "Not a point (let
  or warm-up)", "Delete point", "Mark needs review". Destructive actions confirm with scope.
- **Clip range sheet**: mini timeline with In/Out handles (default = point start − pre-roll 1.5 s to end + post-roll
  2.5 s), "Include audio" toggle (off by default for match sessions, D5), "Show score on video" toggle (burned-in
  overlay from the fold, P1-14), quality "Original (fast, no re-encode)" / "Smaller (720p)", size estimate; primary
  "Save to Photos" (add-only permission requested here, first time only), secondary "Share…" (system share sheet via
  `ShareLink`), tertiary "Add to highlight reel" (N10).
- **Draw mode** (annotation): sticky mode with a toolbar (line, arrow, circle, angle, freehand, colour, undo, delete,
  Done); the jog strip still scrubs while drawing; shapes attach to a frame range (default +12 frames) and autosave
  (P0-16/P1-16).
- **Playback settings**: pre/post-roll defaults for this session, auto-advance to next point, loop current point,
  show/hide scoreboard overlay.

**States.**
| State | Treatment |
|---|---|
| Loading | Poster frame + spinner after 300 ms; controls disabled until `readyToPlay` |
| No points (video only) | Point card replaced by "No points yet" / "Play and tap Mark point at each point's start, or open Fast Point Review." with "Start scoring here" (adds a point at the playhead) |
| Unknown events / unscored footage | Timeline blocks labelled "Unscored footage · 3:10" — always scrubbable |
| Rally-only on | Gap chips; header caption "Rally only · 18 min of 54" (N7) |
| Recalculating | A small inline progress in the point card for >300 ms recomputes (never blocks playback) |
| Needs review | Pill + dashed suggestion as above |
| Video missing | VideoSurface shows **StateCard** (dark) "Video missing" / "The original isn't on this iPhone." + "Download from Google Drive (4.9 GB)" when archived; scoring tools still work on the timeline |
| Unsupported slow motion | Rate options greyed with "This video can't play slower than 1×" |
| Annotation saved | Toast "Drawing saved" |
| Export working / failed | Clip sheet shows progress; failure "Couldn't save the clip. The original is untouched." + Retry |
| Photos add-only denied | "Saving to Photos is off for JOVRA" + "Open iOS Settings"; Share still works |
| Sample | Sample badge on video; corrections allowed and stored in the sample copy (Settings › Reset sample) |

**Accessibility.** Order: Close, title, share, more; video (play/pause button labelled with time), timeline
(adjustable: swipe up/down moves to next/previous point and announces "Point 42, set 1 game 8, Alex serving, 4–3,
15–30, 8 shots, Jon won, needs review"), jog strip (adjustable: one frame per swipe, announces frame and time), rate,
frame buttons, play, rally only, filters, point card. VoiceOver rotor "Points" and "Needs review". Custom actions on
the point card: "Jon won", "Alex won", "Unknown", "Edit point", "Save clip". Captions toggle only where speech exists.
Dynamic Type: transport labels via Large Content Viewer; point card wraps; the video keeps 16:9 and the page scrolls.

**Landscape and iPad.** iPhone landscape: video fills the height on the leading side; a trailing 300 pt panel holds
timeline, jog strip, transport and the point card in a scroll view; the full-screen toggle hides the panel. iPad
(P1-23): video + timeline + jog + transport on the left (≈62%), point list with the current point card expanded on the
right; keyboard shortcuts per §0.5.

**Deliberate differences from the reference image.**
- "Game 8 · 2nd set" → "Set 1 · Game 8 · Alex serving · 4–3, 15–30" (fixture point 42 is in set 1, Rules C15; the
  server's score is called first).
- The CC button moves into "•••" (only meaningful when a caption track exists); its slot becomes "Rally only" (P0-12).
- Added: frame-quantized jog strip and readout (P0-08), shape-coded markers and gap chips, the "Suggested" dashed state,
  and "Detected vs your decision".
- The large title/subtitle is compacted so the video and controls fit; "Sample video" reads "Sample video
  (synthetic)" (D8).
- Timeline marker colours are supplemented by shapes.

---

### S11 Shot placement (`Insights` push, reference 11)

**Purpose.** Where a player's shots landed on a correct top-down court, with In / Out / Needs review markers, depth
bins with denominators, and the way to add or fix placements. In v1 placements are entered by the player (P1-03);
video-derived placement is `disabled` (D10).

**Route.** Pushed on the Insights stack from S15's "Explore" list, S16's Deep-ball card, and S10 Point details ›
"Mark where it landed" (which opens the placement entry mode below directly). Tab bar visible.

**Layout.**
1. `JovraLockup` (40) leading; trailing `AvatarInitial` (→ Profile).
2. Title "Where your shots land", subtitle "See patterns. Play smarter."
3. `FilterPills` "All shots" / "Forehand" / "Backhand".
4. Court card (forest `EditorialCard` variant, no backdrop): header "Jon vs Alex" + chevron (→ **SessionScopePicker**:
   one session or "Last 4 weeks"), detail "Oct 6, 2026 · Sample · 54 min · Singles"; a small player switch "Jon's
   shots / Alex's shots". Then **CourtDiagram** (full court, top-down, ITF geometry: 23.77 × 10.97 m, alleys 1.37 m,
   service lines 6.40 m from the net, centre service line only between the service lines, centre marks, net; the
   hitter's end at the bottom, all of the selected player's landings normalized onto the far half). Depth bands on the
   far half: "Deep" beyond the service line, "Short" inside it, each lightly labelled at the sideline. Markers
   (**CourtMarker**): In = filled chartreuse circle with a forest outline; Out = clay triangle; Needs review = chartreuse
   circle inside a clay ring. Singles: the alleys count as out; doubles: in. Legend row under the court: "● In", "▲ Out",
   "◎ Needs review" (shape glyphs + words).
5. Three `StatTile`s: "62%" Deep balls ("31 of 50"), "24%" Short balls ("12 of 50"), "14%" Out ("7 of 50"); symbols
   per the reference. A caption under them when rounding makes the sum ≠ 100: "Percentages are rounded."
6. Provenance row (`.jovraCard()`): hand symbol + "Placed by you · 50 forehands of 133" + `ProvenanceBadge(.manual)`;
   trailing "Review placements" `.jovraAccent` compact → placement entry mode.

**Placement entry mode** (full-height sheet): top half plays the current shot's clip (3 s loop around the hit), bottom
half shows the CourtDiagram; the player taps where the ball landed (snaps nowhere; a 2× loupe while dragging), or
taps "On the video" to tap the bounce on the frame (projected through the calibration homography; offered only when a
valid calibration exists). Buttons: "Out (net)", "Skip", "Not sure" (marks needs review), "Next shot". Progress
"14 / 133 forehands".

**Data bindings.** `Placement(shotId, courtPoint, source: manual | onVideo, needsReview)`; bins from court geometry;
counts and `pct` per bin; denominator = placed shots of the selected stroke and player in scope; total strokes of that
type from manual stroke tags. Units: the diagram is unitless; any distance shown in detail uses `UnitPreferences`
(metres/feet).

**States** (implementation-states "Shot/serve/stroke labs").
| State | Treatment |
|---|---|
| No placements in scope | Court shows empty bands; **StateCard** under it: "No placements yet" / "Tap where each shot landed while you review. It takes about two seconds a shot." + "Start placing shots" |
| No stroke tags (Forehand/Backhand filter) | "No forehands tagged in this session. Tag strokes in replay or show All shots." |
| Few placements (<20) | Tiles show values plus caption "Based on 12 shots. Patterns settle after about 30." |
| Needs review markers | Counted in their bin with a "1 needs review" caption; tapping a marker opens that shot in entry mode |
| Calibration missing/invalid | "On the video" option hidden; detail "Mark the court corners to place shots on the video" (→ calibration on footage) |
| Video-derived placement | Not available in v1; if the registry ever enables it, markers carry Estimated badges and the provenance row says "Estimated from calibrated video · ±0.3 m near, ±0.8 m far" |
| Outliers | Markers outside the diagram bounds clamp to the edge with an arrow glyph and "outside the court area" in VoiceOver |
| Sample | Badge in the court card header |

**Interactions.** Tap a marker → popover: "Forehand, point 37, landed deep · Placed by you" + "Play" / "Move" /
"Delete". Pinch-zoom the diagram on iPad. Switch player/stroke/scope updates everything.

**Accessibility.** The court is one element with an accessibility label summarising the bins ("Forehand placements,
50 placed: 31 deep, 12 short, 7 out, 1 needs review") and a custom rotor "Shots" that walks markers in time order
("Point 37, deep, cross-court half, in"); "Show as table" lists every placement. Legend uses shapes and words.
Dynamic Type: tiles stack; the court keeps its aspect ratio and scales with width only.

**Landscape and iPad.** iPad and wide landscape: court card left, tiles and provenance stacked right.

**Deliberate differences from the reference image.**
- "Estimated from calibrated video" → "Placed by you · 50 forehands of 133" with a Manual badge: placement in v1 is
  manual (D10, P1-03).
- Markers on both halves of the court become normalized landings on the far half (shots land on the opponent's side);
  out markers are judged against singles lines for a singles match.
- The court is drawn from ITF dimensions (the reference's lines are approximately right but not exact).
- Added: player switch, scope picker, denominators under each tile.

---

### S12 Serve Lab (`Insights` push, reference 12)

**Purpose.** Serve facts the player can trust: first-serve percentages with fractions, placement by side, a
manual-assisted speed estimate with its method stated, and one focus for next time.

**Route.** Pushed on the Insights stack from S15's Explore list. Tab bar visible.

**Layout.** The screen has two clearly scoped sections because speed and match serve stats come from different
sessions (Rules C16).
1. `JovraLockup` + `AvatarInitial`; title "Serve Lab", subtitle "Analyze. Improve. Serve with intent."
2. `SectionHeader` "Serve speed" with trailing scope "Serve practice · Oct 4" + chevron (→ SessionScopePicker limited
   to sessions with marked serves, or "Last 4 weeks").
3. **VideoSurface** (16:10 card) showing the clip of the fastest marked serve, play glyph, **SampleBadge** "Sample
   video (synthetic)" top trailing in demo.
4. **SpeedCard** (forest `EditorialCard` variant): kicker "Fastest marked serve", value "104" + unit "mph"
   (`Font.jovraMetricLarge` + `Font.jovraHeadline`), label "Estimated average speed, contact→bounce", detail "±10% ·
   Fastest of 12 marked serves", info line with symbol "Camera calibration affects speed." + `ProvenanceBadge(.estimated)`.
5. "Review 12 serves" `.jovraSecondary` → serve list for that scope (each serve: clip, estimated speed with range,
   placement, "Edit marks").
6. `SectionHeader` "Latest match" with trailing scope "Jon vs Alex · Oct 6" + chevron.
7. Two `StatTile`s: "67%" First serves in ("40 of 60"); "70%" First-serve points won ("28 of 40").
8. **ServePlacementCard**: title "Serve placement", `FilterPills` "Deuce" / "Ad" (compact), a flat top-down
   **CourtDiagram** service-box variant (the receiver's deuce or ad box with Wide / Body / T zones separated by thin
   lines and labelled), markers as on S11; three columns "52% Wide" ("13 of 25"), "32% Body" ("8 of 25"), "16% T"
   ("4 of 25"); caption "First serves in · placed by you" + Manual badge.
9. **FocusCard**: kicker "One focus for next time", headline "Build a repeatable toss", detail "Same height. Same spot.
   More consistency.", chevron → S15 drill "Toss consistency".

**Speed marking flow** (D10; sheet from "Edit marks" or "Estimate a serve's speed" in the serve list):
1. "Find contact" — jog to the frame where racket meets ball; "Set contact" (frame stored with its timestamp).
2. "Find the bounce" — jog to the first bounce frame; "Set bounce".
3. "Where did it bounce?" — tap the bounce on the frame (projected through the session's calibration) or on the
   service-box diagram; and "Where was the server?" — tap the server's front foot at contact (default: centre mark of
   the server's baseline, shown as an assumption the player can move).
4. Result: "Estimated average speed, contact→bounce: 104 mph (94–114)" with the method line "Distance 18.6 m over
   24 frames (0.40 s) at 60 fps" and Save. Range = ±10% (technical-feasibility §10 error budget) widened when fps < 60.
Requires a valid court calibration; otherwise step 3 offers "Mark the court corners first".

**Data bindings.**
| Element | Fixture | Source | Provenance |
|---|---|---|---|
| Fastest marked serve | 104 mph | `ServeSpeedEstimator` over `ServeMark(contactT, bounceT, bouncePoint, serverPoint)` in scope; `UnitConverter` mph/km/h | Estimated, always |
| 12 serves | 12 | count of serves with complete marks in scope | — |
| First serves in | 67% (40/60) | `MatchStats.firstServeIn` | Manual |
| First-serve points won | 70% (28/40) | `MatchStats.firstServePointsWon` | Manual |
| Placement | 13/8/4 of 25 (deuce) | manual serve placements, zones from the service-box geometry | Manual |
| Focus | "Build a repeatable toss" | `PracticeRules` | — |

**States.**
| State | Treatment |
|---|---|
| No marked serves | SpeedCard replaced by **StateCard**: "No serve speeds yet" / "Mark contact and bounce on a serve to estimate its average speed." + "Estimate a serve's speed" |
| No calibration | "Mark the court corners on this recording to estimate speed." + "Mark corners" |
| Side-on practice clip (court not visible) | "Speed needs a view of the court from behind the baseline." (unsupported for that clip) |
| Outlier (net-cord, >150 mph, or bounce before the service line) | Serve flagged "Check marks" with attention pill; excluded from "fastest" until confirmed |
| Low fps (<60) | Range widens; detail "Lower frame rate: ±15%" |
| No match yet | Latest match section shows "Record a match to see serve stats." |
| Practice session in match scope | Never shows "points won" for practice (Rules §6.8) |
| No placements | ServePlacementCard StateCard: "Tap where your serves landed in replay to see Wide / Body / T." |
| Units | km/h when chosen in S20; ranges convert, never relabel |
| Sample | SampleBadge on video, Sample on SpeedCard and tiles |

**Interactions.** Tap SpeedCard → capability detail N12 ("How JOVRA estimates serve speed"). Tap tiles → fraction
popover. Deuce/Ad toggles the box and numbers.

**Accessibility.** Order: title, Serve speed header + scope, video, speed card ("Fastest marked serve, estimated
average speed from contact to bounce, 104 miles per hour, plus or minus 10 percent, fastest of 12 marked serves,
estimated, sample"), Review 12 serves, Latest match header + scope, tiles, placement (summary label + rotor), focus.
Dynamic Type: the speed numeral scales with `.largeTitle`; tiles stack.

**Landscape and iPad.** iPad: two columns — speed section left, match section right.

**Deliberate differences from the reference image.**
- "Fastest serve · Estimated" → "Fastest marked serve" + "Estimated average speed, contact→bounce" with range and
  count (D10; speed is manual-assisted, never measured, Rules C16).
- The page is split into a speed section (serve practice) and a match section so each number states its source; "Review
  12 serves" moves under the speed card because it belongs to that set.
- "T down the line" → "T" (correct serve-zone term); the perspective mini court becomes a flat top-down service box.
- The reference photo of a player is replaced by the session's own clip.

---

### S13 Stroke Lab (`Insights` push, reference 13)

**Purpose.** Look closely at chosen swings: named key moments the player sets, an on-demand 2D pose overlay labelled as
an estimate, review checklists instead of scores, and a contact-position comparison across several swings.

**Route.** Pushed on the Insights stack from S15's Explore list. Tab bar visible. "Compare swings" pushes the
contact-strip view; "Open in compare" presents S14.

**Layout.**
1. `JovraLockup` + `AvatarInitial`; title "Stroke Lab", subtitle "Analyze. Improve. Repeat."
2. Row: `FilterPills` "Forehand" / "Backhand" (standard forest selection) and a trailing **SourceChip** "Sample video" / the clip's session title, which opens
   the swing picker (sessions with swing clips, then swings).
3. **VideoSurface** (4:3 or 16:9 per clip) paused on the current key moment, with an optional **PoseOverlay**: joints
   drawn only above the confidence threshold, bones as thin ivory lines, the dominant wrist's path over the swing as a
   dashed chartreuse line; label chip "2D pose estimate" top leading whenever the overlay is on. Toggle button "Show 2D
   pose" (eye symbol) top trailing. Mirror toggle for left-handers in "•••".
4. **KeyMomentStrip**: five thumbnails "Backswing", "Forward swing", "Contact", "Follow-through", "Finish"; the
   selected moment has a chartreuse border and bold label; unset moments show a dashed placeholder with "Set".
   Long-press a thumbnail → "Set to current frame" / "Clear".
5. Three **ReviewRow**s (symbol, title, detail, trailing **ReviewStatusButton**): "Contact timing" / "When you meet the
   ball"; "Follow-through" / "Racket path and extension"; "Balance" / "Stability and body control". The button cycles
   through a menu: "Review" (not yet) → "Looks good" → "Work on it", with symbol + text.
6. **FocusCard** (forest): headline "Compare contact position across 5 swings", detail "See consistency, find
   patterns, play better.", mini graphic of five contact points, button "Compare swings" (`.jovraAccent`).

**Contact strip view** (pushed): the contact frames of up to 5 selected swings side by side (or overlaid as an onion
skin at 30% opacity each when the camera did not move), aligned on a user-adjustable reference line; export as an image
("Save contact strip").

**Data bindings.** Swing clips from `SessionDocument` (bookmarks or manual stroke tags with padded ranges −1.0/+1.0 s,
P1-05); `KeyMoment(name, frameTime, source: manual)`; `PoseEstimator.run(frame)` on demand (Vision
`VNDetectHumanBodyPoseRequest`; registry status for the overlay: `estimated`, label "2D pose estimate"); handedness from
`Player`; review statuses stored per swing.

**States.**
| State | Treatment |
|---|---|
| No swing clips | **StateCard**: "No swings to study yet" / "Record a stroke practice from the side, or tag strokes in a match replay." + "Set up stroke practice" (→ S04 preset) |
| Handedness unset | Before mirroring or labelling forehand/backhand: inline prompt "Which hand does Jon play with?" Right / Left |
| Pose not detected | Overlay chip "No pose found in this frame" (no joints drawn) |
| Low confidence joints | Missing joints are simply not drawn; caption "Some joints hidden: low confidence" |
| Player too small (match footage far end) | "Too far from the camera for a pose estimate." Toggle disabled for that clip |
| Pose running | Small progress on the toggle; video stays usable |
| Fewer than 5 swings | Focus card adapts: "Compare contact position across 3 swings" (minimum 2) |
| Camera moved between swings | Onion skin disabled with "Camera position changed; showing side by side." |
| Sample | SourceChip "Sample video", Sample badge on focus card |

**Interactions.** Tap a key moment → seek there. Scrub with the shared JogStrip (shown when the video is tapped).
"Compare swings" → contact strip. "•••" → "Open in compare" (S14 with this swing preloaded), "Mirror", "Draw".

**Accessibility.** The pose overlay is described, not drawn into VoiceOver: "2D pose estimate shown. Joints: right
wrist, right elbow, shoulders, hips, knees." Key moments are buttons ("Contact, selected, frame 1,204"). Review buttons
announce state ("Contact timing, looks good"). No angles or degrees are ever spoken or shown. Dynamic Type: key-moment
strip scrolls horizontally with labels under thumbnails; rows wrap.

**Landscape and iPad.** iPad: video left, key moments under it, review rows and focus card right.

**Deliberate differences from the reference image.**
- The swing path is labelled as the wrist's 2D path (Vision has no racket keypoints, technical-feasibility §11).
- The overlay is off until the player turns it on (on demand, D10), and the "2D pose estimate" chip is always visible
  while it is on.
- Selected segment uses the standard forest selection, not chartreuse, for consistency with every other FilterPills.
- The reference photo becomes the player's own clip.

---

### S14 Video comparison (`compare`, reference 14)

**Purpose.** Put two of the player's own recordings side by side, align them at contact, play or step them together,
draw on them, attach voice notes and a written note, and save the comparison as a project without copying video.

**Route.** Full-screen `compare(project | pair)`. Tab bar hidden. Opened from S13 ("Open in compare", "Compare
swings" when two are chosen), S10 "•••" › "Compare with…", S15 drill evidence, and Insights Explore › "Compare your
form". Close returns; unsaved changes prompt "Save this comparison?".

**Layout (portrait).**
1. Compact header: Close; `JovraLockup` (28); trailing **SourceChip** "Your recordings" (opens the pair picker).
2. Title "Compare your form", subtitle "See the details. Play. Improve." (dropped in compact height).
3. Two stacked **VideoSurface**s (equal 16:9): each with a label chip ("Today · Oct 6", "Previous · Sep 28" —
   relative word only when true: "Today", "Yesterday", else the date only), a "•••" menu (Replace clip, Mirror, Set sync
   point here, Clear drawings, Remove), full-screen toggle, its own play glyph and time "0:12 / 0:28". Drawings render
   on each surface.
4. **DualSyncTimeline**: two scrub rows labelled "Today" / "Previous" with their times; a centre vertical sync line with
   the label above it: "Sync at contact" (Locked state) or "Not synced" (Align state, amber dashed line + unlock glyph).
5. Control row (each a square-ish button with a label under it): "0.25×" Speed (menu 0.25/0.5/1×), Play (forest disc),
   "Draw", "Voice note".
6. **NoteRow**: lightbulb symbol + the user's note "Keep the toss position consistent." + chevron (edit).
7. "Save comparison" `.jovraPrimary` with arrow (bottom inset).

**Sync model (P0-16).** Each side stores `syncEventTime` and its `captureFPS`; the shared playhead is time relative to
the sync event (never frame index). States: **Align** (each timeline scrubs independently; a "Lock at this frame"
button appears) → **Locked** "Sync at contact" (one jog moves both) → **Nudge** (±1 frame buttons for either side
without unlocking). "Play one side" is in each side's menu.

**Data bindings.** `CompareProject(clipA, clipB, syncA, syncB, annotations, voiceNotes, note)` saved in the session
folder of clip A (references, no video copy); `ReplayController` ×2 with a shared clock; `Annotation` per side;
`VoiceNote(audioFile, pinnedTime)`.

**States** (implementation-states "Comparison").
| State | Treatment |
|---|---|
| Choosing the second video | Pair picker sheet: "Pick two of your recordings" — sessions → clips/bookmarks, with thumbnails; only the user's own recordings (no library of other players) |
| Missing file | That surface shows "Video missing" + "Pick another"; the project keeps its notes |
| Mixed frame rates (60 vs 240) | Caption under the timeline: "Different frame rates: aligned by time, stepping follows the slower clip." |
| Not synced | Amber dashed sync line, "Not synced" label, Play plays both from their own positions |
| Voice note recording | Voice note button shows a red dot + elapsed time; playback pauses while recording; mic permission asked here if never asked (explained first); denied → "Microphone is off for JOVRA. Write a note instead." + "Open iOS Settings" |
| Voice notes present | Pins on the sync timeline; tap to play |
| Draw mode | Sticky; tool palette above the control row; jog still scrubs |
| Saved | Toast "Comparison saved"; it appears under both sessions in S09 "•••" › Comparisons |
| Different camera positions | Overlay mode (one surface at 50% opacity over the other, in "•••") warns "Camera positions differ; overlay may mislead." |

**Accessibility.** Order: Close, sources, title, video A (label + play), video B, sync timeline (adjustable: frame
steps of the shared playhead; announces "Synced at contact, plus 3 frames"), speed, play, draw, voice note, note, save.
Each surface's label is read before its controls. Dynamic Type: control labels via Large Content Viewer at
accessibility sizes.

**Landscape and iPad.** Landscape: the two videos side by side, sync timeline and controls in a strip below; iPad: side
by side with a trailing notes panel (voice notes list, note editor, drawings list). Pencil draws only with Pencil
(`drawingPolicy = .pencilOnly`).

**Deliberate differences from the reference image.**
- The overlays in the reference (a toss line and ball rings) are user drawings, not automatic tracking; nothing draws
  itself in v1 (auto contact sync is P2-05).
- Relative date words appear only when true.
- Added explicit Align/Locked/Nudge states and a "Not synced" appearance.

---

### S15 Coaching plan — Insights home (`AppTab.insights`, reference 15)

**Purpose.** One practical focus for the coming week, built by deterministic rules from the player's own stats, with
the evidence one tap away and drills the player can edit. It is also the Insights tab's home, so it ends with the way
into the labs.

**Route.** Insights tab root. Tab bar visible.

**Layout.**
1. `JovraLockup` + `AvatarInitial`.
2. Kicker "Insights" (`Font.jovraKicker`), title "Your next advantage", subtitle "Evidence-linked practice, built for
   your game."
3. `EditorialCard` (with a frame from the evidence clip on the trailing side): kicker with bars symbol "This week",
   headline "A steadier first serve", detail "Based on Jon vs Alex · Oct 6" (demo: "Based on your sample match."),
   **EvidenceRow** inside the card: "28 / 40" (`Font.jovraMetricLarge`) + "first-serve points won" + "Watch evidence"
   (play symbol, compact secondary on forest) and a small `ProvenanceBadge` when not Manual. Kicker "A better game
   tomorrow".
4. `SectionHeader` "Suggested practice" with trailing link "Why these drills?" (→ sheet explaining the rule: "We
   suggest serve drills when you win fewer than 75% of first-serve points or put fewer than 65% of first serves in,
   over at least 30 service points." Thresholds come from `PracticeRules` and are shown verbatim).
5. Three **DrillRow**s (numbered "01"/"02"/"03" in `Font.jovraMetric`, thumbnail art, title, meta, chevron/disclosure):
   - "Toss consistency" / "8 min · 3 sets of 10"
   - "Wide serve targets" / "12 min · Deuce + Ad" — expanded state shows a **CourtDiagram** service-box drawing with
     targets in the two wide corners and the description "Hit first serves to wide targets on both sides. Focus on
     placement and margin over the net."
   - "Serve + first ball" / "15 min · With a partner"
   Expanded rows are outlined in chartreuse with a forest number (selection never by colour alone: the chevron flips
   and the row says "selected" to VoiceOver).
6. "Start drill" `.jovraAccent` with play symbol (starts the expanded drill; disabled until one is expanded).
7. Text button "Edit plan" (reorder, remove, add from the drill library, change sets/minutes).
8. `SectionHeader` "Explore your game" → five navigation rows (`SettingsRow` style with symbols): "Where your shots
   land" (S11), "Serve Lab" (S12), "Stroke Lab" (S13), "Compare your form" (S14), "See the work pay off" (S16).

**Drill session** (full-screen `drillSession`): drill title, instructions, timer (counts down, pausable), set counter
"Set 2 of 3", optional quick tally buttons "In" / "Out" (manual counts saved as a practice log), "Record this drill"
(→ S04 preset as Serve practice with the drill linked), "Finish" (saves the log, updates goal progress on S16).

**Data bindings.** `PracticeRules.suggestions(stats: latest match + pooled 4 weeks, goals)` → focus + up to 3 drills
from a bundled drill library (text and diagrams authored by us; no coach claims); evidence = the stat fraction plus the
point IDs it counts (a playlist for "Watch evidence"); edits stored as the player's plan.

**States** (implementation-states "Drills/progress").
| State | Treatment |
|---|---|
| No sessions | Card: "Record a match to get a focus" / "Suggestions come from your own points." + "Set up a session"; Explore list still shown |
| Too little data (<30 relevant points) | Card: "Not enough points yet" / "We need about 30 service points for a serve focus. You have 18." |
| Evidence unavailable (video missing/archived) | "Watch evidence" → "Evidence video isn't on this iPhone" + "Download" or "Show the points list" |
| Rule fired from Estimated points | Evidence row shows Estimated badge and "Includes points JOVRA filled in from changeover scores. Review them for a firmer number." |
| Edited plan | Header detail "Your plan · edited Oct 7"; "Reset to suggestions" in Edit plan |
| Sample | "Based on your sample match." + Sample badge |

**Accessibility.** Order: kicker+title (header), subtitle, focus card ("This week: a steadier first serve. Based on Jon
vs Alex, October 6. 28 of 40 first-serve points won. Watch evidence, button"), Suggested practice header, Why these
drills, drill rows ("Drill 2 of 3, Wide serve targets, 12 minutes, deuce and ad, expanded"), Start drill, Edit plan,
Explore rows. Dynamic Type: drill thumbnails hide at accessibility sizes; numbers stay.

**Landscape and iPad.** iPad: focus card full width; drills left, Explore list right.

**Deliberate differences from the reference image.**
- "Based on your sample match." is used only in demo; real data names the session.
- The wide-target drawing puts targets in the wide corners of each service box (the reference draws them mid-box).
- The screen doubles as the Insights tab home, so the Explore list is added below the plan.
- "Suggested practice" stays the only framing: no "coach", no guarantees.

---

### S16 Progress (`Insights` push, reference 16)

**Purpose.** Show change over time without being fooled by small samples: pooled numerators and denominators, only
comparable session types, deltas in percentage points, and goals the player sets.

**Route.** Pushed on the Insights stack from S15's Explore list, S03 tiles/trend (switches tab). Tab bar visible.

**Layout.**
1. `JovraLockup` + `AvatarInitial`; title "See the work pay off", subtitle "Track your progress over time."
2. `FilterPills` "4 weeks" / "3 months" / "Year".
3. Scope row: "Singles matches" + chevron (session-type filter: Singles matches, Doubles matches, Serve practice, Stroke
   practice) and "First serves in" + chevron (metric picker: First serves in, First-serve points won, Second-serve
   points won, Points won, Deep balls, Serve speed (estimated), Review completion).
4. **TrendCard** (large): title "First serves in", value "67%", "vs. 63%", delta "+4 percentage points" (positive ink +
   up arrow; negative uses attention ink + down arrow; zero "No change"), **TrendChart** with points and markers per
   bucket (weeks for 4 weeks, months for 3 months and Year), y axis 0–100 with labels at 0/20/40/60/80/100, x axis
   "1 2 3 4" + axis title "Week"; the latest point is a chartreuse marker with a forest outline. Each point's tooltip /
   VoiceOver value: "Week 3: 63 percent, 38 of 60, 1 match".
5. **MilestonePanel** (forest strip with ball symbol): "8 sessions · 6h 42m" / "on court".
6. Two **MetricCard**s side by side: "Deep-ball placement" "62%" with a mini top-down court thumbnail of placements
   (→ S11), and "Review completion" "116 / 124" "points" with a review glyph (→ N1 for the open session).
7. Caption: "Sample data · Compare similar session types" (demo) or "Compare similar session types · Based on 4
   matches, 230 service points".
8. "Set a practice goal" `.jovraAccent` with arrow → **GoalEditor** sheet.
9. "Compare by setup" row (P1-02, Profile gear linked): **SetupComparisonCard** listing the chosen metric per string
   job or racket for the same session type, each with its sample size; shown only when every setup has ≥3 sessions and
   ≥100 points, with the caption "Association in your sessions, not proof the strings caused it." + Estimated badge.
10. Goals list (when any): **GoalRow** "First serves in ≥ 70% over 4 weeks · now 67%" with a progress ring and text
   status ("3 percentage points to go").

**Data bindings.**
| Element | Fixture | Source |
|---|---|---|
| Weekly values | 48, 55, 63, 67 | `TrendPool.bucketed(metric, sessionType, window)` — pooled n/d per bucket, `pct` |
| Headline and "vs." | 67 vs 63 | latest bucket vs the previous non-empty bucket; delta from the displayed integers |
| Milestone | 8 sessions · 6h 42m | session count and Σ duration in window, all types |
| Deep-ball placement | 62% (31/50) | pooled placed groundstrokes in window (fixture: only Jon vs Alex has placements, all 50 forehands) |
| Review completion | 116 / 124 | points reviewed / points in sessions that still have unreviewed points, in window |
| Goals | — | `Goal(metric, target, window)` evaluated by `TrendPool` |

**States** (implementation-states "Drills/progress").
| State | Treatment |
|---|---|
| Too few comparable sessions (<2 buckets with data, or <100 points pooled for a rate) | Chart replaced by "Not enough to compare yet" / "Play 2 more singles matches to see a trend." The milestone still shows |
| Bucket with tiny denominator (<20) | Point drawn hollow with a "small sample" note in its tooltip; excluded from the headline comparison |
| No placements | Deep-ball card: "No placements yet" + "Start placing shots" |
| Everything reviewed | Review card: "All points reviewed" with a check |
| Estimated metric (serve speed) | Card and chart show Estimated badge and ranges as error bars |
| Units change | Speed series convert (stored values are converted, never relabelled) |
| Goal met | GoalRow check + "Goal met on Oct 6" (no confetti; optional subtle haptic) |
| Sample | Caption and badges |

**Accessibility.** The chart has an Audio Graph and "Show as table" (bucket, value, fraction, sessions). Delta reads
"up 4 percentage points from 63 percent". Range and scope controls are buttons with values. Dynamic Type: metric cards
stack; chart labels thin.

**Landscape and iPad.** iPad: chart card wider; metric cards and goals in a right column.

**Deliberate differences from the reference image.**
- Added the session-type and metric pickers (comparable sessions only, Rules §6.10) and denominators in tooltips.
- "Review completion" is defined as review progress on sessions still open, so it cannot silently mix finished matches.
- The milestone photo becomes a plain forest strip with the ball symbol.

---

### S17 Racket Vault (`Profile` push, reference 17)

**Purpose.** The player's own equipment, entered by them: rackets, the active setup with its current string job, and
court kit, linked to sessions so court time and (later) setup comparisons are computed, never guessed.

**Route.** Pushed on the Profile stack from Profile hub (N11). Tab bar visible.

**Layout.**
1. `JovraLockup` + `AvatarInitial`; title "Racket Vault", subtitle "Your gear. A better game."
2. **EquipmentHeroCard** (forest, large): the racket's photo if the player added one (PhotosPicker, single image,
   cropped to the card) else **RacketArt** (vector frame with chartreuse mains and ivory crosses); kicker "Current
   racket", title "Head Prestige", detail "Active setup", **TagPill**s "Hyper-G mains" (chartreuse fill) and "Ghost Wire
   crosses" (ivory fill), plus "Strung Sep 9 · 6h 42m logged" caption. Chevron → racket detail.
3. **EquipmentRow** (card): thumbnail, kicker "Second racket", "Wilson Pro Staff 85", detail "Classic frame" (the
   player's note), chevron.
4. **EquipmentRow**: kicker "Court kit", "Dunlop bag · Grand Prix balls", chevron.
5. "Log a restring" `.jovraPrimary` with arrow → Restring form (S18 aux) prefilled by cloning the active racket's last
   job.
6. Text button "Add a racket".

**Racket detail** (pushed): name, user-entered model text, nickname, head size/weight/balance (all optional, free
text with units; never auto-filled from a catalog, D6), notes, photo, "Make active", string job history (→ S18),
sessions played with it (count and logged court time), "Retire racket" (kept in history), "Delete" (confirm; sessions
keep a text snapshot of the setup).

**Data bindings.** `EquipmentStore` (Racket, StringJob, StringInventoryItem, CourtKit text), `LoggedCourtTime(job)` = Σ
session durations whose `SessionDocument.equipment` references that job, `activeRacket`.

**States.**
| State | Treatment |
|---|---|
| Empty | **StateCard**: "Add your rackets" / "Track which racket and strings you played with and how long they've been in." + "Add a racket" |
| No string job on the active racket | Hero shows "No strings logged" + "Log a restring" |
| Photo access | PhotosPicker needs no permission; nothing else is asked |
| Sample | Sample badge beside the title; sample gear is clearly labelled "Sample setup" |
| Add/edit form errors | Inline: name required; numeric fields accept the user's unit and keep the entered text |

**Accessibility.** Hero: "Current racket, Head Prestige, active setup. Mains Hyper-G, crosses Ghost Wire. Strung
September 9, 6 hours 42 minutes logged." Rows are buttons. Dynamic Type: hero text sits below the art at accessibility
sizes.

**Landscape and iPad.** iPad: hero left, rows right.

**Deliberate differences from the reference image.**
- The generated racket photographs are not shipped: user photos or neutral vector art only (no manufacturer marks, hard
  rule 6).
- Added a "Strung … · logged" caption so the active setup's age is visible here.

---

### S18 String journal (`Profile` push, reference 18)

**Purpose.** A stringer's log: mains and crosses, gauge, tensions exactly as entered, date, optional machine/method,
notes, feel ratings, string inventory, and computed court time since the restring. No sensors, predictions or medical
claims.

**Route.** Pushed on the Profile stack from S17 (hero chevron, "Log a restring" after saving) or N11. Tab bar visible.

**Layout.**
1. `JovraLockup` + `AvatarInitial`; title "String journal", subtitle "Dial in your feel."
2. **RacketSelectorCard** (forest, racket art/photo): "Head Prestige" + chevron-down (menu of rackets); caption "Strung
   Sep 9, 2026 · by you" (from the job).
3. **StringSetupCard** (two columns split by a hairline): "Mains" (chevron-down to pick from inventory or type) with a
   **SpoolArt** swatch in the string's colour (user-chosen colour, default by name-free palette) and "Solinco Hyper-G",
   detail "1.25 mm · 17"; "Crosses" / "Tier One Ghost Wire" / "1.20 mm · 18".
4. Two **TensionField**s: "Mains tension" "52 lb", "Crosses tension" "50 lb" (value + unit + chevron to edit), and the
   label "Sample setup" in demo.
5. **UsageCard**: "6h 42m since restring" + chevron (→ the sessions list), **TrendChart** (cumulative hours by session
   date from the restring date to today, markers per session, x labels "Sep 9 … Oct 6").
6. **FeelCard** "Feel after play": three **RatingSlider**s "Control" 8 / 10, "Comfort" 7 / 10, "Spin" 9 / 10, caption
   "Your ratings".
7. **InventoryRow**: spool swatch, "WeissCANNON", "Add to inventory" + chevron (inventory list with remaining length).
8. "Save stringing note" `.jovraPrimary`.
9. `SectionHeader` "History" → previous jobs (date, mains/crosses, tensions, logged time, note).

**Restring form** (sheet; implementation-states "Racket/strings"): racket; date (default today); strung by (Me / Shop
with name); mains string (inventory or free text), gauge label (text, e.g. "17") and diameter (mm, optional); crosses
(same; "Same as mains" toggle for a full bed); mains and crosses tension (number + unit lb/kg, stored as entered; a
secondary line shows the converted value "≈ 23.6 kg" but the stored value is what the player typed); pre-stretch
(optional %); machine type (optional: Drop weight / Crank / Electronic constant pull / Other); method/knots (optional
text); string pattern (optional, e.g. "16×19"); notes; photos (optional, PhotosPicker); reminder (hours and/or days;
never a prediction). "Save" clones nothing destructive; "Log a restring" from S17 pre-fills from the last job.

**Data bindings.** `StringJob(mains, crosses, tensionMains: Measurement as entered, tensionCrosses, date, machine?,
method?, notes, photos)`, `LoggedCourtTime(job)`, `SetupRating(control, comfort, spin, date)`,
`StringInventoryItem(name, gauge, colour, lengthRemaining?)`, `UnitConverter` for the secondary display only.

**States.**
| State | Treatment |
|---|---|
| No jobs | **StateCard**: "No string jobs yet" / "Log your first restring to track how long your strings have been in." + "Log a restring" |
| No sessions since restring | Usage "0m since restring" + caption "Sessions you record with this racket count here." |
| Reminder due | Banner on the card: "You asked to be reminded after 20 hours. 21h 10m logged." (user-set, not a prediction) |
| Units | lb ↔ kg displays a converted secondary value; the entered value is never rewritten |
| Hybrid vs full bed | Columns collapse to one "Mains and crosses" when "Same as mains" |
| Sample | "Sample setup" label + badge |

**Accessibility.** Tension fields read "Mains tension, 52 pounds, button". Rating sliders are adjustable (1–10 steps)
with value "8 out of 10, your rating". The usage chart has an Audio Graph. Dynamic Type: two-column cards stack.

**Landscape and iPad.** iPad: setup and tension left, usage and feel right.

**Deliberate differences from the reference image.**
- The racket photo with a manufacturer logo and the marketing kicker "Control meets confidence." are removed (hard rule
  6); the card shows the job date instead.
- Spool images become neutral **SpoolArt** swatches (no product packaging).
- The usage chart's dates follow the fixture (Sep 9 – Oct 6), not the reference's April–May labels.
- Gauge is shown as diameter + label because the label alone is ambiguous across makers.

---

### S19 Storage and backup (`Profile` push, reference 19)

**Purpose.** Make ownership concrete: what is on this iPhone, what is backed up and verified in the player's own Google
Drive, what is waiting and why, and how to export or free space. Backup never runs analysis and never deletes an
original without explicit confirmation and a verified copy.

**Route.** Pushed on the Profile stack from N11, S07/S08 backup links, S04 low-space banner. Tab bar visible.

**Layout.**
1. `JovraLockup` + `AvatarInitial`; title "Your video, your choice", subtitle "Keep your footage safe, on your terms."
2. **DeviceStorageCard** (forest): "On this iPhone" / "Originals stay local until you choose backup." Bar
   (**StorageBar**) with "JOVRA uses 12.4 GB" leading and "243.6 GB free" trailing; device capacity in the VoiceOver
   value; phone-with-play glyph.
3. **ProviderRow** (card): cloud-folder symbol (not Google's logo), "Google Drive", status line (below), trailing
   "Manage" button (connected) / "Connect" (not connected) / none (awaiting setup).
4. **ToggleRow** group: "Back up originals" / "Upload a copy of your videos to Google Drive."; "Wi-Fi only" / "Only
   upload when connected to Wi-Fi."; "What to back up" value row "Full video" / "Rallies only (Space Saver)" (N6);
   "Include originals in iCloud backup" / "Off: originals are left out of your iPhone's iCloud backup to save space.
   Keep them safe with Google Drive or Save to Photos." (D7, default off).
5. `SectionHeader` "Upload queue" with `ProvenanceBadge(.sample)` in demo → **QueueRow**s (thumbnail, title, state
   line with symbol, progress bar when uploading, chevron → item detail): "Jon vs Alex" / "Uploading · 62%"; "Serve
   practice" / "Queued · next"; "Forehand session" / "Retry backup" (attention, tap = retry; detail shows the reason).
6. **NavRow** "Export video + analysis" / "Save or share your sessions" → export sheet.
7. Caption "Backup storage does not run analysis."
8. "Manage storage" `.jovraPrimary` with database symbol → N6.

**Provider status lines** (D3; exact strings):
| `DriveAuth` / `ArchiveQueue` state | Status line | Action |
|---|---|---|
| No OAuth client ID configured in the build | "Awaiting setup" with caption "Google Drive backup will be available once JOVRA's Google connection is set up." | none (honest; no fake Connect) |
| Not connected | "Not connected" | "Connect" → `ASWebAuthenticationSession` (Google consent page; scope `drive.file` only) |
| Connected | "Connected · [account email]" + "Folder: JOVRA" | "Manage" |
| Demo | "Connected · Demo" + Sample badge | "Manage" (opens demo detail; nothing leaves the phone) |
| Token expired / revoked (`invalid_grant`) | "Needs reconnect" (attention) | "Reconnect" |
| Quota exceeded | "Google Drive is full" (attention) + "Free up Drive space or back up rallies only." | "Use Space Saver" |
| Offline | "Offline · uploads resume automatically" | — |

**Queue item states** (technical-feasibility §13 state machine): "Queued · next", "Queued · 3rd", "Hashing", "Waiting
for Wi-Fi", "Waiting for a connection", "Uploading · 62%" (bytes "3.0 of 4.9 GB" in detail), "Verifying", "Backed up ·
verified Oct 6" (size + MD5 match), "Retry backup" (with reason: "Connection lost at 41%. JOVRA will resume from
there." / "Google Drive said the upload expired. Starting a new upload."), "Needs reconnect", "Google Drive is full".

**Manage sheet (connected).** Account email, folder path "My Drive › JOVRA", archived sessions count and size, "Restore
a session" (list from the Drive folder's sidecars → download with progress, verify, mark "Restored from Google Drive"),
"Retention" (**RetentionEditor**: "After a verified backup: Keep originals on this iPhone (default) / Offer to remove
originals older than 30 / 90 days" — removal always asks per batch and lists sizes), "Disconnect Google Drive"
(confirmation: "Disconnect? JOVRA stops backing up and forgets its access. Files already in your Drive stay there.
This also disconnects JOVRA on your other devices." → revoke token, clear Keychain).

**Export sheet** (P1-11, implementation-states "Archive"): choose sessions; contents "Original video", "Rally-only
video", "Session data (JSON)", "Points and stats (CSV)"; destination "Save to Files", "Save to Photos" (videos only),
"Share…"; size estimate; "Include audio" (off by default for match sessions, D5).

**Data bindings.** `DeviceBudget.freeBytes` and capacity, `SessionLibrary.totalSize`, `DriveAuth.state`, `ArchiveQueue`
(persisted JSON journal per item, ADR-0002), `UserPreferences.backup*`, `isExcludedFromBackup` on original files.

**States** (implementation-states "Archive").
| State | Treatment |
|---|---|
| OAuth cancelled | No change; caption "Google Drive wasn't connected." |
| OAuth failed | BannerView "Couldn't connect to Google Drive. Try again." |
| Interrupted upload | Item resumes from the confirmed offset (308 Range + 1) automatically; row shows "Resuming at 41%" |
| Checksum mismatch | "Backup didn't verify (sizes or checksums differ). Uploading again." — never "Backed up" |
| No sessions | Queue section: "Nothing to back up yet." |
| Backup off | Queue section hidden; ToggleRow explains "Your originals are only on this iPhone." |
| Low device space | DeviceStorageCard bar turns attention with "Less than 5 GB free" + "Free up space" (→ N6) |
| Sample | Demo numbers (§0.6), Sample badges |

**Accessibility.** DeviceStorageCard: "JOVRA uses 12.4 gigabytes. 243.6 gigabytes free of 256." Toggles are standard
`Toggle`s with labels and hints. Queue rows: "Jon versus Alex, uploading, 62 percent, 3.0 of 4.9 gigabytes"; progress
updates announced at 25% steps. Dynamic Type: toggles wrap their descriptions; queue thumbnails hide at accessibility
sizes.

**Landscape and iPad.** iPad: device card and provider left; toggles and queue right.

**Deliberate differences from the reference image.**
- No Google Drive logo (hard rule 6); a generic cloud-folder symbol and the words "Google Drive".
- "Connected · Demo" appears only in demo; real builds without a configured client ID show "Awaiting setup" (D3).
- "Serve practice · Waiting for Wi-Fi" while another item uploads would contradict the Wi-Fi state; the coherent demo
  shows "Queued · next". "Waiting for Wi-Fi" appears when the phone is actually off Wi-Fi.
- "12.4 GB of 256 GB used" becomes "JOVRA uses 12.4 GB · 243.6 GB free" (the two numbers are different measurements).
- Added: Space Saver choice, iCloud-backup toggle (D7), retention editor, restore and disconnect.

---

### S20 Settings and privacy (`Profile` push, reference 20)

**Purpose.** Permissions with their consequences, preferences, privacy and data controls, recording rules, help and
diagnostics — native grouped settings in JOVRA's palette. No fake permission dialogs, no prices.

**Route.** Pushed on the Profile stack from N11. Tab bar visible.

**Layout** (grouped cards, `SettingsRow` everywhere).
1. `JovraLockup`; title "Settings", subtitle "Your privacy. Your game."
2. Profile card: `AvatarInitial` (52), "Jon", subtitle "Apple sign-in" (Apple symbol) or "No account · on this iPhone";
   chevron → Account sheet (name, Sign in with Apple status, "Sign in with Apple"/"Stop using Apple sign-in").
3. "Recording": "Camera" / "Allowed" (or "Not asked yet", "Off · Turn on to record", "Restricted"); "Microphone" /
   "Optional · Off · Rallies won't be found automatically" (or "Optional · On", "Optional · Not asked yet");
   "Photos" / "Not needed to import" (or "Saving clips · Allowed (add only)", "Saving clips · Off"). Each row → a
   detail sheet with what the permission does, what turning it off costs, and "Open iOS Settings".
4. "Open iOS Settings" row + caption "Manage JOVRA's access in iOS Settings."
5. "Recording defaults": "Default format" (1080p · 60 fps), "Live scoring" (Every point), "Countdown before recording"
   (Off), "Court mode" (Automatic when hot · Always · Off), "Hands-free Mark point" (Volume buttons · Camera Control ·
   AirPods; P1-12), "Include audio in shared clips" (Off).
6. "Preferences": "Units" / "mph · lb" (choices "mph · lb · ft", "km/h · kg · m"); "Appearance" / "System" (Light,
   Dark); "Accessibility" (→ in-app: announce score changes, spoken framing cues, haptics, larger scoreboard during
   recording, show frame numbers); "Language" (→ iOS per-app language settings).
7. "Privacy & data": "Training data" / "Never collected · JOVRA has no servers" (info row, no toggle); "Apple Health" /
   "Off" (P1-22 opt-in: "Save tennis sessions as workouts. JOVRA never adds calories or heart rate."); "Export my data"
   (→ S19 export sheet with "Everything"); "Remove sample data" (only when present); "Delete all JOVRA data" (clay
   title, trash symbol).
8. "Recording rules" → N4 (Competition mode, Junior & parent mode, Consent defaults).
9. "Support": "Recording help" (→ in-app guide: placement, heat, battery, interruptions); "Send diagnostics" (→ N5);
   "Contact" row showing the text "hello@islanddevcrew.com" (selectable, copy button; no `mailto:`); "Privacy policy" and
   "About JOVRA" (version, licences, "Made by Island Development Crew").
10. Footer caption: "JOVRA 1.0 (42)".

**Data bindings.** `PermissionsStatus` (AVCaptureDevice auth for video/audio, `PHPhotoLibrary.authorizationStatus(for:
.addOnly)`), `UserPreferences`, `UnitPreferences`, Sign in with Apple credential state
(`getCredentialState(forUserID:)`), HealthKit authorization (only after opt-in).

**States** (implementation-states "Settings").
| State | Treatment |
|---|---|
| Permission changed in iOS Settings | Rows refresh on `scenePhase == .active` |
| Delete all data | Confirmation sheet listing scope: "Deletes every session (videos, points, notes), your profile, equipment and settings from this iPhone ([size]). Files you backed up to Google Drive and clips saved to Photos are not deleted. This can't be undone." Requires typing "DELETE" for sessions with originals not backed up; then disconnects Drive and returns to S01 |
| Sign in with Apple revoked | Account row "Apple sign-in · stopped"; nothing else breaks |
| Notifications | Never asked here; asked only when the player turns on a feature that needs them (string reminders, background analysis finished) |
| Remove sample data | Confirmation; sample sessions, gear and demo archive state removed; user data untouched |
| Health denied | Row "Off · Allowed in the Health app" with explanation |

**Accessibility.** Standard grouped list semantics (`List` with `.insetGrouped` style restyled by colour roles);
section headers are headers; values read after labels; destructive row announced as "Delete all JOVRA data, button,
deletes data". Dynamic Type: values move under labels.

**Landscape and iPad.** Single column, 720 pt max.

**Deliberate differences from the reference image.**
- "Training data sharing" toggle → info row "Never collected": with no server (D2, ADR-0002) a toggle would imply data
  can leave the phone.
- "Delete account" → "Delete all JOVRA data": there is no JOVRA account; the scope of deletion is stated.
- "Photos · Selected photos" → "Not needed to import" / add-only states (technical-feasibility §2: PhotosPicker needs no
  library access).
- Microphone row states the consequence of Off (P0-22).
- Footer "JOVRA · Reference concept" → version and build.
- Added: Recording defaults, Recording rules (N4), Apple Health, Language, Send diagnostics, contact text.

---

## 2. New surfaces introduced by the backlog

Same visual language: ivory utility surfaces with `.jovraCard()`, forest for video and focused capture, chartreuse for
the single primary action, clay only for attention/flags with a symbol.

---

### N1 Fast Point Review deck (`pointReview`, P0-11)

**Purpose.** Turn an unscored, partly scored or flagged match into a correct point-by-point record in minutes without
trusting automation: one card per point with a looping clip, one gesture or button per decision.

**Route.** Full screen, tab bar hidden. From S09 "Review 8 flagged points" (filter: Needs review), S09 "Score this
match" (filter: Unscored), S16 Review completion, S03 NextStepRow, S10 filter "Needs review" › "Review as cards".

**Layout (portrait).**
1. Header: Close; title "Point review"; progress text "1 / 8" and a thin **ProgressLine**; filter menu chip "Needs
   review ▾" (Needs review · Unscored · All points).
2. Optional **BannerView** for checkpoint conflicts: "Games 7–9 don't match your changeover score 4–4. Review these 23
   points." (`checkpointConflict`).
3. **SwipeReviewCard** (the top card of a stack; the next card peeks 8 pt below at 96% scale, flat with Reduce
   Motion): VideoSurface 16:9 looping the point (start − 0.5 s to end + 1.0 s; `AVPlayerLooper`), mute toggle; under it
   "Point 42 · Set 1 · Game 8", "Alex serving · 4–3, 15–30 before the point", "8 shots" (if known), and either
   "Suggested: Jon won" with a dashed outline and `ProvenanceBadge(.estimated)` (checkpoint auto-fill or detection) or
   "No winner yet". Edge hints appear while dragging: right "Jon won", left "Alex won", up "Not a point", down "Not
   sure" (text + symbol, never colour alone).
4. **ReviewActionBar** (same four decisions as buttons, ≥56 pt): "Alex won" (leading), "Not a point", "Not sure", "Jon
   won" (trailing) — order mirrors the swipe directions; swipe right always means the player (self) won, left the
   opponent.
5. **UndoBar** after every decision: "Jon won point 42 · Undo" (8 s).
6. Footer link "Open in replay" (→ S10 at this point, deck state kept).

**Completion.** Summary card: "8 points reviewed" / "Score and stats updated." + "Done" (→ presenter, which shows the
Recalculated toast) and "Review all 124 points".

**Data bindings.** `ReviewState` queue for the filter; each decision appends a reviewed `PointOutcome` (or
`NotAPoint`/`RallyLet` for "Not a point") and refolds; "Not sure" keeps `needsReview` and moves the card to the end.
Pre-point score from `MatchState` (provisional if an earlier point is unknown). Clip windows from point times or
bookmarks (unscored bookmark → window from the bookmark to the next bookmark, max 20 s).

**States.** Empty filter ("Nothing to review. Every point has a decision." + Done); no video (cards show score context
and a "Video missing" placeholder; decisions still allowed); doubles (buttons name teams "Jon & Sam won"); sample.

**Accessibility.** Each card is one element with the full sentence ("Point 42, set 1 game 8, Alex serving, 4–3, 15–30,
8 shots, suggested Jon won") and custom actions "Jon won", "Alex won", "Not a point", "Not sure", "Play clip", "Open
in replay"; swipes are never the only way. The looping clip pauses while VoiceOver focus is on it if the user enables
"Pause video for VoiceOver". Reduce Motion: decisions cross-fade the next card in.

**Landscape and iPad.** Landscape: clip leading (fills height), actions in a trailing column. iPad: deck centre-left,
a list of all points in the filter on the right with their decisions (tap to jump).

---

### N2 Changeover checkpoint entry (S06, P0-11)

**Purpose.** Score a match with about ten taps: enter only the games at each change of ends; the engine fills point
winners that are forced by the rules and flags the rest for N1.

**Route.** On S06 when Live scoring is "Changeover scores only" (the ScorePad slot shows a single wide "Changeover ·
enter score" button), also available in "Every point" mode from "•••" › "Check the score". Presented as a half-height
**CheckpointPad** sheet; recording continues underneath.

**Layout.** Title "Score at the changeover"; "Set 1" (stepper for set number with "Set finished" toggle); two rows
"Jon" and "Alex", each with a big **CountStepper** (− value +, 64 pt) prefilled with the last checkpoint; a hint line
"Last saved: 3–2 at 18:40"; "Save 4–3" `.jovraAccent` (label includes the score); "Cancel".

**Data bindings.** `Checkpoint(setIndex, games, t)` events (Rules §4.1). After recording, `CheckpointSolver` runs over
bookmarks / detected rallies: unique assignments become `estimated` outcomes; ambiguous stretches stay unknown and are
queued for N1 with `checkpointConflict` when the stretch can't reach the entered score.

**States.** Illegal entry (e.g., 7–3) → inline "That isn't a possible set score" and Save disabled; set finished →
asks for a tie-break score when 7–6; after recording S09 shows "98 points filled in from your changeover scores ·
Estimated · 26 need review".

**Accessibility.** Steppers are adjustable elements ("Jon, 4 games"); Save announces "Saved 4–3 for set 1".

**Landscape and iPad.** Sheet becomes a trailing panel over the capture view.

---

### N3 Share Pack sheet (P1-09)

**Purpose.** Send a coach, partner or opponent exactly what matters — clips, notes, stats and data — without them
needing an app or an account. Private by default.

**Route.** Sheet (large detent) from S09 share, S10 share › "Share pack", S08 context menu, N10 export.

**Layout.**
1. Title "Share pack", subtitle the session ("Jon vs Alex · Oct 6").
2. "Who is it for?" `FilterPills`: "Coach" · "Opponent" · "Partner" · "Me". Presets: Coach = flagged and bookmarked
   clips + notes + stats; Opponent = full rally-only match video + score + `match.json` (the ITF U18 opponent-copy
   case); Partner = highlights + score; Me = everything.
3. Contents (ToggleRows with counts and sizes): "Clips (8 points)" → clip chooser; "Rally-only match video
   (18 min)"; "Stats summary"; "Notes and drawings"; "Session data (JSON + CSV)".
4. Options: "Video size" Original / Smaller (720p); "Include audio" (off by default for matches); in Junior mode,
   "Blur faces" (N4).
5. Delivery: "Zip file (AirDrop, Files, Messages)" (always available) and "Google Drive link" (only when connected
   and the `drive.file` sharing spike has passed; otherwise the row reads "Google Drive link · Not available yet");
   link options: person-specific (recipient's Google email) and expiry "7 days / 30 days".
6. Size estimate "About 640 MB" + "Create pack" `.jovraAccent`.

**Output.** A zip containing `index.html` (static viewer: score, stats with fractions, clip list with notes; no
external resources, no tracking), clips, `match.json` (ADR-0002 schema), `points.csv`. Then the system share sheet.

**States.** Building (progress with cancel), not enough space, video missing (data-only pack offered), no points
(clips section disabled: "No points marked yet"), Drive offline, sample (pack labelled "Sample" inside `index.html`).

**Accessibility.** Standard form controls; size estimate read after each change ("About 640 megabytes").

**Landscape and iPad.** Form sheet on iPad (540 pt).

---

### N4 Consent, competition and junior-parent mode (P1-10)

**Purpose.** Record respectfully and within event rules: a consent decision per session, a competition mode with no
live prompts, and a parent mode for children's profiles kept local and private. JOVRA states practices, never legal
compliance.

**Route.** Settings › "Recording rules" (pushed screen); the Consent sheet from S04's "Recording consent" row; the
"Delete this recording" action on S06 and S09.

**Recording rules screen.**
- "Competition mode" toggle / "Scoring only. No live suggestions or prompts beyond changeover scores. Check your
  event's rules before recording; some events don't allow it." Default for new match sessions when on.
- "Junior and parent mode" toggle / "For recording children. Their profiles stay on this iPhone, consent is required
  before each recording, shared clips are private and leave sound out." When on: player records can be marked "Junior";
  S04 requires a consent choice for sessions with a junior; Share Pack defaults to person-specific delivery; audio off;
  "Blur faces in shared clips" toggle (on-device face blur on all detected faces, labelled "Faces the camera can't see
  clearly may not be blurred.").
- "Default consent" picker (used to pre-fill S04).

**Consent sheet.** Title "Recording consent"; options (radio): "Everyone on court agreed to be recorded", "Written
consent attached" (→ attach a photo or PDF from Photos/Files, stored in the session folder, never uploaded unless the
session is backed up), "Recording only me", "Not set". Caption: "Ask before you record other players. If someone changes
their mind, delete the recording from the record screen."

**Delete this recording (consent withdrawn).** S06 "•••" › "Delete this recording": sheet "Delete this recording
now?" / "The video recorded so far (12:46) and its points are deleted from this iPhone immediately. This can't be
undone." Buttons "Delete now" (destructive) / "Keep recording". Bypasses Recently deleted by design; if a backup
already exists, a second line names it: "A copy is in your Google Drive. Delete it there too?" (Delete Drive copy /
Keep).

**States.** Junior without consent (S04 primary disabled with "Choose a consent option to record a junior"); attached
file missing; sample.

**Accessibility.** Radio group semantics; destructive buttons announce scope.

---

### N5 Diagnostics (P1-21)

**Purpose.** Support that can fix a problem in one exchange, without telemetry: a diagnostics file the player creates,
previews and sends themselves.

**Route.** Settings › Support › "Send diagnostics" (pushed). Also offered from failure states (recording recovery,
export failure) as "Create a diagnostics file".

**Layout.** Title "Send diagnostics", subtitle "Nothing leaves this iPhone unless you send it." Contents (ToggleRows):
"App log (last 7 days)", "Recording journal" (session picker), "Heat and battery log", "Device model and iOS version".
**InfoCard** "Never included": "Videos, audio, photos, names, notes and your Google account." "Preview contents"
(→ read-only text viewer). "Create diagnostics file" `.jovraPrimary` → zip → system share sheet. Caption: "To ask for
help, send the file to hello@islanddevcrew.com" (text, selectable, copy button; no `mailto:`).

**Data bindings.** `DiagnosticsBundle` (OSLog export via `OSLogStore`, session journals with names redacted, thermal
log, versions).

**States.** Creating (progress), nothing selected (button disabled), log unavailable (row explains), share cancelled.

---

### N6 Space Saver (P0-17, P0-07)

**Purpose.** Know what uses space and free it safely: per-session sizes, derived caches, rally-only archive copies and
the explicit, verified path to removing an original from the phone.

**Route.** S19 "Manage storage" (pushed), S04/S05 low-space actions, S08 context menu › Storage.

**Layout.**
1. Title "Manage storage", subtitle "See what's on this iPhone and free space safely."
2. StorageBar card: "Originals 11.3 GB · Replay files 1.1 GB · Free 243.6 GB".
3. "Clear replay files" row: "1.1 GB · Rebuilt automatically when you watch" → confirm → done (always safe).
4. "Back up rallies only" explainer card: "Keep a rally-only copy in Google Drive: about 1.7 GB instead of 4.9 GB for a
   54-minute match. Between-point footage isn't kept in that copy." + toggle (mirrors S19 "What to back up").
5. "Practice preset" row: "Record practice at 1080p · 30 fps (about 60 MB a minute)".
6. `SectionHeader` "Sessions by size" → rows: title, date, size, status ("Backed up · verified", "Rallies backed up",
   "Only on this iPhone"), trailing menu: "Save original to Photos", "Back up now", "Remove original from this
   iPhone…".

**Remove original rules.** Enabled only when a verified backup of the full original exists (then: "Remove the 4.9 GB
original from this iPhone? A verified copy is in your Google Drive (checked Oct 6). You can download it again
anytime."), or when only a rally-only backup exists (then a second, explicit step: "Only the rallies will remain.
About 36 minutes of between-point footage will be gone for good." with "Remove anyway" requiring a hold-to-confirm
button). Never offered for sessions with no verified backup; the row says why ("Back it up first").

**States.** No Drive (rally-only rows say "Connect Google Drive to use this"); no points (rally-only "Mark points first:
rally-only needs to know where points are"); working (export progress for rally copies); sample.

**Accessibility.** Hold-to-confirm has a VoiceOver alternative (a confirmation alert with the same text).

---

### N7 Rally-only playback controls (S10, P0-12)

**Purpose.** Watch a match in a fraction of its length while seeing exactly what was skipped.

**Where.** Integrated into S10: the "Rally only" toggle in the TransportBar's fifth slot, GapChips on the EventTimeline,
a header caption, and options in Playback settings.

**Behaviour and layout.**
- Toggle on → `RallyComposition` from point ranges with pre-roll 1.5 s / post-roll 2.5 s (defaults; per-session
  setting 0–5 s in 0.5 s steps). Header caption "Rally only · 18 min of 54" + source badge: "From your marks"
  (Manual) or "From rally finding · Needs review" (Estimated).
- Each skipped stretch is a **GapChip** "+0:42" on the timeline; tapping it expands that gap inline (the gap plays
  once and the chip shows "Showing 0:42"); long-press "Add a point here".
- "Rallies" list (from "•••"): every rally with a checkbox, "Select all" / "Select none" and duration; deselecting
  removes it from rally-only playback and exports, not from the session.
- "Show all footage" is one tap (the toggle) and the full video's time is always available in the readout.

**States.** No points or bookmarks (toggle disabled; tap explains "Mark points to watch rallies only"); detection
results present but unreviewed (badge as above); export of rally-only (via Clip sheet "Whole match · rally only").

**Accessibility.** Toggle "Rally only, on, 18 minutes of 54"; GapChips are buttons ("Skipped 42 seconds, show").

---

### N8 Pre-flight checklist (S04, S05, P0-02)

**Purpose.** Know before the first serve that the phone has room, charge and a sensible setup.

**Where.** Compact **PreflightStrip** on S04; full **ChecklistRow** on S05 (with "More checks").

**Checks** (each pass / warn / fail with symbol + text; only camera access can block recording, and even then import
is offered):
| Check | Pass | Warn | Fail |
|---|---|---|---|
| Storage | "Room for about 2 h 40 min" | "Room for about 38 min" (less than planned) | "Less than 5 min of space" |
| Battery | "Battery 78%" / "Charging" | "<30%: about 50 min at this rate" ; "Low Power Mode on" | — (never blocks) |
| Heat | "Phone cool" | "Phone warm · preview may turn off" | — |
| Camera | "Camera ready" | "Not asked yet" | "Camera off · Open iOS Settings" |
| Microphone | "Sound on" | "No sound · rallies won't be found" | — |
| Lens (iOS 26+, availability-checked) | "Lens clear" | "Lens may be smudged · wipe it" | — |
| Tip (static) | "Tip: turn on Do Not Disturb so calls don't interrupt recording." | | |

**Data bindings.** `DeviceBudget`, `StorageEstimator`, `PermissionsStatus`, lens-smudge API behind `#available` (D1).

**Accessibility.** Each check one element ("Storage, room for about 2 hours 40 minutes, passed").

---

### N9 Court mode and the heat ladder (S06, P0-03)

**Purpose.** Keep recording on hot days and let the player see from the baseline that it is still saving.

**Court mode layout.** Pure black full screen (OLED), screen brightness lowered for the window scene and restored on
exit; centred: red dot + "REC" + timer in **jovraRecTimer** (64 pt monospaced), under it "Saved · 2 s ago", the score
in small type, battery percentage; bottom: "Show preview" button (shows the preview for 10 s) and the Stop button
(still requires confirmation). Mark point stays available (hardware buttons work too).

**Heat ladder** (from `systemPressureState` and `thermalState`; each rung logged into the session so later analysis
knows the frame rate changed):
| Rung | What JOVRA does | Banner text |
|---|---|---|
| Nominal | — | — |
| Fair | Dims the preview | "Phone warming · Recording safe" |
| Serious | Court mode on (if Automatic) | "Phone hot · Preview off to keep recording" |
| Critical | Lowers to 30 fps (`activeVideoMinFrameDuration`) | "Phone hot · Recording at 30 fps" |
| Shutdown | System stops capture; segment saved | Interruption sheet: "Your phone got too hot. Everything up to 41:12 is saved." |

**Live Activity (spike-gated, P1-13).** If the spike shows it appears while JOVRA records in the foreground, a Live
Activity mirrors "REC 32:10 · Saved 4 s ago · Battery 64%" on the Lock Screen and the Apple Watch Smart Stack
(`Text(timerInterval:)`, updated from the journal heartbeat, never claiming "recording" without a fresh heartbeat:
after 10 s without one it shows "Status unknown"). Not built if the spike fails.

**Accessibility.** VoiceOver users get a "Show preview" button rather than a double-tap gesture (VoiceOver owns double
tap); the timer is read as elapsed time; Reduce Motion: no pulsing dot.

---

### N10 Highlight reel builder (`highlightReel`, P1-14)

**Purpose.** A shareable 60–90 second reel with the score burned in from the fold, so corrections update it.

**Route.** Full screen from S10 "•••" › "Highlight reel", S09 share › "Highlight reel", N3.

**Layout.**
1. Header: Close; title "Highlight reel"; trailing "Export".
2. Preview **VideoSurface** in the chosen aspect with the live overlay (SwiftUI over `AVPlayerLayer`, same layout as
   the export's Core Animation layer).
3. Length indicator "1:12 · aim for 60–90 s".
4. Clip list (reorderable rows): thumbnail, "Point 37 · 6–4, 2–1 · Jon won", duration, trim (opens the Clip range
   sheet), remove. "Add clips" → chooser defaulting to Mark-point favourites and "Great point" notes.
5. Options: "Show score" (on), "Title card" (text field, e.g. "Jon vs Alex · Oct 6"), "Aspect" 16:9 / 9:16 / 1:1 (9:16
   and 1:1 show a draggable crop window per clip), "Include audio" (off by default for matches), "Captions" (only for
   voice-note speech).

**Export.** `HighlightRenderer` (composition + Core Animation tool, `#available` branches for the iOS 26 composition
API); iOS 26: `BGContinuedProcessingTask` with system progress ("You can leave JOVRA"); iOS 18–25: "Keep JOVRA open
until the export finishes" with progress and Cancel. Result: Save to Photos / Share.

**States.** Score changed since export ("Scores changed since you exported. Export again?"), empty reel, export failed
(original untouched; Retry), not enough space, sample (title card defaults to "Sample").

**Accessibility.** Clip rows have reorder actions ("Move up/down"); overlay text is part of the exported video only,
so the preview also exposes the current score as an element.

---

### N11 Profile hub (`AppTab.profile` root)

**Purpose.** The Profile tab's home (not drawn in the references): who the player is and the way to gear, storage and
settings.

**Layout.** `JovraLockup`; title = player name "Jon" (or "Profile" when no name), subtitle "Right-handed · One-handed
backhand · Club player" (unset parts omitted); `.jovraCard()` group of rows: "Player profile" (→ S02 edit), "Racket
Vault" / "Head Prestige · active" (S17), "String journal" / "6h 42m since restring" (S18), "Storage and backup" / "3
sessions only on this iPhone" (S19), "Settings" (S20). DemoBanner in demo.

**States.** No profile name, no gear ("Add your racket"), backup attention ("Needs reconnect" in clay ink with symbol).

---

### N12 Capability detail sheet ("How this was measured", P0-20)

**Purpose.** Every Estimated badge, "Off until it passes testing" note and "Why?" link opens the same explanation, so
the player can judge how much to trust a number.

**Layout** (medium/large sheet): capability name ("Serve speed"); status with badge ("Estimated · manual-assisted");
"How it works" (plain language, two or three sentences); "What affects it" (bullets: calibration, frame rate, where you
tapped); "How well it works" (the latest benchmark result with date and numbers from the registry, or "Not yet
benchmarked on real courts"); "What JOVRA doesn't do" (e.g., "No line calls. No spin readings."); method version
(`serve-speed-manual@1`).

**Data bindings.** `CapabilityRegistry.entry(id)` (status, method/model version, gate, last benchmark run).

---

## 3. Auxiliary-state coverage map

Every row of `implementation-states.md` and where this spec covers it.

| Parent | Covered in |
|---|---|
| Welcome/onboarding: returning sign-in, cancelled/failed Apple sign-in, guest/demo exit, editable profile and goals | S01 States, S02 edit mode, S03 DemoBanner |
| Setup: player editor, match format/rules, doubles positions, racket selector, supported camera presets | S04 auxiliary sheets |
| Calibration: camera denied, open iOS Settings, no camera/simulator fixture, unclear corners, unsuitable angle, low light, low disk space | S05 States |
| Recording: stop confirmation, interruption, segment saved/recovery, thermal reduced capability, low battery/storage, manual score undo, bookmark note | S06 States, N9 |
| Import/queue: picker, unsupported codec/resolution, partial import, duplicates, cancelled task, failed analysis, retry, offline | S07 States |
| Library: empty, search no results, restored archive, archived-only download, delete-to-trash with undo and explicit retention | S08 States |
| Match/replay: point/shot editor, full-video timeline, unknown events, recalculation indicator, drawing mode, clip range and share | S09, S10 auxiliary sheets and States, N7 |
| Labs: no detected data, manual evidence, unknown confidence, outliers, calibration missing/invalid, estimated vs reviewed | S11, S12, S13 States, N12 |
| Comparison: select second video, missing file, align timecodes, saved draw/voice-note state, landscape | S14 |
| Drills/progress: edit plan, evidence unavailable, too few comparable sessions, filter by session type, units, goal completion | S15, S16 |
| Racket/strings: add/edit frame, restring form, inventory, gauge and units, mains/crosses, date, machine/method, notes/photos, session association | S17, S18 |
| Archive: OAuth cancelled/expired/revoked, no quota, interrupted upload, resume/retry, checksum validation, export originals + JSON, retention editor, disconnect | S19, N6 |
| Settings: permission status, Settings redirect, units/appearance, notification opt-in when needed, accessibility, diagnostics consent, data export, deletion confirmation, recording help | S20, N5 |
| Optional future plan (pricing) | Out of v1 (D2): no paywall, StoreKit or prices anywhere |
| Optional future Watch | Out of this spec (D11); Live Activity spike only (N9) |

---

## 4. Screen-to-backlog traceability

| Backlog | Screens |
|---|---|
| P0-01, P0-03, P0-04 | S05, S06, N9 |
| P0-02, P0-05 | S04, S05, N8 |
| P0-06 | S07 |
| P0-07 | S08, S19, N6 |
| P0-08, P0-10 | S10 |
| P0-09 | S04, S06 |
| P0-11 | N1, N2 |
| P0-12 | N7 |
| P0-13 | S07, S10 (gated) |
| P0-14 | S03, S09 |
| P0-15 | S10 clip sheet, S19 export |
| P0-16 | S14 |
| P0-17 | S19, N6 |
| P0-18 | S01, S19, S20 |
| P0-19 | S02, S04 |
| P0-20 | every badge, N12 |
| P0-21 | §0.4 and each screen |
| P0-22 | S20 |
| P1-01 | S17, S18 |
| P1-02 | S16 metric picker (association, Estimated, minimum 3 sessions and 100 points per setup; wording "Association in your sessions — not proof the strings caused it") |
| P1-03 | S11 |
| P1-04 | S12 |
| P1-05 | S13 |
| P1-06 | S15 |
| P1-07 | S16 |
| P1-09 | N3 |
| P1-10 | N4 |
| P1-11 | S19 export |
| P1-12 | S06, S20 |
| P1-13 | N9 (spike-gated) |
| P1-14 | N10 |
| P1-15, P1-16 | S14, S10 draw mode |
| P1-17 | S05 (disabled; no UI until the gate passes) |
| P1-18 | S04 format sheet, S09 "Edit format" |
| P1-19 | S04 players sheet, S06 (doubles order prompt), S09 |
| P1-20 | S09 head-to-head |
| P1-21 | N5 |
| P1-22 | S20 Apple Health |
| P1-23 | iPad sections of S09, S10, S14, N1 |
| P1-24 | §0.2 rule 11, S20 Language |
| P1-26 | §0.1 deep links |
| D10 serve speed / pose | S12 speed flow, S13 overlay |

---

## 5. Token and component inventory

### 5.1 Existing foundation pieces and the extensions they need

| Component | Extension needed | Used by |
|---|---|---|
| `JovraScreen` | Optional `kicker` above the title (S15); optional trailing header content already exists (`accessory`); a `bottomAction` slot rendered as a safe-area inset (S02, S04, S14) | all tab and push screens |
| `JovraLockup` | Ivory-on-forest variant (S01, S05, S06, video headers) and a compact height 28 | S01, S05, S06, S10, S14 |
| `EditorialCard` | `trailingImage` slot (a video frame, fading into forest) for S09, S15; a `minHeight` parameter (S12 SpeedCard, S17 hero are shorter than 220) | S03, S09, S12, S15, S17, S18 |
| `StatTile` | `scope: String?` caption (S03), `fraction: String?` second line ("40 of 60"), `onTap` for the FractionPopover, a compact variant for 4-up rows | S03, S09, S11, S12 |
| `FilterPills` | Scrolling chip variant with counts (S10 filters), compact size (S12 Deuce/Ad) | S02, S08, S10, S11, S12, S13, S16, N3 |
| `ProvenanceBadge` | Size `.small` for markers and table cells; on-forest appearance | everywhere |
| `StatusPill` | `.inProgress` tone with determinate progress text; accepts a custom symbol (iphone, cloud) | S08, S10, S19 |
| `SettingsRow` | Value-under-label layout (S04 SetupRow reuses it), toggle trailing content, destructive title role | S04, S15, S20, N11 |
| `AvatarInitial` | Size presets 52/64/96; person symbol when no name | S02, S03, S20, N11 |
| `JovraButtonStyle` | `.compact` size (44 pt min, used inside cards: "Save clip", "+ Import", "Review placements"); an on-forest secondary (ivory outline) | many |
| `CourtLinesBackdrop` | none | S03 |
| `ComingLaterCard` | Replaced in features by real states; keep for unbuilt tickets only | — |

### 5.2 New components

**Chrome and states**
| Component | Purpose | Notes | Used by |
|---|---|---|---|
| **FocusedHeader** | Compact header for full-screen routes: Close, small lockup, title, trailing actions | ≥44 pt targets; hides title in compact height | S10, S14, N1, N10 |
| **StateCard** | Empty / error / permission / unsupported block: symbol, title, message, primary + secondary actions; light and dark variants | one component for all §0.3 states | most screens |
| **BannerView** | Inline banner (info, positive, attention) with symbol, text, up to two actions | used for conflicts, recovery, failures | S01, S03, S09, S10, S19, N1 |
| **Toast** | Transient confirmation ("Score updated for points 43–124"), announced to VoiceOver | 4 s; never the only place a result is shown | S06, S09, S10 |
| **UndoBar** | Toast with an Undo action, 8 s | | S06, S08, N1 |
| **DemoBanner** | "You're exploring sample data" + action | dashed outline like the Sample badge | S03, N11 |
| **InfoCard** | Icon + title + body card (positive/neutral tint) | | S02, S07, N5 |
| **StepRail** | Onboarding progress (done/current/upcoming) | VoiceOver "Step 2 of 3" | S02 |
| **FractionPopover** | Value + fraction + definition + provenance + "Show points" | the "fraction one tap away" rule | S03, S09, S11, S12, S16 |
| **SessionScopePicker** | Sheet to pick one session or a time window | | S11, S12, S16 |
| **SourceChip** | Small chip naming a clip's source, opens a picker | | S13, S14 |

**Data display**
| Component | Purpose | Used by |
|---|---|---|
| **SessionCard** | Library/home card: thumbnail, title, score, metadata, StatusPills; compact and full variants | S03, S08 |
| **ScoreboardCard** | Set-by-set table with WinBadge, tie-break notation, duration | S09 |
| **WinBadge** | "WIN" chip (chartreuse, forest text) | S09 |
| **TrendCard** + **TrendChart** | Value, delta in percentage points, Swift Charts line with markers, Audio Graph, table fallback | S03, S16, S18 |
| **MomentumChart** | Rolling 10-point balance with set dividers, pattern + tint fills | S09 |
| **ButterflyStatList** | Two-player stat rows with fractions | S09 |
| **InsightCard** / **FocusCard** | Kicker + headline + evidence + chevron | S09, S12, S13 |
| **EvidenceRow** | Big fraction + label + "Watch evidence" | S15 |
| **DrillRow** | Numbered, expandable drill row with art | S15 |
| **MilestonePanel** | Forest strip with a symbol and a two-part figure | S16 |
| **MetricCard** | Titled metric with mini visual and chevron | S16 |
| **GoalRow** / **GoalEditor** | Goal with progress ring and text status; editor sheet | S16 |
| **SetupComparisonCard** | Metric per equipment setup with sample sizes and association caption | S16 |
| **HeadToHeadCard** | Record vs an opponent | S09 |
| **StageTimeline** | Vertical stage list with independent states and values | S07, S09 |
| **QueueRow** | Upload item with state line and progress | S19 |
| **StorageBar** | Segmented usage bar with labelled ends | S19, N6 |
| **ProviderRow** | Archive provider status and action | S19 |
| **CapabilityDetail** | N12 content | N12 |

**Court and placement**
| Component | Purpose | Notes | Used by |
|---|---|---|---|
| **CourtGeometry** (JovraCore) | ITF court model in metres (lines, zones, bins) | single source for diagrams, guides and bins | S05, S11, S12, S15 |
| **CourtDiagram** | Top-down court: full, half, service-box variants; depth bands; zone labels | draws from CourtGeometry, scales with width | S11, S12, S15, S16 |
| **CourtMarker** | In (filled circle), Out (triangle), Needs review (ring), Bookmark (diamond), Unscored (square outline) | shape-first, colour second | S10, S11, S12 |
| **PerspectiveCourtGuide** | Framing overlay drawing the projected court from four corners | | S05 |
| **CornerHandle** + **Loupe** | Draggable 44 pt corner brackets with a 2× magnifier | adjustable for VoiceOver | S05, S11 entry, S12 marks |
| **CourtHeroArt**, **ModeArt**, **RacketArt**, **SpoolArt** | Vector illustrations replacing generated photography | decorative, hidden from VoiceOver | S01, S04, S17, S18 |

**Video, capture and review**
| Component | Purpose | Notes | Used by |
|---|---|---|---|
| **VideoSurface** | `AVPlayerLayer` host with overlay slots, poster, missing-file state | | S10, S12, S13, S14, N1, N10 |
| **VideoScrim** | Top/bottom gradient for legibility over video | solid under Increase Contrast | S05, S06, S10 |
| **ScoreboardOverlay** | Live (ivory) and replay (dark) score overlays with server indicator | derived from `MatchState` only | S06, S10 |
| **SampleBadge** / **FixtureBadge** | "Sample video (synthetic)", "Simulator fixture camera" chips over video | | S06, S10, S12, S05 |
| **EventTimeline** | Whole-session timeline with shape-coded markers, GapChips, adjustable for VoiceOver | | S10 |
| **GapChip** | "+0:42" collapsed-gap chip | | S10/N7 |
| **JogStrip** | Frame-quantized scrubber, ≥48 pt, chase-time seeking | never at the bottom edge | S10, S13, S14, S12 marks |
| **FrameReadout** | "f 46,000 · 12:46.67 · 60 fps" | monospaced | S10 |
| **TransportBar** | Rate menu, frame step, play, fifth slot | hold-to-repeat | S10, S14 |
| **PointCard** + **OutcomeSegment** | Point context, status, two equal winner buttons with Suggested/dashed state | | S10 |
| **SwipeReviewCard** + **ReviewActionBar** | Fast Point Review deck card and its button equivalents | VoiceOver custom actions | N1 |
| **CheckpointPad** + **CountStepper** | Changeover game entry | 64 pt steppers | N2 |
| **DualSyncTimeline** | Two linked scrub rows with sync line and Align/Locked states | | S14 |
| **AnnotationLayer** + **DrawToolbar** | Editable shapes with frame-range lifetime | Pencil-only on iPad | S10, S13, S14 |
| **VoiceNoteButton** | Record/play pinned voice notes | | S14 |
| **PoseOverlay** | Confidence-thresholded joints and wrist path with the "2D pose estimate" chip | no angles | S13 |
| **KeyMomentStrip** | Named key-moment thumbnails with set/clear | | S13 |
| **ReviewRow** + **ReviewStatusButton** | Checklist row with "Review / Looks good / Work on it" | | S13 |
| **GuidanceSheet** + **ChecklistRow** | Framing guidance and pre-flight checks | | S05, N8 |
| **PreflightStrip** | Compact pre-flight chips | | S04 |
| **FormatPill** | Camera format menu over video | | S05 |
| **RecordingStatusPill** | "● REC 12:46" / "Paused" | | S06 |
| **BatteryPill** | Battery level, charging and Low Power | | S06 |
| **SaveHeartbeatLabel** | "Video saved on this iPhone · 2 s ago" | | S06, N9 |
| **HeatBanner** | Heat/battery/storage warnings with detail | | S06 |
| **ScorePad** | Point buttons and Undo during recording | 64 pt | S06 |
| **CaptureControlButton** | Ring buttons (Mark point, Pause) and the Stop disc | 64–76 pt | S06 |
| **CourtModeView** | N9 black recording status screen | | S06/N9 |
| **MicExplainerSheet** | One-time microphone explanation before the system prompt | | S05 |

**Inputs and equipment**
| Component | Purpose | Used by |
|---|---|---|
| **ChoiceSegment** | Two/three large icon+text options (stacks at AX sizes) | S02 |
| **GoalChip** | Multi-select chip with check (max-selection aware) | S02 |
| **ModeRow** | Selectable mode card with art and radio | S04 |
| **SourceTile** | Import source tile | S07 |
| **ImportItemCard** | Selected import with metadata and duplicate state | S07 |
| **SearchField** | Library search | S08 |
| **ToggleRow** | Title + description + toggle | S19, S20, N3, N4, N5 |
| **EquipmentHeroCard**, **EquipmentRow**, **TagPill** | Racket hero, gear rows, string pills | S17 |
| **RacketSelectorCard**, **StringSetupCard**, **TensionField**, **RatingSlider**, **InventoryRow** | String journal pieces (tension shows entered value + converted secondary) | S18 |
| **RetentionEditor** | Post-backup retention choices | S19 |

### 5.3 Token additions

**Colour roles** (add to `ColorRole`; every text role joins the 4.5:1 contrast test, every graphic role a 3:1 test
against its background, in light, dark and Increase Contrast):
| Role | Light | Dark | Use |
|---|---|---|---|
| `recording` | #D63A2E | #E5483B | REC dot, Stop disc (graphic; ≥3:1 on forest and on video scrim) |
| `onRecording` | #FFFFFF | #FFFFFF | Stop glyph |
| `videoScrim` | black 0→55% gradient | same | legibility over video (opaque forest under Increase Contrast) |
| `overlaySurface` | forest at 88% | forest at 88% | chips and panels over video (100% under Increase Contrast) |
| `courtSurface` | #123C33 | #123C33 | diagram fill (forest panel) |
| `courtLine` | ivory | ivory | diagram lines |
| `markerIn` / `markerInOutline` | chartreuse / forest | same | In markers |
| `markerOut` | clay #C47752 | #D98B66 | Out triangles (graphic only, ≥3:1 on courtSurface) |
| `positiveFill` | #E7EFD3 | #1F4A3B | positive InfoCard / safe card background |
| `attentionFill` | #F6E3D8 | #4A2E22 | attention banners and "Needs review" pill background |
| `chartLine`, `chartArea`, `chartGrid` | forest, chartreuse 22%, separator | ivory, chartreuse 22%, separator | TrendChart, MomentumChart |
| `destructiveInk` | = `attentionInk` | = `attentionInk` | "Delete…" titles (already contrast-tested) |

**Type** (add to `Font`): `jovraScore` (`.title2` bold, monospaced digits; scoreboards), `jovraTimecode` (`.callout`
monospaced digits; time and frame readouts), `jovraRecTimer` (64 pt scaled relative to `.largeTitle`, monospaced
digits; court mode), `jovraDrillNumber` (= `jovraMetric`, secondary ink).

**Metrics** (add): `HitTarget.capture = 64`, `HitTarget.stop = 76`, `Radius.sheet = 28`, `Radius.pill = .infinity`
(capsule), `VideoMetrics.jogStripHeight = 48`, `VideoMetrics.timelineToJogGap = 16`.

**Motion and haptics** (new `Motion` namespace): `Motion.standard` (snappy 0.25 s), `Motion.reveal` (easeOut 0.2 s),
both resolving to `nil` under Reduce Motion through one helper; haptics `selection` (mode/segment changes), `success`
(Mark point, Save), `warning` (heat rung, low storage).

---

## 6. Open questions for the lead

1. **Sign in with Apple has no function in v1.** With no server (D2, ADR-0002) it can only pre-fill a name and store a
   local identifier, and Apple's token revocation on account deletion needs a server-side client secret (hard rule 5
   forbids one in the client). This spec keeps the button optional and local-only, with "Delete all JOVRA data" plus
   instructions to stop using Apple sign-in in iOS Settings. Recommendation: hide it behind a build flag until a
   feature needs an identity, and drop "Continue with Apple" from S01 in v1. Needs a decision before the S01 ticket.
2. **Photography.** The generated photos are concept art without usage clearance and several carry marks; v1 ships
   vector art and the player's own video frames. Commissioned or licensed photography is Jon's call.
3. **Microphone prompt placement (D5).** Read here as the first entry to framing (S05), after camera access, so that
   recording starts instantly when the player taps Start. If "first capture" means the Start tap, move the sheet.
4. **Tab roots not drawn in the references.** Insights = S15 with an Explore list; Profile = N11 hub. Alternative: a
   separate Insights hub with S15 pushed from it.
5. **Thresholds to tune on hardware**: framing guidance (§S05 table), practice-rule thresholds (S15), heat ladder
   timings, low-battery and low-storage warnings, trend minimums (S16). Each lives in one constants type so tuning is a
   one-line change.
6. **Share Pack Drive links** depend on the `drive.file` permissions spike (technical-feasibility §13); zip delivery
   ships regardless.
7. **Home "First serves in" scope** is the latest match (so the tile and the fixture agree); a pooled 4-week value would
   read 59% (135 of 230) for the fixture and differ from S09. Confirm.

---

## Section list

S01 Welcome · S02 Player onboarding · S03 Home · S04 Session setup · S05 Court framing and calibration · S06 Live
capture · S07 Import and processing · S08 Session library · S09 Match overview · S10 Smart replay and point correction ·
S11 Shot placement · S12 Serve Lab · S13 Stroke Lab · S14 Video comparison · S15 Coaching plan (Insights home) · S16
Progress · S17 Racket Vault · S18 String journal · S19 Storage and backup · S20 Settings and privacy · N1 Fast Point
Review deck · N2 Changeover checkpoint entry · N3 Share Pack sheet · N4 Consent, competition and junior-parent mode ·
N5 Diagnostics · N6 Space Saver · N7 Rally-only playback controls · N8 Pre-flight checklist · N9 Court mode and the heat
ladder · N10 Highlight reel builder · N11 Profile hub · N12 Capability detail sheet.
