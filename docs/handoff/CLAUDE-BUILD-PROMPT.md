# JOVRA — Claude build prompt

Copy everything below into Claude in the project workspace. Attach the design-reference folder or make it available locally.

---

Build **JOVRA Tennis**, an original premium tennis recording, replay, analysis and practice application. Pronunciation: JOH-vrah. Use the selected Court Arc JV mark. Tagline: **See your game.** Start with iOS; plan Android portability after the iOS capture and analysis gates pass.

## Your role and outcome

Work as a product designer, mobile engineer and video-analysis engineer. Build a usable application from the supplied visual reference pack. The intended player wants to record a match or practice, revisit the exact moment that matters, understand trustworthy metrics, improve through actionable drills, and connect performance with their racket/string setup.

These references are design concepts. They are not evidence that an app, trained model, account integration or hardware feature exists. Inspect the current repository and preserve useful existing work. Do not overwrite an existing implementation blindly.

Read applicable AGENTS.md and installed skills. If available, inspect the user's existing **three @flywheel suite build** chat read-only to identify the actual Matt/Paul Cox ticket-specification and implementation skills. Do not invent those skill names or claim to have used them. Do not message or alter that chat. If unavailable, use a documented local ticket workflow and explicitly identify this substitution. Use mission-control for a multi-phase execution when installed; use flagship-report for a substantial assessment, obeying its routing rules. Respect existing repository custody and merge policies.

## Inputs and source of truth

Read:
- design-reference/brief/product-brief.md
- design-reference/brief/research.md
- design-reference/brief/screens.json
- design-reference/brief/brand-decision.md
- design-reference/brief/implementation-states.md
- design-reference/index.html
- design-reference/screens/ — 20 original raster screen references
- design-reference/logos/01-court-arc.png — selected logo
- design-reference/brief/image-prompts.json — reproducible generation brief

Use the screenshots to reproduce layout, visual rhythm, composition, palette and hierarchy. Use the written specifications for exact copy, navigation, calculations, permissions and behavior. Image generation can introduce small typography or court-diagram errors; never transcribe those errors into production. Recreate the chosen mark as a clean vector and build an iOS app-icon asset catalog rather than using a screenshot of the entire logo board.

Do not implement the app as twenty pictures, a gallery or a web page wrapped in a phone. Create real interactive native screens, real persistence, accessible controls and testable domain logic.

## Brand and interface

Palette: deep forest #092A25; forest panel #123C33; ivory #F4F1E8; charcoal #182F29; tennis chartreuse #D7F56A; warm clay #C47752 for selected flagged states. Use the native Apple system font, tabular metrics, an 8-point spacing system, generous margins, crisp line charts and purposeful court diagrams. Rounded cards around 22 points, with restrained shadows. Photography should feel like real tennis, not generic fitness stock or science fiction. Avoid gratuitous translucent cards, rainbow gradients and trophy dashboards.

Persistent navigation: **Home · Sessions · Record · Insights · Profile**. Focused capture, calibration, replay and comparison screens can hide tabs to give video and safety controls space. Build landscape replay and comparison adaptations even though the references are portrait. Support small iPhones, larger iPhones, iPad layouts where feasible, dark/light/system appearance, Dynamic Type, VoiceOver, increased contrast and reduced motion. Tap targets must be at least 44×44 points. Do not rely on color alone in charts, shot maps or statuses.

Use manufacturer names only as user-entered equipment labels. Do not imply sponsorship or copy protected logos. Gear inspiration includes Head Prestige, Wilson Pro Staff 85, Dunlop bags and Grand Prix balls, WeissCANNON strings, Solinco Hyper-G and Ghost Wire. Confirm exact product variant names during implementation where they affect functionality. Tensions and usage in the mockups are sample data, not the user's recorded settings.

## Twenty screen targets

1. Welcome — the brand, a clear start, native Apple sign-in option and optional demo.
2. Player onboarding — handedness, backhand, level and goals; editable later.
3. Home — next action, latest session, trends and safe recording entry.
4. Session setup — singles, doubles, serve/stroke practice; players, score format, gear and camera preset.
5. Court calibration — framing guides, stable placement and device readiness.
6. Live capture — persistent REC/timer, durable saving state, manual score, bookmark, stop and thermal state.
7. Import/processing — Photos, Files and optional Drive import; separate save, analysis and backup stages.
8. Session library — searchable/filterable sessions with local, archived and review states.
9. Match overview — score, reproducible stats, momentum and flagged events.
10. Smart replay — continuous full-video navigation, event filters, slow motion, frame stepping, point correction and clip export.
11. Shot placement — calibrated court, accessible marker legend, filters and manual correction.
12. Serve Lab — placement and serve statistics, video-linked feedback; estimated speed only after validation.
13. Stroke Lab — selected swings and optional 2D pose/path estimates with confidence and reviewed states.
14. Video comparison — two personal recordings, contact synchronization, annotations, voice notes and landscape mode.
15. Coaching/drills — each suggestion links to supporting clips or entered evidence; practical editable plans.
16. Progress — comparable-session trends, transparent denominators and editable goals.
17. Racket Vault — user-entered equipment, string setup and session associations.
18. String journal — mains/crosses, gauge, tensions, date, machine/method if desired, notes and usage.
19. Storage/backup — optional Drive connection, resumable queue, offline state, retry, verification, export and retention.
20. Settings — profile/authentication, camera/mic/Photos status, iOS Settings links, units, appearance, accessibility, export/deletion and help.

