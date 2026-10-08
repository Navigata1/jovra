# JOVRA Android and Watch v1 — ticket DAGs

Generated from `docs/spec/android-watch-tickets.json` (the source of truth). Android tickets are A01–A99 and watch plus iOS adaptive tickets are W01–W26, each numbered in dependency order; `T`-ids are core iOS tickets (`docs/spec/tickets.md`) and `S`-ids are Studio tickets (`docs/spec/studio-tickets.md`). Blockers are direct edges after transitive reduction; an edge implied through another blocker is named in the ticket text. Depth counts A/W edges only. Labels: `ready-for-agent`, `platform:android|ios|shared`, `track:android|watch|ios-adaptive`, `area:<…>`, and `resource:emulator` on tickets that hold the single JOVRA emulator lease.

125 tickets: 50 L, 69 M, 6 S. Weighted critical path 38: A01 → A04 → A08 → A11 → A15 → A62 → A72 → A79 → A86 → A87 → A88 → A93 → A98 → A99.

## Notes

FINAL SET (2026-10-07): 125 tickets in two linked DAGs. ANDROID A01-A99 (99, track:android) and WATCH + iOS ADAPTIVE W01-W26 (22 track:watch for the Swift JOVRA Room v1 package, watchOS, Wear OS, bridges, commands and the iPhone paired-watch rows, plus 4 track:ios-adaptive: W22, W23, W24, W25). Sizes: 50 L, 69 M, 6 S. Files: docs/spec/android-watch-tickets.json (source of truth) and docs/spec/android-watch-tickets.md; the draft was deleted. Nothing was built or run to produce this plan; every claim in a ticket is a plan until its check passes.

CHECKS RUN BY THE BUILDER (scratchpad scripts): acyclic; every blocker exists (A/W ids, T-ids in docs/spec/tickets.json, S-ids in docs/spec/studio-tickets.json); every internal blocker comes earlier in the list, and A and W ids are each numbered in dependency order; every A/W id named in ticket text exists (screen names such as "screen A10 (Replay)" or "screens A01–A20" are android-v1-spec screen ids, and W61-W72 are watch screen ids; neither is a ticket id); internal edges are transitively reduced, and each removed edge is named in the ticket text as "Implied through other blockers"; no two tickets that can run concurrently own overlapping paths (0 clashes, with module manifests and per-package placeholders treated as owned files). Weighted critical path (S=1, M=2, L=3, A/W only) = 38 (draft: 43): A01-A04-A08-A11-A15-A62-A72-A79-A86-A87-A88-A93-A98-A99. Max depth 14 (draft: 16). Frontier now: A01, A14 (no blockers); W01 as soon as core T03 lands. T09 is now an ancestor of 29 tickets (draft: 88), so the UI spine no longer waits on the iOS sample oracle; T10 is an ancestor of 58, so the iOS lead is asked to schedule T10 (depth 1, after T01 only) early.

STORY COVERAGE: A tickets cite android-v1-spec numbers; all 357 are mapped. Stories 314, 315, 317, 318, 319 and 357 (the phone-side watch bridge) are carried by W10, W20 and W21 and cited in their text, because W user_stories use watch-v1-spec numbering (all 95 mapped). Conditional or partial: 351 is met only when A01 merges behind its ADR gate; 234 sits in A94 behind F-ROOM-STILL (it may close as deferred); 321, 322 and 323 are 'S5, registered not delivered' in A98's register (A86 and A88 are partial); watch stories 55 and 95 are partial on iOS while F-CORE-REVIEW is open (W07 gate row, W26 register). The ios-adaptive tickets have no story numbers.

