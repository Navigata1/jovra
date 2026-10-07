# JOVRA iOS v1 — ticket DAG

Generated from `docs/spec/tickets.json` (the source of truth). T01 is GitHub issue #1, the foundation. Every other ticket is transitively blocked by T01. Blockers are direct edges after transitive reduction. Depth counts from T01.

62 tickets (T02–T63): 29 L, 30 M, 3 S. All 389 user stories are covered.

| ID | Title | Blocked by | Size | Depth | Screens |
|---|---|---|---|---|---|
| T01 | Foundation: app shell, design system, JovraKit packages, CI (issue #1) | — | — | 0 | — |
| T02 | Contract completion: every v1 session field, registry entries, sample media manifest and convention-based fixture plumbing | T01 | M | 1 | — |
| T03 | Contracts in Swift: document models, canonical JSON, pct, units, capability registry and the conformance harness | T02 | L | 2 | — |
| T04 | Scoring engine: event-log resolution, rules fold, conflicts, modes and the recalculation diff | T03 | L | 3 | — |
| T05 | Stats engine, JSON and CSV data export, and pooled trends | T04 | L | 4 | — |
| T06 | UI-test harness, launch configuration, localization and copy lint, Info.plist and entitlements, and the iOS 18 target | T01 | M | 1 | — |
| T07 | Navigation, typed routes and sheets, deep links, permissions center and the service-registration seam | T06 | M | 2 | — |
| T08 | Session store: single-writer document store, state facets, index, trash, migration and MediaLibrary custody | T03 | L | 3 | — |
| T09 | Sample library: eight sample sessions, equipment and practice plan, install, reset and remove, and the sample-scope rule | T08 | M | 4 | — |
| T10 | Media fixtures: frame-counter clips, fixture-camera clip, import fixture set and the benchmark harness | T01 | M | 1 | — |
| T11 | Synthetic sample video, practice clips and the benchmark corpus with the registry-consistency gate | T03, T10 | L | 3 | — |
| T12 | Design-system extensions: state components, provenance and sample badges, fraction popover, capability detail and hero art | T03, T06 | L | 3 | — |
| T13 | Court geometry, 4-tap calibration maths and the court diagram components | T11, T12 | L | 4 | 05-court-calibration, 11-shot-map, 12-serve-lab |
| T14 | Playback core: frame-accurate player, video surface, jog strip and transport | T10, T12 | M | 4 | 10-smart-replay |
| T15 | Capture engine: segment pipeline, write-ahead journal, fixture camera and device budget | T03, T10 | L | 3 | — |
| T16 | Crash recovery: RecoveryScanner, torn segments, gap reports and media-services reset | T15 | M | 4 | — |
| T17 | Capture route and recording screen through the simulator fixture camera | T07, T08, T12, T16 | L | 5 | 06-live-capture |
| T18 | Welcome, three-step onboarding, profile hub and demo entry | T07, T09, T12 | M | 5 | 01-welcome, 02-player-onboarding |
| T19 | Home dashboard: greeting, stat tiles, latest session, weekly trend and next-step row | T05, T07, T09, T12 | M | 5 | 03-home |
| T20 | Session library: independent status facets, search, Trash and quarantine, plus the record-to-library walking skeleton | T07, T09, T12, T15 | L | 5 | 08-session-library |
| T21 | Session setup: modes, players, formats, doubles order, camera presets and the pre-flight strip | T04, T07, T08, T12, T15 | L | 4 | 04-session-setup |
| T22 | Match overview: scoreboard, stats with denominators, momentum, point history and head-to-head | T05, T09, T21 | L | 5 | 09-match-overview |
| T23 | Court framing and 4-corner calibration with the live checklist and microphone explainer | T13, T17, T21 | L | 6 | 05-court-calibration |
| T24 | Live manual scoring, Mark point, bookmark notes, changeover checkpoints and hands-free marking | T04, T17 | M | 6 | 06-live-capture |
| T25 | Device budget during capture: heat ladder, court mode, low battery and low storage | T17 | M | 6 | 06-live-capture |
| T26 | Import from Photos and Files with per-file results and duplicates | T07, T08, T10, T12 | M | 4 | 07-import-processing |
| T27 | Processing queue, background scheduling and the processing screen | T07, T08, T12, T15 | M | 4 | 07-import-processing |
| T28 | Smart replay: event timeline, scoreboard overlay, point card and one-tap winner correction | T04, T07, T09, T14 | L | 5 | 10-smart-replay |
| T29 | Point editor: add, split, merge, delete, nudge, outcomes, stroke tags, conflict banners and Rules vs As-played | T22, T28 | L | 6 | 10-smart-replay, 09-match-overview |
| T30 | Fast Point Review deck | T04, T07, T09, T14 | M | 5 | N1-fast-point-review |
| T31 | Checkpoint auto-fill: CheckpointSolver, 'Score this match' and the checkpoint-conflict banner | T30 | M | 6 | N1-fast-point-review, 09-match-overview |
| T32 | Rally segmentation core and rally-only composition | T03, T10 | M | 3 | — |
| T33 | Rally-only playback in replay with visible gaps | T28, T32 | S | 6 | 10-smart-replay |
| T34 | Audio hit detection and automatic point suggestions, benchmark-gated | T11, T27, T32 | L | 5 | 07-import-processing, 10-smart-replay |
| T35 | Camera-moved detection and line-snap corner assist | T23 | M | 7 | 05-court-calibration |
| T36 | Clip export, Save original and per-session data export | T05, T28 | L | 6 | 10-smart-replay |
| T37 | Condensed match export and the highlight reel with burned-in score | T32, T36 | L | 7 | N10-highlight-reel |
| T38 | Share Pack for coach, opponent and doubles partner | T37 | L | 8 | N3-share-pack |
| T39 | On-device face blur for exports | T36 | S | 7 | 10-smart-replay, N3-share-pack |
| T40 | Sample analysis content: stroke tags, placements, calibrations, serve marks, swing key moments and a comparison | T09, T11 | M | 5 | — |
| T41 | Shot placement map with manual bounce marking | T07, T13, T14, T40 | M | 6 | 11-shot-map |
| T42 | Stroke Lab with key moments, contact strip and on-demand 2D pose | T07, T14, T40 | L | 6 | 13-stroke-lab |
| T43 | Serve Lab: serve stats by side, placements and the manual-assisted speed estimate | T05, T07, T13, T14, T40 | L | 6 | 12-serve-lab |
| T44 | Serve key moments, toss-to-contact timer and toss-consistency overlay | T42, T43 | M | 7 | 12-serve-lab |
| T45 | Compare two recordings with manual contact sync and overlay | T07, T14, T40 | L | 6 | 14-video-comparison |
| T46 | Annotations: drawing tools, frame-range lifetime, voice and text notes, and replay Draw mode | T28, T45 | L | 7 | 14-video-comparison, 10-smart-replay |
| T47 | Insights: evidence-linked practice plan and the drill session | T05, T07, T09, T12 | L | 5 | 15-coaching-plan |
| T48 | Progress: pooled trends, milestones, review completion and practice goals | T05, T07, T09, T12 | M | 5 | 16-progress |
| T49 | Racket Vault and String Journal | T07, T09, T12 | L | 5 | 17-racket-vault, 18-string-journal |
| T50 | Equipment links: setup gear row, restring reminders, 'String broke' and the setup association | T21, T48, T49 | M | 6 | 04-session-setup, 18-string-journal, 16-progress |
| T51 | Storage screen and the archive state machine with a write-ahead journal | T07, T08, T12, T15 | L | 4 | 19-cloud-archive |
| T52 | Google Drive provider: resumable verified uploads, fake Drive and the upload queue | T51 | L | 5 | 19-cloud-archive |
| T53 | Google Drive sign-in: OAuth with PKCE, Keychain tokens, reconnect and disconnect | T51 | M | 5 | 19-cloud-archive |
| T54 | Archive restore: download, verify, restore offers and archive-only sessions | T18, T20, T26, T52, T53 | M | 6 | 19-cloud-archive, 08-session-library, 07-import-processing, 01-welcome |
| T55 | Space Saver, Free up space, retention and Export video + analysis | T37, T52 | L | 8 | 19-cloud-archive, 08-session-library |
| T56 | Settings: account, permissions, units, appearance, accessibility, notifications and demo content | T07, T09, T12 | M | 5 | 20-settings-privacy |
| T57 | Your data: Export my data, Delete account and data, the diagnostics bundle and the privacy checks | T05, T15, T56 | M | 6 | 20-settings-privacy, N5-diagnostics |
| T58 | Consent, Competition mode and junior-parent mode | T17, T21 | M | 6 | 04-session-setup, 06-live-capture, N4-consent-junior |
| T59 | App Intents and Apple Health workouts | T17, T21, T56 | M | 6 | 20-settings-privacy |
| T60 | Live Activity spike: recording status on the Lock Screen | T15 | S | 4 | — |
| T61 | iPad review layouts and keyboard shortcuts | T22, T28, T30, T45 | M | 7 | 09-match-overview, 10-smart-replay, 14-video-comparison, N1-fast-point-review |
| T62 | Performance smoke with fixed thresholds | T17, T20, T28 | M | 6 | — |
| T63 | Final QA: reference-fidelity aggregation, accessibility matrix, declarations and release registers | T19, T24, T25, T29, T31, T33, T34, T35, T38, T39, T41, T44, T46, T47, T50, T54, T55, T57, T58, T59, T60, T61, T62 | L | 9 | 01-welcome, 02-player-onboarding, 03-home, 04-session-setup, 05-court-calibration, 06-live-capture, 07-import-processing, 08-session-library, 09-match-overview, 10-smart-replay, 11-shot-map, 12-serve-lab, 13-stroke-lab, 14-video-comparison, 15-coaching-plan, 16-progress, 17-racket-vault, 18-string-journal, 19-cloud-archive, 20-settings-privacy |

## Frontier by depth

- d1 (3): T02, T06, T10
- d2 (2): T03, T07
- d3 (6): T04, T08, T11, T12, T15, T32
- d4 (10): T05, T09, T13, T14, T16, T21, T26, T27, T51, T60
- d5 (15): T17, T18, T19, T20, T22, T28, T30, T34, T40, T47, T48, T49, T52, T53, T56
- d6 (17): T23, T24, T25, T29, T31, T33, T36, T41, T42, T43, T45, T50, T54, T57, T58, T59, T62
- d7 (6): T35, T37, T39, T44, T46, T61
- d8 (2): T38, T55
- d9 (1): T63

## Owned areas (for conflict avoidance)

- **T02 contract-completion**: `spec/schemas`; `spec/contracts/capability-registry.v1.json`; `spec/reference/generate_fixtures.py`; `spec/reference/jovra_ref/conformance.py`; `scripts/spec/validate.py`; `spec/fixtures/sample/media-manifest.json`; `spec/README.md`
- **T03 contracts-swift-core**: `ios/Packages/JovraCore/Sources/JovraCore/Contracts`; `ios/Packages/JovraCore/Sources/JovraCore/Percent`; `ios/Packages/JovraCore/Sources/JovraCore/Units`; `ios/Packages/JovraCore/Sources/JovraCore/Capabilities (model and loader)`; `ios/Packages/JovraCore/Tests/JovraCoreTests/Conformance`
- **T04 scoring-engine**: `ios/Packages/JovraCore/Sources/JovraCore/Scoring`; `ios/Packages/JovraCore/Tests/JovraCoreTests/Scoring`
- **T05 stats-export-trends**: `ios/Packages/JovraCore/Sources/JovraCore/Stats`; `ios/Packages/JovraCore/Sources/JovraCore/Export`; `ios/Packages/JovraCore/Sources/JovraCore/Trends`; `spec/reference/jovra_ref (trend module)`; `spec/reference/cases/trend_cases.py`; `spec/fixtures/trend`
- **T06 ui-harness-l10n-plist**: `ios/project.yml`; `ios/Jovra/Resources/Info.plist`; `ios/Jovra/Resources/Jovra.entitlements`; `ios/Config`; `ios/Jovra/Platform/LaunchConfiguration`; `ios/Jovra/Resources/Localization`; `ios/JovraUITests/Support`; `scripts/ios`; `scripts/l10n`; `docs/DEVELOPING.md`
- **T07 navigation-routes-permissions**: `ios/Jovra/App`; `ios/Jovra/Platform/Permissions`; `ios/Jovra/Platform/Preferences`; `ios/Jovra/Platform/DataEraser`; `ios/JovraTests/AppRouterTests.swift`; `placeholder files in every ios/Jovra/Features/* folder (each handed to its feature ticket)`
- **T08 session-store**: `ios/Packages/JovraCore/Sources/JovraCore/SessionStore`; `ios/Packages/JovraMedia/Sources/JovraMedia/Library`
- **T09 sample-library**: `ios/Packages/JovraCore/Sources/JovraCore/SampleContent`; `spec/reference/jovra_ref/sample_match.py (library section)`; `spec/fixtures/sample/library`
- **T10 media-fixtures-benchmark-harness**: `scripts/media (renderer core, frame-counter, fixture-camera and import sets)`; `spec/fixtures/media (ground truth and hashes)`; `spec/schemas/ground-truth.schema.json`; `spec/schemas/benchmark-record.schema.json`; `ios/Packages/JovraMedia/Package.swift`; `ios/Packages/JovraMedia/Sources/JovraBenchmark`
- **T11 synthetic-sample-video-corpus**: `scripts/media (sample, practice and benchmark corpus scenes)`; `spec/fixtures/media/sample`; `spec/benchmarks/corpus`; `ios/Jovra/Resources/SampleMedia (bundling step)`; `ios/Packages/JovraMedia/Tests/JovraBenchmarkTests/RegistryConsistency`
- **T12 design-system-extensions**: `ios/Jovra/DesignSystem/Tokens`; `ios/Jovra/DesignSystem/Components`; `ios/Jovra/DesignSystem/Art`; `ios/JovraTests/ColorRoleContrastTests.swift`
- **T13 court-calibration-diagrams**: `ios/Packages/JovraCore/Sources/JovraCore/Court`; `spec/reference/cases/calibration_cases.py`; `spec/fixtures/calibration`; `ios/Jovra/DesignSystem/Court`
- **T14 playback-core**: `ios/Packages/JovraMedia/Sources/JovraMedia/Playback`; `ios/Jovra/DesignSystem/Video`
- **T15 capture-engine**: `ios/Packages/JovraMedia/Sources/JovraMedia/Capture`; `ios/Packages/JovraCore/Sources/JovraCore/CaptureJournal`; `ios/Packages/JovraMedia/Sources/JovraMedia/DeviceBudget`
- **T16 crash-recovery**: `ios/Packages/JovraMedia/Sources/JovraMedia/Capture/Recovery`
- **T17 capture-route-recording**: `ios/Jovra/Features/Capture (route container and Recording)`; `ios/Jovra/Platform/Capture`
- **T18 welcome-onboarding-profile**: `ios/Jovra/Features/Welcome`; `ios/Jovra/Features/Onboarding`; `ios/Jovra/Features/Profile`; `ios/Packages/JovraCore/Sources/JovraCore/Profile`; `ios/Jovra/Platform/AppleSignIn`; `ios/Jovra/Features/Welcome/RestoreOfferSlot (filled by the restore ticket)`
- **T19 home-dashboard**: `ios/Jovra/Features/Home`
- **T20 session-library**: `ios/Jovra/Features/Sessions/Library`; `ios/Jovra/Features/Sessions/Library/ArchiveActionSlot (filled by the restore ticket)`
- **T21 session-setup**: `ios/Jovra/Features/Record`; `ios/Jovra/Features/Record/FormatSheet (reused by the match overview)`; `ios/Packages/JovraCore/Sources/JovraCore/Setup`; `ios/Packages/JovraMedia/Sources/JovraMedia/CaptureFormats`
- **T22 match-overview**: `ios/Jovra/Features/Sessions/MatchOverview`
- **T23 framing-calibration**: `ios/Jovra/Features/Capture/Framing`; `ios/Packages/JovraCore/Sources/JovraCore/Framing`; `ios/Jovra/Features/Calibration (sheet route)`
- **T24 live-scoring-mark-point**: `ios/Jovra/Features/Capture/Scoring`; `ios/Jovra/Platform/HandsFree`
- **T25 device-budget-court-mode**: `ios/Packages/JovraMedia/Sources/JovraMedia/Capture/Thermal`; `ios/Jovra/Features/Capture/CourtMode`
- **T26 import**: `ios/Jovra/Features/Sessions/Import`; `ios/Jovra/Features/Sessions/Import/DriveTileArchiveSlot (filled by the restore ticket)`; `ios/Packages/JovraMedia/Sources/JovraMedia/Import`
- **T27 processing-queue**: `ios/Jovra/Features/Processing`; `ios/Jovra/Features/Processing/Analyzers`; `ios/Packages/JovraCore/Sources/JovraCore/Processing`; `ios/Jovra/Platform/BackgroundTasks`
- **T28 smart-replay**: `ios/Jovra/Features/Replay (screen, timeline and extension points)`
- **T29 point-editor**: `ios/Jovra/Features/PointEditor`
- **T30 fast-point-review**: `ios/Jovra/Features/PointReview`
- **T31 checkpoint-autofill**: `ios/Packages/JovraCore/Sources/JovraCore/CheckpointSolver`; `spec/reference/cases/checkpoint_cases.py`; `spec/fixtures/checkpoint`; `ios/Jovra/Features/PointReview/Checkpoint`
- **T32 rally-core**: `ios/Packages/JovraCore/Sources/JovraCore/Rally`; `spec/reference/cases/rally_cases.py`; `spec/fixtures/rally`; `ios/Packages/JovraMedia/Sources/JovraMedia/Playback/RallyComposition`
- **T33 rally-only-playback**: `ios/Jovra/Features/Replay/RallyOnly`
- **T34 audio-hit-detection**: `ios/Packages/JovraMedia/Sources/JovraMedia/Analysis/Audio`; `spec/benchmarks/audio`; `spec/contracts/capability-registry.v1.json (status values only)`; `ios/Jovra/Features/Processing/Analyzers/Audio`
- **T35 camera-moved-line-snap**: `ios/Packages/JovraMedia/Sources/JovraMedia/Analysis/Vision`; `spec/benchmarks/vision`; `spec/contracts/capability-registry.v1.json (status values only)`; `ios/Jovra/Features/Capture/Framing/Assist`
- **T36 clip-export**: `ios/Packages/JovraMedia/Sources/JovraMedia/Export`; `ios/Jovra/Features/Export`
- **T37 condensed-highlight-reel**: `ios/Jovra/Features/Highlights`; `ios/Packages/JovraMedia/Sources/JovraMedia/Export/Highlight`; `ios/Packages/JovraMedia/Sources/JovraMedia/Export/Condensed`
- **T38 share-pack**: `ios/Jovra/Features/SharePack`; `ios/Packages/JovraCore/Sources/JovraCore/SharePack`; `ios/Jovra/Resources/SharePackViewer`
- **T39 face-blur**: `ios/Packages/JovraMedia/Sources/JovraMedia/Analysis/FaceBlur`; `ios/Jovra/Features/Export/PrivacyOptions`; `spec/contracts/capability-registry.v1.json (status values only)`
- **T40 sample-analysis-content**: `spec/reference/jovra_ref/sample_match.py (analysis section)`; `spec/fixtures/sample/analysis`; `ios/Packages/JovraCore/Sources/JovraCore/SampleContent/Analysis`
- **T41 shot-placement**: `ios/Jovra/Features/Insights/ShotMap`; `ios/Packages/JovraCore/Sources/JovraCore/Placement`
- **T42 stroke-lab-pose**: `ios/Jovra/Features/Insights/StrokeLab`; `ios/Packages/JovraMedia/Sources/JovraMedia/Analysis/Pose`; `ios/Packages/JovraCore/Sources/JovraCore/StrokeLab`; `ios/Packages/JovraCore/Sources/JovraCore/KeyMoments`
- **T43 serve-lab-speed**: `ios/Jovra/Features/Insights/ServeLab`; `ios/Packages/JovraCore/Sources/JovraCore/ServeLab`; `spec/reference/cases/serve_speed_cases.py`; `spec/fixtures/serve-speed`
- **T44 serve-key-moments**: `ios/Jovra/Features/Insights/ServeLab/KeyMoments`
- **T45 compare-recordings**: `ios/Jovra/Features/Compare`; `ios/Packages/JovraCore/Sources/JovraCore/Compare`; `ios/Packages/JovraMedia/Sources/JovraMedia/Playback/DualPlayback`; `spec/reference/cases/compare_cases.py`; `spec/fixtures/compare`
- **T46 annotations-draw-mode**: `ios/Jovra/DesignSystem/Annotation`; `ios/Jovra/Features/Compare/Annotations`; `ios/Jovra/Features/Replay/DrawMode`
- **T47 practice-plan-drills**: `ios/Jovra/Features/Insights/Plan`; `ios/Jovra/Features/Insights/DrillSession`; `ios/Packages/JovraCore/Sources/JovraCore/Practice`; `ios/Jovra/Resources/Drills`
- **T48 progress-goals**: `ios/Jovra/Features/Insights/Progress`; `ios/Jovra/Features/Insights/Progress/AssociationSlot (filled by the equipment-links ticket)`; `ios/Packages/JovraCore/Sources/JovraCore/Progress`
- **T49 racket-vault-string-journal**: `ios/Jovra/Features/Equipment`; `ios/Packages/JovraCore/Sources/JovraCore/Equipment`
- **T50 equipment-links**: `ios/Jovra/Features/Record/GearRow (slot provided by session setup)`; `ios/Jovra/Features/Equipment/Reminders`; `ios/Packages/JovraCore/Sources/JovraCore/Equipment/Association`; `ios/Jovra/Features/Insights/Progress/AssociationSlot`
- **T51 storage-archive-core**: `ios/Packages/JovraCore/Sources/JovraCore/Archive`; `ios/Jovra/Features/Storage (screen and section slots)`
- **T52 drive-upload**: `ios/Packages/JovraCore/Sources/JovraCore/Archive/GoogleDrive`; `ios/Jovra/Features/Storage/Queue`; `spec/reference/cases/archive_cases.py`; `spec/fixtures/archive`
- **T53 drive-auth**: `ios/Jovra/Platform/DriveAuth`; `ios/Jovra/Platform/Keychain`; `ios/Jovra/Features/Storage/Account`
- **T54 archive-restore**: `ios/Jovra/Features/Storage/Restore`; `ios/Jovra/Features/Welcome/RestoreOfferSlot`; `ios/Jovra/Features/Sessions/Library/ArchiveActionSlot`; `ios/Jovra/Features/Sessions/Import/DriveTileArchiveSlot`
- **T55 space-saver-retention**: `ios/Jovra/Features/Storage/SpaceSaver`; `ios/Jovra/Features/Storage/Retention`; `ios/Packages/JovraMedia/Sources/JovraMedia/Library/Removal`
- **T56 settings**: `ios/Jovra/Features/Settings`; `ios/Jovra/Features/Settings/HealthSlot (filled by the App Intents and Health ticket)`; `ios/Jovra/Features/Settings/DataSlot (filled by the data and privacy ticket)`
- **T57 data-privacy-diagnostics**: `ios/Jovra/Features/Settings/DataSlot`; `ios/Jovra/Features/Diagnostics`; `ios/Jovra/Platform/Diagnostics`; `ios/Jovra/Resources/PrivacyInfo.xcprivacy`; `scripts/ci (privacy checks)`
- **T58 consent-competition-junior**: `ios/Jovra/Features/Consent`; `ios/Packages/JovraCore/Sources/JovraCore/Consent`; `ios/Jovra/Features/Record/ConsentRow (slot provided by session setup)`; `ios/Jovra/Features/Profile/RecordingRules`
- **T59 app-intents-health**: `ios/Jovra/Platform/AppIntents`; `ios/Jovra/Platform/Health`; `ios/Jovra/Features/Settings/HealthSlot`
- **T60 live-activity-spike**: `docs/spikes/live-activity.md`; `evidence/ios (spike folder)`
- **T61 ipad-review-layout**: `ios/Jovra/DesignSystem/Layout`; `ios/Jovra/App/KeyboardCommands`; `regular-width adapter files inside Features/Sessions/MatchOverview, Features/Replay, Features/Compare, Features/PointReview`
- **T62 performance-smoke**: `ios/JovraUITests/Performance`; `ios/JovraTests/Performance`; `.github/workflows (nightly performance job)`
- **T63 final-qa**: `ios/JovraUITests/QA`; `evidence/ios (final QA folder)`; `docs/qa`

## Notes

FINAL SET: 62 tickets, T02-T63, on top of T01 (issue #1). Sizes: 29 L, 30 M, 3 S. Every blocker comes earlier in the list, the graph is acyclic, every ticket reaches T01, and all 389 user stories are covered. Blockers were transitively reduced, so each ticket lists only its direct blockers. Each what_to_build ends with "Why blocked:", one reason per remaining edge. The builder script checks these properties.

COUNT: this is above both the 25-35 target and the critics' suggested 48-50. The binding constraint is one fresh context window per ticket, so I applied every requested split and added three more:
- T02 (contract completion) and T03 (Swift contracts) are separate, because the contract-completion scope made the old T02 too big.
- Settings is split into T56 (settings) and T57 (your data, diagnostics and privacy checks).
- The Live Activity spike (T60) and the performance smoke (T62) are their own tickets.
Sizing heuristic for future tickets: a ticket is too big if it has more than about 12 stories, or more than 2 new modules plus a screen, or a new reference fixture kind plus a Swift port plus UI. T18, T21, T22 and T29 still carry 13-18 stories, but those are copy-level stories on one screen or one sheet.

PREFACTORS (horizontal by design): T02 contracts, T03 Swift contracts, T04 scoring, T05 stats, T06 harness, T07 router, T08 store, T09 sample library, T10 media fixtures, T11 synthetic media, T12 design system, T13 court, T15 capture engine, T16 recovery, T32 rally core, T40 sample analysis content.
WALKING SKELETON: T20 (Library) records through CaptureEngine and FixtureCamera headlessly, lists the session and opens replay, at depth 5.

FRONTIER BY DEPTH (from T01):
- d1: T02, T06, T10
- d2: T03, T07
- d3: T04, T08, T11, T12, T15, T32
- d4 (10): T05, T09, T13, T14, T16, T21, T26, T27, T51, T60
- d5 (15): T17, T18, T19, T20, T22, T28, T30, T34, T40, T47, T48, T49, T52, T53, T56
- d6 (17): T23, T24, T25, T29, T31, T33, T36, T41, T42, T43, T45, T50, T54, T57, T58, T59, T62
- d7: T35, T37, T39, T44, T46, T61
- d8: T38, T55
- d9: T63
Weighted critical path (S=1, M=2, L=3) is 25: T01, T02, T03, T08, T09, T28, T36, T37, T38, T63.

CONFLICT AVOIDANCE (rules written into the tickets):
- Contracts:
  - T02 adds every missing v1 session field as optional, pre-seeds lineSnap and faceBlur at disabled, adds a sample media manifest, and switches fixture plumbing to convention-based discovery.
  - After T02, schema gaps go into a contract-fix PR. New fixture kinds are new files only (cases module, schema, Swift runner file).
  - T03 owns the CapabilityRegistry model. Fixtures dispatch by kind, and the pending allow-list holds kinds.
- Project and build:
  - T06 lands every Info.plist key, both entitlements and the Drive xcconfig chain. After that, only a possible Live Activity follow-up touches project.yml.
  - T10 is the only ticket that edits the JovraMedia package manifest.
  - String Catalogs are one table per owned area, with a CI ownership check.
- App composition:
  - T07 declares every route and sheet, typed, with payloads, and creates the placeholders.
  - T07 also sets up per-service environment-key registration (nobody edits the app entry point), the full AppPreferences key set, and the DataEraser registry.
  - Consequences: capture reads its preferences and Settings renders them with no edge between those tickets, and erasers register from their own stores.
- Store:
  - T08 is a package-only single-writer actor with batch append.
  - Capture high-frequency state lives in the journal behind a RecordingSink.
  - After T08, store gaps go into a store-fix PR.
- Named slots, each filled by exactly one ticket:
  - Capture route (T17): framing slot (T23), score overlay and MarkPointAction (T24), court mode (T25), CaptureConfig hooks (T58).
  - Session setup (T21): consent row (T58), gear row (T50).
  - Replay (T28): transport slot 5 (T33), timeline decorations (T33, T36), overlay slot (T46 drawing, T42 pose), toolbar presenters.
  - Restore slots (T54): Welcome (T18), Library card (T20), Import Drive tile (T26).
  - Storage screen sections (T51): queue (T52), account (T53), Manage storage (T55).
  - Settings Health (T59) and Your data (T57).
  - Progress association card (T50).
  - ExportOptions privacy slot (T39).
- Calibration and String broke are typed sheet routes, so replay and Serve Lab present them without depending on T23 or T50. T63 verifies these entry points end to end.
- Remaining shared touch points:
  - Registry status values: T34, T35, T39 (only alongside a benchmark record where the gate rule needs one).
  - The sample generator: T09, then T40, in separate sections and in sequence.
  - The KeyMoments module: owned by T42 and reused by T44.
  - ios/Jovra/App/KeyboardCommands: a new subfolder created by T61.

CRITIQUES APPLIED: all of them, except those listed under rejections below. The main changes:
- Splits:
  - T06 into T06 and T07, T05 into T08 and T09, T08 into T10 and T11.
  - T14 into T15, T16 and T17 (DeviceBudget sits in the engine; the low-storage stop moved to T25).
  - T12 into T19 and T20, T19 into T26 and T27, T22 into T30 and T31, T23 into T32 and T33.
  - T27 into T37, T38 and T39 (the condensed export moved out of clip export).
  - T29 into T43 and T44 (the speed estimator moved from court into T43), T31 into T45 and T46, T32 into T47 and T48.
  - T33 into T49 and T50 (the association card moved here), T34 into T51, T52 and T53, T35 into T54 and T55.
  - The old T38 into T59 and T60.
- New tickets: T40 (sample analysis content) and T62 (performance smoke).
- Fixes inside tickets:
  - T22 honesty fix: the demo's flagged points are manual/needsReview, so the demo shows the Manual badge with '8 need review'. The Estimated caption is proven by a separate fixture.
  - Fixed numeric tolerances in T13, T41 and T43, and a held-out-seed benchmark corpus with at least 2 h of no-nudge footage.
  - ACs that previously could not fail now assert textClipped; the sum note gets a 33/33/33 fixture; the jog strip gets 48 pt and 16 pt checks; the proxy has a timing AC.
  - Per-ticket only-testing evidence, with a reviewer line required per side-by-side pair.
  - Copy lint for banned claims, the StoreKit/D2 check, mailto checks scoped to shipped surfaces, and audio-off defaults on every export path.
  - Pinch zoom, captions, stroke tags, the drillSession route, guest/demo exit, warming copy and pause-order ACs.
  - QA additions: device-test checklist, capability status report and offline sweep.

CRITIQUES REJECTED OR ADAPTED, WITH REASONS:
1. Moving Toast, UndoBar and FractionPopover out of the design system: rejected. Each has at least two consumers:
   - Toast: replay, editor, export, review deck.
   - UndoBar: Library delete-undo and the review deck.
   - FractionPopover: Home, overview, shot map, Serve Lab.
   SessionCard did move to Library, as suggested.
2. Splitting the capability registry into one file per capability: rejected. Pre-seeding already reduces each later PR to a one-line status change, and a per-file split would change the shared contract shape that Android consumes.
3. Optional split of court maths from court views: not taken. Once the speed estimator moved to Serve Lab, T13 is a coherent L ticket whose two halves serve the same consumers.
4. Making CheckpointSolver (T31) blocked by live scoring (T17): rejected. The solver runs on checkpoint events in fixture logs and never needs the entry UI.
5. Three-way T06 split: adapted to two tickets. PermissionsCenter is small, and every consumer also needs the router.
6. Walking skeleton through the capture UI: adapted. Library (T20) records headlessly through the engine, so the Library does not wait for the capture UI.
7. Capture engine split: adapted. I combined the two critics' proposals: engine package (with DeviceBudget and the CaptureActivity signal), recovery package, and capture route UI. The interruption sheet stays in the capture route.
No lead decision (D1-D12) had to change for a hard technical reason. One risk is noted in T06: if the Sign in with Apple and HealthKit entitlements block an unsigned simulator build, they move behind a device-only configuration and the PR records why.

OPEN DECISIONS FOR THE LEAD (each is written into its ticket as "lead to confirm"):
1. T11: the bundled sample media budget is set at 60 MB, with excerpt mode as the fallback.
2. T19: Home's first-serve tile is scoped to the latest match with a 'Latest match' caption (screen spec Q7). This conflicts with story 32, which asks for pooling (pooled it would read 59%, 135/230).
3. T43: 'Fastest marked serve' follows screens.md S12: it shows the estimator's output over the 12 sample serve marks and is expected to read 104 mph (94–114), never a typed constant. This replaces the draft's "sample-only tile", and story 23's framing should be amended to match.
4. T43: 'Review 12 serves' opens the S12 serve list with Edit marks, not the review deck; story 240 should be amended to match.
5. T18: Continue with Apple sits behind a build setting (Q1).
6. T23: the microphone explainer appears at first framing (Q3).
7. T47: the Insights root is the practice plan plus an Explore list (Q4).
8. T12: hero art is vector only, with no photographs (Q2). This needs Jon's confirmation.
9. T62: the performance thresholds are fixed (cold launch at most 1.5 s, refold at most 50 ms, seek p95 at most 200 ms, hitch ratio at most 5 ms/s, recording memory at most 300 MB and growth under 20 MB). Changing them needs lead approval.
10. D1 sequencing: bump the deployment target to 18.0 inside T01 if T01 is still open; otherwise it is T06's first commit. ios/project.yml still says 17.0.

OUT OF THIS DAG: Studio, the backend and identity (ADR-0014 to ADR-0022), Watch, Android, P1-08 and P1-25. A shipped Live Activity becomes a follow-up ticket filed only if the T60 spike decides to ship. The expiring Drive share link is a deferred spike recorded in T53's UNVERIFIED register.

UNVERIFIED ITEMS CARRIED IN THE ACCEPTANCE CRITERIA: device capture, iOS 18 runtime, real Google Drive and the share link, real-court analysis accuracy, hands-free buttons, face detection on real footage, and the Live Activity and Smart Stack on device.

ENVIRONMENT NOTE: the foundation worktree path /Users/IDC2.5/jv/.claude/worktrees/t01-foundation does not exist. I read the layout from the main checkout's ios/ folder.