Implement auxiliary screens/sheets listed in implementation-states.md. Twenty references are the visual spine, not a reason to omit important flows.

## Architecture decision

Prefer **SwiftUI + AVFoundation + AVPlayer + Vision/Core ML where validated**, with local structured persistence and originals in the app's protected document storage. If this repository already has a capable React Native/Expo implementation, document the tradeoff before changing frameworks; advanced capture still needs actual native device support.

Define framework-independent domain schemas for players, sessions, score events, shots, calibration, annotations, equipment, strings and provider-independent archive manifests. This supports a later Kotlin/Jetpack Compose and CameraX Android implementation without compromising the iOS camera experience.

Save locally first. Google Drive is an optional user-owned archive; it is not the database or analysis engine. Use scoped OAuth, app-created/explicitly selected files, resumable uploads, retry/backoff, verified completion and versioned JSON sidecars. Store credentials in Keychain. Never send raw videos to an AI service by default. Explain any optional server-analysis destination, retention and cost before opt-in.

Begin with local/manual annotation and real playback. Evaluate on-device analysis using actual test footage. If server processing is necessary, use a private object-storage upload and a separate asynchronous worker, with expiring scoped access and a deletion policy. Choose a provider only after checking processing needs, region and costs. Never embed server secrets in the client. Preserve original footage until a verified export/backup and explicit retention rule allow removal.

## Honest analysis

Build a capability registry: manual, validated automatic, estimated, unsupported, needs review. Every metric must trace to source events/frames, method/model version, calibration and confidence. Do not generate random analytics and present them as detected results.

Treat automatic point segmentation, ball tracking, court mapping, serve speed, stroke classification and scoring as independent ML projects. Vision body-pose detection is a starting primitive, not a trained tennis coach. A single camera does not justify reliable spin RPM, exact 3D biomechanics, injury diagnosis or officiating-grade line calls. Defer unsupported claims.

Correcting a point winner must update all later scoreboard states, summaries and exports. Preserve the original model result and the user edit separately. Full-video scrubbing must remain available even for unrecognized events. Clearly show denominators; changing units must convert data, not relabel values.

Sample fixture: Jon beats Alex 6–4, 6–3; session length 54 minutes; 124 points with Jon winning 72; 40 first serves in out of 60 attempts; 28 of those 40 points won; 386 shots. Display 58%, 67%, 70% by documented rounding. The fixture is illustrative and must be validated as a coherent tennis event sequence before using it as a test oracle. The 104 mph speed in the reference is a labeled illustrative estimate.

## Durable recording and permissions

Request camera permission only on entering capture. Microphone is optional; denial must not block silent tennis recording. Use the system Photos picker to avoid unnecessary full-library access. Do not draw a fake system permission modal or promise to change iOS permissions inside the app.

Recording is a foreground task. Handle phone calls, interruptions, app backgrounding, thermal pressure, low storage, battery and camera errors. Flush recoverable segments and recover after relaunch. Never claim unlimited background camera capture. A sample 1080p/60 setting must be selected only when the actual camera supports it; estimate disk space from real preset/bitrate and remaining capacity.

## Build sequence and tickets

First write the product specification, domain model, capability ledger and architecture decisions. Turn them into tickets with: problem, user outcome, scope, dependencies, affected screens, acceptance criteria, meaningful tests and evidence requirements.

Execute in this order:
1. Design system, navigation, honest demo fixtures and local equipment/session records.
2. Reliable capture/import, local playback, recovery and metadata.
3. Manual scoring/annotations, full replay, correction and export.
4. Analysis feasibility benchmark with labeled footage; ship only passing capabilities.
5. Optional Google Drive archive and private evidence-linked practice recommendations.
6. Accessibility, resilience, performance and iOS simulator/device QA.
7. Android port and equivalent emulator/device QA after the iOS gates.

Create small reviewable PRs when a real authorized remote exists. Apply the user's established ticket/implementation workflow. Use auto-merge only where the repository's explicit authorization and branch protections permit it; required checks must pass. Never bypass a failing gate. Do not create a remote repository, enable billing, submit to stores or deploy a backend from this prompt alone without an established user-authorized destination. Continue all local, reversible implementation work while external credentials are unavailable, marking affected integrations unverified.

## Verification and completion

Run meaningful tests for the scoring state machine, tie-break/deuce rules, corrections, unit conversions, session/backup persistence, resumable failures and metric recomputation. Test export against original timecodes and missing/unsupported videos. Check contrast and VoiceOver/Dynamic Type by actual behavior.

Use the installed Xcode simulator for UI flows and imported prerecorded fixtures. A simulator cannot prove court capture, heat behavior, true camera frame rates, Apple Watch pairing or sustained recording. Run Android emulator checks only after an Android implementation exists. Record commands, simulator/device identifiers, test results, screenshots, analysis benchmark results and unresolved failures. Do not invent passing evidence.

When simulator gates pass, give a concise device-test checklist and stop that hardware gate for the user to connect the iPhone. Later request the Pixel for Android hardware verification. Test long real recordings, interruption recovery, heating, low storage, phone rotation and network loss on physical hardware. Keep simulator success, physical-device success, ML validation, signing, backend integration and App Store readiness separate.

Deliver the working source, durable mission/ticket state, a clear local run entrypoint, screenshot comparisons to all twenty references, and an evidence-backed status report. State exactly which features are implemented, validated, estimated, disabled or awaiting external configuration. The goal is a tennis application players can trust and enjoy.