OWNED-AREA CONVENTIONS: android/<module>/<package>/** means that package directory in the module's main and test source sets plus its own per-package resource file res/values/strings_<package>.xml (A02's lint enforces the prefix). A01 writes every module's build file with every planned Lane A dependency; a missing dependency is a one-line catalog-fix PR. A02 writes every module manifest once (all v1 permissions, foreground-service types, services, providers, shortcuts resource, backup attributes and the watch capability); a missing entry is a one-line manifest-fix PR. A11 declares every route and sheet as <module>/placeholder/<Route>Placeholder.kt; each screen ticket lists the placeholder file it deletes in its owned_areas. Cross-screen additions go through declared slots (Studio entry, gear row, String broke, equipment association, restore offer, multi-angle mark review), each filled by exactly one later ticket. Demo-to-real Studio pairs transfer ownership explicitly (A79 from A72, A80 from A72/A69, A81 from A71, A82 from A68, A83 from A70, A86 and A87 from A67, A96 from A72); each pair is sequential. The 'Paired watch' rows (A51, A64, A66) read a watch-bridge status seam in the composition root; W10 supplies the live adapter. Module seam: only :media references CameraX, Media3 or MediaCodec; it exports the camera preview (A22), the player surface (A21) and QR scanner frames (A90).

CONFORMANCE-KIND MARKERS (decided in A04): a kind with no marker under android/testing/conformance-kinds fails the required android-core job, as the drift guard ADR-0001/ADR-0024 ask for. Before A04 merges, amendment issues are filed on T13, T31, T32, T52, S05-S09, S55 and S56 so each adds a `.pending` marker in the PR that adds its kind, and CODEOWNERS routes the folder to the Android owner.

CORE AND STUDIO BLOCKERS USED (only where a shared or iOS artefact is truly required): T03 (W01, JovraCore canonical JSON writer); T06 and S04 (W03, project.yml); T09 (A07 only: sample oracle; A09, A16, A17, A44-A46 and A51 reach it through A09, A11 does not); T10 (A21, A22, A28); T11 and T34 (A35); T17 and T24 (W07); T31 (A33); T40 (A38); T52 (A50); S05-S07 (A75, A76); S08 and S09 (A77); S15 (W22); S17, S21 and S25 (W23); S19 and S72 (W24); S29 and S71 (W08); S34 (W25); S56 and S58 (A86); S71 (A92); S72 (W21); S73 (A93); S81 (A95). No iOS core or Studio ticket is duplicated: Android ports decided contracts and reads the same fixtures in place.

CROSS-DAG FINDINGS FOR THE LEAD (other owners' files, not fixed here):
1. Studio S68-S72 predate spec/room. S68 defines jovra.room/1 in spec/studio with the superseded guest-key approval code (F-ADR-0017), and S72 sends stills every 5 s that spec/room does not have. W01/W02 build the spec/room package ios/Packages/JovraRoom. Recommendation: close S68 as superseded, re-scope S69 onto JovraRoom (blocked by W02), have S70 pass the authenticated peer to the ledger on every frame (the D1 transport half of F-ROOM-PORTS, which W02 does NOT close), and have S71/S72 carry spec/room records. A92 and W21 carry 'S68-S72 rescope decision' in their gates; no W ticket duplicates S69/S70.
2. watch-v1-spec places the pure watch modules in JovraCore; this plan proposes the separate Foundation-only JovraRoom package with its own room.yml (validate_room.py + swift test on Linux). Lead to confirm.
3. ios/project.yml is edited after T06 and S04 by W03 (JovraWatch targets and the JovraRoom package) and then W14 (the complications extension and app group), each with core-owner review. watchOS 11 is INFERRED.
4. One-line Studio-owned insertions, each reviewed by the Studio owner: W22 in S15's StudioPaneLayout; W24 in the Director layout switch (after S72); W08 in the Lobby (after S71) and in S29's Settings slot.
5. A14 drafts the ADR-0025 §8 pane-policy vectors as new spec/adaptive files with their own adaptive.yml workflow (F-PANE-VECTORS) for the spec/ contracts owner; no existing spec file is edited.
6. W23 files an issue on T61 so the core iPad review layouts delegate to W22's PanePolicy.
7. Open findings and where they gate: F-ADR-0001 + Lane A pins ADR (A01 merge gate); F-ADR-0008 (A49 merge); F-STUDIO-ANDROID (A59, A61, A62 and through them all Studio Android work: built, but no Studio S0/S1 gate claimed while open); F-ROOM-STILL (A94; and A92 before A2 is reported passed); F-ADR-0017 and F-STUDIO-INVITE (A92 before A2 is reported passed); F-QUOTE-CONSENT (A72, A96); F-ADR-0023 pricing ADR (A96 real quotes); F-ROOM-PORTS (Kotlin half closed by A89 + A90; Swift ledger half by W02; Swift transport half needs the S69/S70 rescope); F-CORE-REVIEW (W07 review-count row; watch stories 55 and 95 partial on iOS); F-IOS-ADAPTIVE (W22-W24 labelled 'study, not adopted' until the owners adopt adaptive-screens §4.5; W25 files the gaps).

MACHINE, CONCURRENCY AND GATES: `df -h /` showed 9.6 GiB free while drafting and 32 GiB available when this set was finalized; budgets assume the low end. Every Android ticket records `df -h /` at start (does not start below 8 GB free) and after `./gradlew -p android clean` at the end. Concurrency budget while free space is under 14 GiB: at most 2 Android Gradle tickets, 1 emulator ticket and 1 iOS xcodebuild ticket at once. Emulator use is serialized by A03's avd.sh lease (an mkdir lock under ~/.android/avd/.jovra-lock): `acquire` creates from the installed android-35 google_apis arm64 image only if absent, with the toolchain §7.1 config.ini (4 GB data partition, cold boot, 4 GB RAM, no snapshots), refuses below 6 GB (the ticket then reports its emulator rows 'not run (disk)' and stays open), `release` deletes the AVD when free space is under 8 GB, `delete` refuses while leased, and OlamyPixel is never touched. The 29 emulator tickets carry the label `resource:emulator` (A21, A22, A23, A24, A25, A26, A27, A28, A30, A35, A36, A37, A57, A58, A73, A77, A78, A79, A80, A84, A85, A86, A88, A91, A98, W11, W12, W13, W15); the scheduler runs at most one at a time. Whichever of A21, A22 or A28 runs first creates jovra_phone_p9_api35; A57 creates jovra_compact360_api35; A58 creates the fold and tablet AVDs, and A73 runs after A58 so the two never create them in parallel. JDK 17 only: Robolectric runs locally at sdk=34, and every Roborazzi test is pinned to sdk=34 so local and CI Linux render on the same Robolectric SDK; goldens are recorded by the roborazzi-record workflow_dispatch job and verified in android-unit (G-JDK21 for other SDK 36 runs). The 16 KB alignment check runs on every release APK from A02 on (CameraX is expected to carry .so files; INFERRED until A02 lists them); A43 adds only the `_ps16k` runtime run. Gates named in tickets: G-RESOLVE (A01); G-CORE (A04-A07, A33, A50, A59, A60, A75); G-ROOM (A65, A89 with a room-contracts CI run, W01, W02); G-PANE (A14 contract, A15 Kotlin, W22 iOS); G-16K (A43); G-IMG36 + G-DISK (A24, A54, A56, A58, A73 Android 16 rows, reported 'not run' without the image); G-SDK37 + G-DISK (A99, the last Android ticket, which re-records every golden); G-TARGET37 (A90 stays at target 36); G-WEARIMG + G-DISK (W11, W12, W13, W15 emulator rows); G-WEARPAIR + G-DISK (W10, W17). Physical gates, reported separately and never satisfied by emulator or simulator evidence: Pixel capture (A22, A24, A26, A27), Gate A2 two-phone (A92 device row, W20, W21 device rows; A3b exit for W16/W17), six-device field (A93), G-W-REALPAIR (W07, W10, W16-W21), real Drive (A49), real footage (A35, A85, A88). Every hinge or posture result is labelled 'injected FoldingFeature (window-testing)' or 'emulator posture, pixel_9_pro_fold profile (approximation)'.

CRITIQUE DISPOSITION: adopted - the store split (A08 store, A09 sample install) so T09 leaves the UI spine; the pane-policy split (A14 shared contract with no blockers, A15 Kotlin + scaffolds) with W22 on A14; A18/A20/A30 decoupled (navigation paths tested in A56); A35 no longer waits on A34; A25 depends on A19/A22/A13, not A24; A40/A41 reach their routes; A24 asserts on the store; the Wear bridge split (W09 contract, W10 phone side) so the Wear UI starts after A89; W20 no longer blocked by A92 and A92 closes on its rehearsal; avd.sh lease, config.ini, disk refusal wording and the resource:emulator label; the concurrency budget; Roborazzi sdk=34 pin and record job; module manifests and per-package resources owned once; explicit ownership transfers and placeholder files; W14 owns its project.yml edit; W24 after S72 with its insertion listed; A99 last; the shell split (A11 routes and harness, A12 permissions, back and IME); the core adaptive matrix scoped to its own screens; W03 on W01; watch score split from serve and mark on both OSes (W05/W06, W12/W13); F-ADR-0001 merge gate; F-STUDIO-ANDROID on the Studio roots; A2 findings on A92; the F-ROOM-PORTS over-claim removed; F-CORE-REVIEW gate row; W08 for the iPhone paired-watch rows; W10 no-keep-alive and junior tests; serve-value guards; df preconditions and G-DISK; A58 before A73; the :media seam; the 16 KB check moved to the first native dependency; Android 16 rows; marker amendment issues; A98 full coverage plus A23 and A93; IME tests; A91 permission/background test; story 234 to A94; A88 multi-angle mark review (353); A47 boundaries; junior tests in A53/A72/A84; S5 stories registered; the Android claim lint in A10; posture labels; G-ROOM CI via W01; A93 extends S73; W23 reuses S21/S25 and files the T61 issue; A96 pricing gate. Modified - the Android root split three ways (A01 build + boundary check + android-core, A02 shell + manifests + android-unit + Roborazzi + 16 KB, A03 avd.sh + guide) rather than four; the core adaptive matrix split three ways (Robolectric matrix, phone/compact AVDs, fold/tablet AVDs) rather than one per AVD; F-IOS-ADAPTIVE handled by labelling W22-W24 'study, not adopted' rather than blocking them; F-CORE-REVIEW handled by a W07 gate row rather than a new iOS core review ticket (the iOS core spec owner decides whether T-DAG gains one). Not adopted - moving every emulator row into a few serialized evidence tickets: media tickets (frame stepping, capture, export, render) need their instrumented proof in the same PR or they cross a gate on claims; the lease and the one-emulator rule give the same serialization; a new W ticket for the Swift room transport: it would duplicate S69/S70, so A92 and W21 are gated on the rescope decision instead.

GRANULARITY VS iOS: core parity is coarser than iOS T01-T63 where Android reuses decided contracts (one store ticket plus a small sample-install ticket where iOS has T08+T09; export and Share Pack in two tickets). Labs keep iOS granularity because each is one screen. Studio demo screens are grouped by family, as iOS S17-S29 are. The :core conformance tickets mirror T03-T05, because the fixtures define their boundaries.

## Tickets

| ID | Title | Track | Blocked by | Size | Depth | Gate | Screens |
|---|---|---|---|---|---|---|---|
| A01 | Android build foundation on Lane A: Gradle wrapper and catalog, build-logic, every ADR-0024 module skeleton, the module-boundary check and the required android-core CI job | android | — | L | 1 | G-RESOLVE; merge gate F-ADR-0001 + Lane A pins ADR (ADR owner) | — |
| A02 | Android shell: JOVRA theme with the Court Arc mark and launcher icon, a five-destination NavigationSuiteScaffold, every module manifest declared up front, the per-package resource convention, android-unit CI, Roborazzi at sdk=34 with a record job, and the 16 KB alignment check | android | A01 | L | 2 | none | 03-home |
| A03 | Emulator tooling: avd.sh with an exclusive JOVRA lease, the toolchain config.ini and the disk guard, and the Android section of the developer guide | android | A01 | S | 2 | none | — |
| A04 | Kotlin contracts and the conformance harness: :testing fixture walker, canonical JSON, strict session decoding, pct, units and record round-trips | android | A01 | L | 2 | G-CORE (partial: pct, units, records) | — |
| A05 | Kotlin scoring engine: event-log resolution, rules fold, provisional scores, conflicts and the recalculation diff against every scoring fixture | android | A04 | L | 3 | G-CORE (scoring) | — |
| A06 | Kotlin stats, JSON and CSV data export byte-for-byte, the Jon vs Alex sample conformance and pooled trends | android | A05 | M | 4 | G-CORE (stats, sample) | — |
| A07 | Kotlin sample library: eight Sample sessions, equipment and practice plan from the reference generator, and the one sample-scope rule | android | A06, T09 | M | 5 | none | — |
| A08 | Android document store: atomic session folders, index rebuild, quarantine, migration, trash, preferences, backup exclusions and the Movies/JOVRA helper | android | A04, A02 | L | 3 | none | — |
| A09 | Sample install, byte-for-byte reset and remove on the document store | android | A08, A07 | S | 6 | none | — |
| A10 | Design-system components: provenance and Sample badges, status pills, state cards, capability detail, charts with spoken summaries and tables, and contrast tests | android | A04, A02 | L | 3 | none | — |
| A11 | App shell: Navigation 3 saveable back stack, every typed route and sheet as an owned placeholder, the state harness, the composition root and the network trap | android | A08, A10 | L | 4 | none | 08-session-library |
| A12 | PermissionsCenter, guarded and sheet-first back, the 48 dp Close and the on-screen-keyboard inset helper | android | A11 | M | 5 | none | — |
| A13 | Court geometry and 4-tap calibration maths in :core with the court diagram, markers, perspective guide and loupe handle | android | A10 | M | 4 | none | 05-court-calibration, 11-shot-map |
| A14 | Shared pane-policy contract (F-PANE-VECTORS): golden vectors, a Python reference and a validator with its own CI workflow | android | — | M | 1 | G-PANE (contract) | — |
| A15 | Kotlin pane policy held to the shared vectors, and the adaptive scaffolds: list/detail, supporting pane, hinge split, tabletop and compact height | android | A14, A11 | L | 5 | G-PANE (Kotlin) | — |
| A16 | Welcome, three-step onboarding, Profile hub and demo entry | android | A12, A09 | M | 7 | none | 01-welcome, 02-player-onboarding |
| A17 | Home dashboard: greeting, stat tiles, latest session, weekly chart and next-step row | android | A11, A09 | M | 7 | none | 03-home |
| A18 | Session library: search, filters, independent status facets, Only on this phone, Trash with Undo and quarantine, list beside overview on wide windows | android | A15 | M | 6 | none | 08-session-library |
| A19 | Session setup: modes, players, formats, doubles order, CameraX-supported presets, storage range and setup drafts | android | A15, A05 | M | 6 | none | 04-session-setup |
| A20 | Match overview: scoreboard, stats with denominators, momentum, point history, head-to-head and explicit results | android | A15, A06 | M | 6 | none | 09-match-overview |
| A21 | Media3 playback core: exact seeking, PTS-index frame steps, rates and A–B loop, with the video surface, jog strip and transport, proven on frame-counter fixtures | android | A10, A03, T10 | L | 4 | AVD jovra_phone_p9_api35 (disk) | 10-smart-replay |
| A22 | CameraX recording engine: one segment per Recording behind the ADR-0010 journal, finalize mapping, preflight, thermal ladder state machine and the emulator fixture camera | android | A08, A03, T10 | L | 4 | Hardware: Pixel (durability, fps, thermals) | — |
| A23 | Crash recovery: launch scan decoding every segment to the end, torn segments, gap reports and the Resume prompt | android | A22, A18 | M | 7 | Hardware: Pixel (crash loss ≤ 3 s) | — |
| A24 | Capture route and recording screen: REC, save status, Mark and Stop, guarded back, pause/resume, ongoing notification and interruptions as gaps | android | A19, A22, A12 | L | 7 | Hardware: Pixel | 06-live-capture |
| A25 | Court framing and 4-corner calibration with the live checklist, loupe and microphone explainer | android | A19, A22, A13, A12 | M | 7 | none | 05-court-calibration |
| A26 | Live manual scoring, Mark point, bookmark notes, changeover checkpoint entry and volume-key/headset Mark | android | A24 | M | 8 | Hardware: Pixel (headset range UNVERIFIED) | 06-live-capture |
| A27 | Device budget during capture: thermal ladder UI, court mode, low battery and low storage | android | A24 | M | 8 | Hardware: Pixel (thermals) | 06-live-capture |
| A28 | Import from the photo picker and Files with per-file results, duplicates and drag-and-drop | android | A11, A03, T10 | M | 5 | none | 07-import-processing |
| A29 | Processing queue on WorkManager with checkpoints and the processing screen's stage timeline | android | A28, A22 | M | 6 | none | 07-import-processing |
| A30 | Smart replay: score overlay from the fold, event timeline, filters, point card, one-tap winner correction, tabletop and keyboard | android | A21, A15, A05 | L | 6 | none | 10-smart-replay |
| A31 | Point editor: add, split, merge, delete, nudge, Unknown, stroke tags, conflict banners and Rules vs As-played | android | A30 | L | 7 | none | 10-smart-replay, 09-match-overview |
| A32 | Fast Point Review deck with edge-safe swipes and TalkBack actions | android | A30 | M | 7 | none | N1 Fast Point Review |
| A33 | Checkpoint auto-fill on the shared checkpoint fixtures, 'Score this match' and the checkpoint-conflict banner | android | A32, T31 | M | 8 | G-CORE (checkpoint) | N1 Fast Point Review, 09-match-overview |
| A34 | Rally segmentation in :core and rally-only playback with visible gap chips | android | A30 | M | 7 | none | 10-smart-replay |
| A35 | Android HitDetector and benchmark records: point suggestions only when the Android detector passes its synthetic benchmark | android | A29, T11, T34 | L | 7 | Real-footage benchmark (separate) | 07-import-processing |
| A36 | Clip export with Transformer, Save original to Movies/JOVRA or Files, and per-session JSON and CSV export | android | A30 | L | 7 | none | 10-smart-replay |
| A37 | Condensed match, highlight reel with burned-in score and the Share Pack for coach, opponent and partner | android | A36, A34 | L | 8 | none | N3 Share Pack, N10 Highlight reel |
| A38 | Sample analysis content: stroke tags, placements, calibrations, serve marks, key moments and the comparison project | android | A07, T40 | S | 6 | none | — |
| A39 | Shot placement map with manual bounce marking and TalkBack descriptions | android | A13, A30, A38 | M | 7 | none | 11-shot-map |
| A40 | Stroke Lab: padded clips, key moments, contact strip and review statuses | android | A21, A38, A15 | M | 7 | none | 13-stroke-lab |
| A41 | Serve Lab: deuce/ad stats, placements, manual-assisted speed estimate, key moments and the toss timer | android | A13, A21, A38, A15 | L | 7 | none | 12-serve-lab |
| A42 | Compare two recordings with manual contact sync, book-posture split and annotations with stylus draw-only | android | A30, A38 | L | 7 | none | 14-video-comparison |
| A43 | Optional ML Kit capabilities behind G-16K: bystander face blur in exports and on-demand 2D pose in Stroke Lab | android | A36, A40 | M | 8 | G-16K (runtime _ps16k image: G-DISK + Jon's approval) | 13-stroke-lab, 10-smart-replay |
| A44 | Insights: evidence-linked practice plan, drill session and the Explore list | android | A15, A09 | M | 7 | none | 15-coaching-plan |
| A45 | Progress: pooled trends, milestones, review completion and goals with spoken chart summaries | android | A15, A09 | M | 7 | none | 16-progress |
| A46 | Racket Vault and String Journal | android | A15, A09 | M | 7 | none | 17-racket-vault, 18-string-journal |
| A47 | Equipment links: setup gear row, restring reminders, 'String broke' during capture and equipment associations | android | A46, A45, A24 | M | 8 | none | 18-string-journal, 04-session-setup |
| A48 | Storage and backup screen with the archive state machine, uninstall warning, Movies/JOVRA copy and 'Awaiting Google Drive setup' | android | A15 | L | 6 | none | 19-cloud-archive |
| A49 | Google Drive archive on Android: AuthorizationClient with drive.file, resumable verified uploads, the fake Drive and reconnect/disconnect | android | A48 | L | 7 | F-ADR-0008 amendment; Jon's Android OAuth client (real Drive) | 19-cloud-archive |
| A50 | Archive restore with verification, cross-platform restore of an iOS archive, archive-only sessions and Space Saver | android | A49, A18, A16, T52 | M | 8 | G-CORE (archive) | 19-cloud-archive, 08-session-library |
| A51 | Settings and privacy: No account, real permission rows, saving/choosing videos rows, units, appearance, accessibility, notifications, demo content and per-app language | android | A15, A09, A12 | M | 7 | none | 20-settings-privacy |
| A52 | Your data: export my data, delete all data, diagnostics bundle and the privacy checks | android | A51, A22 | M | 8 | none | 20-settings-privacy, N5 Diagnostics |
| A53 | Consent records, Competition mode and junior-parent mode | android | A24 | M | 8 | none | N4 Consent and junior, 04-session-setup |
| A54 | App shortcuts, the Health Connect opt-in spike and the ongoing-notification live-update spike | android | A24, A20, A51 | M | 8 | G-IMG36 + G-DISK (live update only) | — |
| A55 | Review marks and manual call notes (ADR-0028 Stage 1): Marked list, timeline markers, manual In/Out/Needs-review placement | android | A26, A39 | M | 9 | none | 10-smart-replay |
| A56 | Core adaptive matrix under Robolectric: posture variants, state preservation, idempotency, the keyboard inset and the cross-screen navigation paths | android | A16, A17, A18, A20, A25, A28, A31, A32, A39, A40, A41, A42, A44, A45, A46, A48, A51 | L | 8 | G-IMG36 + G-DISK for Android 16 large-screen claims | 03-home, 08-session-library, 09-match-overview, 10-smart-replay, 14-video-comparison |
| A57 | Core emulator run on the phone and compact AVDs: rotation, process death, font scale and a TalkBack label sweep | android | A56 | M | 9 | Native UI gate (phone, compact AVDs) | — |
| A58 | Core emulator run on the fold and tablet AVDs: fold and unfold, book posture, keyboard focus order | android | A57 | M | 10 | Native UI gate (fold, tablet AVDs); G-IMG36 + G-DISK for Android 16 large-screen claims | — |
| A59 | :studio-core contracts: strict models for every Studio schema, canonical hashes for 31 records, 172 invalid cases and the EDL validator | android | A04 | L | 3 | G-CORE (Studio records); F-STUDIO-ANDROID (claims) | — |
| A60 | :studio-core vectors: exact sync fits, sound delays, job transitions, ledger, quote credits, sample truth and edl-context | android | A59 | L | 4 | G-CORE (Studio vectors) | — |
| A61 | Studio project store, the Studio sample project and the demo cloud client | android | A60, A08 | M | 5 | F-STUDIO-ANDROID (claims) | — |
| A62 | Studio shell: Studio route states in the harness, shared Studio components and the Studio pane layout | android | A61, A15 | M | 6 | F-STUDIO-ANDROID (claims) | — |
| A63 | Studio entry points on Home, Match overview, Insights and the Profile hub | android | A62, A16, A17, A20, A44 | S | 8 | none | 41-android-studio-home |
| A64 | Studio Home (41) and Studio settings (60) in every demo state | android | A62 | M | 7 | none | 41-android-studio-home, 60-android-studio-settings |
| A65 | :room-protocol part 1: codecs for the 14 room schemas, 27 records, 103 invalid cases and the freshness, snapshot, status, display, disconnect and analysis vectors | android | A04 | L | 3 | G-ROOM (part 1) | — |
| A66 | Build your match (42), camera lobby (43) and director capture (44) in demo on the fixture room | android | A62, A65 | L | 7 | none | 42-android-build-match, 43-android-camera-lobby, 44-android-director-capture |
| A67 | Source import (45) and the sync workspace (46: sheets on compact, desk split at the hinge) in demo | android | A62 | M | 7 | none | 45-android-source-import, 46-android-fold-sync |
| A68 | Match Broadcast player (47) and angle insights (48) in demo | android | A62, A21 | M | 7 | none | 47-android-fold-broadcast, 48-android-angle-insights |
| A69 | Story modes (49) and the profile screens Coach's Cut, Rally Pulse, Progress Story and Court Memories (50–53) in demo | android | A62 | M | 7 | none | 49-android-story-modes, 50-android-coachs-cut, 51-android-rally-pulse, 52-android-progress-story, 53-android-court-memories |
| A70 | Lesson journal (54) and the lesson workspace (55: one, two or three panes) in demo | android | A62 | M | 7 | none | 54-android-lesson-journal, 55-android-tablet-lesson |
| A71 | Film storyboard (56): beat list with sheets on compact, preview and timeline on wide, tabletop split, in demo | android | A62 | M | 7 | none | 56-android-fold-storyboard |
| A72 | Cloud preflight quote (57), render queue (58) and film delivery (59) in demo with Sample credits | android | A62 | L | 7 | F-QUOTE-CONSENT (cloud planning state) | 57-android-cloud-preflight, 58-android-render-queue, 59-android-film-delivery |
| A73 | Studio fold and tablet workspaces 46, 47, 55 and 56 on the fold and tablet AVDs with state preservation and no duplicated side effects | android | A67, A68, A70, A71, A72, A58 | L | 11 | Native UI gate (fold, tablet AVDs); G-IMG36 + G-DISK for Android 16 claims | 46-android-fold-sync, 47-android-fold-broadcast, 55-android-tablet-lesson, 56-android-fold-storyboard |
| A74 | Studio S0 / A1 gate on Android: every Studio state reachable and audited, copy checks and the status report | android | A63, A64, A66, A69, A73 | M | 12 | none | 41-android-studio-home, 42-android-build-match, 43-android-camera-lobby, 44-android-director-capture, 45-android-source-import, 46-android-fold-sync, 47-android-fold-broadcast, 48-android-angle-insights, 49-android-story-modes, 50-android-coachs-cut, 51-android-rally-pulse, 52-android-progress-story, 53-android-court-memories, 54-android-lesson-journal, 55-android-tablet-lesson, 56-android-fold-storyboard, 57-android-cloud-preflight, 58-android-render-queue, 59-android-film-delivery, 60-android-studio-settings |
| A75 | Story engine in Kotlin: keepers, staleness, StoryDirector, RulesPlanner and the EDL compiler with parity to the Python reference | android | A60, S05, S06, S07 | L | 5 | G-CORE (Studio S1 kinds) | — |
| A76 | LessonJournal and ProgressStoryBuilder in :studio-core | android | A60, S05 | M | 5 | none | — |
| A77 | Android FilmVerifier: full decode, frame count and timestamp grid, barcodes and clicks within one frame, audio sample count and overlay text | android | A59, A21, S08, S09 | M | 5 | none | — |
| A78 | Local film renderer on Media3 Transformer, each operation enabled only after its barcode-court test renders and verifies | android | A77, A75 | L | 6 | none | — |
| A79 | S1 tracer: one Match Broadcast film from the synthetic match produced, verified, recorded and delivered on the emulator | android | A78, A72 | L | 8 | none | 59-android-film-delivery |
| A80 | Local film jobs for all five profiles: resumable WorkManager renders, notifications, real story modes and stale-on-correction | android | A79, A69 | L | 9 | none | 49-android-story-modes |
| A81 | Film storyboard for real: re-validated edits, continuous draft cuts and Rebuild | android | A80, A71 | M | 10 | none | 56-android-fold-storyboard |
| A82 | Project player for one angle and angle insights on real data | android | A79, A68 | M | 9 | none | 47-android-fold-broadcast, 48-android-angle-insights |
| A83 | Lesson journal and workspace for real, lesson links from films, Progress Story and private lesson export | android | A76, A70, A80, A37 | M | 10 | none | 54-android-lesson-journal, 52-android-progress-story |
| A84 | Saving films: Include audio, a separately verified no-audio file, Movies/JOVRA, and Prepare for YouTube | android | A80 | M | 10 | none | 59-android-film-delivery |
| A85 | Studio S1 journey gate on Android: one match to five verified films, lessons and saved files, end to end on the emulator | android | A81, A82, A83, A84 | M | 11 | Real media (Jon's match) | — |
| A86 | ProxyNormalizer and multi-source import: CFR render proxies with original-PTS tables, rotation once, HDR to SDR | android | A79, S56, S58, A67 | L | 9 | none | 45-android-source-import |
| A87 | Sync anchors from the Android HitDetector, markers and capture hints, and the sync desk for real | android | A86, A35 | L | 10 | none | 46-android-fold-sync |
| A88 | Multi-angle player and multi-angle films (alt-bed, multi-angle live and replay) with the S2 synthetic two-camera gate | android | A87, A80, A82, A55 | L | 11 | Two-view real footage (separate) | 47-android-fold-broadcast |
| W01 | Swift JovraRoom package part 1: spec/room records, invalid cases and the freshness, snapshot, status, display, disconnect and analysis vectors, with a room CI workflow | watch | T03 | L | 1 | G-ROOM / G-W-CONTRACT (part 1) | — |
| A89 | :room-protocol part 2: invitations with commit-then-reveal codes, the command ledger bound to the authenticated peer, outbox, bridge acceptance and AlertPolicy | android | A65, W01 | L | 4 | G-ROOM (Kotlin) | — |
| A90 | :room-transport: NSD picker-first discovery, TLS 1.3 with SPKI pinning, length-prefixed framing, QR invites with the in-app scanner and the LocalOnlyHotspot host | android | A89, A02 | L | 5 | Two-phone room (real LAN); G-TARGET37 for targetSdk 37 | 43-android-camera-lobby |
| A91 | Camera lobby and director capture on a real JOVRA Room v1: invites, code approval, acknowledgements, heartbeats and stop fan-out | android | A90, A66, A24 | L | 8 | Two-phone room (A2) | 43-android-camera-lobby, 44-android-director-capture |
| W02 | Swift JovraRoom part 2: commit-then-reveal invitations, the ledger bound to the authenticated peer, outbox, BridgeReceiver, HealthSummary and AlertPolicy | watch | W01 | L | 2 | G-ROOM / G-W-CONTRACT (Swift) | — |
| A92 | A2 two-phone gate: Pixel and iPhone, each as host and camera, with the runbook and log collector | android | A91, W02, S71 | M | 9 | Gate A2 (Jon's Pixel + iPhone; physical row only); F-ADR-0017, F-ROOM-STILL (decided or deferred with Jon's sign-off) and F-STUDIO-INVITE must be closed before A2 is reported passed; S68-S72 rescope decision | 43-android-camera-lobby |
| A93 | Six-device field protocol on Android (S3/A4): 60-minute mixed-OS session, per-device recovery and warnings | android | A92, A88, S73 | M | 12 | Six-device field (Studio S3 / A4); F-ROOM-STILL for still cadence | — |
| A94 | Aged secondary stills on both ports, once F-ROOM-STILL decides the still record | android | A91, W02 | M | 9 | F-ROOM-STILL | 44-android-director-capture |
| A95 | Android CloudClient Test and Live adapters on OkHttp, contract-tested against the backend fixtures, with the test identity and Keystore credential store | android | A72, S81 | L | 8 | Test backend activation (S104) for hosted runs | 60-android-studio-settings |
| A96 | Cloud quote, render jobs and private delivery for real against the stubbed gateway, with idempotency persisted before every send | android | A95, A84 | L | 11 | F-QUOTE-CONSENT; F-ADR-0023 (pricing ADR) for real quotes; test backend activation | 57-android-cloud-preflight, 58-android-render-queue, 59-android-film-delivery |
| A97 | Studio storage providers on Android: device, Files folder, Google Drive wrapper, planned Box and Dropbox, no iCloud | android | A64, A49 | M | 8 | none | 60-android-studio-settings |
| A98 | Final Android QA: approved Roborazzi baselines, TalkBack and font-scale matrix, Maestro suite, performance smoke and the release registers | android | A27, A33, A43, A47, A50, A52, A53, A54, A74, A85, A96, A97, A23, A93 | L | 13 | Hardware: Pixel/Galaxy (registered, not run here) | 01-welcome, 41-android-studio-home |
| A99 | Lane B: one catalog diff to the current-stable stack and compileSdk 37 after G-SDK37, with an optional CI job | android | A98 | S | 14 | G-SDK37; G-DISK | — |
| W03 | watchOS app target via XcodeGen: JovraWatch with the four-page shell, fake bridge, -watchState harness and JOVRA watch simulators | watch | W01, T06, S04 | L | 2 | G-W-SIMUI (simulator) | 61-watchos-camera-health |
| W04 | Apple Watch camera health (61) and connection alert (65) in every state | watch | W03, W02 | L | 3 | G-W-SIMUI | 61-watchos-camera-health, 65-watchos-connection-alert |
| W05 | Apple Watch score and undo (62) in every state | watch | W03, W02 | M | 3 | G-W-SIMUI | 62-watchos-score |
| W06 | Apple Watch latest serve (63) and mark for review (64) in every state | watch | W03, W02 | M | 3 | G-W-SIMUI | 63-watchos-serve, 64-watchos-review-marker |
| W07 | iPhone WatchBridge in single-phone mode over WatchConnectivity: snapshots, echo, marks with receipts and alert acknowledgement | watch | W03, W02, T17, T24 | L | 3 | G-W-SIMPAIR; G-W-REALPAIR (physical); F-CORE-REVIEW (review-count row) | 61-watchos-camera-health |
| W08 | iPhone 'Paired watch' surfaces: the camera lobby watch section (ST23) and the Studio settings row (ST40) | watch | W07, S71, S29 | M | 4 | G-W-SIMUI | ST23 Camera lobby, ST40 Studio settings |
| W09 | :wear-bridge Data Layer contract: paths, capability, codecs from :room-protocol and the FakeDataLayerClient | watch | A89, A02 | M | 5 | none | — |
| W10 | Android phone-side Wear bridge in single-phone mode: snapshot projection, echo, marks with receipts and the live 'Paired watch' adapter | watch | W09, A26 | L | 9 | G-WEARPAIR + G-DISK (Data Layer emulator evidence); G-W-REALPAIR (physical) | 66-wearos-camera-health |
| W11 | :wear app shell on Compose for Wear OS with camera health (66) and connection alert (70) in every state | watch | W09, A03 | L | 6 | G-W-WEARUI; G-WEARIMG + G-DISK for emulator screenshots | 66-wearos-camera-health, 70-wearos-connection-alert |
| W12 | Wear OS score and undo (67) in every state | watch | W11 | M | 7 | G-W-WEARUI; G-WEARIMG + G-DISK for emulator screenshots | 67-wearos-score |
| W13 | Wear OS latest serve (68) and mark for review (69) in every state | watch | W11 | M | 7 | G-W-WEARUI; G-WEARIMG + G-DISK for emulator screenshots | 68-wearos-serve, 69-wearos-review-marker |
| W14 | Apple Watch complications and always-on: timestamped snapshot, budget-aware refresh and tap-to-refresh | watch | W04, W05, W06, W07 | M | 4 | G-W-SIMUI | 61-watchos-camera-health |
| W15 | Wear OS tile, complication data source and ambient snapshot | watch | W12 | M | 8 | G-WEARIMG + G-DISK for emulator evidence | 66-wearos-camera-health |
| W16 | Watch score commands on iOS (A3b): PointWon and Undo with receipts, conflicts and offline chains through the iPhone | watch | W07, W05 | M | 4 | G-W-SIMPAIR; A3b exit needs Gate A2 + G-W-REALPAIR (flagged until then) | 62-watchos-score |
| W17 | Watch score commands on Android/Wear (A3b): PointWon and Undo with receipts, conflicts and offline chains through the phone | watch | W10, W12 | M | 10 | G-WEARPAIR + G-DISK; A3b exit needs Gate A2 + G-W-REALPAIR (flagged until then) | 67-wearos-score |
| W18 | Connection alerts and haptics policy on iPhone and Apple Watch: deferral, dedupe, critical own-phone alerts and acknowledgement sync | watch | W07, W04 | M | 4 | G-W-REALPAIR (haptics) | 65-watchos-connection-alert |
| W19 | Connection alerts and haptics policy on Android and Wear OS | watch | W10, W11 | M | 10 | G-W-REALPAIR (haptics) | 70-wearos-connection-alert |
| W20 | Own-phone stop from either watch (A3c): a confirmed bridge-local request that never travels as a room command | watch | W16, W17 | M | 11 | Gate A2 (device rows); G-W-REALPAIR | 62-watchos-score, 67-wearos-score |
| W21 | Room-fed watch bridge (A3a+room): both phones project the room aggregate, so either watch sees mixed-OS cameras | watch | W07, W10, A91, S72 | M | 10 | Gate A2; G-W-REALPAIR; S68-S72 rescope decision (an iPhone on the S68 draft cannot interoperate) | 61-watchos-camera-health, 66-wearos-camera-health |
| W22 | Swift pane policy held to the shared pane-policy vectors (G-PANE iOS half), with StudioPaneLayout delegating to it | ios-adaptive | A14, S15 | S | 2 | G-PANE (iOS); F-IOS-ADAPTIVE (claims) | — |
| W23 | Studio workspace at regular width (I71): one, two or three columns by window class with film, playhead and lesson preserved | ios-adaptive | W22, S17, S21, S25 | L | 3 | iPad stand-in only (no foldable simulator); F-IOS-ADAPTIVE (claims) | 71-ios-fold-studio |
| W24 | Camera desk at regular width (I72): director capture with device rows and the paired-watch panel | ios-adaptive | W22, S19, W07, S72 | M | 4 | iPad stand-in; hardware for capture continuity; F-IOS-ADAPTIVE (claims) | 72-ios-fold-angle-desk |
| W25 | iOS Studio preserved-state matrix: the adaptive-screens §4.5 test plan over every Studio row | ios-adaptive | W23, W24, S34 | L | 5 | F-IOS-ADAPTIVE stays open until the owners adopt the table | 71-ios-fold-studio, 72-ios-fold-angle-desk |
| W26 | Watch and iOS adaptive QA: simulator and Roborazzi evidence aggregated, references 61–72 side by side, and the gate registers | watch | W08, W13, W14, W15, W16, W17, W18, W19, W25 | L | 11 | G-W-REALPAIR, G-W-FIELD (registered, not run here) | 61-watchos-camera-health, 66-wearos-camera-health, 71-ios-fold-studio, 72-ios-fold-angle-desk |

## A01: Android build foundation on Lane A: Gradle wrapper and catalog, build-logic, every ADR-0024 module skeleton, the module-boundary check and the required android-core CI job

`android-build-foundation-lane-a` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:foundation`

**Blocked by:** None (can start immediately)

**What to build:** The first Android code in the repository, split from the shell (A02) and the emulator tooling (A03) so the pure-JVM conformance work can start as early as possible. Zero installs: it builds on the machine as it is. (0) Before the first build, record `df -h /`; the Lane A build is budgeted at 3.5-6 GB of Gradle caches that persist after `clean`, and the ticket stops (and reports) if projected free space would drop under 8 GB. (1) `android/` as one Gradle build: Gradle 9.3.1 wrapper with distributionSha256Sum, AGP 9.1.1 with built-in Kotlin 2.4.20 plus the Compose and serialization compiler plugins, JDK 17, `gradle/libs.versions.toml` with the AD6 Lane A pins, configuration cache on. (2) `build-logic` convention plugins (jovra.jvm.library, jovra.android.library, jovra.android.compose, jovra.android.application, jovra.android.test) holding compileSdk 36 / targetSdk 36 / minSdk 29 (Wear 36/36/30) in one place. (3) Every ADR-0024 module as a skeleton with one smoke test: :core, :studio-core, :room-protocol, :testing (pure JVM, no Android), :designsystem, :data, :media, :room-transport, :wear-bridge, :feature:{home,sessions,record,insights,profile}, :studio:{build-match,films,editor,cloud}, :app and :wear. Each module's build file declares every Lane A dependency it is planned to need, so later tickets add code, not build edits; a missing dependency later is a one-line catalog-fix PR. Never a module named :room; no Room, SQLite, Hilt, KSP or kapt. (4) A module-boundary check task that fails when a JVM module depends on an Android module, a feature module depends on another feature module, a module other than :room-transport references java.net.Socket/NsdManager/WifiManager, or a module other than :media references CameraX, Media3 or MediaCodec. The seam is decided here: :media exports the composables and flows other modules need (camera preview under android/media/ui/preview, the player surface under android/media/ui/video, QR scanner frames under android/media/ui/scanner), so framing, replay, the Studio player, the director preview and the room QR scanner never reference CameraX or Media3 themselves. (5) `.github/workflows/android.yml` (ci.yml is not edited) with the required `android-core` job: temurin 17, no Android SDK, `./gradlew -p android :core:test :studio-core:test :room-protocol:test :testing:test`. (6) Issues filed for the ADR owner: the F-ADR-0001 header note, an ADR or amendment recording the Android start and the Lane A pins (story 351), and the F-ADR-0008 Android Drive amendment. They are not edited here, and this PR does not merge before the first two land. Why blocked: nothing; this is the root of the Android DAG.

**Acceptance criteria**

- [ ] G-RESOLVE: `./gradlew -p android help :app:dependencies :app:checkDebugAarMetadata :wear:checkDebugAarMetadata` succeeds on compileSdk 36 with the Lane A catalog (raw output attached); if Navigation 3 1.1.7 fails resolution the documented fallback (Navigation Compose 2.9.8) is recorded, not silently swapped.
- [ ] `./gradlew -p android assembleDebug :wear:assembleDebug` succeeds with the empty skeletons; no AVD is created.
- [ ] The module-boundary check fails on each of five deliberate violations in a scratch branch (JVM→Android dependency, feature→feature, Socket outside :room-transport, CameraX outside :media, Media3 outside :media) and passes on main.
- [ ] settings.gradle.kts contains no module named `:room`, and a grep of every build file for `androidx.room`, `kapt`, `ksp` and `hilt` returns nothing.
- [ ] android.yml runs android-core on a pull request without an Android SDK (setup log); a deliberately failing :core smoke test turns it red (run link).
- [ ] `df -h /` before the first build and the projected budget are in the PR; the ticket stopped, or would have stopped, below 8 GB.
- [ ] Merge gate: the PR links the merged F-ADR-0001 header note and the merged ADR or amendment for the Android start and Lane A pins (story 351); without them it stays open and unmerged. The F-ADR-0008 issue is linked.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- G-RESOLVE raw output
- assembleDebug output
- Boundary-check negative transcripts
- android.yml CI run links (green and the deliberate red run)
- ADR links

**Owned areas**

- `android/settings.gradle.kts`
- `android/build.gradle.kts`
- `android/gradle.properties`
- `android/gradle/`
- `android/gradlew*`
- `android/build-logic/`
- `android/*/build.gradle.kts (module skeletons)`
- `android/**/src/test/smoke/** (skeleton smoke tests)`
- `.github/workflows/android.yml (file and the android-core job)`

**User stories:** 336, 339, 343, 348, 349, 351

**Gate:** G-RESOLVE; merge gate F-ADR-0001 + Lane A pins ADR (ADR owner)

## A02: Android shell: JOVRA theme with the Court Arc mark and launcher icon, a five-destination NavigationSuiteScaffold, every module manifest declared up front, the per-package resource convention, android-unit CI, Roborazzi at sdk=34 with a record job, and the 16 KB alignment check

`android-shell-theme-manifests-ci` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:foundation`

**Blocked by:** A01

**What to build:** (1) :designsystem theme only: JOVRA colour roles mirrored from iOS ColorRole (forest #092A25, secondary forest, ivory #F4F1E8, text #182F29, chartreuse #D7F56A, clay #C47752) in light, dark and high contrast, dynamic colour off, type scale on the system font, 8 dp spacing; the Court Arc mark redrawn as an ImageVector/VectorDrawable from the iOS BrandGeometry geometry; an adaptive launcher icon with foreground, background and monochrome layers. (2) :app: edge-to-edge activity, NavigationSuiteScaffold with Home, Sessions, Record, Insights, Profile (bar on compact width, rail on medium and wider, from currentWindowAdaptiveInfo), each destination a placeholder; :wear gets a placeholder activity with the same applicationId and signing config as :app. (3) Every module manifest is written here, once, from android-v1-spec AD17 and the permissions list: CAMERA, RECORD_AUDIO, POST_NOTIFICATIONS, NEARBY_WIFI_DEVICES, INTERNET, RUN_USER_INITIATED_JOBS, the camera, microphone and mediaProcessing foreground-service types, the WorkManager and FileProvider entries, the static-shortcut resource, the `android:dataExtractionRules`/`fullBackupContent` attributes pointing at the XML files A08 fills, and the `jovra_watch_bridge_v1` capability XML in both :app and :wear. A later ticket that needs a new manifest entry makes a one-line manifest-fix PR, never an edit inside a feature ticket. (4) Per-package resources: each package keeps its strings in `res/values/strings_<package>.xml` with names prefixed `<package>_`, enforced by a lint check, so tickets in the same module never touch the same resource file. (5) The `android-unit` job in android.yml (JDK 17 Gradle, test workers on JDK 21): testDebugUnitTest, lintDebug, assembleDebug, :wear:assembleDebug, Roborazzi verify, and `zipalign -c -P 16` on every assembled release APK with a list of the artifacts that carry .so files (CameraX core is expected to, from A22 on; INFERRED until listed). (6) Roborazzi set up with every screenshot test pinned to `@Config(sdk = [34])`, so local runs on JDK 17 and CI render on the same Robolectric SDK; a `roborazzi-record` workflow_dispatch job records goldens on Linux and uploads them as an artifact for the ticket to commit. Goldens are compared locally only. Why blocked: A01 (module skeletons, android.yml).

**Acceptance criteria**

- [ ] A Robolectric (sdk=34) Compose test shows exactly five destinations in a bottom bar at 360 dp width and in a rail at 840 dp width, each item labelled for TalkBack.
- [ ] A contrast unit test checks every text/background role pair in light, dark and high contrast against the iOS ContrastRequirement thresholds and fails when one role is deliberately weakened.
- [ ] The launcher icon has foreground, background and monochrome layers (aapt2 dump of the merged resources); the Court Arc vector renders at 24 dp and 108 dp in a Roborazzi test.
- [ ] The merged manifests list every permission, foreground-service type, service, provider and the watch capability named above (merged-manifest report); :app and :wear share applicationId and signing config (signingReport).
- [ ] The per-package resource lint fails on a scratch string without its package prefix and on a second package writing into another package's strings file.
- [ ] android-unit runs on a pull request; the roborazzi-record job produces a golden artifact that, once committed, verifies green in android-unit.
- [ ] The 16 KB step passes on the current release APK and fails on a deliberately unaligned scratch library; the .so artifact list is in the PR.
- [ ] docs/DEVELOPING.md's Android section (A03) is not edited here (diff stat).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- CI run links (android-unit, roborazzi-record)
- Merged-manifest report
- Roborazzi images of the shell bar/rail and the Court Arc mark
- zipalign -c -P 16 output

**Screens**

- design-reference/screens/03-home.png (derived; hierarchy and copy only) (shell only)

**Owned areas**

- `android/designsystem/theme/**`
- `android/designsystem/brand/**`
- `android/app/shell/**`
- `android/app/src/main/res/mipmap*`
- `android/app/src/main/res/xml/shortcuts.xml (placeholder)`
- `android/wear/placeholder/**`
- `android/build-logic/lint/resources/**`
- `.github/workflows/android.yml (android-unit and roborazzi-record jobs only)`
- `android/{app,wear,designsystem,data,media,room-transport,wear-bridge}/src/main/AndroidManifest.xml (module manifests)`
- `android/feature/*/src/main/AndroidManifest.xml`
- `android/studio/*/src/main/AndroidManifest.xml`

**User stories:** 14, 15, 340, 341

**Gate:** none

## A03: Emulator tooling: avd.sh with an exclusive JOVRA lease, the toolchain config.ini and the disk guard, and the Android section of the developer guide

`emulator-lease-developer-guide` · android · size S · labels `ready-for-agent`, `platform:android`, `track:android`, `area:foundation`

**Blocked by:** A01

**What to build:** (1) `android/scripts/avd.sh acquire|release|delete <name>`. It accepts only the AVD names of the toolchain doc §7.1/§7.3. `acquire` takes an exclusive lease by creating ~/.android/avd/.jovra-lock with mkdir (atomic), waits or refuses with a clear message while another JOVRA lease is held, and creates the AVD from the installed android-35 google_apis arm64 image only if absent, writing the §7.1 config.ini values every time (disk.dataPartition.size=4G, fastboot.forceColdBoot=yes, hw.ramSize=4096, snapshots off). It refuses to create when free space would drop under 6 GB, and the caller then reports its emulator rows 'not run (disk)'. `release` drops the lease and deletes the AVD when free space is under 8 GB; `delete` refuses while the emulator is running or leased. It never touches another project's AVD (OlamyPixel). It creates nothing in this ticket. (2) The Android section of docs/DEVELOPING.md: JAVA_HOME for JDK 17, `-p android`, local Robolectric at sdk=34 (G-JDK21), the Roborazzi record round trip (roborazzi-record artifact → commit → android-unit verify), AVD names, the lease, the disk rules, the machine concurrency budget (at most 2 Android Gradle tickets, 1 emulator ticket and 1 iOS xcodebuild ticket at once while free space is under 14 GiB), `df -h /` at ticket start and `./gradlew -p android clean` at ticket end. Why blocked: A01 (the android/ tree and its scripts folder).

**Acceptance criteria**

- [ ] Script tests (bats or a shell harness with a fake avdmanager/emulator): an unknown name and `OlamyPixel` are rejected; a second `acquire` while the lease is held waits then refuses; `delete` refuses while leased; a stubbed `df` under 6 GB makes `acquire` refuse to create.
- [ ] The generated config.ini contains the four §7.1 values (test against the fake avdmanager output directory).
- [ ] docs/DEVELOPING.md gains an Android section only (diff stat) covering every item listed above.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Script test output
- DEVELOPING.md diff

**Owned areas**

- `android/scripts/avd.sh`
- `android/scripts/test/**`
- `docs/DEVELOPING.md (Android section only)`

**User stories:** 342, 343

**Gate:** none

## A04: Kotlin contracts and the conformance harness: :testing fixture walker, canonical JSON, strict session decoding, pct, units and record round-trips

`core-contracts-pct-units` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:core`

**Blocked by:** A01

**What to build:** The :core twin of iOS T03. :testing resolves the repository root from the `jovra.repoRoot` system property with `inputs.dir("../spec")` declared on every JVM test task, walks spec/fixtures, spec/studio/fixtures and spec/room/fixtures in place (never copied), and keeps one marker file per fixture kind under android/testing/conformance-kinds/<kind>.consumed|.pending; a kind with no marker fails the run (mirrors scripts/spec/validate.py), a `.consumed` kind with no registered runner fails, and an unconsumed fixture file under a consumed kind fails. Spec tickets that add a kind add a `.pending` marker; the Android ticket that ports the kind flips it. It also provides a canonical JSON comparator (deep equality, integers only) and a FakeMonotonicClock. :core gains the canonical JSON writer (sorted keys, no insignificant whitespace, UTF-8, integers as integers, refuses floats where the contract does), strict kotlinx.serialization decoding (unknown keys rejected, integral floats like 744.0 refused for integers, ids checked with ECMA-262 end-of-input semantics), the session document model for every field in spec/schemas (decodes jon-vs-alex.session.json), `pct(n, d) = (200n + d) / (2d)` in Long arithmetic with d = 0 → null, units in BigDecimal (≥ 20 digits, half-up once) for convert/display/gaugeHint, the capability registry reader with provenance labels, and record round-trips for equipment, practice plan and the capability registry. A source test fails if DecimalFormat, NumberFormat.getPercentInstance or roundToInt appear under :core. It also records the cross-DAG choice for markers: they stay a required android-core rule, so before this PR merges amendment issues are filed on T13, T31, T32, T52, S05-S09, S55 and S56 (each adds a `.pending` marker in the PR that adds its kind), and `.github/CODEOWNERS` routes android/testing/conformance-kinds/ to the Android owner. Why blocked: A01 (module skeletons, android-core job).

**Acceptance criteria**

- [ ] `spec/fixtures/stats/T01-integer-percentages.json` (32 cases: 24 ratio, 5 delta, 3 pool) passes case by case, including 1/8 → 13, 199/200 → 100, 1/201 → 0 and 0/0 → "—".
- [ ] `spec/fixtures/units/U01-exact-conversions.json` (31 vectors) passes; same-unit display returns the stored text untouched.
- [ ] equipment.sample.json, practice-plan.sample.json and capability-registry.v1.json decode with the real model types and re-encode canonically equal to the files.
- [ ] jon-vs-alex.session.json decodes; adding an unknown property and changing an integer to 744.0 each make decoding fail (negative tests); an id ending in a newline is refused.
- [ ] Mutation checks that must fail, shown in the PR with scratch commits: pct via a half-even formatter (1/8 case fails), a fixture file removed from the walk (manifest test fails), a new fixture kind with no marker (run fails), a `.consumed` marker with no runner (run fails).
- [ ] The banned-API source test fails on a scratch `DecimalFormat` import in :core.
- [ ] Markers exist for every kind present in the three fixture roots on merge day; kinds not ported here are `.pending` and are listed in the PR.
- [ ] `./gradlew -p android :core:test :testing:test` passes on JDK 17 without an Android SDK (android-core CI log).
- [ ] Amendment issues on T13, T31, T32, T52, S05-S09, S55 and S56 are linked in the PR before merge, and the CODEOWNERS line for android/testing/conformance-kinds/ is present.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Mutation transcripts
- Marker listing (consumed vs pending)

**Owned areas**

- `android/testing/** (except android/testing/claims/**, A10)`
- `android/core/json/**`
- `android/core/contracts/**`
- `android/core/pct/**`
- `android/core/units/**`
- `android/core/registry/**`
- `android/core/conformance/harness/**`
- `.github/CODEOWNERS (the conformance-kinds line only)`

**User stories:** 123, 175, 180, 337, 338

**Gate:** G-CORE (partial: pct, units, records)

## A05: Kotlin scoring engine: event-log resolution, rules fold, provisional scores, conflicts and the recalculation diff against every scoring fixture

`core-scoring-engine` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:core`

**Blocked by:** A04

**What to build:** The ScoringEngine twin of iOS T04, held to spec/fixtures/scoring. Event-log resolution (supersedes, insertBefore, voids, rally lets, penalties, terminations, doubles orders, checkpoints), the rules fold for every format in the fixtures (No-Ad, short sets, Fast4, match tie-breaks, advantage sets, best of 5, doubles rotation), provisional scores for unknown outcomes, conflict reporting, Rules vs As-played (hand-checked literal tests where the shared fixtures do not yet cover it; spec/README decision 12) and the per-checkpoint recalculation diff (`fold.changes`). Errors are typed with the fixture's code. Point events are the only input; no cached totals (ADR-0003). Flips the scoring marker to consumed. Why blocked: A04 (models, canonical JSON, harness).

**Acceptance criteria**

- [ ] All 74 files under spec/fixtures/scoring pass: 64 scoring cases (deep equality with `checkpoints[i].expected`, fold per checkpoint and `fold.changes`) and 10 rejections (E01–E10) throw the typed error with the expected code.
- [ ] A fixture's hand-derived `assertions` are printed first when a case fails (shown with a scratch mutation).
- [ ] Mutation that must fail: swapping the No-Ad deciding-point receiver choice turns the No-Ad fixtures red (scratch transcript).
- [ ] No floating-point type appears in the scoring package (source test).
- [ ] The scoring kind marker reads `.consumed`; android-core is green.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Scoring conformance report (per fixture pass list)

**Owned areas**

- `android/core/scoring/**`
- `android/core/conformance/scoring/**`

**User stories:** 88, 102, 103

**Gate:** G-CORE (scoring)

## A06: Kotlin stats, JSON and CSV data export byte-for-byte, the Jon vs Alex sample conformance and pooled trends

`core-stats-export-trends` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:core`

**Blocked by:** A05

**What to build:** The stats engine and exporters, twin of iOS T05. Stats from the fold (denominators kept), the screen-9 overview numbers, the session JSON export and both CSVs (UTF-8 without BOM, LF, minimal quoting, ASCII hyphen-minus in deltas), export.json and archive.json size and hash checks, and pooled trends (numerators and denominators summed, never averaged percentages). Flips the stats and sample markers. Why blocked: A05 (fold).

**Acceptance criteria**

- [ ] spec/fixtures/stats T02, T03 and T04 pass with deep equality.
- [ ] The `jovra.fixture.sample` case passes: the real decoder loads jon-vs-alex.session.json (124 points), fold and stats deep-equal the expected file, the overview equals the screen-9 numbers, and jon-vs-alex.points.csv and jon-vs-alex.stats.csv are reproduced byte for byte.
- [ ] export.json and archive.json sizes and hashes match their files.
- [ ] Mutations that must fail: CRLF line endings (sample CSV fails), a UTF-8 BOM (fails), a Unicode minus in a delta (fails).
- [ ] Pooled-trend unit tests use hand-checked literals (24/50, 33/60 pooled ≠ mean of percentages) and pass.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Byte-diff output of both CSVs (empty)

**Owned areas**

- `android/core/stats/**`
- `android/core/export/**`
- `android/core/trends/**`
- `android/core/conformance/sample/**`

**User stories:** 24, 123, 138

**Gate:** G-CORE (stats, sample)

## A07: Kotlin sample library: eight Sample sessions, equipment and practice plan from the reference generator, and the one sample-scope rule

`core-sample-library` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:core`

**Blocked by:** A06, T09

**What to build:** SampleContent for Android, built from the reference library that iOS T09 adds to the shared generator (8 sessions, 402 min, the Sep 9 string job linked to all 8, the sample practice plan) and the sample media manifest from T02. Pure :core: produce the documents, each flagged isSample, plus the sample-scope rule (samples count only when the whole scope is sample; any mixed scope excludes them; head-to-head excludes samples unless asked). Installing into storage is A09. Why blocked: A06 (stats for the summaries); T09 (the reference library oracle and the generator extension are produced there; Android must not re-derive them).

**Acceptance criteria**

- [ ] Kotlin summaries equal the reference library oracle: 8 sessions, 402 minutes, weekly pooled first-serve fractions 24/50, 33/60, 38/60, 40/60, all 8 linked to the Sep 9 string job.
- [ ] Sample-scope tests: an all-sample scope counts samples and is flagged Sample; one real session plus samples counts only the real one; head-to-head excludes samples by default.
- [ ] Every generated document carries isSample and validates against the session schema via the reference tooling in CI.
- [ ] Media references use the stable ids of the sample media manifest; a missing media id yields the missing-media state, not an exception (test).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Owned areas**

- `android/core/sample/**`

**User stories:** 16, 17, 18, 21

**Gate:** none

## A08: Android document store: atomic session folders, index rebuild, quarantine, migration, trash, preferences, backup exclusions and the Movies/JOVRA helper

`data-document-store` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:data`

**Blocked by:** A04, A02

**What to build:** `:data` SessionStore on app-specific storage (ADR-0002, AD8). One folder per session holding its media and session.json; writes go to a temp file, flush + fsync, then an atomic move (or AtomicFile). The library index is a cache rebuilt from folders; an unreadable document is quarantined with its reason, never deleted. Forward migration of older schema versions. Independent status facets as on iOS. Trash with restore and permanent delete. DataStore Preferences holds preferences only, with the full v1 key set (units, appearance, larger scoreboard, hands-free mapping, haptic/audio confirmations, Health, back up originals, Wi-Fi only, retention). The backup and data-extraction rule XML files the :app manifest already points at (A02) exclude every session and project folder, Studio caches and credential stores (preferences may back up). A MediaStore helper writes a user-owned copy to Movies/JOVRA (no permission on API 29+), never counted as a verified backup. A SampleInstaller seam with a stub under android/data/sample/ that reports 'Sample content not available yet', so the shell and harness do not wait for the sample library; A09 replaces the stub. Split from sample install so the UI spine does not wait on the iOS sample oracle (T09). Why blocked: A04 (document models, canonical JSON); A02 (the :app manifest that points at the backup XML files and the :data manifest).

**Acceptance criteria**

- [ ] Robolectric tests: a crash injected between temp write and move leaves the previous document intact; deleting the index then reopening rebuilds the same library listing.
- [ ] A document with an unknown field is quarantined with reason text and the rest of the library loads.
- [ ] A schema 1.0.0 document migrates forward and re-encodes canonically (test).
- [ ] The data-extraction rules XML excludes the sessions, projects and credentials directories (parsed in a unit test that fails if one exclude is removed).
- [ ] The MediaStore helper inserts into Movies/JOVRA under Robolectric's MediaStore shadow without requesting any READ_MEDIA permission (merged-manifest permissions check).
- [ ] The SampleInstaller stub returns its 'not available yet' state (test).
- [ ] No class in :data imports androidx.room or android.database.sqlite (source test).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Owned areas**

- `android/data/** (android/data/sample/** passes to A09)`
- `android/app/src/main/res/xml/backup_rules.xml`
- `android/app/src/main/res/xml/data_extraction_rules.xml`

**User stories:** 80, 81, 83, 155, 185

**Gate:** none

## A09: Sample install, byte-for-byte reset and remove on the document store

`data-sample-install` · android · size S · labels `ready-for-agent`, `platform:android`, `track:android`, `area:data`

**Blocked by:** A08, A07

**What to build:** Replaces A08's SampleInstaller stub: install the eight Sample sessions plus equipment and practice plan from A07, reset an edited sample byte for byte, and remove only sample objects. The harness sample adapter (A11) then uses this live implementation instead of its fake. Why blocked: A08 (store); A07 (sample documents, which wait on T09).

**Acceptance criteria**

- [ ] Sample install creates 8 sessions plus equipment and practice plan; reset restores an edited sample byte for byte; remove deletes only sample objects (Robolectric store tests).
- [ ] With the live installer bound, A11's harness self-test passes with the sample state installed.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Owned areas**

- `android/data/sample/**`

**User stories:** 20

**Gate:** none

## A10: Design-system components: provenance and Sample badges, status pills, state cards, capability detail, charts with spoken summaries and tables, and contrast tests

`designsystem-components` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:design-system`

**Blocked by:** A04, A02

**What to build:** `:designsystem` components that every screen uses (AD23), mirroring iOS T12: ProvenanceBadge (Manual, Estimated, Reviewed, Validated), Sample badge and DemoBanner, StatusPill, StateCard (empty, loading, error, offline, missing media), the fraction popover (a stat reveals its numerator/denominator in one tap), the capability detail sheet content (status, method, tested on, 'Not available on Android yet'), buttons and rows at 48 dp (64 dp capture controls, 76 dp Stop), tiles, focus indicators on every interactive element, selection by fill + check + weight, markers by shape, and charts drawn in Compose (no chart library) with semantics: a spoken trend summary and a 'Show as table' alternative. Font: the system font unless the iOS brand font's licence allows Android embedding (checked and recorded). A component gallery is reachable through the harness. An Android-wide copy and claim lint (a JVM test in :testing that scans every strings_*.xml and Compose string literal in :app, :feature:*, :studio:* and :wear, so it runs in android-core) bans automatic In/Out verdict wording, "live" with speed units, "fastest" without "marked", spin/RPM, injury or medical claims, "Validated" for sync, and named-device claims without "approximated", with a listed exceptions file. Why blocked: A02 (theme); A04 (provenance and capability registry models).

**Acceptance criteria**

- [ ] A contrast test over every component colour pair in light, dark and high contrast fails when a role is weakened (scratch mutation).
- [ ] ProvenanceBadge renders the four labels from the registry model; a value without provenance cannot be constructed (compile-time or test).
- [ ] Charts expose a spoken summary and a table alternative to TalkBack (semantics assertions) and render without animation when the animator duration scale is 0.
- [ ] Status and markers are distinguishable without colour: a greyscale Roborazzi variant of the gallery is recorded.
- [ ] The font licence decision is recorded in the PR with its source.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] The claim lint fails on each banned phrase planted in a scratch strings file and passes on main; the exceptions file is listed in the PR.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Roborazzi gallery images

**Owned areas**

- `android/designsystem/components/**`
- `android/designsystem/charts/**`
- `android/designsystem/gallery/**`
- `android/testing/claims/**`

**User stories:** 139, 166, 168, 169, 170, 171, 173, 175, 177

**Gate:** none

## A11: App shell: Navigation 3 saveable back stack, every typed route and sheet as an owned placeholder, the state harness, the composition root and the network trap

`app-shell-routes-harness` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:foundation`

**Blocked by:** A08, A10

**What to build:** The Android counterpart of iOS T07's routing half, so no later ticket edits :app. Navigation 3 back stack of @Serializable keys per destination (IDs, never objects), saved across process death. Every route of android-v1-spec (core screens A01–A20, N1–N12, and Studio screens 41–60 including full-screen capture, replay, compare, review deck, director capture, project player, storyboard) and every sheet is declared with its payload and resolves to a placeholder file `<module>/placeholder/<Route>Placeholder.kt` in the owning feature module that names the ticket id that builds it; that ticket deletes the file and owns it from then on. A test harness reads intent extras `jovra.route` and `jovra.state` (installs the sample and demo adapters, opens any route in any registered state); each feature registers its own states in its own file; the sample adapter uses a fake until A09 lands. Composition root with plain constructor injection and fake/live seams (PermissionsCenter interface, clock, camera capability query, Drive, room, watch bridge status, cloud, SampleInstaller). Edge-to-edge insets helpers in :designsystem. A UI-test base with a network trap that every screen ticket's demo-state test uses. App shortcuts declared as placeholders for A54. The live PermissionsCenter, guarded back and the IME helper are A12. Why blocked: A08 (store and the SampleInstaller seam); A10 (components the placeholders and harness render).

**Acceptance criteria**

- [ ] Navigation tests cover every declared route and sheet: each key round-trips through saved state; system back pops one level, then the destination start, then Home, then exits (story 206).
- [ ] A harness self-test opens every registered route/state; an unknown state fails with a listed error; each placeholder shows the owning ticket id.
- [ ] Process-death test (saved-state round trip) restores the selected destination and a pushed route's ID payload.
- [ ] The network trap fails a deliberately networked scratch test and records zero requests across the harness self-test.
- [ ] Insets helpers keep content clear of cutouts, status bar and gesture handle at 360 dp and 1280 dp (Robolectric insets tests).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Harness self-test output

**Screens**

- design-reference/screens/08-session-library.png (derived; hierarchy and copy only) (navigation only)

**Owned areas**

- `android/app/navigation/**`
- `android/app/harness/**`
- `android/app/di/**`
- `android/designsystem/insets/** (android/designsystem/insets/ime/** passes to A12)`
- `android/testing/ui/**`
- `android/feature/*/placeholder/**`
- `android/studio/*/placeholder/**`

**User stories:** 193, 206, 345, 346

**Gate:** none

## A12: PermissionsCenter, guarded and sheet-first back, the 48 dp Close and the on-screen-keyboard inset helper

`permissions-back-ime` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:foundation`

**Blocked by:** A11

**What to build:** PermissionsCenter for CAMERA, RECORD_AUDIO, POST_NOTIFICATIONS and NEARBY_WIFI_DEVICES with status, rationale, consequence text and the app-settings intent; the fake for tests; never an imitation system dialog and never a request at launch. Predictive back on; a guarded-screen helper that opts out of the preview and confirms with the safe default ('Discard changes?' / Keep editing); sheet-first back; a 48 dp Close at top start on full-screen routes. An IME-inset helper so a screen's primary or confirm action stays visible above the on-screen keyboard (story 194), which A56 and A73 assert on real screens. Why blocked: A11 (composition root seams, harness).

**Acceptance criteria**

- [ ] A guarded placeholder opts out of predictive back and shows a confirmation with the safe default; an open sheet consumes back first (tests).
- [ ] The fake PermissionsCenter drives granted, denied, permanently denied and not-requested for each permission and the consequence text is asserted; the live adapter never requests at launch (launch test with a recording fake).
- [ ] IME helper self-test: with the IME shown at 360 x 480 dp and font scale 2.0, the confirm button of a sample form stays fully visible (Robolectric insets test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Owned areas**

- `android/app/permissions/**`
- `android/designsystem/permissions/**`
- `android/designsystem/back/**`
- `android/designsystem/insets/ime/**`

**User stories:** 162, 207, 208, 209

**Gate:** none

## A13: Court geometry and 4-tap calibration maths in :core with the court diagram, markers, perspective guide and loupe handle

`court-geometry-calibration` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:core`

**Blocked by:** A10

**What to build:** Twin of iOS T13. :core CourtGeometry holds the ITF court in metres (lines, zones, depth bins; the centre service line only between the service lines and the net) and CourtCalibration fits a homography by normalized DLT (exact 4-point solve, least squares with more), projects/unprojects on the ground plane only, checks reprojection RMSE (accept ≤ 3 px at 1080p) and binds validity to lens, format, zoom and the stale-from time. If spec/fixtures/calibration exists on merge day (iOS T13 adds it), every case passes and the marker flips; otherwise hand-checked literal tests and a `.pending` marker. :designsystem gains CourtDiagram (full, half, service box, depth bands), CourtMarker (filled circle In, triangle Out, ring Needs review, diamond Bookmark, square outline Unscored), PerspectiveCourtGuide and a CornerHandle with a 2× loupe exposed to TalkBack as an adjustable control. Why blocked: A04 (harness); A10 (components).

**Acceptance criteria**

- [ ] Homography tests: exact 4-point round trip within 1e-9 m on hand-checked corners; an RMSE above 3 px at 1080p is rejected with a reason.
- [ ] Calibration fixture cases (if present) all pass; otherwise the marker reads `.pending` and the literal tests are listed.
- [ ] CourtDiagram dimensions match ITF metres at three scales (Roborazzi plus a geometry unit test); markers differ by shape in a greyscale render.
- [ ] The loupe handle moves by one step per TalkBack adjust action (semantics test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/05-court-calibration.png (derived; hierarchy and copy only)
- design-reference/screens/11-shot-map.png (derived; hierarchy and copy only)

**Owned areas**

- `android/core/court/**`
- `android/designsystem/court/**`

**User stories:** 41, 124

**Gate:** none

## A14: Shared pane-policy contract (F-PANE-VECTORS): golden vectors, a Python reference and a validator with its own CI workflow

`pane-policy-shared-vectors` · android · size M · labels `ready-for-agent`, `platform:shared`, `track:android`, `area:adaptive`

**Blocked by:** None (can start immediately)

**What to build:** ADR-0025 §8 and android-v1-spec AND-1e. New files only: `spec/adaptive/pane-policy.vectors.json` holding golden vectors for the pure function `(widthDp, heightDp, posture, hinge, textScaleBand, task) → (panes, navigation)`, a dependency-free Python reference `spec/adaptive/reference/pane_policy.py`, `scripts/spec/validate_adaptive.py`, and `.github/workflows/adaptive.yml` running the validator on pull requests (android.yml and ci.yml are not edited). Vectors cover every width class × height class, font scale ≥ 1.5 removing one pane (never below 1), compact height capping at 2 with player priority, a separating vertical hinge → exactly 2 split at the hinge, an occluding hinge, tabletop, and input mode not changing pane count. Posture vectors are marked so the iOS port can skip them by name (ADR-0025 §5). Reviewed by the spec/ contracts owner in the PR. It has no Android dependency, so it can start on day one and both platform ports (A15, W22) wait only on it. Why blocked: nothing.

**Acceptance criteria**

- [ ] `python3 scripts/spec/validate_adaptive.py` passes and prints the vector count; a scratch mutation that removes the font-scale rule from the reference makes it fail.
- [ ] adaptive.yml runs on a pull request; a broken vector in a scratch branch turns it red (run link).
- [ ] Every category listed above has at least one vector, and posture vectors carry the `posture` tag (validator check).
- [ ] No existing file under spec/ changes (diff stat); the spec owner's review is recorded.

**Evidence required**

- validate_adaptive.py output
- adaptive.yml run links

**Owned areas**

- `spec/adaptive/**`
- `scripts/spec/validate_adaptive.py`
- `.github/workflows/adaptive.yml`

**User stories:** 203, 204

**Gate:** G-PANE (contract)

## A15: Kotlin pane policy held to the shared vectors, and the adaptive scaffolds: list/detail, supporting pane, hinge split, tabletop and compact height

`pane-policy-kotlin-adaptive-scaffold` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:adaptive`

**Blocked by:** A14, A11

**What to build:** Kotlin PanePolicy in :core passes every vector of spec/adaptive/pane-policy.vectors.json. :designsystem adaptive wrappers over NavigableListDetailPaneScaffold / NavigableSupportingPaneScaffold read currentWindowAdaptiveInfo (never device names or hard-coded breakpoints), split panes at a separating hinge, keep controls off hinge bounds, switch video screens to tabletop, and turn supporting panes into sheets at compact height. Every hinge or posture result in this and later tickets is labelled 'injected FoldingFeature (window-testing)' or 'emulator posture, pixel_9_pro_fold profile (approximation)'. Why blocked: A14 (vectors); A11 (shell navigation the rail/bar switch lives in, and A10's components through it).

**Acceptance criteria**

- [ ] Kotlin PanePolicy passes every vector (dynamic test per vector); a mutation using width alone fails the compact-height vectors.
- [ ] window-testing publisher tests: separating vertical hinge → two panes split at the hinge with no focusable node intersecting hinge bounds; occluding hinge → no content in bounds; tabletop → video above, controls below; height < 480 dp → supporting pane rendered as a sheet; each result labelled 'injected FoldingFeature (window-testing)'.
- [ ] A grep finds no `Build.MODEL`, `isTablet` or numeric dp breakpoint in routing code.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- window-testing screenshots per posture

**Owned areas**

- `android/core/layout/**`
- `android/designsystem/adaptive/**`

**User stories:** 187, 188, 189, 190, 191, 192

**Gate:** G-PANE (Kotlin)

## A16: Welcome, three-step onboarding, Profile hub and demo entry

`welcome-onboarding-profile` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:onboarding`

**Blocked by:** A12, A09

**What to build:** Screens A01/A02 and N11 on Android. Welcome with the Court Arc mark, 'See your game.', 'Get started' and an understated 'Explore a demo' and no sign-in (AD5). Onboarding in three steps with a Material linear progress indicator and 'Step 2 of 3', name + initial avatar, handedness and backhand as segmented buttons, level and goals as filter chips (check + weight), step 3's ownership copy including 'Uninstalling JOVRA deletes footage kept only on this phone.', no permission requests, back to the previous step, state kept through rotation, fold and process death. Profile hub with edit profile and declared slots for Studio settings (A63), equipment (A46) and a restore offer (A50). 'Explore a demo' installs the sample via A09. Why blocked: A12 (PermissionsCenter fake the no-request assertion uses, and A11 routes through it); A09 (sample install behind "Explore a demo").

**Acceptance criteria**

- [ ] Copy assertions against design-reference/brief/screens.json for screens 01 and 02 with the Android copy changes; no 'Sign in' string exists in the welcome screen tree.
- [ ] Onboarding never calls PermissionsCenter.request (fake records zero requests across the flow).
- [ ] Rotation and saved-state process-death tests keep the step, the name and chip selections.
- [ ] Back on step 2/3 returns to the previous step; on step 1 returns to welcome.
- [ ] Explore a demo installs 8 Sample sessions and lands on Home with the DemoBanner.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Roborazzi images vs references 01, 02 side by side

**Screens**

- design-reference/screens/01-welcome.png (derived; hierarchy and copy only)
- design-reference/screens/02-player-onboarding.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/profile/onboarding/**`
- `android/feature/profile/hub/**`
- `android/feature/profile/placeholder/{Welcome,Onboarding,ProfileHub}Placeholder.kt (A11's placeholder; deleted here)`

**User stories:** 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 19

**Gate:** none

## A17: Home dashboard: greeting, stat tiles, latest session, weekly chart and next-step row

`home-dashboard` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:home`

**Blocked by:** A11, A09

**What to build:** Screen A03 (Home) on Android. Large top app bar that collapses, 'Your game, in focus.', the 'Ready for your next session?' card opening session setup, three stat tiles and the latest-session card computed from stored sessions with denominators one tap away, the 'This week' chart with spoken summary and table, the next useful action, the sample-scope rule, a declared Studio card slot (A63), and a wider grid on medium and wider windows with the same order. Why blocked: A11 (routes, harness); A09 (installed sample library the tiles are tested against); A06 (stats and trends). Implied through other blockers and not repeated as edges: A06.

**Acceptance criteria**

- [ ] Tiles equal Kotlin stats over the installed library (test against A07 oracles); an all-sample library shows the Sample badge on the block; one real session hides sample counts.
- [ ] 'Record a session' opens the Record destination's setup route (navigation test).
- [ ] At 840 dp width the cards lay out in two columns with the same order (Roborazzi + semantics order test).
- [ ] Copy assertions for screen 03 with the Android changes.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/03-home.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/home/dashboard/**`
- `android/feature/home/placeholder/HomePlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 22, 23, 24, 25, 26

**Gate:** none

## A18: Session library: search, filters, independent status facets, Only on this phone, Trash with Undo and quarantine, list beside overview on wide windows

`session-library` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:sessions`

**Blocked by:** A15

**What to build:** Screen A08 (Library) on Android. 'Your sessions' with a search bar, All/Matches/Practice filter chips, cards with independent facets (analysis, review, archive, storage), 'Only on this phone' with size, 'Also save to Movies/JOVRA', delete to Trash with an Undo snackbar and exact permanent-delete text, quarantined documents shown with their reason, an Import action, and list | overview at medium width or wider (the detail pane hosts whatever the overview route resolves to: A11's placeholder until A20 lands). Why blocked: A15 (list/detail scaffold); A08 (store, facets, trash). Implied through other blockers and not repeated as edges: A08.

**Acceptance criteria**

- [ ] Facet combinations from the store render independent pills (tests over every facet state).
- [ ] Delete → Undo restores the session; permanent delete removes its folder (store assertion).
- [ ] A quarantined fixture document appears with its reason and does not crash the list.
- [ ] At 840 × 900 dp the list and the selected session's overview placeholder show side by side; at 360 dp selecting pushes a new screen; back returns to the list (tests).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/08-session-library.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/sessions/library/**`
- `android/feature/sessions/placeholder/LibraryPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 79, 80, 81, 82, 83, 84, 85

**Gate:** none

## A19: Session setup: modes, players, formats, doubles order, CameraX-supported presets, storage range and setup drafts

`session-setup` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:record`

**Blocked by:** A15, A05

**What to build:** Screen A04 (Session setup, the Record root) on Android. Modes, players, every format preset with doubles order and Ad/No-Ad, the camera preset row listing only the qualities and frame rates the camera capability query reports (fake in tests; the live adapter uses CameraX isSessionConfigSupported in A22), 120/240 fps for practice only, a storage estimate as a range, the microphone row copy, 'Check camera position', last setup remembered, bottom-sheet editors on compact and list | editor pane on wide, a declared gear-row slot (A47), and setup drafts written to disk on change (debounced) so they survive process death. Why blocked: A15 (list | editor scaffold; A11 routes through it); A05 (format rules).

**Acceptance criteria**

- [ ] Format choices produce the same match-format record the scoring fixtures use (round-trip test for each preset).
- [ ] With a fake capability set lacking 60 fps, the preset row omits it; 240 fps appears only for a practice session (tests).
- [ ] A setup draft survives a saved-state process-death test and an app restart (disk draft reload).
- [ ] Copy assertions for screen 04 with Android changes.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/04-session-setup.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/record/setup/**`
- `android/feature/record/placeholder/SetupPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 28, 29, 30, 31, 32, 33, 34, 35

**Gate:** none

## A20: Match overview: scoreboard, stats with denominators, momentum, point history, head-to-head and explicit results

`match-overview` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:sessions`

**Blocked by:** A15, A06

**What to build:** Screen A09 (Match overview) on Android: match header, scoreboard, headline metrics with fractions one tap away, source insights, momentum, point history, head-to-head (samples excluded), explicit result types (retired, default, walkover, incomplete), 'Watch match' and 'Review N flagged points' actions, a declared 'Make a film' slot (A63), stats in the main pane and point history in a supporting pane on expanded windows. Why blocked: A15 (supporting-pane scaffold); A06 (stats). It renders standalone from its route; the path from the library is tested in A56, not here.

**Acceptance criteria**

- [ ] The sample overview equals the fixture's screen-9 `overview` numbers (test).
- [ ] A retirement fixture shows the explicit result text; an incomplete match is labelled so.
- [ ] At expanded width the point history is a supporting pane; at compact it is a section below (Roborazzi + semantics).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/09-match-overview.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/sessions/overview/**`
- `android/feature/sessions/placeholder/MatchOverviewPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 86, 87, 88, 89

**Gate:** none

## A21: Media3 playback core: exact seeking, PTS-index frame steps, rates and A–B loop, with the video surface, jog strip and transport, proven on frame-counter fixtures

`media-playback-core` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:media`, `resource:emulator`

**Blocked by:** A10, A03, T10

**What to build:** `:media` PlaybackController on ExoPlayer with exact seeking and scrubbing mode; frame steps from a decoded PTS index built at probe time (pause, exact seek to the neighbouring frame's timestamp) because Media3 has no frame-step API; rates 0.25×–2×; A–B loop; a frame/time/fps readout. :media exports VideoSurface (android/media/ui/video), so no other module references Media3; :designsystem holds JogStrip (≥ 48 dp, above the bottom gesture inset, edge hold areas with gesture exclusion within Android's limit, exposed as an adjustable control) and Transport, with no Media3 types. Instrumented tests use iOS T10's frame-counter fixtures (24/30/60/120/240 fps) rendered from the repository script into the ignored cache and pushed to the AVD. Whichever of this ticket, A22 or A28 runs first creates jovra_phone_p9_api35 under the avd.sh lease. Why blocked: A10 (components); A03 (avd.sh lease); T10 (the frame-counter fixture script and its decoded-frame hashes are produced there).

**Acceptance criteria**

- [ ] Instrumented test on jovra_phone_p9_api35: for each fps, decoding frame N yields counter N at sampled frames, and ±1 step lands on the exact neighbour (including across a GOP boundary).
- [ ] Rate changes to 0.25×, 0.5×, 1×, 2× are reflected in the readout; an A–B loop repeats within ±1 frame of A and B.
- [ ] JogStrip exposes progressBarRangeInfo with setProgress stepping one frame per adjust action (semantics test).
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] Evidence is labelled 'emulator, software decoder' with the codec name; device decoding is not claimed.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- connectedDebugAndroidTest output with AVD name, profile and image
- df -h before/after

**Screens**

- design-reference/screens/10-smart-replay.png (derived; hierarchy and copy only) (transport only)

**Owned areas**

- `android/media/playback/**`
- `android/media/ui/video/**`
- `android/designsystem/video/** (JogStrip, Transport; no Media3 types)`

**User stories:** 91, 92, 93, 165, 211

**Gate:** AVD jovra_phone_p9_api35 (disk)

## A22: CameraX recording engine: one segment per Recording behind the ADR-0010 journal, finalize mapping, preflight, thermal ladder state machine and the emulator fixture camera

`recording-engine` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:capture`, `resource:emulator`

**Blocked by:** A08, A03, T10

**What to build:** AD10/AD11. :core holds the pure parts, JVM-tested: the write-ahead journal state machine (session id, segments, gaps with reasons, last confirmed media time, thermal and frame-rate changes, 'saved through'), recovery decisions and the thermal ladder (NONE/LIGHT normal; MODERATE helpers off; SEVERE court mode; CRITICAL 30 fps at the next safe rebind as a new segment; EMERGENCY clean finish). :media RecordingEngine: one CameraX Recording per segment to a FileOutputOptions file in the session folder, rollover on interruption, pause or format change, every VideoRecordEvent.Finalize error mapped to a gap reason with the output file always checked and kept if it decodes, preflight (supported qualities and fps via isSessionConfigSupported, storage range = bitrate × length × 1.2 then the measured slope, battery, thermal status and headroom), and test hooks that inject interruptions, thermal rungs, low storage and crashes. The emulator's back camera plays iOS T10's fixture-camera clip so the real CameraX path runs; first verify which emulator camera mode can play a file (video-file/virtual scene) and record the result (UNVERIFIED today); debug builds label capture 'Emulator fixture camera'. The MediaCodec + fragmented-MP4 fallback is an interface only. :media also exports the camera preview composable (android/media/ui/preview) that framing and the director screens use, so no other module references CameraX. Why blocked: A08 (session folders); A03 (avd.sh lease); T10 (fixture-camera clip).

**Acceptance criteria**

- [ ] JVM tests of the journal: every gap reason, thermal rung and format change is journalled; replaying a journal reproduces the segment list.
- [ ] Instrumented on jovra_phone_p9_api35: record 60 s with an injected home-press at 20 s → two segments and one gap 'left JOVRA'; each segment decodes to its end.
- [ ] Each Finalize error code in the mapping table has a unit test; a FILE_SIZE_LIMIT_REACHED result keeps the decodable file.
- [ ] An injected CRITICAL rung produces a new segment at 30 fps journalled as a format change.
- [ ] The 'Emulator fixture camera' label appears only in debug builds (release manifest/resources test).
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] The report says 'emulator, fixture camera'; durability, 60 fps and heat are listed under the Pixel hardware gate, not claimed.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- connectedDebugAndroidTest output
- Note on which emulator camera mode played the fixture

**Owned areas**

- `android/core/journal/**`
- `android/core/thermal/**`
- `android/core/recovery/**`
- `android/media/capture/**`
- `android/media/ui/preview/**`

**User stories:** 44, 46, 48, 60, 65, 66, 68

**Gate:** Hardware: Pixel (durability, fps, thermals)

## A23: Crash recovery: launch scan decoding every segment to the end, torn segments, gap reports and the Resume prompt

`crash-recovery` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:capture`, `resource:emulator`

**Blocked by:** A22, A18

**What to build:** RecoveryScanner at launch (ADR-0010): for each session with an open journal, decode every segment to its end with MediaExtractor, keep every playable segment, record torn tails as gaps, write a gap report ('Gap 41:12–41:31 · left JOVRA'), and surface 'Recording stopped at 41:12 — Resume?' and recovered states in the library. Why blocked: A22 (journal and engine); A18 (library shows recovered sessions). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Instrumented: `adb shell am kill` mid-segment, relaunch → the scan recovers the session with its segments decoding to the end and the gap listed.
- [ ] A truncated segment fixture is recovered up to its last decodable frame; the loss is stated in words.
- [ ] Recovery never deletes a file (test with an undecodable segment: kept and reported).
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Kill-and-recover transcript

**Owned areas**

- `android/media/recovery/**`
- `android/feature/sessions/recovery/**`

**User stories:** 62, 63, 64, 67

**Gate:** Hardware: Pixel (crash loss ≤ 3 s)

## A24: Capture route and recording screen: REC, save status, Mark and Stop, guarded back, pause/resume, ongoing notification and interruptions as gaps

`capture-route-recording` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:record`, `resource:emulator`

**Blocked by:** A19, A22, A12

**What to build:** Screen A06 (Recording) on Android through the emulator fixture camera. Full-screen recording with bars hidden (edge-swipe reveal), persistent REC and timer, save status ('Video saved on this phone', 'Saved through 41:12'), Mark point (64 dp) and Stop (76 dp), back and predictive back opening 'Stop recording?' with Keep recording as the default, pause closing the segment and resuming into the same session, keep-awake only while recording, an ongoing notification with REC time and save status (only if notifications are granted; the in-app status is always there), camera and microphone requested through PermissionsCenter at the moment of need (video records with mic denied), 'Delete this recording', interruptions closing the segment with a visible gap, a layout that never depends on an orientation lock (Android 16 large-screen behaviour itself is not verified without G-IMG36), and declared slots for the scoreboard (A26), budget warnings (A27) and 'String broke' (A47). Why blocked: A19 (setup → capture); A22 (engine); A12 (PermissionsCenter, guarded back). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] UI test: setup → capture → stop → SessionStore holds the session folder with its segment list and closed journal (store assertion; the library is not needed). Navigating from the framing route key to capture opens this route (navigation test against A11's key, whether or not A25 has landed).
- [ ] Back during recording shows 'Stop recording?' and Keep recording leaves REC running (test).
- [ ] Mic denied via the fake: recording proceeds and audio features show 'unavailable' with reason.
- [ ] Screen-off and home during recording each close the segment with a gap; resume continues the same session.
- [ ] Stop and Mark meet 76 dp and 64 dp (semantics bounds).
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] A display change during recording (window-testing resize/fold, or an emulator posture action) closes the segment with gap reason 'display changed'; a copy lint finds no string promising that recording survives a fold (stories 199-200).
- [ ] The capture screen tree contains no live ball speed, skeleton or line-call element (semantics and copy test).
- [ ] Android 16 orientation/resizability override on an API 36 system image: not run unless G-IMG36 and G-DISK passed, and reported as such; Robolectric resize tests cover the layout without the lock.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Recording screen screenshots (portrait, landscape)

**Screens**

- design-reference/screens/06-live-capture.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/record/capture/**`
- `android/feature/record/placeholder/CapturePlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 46, 47, 48, 49, 55, 56, 59, 60, 61, 54, 199, 200

**Gate:** Hardware: Pixel

## A25: Court framing and 4-corner calibration with the live checklist, loupe and microphone explainer

`framing-calibration` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:record`, `resource:emulator`

**Blocked by:** A19, A22, A13, A12

**What to build:** Screen A05 (Framing): near-full-screen preview with 'Frame your court', the perspective guide, a live checklist sheet, four corner taps with the loupe (calibration optional before recording), widest suitable lens and AE/AF lock after framing where CameraX allows, the preset pill, landscape controls clear of cutouts and gesture areas, the camera permission explanation then the system dialog with 'Open app settings' after a permanent denial, the microphone explainer, and 'Start recording', which navigates to the capture route (A11's key; the capture screen itself is A24). The preview is A22's :media composable. Why blocked: A19 (setup hands over the session draft); A22 (camera preview and lens control in :media); A13 (calibration maths, loupe); A12 (camera permission explanation). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Corner taps on the fixture-camera frame produce a calibration whose RMSE check passes on the synthetic court (instrumented).
- [ ] Permanently denied camera shows the explanation and 'Open app settings' and blocks nothing else (fake).
- [ ] No control intersects the display cutout or system-gesture insets in landscape (insets assertion).
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/05-court-calibration.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/record/framing/**`
- `android/feature/record/placeholder/FramingPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 36, 37, 38, 39, 40, 41, 42, 43, 45

**Gate:** none

## A26: Live manual scoring, Mark point, bookmark notes, changeover checkpoint entry and volume-key/headset Mark

`live-scoring-marks-handsfree` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:record`, `resource:emulator`

**Blocked by:** A24

**What to build:** Fills A24's scoreboard slot: a compact scoreboard badged 'Manual score', one-tap point buttons with the server shown, undo, Mark point with a receipt, bookmark notes, changeover checkpoint entry (no auto-fill; A33), and AD12 hands-free: volume keys and a headset media button map to Mark point only while the capture screen is resumed, never to Stop, switchable in settings (A51 renders the toggle). Points are appended as events and the score is the fold (ADR-0003). Why blocked: A24; A05. Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Tapping points appends events whose fold equals a scoring fixture's expected score at that checkpoint (test replaying a fixture through the UI).
- [ ] Undo voids the last point and the score recomputes.
- [ ] A volume-down key event while resumed creates a Mark; while paused or backgrounded it does nothing; with the toggle off it changes volume (tests).
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/06-live-capture.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/record/scoring/**`

**User stories:** 50, 57, 58

**Gate:** Hardware: Pixel (headset range UNVERIFIED)

## A27: Device budget during capture: thermal ladder UI, court mode, low battery and low storage

`capture-device-budget` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:record`, `resource:emulator`

**Blocked by:** A24

**What to build:** Fills A24's budget slot: the thermal ladder following PowerManager thermal status and headroom (polled ≤ 1/s), 'Phone warming · Analysis paused', court mode blacking out the preview while REC/timer/save status stay visible (unbinding the preview only if a test shows the recording survives), low-battery and low-storage warnings with minutes as a range from StatFs and a clean finish, and non-essential work paused first. Why blocked: A24. Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Each injected rung shows its UI state and journals the rung (instrumented with test hooks).
- [ ] Court mode keeps REC, timer and save status visible and announced politely to TalkBack.
- [ ] Injected low storage stops recording cleanly with the segment decodable.
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/06-live-capture.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/record/budget/**`

**User stories:** 51, 52, 53, 172, 186

**Gate:** Hardware: Pixel (thermals)

## A28: Import from the photo picker and Files with per-file results, duplicates and drag-and-drop

`import-photo-picker-saf` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:sessions`, `resource:emulator`

**Blocked by:** A11, A03, T10

**What to build:** Screen A07 (Import): 'Bring your game in' with Photos (PickVisualMedia VideoOnly; no READ_MEDIA_VIDEO), Files (ACTION_OPEN_DOCUMENT) and a Google Drive tile that explains Drive videos import through Files today; copy inside the result callback into a new session folder; probe duration, fps, codec, dimensions, rotation and HDR; HDR→SDR transcoding disabled by declaring media capabilities; content-hash duplicates; per-file results with specific unsupported reasons; cancel cleanup; 'Waiting for download' for cloud-only files; manual 90° rotation as metadata; drag-and-drop onto the import screen on tablets. Persistable grants only where needed. Why blocked: A11 (route, harness); A08 (session folders); A03 (avd.sh lease); T10 (import fixture set and ground truth). Implied through other blockers and not repeated as edges: A08.

**Acceptance criteria**

- [ ] Each T10 import fixture's probed facts equal its ground truth (instrumented).
- [ ] The duplicate pair yields one session and a 'Duplicate' result; the unsupported codec gets its specific message.
- [ ] The merged manifest contains no READ_MEDIA_* permission (manifest test).
- [ ] A cancelled import leaves no session folder (store assertion).
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/07-import-processing.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/sessions/import/**`
- `android/media/importer/**`
- `android/feature/sessions/placeholder/ImportPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 69, 70, 71, 72, 73, 74, 75, 205

**Gate:** none

## A29: Processing queue on WorkManager with checkpoints and the processing screen's stage timeline

`processing-queue` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:sessions`

**Blocked by:** A28, A22

**What to build:** The processing-queue state machine in :core (JVM-tested) and its WorkManager runner with a mediaProcessing foreground service where allowed, chunked checkpoints, clean stop on the foreground-service time-out and resume later; the processing screen's stage timeline (Saved locally, Preparing replay, Analyzing points, Backing up) with 'Demo processing state' in the demo; a failed analysis leaves the video viewable with 'Retry analysis'. Why blocked: A28 (imported sessions to process); A22 (recorded sessions enqueue on stop).

**Acceptance criteria**

- [ ] JVM tests over every queue transition including time-out → paused → resumed from the last checkpoint.
- [ ] WorkManager test (work-testing) proves a stage resumes from its checkpoint after cancellation, not from zero.
- [ ] An injected analysis failure leaves replay available and shows 'Retry analysis'.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/07-import-processing.png (derived; hierarchy and copy only)

**Owned areas**

- `android/core/queue/**`
- `android/feature/sessions/processing/**`
- `android/feature/sessions/placeholder/ProcessingPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 76, 77, 78, 182, 183

**Gate:** none

## A30: Smart replay: score overlay from the fold, event timeline, filters, point card, one-tap winner correction, tabletop and keyboard

`smart-replay` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:replay`, `resource:emulator`

**Blocked by:** A21, A15, A05

**What to build:** Screen A10 (Replay): full-screen replay with a 16:9 video, the score overlay derived from the fold at each presentation time (video-frame metadata listener), event timeline, filter chips with empty-filter messages, current-point card, one-tap winner correction propagating to every later score, captions, landscape full screen, tabletop posture (video above the fold; jog, transport and point card below), video | point list supporting pane on wide windows, keyboard shortcuts (space, arrows, shift-arrows by point, J/K/L), TalkBack point-by-point navigation, and playhead/rate/point/loop preserved through rotation, fold and process death (rational time, restored paused). Why blocked: A21 (player, jog strip); A15 (supporting pane and tabletop scaffolds); A05 (fold). Replay is reached through its own route; it does not wait for the overview screen. Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Overlay text equals the fold at 20 sampled frames of the sample session (instrumented, frame-counter mapping).
- [ ] Correcting a winner updates the overlay and the fold the overview reads, in the same run (store assertion; the overview UI path is tested in A56).
- [ ] Tabletop window-testing publisher puts video above the hinge and controls below; book/flat shows the supporting pane.
- [ ] Saved-state process death restores the same playhead (rational time) paused and the same selected point.
- [ ] Shift-right moves one point; J/K/L change rate (Robolectric key events).
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/10-smart-replay.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/sessions/replay/**`
- `android/feature/sessions/placeholder/ReplayPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 90, 94, 95, 96, 97, 98, 99, 101, 164

**Gate:** none

## A31: Point editor: add, split, merge, delete, nudge, Unknown, stroke tags, conflict banners and Rules vs As-played

`point-editor` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:review`

**Blocked by:** A30

**What to build:** Twin of iOS T29 inside replay and the overview: flip winner, add a missed point, split, merge, delete, nudge, mark Unknown, stroke tags, conflict banners, Rules vs As-played, the recalculation diff shown before saving; automatic suggestions stored separately from user decisions; corrections survive re-analysis; draft corrections written to disk. Every later score, stat and export recomputes (hard rule 4). Why blocked: A30 (replay host).

**Acceptance criteria**

- [ ] Each editor operation produces events whose fold equals a hand-built scoring fixture (one test per operation).
- [ ] An edit that moves later points into a different service game shows the serverMismatch conflict from the fixture.
- [ ] A draft correction survives process death (disk) and is discarded only after 'Discard changes?'.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/10-smart-replay.png (derived; hierarchy and copy only)
- design-reference/screens/09-match-overview.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/sessions/editor/**`
- `android/feature/sessions/placeholder/PointEditorSheetPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 102, 103

**Gate:** none

## A32: Fast Point Review deck with edge-safe swipes and TalkBack actions

`fast-point-review-deck` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:review`

**Blocked by:** A30

**What to build:** N1: cards with right 'I won', left 'Opponent won', up 'Let / not a point' and Unsure; swipes start away from the edges and explicit buttons sit near them; TalkBack custom actions for each outcome; review completion counted from events. Why blocked: A30 (replay clips and correction path).

**Acceptance criteria**

- [ ] Each swipe and each TalkBack custom action appends the same event (tests).
- [ ] A swipe starting inside the system-gesture inset does not trigger a card action (test).
- [ ] Completion count equals reviewed events in the store.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- N1 Fast Point Review (no reference image; screens.md)

**Owned areas**

- `android/feature/sessions/review/**`
- `android/feature/sessions/placeholder/ReviewDeckPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 104, 105, 106, 210

**Gate:** none

## A33: Checkpoint auto-fill on the shared checkpoint fixtures, 'Score this match' and the checkpoint-conflict banner

`checkpoint-autofill` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:review`

**Blocked by:** A32, T31

**What to build:** CheckpointSolver in Kotlin, shipped only because the shared fixtures exist (spec/README decision 12): bounded enumeration over legal game lengths, uniquely determined winners appended as estimated, ambiguous stretches become review cards, an unreachable checkpoint flags only its stretch; 'Score this match' on the overview opens the deck on what remains. Flips the checkpoint marker. Why blocked: A32 (deck); T31 (the checkpoint fixture kind and its reference cases land there).

**Acceptance criteria**

- [ ] Every spec/fixtures/checkpoint case passes; the marker reads `.consumed`.
- [ ] 'Score this match' on a fixture session appends only estimated outcomes and opens the deck on the ambiguous stretch (test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- N1 Fast Point Review (no reference image)
- design-reference/screens/09-match-overview.png (derived; hierarchy and copy only)

**Owned areas**

- `android/core/checkpoint/**`
- `android/feature/sessions/checkpoint/**`

**User stories:** 107

**Gate:** G-CORE (checkpoint)

## A34: Rally segmentation in :core and rally-only playback with visible gap chips

`rally-only-playback` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:replay`

**Blocked by:** A30

**What to build:** RallySegmenter and RallyOnlyPlan in :core (pre/post-roll defaults 1.5 s / 2.5 s, bookmarks as candidates without audio, excluded side). If spec/fixtures/rally exists (iOS T32 adds it) every case passes and the marker flips; otherwise hand-checked literals and `.pending`. Replay plays rally-only from Marks as an ExoPlayer playlist with collapsed gaps shown as tappable chips ('+0:42'); audio-derived segmentation reads the capability registry and stays disabled until an Android benchmark record passes; A35 writes that record, so there is no edge in either direction. Why blocked: A30 (replay host).

**Acceptance criteria**

- [ ] Rally fixture cases pass (or the literal tests are listed with `.pending`).
- [ ] Rally-only playback skips exactly the planned gaps (instrumented, frame-counter fixture) and each chip seeks into the gap.
- [ ] Without audio the segmentation option shows 'unavailable' with the reason.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/10-smart-replay.png (derived; hierarchy and copy only)

**Owned areas**

- `android/core/rally/**`
- `android/feature/sessions/rally/**`

**User stories:** 108, 111

**Gate:** none

## A35: Android HitDetector and benchmark records: point suggestions only when the Android detector passes its synthetic benchmark

`hit-detector-android-benchmark` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:analysis`, `resource:emulator`

**Blocked by:** A29, T11, T34

**What to build:** AD14 per-platform evidence. HitDetector on Android: MediaExtractor + MediaCodec decode to mono 48 kHz, the same onset algorithm and parameters as iOS T34 (spectral flux, adaptive threshold, 150 ms refractory, hit/bounce/other heuristics, sound-travel correction), registered as the analyze stage of A29's queue; an Android benchmark harness runs the T11 synthetic corpus (tuning vs held-out seeds) and writes Android benchmark records under evidence/android/benchmarks; suggestions (estimated, needsReview) appear only when the Android record passes the floor, otherwise 'Not available on Android yet' with what was tested. Why blocked: A29 (queue); T11 (benchmark corpus); T34 (the algorithm and parameter values Android must match are defined there). A34 is not a blocker: it reads the record this ticket writes. Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] On the held-out synthetic seeds the Android record states precision/recall and the pass/fail against the iOS floor; tuning seeds are refused for gating.
- [ ] With a failing record the UI shows 'Not available on Android yet'; with a passing record suggestions appear as Estimated · needs review (tests with injected records).
- [ ] Synthetic results never set `validated` (test).
- [ ] Run on jovra_phone_p9_api35 or the JVM decode path; the record names the decoder used.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Android benchmark record files

**Screens**

- design-reference/screens/07-import-processing.png (derived; hierarchy and copy only)

**Owned areas**

- `android/media/analysis/audio/**`
- `evidence/android/benchmarks/**`

**User stories:** 109, 110, 176

**Gate:** Real-footage benchmark (separate)

## A36: Clip export with Transformer, Save original to Movies/JOVRA or Files, and per-session JSON and CSV export

`clip-export-data-export` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:export`, `resource:emulator`

**Blocked by:** A30

**What to build:** Clip export through Media3 Transformer: point or range clips with start/end within ±1 frame, the score overlay from the fold at each presentation time, audio removed by default with an 'Include audio' switch, external shares always re-encoded (edit-list trims only for files kept inside the app), each export recording the event-log version it used, long exports under WorkManager with a progress notification and resume. 'Save original' to Movies/JOVRA through MediaStore (no permission) or a location from SAF. Per-session data export (versioned JSON, points CSV, stats CSV) shared through a FileProvider. Why blocked: A30 (replay entry points); A06 (exporters). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Instrumented on frame-counter fixtures at 30 and 60 fps: exported first and last frames equal the requested source frames ±1.
- [ ] Overlay text at 10 sampled output frames equals the fold for the matching source time.
- [ ] Default export has no audio track; with Include audio it has one (MediaExtractor assertion).
- [ ] The sample session's exported CSVs are byte-identical to the golden files.
- [ ] A correction after export marks the export stale by event-log version (test).
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/10-smart-replay.png (derived; hierarchy and copy only) (export sheet)

**Owned areas**

- `android/media/export/**`
- `android/feature/sessions/export/**`
- `android/feature/sessions/placeholder/ExportSheetPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 112, 113, 114, 115, 117, 118, 123

**Gate:** none

## A37: Condensed match, highlight reel with burned-in score and the Share Pack for coach, opponent and partner

`highlights-share-pack` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:export`, `resource:emulator`

**Blocked by:** A36, A34

**What to build:** N10 and N3: a condensed match from the rally-only plan, a highlight reel with the derived score burned in, optional vertical crop and captions; a Share Pack (clips, notes, stats, match JSON, points CSV and a static viewer page) for a coach, an opponent or a doubles partner (full copy or selected points), private by default, built from 720p proxies or rally-only cuts on request, shared through the share sheet. Why blocked: A36 (exporter); A34 (rally-only plan). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] The reel's burned-in score at each clip start equals the fold (instrumented sample).
- [ ] A Share Pack zip contains exactly the listed files and its JSON/CSV equal the session export (test).
- [ ] Default Share Pack excludes audio and originals.
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- N3 Share Pack, N10 Highlight reel (no reference images)

**Owned areas**

- `android/feature/sessions/sharepack/**`
- `android/media/highlights/**`
- `android/feature/sessions/placeholder/{SharePack,HighlightReel}Placeholder.kt (A11's placeholder; deleted here)`

**User stories:** 116, 119, 120, 121

**Gate:** none

## A38: Sample analysis content: stroke tags, placements, calibrations, serve marks, key moments and the comparison project

`sample-analysis-content` · android · size S · labels `ready-for-agent`, `platform:android`, `track:android`, `area:core`

**Blocked by:** A07, T40

**What to build:** Load the analysis records that iOS T40 adds to the shared sample generator into Kotlin SampleContent so every number on the shot map, Serve Lab, Stroke Lab and Compare demos is computed from data. Why blocked: A07 (sample library); T40 (the records and oracles are generated there).

**Acceptance criteria**

- [ ] Kotlin summaries equal the oracles: forehand placements 31, 12 and 7 of 50; deuce first-serve placements 13, 8 and 4 of 25; 12 serve marks on Oct 4.
- [ ] Installed sample analysis records carry isSample and re-encode canonically equal to the fixture files.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Owned areas**

- `android/core/sample/analysis/**`

**User stories:** 17

**Gate:** none

## A39: Shot placement map with manual bounce marking and TalkBack descriptions

`shot-placement-map` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:labs`

**Blocked by:** A13, A30, A38

**What to build:** Screen A11 (Shot placement): the accurate top-down court, manual placements on the diagram or on the video frame through the calibration, filters, legend, provenance row, placements described in words for TalkBack ('Deep cross-court, in'), mirrored diagrams for left-handed players, diagram beside list on wide windows. Placement is entered by tapping and is never a line call. Why blocked: A13; A30; A38.

**Acceptance criteria**

- [ ] Sample placements equal the A38 oracles on the map (test).
- [ ] A tap on the video frame maps through the homography to the same court point as the diagram tap (unit test).
- [ ] Each marker has a word description; no 'line call' wording anywhere (copy lint).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/11-shot-map.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/insights/shotmap/**`
- `android/feature/insights/placeholder/ShotMapPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 124, 125, 130

**Gate:** none

## A40: Stroke Lab: padded clips, key moments, contact strip and review statuses

`stroke-lab` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:labs`

**Blocked by:** A21, A38, A15

**What to build:** Screen A13 (Stroke Lab): padded clips, manual key moments, the contact strip, review statuses, video beside strip on wide windows; the 2D pose control shows 'Not available on Android yet' until A43. Why blocked: A21 (player); A38 (sample swing key moments); A15 (two-pane scaffold and the route through A11).

**Acceptance criteria**

- [ ] Sample key moments render at the oracle frames (test).
- [ ] Pose control shows the unavailable state with reason from the capability registry (test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/13-stroke-lab.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/insights/strokelab/**`
- `android/feature/insights/placeholder/StrokeLabPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 128

**Gate:** none

## A41: Serve Lab: deuce/ad stats, placements, manual-assisted speed estimate, key moments and the toss timer

`serve-lab` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:labs`

**Blocked by:** A13, A21, A38, A15

**What to build:** Screen A12 (Serve Lab): serve stats by side, service-box placements, the manual-assisted serve speed estimate (contact and bounce marked by the user; formula hand-checked by literals until a shared fixture exists; registry status estimated; method and range shown; 'Needs court calibration' when missing), serve key moments, the toss-to-contact timer and toss overlay, 'One focus for next time'. Two panes on wide windows. Why blocked: A13 (calibration); A21 (player); A38 (sample serve marks); A15 (two-pane scaffold and the route through A11); A06 (stats). Implied through other blockers and not repeated as edges: A06.

**Acceptance criteria**

- [ ] Speed estimates for the 12 Oct 4 sample serves are within the documented tolerance of the T11 ground-truth speeds and labelled Estimated (test).
- [ ] Without calibration the estimate shows 'Needs court calibration', never a number.
- [ ] No 'fastest serve' wording without 'marked' (copy lint).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/12-serve-lab.png (derived; hierarchy and copy only)

**Owned areas**

- `android/core/serve/**`
- `android/feature/insights/servelab/**`
- `android/feature/insights/placeholder/ServeLabPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 126, 127

**Gate:** none

## A42: Compare two recordings with manual contact sync, book-posture split and annotations with stylus draw-only

`compare-annotations` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:labs`

**Blocked by:** A30, A38

**What to build:** Screen A14 (Compare): two players driven by a pure CompareSync time model; stacked in portrait, side by side in landscape and wide windows, one per side of the hinge in book posture; independent alignment, 'Synced at Contact' locking, ±1-frame nudges on time; line, arrow, circle, 2D angle and freehand tools with editable handles and frame-range lifetime; voice and text notes; stylus tool type draws while a finger scrubs; replay Draw mode in which the jog still scrubs; a missing video offers relink. Why blocked: A30 (replay Draw mode host); A38 (sample comparison project).

**Acceptance criteria**

- [ ] CompareSync JVM tests: locking at contact keeps both playheads aligned across rate changes.
- [ ] Book-posture publisher puts each video on its own side with nothing in hinge bounds.
- [ ] A stylus MotionEvent draws; a finger MotionEvent scrubs (tests).
- [ ] An annotation outside its frame range is hidden (test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/14-video-comparison.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/insights/compare/**`
- `android/core/compare/**`
- `android/feature/insights/placeholder/ComparePlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 100, 131, 132, 133, 134, 135, 136

**Gate:** none

## A43: Optional ML Kit capabilities behind G-16K: bystander face blur in exports and on-demand 2D pose in Stroke Lab

`mlkit-optional-capabilities` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:analysis`

**Blocked by:** A36, A40

**What to build:** Face detection (export blur) and pose (Stroke Lab, beta: one person, face visible) as separately registered capabilities, off by default, each shown only with an Android benchmark record and only in builds that pass the 16 KB alignment check A02 runs on every release APK, plus a runtime run on the `_ps16k` system image (1,779 MB; G-DISK and Jon's approval). Until both hold, release builds exclude the native libraries and the UI says 'Not available on Android yet'. Why blocked: A36 (export pipeline); A40 (Stroke Lab).

**Acceptance criteria**

- [ ] With no passing record the capability rows read 'Not available on Android yet' (test).
- [ ] Pose overlays carry Estimated provenance and no numeric biomechanics (copy lint).
- [ ] The A02 zipalign step passes on a release APK that includes the ML Kit libraries (CI link).
- [ ] Runtime on the `_ps16k` image: not run unless Jon approved the image download and G-DISK holds; reported 'not run' until then, and the capability stays off in release builds.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- zipalign -c -P 16 output (A02 step)
- _ps16k run log (after the gate only)

**Screens**

- design-reference/screens/13-stroke-lab.png (derived; hierarchy and copy only)
- design-reference/screens/10-smart-replay.png (derived; hierarchy and copy only)

**Owned areas**

- `android/media/ml/**`

**User stories:** 122, 129, 350

**Gate:** G-16K (runtime _ps16k image: G-DISK + Jon's approval)

## A44: Insights: evidence-linked practice plan, drill session and the Explore list

`insights-practice-plan` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:insights`

**Blocked by:** A15, A09

**What to build:** Screen A15 (Insights): 'Your next advantage' with one weekly focus, evidence rows whose 'Watch evidence' opens replay at the point, numbered drills, the drill session, an Explore list with declared Studio slots (lesson journal, Progress Story, Angle insights; A63), list | detail on wide windows, sample-scope rule. Why blocked: A15 (list | detail scaffold and routes); A09 (sample practice plan installed).

**Acceptance criteria**

- [ ] Plan evidence counts equal the sample practice-plan record (test).
- [ ] 'Watch evidence' navigates to replay with the point payload.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/15-coaching-plan.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/insights/plan/**`
- `android/feature/insights/placeholder/{Insights,DrillSession}Placeholder.kt (A11's placeholder; deleted here)`

**User stories:** 137

**Gate:** none

## A45: Progress: pooled trends, milestones, review completion and goals with spoken chart summaries

`progress` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:insights`

**Blocked by:** A15, A09

**What to build:** Screen A16 (Progress): range chips (4 weeks / 3 months / Year), pooled trends of similar session types from A06, milestones, review completion, practice goals, charts with spoken summary and table, a declared equipment-association slot (A47), chart beside details on wide windows. Why blocked: A15 (chart | details scaffold and routes); A09 (sample library installed); A06 (trends). Implied through other blockers and not repeated as edges: A06.

**Acceptance criteria**

- [ ] Trend points equal pooled fractions from the sample library oracle (24/50, 33/60, 38/60, 40/60).
- [ ] Each chart has a TalkBack summary and a table alternative (semantics).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/16-progress.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/insights/progress/**`
- `android/feature/insights/placeholder/ProgressPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 138, 139

**Gate:** none

## A46: Racket Vault and String Journal

`racket-vault-string-journal` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:equipment`

**Blocked by:** A15, A09

**What to build:** Screens A17 (Racket Vault) and A18 (String journal): the active setup, string tags, court kit, rackets with notes and photos chosen through the photo picker, the string journal with tensions, logged time and feel; manufacturer names only as user-entered text; two panes on wide windows. Why blocked: A15 (two-pane scaffold and routes); A09 (sample equipment installed).

**Acceptance criteria**

- [ ] Sample equipment renders with hours equal to the oracle (Sep 9 string job linked to 8 sessions).
- [ ] No bundled brand names or logos (resource and copy lint).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/17-racket-vault.png (derived; hierarchy and copy only)
- design-reference/screens/18-string-journal.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/profile/equipment/**`
- `android/feature/profile/placeholder/{RacketVault,StringJournal}Placeholder.kt (A11's placeholder; deleted here)`

**User stories:** 141

**Gate:** none

## A47: Equipment links: setup gear row, restring reminders, 'String broke' during capture and equipment associations

`equipment-links` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:equipment`

**Blocked by:** A46, A45, A24

**What to build:** Fills declared slots only: the gear row in setup (A19), 'String broke' in the capture More menu (A24), restring reminders as notifications only after reminders are on and POST_NOTIFICATIONS is granted, and equipment associations on Progress (A45) shown only as associations with sample sizes and a minimum of 3 sessions. Why blocked: A46 (equipment records); A45, A24 and A19 through A24 (the slots); A12 (notification permission). Implied through other blockers and not repeated as edges: A12.

**Acceptance criteria**

- [ ] Boundary tests: 2 sessions with 100 points and 3 sessions with 99 points are not shown; 3 sessions with 100 points shows the association with both sample sizes (story 140).
- [ ] Reminders schedule nothing until the toggle is on and permission granted (fake).
- [ ] Only slot files change in A19/A24/A45 folders (diff stat).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/18-string-journal.png (derived; hierarchy and copy only)
- design-reference/screens/04-session-setup.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/profile/equipment/links/**`
- `android/feature/record/setup/slots/gear/**`
- `android/feature/record/capture/slots/stringbroke/**`
- `android/feature/insights/progress/slots/equipment/**`

**User stories:** 140, 142

**Gate:** none

## A48: Storage and backup screen with the archive state machine, uninstall warning, Movies/JOVRA copy and 'Awaiting Google Drive setup'

`storage-archive-state-machine` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:storage`

**Blocked by:** A15

**What to build:** Screen A19 (Storage): 'Your video, your choice', the 'On this phone' card, 'Uninstalling JOVRA deletes footage kept only on this phone.', 'Also save to Movies/JOVRA', the Google Drive row reading 'Awaiting Google Drive setup' (no OAuth client configured), the provider-independent ArchiveService state machine in :core with its write-ahead journal in :data (journal before network), the queue section against a fake provider, retention, 'Backup storage does not run analysis', and no upload while recording. Why blocked: A15 (routes and two-pane scaffold); A08 (store and journal location). Implied through other blockers and not repeated as edges: A08.

**Acceptance criteria**

- [ ] JVM tests over every archive state transition; a crash between journal and upload resumes without duplicate (fake provider).
- [ ] With no Drive configuration the row reads 'Awaiting Google Drive setup' and offers no connect action.
- [ ] A capture-in-progress fake blocks queue starts (test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/19-cloud-archive.png (derived; hierarchy and copy only)

**Owned areas**

- `android/core/archive/**`
- `android/data/archive/**`
- `android/feature/profile/storage/**`
- `android/feature/profile/placeholder/StoragePlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 143, 144, 145, 154

**Gate:** none

## A49: Google Drive archive on Android: AuthorizationClient with drive.file, resumable verified uploads, the fake Drive and reconnect/disconnect

`drive-authorization-uploads` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:storage`

**Blocked by:** A48

**What to build:** AND-4 (AD16). Google AuthorizationClient requesting drive.file only, no refresh token on the device, re-authorization in the worker and 'Needs reconnect' when user action is needed, Disconnect calling revokeAccess. OkHttp Drive v3 REST: pre-generated file ids, resumable sessions with 256 KiB-multiple chunks streamed from a file offset, 308 + Range resume, 404 session expiry, backoff on 5xx/429/rate-403, terminal quotaBlocked, archive root by appProperties, layout JOVRA/<year>/<date> <title>/ with the versioned sidecar, backed up only when size and MD5 (and SHA-256 when present) match. 'Back up now' as a user-initiated data transfer job (API 34+) or expedited work with a notification (29–33); automatic backup on WorkManager with Wi-Fi-only. A MockWebServer fake Drive implements all of it for tests. Drive is enabled only when the build carries an Android OAuth client id; otherwise A48's 'Awaiting setup' stays. Why blocked: A48 (archive state machine). Also waits on the F-ADR-0008 amendment (ADR owner) before merge.

**Acceptance criteria**

- [ ] Fake-Drive tests: kill and resume at 10%, 50% and 99% with no duplicate file; expired session restarts; quota block without a retry storm; revoked access → Needs reconnect; checksum mismatch never reaches 'backed up'.
- [ ] Wi-Fi-only policy prevents upload on a metered fake network (WorkManager constraint test).
- [ ] No client secret or token in source or resources (grep); configuration absent → 'Awaiting Google Drive setup'.
- [ ] The PR links the merged ADR-0008 Android amendment; without it the ticket stays open.
- [ ] Real Drive is reported UNVERIFIED until Jon's OAuth client exists.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Fake-Drive transcript

**Screens**

- design-reference/screens/19-cloud-archive.png (derived; hierarchy and copy only)

**Owned areas**

- `android/data/drive/**`
- `android/feature/profile/storage/drive/**`

**User stories:** 146, 147, 148, 149, 150, 151, 153

**Gate:** F-ADR-0008 amendment; Jon's Android OAuth client (real Drive)

## A50: Archive restore with verification, cross-platform restore of an iOS archive, archive-only sessions and Space Saver

`archive-restore-space-saver` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:storage`

**Blocked by:** A49, A18, A16, T52

**What to build:** Restore with checksum verification, the archive root found again after reinstall (fills A16's restore-offer slot), archive-only sessions in the library, Space Saver and 'Free up space'. An archive written by iOS restores on Android with identical fold, stats and CSVs, proven against the iOS fake-Drive archive transcripts in spec/fixtures/archive. Flips the archive marker. Why blocked: A49 (Drive provider); A18 (library); A16 (restore slot); T52 (the archive transcript fixture kind is produced there).

**Acceptance criteria**

- [ ] Every spec/fixtures/archive transcript restores on the fake Drive; the restored sample's fold and stats deep-equal and its CSVs are byte-identical.
- [ ] A corrupted chunk fails verification and the session is not marked restored.
- [ ] Space Saver removes only verified-archived originals (test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/19-cloud-archive.png (derived; hierarchy and copy only)
- design-reference/screens/08-session-library.png (derived; hierarchy and copy only)

**Owned areas**

- `android/data/restore/**`
- `android/feature/profile/storage/restore/**`
- `android/feature/profile/onboarding/slots/restore/**`

**User stories:** 12, 152, 320

**Gate:** G-CORE (archive)

## A51: Settings and privacy: No account, real permission rows, saving/choosing videos rows, units, appearance, accessibility, notifications, demo content and per-app language

`settings-privacy` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:settings`

**Blocked by:** A15, A09, A12

**What to build:** Screen A20 (Settings): grouped list with 'No account', camera/microphone/notifications/nearby-devices rows showing the real permission state with consequences and 'Open app settings', 'Saving videos · No permission needed', 'Choosing videos · Not needed: you pick each video', units, appearance, accessibility (larger live scoreboard, haptic/audio confirmations, volume-key Mark toggle), notifications, remove/reopen/reset demo content, per-app language, a 'Paired watch' row bound to the composition root's watch-bridge status seam (fake until W10's live adapter). List beside detail on wide windows. Why blocked: A15 (list | detail scaffold); A09 (sample remove/reopen); A12 (live permission states).

**Acceptance criteria**

- [ ] Each permission row reflects every fake state with its consequence text.
- [ ] Removing sample content with one confirmation deletes only sample objects; reopen reinstalls (test).
- [ ] Per-app language switch is honoured (LocaleManager/AppCompat test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/20-settings-privacy.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/profile/settings/**`
- `android/feature/profile/placeholder/SettingsPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 20, 156, 157, 158, 159, 162, 181

**Gate:** none

## A52: Your data: export my data, delete all data, diagnostics bundle and the privacy checks

`your-data-diagnostics` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:settings`

**Blocked by:** A51, A22

**What to build:** Export my data (every session JSON + CSVs), Delete all data through a registry where each store registers its eraser, the N5 diagnostics bundle built from JOVRA's own logs and session manifests and shared only by the user, an offline sweep proving every core flow except Drive works without network, and the inputs for the Play data-safety draft (no analytics SDK, no data collected by core). Why blocked: A51 (settings host); A06 (export); A22 (capture logs in the bundle).

**Acceptance criteria**

- [ ] Delete all data leaves no session, project, preference or credential file (store walk test).
- [ ] The diagnostics bundle contains no media, token or invite secret (content scan test).
- [ ] Offline sweep with networking stubbed passes every non-Drive harness route.
- [ ] The merged manifest and dependency graph contain no analytics SDK (dependency report check).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/20-settings-privacy.png (derived; hierarchy and copy only)
- N5 Diagnostics (no reference image)

**Owned areas**

- `android/feature/profile/data/**`
- `android/data/erase/**`
- `android/feature/profile/placeholder/{YourData,Diagnostics}Placeholder.kt (A11's placeholder; deleted here)`

**User stories:** 160, 161, 184

**Gate:** none

## A53: Consent records, Competition mode and junior-parent mode

`consent-competition-junior` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:settings`

**Blocked by:** A24

**What to build:** N4: consent records with attached forms through the photo picker or SAF, withdrawal honoured by 'Delete this recording', Competition mode, child profiles kept only on this phone with junior protections (no sharing, names as entered). Why blocked: A19 (setup consent row); A24 (delete during capture).

**Acceptance criteria**

- [ ] Withdrawing consent offers deletion of that recording and logs the withdrawal time (test).
- [ ] Junior profiles are excluded from Share Packs and exports by default (test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Junior profile tests: one-tap stop and delete during capture removes the recording; a junior export has no audio track (MediaExtractor); the opponent-family copy is produced with only names as entered (story 163).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- N4 Consent and junior (no reference image)
- design-reference/screens/04-session-setup.png (derived; hierarchy and copy only)

**Owned areas**

- `android/feature/profile/consent/**`
- `android/feature/profile/placeholder/ConsentPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 163

**Gate:** none

## A54: App shortcuts, the Health Connect opt-in spike and the ongoing-notification live-update spike

`platform-integrations` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:integrations`

**Blocked by:** A24, A20, A51

**What to build:** Static and dynamic shortcuts ('Start singles recording' → setup prefilled singles, 'Show last match' → newest real session overview) filling A11's placeholders; a Health Connect opt-in spike writing only start, end and the session id (record type confirmed in the spike; UNVERIFIED today); an Android 16 progress-style live update spike for the recording notification, run only after G-IMG36; locale-aware formatting of dates, numbers and units. Why blocked: A24 (capture route); A20 (overview route); A51 (Health toggle in settings).

**Acceptance criteria**

- [ ] Shortcut intents resolve to the typed routes (tests).
- [ ] Health Connect writes nothing until opted in (fake client).
- [ ] The live-update spike report states whether G-IMG36 was available; without it the spike is recorded as not run.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Spike notes

**Owned areas**

- `android/app/shortcuts/**`
- `android/feature/profile/health/**`
- `android/media/capture/liveupdate/**`

**User stories:** 178, 179, 180

**Gate:** G-IMG36 + G-DISK (live update only)

## A55: Review marks and manual call notes (ADR-0028 Stage 1): Marked list, timeline markers, manual In/Out/Needs-review placement

`review-marks-manual-calls` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:review`

**Blocked by:** A26, A39

**What to build:** Stories 352–356: every mark (phone Mark point, or a watch Mark for review once W10 lands) appears in a 'Marked' list and as a timeline marker at its point and match time; opening a mark goes to replay at that point (multi-angle with per-angle sync state once Studio S2 exists; single angle now); the user can add their own call note ('I called it out', 'Let', free text) shown as theirs, and place the bounce by tapping labelled In, Out or Needs review with provenance Manual; a review note never changes the score, and a correction is a normal point edit. It declares an empty multi-angle slot (android/feature/sessions/marks/slots/multiangle) that A88 fills. Why blocked: A26 (marks); A30 (replay); A39 (placement).

**Acceptance criteria**

- [ ] A mark from capture appears in the Marked list and on the timeline at the same match time (test).
- [ ] A manual call note never changes the fold (test asserting identical score before and after).
- [ ] No copy words a manual note as JOVRA's verdict (copy lint over the review strings).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/screens/10-smart-replay.png (derived; hierarchy and copy only) (marks)

**Owned areas**

- `android/feature/sessions/marks/**`
- `android/feature/sessions/placeholder/MarkedPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 352, 353, 354, 355, 356

**Gate:** none

## A56: Core adaptive matrix under Robolectric: posture variants, state preservation, idempotency, the keyboard inset and the cross-screen navigation paths

`core-adaptive-matrix-robolectric` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:adaptive`

**Blocked by:** A16, A17, A18, A20, A25, A28, A31, A32, A39, A40, A41, A42, A44, A45, A46, A48, A51

**What to build:** AND-1 acceptance for the core screens it depends on, without duplicating the per-screen goldens their own tickets already record. (1) Posture variants only (separating hinge, occluding hinge, tabletop) as Roborazzi goldens for the listed screens, labelled 'injected FoldingFeature (window-testing)'. (2) A coverage test that checks every route/state of the listed screens already has goldens at the AD15 windows; missing ones are filed against the owning ticket. (3) State-preservation tests (rotation, resize, fold/unfold, split screen, process death) for the AD15 rows these screens cover. (4) An idempotency test that fails if a recreation re-sends a job, score event, upload or invite. (5) IME-inset assertions with A12's helper on core notes and editors (point editor, bookmark notes, equipment notes, settings fields). (6) Navigation paths across screens that were deliberately not edges: library → overview → replay, framing → capture. Full route × state coverage across all screens is A98's. Fixes are filed against owning tickets; trivial layout fixes land here only in adaptive wrappers. Why blocked: the core screens it exercises.

**Acceptance criteria**

- [ ] Posture-variant goldens exist for every listed screen's route/state (coverage test); the coverage test also lists none of their AD15-window goldens as missing, or files each gap against its owner.
- [ ] Process-death tests restore selection, playhead (paused, rational time) and disk drafts for every AD15 row these screens cover.
- [ ] The idempotency test fails on a scratch change that re-sends an export job on recreation, and passes on main.
- [ ] With the IME shown at compact height and font scale 2.0, the confirm or primary action of the point editor, bookmark note, equipment note and settings text fields stays visible (story 194).
- [ ] Navigation tests: library → overview → replay with the point payload; framing → capture.
- [ ] Android 16 orientation-lock override (story 198): Robolectric resize tests only; the API 36 behaviour is reported 'not run' unless G-IMG36 and G-DISK passed.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- State-restoration transcript
- Coverage test output

**Screens**

- design-reference/screens/03-home.png (derived; hierarchy and copy only)
- design-reference/screens/08-session-library.png (derived; hierarchy and copy only)
- design-reference/screens/09-match-overview.png (derived; hierarchy and copy only)
- design-reference/screens/10-smart-replay.png (derived; hierarchy and copy only)
- design-reference/screens/14-video-comparison.png (derived; hierarchy and copy only)

**Owned areas**

- `android/app/src/test/adaptive/**`
- `evidence/android/A56/**`

**User stories:** 99, 167, 173, 187, 188, 189, 190, 191, 192, 194, 195, 196, 197, 198, 201, 202, 330, 331, 332, 347

**Gate:** G-IMG36 + G-DISK for Android 16 large-screen claims

## A57: Core emulator run on the phone and compact AVDs: rotation, process death, font scale and a TalkBack label sweep

`core-emulator-phone-compact` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:adaptive`, `resource:emulator`

**Blocked by:** A56

**What to build:** One emulator ticket per AVD family, so each creates and deletes as little as possible. On jovra_phone_p9_api35 then jovra_compact360_api35 (one at a time under the avd.sh lease): rotate, `adb shell am kill` after backgrounding and relaunch, font scale 2.0, and a TalkBack label sweep over the core harness routes. Evidence names the AVD, profile, image and what it approximates (Pixel 10 labelled an approximation). Why blocked: A56 (the matrix it runs on device images); A03 (lease). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Each AVD is acquired with `android/scripts/avd.sh acquire <name>` from the installed android-35 google_apis arm64 image only if absent (§7.1 config.ini, cold boot, no snapshots, 4 GB data cap), one at a time; `df -h /` is recorded before and after each; each is released and deleted after its evidence when free space is under 8 GB; `OlamyPixel` is untouched (avdmanager list before/after). A disk refusal reports the rows 'not run (disk)' and keeps the ticket open.
- [ ] The process-death and rotation transcripts on both AVDs restore the same state the A56 tests assert.
- [ ] The TalkBack label sweep finds no unlabelled focusable node on any core route (dump attached).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Per-AVD run logs and screenshots
- df -h per AVD
- Accessibility dumps

**Owned areas**

- `android/app/src/androidTest/adaptive/phone/**`
- `evidence/android/A57/**`

**User stories:** 342

**Gate:** Native UI gate (phone, compact AVDs)

## A58: Core emulator run on the fold and tablet AVDs: fold and unfold, book posture, keyboard focus order

`core-emulator-fold-tablet` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:adaptive`, `resource:emulator`

**Blocked by:** A57

**What to build:** On jovra_fold_p9pf_api35 then jovra_tablet_ptab_api35 (one at a time under the lease): fold/unfold through the emulator posture device actions where supported, book posture with an accessibility-tree dump, keyboard focus order on the tablet, process death. The fold is labelled 'emulator posture, pixel_9_pro_fold profile (approximation of the Pixel 10 Pro Fold; outer display differs)'; the tablet as a Galaxy approximation. A73 runs after this ticket so the two never create the same AVDs in parallel. Why blocked: A57 (serializes AVD use). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Each AVD is acquired with `android/scripts/avd.sh acquire <name>` only if absent (§7.1 config.ini), one at a time, with `df -h /` before/after, released and deleted after evidence when free space is under 8 GB; OlamyPixel untouched; a disk refusal reports 'not run (disk)'.
- [ ] No hinge-bound focusable node on the fold AVD in book posture (accessibility-tree dump).
- [ ] Keyboard focus order on the tablet follows the A56 semantics order for list | detail screens (transcript).
- [ ] Android 16 large-screen behaviour: 'not run' unless G-IMG36 and G-DISK passed.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Per-AVD run logs and screenshots
- df -h per AVD
- Accessibility dumps

**Owned areas**

- `android/app/src/androidTest/adaptive/largescreen/**`
- `evidence/android/A58/**`

**User stories:** 198

**Gate:** Native UI gate (fold, tablet AVDs); G-IMG36 + G-DISK for Android 16 large-screen claims

## A59: :studio-core contracts: strict models for every Studio schema, canonical hashes for 31 records, 172 invalid cases and the EDL validator

`studio-core-records-invalid` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A04

**What to build:** G-CORE for Studio, part 1. :studio-core models every jovra.* Studio record (project-lock, source-manifest, sync-map, observation, keeper and B-roll catalogs, story-profile catalog, story-brief, edit-plan/2, reference-catalog, render-job, quote, usage-reservation, delivered-artifact, lesson, camera-invite, storage-providers, plus the contract data files) with strict decoding, canonical re-encoding and canonical SHA-256; times as exact rationals and integer microseconds with the one half-up rounding function; and the edit-plan validator in parity with the reference (rules 1–12, clean alternate, stage allowlist). Markers for the record and invalid kinds flip. Why blocked: A04 (harness, canonical JSON).

**Acceptance criteria**

- [ ] All 31 records under spec/studio/fixtures/records decode, re-encode and hash equal to the reference; the 15 cross-record bundle mutations are rejected.
- [ ] All 172 invalid cases are rejected: 144 by the Kotlin rule with the reference's code, 28 by strict decoding; an accepted case fails the suite.
- [ ] An id with a trailing newline and an integral float in a frame field are refused.
- [ ] android-core runs :studio-core:test on JDK 17 without an SDK.
- [ ] The PR and the status report state F-STUDIO-ANDROID's state; while it is open, no Studio S0/S1 gate is claimed from this evidence.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Per-case pass list

**Owned areas**

- `android/studio-core/contracts/**`
- `android/studio-core/edl/**`
- `android/studio-core/conformance/records/**`

**User stories:** 291, 337

**Gate:** G-CORE (Studio records); F-STUDIO-ANDROID (claims)

## A60: :studio-core vectors: exact sync fits, sound delays, job transitions, ledger, quote credits, sample truth and edl-context

`studio-core-vectors` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A59

**What to build:** G-CORE for Studio, part 2: the 137 vector cases across sync-fit, sound-delay, job-transitions, ledger, quote-credits, sample-truth and edl-context. Sync fitting uses BigInteger and an integer square root, never Double; sound delays within 0.1 ms; the render-job state machine including refused resume stages; the quote/consent and reservation ledger. Why blocked: A59 (records and models).

**Acceptance criteria**

- [ ] All 137 vector cases pass; a scratch mutation using Double in the fit fails the exact-transform cases.
- [ ] Job-transition refusals return the reference's codes.
- [ ] Every Studio fixture kind present on merge day has a `.consumed` or `.pending` marker; the manifest test passes.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Owned areas**

- `android/studio-core/sync/**`
- `android/studio-core/jobs/**`
- `android/studio-core/ledger/**`
- `android/studio-core/conformance/vectors/**`

**User stories:** 254, 291

**Gate:** G-CORE (Studio vectors)

## A61: Studio project store, the Studio sample project and the demo cloud client

`studio-project-store-sample` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A60, A08

**What to build:** Project folders with atomic studio.json and records, revisions and delete scopes in :data; the Studio sample project from the shared fixtures labelled Sample; DemoCloudClient (in-process transcripts, Sample quotes, no network) and CloudMode (Local demo / Test / Connected) with live compiled but disabled; a local Studio entitlement flag. Why blocked: A60 (job/quote models); A08 (store pattern).

**Acceptance criteria**

- [ ] Sample project installs, resets byte for byte and removes only itself (test).
- [ ] DemoCloudClient returns the fixture transcripts and performs no network I/O (network trap).
- [ ] Live mode refuses to start without activation configuration (test).
- [ ] The PR and the status report state F-STUDIO-ANDROID's state; while it is open, no Studio S0/S1 gate is claimed from this evidence.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Owned areas**

- `android/data/studio/**`
- `android/studio-core/sample/**`
- `android/studio/cloud/demo/**`

**User stories:** 214, 215, 327, 328

**Gate:** F-STUDIO-ANDROID (claims)

## A62: Studio shell: Studio route states in the harness, shared Studio components and the Studio pane layout

`studio-shell` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A61, A15

**What to build:** Fills the Studio route placeholders' infrastructure: Studio routes live inside the five destinations (no sixth destination), each Studio screen family registers its harness states, shared Studio components in :designsystem (FilmCard, StudioFactTile, NextStepRow, LessonRow, TodayFocusCard, CameraSlotRow/AddSlotRow, ComparisonPair, QuoteCard shell, angle and status rows, gap hatch and source tints paired with number tags), and StudioPaneLayout built on A15's PanePolicy. Every Studio entry reads the local Studio flag. Why blocked: A61; A15.

**Acceptance criteria**

- [ ] A test asserts exactly Home, Sessions, Record, Insights, Profile in the navigation suite with Studio routes reachable.
- [ ] Shared components render in light, dark, high contrast and font 2.0 without clipping (Roborazzi).
- [ ] With the Studio flag off every Studio entry is hidden and core is unchanged (test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] The PR and the status report state F-STUDIO-ANDROID's state; while it is open, no Studio S0/S1 gate is claimed from this evidence.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Owned areas**

- `android/designsystem/studio/**`
- `android/studio/films/shell/**`

**User stories:** 216

**Gate:** F-STUDIO-ANDROID (claims)

## A63: Studio entry points on Home, Match overview, Insights and the Profile hub

`studio-entry-points` · android · size S · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A62, A16, A17, A20, A44

**What to build:** Fills the declared slots: the Studio card on Home ('Your game, made into a story.'), 'Make a film' on the overview, Lesson journal / Progress Story / Angle insights rows on Insights, and the Studio settings row on the Profile hub. Why blocked: A62; A16; A17; A20; A44 (the slots).

**Acceptance criteria**

- [ ] Each entry opens its Studio route (navigation tests).
- [ ] Only slot files change in the four feature folders (diff stat).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/41-android-studio-home.png

**Owned areas**

- `android/feature/home/dashboard/slots/studio/**`
- `android/feature/sessions/overview/slots/studio/**`
- `android/feature/insights/plan/slots/studio/**`
- `android/feature/profile/hub/slots/studio/**`

**User stories:** 27, 87, 212

**Gate:** none

## A64: Studio Home (41) and Studio settings (60) in every demo state

`studio-home-settings-demo` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A62

**What to build:** Screen specs A41 and A60 of adaptive-screens.md: Studio Home with the hero, Build your match, angles/styles cards, latest film, lessons, grid on wide windows, all states; Studio settings with storage providers (Device active, Files folder, Google Drive awaiting setup, Box and Dropbox planned, no iCloud row), a 'Paired watch · Status mirror' row bound to the watch-bridge status seam (Sample in demo; live once W10 lands), cloud off, Advanced in Test builds. Copy from screen-specs.json with the documented deliberate differences. Why blocked: A62.

**Acceptance criteria**

- [ ] Every screen A41 and screen A60 state is reachable by the harness and has Roborazzi goldens at all AD15 windows.
- [ ] No iCloud provider row exists on Android (test).
- [ ] Copy assertions against design-reference/adaptive/brief/screen-specs.json for 41 and 60.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Side-by-side images vs references 41 and 60

**Screens**

- design-reference/adaptive/screens/41-android-studio-home.png
- design-reference/adaptive/screens/60-android-studio-settings.png

**Owned areas**

- `android/studio/films/home/**`
- `android/studio/films/settings/**`
- `android/studio/films/placeholder/{StudioHome,StudioSettings}Placeholder.kt (A11's placeholder; deleted here)`

**User stories:** 213, 217, 308, 309, 312, 313

**Gate:** none

## A65: :room-protocol part 1: codecs for the 14 room schemas, 27 records, 103 invalid cases and the freshness, snapshot, status, display, disconnect and analysis vectors

`room-protocol-records-freshness` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:room`

**Blocked by:** A04

**What to build:** G-ROOM, Kotlin side, part 1. :room-protocol (pure JVM, no sockets) decodes and canonically re-encodes every jovra.room.*/1 record, rejects every invalid case at the expected layer, and implements receiver-owned freshness (injected monotonic clock; fresh ≤ 5 s, delayed ≤ 15 s, Unknown above or on unbounded transit or a restarted baseline), snapshot acceptance (room, epoch, per-sender seq), phone status rows, display strings, disconnect handling and the analysis result gate. Expected values are fixture literals. Why blocked: A04 (harness).

**Acceptance criteria**

- [ ] All 27 records round-trip canonically; all 103 invalid cases are rejected (61 by strict decoding, 42 with the reference's code).
- [ ] Vectors pass: freshness 14, snapshot 14, phone-status 5, display 6, disconnect 1, analysis 7 (47 cases); 5,000/5,001/15,000/15,001 ms boundaries asserted.
- [ ] Mutations that must fail: fresh threshold 6 s; unbounded transit treated as bounded.
- [ ] Markers for these kinds read `.consumed`; android-core runs :room-protocol:test without an SDK.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Owned areas**

- `android/room-protocol/records/**`
- `android/room-protocol/freshness/**`
- `android/room-protocol/snapshot/**`
- `android/room-protocol/conformance/part1/**`

**User stories:** 318, 337

**Gate:** G-ROOM (part 1)

## A66: Build your match (42), camera lobby (43) and director capture (44) in demo on the fixture room

`build-match-lobby-capture-demo` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A62, A65

**What to build:** Demo screens driven by a fixture room that replays spec/room sample records through :room-protocol types: court setup with the doubles diagram and slot sheets, slot-taken warning and placement hint; the lobby (JVR-482, Camera 1 Ready, Camera 2 Ready, Camera 3 Waiting), 'Each phone saves its own video', a paired watch shown as 'Status only'; director capture with the primary preview, 'Recording on n of m' from fresh acknowledgements with enrolled/fresh/recording counts, a silent camera frozen with 'May still be recording', stop-one and 'Ask all cameras to stop' sheets reporting per-device Accepted/Failed/Unknown, and 'Preview unavailable · not in this version' instead of stills (F-ROOM-STILL). Why blocked: A62 (shell); A65 (room record models and freshness).

**Acceptance criteria**

- [ ] Counts in the demo equal :room-protocol's HealthSummary over the fixture snapshot (test).
- [ ] A camera silent for 42 s reads 'No contact for 0:42 · may still be recording' and is not counted as recording.
- [ ] No still image is rendered anywhere on 44 (semantics/test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Side-by-side vs references 42–44

**Screens**

- design-reference/adaptive/screens/42-android-build-match.png
- design-reference/adaptive/screens/43-android-camera-lobby.png
- design-reference/adaptive/screens/44-android-director-capture.png

**Owned areas**

- `android/studio/build-match/court/**`
- `android/studio/build-match/lobby/**`
- `android/studio/build-match/director/**`
- `android/studio/build-match/fixtureroom/**`
- `android/studio/build-match/placeholder/{BuildMatch,CameraLobby,DirectorCapture}Placeholder.kt (A11's placeholder; deleted here)`

**User stories:** 218, 219, 220, 226, 230, 232, 235, 236, 237

**Gate:** none

## A67: Source import (45) and the sync workspace (46: sheets on compact, desk split at the hinge) in demo

`sources-sync-demo` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A62

**What to build:** Screen A45 'Choose the footage' with Photos and Files buttons, source rows, 'Originals stay on your phone', Wi-Fi only, 'Use one old match instead'; screen A46 'One match. One clock.' as sheets per angle and lane on compact and as stills + lanes beside the review card on wide windows split at a separating hinge; sample values (+120 ms, 18 ms/min, Estimated before confirmation, Reviewed after) from the sample truth; below-threshold alignment says 'Needs review' with the reason. Why blocked: A62.

**Acceptance criteria**

- [ ] Sample sync values equal spec/studio sample-truth (test).
- [ ] Window-testing: the desk splits at the hinge with nothing in hinge bounds; compact height turns panels into sheets.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/45-android-source-import.png
- design-reference/adaptive/screens/46-android-fold-sync.png

**Owned areas**

- `android/studio/editor/sources/**`
- `android/studio/editor/sync/**`
- `android/studio/editor/placeholder/{SourceImport,SyncDesk}Placeholder.kt (A11's placeholder; deleted here)`

**User stories:** 243, 244, 249, 250, 252, 254

**Gate:** none

## A68: Match Broadcast player (47) and angle insights (48) in demo

`player-insights-demo` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A62, A21

**What to build:** Screen A47: a large stable video with the score bug from the fold at the playhead, the angle strip, point chips, 'Reviewed sync' and Sample badges, an angle with no video for a moment shown honestly, tabletop video/controls; screen A48: 'More context. Clearer feedback.' with a still, one 2D annotation, 'Serve speed estimate · Needs court calibration' when uncalibrated, and observations from capabilities without an Android benchmark hidden or marked unavailable. Why blocked: A62; A21 (player).

**Acceptance criteria**

- [ ] Score bug equals the fold at sampled playheads of the sample project (test).
- [ ] Tabletop publisher: video above, angles and controls below.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/47-android-fold-broadcast.png
- design-reference/adaptive/screens/48-android-angle-insights.png

**Owned areas**

- `android/studio/editor/player/**`
- `android/studio/editor/insights/**`
- `android/studio/editor/placeholder/{ProjectPlayer,AngleInsights}Placeholder.kt (A11's placeholder; deleted here)`

**User stories:** 256, 257, 258, 259, 260, 261, 262, 263

**Gate:** none

## A69: Story modes (49) and the profile screens Coach's Cut, Rally Pulse, Progress Story and Court Memories (50–53) in demo

`story-modes-profiles-demo` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A62

**What to build:** Screen A49 'Choose your story.' with five cards, length chips from the ADR-0023 list (3, 5, 10, 15, 20, 25, 30 min and Full, as defined in story 265) in a flow row on compact and a segmented row on wide windows, the film options sheet, 'Preview my story'; screens A50–A53 per-profile options and preview in every coverage state, each profile's fallback, Rally Pulse 'With effects · Clean' with Clean the default when animations are off, every on-screen word from records or fixed templates. Why blocked: A62.

**Acceptance criteria**

- [ ] Every 49–53 harness state renders; the Full length is present and defined as in story 265.
- [ ] With animator duration scale 0 the Clean variant is selected by default (test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Side-by-side vs references 49–53

**Screens**

- design-reference/adaptive/screens/49-android-story-modes.png
- design-reference/adaptive/screens/50-android-coachs-cut.png
- design-reference/adaptive/screens/51-android-rally-pulse.png
- design-reference/adaptive/screens/52-android-progress-story.png
- design-reference/adaptive/screens/53-android-court-memories.png

**Owned areas**

- `android/studio/films/stories/**`
- `android/studio/films/profiles/**`
- `android/studio/films/placeholder/{StoryModes,CoachsCut,RallyPulse,ProgressStory,CourtMemories}Placeholder.kt (A11's placeholder; deleted here)`

**User stories:** 264, 265, 266, 267, 268, 269, 270, 271, 272

**Gate:** none

## A70: Lesson journal (54) and the lesson workspace (55: one, two or three panes) in demo

`lessons-demo` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A62

**What to build:** Screen A54 'Every lesson stays with you' with dated lessons, clip counts, Journal/Practice chips, Today's focus and checklist counts computed from records (sample: 10/10, 20/20, review 0/5 → 2 of 3 complete); screen A55: lesson → list | lesson → list | clip | notes by PanePolicy, notes carrying author and provenance, 'Find the video' for a missing clip. Why blocked: A62.

**Acceptance criteria**

- [ ] Checklist counts equal the sample records (test).
- [ ] PanePolicy-driven pane counts at 360, 840 and 1280 × 800 dp match the vectors for the lesson task (test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/54-android-lesson-journal.png
- design-reference/adaptive/screens/55-android-tablet-lesson.png

**Owned areas**

- `android/studio/films/lessons/**`
- `android/studio/films/placeholder/{LessonJournal,LessonWorkspace}Placeholder.kt (A11's placeholder; deleted here)`

**User stories:** 273, 274, 275, 276, 278

**Gate:** none

## A71: Film storyboard (56): beat list with sheets on compact, preview and timeline on wide, tabletop split, in demo

`storyboard-demo` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A62

**What to build:** Screen A56 'Shape the story': a beat list with per-beat sheets on compact windows, preview + timeline on wide windows, film above the fold and timeline below in tabletop posture, the timeline adjustable by beat and by frame for TalkBack, demo edits that show the validator's refusal reason in words. Why blocked: A62.

**Acceptance criteria**

- [ ] Tabletop publisher: preview above the hinge, timeline below; compact: beat list with sheets.
- [ ] TalkBack adjust steps one beat, and with a modifier action one frame (semantics test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/56-android-fold-storyboard.png

**Owned areas**

- `android/studio/editor/storyboard/**`
- `android/studio/editor/placeholder/StoryboardPlaceholder.kt (A11's placeholder; deleted here)`

**User stories:** 279, 280, 283

**Gate:** none

## A72: Cloud preflight quote (57), render queue (58) and film delivery (59) in demo with Sample credits

`quote-jobs-delivery-demo` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A62

**What to build:** Screen A57 as one full screen (consent never in a swipe-dismissable sheet): the QuoteCard bound to the shipped jovra.quote/1 (estimate range and spending limit = capCredits; one figure if min = max), 'What sets the price' modal bottom sheet (length chips on compact / segmented on wide, Film quality for 4K captures, one switch per angle, read-only source minutes, the planning switch mirrored), 'Plan the story in the cloud' off by default whose consent names both planning services (the 'Cloud planning on' state is built but flagged off until F-QUOTE-CONSENT closes), a consent checkbox, 'Create film' disabled with its reason, two panes on wide windows with the boundary off the hinge, a polite live region for the confirmed price, no dollar amounts, provider names, Play Billing or credit-pack sheet; screen A58 real-stage names and job card; screen A59 preview, '1080p · Private', Save to device, Include audio (off by default except Rally Pulse). Why blocked: A62.

**Acceptance criteria**

- [ ] Changing any driver clears consent and re-quotes from DemoCloudClient (test).
- [ ] The quote screen tree contains no currency symbol, provider name or purchase button (copy lint).
- [ ] TalkBack reads the card as one sentence ('Sample quote. Estimated 2 to 4 credits. Spending limit …').
- [ ] No Play Billing dependency in the dependency report.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Roborazzi goldens per state at 360/411 dp, fold outer, 852x883 dp and 1280x800 dp, light and dark (Robolectric sdk=34; recorded by the roborazzi-record job and verified in android-unit on CI Linux).
- [ ] Demo-state tests record zero network requests (network trap).
- [ ] Junior profile: the Include audio switch is absent on delivery (59) and the planned export has no audio (test).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/57-android-cloud-preflight.png
- design-reference/adaptive/screens/58-android-render-queue.png
- design-reference/adaptive/screens/59-android-film-delivery.png

**Owned areas**

- `android/studio/films/quote/**`
- `android/studio/films/jobs/**`
- `android/studio/films/delivery/**`
- `android/studio/films/placeholder/{CloudPreflight,RenderQueue,FilmDelivery}Placeholder.kt (A11's placeholder; deleted here)`

**User stories:** 292, 293, 294, 295, 296, 297, 299, 301, 302, 303, 304

**Gate:** F-QUOTE-CONSENT (cloud planning state)

## A73: Studio fold and tablet workspaces 46, 47, 55 and 56 on the fold and tablet AVDs with state preservation and no duplicated side effects

`studio-fold-tablet-workspaces` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:adaptive`, `resource:emulator`

**Blocked by:** A67, A68, A70, A71, A72, A58

**What to build:** Studio A1 on emulators: the sync desk split at the hinge (46), the tabletop player (47), the three-pane lesson workspace (55) and the tabletop storyboard (56) run on jovra_fold_p9pf_api35 and jovra_tablet_ptab_api35 (one at a time); sync-edit drafts, draft cuts, the playhead and the quote's idempotency key survive rotate, fold/unfold (posture device actions where supported) and process death (`adb shell am kill`); a recreation never re-sends a job or quote acceptance. Why blocked: A67; A68; A70; A71; A72; A58 (the core fold/tablet run, so the two never create the same AVDs in parallel). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Fold AVD: 46 and 56 split at the hinge in book/tabletop; no focusable node intersects hinge bounds (accessibility dump).
- [ ] Tablet AVD: 55 shows three panes at 1280 × 800 dp and two at font scale 2.0.
- [ ] Process death restores drafts from disk and leaves the quote acceptance count at one (test with DemoCloudClient counters).
- [ ] Each AVD is created by `android/scripts/avd.sh acquire` from the installed android-35 image only if absent, one at a time, with `df -h /` before/after, deleted after evidence when free space is under 8 GB; OlamyPixel untouched.
- [ ] Evidence labels the fold as an approximation of the Pixel 10 Pro Fold (outer display differs).
- [ ] With the IME shown at compact height and font scale 2.0, the lesson-note save (55), the storyboard beat note (56) and the quote consent checkbox and Create film (57) stay visible (story 194).
- [ ] Android 16 large-screen behaviour: 'not run' unless G-IMG36 and G-DISK passed.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Per-AVD screenshots and logs

**Screens**

- design-reference/adaptive/screens/46-android-fold-sync.png
- design-reference/adaptive/screens/47-android-fold-broadcast.png
- design-reference/adaptive/screens/55-android-tablet-lesson.png
- design-reference/adaptive/screens/56-android-fold-storyboard.png

**Owned areas**

- `android/studio/src/androidTest/adaptive/**`
- `evidence/android/A73/**`

**User stories:** 231, 255, 260, 274, 282, 298, 300, 347

**Gate:** Native UI gate (fold, tablet AVDs); G-IMG36 + G-DISK for Android 16 claims

## A74: Studio S0 / A1 gate on Android: every Studio state reachable and audited, copy checks and the status report

`studio-s0-gate-android` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:qa`

**Blocked by:** A63, A64, A66, A69, A73

**What to build:** Aggregates S0 evidence: every Studio state of adaptive-screens §1 reachable by the harness with Roborazzi coverage at all windows and postures, TalkBack labels and font scale 2.0, the no-network demo proof, the five destinations unchanged, copy checked against screen-specs.json with the deliberate differences listed, a side-by-side page pairing 41–60 with our screenshots and a reviewer line per pair, and the stage report in separate columns (JVM conformance, Robolectric/Compose, screenshot, named emulator, physical, …). Why blocked: A63; A64; A66; A69; A73.

**Acceptance criteria**

- [ ] A coverage test lists every Studio route × state and fails if any is missing a golden.
- [ ] The side-by-side generator refuses to finish without a reviewer line per pair.
- [ ] The status report marks physical, real-media and backend columns 'not run'.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Coverage test output
- evidence/android/A74/side-by-side.html
- Stage report

**Screens**

- design-reference/adaptive/screens/41-android-studio-home.png
- design-reference/adaptive/screens/42-android-build-match.png
- design-reference/adaptive/screens/43-android-camera-lobby.png
- design-reference/adaptive/screens/44-android-director-capture.png
- design-reference/adaptive/screens/45-android-source-import.png
- design-reference/adaptive/screens/46-android-fold-sync.png
- design-reference/adaptive/screens/47-android-fold-broadcast.png
- design-reference/adaptive/screens/48-android-angle-insights.png
- design-reference/adaptive/screens/49-android-story-modes.png
- design-reference/adaptive/screens/50-android-coachs-cut.png
- design-reference/adaptive/screens/51-android-rally-pulse.png
- design-reference/adaptive/screens/52-android-progress-story.png
- design-reference/adaptive/screens/53-android-court-memories.png
- design-reference/adaptive/screens/54-android-lesson-journal.png
- design-reference/adaptive/screens/55-android-tablet-lesson.png
- design-reference/adaptive/screens/56-android-fold-storyboard.png
- design-reference/adaptive/screens/57-android-cloud-preflight.png
- design-reference/adaptive/screens/58-android-render-queue.png
- design-reference/adaptive/screens/59-android-film-delivery.png
- design-reference/adaptive/screens/60-android-studio-settings.png

**Owned areas**

- `android/studio/src/test/coverage/**`
- `evidence/android/A74/**`
- `scripts/android/side-by-side/**`

**User stories:** 214, 330

**Gate:** none

## A75: Story engine in Kotlin: keepers, staleness, StoryDirector, RulesPlanner and the EDL compiler with parity to the Python reference

`studio-story-engine` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A60, S05, S06, S07

**What to build:** Ports the reference modules added by Studio S05–S07: keeper selection and ranking, cross-angle dedupe, staleness propagation, Progress comparisons, the StoryDirector grammar lint, the RulesPlanner for five profiles and three lengths, and the EDL compiler with PTS snapping and the audio bed; every vector kind they add passes and its marker flips. Why blocked: A60 (Studio models and validator); S05, S06, S07 (the reference modules and vectors are produced there).

**Acceptance criteria**

- [ ] Every keepers, director, planner and compile vector passes; markers read `.consumed`.
- [ ] A compiled plan validates with the A59 validator and hashes equal to the reference's for each sample profile.
- [ ] A correction marks dependent films stale exactly as the staleness vectors state.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Owned areas**

- `android/studio-core/keepers/**`
- `android/studio-core/story/**`
- `android/studio-core/compile/**`

**User stories:** 270, 271, 288

**Gate:** G-CORE (Studio S1 kinds)

## A76: LessonJournal and ProgressStoryBuilder in :studio-core

`studio-lessons-progress-logic` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A60, S05

**What to build:** Lesson records, clips, cues and drills, and the Progress Story builder that compares dated sessions only when definitions and methods match, with percentages from pct. Why blocked: A60; S05 (progress reference vectors).

**Acceptance criteria**

- [ ] Progress vectors pass; a comparison across differing definitions is refused with its reason.
- [ ] Checklist counts for the sample lesson equal 10/10, 20/20 and 0/5 → 2 of 3.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Owned areas**

- `android/studio-core/lessons/**`
- `android/studio-core/progress/**`

**User stories:** 268, 275, 278

**Gate:** none

## A77: Android FilmVerifier: full decode, frame count and timestamp grid, barcodes and clicks within one frame, audio sample count and overlay text

`film-verifier-android` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`, `resource:emulator`

**Blocked by:** A59, A21, S08, S09

**What to build:** AD22 verifier with MediaExtractor + MediaCodec: full decode; exact frame count and timestamp grid; output dimensions, aspect and codec facts equal to the plan; audio sample count and route; for barcode sources every frame's barcode equals the plan's frame map and clicks fall within ±1 output frame; overlay text equal to the fold at sampled frames. The report names the codec used. Why blocked: A59 (plan models); A21 (media module plumbing); S08 (barcode and click media fixtures); S09 (barcode-court vectors). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Each S08 barcode fixture verifies as passing; mutations that must fail: one dropped frame, a click shifted by two frames, a wrong overlay string, a missing audio packet.
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] Evidence states 'emulator software codec <name>'.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Verifier reports including mutation runs

**Owned areas**

- `android/media/verify/**`

**User stories:** 285, 286

**Gate:** none

## A78: Local film renderer on Media3 Transformer, each operation enabled only after its barcode-court test renders and verifies

`local-film-renderer-media3` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`, `resource:emulator`

**Blocked by:** A77, A75

**What to build:** A Transformer Composition from the compiled EDL: one sequence per output track; live and B-roll at 1×; replay by time-stretching a distinct inserted range with no frame interpolation; exact freeze from an extracted still held for the planned range; dissolve and dip with a two-sequence compositor; overlays (score bug from the fold, metric and cue chips, labels, Sample badge, one annotation); the audio bed with fades and holds; H.264 High (or HEVC Main) yuv420p, AAC-LC 48 kHz stereo MP4. An operation whose barcode-court vector fails stays disabled on Android (SD6b) and is listed. Cancelled or failed renders leave no partial file and originals unchanged. Why blocked: A77 (verifier); A75 (compiled plans). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Each barcode-court plan renders on jovra_phone_p9_api35 and passes A77; disabled operations are listed with the failing vector.
- [ ] Original hashes are equal before and after a cancelled and a failed render (test).
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Per-operation render/verify table

**Owned areas**

- `android/media/render/**`

**User stories:** 284, 289, 290

**Gate:** none

## A79: S1 tracer: one Match Broadcast film from the synthetic match produced, verified, recorded and delivered on the emulator

`studio-s1-tracer` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`, `resource:emulator`

**Blocked by:** A78, A72

**What to build:** `StudioEngine.produceFilm(projectId, profileId, options) -> FilmJob` composes keeper selection → brief → RulesPlanner → compile → validate → render → verify → record. Single-source SourceIngest (byte facts, hashes, decoded PTS table; sources needing normalization refused with 'needs normalization (coming with multi-angle)'), project from a session, the DeliveredArtifact moved atomically into the films folder only after verification, and the delivery screen (59) on real data. Why blocked: A78; A61 (project store); A72 (delivery screen). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] The synthetic match yields one verified Match Broadcast MP4 and a `ready` DeliveredArtifact (instrumented).
- [ ] A VFR source is refused with the normalization message.
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] Reported as 'rendered and verified on the Android emulator from synthetic fixtures'.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/59-android-film-delivery.png

**Owned areas**

- `android/studio-core/engine/**`
- `android/media/ingest/**`
- `android/studio/films/delivery/** (ownership transfers from A72, which merged first)`

**User stories:** 245, 246, 247, 248, 285, 290

**Gate:** none

## A80: Local film jobs for all five profiles: resumable WorkManager renders, notifications, real story modes and stale-on-correction

`local-film-jobs-five-profiles` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`, `resource:emulator`

**Blocked by:** A79, A69

**What to build:** All five profiles through produceFilm; long renders on WorkManager with a mediaProcessing foreground service, resumable at stage checkpoints; job notifications only when on and granted; story modes and profile screens on real readiness, lengths, options and preview; a correction marks films 'Made before a correction' with Rebuild. Why blocked: A79; A69 (screens). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Each profile renders and verifies from the synthetic match on the emulator.
- [ ] Killing the app mid-render resumes from the last checkpoint without re-rendering completed stages (instrumented).
- [ ] A point correction marks dependent films stale (test).
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/49-android-story-modes.png

**Owned areas**

- `android/studio/films/jobs/** (ownership transfers from A72)`
- `android/studio/films/stories/** (ownership transfers from A69)`
- `android/studio/films/profiles/** (ownership transfers from A69)`

**User stories:** 264, 265, 266, 267, 269, 271, 287, 288

**Gate:** none

## A81: Film storyboard for real: re-validated edits, continuous draft cuts and Rebuild

`storyboard-real` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A80, A71

**What to build:** 56 on real plans: each edit validated before save with a refused edit naming the rule in words, draft cuts saved continuously and restored after process death, Rebuild producing a verified film. Why blocked: A80; A71.

**Acceptance criteria**

- [ ] A rule-breaking edit is refused with the rule's wording (test per rule family).
- [ ] Draft cut survives process death (disk).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/56-android-fold-storyboard.png

**Owned areas**

- `android/studio/editor/storyboard/** (ownership transfers from A71)`

**User stories:** 281, 282

**Gate:** none

## A82: Project player for one angle and angle insights on real data

`player-insights-real` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A79, A68

**What to build:** 47 one-angle real: score at the playhead, point bookmarks, study controls, keeper marking; 48 real: manual observations, confirm or reject estimated cues (hidden without an Android benchmark), keep a cue for a lesson. Why blocked: A79; A68.

**Acceptance criteria**

- [ ] Score at playhead equals the fold (test).
- [ ] A cue from a capability without an Android record is not shown (test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/47-android-fold-broadcast.png
- design-reference/adaptive/screens/48-android-angle-insights.png

**Owned areas**

- `android/studio/editor/player/** (ownership transfers from A68)`
- `android/studio/editor/insights/** (ownership transfers from A68)`

**User stories:** 256, 257, 261, 262, 263

**Gate:** none

## A83: Lesson journal and workspace for real, lesson links from films, Progress Story and private lesson export

`lessons-progress-real` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A76, A70, A80, A37

**What to build:** 54/55 on real lessons, lesson linking from films, Progress Story films from A76, and a private lesson export as a Share Pack scoped to one lesson's notes and clips. Why blocked: A76; A70; A80; A37 (Share Pack builder).

**Acceptance criteria**

- [ ] A lesson export contains only that lesson's clips and notes (zip listing test).
- [ ] Progress Story refuses mismatched definitions with the reason shown.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/54-android-lesson-journal.png
- design-reference/adaptive/screens/52-android-progress-story.png

**Owned areas**

- `android/studio/films/lessons/** (ownership transfers from A70)`
- `android/studio/films/progress/**`

**User stories:** 273, 274, 275, 276, 277, 278

**Gate:** none

## A84: Saving films: Include audio, a separately verified no-audio file, Movies/JOVRA, and Prepare for YouTube

`saving-films-youtube` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`, `resource:emulator`

**Blocked by:** A80

**What to build:** Include audio shown whenever a film leaves the app (off by default except Rally Pulse), each variant its own verified file, version choice, Save to Movies/JOVRA through MediaStore, and 'Prepare for YouTube' saving the film, a cover from a real frame, a draft title, description and chapters, never publishing. Why blocked: A80. Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] The no-audio variant passes the verifier with zero audio tracks; the audio variant passes with its sample count.
- [ ] The YouTube package contains the listed files and `published` is false.
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Junior profile: no Include audio switch is shown and the saved film passes FilmVerifier with zero audio tracks (story 304).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/59-android-film-delivery.png

**Owned areas**

- `android/studio/films/delivery/save/** (inside A79's delivery package, which merged first)`
- `android/studio/films/delivery/youtube/**`

**User stories:** 303, 304, 305, 306

**Gate:** none

## A85: Studio S1 journey gate on Android: one match to five verified films, lessons and saved files, end to end on the emulator

`studio-s1-journey-gate` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:qa`, `resource:emulator`

**Blocked by:** A81, A82, A83, A84

**What to build:** The Studio S1 journey on Android from the synthetic sample video: session → project → points and keepers → profile and length → plan → compile → validate → render → verify → record → lesson → Progress Story → save with and without audio → Prepare for YouTube → delivery, driven by a Maestro flow and instrumented tests, with the Studio spec's S1 mutation tests. Jon's old match (real footage) is a separate real-media gate. Why blocked: A81; A82; A83; A84. Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] The Maestro journey passes on jovra_phone_p9_api35; each of five films passes FilmVerifier.
- [ ] Each S1 mutation fails as required (listed in the PR).
- [ ] Report labelled 'rendered and verified on the Android emulator from synthetic fixtures'; real-media column 'not run'.
- [ ] Each AVD use follows the avd.sh lease, create/delete and disk rules; OlamyPixel untouched.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Maestro output
- Verifier reports
- evidence/android/A85 report

**Owned areas**

- `android/maestro/studio-s1/**`
- `evidence/android/A85/**`

**User stories:** 284, 285, 286, 287, 291

**Gate:** Real media (Jon's match)

## A86: ProxyNormalizer and multi-source import: CFR render proxies with original-PTS tables, rotation once, HDR to SDR

`proxy-normalizer-multisource` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`, `resource:emulator`

**Blocked by:** A79, S56, S58, A67

**What to build:** Transformer render proxies at constant frame rate with rotation applied once, HDR tone-mapped to SDR with a declared method, zero start, and an explicit hashed original-PTS → proxy-frame table; analysis proxies keep original timestamps; original hashes checked unchanged after every run; two-view import (45) for real. Why blocked: A79 (ingest); A67 (the sources screen it wires); S56 (normalization contract and vectors); S58 (multi-angle synthetic fixtures). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Normalization fixtures: decoded frame IDs match the PTS tables 100% (instrumented).
- [ ] Original hashes unchanged after a cancelled normalization.
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/45-android-source-import.png

**Owned areas**

- `android/media/normalize/**`
- `android/studio/editor/sources/** (ownership transfers from A67)`

**User stories:** 246, 247, 322

**Gate:** none

## A87: Sync anchors from the Android HitDetector, markers and capture hints, and the sync desk for real

`sync-anchors-desk-real` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A86, A35

**What to build:** Anchors from Android HitDetector onsets (same algorithm), marked visual anchors and capture hints from the journal (fileZeroHostNs on elapsedRealtimeNanos); fitting by :studio-core; the sync desk and sheets for real: add marker, nudge by frames, reject anchor, Confirm sync only after the checks, 'Needs review' below thresholds with the reason, lanes adjustable by point and frame for TalkBack. Room clock pings are not alignment evidence and are not in contract v1. Why blocked: A86; A35 (HitDetector).

**Acceptance criteria**

- [ ] On the synthetic two-camera fixture the fitted offset and drift fall within the S2 tolerances; a sub-threshold fit reads 'Needs review'.
- [ ] Sync edits survive process death (disk).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/46-android-fold-sync.png

**Owned areas**

- `android/studio/editor/sync/** (ownership transfers from A67)`
- `android/media/syncanchors/**`

**User stories:** 249, 250, 251, 252, 253, 255

**Gate:** none

## A88: Multi-angle player and multi-angle films (alt-bed, multi-angle live and replay) with the S2 synthetic two-camera gate

`multi-angle-player-films` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`, `resource:emulator`

**Blocked by:** A87, A80, A82, A55

**What to build:** Angle switching on the match clock without changing the score, no-coverage honesty, keeper marking per angle, alt-bed and multi-angle live/replay in films, and the S2 multicam §8.3 tests through the Kotlin port on the synthetic two-camera match. It also fills A55's multi-angle slot: opening a mark with a confirmed sync map shows every angle with its Reviewed, Estimated or not-aligned state and steps frames on the match clock (story 353). Why blocked: A87; A80; A82; A55 (the mark review slot). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Switching angle keeps the score and match time (test).
- [ ] A multi-angle film from the synthetic pair renders and verifies on the emulator.
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Opening a mark on the synthetic two-camera match shows both angles with their sync states (Reviewed, Estimated or not aligned) and frame steps keep both on the match clock (test).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/47-android-fold-broadcast.png

**Owned areas**

- `android/studio/editor/player/multi/** (inside A82's player package)`
- `android/media/render/multiangle/**`
- `android/feature/sessions/marks/slots/multiangle/**`

**User stories:** 257, 258, 323, 353

**Gate:** Two-view real footage (separate)

## W01: Swift JovraRoom package part 1: spec/room records, invalid cases and the freshness, snapshot, status, display, disconnect and analysis vectors, with a room CI workflow

`jovraroom-swift-records-freshness` · watch · size L · labels `ready-for-agent`, `platform:ios`, `track:watch`, `area:room`

**Blocked by:** T03

**What to build:** The Swift twin of A65 (G-ROOM / G-W-CONTRACT, iOS side). A new Foundation-only SwiftPM package `ios/Packages/JovraRoom` (builds and tests on Linux; depends on JovraCore only for the canonical JSON writer) holding jovra.room.*/1 models with strict decoding and canonical re-encoding, receiver-owned freshness on an injected monotonic clock (ContinuousClock in production, never mach_absolute_time), snapshot acceptance, phone status rows, display strings, disconnect handling and the analysis result gate. A test helper locates spec/room/fixtures from #filePath (no copies) and fails on an unknown kind or an unconsumed file. New workflow .github/workflows/room.yml with `room-contracts` (python3 scripts/spec/validate_room.py) and `jovra-room` (swift test on Linux); core ci.yml and studio.yml are not edited. Studio S68/S69 predate spec/room and target a different draft (jovra.room/1 in spec/studio); this package is the spec/room implementation they should consume (see notes), so nothing here duplicates a Studio ticket. Why blocked: T03 (JovraCore canonical JSON writer reused, not copied).

**Acceptance criteria**

- [ ] All 27 records round-trip canonically; all 103 invalid cases are rejected (61 schema-layer by strict decoding, 42 with the reference's code).
- [ ] Vectors pass: freshness 14, snapshot 14, phone-status 5, display 6, disconnect 1, analysis 7; the 5,000/5,001/15,000/15,001 ms boundaries are asserted.
- [ ] Mutations that must fail: fresh threshold 6 s; unbounded transit treated as bounded; a clock that stops during sleep (fake) under-states age.
- [ ] `swift test --package-path ios/Packages/JovraRoom` passes on macOS and in the Linux job; a grep for `import UIKit|SwiftUI|WatchConnectivity` under the package returns nothing.
- [ ] room.yml runs both jobs on a PR; breaking a room fixture in a scratch branch turns room-contracts red.

**Evidence required**

- swift test output (macOS + Linux CI log)
- validate_room.py output
- Mutation transcripts

**Owned areas**

- `ios/Packages/JovraRoom/Sources/JovraRoom/{Records,Freshness,Snapshot,Status,Analysis}`
- `ios/Packages/JovraRoom/Tests/Part1`
- `ios/Packages/JovraRoom/Package.swift`
- `.github/workflows/room.yml`

**User stories:** 68, 69, 71, 72, 73, 90, 91

**Gate:** G-ROOM / G-W-CONTRACT (part 1)

## A89: :room-protocol part 2: invitations with commit-then-reveal codes, the command ledger bound to the authenticated peer, outbox, bridge acceptance and AlertPolicy

`room-protocol-invites-ledger-bridge` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:room`

**Blocked by:** A65, W01

**What to build:** G-ROOM, Kotlin side, part 2: invitation vectors (single use, ≤ 10 min, strict QR parsing, local-only endpoints, commit-then-reveal six-digit code, attempt limit, alreadyMember, host transfer voiding invites), the ledger whose API takes the authenticated peer device for every frame (issuer bound to the channel peer, member-scoped idempotency, payload hash excluding ageAtSendMs, fail-closed transit, grants as sets, watch capture requests refused), the outbox (ageAtSendMs recomputed on every send, epoch guard, offline chains), bridge acceptance (paired phone only, retired instance, strictly increasing bridgeSeq, epoch/revision regressions) and AlertPolicy. Closes the Kotlin ledger half of F-ROOM-PORTS; A90 closes the Kotlin transport half by passing the authenticated peer on every frame. Why blocked: A65; W01 (its room.yml `room-contracts` job runs validate_room.py in CI, which G-ROOM requires).

**Acceptance criteria**

- [ ] Vectors pass: invitation 28, ledger 22, outbox 8, bridge 6, alerts 9, watch-sample 9 (82 cases; 129 with part 1).
- [ ] Room mutation set fails as required: forged issuer (ledger ignores the peer), replayed bridge payload accepted, frozen send age.
- [ ] Every spec/room fixture file is consumed (manifest test); no room kind remains `.pending`.
- [ ] G-ROOM evidence cites a green `room-contracts` CI run of `python3 scripts/spec/validate_room.py` on the same commit.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Mutation transcripts

**Owned areas**

- `android/room-protocol/invitation/**`
- `android/room-protocol/ledger/**`
- `android/room-protocol/bridge/**`
- `android/room-protocol/alerts/**`
- `android/room-protocol/conformance/part2/**`

**User stories:** 227, 316, 317

**Gate:** G-ROOM (Kotlin)

## A90: :room-transport: NSD picker-first discovery, TLS 1.3 with SPKI pinning, length-prefixed framing, QR invites with the in-app scanner and the LocalOnlyHotspot host

`room-transport-lan` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:room`

**Blocked by:** A89, A02

**What to build:** The only module that touches sockets or Wi-Fi. NSD advertise/browse with an opaque random room hint, the system picker path first (no local-network permission), every resolved address re-checked against the LAN allow-list; TLS 1.3 SSLSocket with a pinned X509TrustManager (hostKeySha256) and guest P-256 keys in Android Keystore; 4-byte length-prefixed JSON frames with a maximum length; the authenticated peer passed to the ledger on every frame; QR generation and an in-app scanner whose camera frames come from :media (android/media/ui/scanner; CameraX stays in :media) and are decoded by a pure-JVM decoder in :room-transport (no native library) accepting only `jovra-room:1:` payloads and never opening a URL; LocalOnlyHotspot host with the QR's network block; NEARBY_WIFI_DEVICES requested only for hotspot/raw-address paths. Tests run two endpoints in one JVM/Robolectric process over loopback TLS. Real LAN behaviour is UNVERIFIED until A92. targetSdk stays 36 (G-TARGET37). Why blocked: A89; A02 (NEARBY_WIFI_DEVICES and the module manifest are declared there).

**Acceptance criteria**

- [ ] Loopback: join, commit-then-reveal approval, ack and stop-all complete over TLS; a guest presenting the wrong pinned key is refused.
- [ ] A man-in-the-middle fixture with a third key produces mismatched codes and is refused.
- [ ] A QR whose endpoint is a public address is refused before any connection; the advertised instance name contains no player, project or device name.
- [ ] A frame over the maximum length closes the connection.
- [ ] Module-boundary check still shows sockets only in :room-transport and CameraX only in :media.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/43-android-camera-lobby.png

**Owned areas**

- `android/room-transport/**`
- `android/media/ui/scanner/**`

**User stories:** 221, 222, 225, 227, 229

**Gate:** Two-phone room (real LAN); G-TARGET37 for targetSdk 37

## A91: Camera lobby and director capture on a real JOVRA Room v1: invites, code approval, acknowledgements, heartbeats and stop fan-out

`lobby-director-capture-real` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:room`, `resource:emulator`

**Blocked by:** A90, A66, A24

**What to build:** 43 real: invites per slot, approval only after both phones show the same six-digit code, revoke closing the connection and voiding the code, readiness; 44 real: every phone records with the unchanged core engine, sends recordingStarted acknowledgements and device-status heartbeats every 2 s, 'Recording on n of m' from fresh acknowledgements, start Pending until acknowledged (a locked or backgrounded phone ends Pending or Rejected), Mark point with a receipt, stop-one and a confirmed stop-all fan-out with per-device results, no automatic stop on disconnect, and host loss leaving every local recording running. Lobby and room state survive rotation, fold and process death with cached device status shown Unknown. Why blocked: A90; A66 (demo screens); A24 (core capture). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] In-process two-endpoint test: host + 3 guests, one revoked, one silent for 42 s → 'No contact for 0:42 · may still be recording', count drops to 2 of 3 fresh, never marked stopped.
- [ ] Stop-all with one guest unreachable reports Accepted, Accepted, Unknown (test).
- [ ] Process death in the lobby restores the invite id and shows remote rows Unknown until heard.
- [ ] AVD `jovra_phone_p9_api35` via `android/scripts/avd.sh acquire` (exclusive JOVRA emulator lease; created from the installed android-35 image with the toolchain §7.1 config.ini only if absent; cold boot, no snapshots); released, and deleted after evidence if free space < 8 GB; if avd.sh refuses for disk, the emulator rows are reported 'not run (disk)' and the ticket stays open; OlamyPixel untouched.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] In-process two-endpoint test: a guest with camera permission denied and a guest backgrounded during start each end Pending → Rejected with the reason shown on the host, and neither is ever counted as recording (story 239).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/43-android-camera-lobby.png
- design-reference/adaptive/screens/44-android-director-capture.png

**Owned areas**

- `android/studio/build-match/lobby/real/**`
- `android/studio/build-match/director/real/**`
- `android/media/capture/roomparticipant/**`

**User stories:** 221, 222, 223, 224, 228, 231, 233, 235, 236, 237, 238, 239, 240, 241, 242

**Gate:** Two-phone room (A2)

## W02: Swift JovraRoom part 2: commit-then-reveal invitations, the ledger bound to the authenticated peer, outbox, BridgeReceiver, HealthSummary and AlertPolicy

`jovraroom-swift-invites-ledger-bridge` · watch · size L · labels `ready-for-agent`, `platform:ios`, `track:watch`, `area:room`

**Blocked by:** W01

**What to build:** Twin of A89 and the watch spec's pure modules on Apple platforms: invitations (strict QR, local endpoints, commit-then-reveal six-digit code, attempt limit), CommandLedger with an API that requires the authenticated peer device per frame, Outbox (ageAtSendMs recomputed on every send, epoch guard, offline chains), BridgeReceiver (paired phone only, retired instances, strictly increasing bridgeSeq, no epoch/revision regression, replay marks persisted across restarts, freshness not), HealthSummary (enrolled from the roster, fresh, freshRecording; elapsed frozen as last reported), AlertPolicy and ServeResultGate. Closes the Swift ledger-API half of F-ROOM-PORTS (the ledger requires the authenticated peer); the transport half (D1: the Swift carrier passes the authenticated peer on every frame) stays with the rescoped S69/S70 (cross-DAG finding 1). Why blocked: W01.

**Acceptance criteria**

- [ ] Vectors pass: invitation 28, ledger 22, outbox 8, bridge 6, alerts 9, watch-sample 9 (129 total with W01).
- [ ] Room mutation set fails as required: forged issuer, replayed bridge payload, frozen send age.
- [ ] Every spec/room fixture file is consumed; the manifest test passes on Linux.
- [ ] Public API used by the watch app is documented in the package README (HealthSummary, FreshnessClock, BridgeReceiver, Outbox, AlertPolicy, ServeResultGate).

**Evidence required**

- swift test output (macOS + Linux)
- Mutation transcripts

**Owned areas**

- `ios/Packages/JovraRoom/Sources/JovraRoom/{Invitation,Ledger,Outbox,Bridge,Health,Alerts}`
- `ios/Packages/JovraRoom/Tests/Part2`

**User stories:** 9, 10, 32, 35, 36, 37, 38, 53, 60, 61, 66, 87, 91

**Gate:** G-ROOM / G-W-CONTRACT (Swift)

## A92: A2 two-phone gate: Pixel and iPhone, each as host and camera, with the runbook and log collector

`two-phone-room-gate` · android · size M · labels `ready-for-agent`, `platform:shared`, `track:android`, `area:room`

**Blocked by:** A91, W02, S71

**What to build:** The agent half: a runbook and checklist for the A2 list (invite, commit-then-reveal approval, independent recording, acknowledgement, stale and Unknown, stop one, stop-all with per-device results, disconnect and rejoin, expired and replayed invites refused, a forwarded QR declined three times then revoked, camera permission denied, app backgrounded during start), an Android log collector and an evidence template, rehearsed end to end on the in-process loopback. The human half: Jon runs it with his Pixel and an iPhone; until then the gate is reported not run. The iPhone side must speak spec/room (W02), not the older spec/studio jovra.room/1 draft, so the device run is blocked pending the S68-S72 rescope decision (cross-DAG finding 1). The collector writes S73's report format when S73 has merged. Closure: this ticket closes on the loopback rehearsal, the runbook and the log collector; the physical run is a gate row, not a closure condition. Why blocked: A91; W02 (Swift spec/room protocol); S71 (iOS lobby on a real room).

**Acceptance criteria**

- [ ] The loopback rehearsal produces a complete evidence report from the template (every row filled or marked 'needs device').
- [ ] The runbook names both device roles and every A2 row; the log collector redacts tokens, keys and QR secrets (test).
- [ ] With devices: every A2 row passes on Pixel host + iPhone camera and iPhone host + Pixel camera, or the failing rows are filed.
- [ ] The evidence report has one row per finding (F-ADR-0017, F-ROOM-STILL, F-STUDIO-INVITE) with its open/closed state; A2 is never reported passed while any is open.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Rehearsal report
- Device evidence (when run)

**Screens**

- design-reference/adaptive/screens/43-android-camera-lobby.png

**Owned areas**

- `docs/android/field-tests/two-phone/**`
- `scripts/android/room-log-collector/**`
- `evidence/android/A92/**`

**User stories:** 223, 324

**Gate:** Gate A2 (Jon's Pixel + iPhone; physical row only); F-ADR-0017, F-ROOM-STILL (decided or deferred with Jon's sign-off) and F-STUDIO-INVITE must be closed before A2 is reported passed; S68-S72 rescope decision

## A93: Six-device field protocol on Android (S3/A4): 60-minute mixed-OS session, per-device recovery and warnings

`six-device-field-android` · android · size M · labels `ready-for-agent`, `platform:shared`, `track:android`, `area:room`

**Blocked by:** A92, A88, S73

**What to build:** Android side of the six-phone run, extending S73's protocol and report template with Android rows rather than writing a parallel document: protocol additions for Android participants, per-device recovery after forced kills, acknowledgement counts, silenced device shown with contact age and complete locally, thermal/battery/storage warnings, and the six-device sync report input. Still cadence waits for F-ROOM-STILL. Rehearsed on the loopback; the run is a hardware gate. Why blocked: A92; A88 (multi-angle sync for the report); S73 (the six-device protocol, template and log collector this extends).

**Acceptance criteria**

- [ ] Loopback rehearsal with six simulated participants produces the report template filled.
- [ ] Field run (when held): every phone's local recording complete after forced kills, or failures filed.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Rehearsal report
- Field evidence (when run)

**Owned areas**

- `docs/studio/field-tests/ (Android rows in S73's six-device protocol and template only; Studio-owner review)`
- `evidence/android/A93/**`

**User stories:** 324

**Gate:** Six-device field (Studio S3 / A4); F-ROOM-STILL for still cadence

## A94: Aged secondary stills on both ports, once F-ROOM-STILL decides the still record

`room-stills-both-ports` · android · size M · labels `ready-for-agent`, `platform:shared`, `track:android`, `area:room`

**Blocked by:** A91, W02

**What to build:** Story 234, deferred out of A66/A91: when the spec/room owner decides `jovra.room.still/1` (size, format, cadence under heat, consent for a still of a person, and how image bytes are framed beside the JSON records), port the record and its vectors to Kotlin (:room-protocol) and Swift (JovraRoom), show secondary previews as stills labelled with their receiver-owned age ('Preview 8 s ago'), never as live video, and file the alignment issue on S72's existing 5 s still cadence. If F-ROOM-STILL closes as 'deferred' with Jon's sign-off, this ticket closes as deferred with no code. Why blocked: A91 (Android director capture); W02 (JovraRoom); gate F-ROOM-STILL.

**Acceptance criteria**

- [ ] Does not start until F-ROOM-STILL is closed (link); a deferral closes the ticket with no code.
- [ ] Every still vector in spec/room passes in Kotlin and in Swift (counts in the PR).
- [ ] The director screen shows each secondary still with its age from the receiver's clock and never animates it (test); the age label is spoken to TalkBack.
- [ ] An issue on S72 records whether its still cadence matches the decided record.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle and swift test output
- CI run links

**Screens**

- design-reference/adaptive/screens/44-android-director-capture.png

**Owned areas**

- `android/room-protocol/still/**`
- `android/studio/build-match/director/stills/**`
- `ios/Packages/JovraRoom/Sources/JovraRoom/Still`
- `ios/Packages/JovraRoom/Tests/Still`

**User stories:** 234

**Gate:** F-ROOM-STILL

## A95: Android CloudClient Test and Live adapters on OkHttp, contract-tested against the backend fixtures, with the test identity and Keystore credential store

`cloud-client-test-identity` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A72, S81

**What to build:** Test adapter (base URL, issuer and publishable key from build configuration; refuses to start without them) and Live adapter (compiled, disabled until activation), contract-tested by a MockWebServer that replays the backend request/response fixtures; tester sign-in with email one-time codes against the isolated test Auth project; session tokens encrypted with an Android Keystore AES-GCM key (decide EncryptedSharedPreferences vs Keystore + AES-GCM and record it against CLAUDE.md rule 5); the mode always shown (Local demo, Test, Connected); signing out keeps local projects and films. Why blocked: A72 (screens); A61 (CloudMode); S81 (backend contract fixtures).

**Acceptance criteria**

- [ ] Every gateway route fixture replays green; a response violating its schema fails the client test.
- [ ] A demo or test token sent to the live adapter is refused before any request (test).
- [ ] No token appears in logs or plain preferences (scan test).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/60-android-studio-settings.png

**Owned areas**

- `android/studio/cloud/client/**`
- `android/studio/cloud/identity/**`

**User stories:** 325, 326, 327, 328, 329

**Gate:** Test backend activation (S104) for hosted runs

## A96: Cloud quote, render jobs and private delivery for real against the stubbed gateway, with idempotency persisted before every send

`cloud-quote-jobs-delivery-real` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A95, A84

**What to build:** 57–59 against the Test adapter: quote acceptance and its idempotency key persisted before the request; uploads as server-instructed parts, resumable, Wi-Fi only, run as user-initiated jobs; real job stages; private delivery and 24-hour share links; duplicate requests, redelivered messages and retries create one job, one reservation and one artifact; cancellation keeps local sources; the 'Cloud planning on' state stays off until F-QUOTE-CONSENT closes. Why blocked: A95; A84 (local delivery variants).

**Acceptance criteria**

- [ ] Rotation and process death during acceptance never create a second reservation (MockWebServer request count).
- [ ] An upload killed at 50% resumes from the last acknowledged part.
- [ ] Cancelling a job leaves source files and hashes unchanged.
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] Only labelled Test or Sample quotes are accepted; real-quote and charge rows read 'not run' until the pricing ADR (F-ADR-0023) lands.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/57-android-cloud-preflight.png
- design-reference/adaptive/screens/58-android-render-queue.png
- design-reference/adaptive/screens/59-android-film-delivery.png

**Owned areas**

- `android/studio/films/quote/** (ownership transfers from A72)`
- `android/studio/films/jobs/cloud/** (inside A80's jobs package)`
- `android/studio/films/delivery/cloud/** (inside A79's delivery package)`

**User stories:** 292, 296, 300, 301, 307

**Gate:** F-QUOTE-CONSENT; F-ADR-0023 (pricing ADR) for real quotes; test backend activation

## A97: Studio storage providers on Android: device, Files folder, Google Drive wrapper, planned Box and Dropbox, no iCloud

`studio-storage-providers` · android · size M · labels `ready-for-agent`, `platform:android`, `track:android`, `area:studio`

**Blocked by:** A64, A49

**What to build:** One StorageProvider interface: Device (active), FilesFolder through ACTION_OPEN_DOCUMENT_TREE (reaches cloud-drive document providers), GoogleDrive wrapping the core archive connection with the same states, Box and Dropbox listed as planned; archive permission never treated as processing consent. Why blocked: A64 (settings screen); A49 (Drive archive).

**Acceptance criteria**

- [ ] Exporting a film to a SAF tree writes it and records the provider; revoking the grant shows the reconnect state.
- [ ] No iCloud provider exists on Android (test).
- [ ] TalkBack labels, targets >= 48 dp, no clipping at font scale 2.0, light/dark/high contrast (Compose UI tests + ATF checks; exceptions listed).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/60-android-studio-settings.png

**Owned areas**

- `android/studio/films/settings/providers/**`
- `android/data/providers/**`

**User stories:** 308, 309, 310, 311

**Gate:** none

## A98: Final Android QA: approved Roborazzi baselines, TalkBack and font-scale matrix, Maestro suite, performance smoke and the release registers

`final-android-qa` · android · size L · labels `ready-for-agent`, `platform:android`, `track:android`, `area:qa`, `resource:emulator`

**Blocked by:** A27, A33, A43, A47, A50, A52, A53, A54, A74, A85, A96, A97, A23, A93

**What to build:** The release-readiness pass, aggregating per-ticket evidence. Reference fidelity: a side-by-side page pairing derived screens A01–A20 with design-reference/screens/01–20 (hierarchy and copy) and 41–60 with the adaptive references, a reviewer line per pair. Accessibility matrix: TalkBack sweep, font scale to the system maximum, high contrast, animations off, keyboard and Switch Access focus order, 48 dp checks. Maestro suite on JOVRA AVDs: onboarding; demo entry and removal; setup → framing → record → interruption → resume → stop → processing → library; live scoring with undo; replay correction propagating to the overview; review deck; export; storage states with the fake Drive; Studio demo journey; fold/unfold and rotate with a pending job; process death with an unsaved note. A performance smoke with fixed thresholds (cold start, library of 200 sessions, replay seek). Registers: the UNVERIFIED register (capture durability, fps, thermals, Galaxy, real Drive, real footage, Wear pairing, hotspot clients, developer verification), the capability status report per AD14, the data-safety draft, the accessibility claims draft (only what passed), the Pixel/Galaxy hardware checklist and the gate table with separate evidence columns. It runs the full route × state Roborazzi coverage test across every core and Studio screen (A56 covers only its own screens). Every hinge or posture result is labelled 'injected FoldingFeature (window-testing)' or 'emulator posture, pixel_9_pro_fold profile (approximation)', and the UNVERIFIED register adds real hinge and posture sensor timing, the Pixel 10 Pro Fold outer display, capture continuity across a fold and Android 16 large-screen behaviour. Stories 321, 322 and 323 are registered as 'S5, registered not delivered' (A86 and A88 are partial). Why blocked: the leaf tickets of the Android DAG it aggregates, including recovery (A23) and the room gates' status (A93). Implied through other blockers and not repeated as edges: A55, A88, A58, A03.

**Acceptance criteria**

- [ ] The side-by-side page covers 20 core and 20 Studio references and every pair has a reviewer line (the generator refuses otherwise).
- [ ] Every Maestro flow passes on the named AVDs (one at a time, created/deleted per avd.sh rules, OlamyPixel untouched).
- [ ] The performance smoke passes its fixed thresholds on jovra_phone_p9_api35 (thresholds in the PR).
- [ ] The registers are complete; no emulator result is reported as device evidence; Galaxy claims read 'approximated'.
- [ ] The S5 interop list (fixtures byte for byte, mixed real media, cross-platform lobby, cross-platform project opening) has one gate-table row each with evidence or 'not run'.
- [ ] The full route × state coverage test over every core and Studio harness route passes, or lists each gap against its owner.
- [ ] Every hinge/posture result in the evidence is labelled injected or emulator-approximation; the UNVERIFIED register contains the four fold/Android 16 rows named above.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- evidence/android/A98/side-by-side.html
- Maestro outputs
- Performance smoke output
- Registers (UNVERIFIED, capability status, data safety, accessibility claims, hardware checklist, gate table)

**Screens**

- design-reference/screens/01-welcome.png … 20-settings-privacy.png (derived A01–A20; hierarchy and copy only)
- design-reference/adaptive/screens/41-android-studio-home.png … 60-android-studio-settings.png

**Owned areas**

- `android/maestro/core/**`
- `android/app/src/androidTest/perf/**`
- `evidence/android/A98/**`
- `docs/android/release/**`

**User stories:** 161, 174, 177, 330, 331, 332, 333, 334, 335, 344, 321

**Gate:** Hardware: Pixel/Galaxy (registered, not run here)

## A99: Lane B: one catalog diff to the current-stable stack and compileSdk 37 after G-SDK37, with an optional CI job

`lane-b-migration` · android · size S · labels `ready-for-agent`, `platform:android`, `track:android`, `area:foundation`

**Blocked by:** A98

**What to build:** After Jon approves the android-37.0 platform (G-SDK37): the version catalog moves to BOM 2026.09.00, Navigation 3 1.2.0 with adaptive-navigation3 1.3.0, lifecycle 2.11.0 (all lifecycle artifacts together), core 1.19.1, Wear Compose 1.7.1, and compileSdk 37 in build-logic; targetSdk stays 36 (G-TARGET37 is separate). Adds `android-lane-b` (workflow_dispatch) proving the upgrade in CI. The BOM bump changes Compose rendering, so this is the last Android ticket: every Roborazzi golden is re-recorded through the roborazzi-record job and reviewed in this PR. About 1 GB of new artifacts lands in the Gradle cache (G-DISK). Why blocked: A98 (all goldens are recorded and the release registers written first; the catalog comes from A01).

**Acceptance criteria**

- [ ] G-SDK37 approval is linked; without it the ticket does not start.
- [ ] checkAarMetadata passes on compileSdk 37; android-core, android-unit and Roborazzi verification stay green.
- [ ] targetSdk is 36 in the merged manifest.
- [ ] Every Roborazzi golden is re-recorded by the roborazzi-record job and the diff is reviewed in the PR; `df -h /` shows G-DISK headroom before the dependency download.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Owned areas**

- `android/gradle/libs.versions.toml`
- `android/build-logic/sdk/**`
- `.github/workflows/android.yml (lane-b job only)`

**User stories:** 336

**Gate:** G-SDK37; G-DISK

## W03: watchOS app target via XcodeGen: JovraWatch with the four-page shell, fake bridge, -watchState harness and JOVRA watch simulators

`watchos-target-scaffold` · watch · size L · labels `ready-for-agent`, `platform:ios`, `track:watch`, `area:watch`

**Blocked by:** W01, T06, S04

**What to build:** A JovraWatch watchOS app target (and JovraWatchUITests) added to ios/project.yml as a companion of the Jovra app, depending on JovraRoom; deployment target watchOS 11 to pair with iOS 18 (INFERRED; recorded for the target ADR). A vertical-page TabView (Health → Score → Latest serve → Mark) with NavigationStack for 'View all' and confirmations; the connection alert as a full-screen sheet. A WatchBridgeClient protocol with a FakeWatchBridge (deliver now / queue / drop / reorder / duplicate / restart) and a `-watchState <surface>.<state>` launch harness that feeds snapshots from spec/room records (Sample label when `sample: true`). Shared watch components: dark forest background, ivory text, chartreuse primary and fresh counts, clay attention, words + shapes for states, ≤ 18 characters per line with full names in accessibility labels. Uses simulators created by this ticket from the installed watchOS 26.5 runtime with `xcrun simctl create` and JOVRA names ('JOVRA Watch Ultra 3 49mm', 'JOVRA Watch Series 11 42mm', and 'JOVRA Watch SE 3 40mm' for the smallest case), deleted after evidence; no existing simulator pair is touched. The project.yml edit adds only the two targets and the JovraRoom package; the core owner reviews it. Why blocked: W01 (record models and freshness the harness and fake bridge use; HealthSummary and AlertPolicy from W02 are first needed by W04-W07); T06 (owns project.yml and the Info.plist/xcconfig chain); S04 (the other planned project.yml addition lands first so the edits are sequential).

**Acceptance criteria**

- [ ] `scripts/ios/generate.sh` then `xcodebuild -scheme JovraWatch -destination 'platform=watchOS Simulator,name=JOVRA Watch Ultra 3 49mm' build` succeeds; the iOS app build and core smoke UI tests stay green.
- [ ] Every registered -watchState opens its surface; an unknown value fails with a listed error (harness self-test).
- [ ] The fake bridge's queue path marks rows Unknown and the deliver-now path marks them Fresh (unit test via JovraRoom).
- [ ] The project.yml diff adds only the JovraWatch and JovraWatchUITests targets and the JovraRoom package (diff stat, core-owner review recorded).
- [ ] Simulators are created and deleted by `scripts/ios/watch-sim.sh` with JOVRA names; `xcrun simctl list` before/after shows no other device changed.

**Evidence required**

- xcodebuild output
- Harness self-test output
- simctl list before/after

**Screens**

- design-reference/adaptive/screens/61-watchos-camera-health.png (shell)

**Owned areas**

- `ios/JovraWatch/App`
- `ios/JovraWatch/Harness`
- `ios/JovraWatch/DesignSystem`
- `ios/JovraWatch/Bridge/Fake`
- `ios/JovraWatchUITests/Support`
- `ios/project.yml (JovraWatch targets and JovraRoom package only)`
- `scripts/ios/watch-sim.sh`

**User stories:** 1, 2, 13, 92

**Gate:** G-W-SIMUI (simulator)

## W04: Apple Watch camera health (61) and connection alert (65) in every state

`watchos-health-alert-surfaces` · watch · size L · labels `ready-for-agent`, `platform:ios`, `track:watch`, `area:watch`

**Blocked by:** W03, W02

**What to build:** W61: the large freshRecording/enrolled count with its basis line ('Recording, heard in the last 5 s'), rows with slot names, frozen last elapsed time, 'Unknown · 18 s' and 'May still be recording', storage/battery/heat flags, words for paused/finalizing/saved/failed, 'View all 6', host-unreachable state, single-phone 1/1, no video. W65: alert sheet naming camera and slot, 'Last heard 18 s ago. May still be recording.', 'Check on phone' and 'Acknowledge', phone-unreachable and host-lost variants. All from HealthSummary/AlertPolicy over fake snapshots. Screenshots compare against references 61 and 65 with the documented deliberate differences. Why blocked: W03 (shell, harness); W02 (HealthSummary, AlertPolicy).

**Acceptance criteria**

- [ ] Counts equal JovraRoom HealthSummary for each watch-sample vector snapshot (5/6 fresh with C3 Unknown at 18 s).
- [ ] A stale row's elapsed time does not advance across a 10 s wait in the UI test.
- [ ] XCUITest with performAccessibilityAudit on every -watchState state, VoiceOver labels in full words with ages, the largest Dynamic Type size without clipping, states shown by word and shape (not colour alone), Reduce Motion with no animated counters.
- [ ] Screenshots on Ultra 3 49mm, Series 11 42mm and SE 3 40mm for every state, paired with references 61 and 65 with reviewer lines.

**Evidence required**

- scripts/ios/ui-test.sh -only-testing output for the watch classes with simulator ids and .xcresult path
- Screenshots under evidence/watch/W04/

**Screens**

- design-reference/adaptive/screens/61-watchos-camera-health.png
- design-reference/adaptive/screens/65-watchos-connection-alert.png

**Owned areas**

- `ios/JovraWatch/Features/Health`
- `ios/JovraWatch/Features/Alert`
- `ios/JovraWatchUITests/Health`
- `ios/JovraWatchUITests/Alert`

**User stories:** 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 58, 59, 62, 64, 65, 82, 83, 84, 85, 86

**Gate:** G-W-SIMUI

## W05: Apple Watch score and undo (62) in every state

`watchos-score-surface` · watch · size M · labels `ready-for-agent`, `platform:ios`, `track:watch`, `area:watch`

**Blocked by:** W03, W02

**What to build:** W62: large point score, games smaller, server marked, 'Manual' provenance, Synced / 1 pending / Offline, scorer buttons ('Jon point', 'Alex point') only with the grant and the abilities toggle, 'sending' until a receipt, undo with confirmation naming the point, offline pending, expired → 'enter it on the phone', conflict 'Score changed on the phone. Now 30–15. Send Jon point again?', provisional score, 'Status only' when view-only, no serve numbers, never a declared winner. All on the fake bridge. Why blocked: W03 (shell, harness); W02 (ledger receipts).

**Acceptance criteria**

- [ ] Each receipt status from the ledger vectors renders its state (Pending, Accepted, Rejected, Expired, Conflicted) with the reason text.
- [ ] A view-only grant shows 'Status only' and no scorer buttons (test).
- [ ] No string on the score surface contains a serve speed, 'mph live' or 'fastest' (copy lint).
- [ ] XCUITest with performAccessibilityAudit on every -watchState state, VoiceOver labels in full words with ages, the largest Dynamic Type size without clipping, states shown by word and shape (not colour alone), Reduce Motion with no animated counters.
- [ ] Screenshots on the three JOVRA watch simulators paired with reference 62 with reviewer lines.

**Evidence required**

- ui-test.sh -only-testing output
- Screenshots under evidence/watch/W05/

**Screens**

- design-reference/adaptive/screens/62-watchos-score.png

**Owned areas**

- `ios/JovraWatch/Features/Score`
- `ios/JovraWatchUITests/Score`

**User stories:** 11, 26, 27, 28, 29, 30, 31, 33, 35, 36, 37, 39, 40, 41

**Gate:** G-W-SIMUI

## W06: Apple Watch latest serve (63) and mark for review (64) in every state

`watchos-serve-mark-surfaces` · watch · size M · labels `ready-for-agent`, `platform:ios`, `track:watch`, `area:watch`

**Blocked by:** W03, W02

**What to build:** W63: 'Not measured live' with the explanation, or the last post-capture estimate labelled 'Estimated average speed, contact→bounce' with units, point, camera and age, previous results shown as previous, 'Needs calibration' / 'Waiting for the phone', 'Mark this serve'. W64: one large 'Mark for review', optional reason, receipt 'Marked · Point 42', offline pending with original time, 'Review video on phone', 'Review needed · 2 marks', never an In/Out word. The estimate value state is reachable from fixtures only in v1 (no bridge wires a post-capture estimate). All on the fake bridge. Why blocked: W03 (shell, harness); W02 (ServeResultGate, ledger receipts).

**Acceptance criteria**

- [ ] ServeResultGate vectors drive W63: capability off → 'Not measured live'; calibration missing → 'Needs calibration'; older point → shown as previous.
- [ ] Each mark receipt status from the ledger vectors renders its state with the reason text; an offline mark keeps its original time.
- [ ] No string on these surfaces contains 'In', 'Out' as a verdict, 'mph live' or 'fastest' (copy lint).
- [ ] XCUITest with performAccessibilityAudit on every -watchState state, VoiceOver labels in full words with ages, the largest Dynamic Type size without clipping, states shown by word and shape (not colour alone), Reduce Motion with no animated counters.
- [ ] Screenshots on the three JOVRA watch simulators paired with references 63 and 64 with reviewer lines.

**Evidence required**

- ui-test.sh -only-testing output
- Screenshots under evidence/watch/W06/

**Screens**

- design-reference/adaptive/screens/63-watchos-serve.png
- design-reference/adaptive/screens/64-watchos-review-marker.png

**Owned areas**

- `ios/JovraWatch/Features/Serve`
- `ios/JovraWatch/Features/Mark`
- `ios/JovraWatchUITests/Serve`
- `ios/JovraWatchUITests/Mark`

**User stories:** 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 93, 94, 95

**Gate:** G-W-SIMUI

## W07: iPhone WatchBridge in single-phone mode over WatchConnectivity: snapshots, echo, marks with receipts and alert acknowledgement

`ios-watchbridge-single-phone` · watch · size L · labels `ready-for-agent`, `platform:ios`, `track:watch`, `area:watch`

**Blocked by:** W03, W02, T17, T24

**What to build:** Stage A3a on iOS. A WatchBridge adapter in the iPhone app projects its own CaptureEngine status and EventLog fold into jovra.room.watch-bridge/1 (its own host at epoch 1, roster of one, bridgeInstanceId per process, bridgeSeq increasing): updateApplicationContext for the latest snapshot (throttled to one per 2 s while foreground and on meaningful change), sendMessage echo when reachable, commands by sendMessage else transferUserInfo, receipts by reply or the next snapshot. MarkForReview lands as a core Mark point bookmark with a receipt; ackAlert clears the phone's alert. The watch-side WCSession client replaces the fake in live mode; the watch outbox persists across restarts. A 'Paired watch' status provider is exposed for phone screens; W08 fills the iPhone rows. G-W-SIMPAIR on a JOVRA-created iPhone + watch simulator pair covers the interactive path only (the Simulator does not support transferUserInfo). Where watch marks become reviewable on iPhone depends on the iOS core review surfaces (F-CORE-REVIEW). Why blocked: W03 (watch app); W02 (bridge and ledger); T17 (capture route and engine status); T24 (Mark point and the live score fold).

**Acceptance criteria**

- [ ] Unit tests with a fake WCSession: queued delivery → watch rows Unknown; an echo reply → Fresh; a duplicate MarkForReview returns the stored receipt.
- [ ] SIMPAIR run: echo, snapshot, MarkForReview and its receipt cross between a JOVRA iPhone simulator and its paired JOVRA watch simulator (log attached).
- [ ] The snapshot never contains media paths, images, tokens or invite codes (schema check + content scan).
- [ ] No HKWorkoutSession or keep-alive is started (grep and entitlement check).
- [ ] Evidence labels transport 'simulator interactive path only'; transferUserInfo and background delivery are listed for G-W-REALPAIR.
- [ ] In junior mode the bridge snapshot carries no names beyond those entered and the watch offers no sharing (test).
- [ ] Content test: every projected snapshot has liveServeSpeed false and serveSpeedResults off unless a post-capture estimate exists (none is wired in v1).
- [ ] Gate row F-CORE-REVIEW: a mark reviewed on the iPhone decrements 'Review needed' in the next snapshot (watch stories 55 and 95). Reported 'not run' while iOS has no Marked list; the bridge closes without it, and W26 lists the stories as partial.

**Evidence required**

- Hosted unit test output
- SIMPAIR transcript with simulator ids
- Content-scan output

**Screens**

- design-reference/adaptive/screens/61-watchos-camera-health.png

**Owned areas**

- `ios/Jovra/Platform/WatchBridge`
- `ios/JovraWatch/Bridge/Live`
- `ios/JovraTests/WatchBridge`

**User stories:** 2, 24, 52, 63, 69, 70, 87, 88, 89

**Gate:** G-W-SIMPAIR; G-W-REALPAIR (physical); F-CORE-REVIEW (review-count row)

## W08: iPhone 'Paired watch' surfaces: the camera lobby watch section (ST23) and the Studio settings row (ST40)

`ios-paired-watch-rows` · watch · size M · labels `ready-for-agent`, `platform:ios`, `track:watch`, `area:watch`

**Blocked by:** W07, S71, S29

**What to build:** Watch story 12 on iOS, which adaptive-screens C-A3 gives to the watch spec on both OSes (Android has A51, A64 and A66). The ST23 camera lobby gets a watch section and ST40 Studio settings a 'Paired watch · Status mirror' row, each read from W07's provider: none paired → hidden; app missing → 'Install JOVRA on your watch'; fresh → 'Last updated 2 s ago'; stale → 'Not updated for 40 s'; the row opens the abilities sheet. The views live in a new folder; the lobby and settings get one insertion line each in their declared slots, reviewed by the Studio owner. Why blocked: W07 (provider); S71 (lobby real wiring, so the insertion follows it); S29 (Studio settings slots).

**Acceptance criteria**

- [ ] Each provider state renders the exact copy in both places (XCUITest with injected bridge states).
- [ ] VoiceOver reads 'Paired watch, status and marks, last updated 2 seconds ago'; performAccessibilityAudit passes in light, dark and AX5; targets ≥ 44 pt.
- [ ] The diff in ios/Jovra/Features/Studio/Lobby and Settings is one insertion line each (diff stat, Studio-owner review recorded).
- [ ] Screenshots of both states paired with the ST23 and ST40 references in studio-screens.md with reviewer lines.

**Evidence required**

- ui-test.sh -only-testing output
- Screenshots under evidence/watch/W08/

**Screens**

- ST23 Camera lobby (watch section; studio-screens.md)
- ST40 Studio settings (Paired watch row; studio-screens.md)

**Owned areas**

- `ios/Jovra/Features/Studio/PairedWatch`
- `ios/Jovra/Features/Studio/Lobby (one insertion line; Studio-owner review)`
- `ios/Jovra/Features/Studio/Settings (one insertion line in its slot; Studio-owner review)`
- `ios/JovraUITests/Watch/PairedWatchRows`

**User stories:** 12

**Gate:** G-W-SIMUI

## W09: :wear-bridge Data Layer contract: paths, capability, codecs from :room-protocol and the FakeDataLayerClient

`wear-bridge-data-layer-contract` · watch · size M · labels `ready-for-agent`, `platform:android`, `track:watch`, `area:watch`

**Blocked by:** A89, A02

**What to build:** The shared half of AND-W, so the Wear surfaces do not wait on phone capture. :wear-bridge holds the Data Layer contract: DataItem `/jovra/v1/snapshot` (latest replaces; setUrgent while live), MessageClient `/jovra/v1/echo`, `/jovra/v1/command`, `/jovra/v1/receipt`, the CapabilityClient name `jovra_watch_bridge_v1` (declared in both manifests by A02), codecs from :room-protocol, the watch-side Data Layer client, and a FakeDataLayerClient (deliver now / queue / drop / reorder / duplicate / restart) that proves the freshness rules. Why blocked: A89 (bridge acceptance rules and codecs); A02 (manifests with the capability).

**Acceptance criteria**

- [ ] Fake Data Layer tests: a DataItem delivered after reconnect is Unknown on the watch until an interactive echo bounds transit; an echo makes rows Fresh.
- [ ] Codecs round-trip every watch-bridge record in spec/room canonically; a replayed bridgeSeq is rejected through the client (test).
- [ ] Path and capability constants match the spec/room bridge mapping (test reading the spec table).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Fake Data Layer transcript

**Owned areas**

- `android/wear-bridge/** (later subpackages projection, commands, alerts, stop and room belong to W10, W17, W19, W20, W21)`

**User stories:** 69, 70

**Gate:** none

## W10: Android phone-side Wear bridge in single-phone mode: snapshot projection, echo, marks with receipts and the live 'Paired watch' adapter

`wear-bridge-phone-single-phone` · watch · size L · labels `ready-for-agent`, `platform:android`, `track:watch`, `area:watch`

**Blocked by:** W09, A26

**What to build:** AND-W / A3a (android-v1-spec stories 314, 318, 319, 357). The phone projects its own RecordingEngine status and EventLog fold into jovra.room.watch-bridge/1 (epoch 1, roster of one), throttled to one per 2 s while foreground; MarkForReview becomes a Mark point with a receipt; ackAlert clears the phone's alert; no foreground-service keep-alive, fake workout or wake lock. Provides the live adapter behind the composition root's watch-bridge status seam that the 'Paired watch' rows (A51, A64, A66) read. Junior mode carries only entered names and the Wear app offers no sharing. Data Layer evidence between emulators needs G-WEARPAIR (Play image, G-DISK; Jon signs in himself; agents never enter credentials). Why blocked: W09 (contract, fake client); A26 (marks and the live fold; A24's capture status through it).

**Acceptance criteria**

- [ ] A duplicate MarkForReview returns the stored receipt; the same commandId with a different payload is rejected as commandIdReuse.
- [ ] The snapshot never contains media paths, images, tokens or invite codes, has liveServeSpeed false, and keeps serveSpeedResults off unless a post-capture estimate exists (content scan).
- [ ] The merged manifests of :app and :wear contain no FOREGROUND_SERVICE_HEALTH, no Health Services ExerciseClient use and no WakeLock held by the bridge (manifest and source check; watch story 88, android story 319).
- [ ] Junior-mode test: the snapshot carries only names as entered and the Wear app shows no sharing action (watch story 89).
- [ ] The G-W-WEARPAIR-EMU row is reported 'not run' unless G-WEARPAIR passed; the ticket closes on the fake-client evidence.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Fake Data Layer transcript

**Screens**

- design-reference/adaptive/screens/66-wearos-camera-health.png

**Owned areas**

- `android/wear-bridge/projection/**`
- `android/app/watchbridge/**`

**User stories:** 2, 12, 24, 52, 63, 87, 88, 89

**Gate:** G-WEARPAIR + G-DISK (Data Layer emulator evidence); G-W-REALPAIR (physical)

## W11: :wear app shell on Compose for Wear OS with camera health (66) and connection alert (70) in every state

`wear-app-health-alert-surfaces` · watch · size L · labels `ready-for-agent`, `platform:android`, `track:watch`, `area:watch`, `resource:emulator`

**Blocked by:** W09, A03

**What to build:** The Wear OS companion (minSdk 30, compile/target 36, Wear Compose Material 3 1.6.2): AppScaffold/ScreenScaffold, a HorizontalPagerScaffold for the four page surfaces, SwipeDismissableNavHost for 'View all' and confirmations, TransformingLazyColumn with rotary input, EdgeButton for primary actions, round-safe padding with nothing in the corners; a watchState harness via intent extras feeding spec/room snapshots through a fake bridge; the watch-side Data Layer client from W09. W66 and W70 with the same states and copy as W61/W65, laid out natively for round screens. Why blocked: W09 (bridge codecs, paths, fake client); A02 (the :wear manifest, applicationId and Roborazzi setup). Implied through other blockers and not repeated as edges: A02.

**Acceptance criteria**

- [ ] Counts equal :room-protocol HealthSummary for each watch-sample vector snapshot.
- [ ] Compose UI tests assert TalkBack semantics in full words with ages, no clipping at the largest font scale, round-safe padding (no text outside the circle on round configs), rotary scrolling on lists, and states by word and shape.
- [ ] Roborazzi screenshots (Robolectric device qualifiers, no emulator image needed) for every state on wearos_small_round, wearos_xl_round and wearos_rect, recorded by the roborazzi-record job and verified in android-unit (Robolectric sdk=34).
- [ ] Wear emulator screenshots on jovra_wear_xlround_api36 and jovra_wear_smallround_api36 are taken only after gate G-WEARIMG (Jon approves the 1,138 MB Wear OS 6 image and G-DISK holds); until then this row is reported 'not run' and the ticket still closes on the Roborazzi and Compose evidence.
- [ ] Component names are those of the resolved Wear Compose 1.6.2 APIs (compile proves it; any substitute is recorded).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Roborazzi images per config
- Wear emulator screenshots (after G-WEARIMG only)

**Screens**

- design-reference/adaptive/screens/66-wearos-camera-health.png
- design-reference/adaptive/screens/70-wearos-connection-alert.png

**Owned areas**

- `android/wear/app/**`
- `android/wear/harness/**`
- `android/wear/health/**`
- `android/wear/alert/**`

**User stories:** 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 58, 59, 62, 64, 65, 82, 83, 84, 85, 86

**Gate:** G-W-WEARUI; G-WEARIMG + G-DISK for emulator screenshots

## W12: Wear OS score and undo (67) in every state

`wear-score-surface` · watch · size M · labels `ready-for-agent`, `platform:android`, `track:watch`, `area:watch`, `resource:emulator`

**Blocked by:** W11

**What to build:** W67 with the same state model and copy as W62, laid out for round screens with EdgeButton scorer actions, confirmation for undo, receipts, conflict and expiry messages, 'Status only' when view-only. Why blocked: W11 (Wear shell, harness). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] Each receipt status from the ledger vectors renders its state with the reason text.
- [ ] Copy lint: no serve speed, no 'live' speed, no 'fastest' on the score surface.
- [ ] Compose UI tests assert TalkBack semantics in full words with ages, no clipping at the largest font scale, round-safe padding (no text outside the circle on round configs), rotary scrolling on lists, and states by word and shape.
- [ ] Roborazzi screenshots (Robolectric device qualifiers, no emulator image needed) for every state on wearos_small_round, wearos_xl_round and wearos_rect, recorded by the roborazzi-record job and verified in android-unit (Robolectric sdk=34).
- [ ] Wear emulator screenshots on jovra_wear_xlround_api36 and jovra_wear_smallround_api36 are taken only after gate G-WEARIMG (Jon approves the 1,138 MB Wear OS 6 image and G-DISK holds); until then this row is reported 'not run' and the ticket still closes on the Roborazzi and Compose evidence.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Roborazzi images per config

**Screens**

- design-reference/adaptive/screens/67-wearos-score.png

**Owned areas**

- `android/wear/score/**`

**User stories:** 11, 26, 27, 28, 29, 30, 31, 33, 35, 36, 37, 39, 40, 41

**Gate:** G-W-WEARUI; G-WEARIMG + G-DISK for emulator screenshots

## W13: Wear OS latest serve (68) and mark for review (69) in every state

`wear-serve-mark-surfaces` · watch · size M · labels `ready-for-agent`, `platform:android`, `track:watch`, `area:watch`, `resource:emulator`

**Blocked by:** W11

**What to build:** W68 and W69 with the same state model and copy as W63 and W64: 'Not measured live' / Estimated serve results with point and age, Mark for review with reason, receipt and 'Review needed · n marks'; never an In/Out word. Why blocked: W11 (Wear shell, harness). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] ServeResultGate vectors drive W68 states.
- [ ] Each mark receipt status from the ledger vectors renders its state with the reason text.
- [ ] Copy lint: no In/Out verdicts, no 'live' speed, no 'fastest'.
- [ ] Compose UI tests assert TalkBack semantics in full words with ages, no clipping at the largest font scale, round-safe padding (no text outside the circle on round configs), rotary scrolling on lists, and states by word and shape.
- [ ] Roborazzi screenshots (Robolectric device qualifiers, no emulator image needed) for every state on wearos_small_round, wearos_xl_round and wearos_rect, recorded by the roborazzi-record job and verified in android-unit (Robolectric sdk=34).
- [ ] Wear emulator screenshots on jovra_wear_xlround_api36 and jovra_wear_smallround_api36 are taken only after gate G-WEARIMG (Jon approves the 1,138 MB Wear OS 6 image and G-DISK holds); until then this row is reported 'not run' and the ticket still closes on the Roborazzi and Compose evidence.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links
- Roborazzi images per config

**Screens**

- design-reference/adaptive/screens/68-wearos-serve.png
- design-reference/adaptive/screens/69-wearos-review-marker.png

**Owned areas**

- `android/wear/serve/**`
- `android/wear/mark/**`

**User stories:** 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 93, 94, 95

**Gate:** G-W-WEARUI; G-WEARIMG + G-DISK for emulator screenshots

## W14: Apple Watch complications and always-on: timestamped snapshot, budget-aware refresh and tap-to-refresh

`watchos-complications-always-on` · watch · size M · labels `ready-for-agent`, `platform:ios`, `track:watch`, `area:watch`

**Blocked by:** W04, W05, W06, W07

**What to build:** WidgetKit complications showing '5/6 · 9:41' and the score with their timestamp; always-on and wrist-down show the last snapshot dimmed with 'Updated 9:41' and no per-second remote timers; tapping opens the app and requests an echo. The phone triggers transferCurrentComplicationUserInfo only on meaningful change and only with remaining budget (checked before use). It adds the JovraWatchComplications WidgetKit extension target and the app-group entitlement the widget needs to read the last snapshot: the only ios/project.yml edit after W03, reviewed by the core owner. Why blocked: W04, W05, W06 (surfaces); W07 (bridge path the refresh uses).

**Acceptance criteria**

- [ ] Timeline entries carry the snapshot time; a 2-minute-old entry renders its timestamp, never 'now' (WidgetKit snapshot test).
- [ ] With zero remaining complication budget the phone does not call the transfer (fake session test).
- [ ] Always-on rendering test shows no running timer views.
- [ ] XCUITest with performAccessibilityAudit on every -watchState state, VoiceOver labels in full words with ages, the largest Dynamic Type size without clipping, states shown by word and shape (not colour alone), Reduce Motion with no animated counters.

**Evidence required**

- Widget snapshot tests output
- Screenshots of complications families

**Screens**

- design-reference/adaptive/screens/61-watchos-camera-health.png (complication)

**Owned areas**

- `ios/JovraWatch/Complications`
- `ios/Jovra/Platform/WatchBridgeComplication`
- `ios/project.yml (JovraWatchComplications extension target and app-group entitlement only; core-owner review)`

**User stories:** 74, 75, 76, 77

**Gate:** G-W-SIMUI

## W15: Wear OS tile, complication data source and ambient snapshot

`wear-tiles-complications-ambient` · watch · size M · labels `ready-for-agent`, `platform:android`, `track:watch`, `area:watch`, `resource:emulator`

**Blocked by:** W12

**What to build:** Tiles 1.6.2 + protolayout tile and a complication data source with the same '5/6 · 9:41' + score content and timestamp, updated on meaningful change; ambient mode shows the last snapshot dimmed with its time and no per-second timers; tapping opens the app and requests an echo. Tile rendering in Robolectric is UNVERIFIED and checked first; if not possible, layout unit tests on the protolayout tree stand in and emulator evidence waits for G-WEARIMG. Why blocked: W12 (score surface; the count comes from W11 through it). Implied through other blockers and not repeated as edges: A03.

**Acceptance criteria**

- [ ] The tile layout tree contains the timestamp and count text (protolayout unit test).
- [ ] Complication data has the snapshot time and never 'now' for a stale snapshot.
- [ ] Wear emulator screenshots on jovra_wear_xlround_api36 and jovra_wear_smallround_api36 are taken only after gate G-WEARIMG (Jon approves the 1,138 MB Wear OS 6 image and G-DISK holds); until then this row is reported 'not run' and the ticket still closes on the Roborazzi and Compose evidence.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/66-wearos-camera-health.png (tile)

**Owned areas**

- `android/wear/tiles/**`
- `android/wear/complications/**`

**User stories:** 74, 75, 76, 77

**Gate:** G-WEARIMG + G-DISK for emulator evidence

## W16: Watch score commands on iOS (A3b): PointWon and Undo with receipts, conflicts and offline chains through the iPhone

`score-commands-ios` · watch · size M · labels `ready-for-agent`, `platform:ios`, `track:watch`, `area:watch`

**Blocked by:** W07, W05

**What to build:** Phone-side ScoreCommandReconciler on iPhone: authorize the role, check the epoch, compare baseEventRevision with the current revision; equal → append a PointOutcome (provenance manual, source user, issuer recorded) or a Void of the last outcome, refold, Accepted with canonicalEventRevision; different → Conflicted with the current score in the next snapshot. 'Score from watch' is off until the scorer enables it on the phone (abilities sheet). The watch outbox chains offline points and holds later ones when one is not accepted. Single-phone mode now; through the room only after Gate A2. It ships A3b behind the 'Score from watch' flag: the A3b stage exit is 'not met' until Gate A2 and G-W-REALPAIR score receipts pass (W26 gate-table row). Why blocked: W07 (bridge); W05 (score surface).

**Acceptance criteria**

- [ ] Hosted tests over the ledger vectors: identical retry returns the original receipt; same id different payload → commandIdReuse; stale base → Conflicted; viewer → roleNotPermitted.
- [ ] A watch PointWon produces the same fold as the equivalent spec/fixtures scoring sequence (test).
- [ ] SIMPAIR: a point from the watch simulator lands on the phone simulator and returns Accepted; a forced stale base shows the conflict message.
- [ ] Real two-phone evidence is listed as waiting for Gate A2.
- [ ] Killing the phone app mid-command and relaunching reconciles the watch outbox to exactly one receipt for that commandId (hosted test with the fake session; acceptance-matrix row 3).

**Evidence required**

- Hosted test output
- SIMPAIR transcript

**Screens**

- design-reference/adaptive/screens/62-watchos-score.png

**Owned areas**

- `ios/Jovra/Platform/WatchBridge/Commands`
- `ios/JovraWatch/Features/Score/Outbox`

**User stories:** 6, 7, 8, 30, 31, 32, 34, 35, 36, 37, 38

**Gate:** G-W-SIMPAIR; A3b exit needs Gate A2 + G-W-REALPAIR (flagged until then)

## W17: Watch score commands on Android/Wear (A3b): PointWon and Undo with receipts, conflicts and offline chains through the phone

`score-commands-android` · watch · size M · labels `ready-for-agent`, `platform:android`, `track:watch`, `area:watch`

**Blocked by:** W10, W12

**What to build:** The Android counterpart of W16 through the Data Layer: ScoreCommandReconciler on the phone, abilities sheet narrowing, Wear outbox chains, conflict and expiry states. It ships A3b behind the same flag as W16; the A3b exit is 'not met' until Gate A2 and G-W-REALPAIR. Why blocked: W10 (phone projection and receipts); W12 (score surface).

**Acceptance criteria**

- [ ] JVM/Robolectric tests over the ledger vectors as in W16, through the fake Data Layer client.
- [ ] A watch PointWon produces the same fold as the equivalent scoring fixture sequence.
- [ ] Data Layer emulator evidence only after G-WEARPAIR; otherwise reported 'not run'.
- [ ] Killing the phone app mid-command reconciles the Wear outbox to exactly one receipt (Robolectric test with the fake client).
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/67-wearos-score.png

**Owned areas**

- `android/wear-bridge/commands/**`
- `android/wear/score/outbox/**`

**User stories:** 6, 7, 8, 30, 31, 32, 34, 35, 36, 37, 38

**Gate:** G-WEARPAIR + G-DISK; A3b exit needs Gate A2 + G-W-REALPAIR (flagged until then)

## W18: Connection alerts and haptics policy on iPhone and Apple Watch: deferral, dedupe, critical own-phone alerts and acknowledgement sync

`alerts-haptics-ios` · watch · size M · labels `ready-for-agent`, `platform:ios`, `track:watch`, `area:watch`

**Blocked by:** W07, W04

**What to build:** AlertPolicy (JovraRoom) on the iPhone produces `alerts[]`: a camera going Unknown is deferred until the next accepted point or 45 s and collapses with other deferred alerts into one haptic; one alert per camera per outage with the re-alert cap; auto-clear when heard again; critical (immediate) only for ownRecordingFailed and ownStorageCritical (< 5 min). Watch haptic patterns: none for routine updates, a short confirmation for Accepted, a distinct pattern for critical; a phone-side switch turns watch haptics off. ackAlert on the watch clears the same alert on the phone. No alert starts or stops any recording. Haptic feel is physical-watch evidence. Why blocked: W07; W04.

**Acceptance criteria**

- [ ] Hosted tests replay the alerts vectors (3 s raise, blip, never-recording camera, 4 s clear, the cap, 45 s deferral, collapse, acknowledgement, critical own-phone failure) and assert the alerts and haptic calls.
- [ ] A cameraUnknown alert never maps to the critical pattern (test).
- [ ] With watch haptics off, no haptic API is called (fake).
- [ ] XCUITest with performAccessibilityAudit on every -watchState state, VoiceOver labels in full words with ages, the largest Dynamic Type size without clipping, states shown by word and shape (not colour alone), Reduce Motion with no animated counters.

**Evidence required**

- Hosted test output
- SIMPAIR acknowledgement transcript

**Screens**

- design-reference/adaptive/screens/65-watchos-connection-alert.png

**Owned areas**

- `ios/Jovra/Platform/WatchBridge/Alerts`
- `ios/JovraWatch/Haptics`

**User stories:** 58, 60, 61, 63, 64, 65, 66, 67, 78, 79, 80, 81

**Gate:** G-W-REALPAIR (haptics)

## W19: Connection alerts and haptics policy on Android and Wear OS

`alerts-haptics-android` · watch · size M · labels `ready-for-agent`, `platform:android`, `track:watch`, `area:watch`

**Blocked by:** W10, W11

**What to build:** The Android counterpart of W18: AlertPolicy from :room-protocol on the phone, Wear vibration patterns (none routine, short confirmation, distinct critical), a phone-side switch, ackAlert round trip over MessageClient. Why blocked: W10 (phone-side alerts source); W11 (Wear shell).

**Acceptance criteria**

- [ ] Robolectric tests replay the alerts vectors and assert alerts and Vibrator calls.
- [ ] cameraUnknown never uses the critical pattern; haptics off → no Vibrator call.
- [ ] `df -h /` at ticket start (the ticket does not start below 8 GB free, and with at most two Android Gradle tickets, one emulator ticket and one iOS xcodebuild ticket running while free space is under 14 GiB) and again after `./gradlew -p android clean` at ticket end, both in the PR.

**Evidence required**

- Gradle test output (tasks, counts)
- CI run links

**Screens**

- design-reference/adaptive/screens/70-wearos-connection-alert.png

**Owned areas**

- `android/wear-bridge/alerts/**`
- `android/wear/haptics/**`

**User stories:** 58, 60, 61, 63, 64, 65, 66, 67, 78, 79, 80, 81

**Gate:** G-W-REALPAIR (haptics)

## W20: Own-phone stop from either watch (A3c): a confirmed bridge-local request that never travels as a room command

`own-phone-stop-both-watches` · watch · size M · labels `ready-for-agent`, `platform:shared`, `track:watch`, `area:watch`

**Blocked by:** W16, W17

**What to build:** stopOwnPhone as a jovra.room.watch-local/1 message on both platforms: confirmed on the watch, executed by the paired phone's own capture stop path, no target field (a watch can only stop its own phone); any watch capture request to the room is refused with surfaceNotPermitted; no automatic stop on disconnect (android-v1-spec story 317). Real foreground/permission behaviour on both OSes is recorded at the A2 gate. Why blocked: W16; W17 (command paths). Gate A2 governs only its device rows, so it is a gate, not an edge.

**Acceptance criteria**

- [ ] Unit tests on both platforms: stopOwnPhone stops only the local capture; a crafted room capture request from a watch is refused surfaceNotPermitted.
- [ ] Losing the bridge mid-recording does not stop anything (test).
- [ ] Device evidence on both OSes is attached after Gate A2 or reported 'not run'.

**Evidence required**

- Unit test outputs (Swift and Kotlin)
- Device evidence (after A2)

**Screens**

- design-reference/adaptive/screens/62-watchos-score.png
- design-reference/adaptive/screens/67-wearos-score.png

**Owned areas**

- `ios/Jovra/Platform/WatchBridge/Stop`
- `ios/JovraWatch/Features/Stop`
- `android/wear-bridge/stop/**`
- `android/wear/stop/**`

**User stories:** 10, 67

**Gate:** Gate A2 (device rows); G-W-REALPAIR

## W21: Room-fed watch bridge (A3a+room): both phones project the room aggregate, so either watch sees mixed-OS cameras

`room-fed-bridge-mixed-os` · watch · size M · labels `ready-for-agent`, `platform:shared`, `track:watch`, `area:watch`

**Blocked by:** W07, W10, A91, S72

**What to build:** Each phone's bridge projects its room view (roster, per-device rows with ageAtBridgeMs, host epoch, receipts) instead of its own capture; a Galaxy Watch sees an iPhone camera through its Android phone and an Apple Watch sees an Android camera through its iPhone; host lost → rows Unknown with the reason; a new host epoch replaces the old only after reconciliation. (android-v1-spec story 315.) G-W-REALPAIR with two phones of different OS. Why blocked: W07; W10 (bridges); A91 (Android real room); S72 (iOS director capture on a real room).

**Acceptance criteria**

- [ ] Loopback test on each platform: a two-device room projects both rows into the bridge snapshot with correct freshness.
- [ ] Host loss marks every row Unknown and raises hostLost (vectors).
- [ ] Physical mixed-OS evidence attached after the gate, otherwise 'not run'.

**Evidence required**

- Loopback outputs
- Device evidence (after gate)

**Screens**

- design-reference/adaptive/screens/61-watchos-camera-health.png
- design-reference/adaptive/screens/66-wearos-camera-health.png

**Owned areas**

- `ios/Jovra/Platform/WatchBridge/Room`
- `android/wear-bridge/room/**`

**User stories:** 3, 4, 5, 23, 72

**Gate:** Gate A2; G-W-REALPAIR; S68-S72 rescope decision (an iPhone on the S68 draft cannot interoperate)

## W22: Swift pane policy held to the shared pane-policy vectors (G-PANE iOS half), with StudioPaneLayout delegating to it

`ios-pane-policy-vectors` · ios-adaptive · size S · labels `ready-for-agent`, `platform:ios`, `track:ios-adaptive`, `area:adaptive`

**Blocked by:** A14, S15

**What to build:** A pure Swift PanePolicy computing panes and navigation from the scene's container size in points, height, text size and input mode (never userInterfaceIdiom), passing every vector in spec/adaptive/pane-policy.vectors.json from #filePath; StudioPaneLayout (S15) delegates to it in a one-line change reviewed by the Studio owner. iOS has no posture input (ADR-0025 §5): hinge vectors are asserted as not-applicable on iOS. Until F-IOS-ADAPTIVE closes (the iOS core and Studio screen owners adopt adaptive-screens §4.5), its output is labelled 'study, not adopted'. Why blocked: A14 (vectors); S15 (StudioPaneLayout).

**Acceptance criteria**

- [ ] Every non-posture vector passes in Swift; posture vectors are skipped with a listed reason, never silently.
- [ ] A grep finds no userInterfaceIdiom under the new code or StudioPaneLayout.
- [ ] S15's StudioPaneLayout tests still pass after delegation.
- [ ] The PR labels the result 'study, not adopted' while F-IOS-ADAPTIVE is open (link to the finding).

**Evidence required**

- swift/xcodebuild test output
- grep output

**Owned areas**

- `ios/Jovra/DesignSystem/Adaptive`
- `ios/JovraTests/Adaptive`
- `ios/Jovra/DesignSystem/Studio/StudioPaneLayout (one-line delegation; Studio-owner review)`

**Gate:** G-PANE (iOS); F-IOS-ADAPTIVE (claims)

## W23: Studio workspace at regular width (I71): one, two or three columns by window class with film, playhead and lesson preserved

`ios-studio-workspace-i71` · ios-adaptive · size L · labels `ready-for-agent`, `platform:ios`, `track:ios-adaptive`, `area:adaptive`

**Blocked by:** W22, S17, S21, S25

**What to build:** I71 on the generic adaptive path: at compact width Studio Home is ST21 unchanged; at Medium/Expanded width a two-column NavigationSplitView (Films | player) with the sidebar collapsing to a toolbar button; three columns (Films | player | lesson) only at width ≥ 1,200 pt with height ≥ 480 pt; height compact at most two; accessibility text sizes one fewer. Selected film, playhead (rational, restored paused) and lesson selection survive resize and terminate/relaunch through SceneStorage and the restored path. No hinge or crease code (ADR-0025 §5). Tested on iPad simulators as stand-ins (iPad mini A17 Pro, iPad Air 11-inch M4, iPad Pro 13-inch M5) in portrait, landscape, Split View widths and resizable windows; every foldable claim is labelled 'iPad stand-in'. It owns only the I71 container, selection and state preservation: S25's lesson pane and S21's player are reused as children, never re-implemented. An issue is filed on T61 so the core iPad review layouts delegate to W22's PanePolicy (core-owner review), keeping the G-PANE iOS half covering core too. Why blocked: W22; S17 (Studio Home); S21 (player); S25 (lessons).

**Acceptance criteria**

- [ ] XCUITest per window class shows the column count from PanePolicy (1 / 2 / 3) and one fewer at AX text sizes.
- [ ] Compact → expanded → compact resize keeps the selected film and lesson; terminate/relaunch restores them with the playhead paused at the saved time.
- [ ] VoiceOver order is sidebar → content → detail with headers; performAccessibilityAudit passes in light, dark and AX5.
- [ ] Screenshots paired with reference 71 with the documented deliberate differences and reviewer lines.
- [ ] A grep finds no userInterfaceIdiom and no hinge/crease symbols in the new code.
- [ ] The T61 delegation issue is linked; a grep shows no copy of S21's player or S25's lesson pane under the new folder.
- [ ] Layout claims are labelled 'study, not adopted' while F-IOS-ADAPTIVE is open.

**Evidence required**

- ui-test.sh -only-testing output with simulator ids
- Screenshots under evidence/ios/adaptive/W23/

**Screens**

- design-reference/adaptive/screens/71-ios-fold-studio.png

**Owned areas**

- `ios/Jovra/Features/Studio/Workspace`
- `ios/JovraUITests/Studio/Adaptive/I71`

**Gate:** iPad stand-in only (no foldable simulator); F-IOS-ADAPTIVE (claims)

## W24: Camera desk at regular width (I72): director capture with device rows and the paired-watch panel

`ios-camera-desk-i72` · ios-adaptive · size M · labels `ready-for-agent`, `platform:ios`, `track:ios-adaptive`, `area:adaptive`

**Blocked by:** W22, S19, W07, S72

**What to build:** I72: ST24 at regular width — preview upper area with device rows lower-start and the watch panel lower-end in portrait-square, preview start with rows and watch panel end in landscape; compact is ST24 portrait. The watch panel reads the WatchBridge status (none paired: hidden; app missing: 'Install JOVRA on your watch'; 'Last updated 2 s ago'; 'Not updated for 40 s' when stale) and opens the abilities sheet. Freshness wording per C-A1; 'Preview unavailable · not in this version' instead of stills (F-ROOM-STILL). Capture continuity across a fold is a hardware test, never promised. Lives in a sibling folder with one insertion line in the Director layout switch (Studio-owned edit, reviewed). Why blocked: W22; S19 (director capture demo); W07 (WatchBridge status); S72 (real director wiring edits the same Director folder, so the insertion follows it).

**Acceptance criteria**

- [ ] XCUITest on iPad stand-ins: landscape and portrait-square layouts match the I72 arrangement; compact shows ST24 portrait.
- [ ] Watch panel states render from injected bridge states with the exact copy.
- [ ] performAccessibilityAudit passes; the watch panel reads 'Paired watch, status and marks, last updated 2 seconds ago'.
- [ ] Screenshots paired with reference 72 with reviewer lines.

**Evidence required**

- ui-test.sh -only-testing output
- Screenshots under evidence/ios/adaptive/W24/

**Screens**

- design-reference/adaptive/screens/72-ios-fold-angle-desk.png

**Owned areas**

- `ios/Jovra/Features/Studio/DirectorRegular`
- `ios/JovraUITests/Studio/Adaptive/I72`
- `ios/Jovra/Features/Studio/Director (one insertion line in the layout switch; Studio-owner review)`

**Gate:** iPad stand-in; hardware for capture continuity; F-IOS-ADAPTIVE (claims)

## W25: iOS Studio preserved-state matrix: the adaptive-screens §4.5 test plan over every Studio row

`ios-studio-adaptive-state-matrix` · ios-adaptive · size L · labels `ready-for-agent`, `platform:ios`, `track:ios-adaptive`, `area:adaptive`

**Blocked by:** W23, W24, S34

**What to build:** For every Studio row of adaptive-screens §4.5 (ST21–ST40) on an iPhone 17-family simulator and an iPad simulator in Split View: (1) compact → expanded → compact by resizing, same selection, no network side effect; (2) rotate; (3) background, `xcrun simctl terminate`, relaunch: restored path, paused playhead at the saved rational time, drafts reloaded from disk, remote status Unknown; (4) largest accessibility text and VoiceOver; (5) no job, quote acceptance, score command, upload or invite sent twice. Failures are filed against the owning Studio tickets; F-IOS-ADAPTIVE stays open until the owners adopt the table. Why blocked: W23; W24; S34 (every Studio state reachable).

**Acceptance criteria**

- [ ] A matrix test enumerates every §4.5 Studio row × the five checks and reports pass/fail per simulator; the network trap records zero duplicate requests.
- [ ] Each failing row has a linked issue against its owning ticket.
- [ ] Evidence labels iPad runs as 'iPad stand-in' for any foldable statement.

**Evidence required**

- Matrix report
- ui-test.sh output
- Linked issues

**Screens**

- design-reference/adaptive/screens/71-ios-fold-studio.png
- design-reference/adaptive/screens/72-ios-fold-angle-desk.png

**Owned areas**

- `ios/JovraUITests/Studio/Adaptive/Matrix`
- `evidence/ios/adaptive/W25`

**Gate:** F-IOS-ADAPTIVE stays open until the owners adopt the table

## W26: Watch and iOS adaptive QA: simulator and Roborazzi evidence aggregated, references 61–72 side by side, and the gate registers

`watch-adaptive-qa` · watch · size L · labels `ready-for-agent`, `platform:shared`, `track:watch`, `area:qa`

**Blocked by:** W08, W13, W14, W15, W16, W17, W18, W19, W25

**What to build:** Aggregates: G-W-SIMUI (every -watchState on Ultra 3 49mm, Series 11 42mm, SE 3 40mm), G-W-WEARUI (Roborazzi on small round, XL round, rect; emulator only if G-WEARIMG passed), a side-by-side page pairing references 61–72 with our screenshots and a reviewer line each, the accessibility sweep, the acceptance-matrix rows of design-reference/adaptive/brief/acceptance-matrix.md mapped to fixtures and UI states, and the registers: UNVERIFIED (transferUserInfo, background delivery, suspension, Data Layer timing, haptics feel, battery, Galaxy Watch Ultra panel, foldable iPhone), the gate table with separate columns (contract, simulator UI, Wear UI, SIMPAIR, WEARPAIR-EMU, REALPAIR, field, metric). W20 and W21 are reported as waiting for Gate A2 if not done. The gate table has an A3b-exit row (W16/W17 flagged until Gate A2 and G-W-REALPAIR), an F-CORE-REVIEW row (watch stories 55 and 95 partial on iOS), and the register records that the latest-serve value state is fixture-only in v1: wiring it to the Serve Lab estimate is an explicit follow-up, never a live value. Why blocked: W14; W15; W16; W17; W18; W19; W25.

**Acceptance criteria**

- [ ] The side-by-side generator refuses to finish without a reviewer line for each of references 61–72.
- [ ] Every acceptance-matrix row maps to at least one fixture and one UI state or is listed as physical-only.
- [ ] No simulator or emulator result is reported as paired-transport or device evidence.
- [ ] The gate table carries the A3b-exit, F-CORE-REVIEW and latest-serve-fixture-only rows with their states.

**Evidence required**

- evidence/watch/W26/side-by-side.html
- Registers and gate table

**Screens**

- design-reference/adaptive/screens/61-watchos-camera-health.png
- design-reference/adaptive/screens/66-wearos-camera-health.png
- design-reference/adaptive/screens/71-ios-fold-studio.png
- design-reference/adaptive/screens/72-ios-fold-angle-desk.png

**Owned areas**

- `evidence/watch/W26`
- `docs/watch/release`

**User stories:** 82, 83, 84, 90, 92

**Gate:** G-W-REALPAIR, G-W-FIELD (registered, not run here)

