# Video analysis apps: competitive research for Stroke Lab, Serve Lab and Video Comparison

Researcher notes for JOVRA Tennis. Access date for every source: **2026-10-07**. Scope: tennis-relevant video
analysis and coaching apps (Onform, SevenSix, CoachNow, Hudl Technique, Coach's Eye, Dartfish, Kinovea, Spark Motion,
V1 Sports), lightweight frame-by-frame players, and the tennis-specific AI technique apps that appeared in 2025–2026.
SwingVision appears only for context, because it has its own research track.

**Labels.** `[OBS Sx]` means I saw it in source Sx (see `## Sources`). `[INF]` is my reasoning. `[UNV]` is unverified:
secondary, single-source or not checkable. Review evidence comes from user reports, not measured failure rates, and
each complaint carries its date and app version because older problems may have been fixed since.

**Method.** I used iTunes lookup and search JSON (US storefront) for listing facts. I pulled the App Store
customer-review RSS for every app that had text reviews (Onform 297 reviews across 6 pages, CoachNow 175, V1 Golf 250,
SlowMo 84, VisualEyes 26, plus small sets) and coded them by keyword. Feature mechanics come from official help
centers and docs (Onform KB, CoachNow help, Dartfish KB, Kinovea docs). Implementation constraints come from Apple
developer documentation. I inspected App Store screenshots visually (Onform, CoachNow, VisualEyes, SevenSix, TorqAI,
AI Tennis Swing Coach). I did no hands-on testing of any app.

**Review-sample caveat.** `[OBS S6]` Onform's text reviews average far below its 4.79 overall rating. By year: 2021
averages 2.62 (n=73), 2023 averages 4.32, and 2026 averages 3.62 (n=26). Most of the star mass comes from ratings
without text. Text reviews over-represent complaints, so read them as themes, not prevalence. Brand-new tennis AI
apps (TorqAI, AI Tennis Swing Coach, KineVision) show small, all-5-star review sets. `[INF]` Those sets are too small,
and possibly solicited, to signal quality.

---

## 0. Decision-relevant summary

1. **Frame-accurate scrubbing is the make-or-break interaction, and the market converged on a two-control
   model.** One control is an absolute timeline for jumping. The other is a relative jog strip or "frame scrubber"
   for single frames. Onform documents a "Macro Scrubber" plus a "Frame Scrubber" with one-frame step buttons and
   speeds from 2× to 1/8× `[OBS S20]`. CoachNow, VisualEyes and SlowMo use a ribbed jog strip under the video
   `[OBS S58, S4]`. The documented failures follow from that model:
   - the bottom-edge scrubber triggers the iOS app switcher (Onform 2023, SlowMo 2018 and 2023) `[OBS S6, S10]`;
   - an absolute bar cannot land precisely in a 240 fps video longer than about 1 minute (Onform 2022) `[OBS S6]`;
   - the two controls sit too close together, so a near-miss jumps the video (Onform 2022) `[OBS S6]`;
   - the jog "disengages" on finger lift and the app flips into drawing (Onform 2022) `[OBS S6]`.
2. **Draw mode vs. scrub is a real, documented conflict, and it is a mode-design bug, not a gesture bug.** The fix
   is an explicit, sticky Draw mode in which the jog strip still scrubs and lifting a finger never changes mode. On
   iPad, add a pencil-only drawing policy. Users also ask for editable line and angle endpoints and for drawings that
   persist reliably (V1 Golf 2026, Onform 2025, CoachView 2026) `[OBS S9, S6, S12]`. `[INF]` for the fix.
3. **Comparison sync is the most-praised feature and the most fragile one.**
   - Praised: Onform reviews call side-by-side and overlay sync a game changer for javelin, golf and baseball
     `[OBS S6]`.
   - Fragile: "very hit or miss" sync (Onform v4.1.4, 2025-07), "sync adjustment not working" (Onform v4.0.13,
     2025-05), compare freezing (VisualEyes v2.1.5, 2026-04), and no way to play one side alone to re-align
     (VisualEyes 2024-12) `[OBS S6, S11]`.
   - The best-documented model is Dartfish's. Each clip gets its own jog, scrub and nudge to the sync point, then
     "Done" locks the sync point and collapses to one set of controls `[OBS S30]`.
   - Kinovea adds time-origin sync, proportional speed linking across different capture frame rates, and a 50%
     superposition `[OBS S35]`.
4. **Voice-over is expected, and its feature set is now standard.** That set is screen plus mic or screen only,
   pause/resume, output written as a new file with the original untouched, a picture-in-picture face cam, and
   transcription (Onform v4.7.0, 2026-09-26) `[OBS S20, S16]`. Apple's `RPScreenRecorder` **cannot capture AVPlayer
   video** `[OBS S50]`. JOVRA must therefore record a voice-over as an event timeline (audio, playhead, rate,
   drawings) and render it with `AVMutableComposition` / `AVVideoCompositionCoreAnimationTool` `[OBS S51, S52]`
   rather than with ReplayKit. `[INF]`
5. **Pose overlays are now table stakes, and honesty about them is the differentiator.**
   - Apple Vision gives 2D bodies with 19 joints (iOS 14+) and 3D bodies with 17 joints (iOS 17+). Neither has
     racket, ball or hand-on-racket points `[OBS S53, S54]`.
   - Every tennis app that shows a racket path claims a custom model `[OBS S4]`.
   - ServeFix's 2026-10-07 release notes fix arms and hips appearing on the wrong side of the body at serve contact
     `[OBS S4]`. That is direct evidence that 2D pose fails exactly at the moment tennis cares about.
   - SevenSix reviewers report scores given for unrecognized swings (2024) `[OBS S7]`.
   - JOVRA's "2D pose estimate" label and "Review" statuses instead of scores (screens 12–13) are the right call.
6. **Business-model anger dominates the negative reviews more than feature gaps do.**
   - Onform: 28 of 43 one- and two-star reviews in 2021 were about price or paywall, and 11 of 26 in 2024–2026
     `[OBS S6]`.
   - A 2026-09 Onform review says the user cannot view their own videos after the subscription lapsed `[OBS S6]`.
   - Onform users complain about forced Google, Microsoft or Apple sign-in (2022, 2024, 2026) `[OBS S6]`.
   - V1 Golf users complain that even line drawing is paywalled (2026) `[OBS S9]`.
   - `[INF]` JOVRA should keep the core local review tools (scrub, draw, compare, voice note, export) free and
     unlimited on the user's own videos. Never hold originals hostage.
7. **Status facts the build must not get wrong.**
   - **Hudl Technique** is discontinued (2021). Its users were migrated to OnForm, whose founders include the
     original UberSense developer `[OBS S25]`. The old App Store id returns 404 `[OBS S59]`.
   - **Coach's Eye** (TechSmith) is retired. Competitor pages date it 31 March 2022 `[UNV S40, S41]`. A *different*
     developer (Gym Art Inc.) shipped a new app named "Coach's Eye" on 2026-03-26 (v1.1.0, 4.24 from 25 ratings)
     `[OBS S4]`.
   - **Kinovea** is alive: tag `2025.2`, repo pushed 2026-10-07, GPL-2.0, Windows `[OBS S37, S38]`.
   - **Spark Motion Pro** is low-activity (last update 2025-08-08, 14 ratings) `[OBS S4]`.
   - **V1 Pro** is legacy (last update 2023-07-24) and has been replaced by V1 Coach `[OBS S4]`.

---

## 1. Listing facts (US App Store, 2026-10-07)

| App (id) | Seller | Rating (count) | Price model | Version · last update | Status | Source |
|---|---|---|---|---|---|---|
| Onform (1490334045) | OnForm, Inc. | 4.79 (8,666) | Free download. Standard $9.99/mo, Premium $14.99/mo. Coach Basic $19.99, Standard $39.99, Pro $59.99/mo. Quarterly and yearly discounts. 14-day trial | 4.7.3 · 2026-10-06 ("minor fixes"); min iOS 18.6; 208.7 MB | Active, frequent updates | `[OBS S1, S16, S24]` |
| SevenSix (1505604446) | SevenSix AS (Norway) | 4.19 (68) | $14.99/mo, $149.99/yr (14-day trial). Pay-per-swing $1.99 (1), $3.99 (3), $4.99 (5) | 4.0.2 · 2026-10-07; min iOS 15.6; 78.4 MB | Active. AI Coach chat removed in 4.0.1 (Aug 6) | `[OBS S2, S17]` |
| CoachNow (596598472) | Golf Genius Mobile, LLC | 4.86 (13,023) | Analyze $9.99/mo or $59.99/yr; Plus $39.99/mo or $349.99/yr; PRO $49.99/mo or $499.99/yr; Analyze Athlete $29.99/yr (IAP). Web lists Academy $899/yr, 7-day trial, no free plan | 8.0 · 2026-09-21 (Liquid Glass redesign) | Active | `[OBS S4, S18, S28]` |
| SwingVision (989461317), context only | SwingVision, Inc. | 4.71 (4,928) | Pro $179.99/yr or $14.99/mo | 11.9.67 · 2026-09-27 | Active | `[OBS S3]` |
| myDartfish Express (1040982427) | Dartfish | 2.79 (29) | Annual subs: myDartfish Mobile from €7/mo; 360 €20/mo; Live S €80/mo; Pro S €180/mo (billed annually); 15-day trial | 11.0 · 2026-07-06 | Active, enterprise-oriented | `[OBS S4, S31]` |
| Kinovea (desktop) | Open source | n/a | Free, GPL-2.0 | Tag 2025.2; repo pushed 2026-10-07 | Active, Windows | `[OBS S37, S38]` |
| Spark Motion Pro (552652332) | Spark Motion Inc. | 4.14 (14) | Free app; account required; cloud tiers | 12.12.08 · 2025-08-08 | Low activity, clinical focus | `[OBS S4, S42]` |
| V1 Golf (349715369) | Interactive Frontiers | 4.08 (1,846) | Plus $9.99/mo, $79.99/yr; Advanced V1sion $14.99/mo or $119.99/yr | 5.15.0 · 2026-09-23 | Active (golf) | `[OBS S4, S19]` |
| V1 Coach (6476321492) | Interactive Frontiers | 4.69 (26) | Paid coach tiers | 5.14.0 · 2026-09-11 (first 2024-05-16) | Active; replaces V1 Pro | `[OBS S4]` |
| V1 Pro (506014662) | Interactive Frontiers | 3.11 (44) | n/a | 3.6.0 · 2023-07-24 | Legacy | `[OBS S4]` |
| Hudl Technique | Hudl | n/a | n/a | n/a | **Discontinued 2021**; id 470428362 returns 404 | `[OBS S25, S59]` |
| Coach's Eye (TechSmith) | TechSmith | n/a | was a one-time fee | n/a | **Retired**, reportedly 2022-03-31 | `[UNV S40, S41]` |
| "Coach's Eye" (6761056366) | Gym Art Inc. (unrelated new app) | 4.24 (25) | Free with 7 videos; Pro unlimited, 1-week trial | 1.1.0 · 2026-09-26 (first 2026-03-26) | New | `[OBS S4]` |
| VisualEyes (1643006248) | TM Athletics LLC | 4.78 (402) | Free core, cloud subscriptions | 2.3.3 · 2026-09-26 | Active; positioned as a Coach's Eye replacement | `[OBS S4, S11]` |
| KineVision (6752237075) | W. Mandrysz | 5.0 (18) | Free and ad-free; "Max" subscription | 1.9.0 · 2026-10-02 | New, active | `[OBS S4]` |
| SlowMo – Video Analysis (843274461) | Pico Brothers | 4.63 (1,674) | Free plus add-ons | 2.7.0 · 2026-05-02 | Active | `[OBS S4]` |
| CoachView (1662383024) | Firecracker Software | 4.55 (611) | Paid unlock (reviews say not a subscription) | 1.8.0 · 2026-07-14 | Active | `[OBS S4, S12]` |
| CMV Pro (737665687) | CoachMyVideo | 4.08 (51) | $6.99 | 5.0 · 2017-09-12 | Abandoned | `[OBS S4]` |
| TorqAI (6759643780) | Tornatto Labs | 5.0 (4) | 5 free analyses/mo; $5.99/mo; annual about 30% off | 4.2 · 2026-09-26 | New (2026-04) | `[OBS S4]` |
| AI Tennis Swing Coach (6776502111) | Y. Brei | 4.88 (8) | Free visual coach; Pro for AI write-ups | 2.5.2 · 2026-09-25 | New (2026-06) | `[OBS S4]` |
| ServeFix (6773094806) | V. Myslivecek | no ratings | First analysis free; Pro | 2.1 · 2026-10-07 | New (2026-06) | `[OBS S4]` |
| INTER TENNIS: 3D AI Analysis (6477877180) | Melilot Analytics SA | no ratings | Free download | 5.0.0 · 2026-10-06 | Active | `[OBS S4]` |
| Toach (6774433013) | yin song | 5.0 (6) | Free: first 5 min/match and 3 serve speeds per session; Pro trial 7 days | 1.9.2 · 2026-10-07 | New (2026-06) | `[OBS S4]` |
| TennisCut (6754323620) | A. Tellioglu | 4.08 (12) | Free with Pro | 2.0.0 · 2026-09-19 | New (2025-11) | `[OBS S4]` |

---

## 2. App profiles

### 2.1 Onform: the most complete mobile analysis tool and the closest analog for JOVRA's labs

**Core features**
- **Player.** `[OBS S20]` A Macro Scrubber ("slide the gold ball") covers the whole video. A Frame Scrubber (drag
  vertical lines) gives frame-precise navigation, with back and forward buttons that move exactly one frame.
  Speeds run from 2× to 1/8×. `[OBS S58]` Screenshots show the time readout with three decimals (e.g. "2.300"), a
  speed chip "1×", the transport row (frame back, play, frame forward) and a settings button. The scrubber row sits
  above the transport row, not on the screen edge.
- **Drawing.** `[OBS S20]` The pen icon opens 10 tools: line, arrow, degree measurement, angle, circle, box,
  freeform, timer, ruler, text. Line thickness is adjustable and colors are custom. `[OBS S58]` The tools sit in a
  vertical toolbar on the right edge with Undo and Clear.
- **Analysis tools.** `[OBS S21]` Skeleton Tracking (tap a joint for its angle, toggle inside or outside angle),
  Side-by-Side, Overlay, Drawing, Angles, Voiceover, Stopwatch, and Measure (calibrated against a known length).
- **Compare.** `[OBS S58]` Two videos stack vertically, each with its own index badge, and an "Unlink" button
  controls sync. Mirroring (flip) is available during voice-over `[OBS S20]`.
- **Voice-over.**
  - Modes: "Record Screen & Microphone" or "Record Screen Only". You can pause, resume and stop. The output is a
    brand-new video file and the original is untouched `[OBS S20]`.
  - You can swap the comparison video mid-recording, and **Coach Cam** embeds the coach's live video `[OBS S20]`.
  - Athletes are capped at 5 voice-overs/month (Standard) or 20 (Premium); coaches are unlimited `[OBS S20]`.
  - v4.7.0 (2026-09-26) added voice-over transcription `[OBS S16]`.
- **Pose and 3D.**
  - The skeleton needs an A15 Bionic or newer `[OBS S20]`. The listing says skeleton tracking needs iOS 18+
    `[OBS S16]`.
  - 3D is **golf full swings only**. It needs 120 or 240 fps, a face-on camera at hip height, and iPhone 14 or
    iPad Pro 2020 or newer. It runs offline after a model download `[OBS S22]`.
  - The developers claim results are "usually within just a few degrees" of motion capture `[OBS S22]`. The model
    card is a separate PDF, v2, updated 2026-04-13 `[OBS S23]`.
  - Tennis is not a supported 3D sport `[OBS S22]`.
- **Capture and organization.** Up to 240 fps; pause and resume recording; multi-angle Multi-Cam; auto-detect for
  golf and baseball; Bluetooth trigger; Apple Watch app; radar triggers `[OBS S1]`. Libraries are organized by
  athlete or team, with tags and titles, plus a Reference Content Library stored on device `[OBS S1, S20]`. A
  streaming player for long videos arrived in v4.4.1 `[OBS S16]`.

**Praised** `[OBS S6]`
- Side-by-side and overlay compare in sync against a "best practice" or pro clip (javelin coach, 2024-10; golf and
  baseball, many).
- Voice-over (frequent).
- Drawing tools and degree angles (track 2023-03, rowing 2024-10).
- Frame-by-frame review (2026-07).
- Chat and sharing as one place for coach and athlete.
- Responsive support.

**Recurring complaints** (newest first) `[OBS S6]`
- **2026.**
  - Videos half the time don't submit or don't save (v4.6.2, 2026-09-05).
  - "Updated and ruined" (v4.6.2).
  - Lapsed subscribers can't see their own saved videos; the $100/yr price is resented (v4.6.3, 2026-09-26).
  - Every feature is paywalled (2025-10, 2026-07).
  - Slow imports and phone storage bloat (2026-07).
  - Forced third-party login (2026-03).
- **2025.**
  - Compare sync "hit or miss," and the app crashes when phone storage fills mid-recording (v4.1.4).
  - Multicam clips out of sync; sync adjustment broken; drawings not saved (v4.0.13).
  - Uploads take a day (v4.1.0).
- **2024.**
  - Golf auto-detect fills the library with practice swings (v3.2.3).
  - No export to camera roll (v3.2.3).
  - Trial billing confusion (v3.4.1).
- **2023.**
  - The scrub bar overlaps the iPhone app-switch swipe (v3.0.1).
  - Thumbnails render black (v3.0.1).
- **2022.**
  - **Flywheel** (v2.01.3, 2022-03-24): lifting the finger disengages the flywheel and engages drawing, and the
    flywheel must be "recaptured." The reviewer says it was a downgrade from Hudl.
  - The scroll bar and flywheel sit too close together (v2.01.3).
  - New scrubbing in v2.01.9 (2022-11): 240 fps needs many cross-screen swipes, and the bottom bar is imprecise past
    1 minute.
  - Vertical imports loaded sideways (2022-08).
  - A 10 GB cache leak (2022-04).
  - Record buried under the Library (2022-03).
- **2021 (Hudl migration wave).** The free tier fell from unlimited (Hudl) to 10 videos. Prices were $5/mo for
  athletes and about $30/mo for coaches. Migrations failed, and videos were auto-cropped to Onform's aspect ratio.

**Freshness check.**
- `[OBS S58]` The current screenshots show a floating red record button inside the Library and a scrubber row above
  the transport buttons.
- `[OBS S16]` v4.3.6–4.4.3 notes mention scrubbing performance on older devices.
- `[INF]` The 2022 navigation and edge-scrub complaints have likely been addressed. The pricing, upload and
  sync-reliability complaints persist into 2025–2026.

### 2.2 CoachNow: a communication-first coaching platform with a solid analysis kit

- **Features.** `[OBS S4]` AI Skeleton Tracking (joint angles), Voice Overs and CoachCam, side-by-side
  comparisons, Live MultiCam, slow motion to 240 fps, draw and annotate with angles, shapes and timers, and a cloud
  library. The app also offers Spaces, Groups, Smart Lists, templates and auto posts, and read receipts.
- **Versus mode.** `[OBS S26]` (updated 2023-10-13)
  - Tap "V|S" in the analysis kit and pick the second clip from the camera roll or the library.
  - Each video scrubs independently until you **tap the link icon** to scrub both at once.
  - Telestration and voice-over can be added to both clips. Landscape shows them side by side.
- **Observed UI.** `[OBS S58]`
  - A ribbed jog strip runs under the video with frame-step buttons, loop and "1x".
  - A vertical tool rail on the right holds arrow, line, angle, curve, circle, rectangle, stopwatch and text.
  - Voice-over shows a top bar (close, pause, red stop, elapsed time, V|S toggle) and a picture-in-picture coach
    cam.
  - Versus mode stacks vertically, with **two independent jog strips and a link icon between them**.
  - MultiCam shows a 4-up grid with 60/120/240 FPS chips.
  - The splash shows "CoachNow by Golf Genius."
- **v8.0 (2026-09-21).** The 13-year-old capture button became a "+". Press and hold it to start recording; the
  action is configurable in Settings `[OBS S18]`.
- **Ownership.** The seller is "Golf Genius Mobile, LLC" `[OBS S4]`. Golf Genius reportedly acquired Shotzoom
  (Golfshot and CoachNow) in February 2024 `[UNV, search snippet only]`.
- **Praised.** Draw plus voice in one pass (physical therapy, 2019); remote lessons; the AI skeleton and CoachCam
  (2024-09); a tennis instructor using the web app (2024-01) `[OBS S8]`.
- **Complaints.** `[OBS S8]`
  - Uploads and visibility between coach and athlete (2026-02).
  - Videos slow to load in-app (2025-08).
  - "If working don't update" (2025-07).
  - Can't save annotated videos (2025-05).
  - Re-crop on upload (2025-06).
  - Apple Watch camera control lost after watchOS 26 (2025-09).
  - No easy 30-second rewind or slow-motion segment for new users (2021).
  - Phantom lines in the finished product (2019).
  - Insufficient fps (2025-03).

### 2.3 SevenSix: the only incumbent tennis-specific AI stroke coach, with a weak execution record

- **Positioning.** `[OBS S2]` Computer vision, biomechanics and AI analyze swing path, kinetic chain, timing, ball
  impact point, movement efficiency and consistency. It promises comparison with professional players and
  "unlimited cloud video storage" (Premium). Setup is a tripod or a friend filming.
- **Version history.** `[OBS S17]`
  - 3.0.0 (2022-07-04): analysis under 5 seconds on 3G or better.
  - 3.1.0 (2022-10-27): recordings up to 1 minute, detecting up to 5 swings.
  - 3.3.7 (2024-09-18): Stickman Overlay with joint angles.
  - 4.0.0 (2026-06-02): AI Coach Assistant, graphs, injury-prevention insights, drills.
  - **4.0.1 (2026-08-06): AI Coach removed** "as we focus on bug fixes".
  - `[INF]` The store shows the 4.0.x dates without a year ("Jun 2", "Aug 6"). The year 2026 is inferred: the
    reviews still cite v3.3.7 as of 2025-10-12, and the store shows full dates only for earlier years.
  - 4.0.2 (2026-10-07): 7 languages, redesigned Score and Details screen in plain words, Facebook login removed.
- **Screenshots** `[OBS S58]` look dated (iPhone X frames, "App of the Day," an AI award from 2020). They show swing
  curves for "pro curve" vs. "your curve," 0–100 scores for swing curve, timing and impact point, and a landscape
  framing box with a Record button.
- **Complaints** `[OBS S7]` (11 text reviews, 2022–2025).
  - Analysis stuck at "analyzing" for days (2023-11, 2024-06, 2024-12, 2025-10).
  - The camera fails on the second trial and the front camera isn't supported (2025-04).
  - The AI errors and deletes the video (2024-10).
  - A score of 81 for a swing the app didn't recognize (2024-06).
  - The screen sleeps during recording, so the clip captured the player walking back (2023-09).
- **Praise.** Concept quality only (2022-09, 2024-05).
- `[INF]` For JOVRA, SevenSix proves demand for focused stroke feedback. It also shows the cost of cloud-dependent
  analysis without visible status or recovery, and of scores without confidence gating.

### 2.4 Hudl Technique (status: discontinued)

- **Lineage.** `[OBS S25]` UberSense became Hudl Technique. In 2021 users received in-app notices that backend
  storage would disappear "later this year." Partners Gear Fisher and Krishna Ramachandran (the original UberSense
  developer) took over the user base with OnForm. OnForm's migration tool imported the past year of videos by
  default; a single coach account cost US $299/yr.
- **Store status.** `[OBS S59]` App Store id 470428362 (attributed to Hudl Technique by justuseapp, `[UNV]` mapping)
  returns 0 lookup results and HTTP 404. Hudl's old support URL redirects with `ref=support_sunset` to a 404 page.
- **What users missed.** `[OBS S6]` Unlimited free local videos, simplicity, organization by tags and people
  (figure skating, 2021), a positioning outline for framing the golfer (2022), loop playback (2021), and the timer
  zero reset (a physics teacher, 2021).
- `[INF]` The lessons for JOVRA: a simple local-first tool earns loyalty, and migration with pricing shock destroys
  it.

### 2.5 Coach's Eye (status: retired) and its successors

- **Retirement.** TechSmith's Coach's Eye (slow motion, frame scrubbing, drawing, side-by-side, voice-over, all
  for a one-time fee) was retired. Apps were pulled and cloud accounts closed. Competitor pages date this
  2022-03-31 `[UNV S40, S41]`, and I found no TechSmith primary page. Users still grieve it in 2023–2026 reviews
  `[OBS S6, S11, S15]`.
- **What they miss most.** Screen-recording while drawing **and** doing voice-over in one pass (VisualEyes 2023-01).
  On-screen timers and splits (VisualEyes 2023-04 and 2023-05) `[OBS S11]`.
- **Successor apps** `[OBS S4, S11, S15]`
  - **VisualEyes** (4.78, 402). Tick-strip scrubbing with a time bubble, side-by-side or overlay compare with a
    link icon, voice-overs, and tags plus athletes.
    - v2.3.3 (2026-09-26) made uploads resume "exactly where the server left off." It fixed compare-screen stutter
      on resize and large-library sync `[OBS S4]`.
    - Asks: pencil-only drawing on iPad (2026-09), a compare freeze (2026-04), a way to play one side of a compare
      to re-sync (2024-12), angle tool and timer (2023) `[OBS S11]`.
  - **KineVision** (5.0, 18). Versus Mode (side-by-side synced), stopwatches between any two frames (works in split
    view), skeleton with joint angles and joint tracking, shutter and ISO camera controls, Reference tags, Google
    Drive sharing. An "AI Coach Assistant" runs on Apple Intelligence devices. Reviews call it a cheaper Onform
    alternative `[OBS S4, S15]`.
  - **Gym Art "Coach's Eye"** (new, 2026). Frame stepping, pinch zoom, protractor, object and pixel erasers,
    undo/redo, color labels, resume where you left off. The only text review (2026-09) calls it underwhelming next
    to the old app `[OBS S4, S15]`.

### 2.6 Dartfish: the elite reference for workflows, but heavy for consumers

- **Plans** `[OBS S31]` (all billed annually, 15-day trial)
  - myDartfish Mobile (from €7/mo): drawings, slow motion, zoom, angle and time measurement, voice notes on iOS,
    tagging panels.
  - 360 (€20/mo): 4K, overlays, compositing, multi-video, 3D drawings, 50 GB.
  - Live S (€80/mo): live tagging, split-screen.
  - **Pro S (€180/mo): SimulCam and StroMotion**, automatic tracking and trajectories.
- **Express app.** `[OBS S4]` Frame-by-frame and slow motion, side-by-side, drawings and labels, angles and times,
  voice and text notes, stills sharing (break the motion into still shots shared without the video), voice-overs,
  iPhone/iPad sync, and delayed-replay "Mobile Plus" (capture on one device, review live on a second).
- **Compare workflow** `[OBS S30]` (myDartfish 360, modified 2025-05-07)
  - Open a video, click Compare, and drag in a second video.
  - Use each video's own **jog, scrub and nudge** to reach the comparable moment.
  - Click **Done to lock the sync point** and get a single set of controls; zoom and position for the best view.
- **Blend vs. SimulCam.** `[OBS S32, S33]` Blend mode overlays two videos to show subtle differences. SimulCam (Pro
  only) matches background pixels so the blend holds through camera pans and zooms, and it "cannot be used" if the
  backgrounds can't be matched (no cross-venue use).
- **Tennis footprint.** `[OBS S4]` Dartfish builds white-label channel apps for federations, including USTA.TV
  ("key position technology," frame-accurate forward and backward playback, drawings with text) and Tennis Canada
  HP TV.
- **Reviews** `[OBS S13]` 15 reviews, 2015–2023: clinics and biomechanics programs love it. Students groan at the
  learning curve, and there are expensive-support complaints. A tennis coach values timing ball and foot speed in
  serve drills (2022).

### 2.7 Kinovea: the open-source desktop gold standard for precision workflows

- **Status.** `[OBS S37, S38]` Free and open source (GPL-2.0), with a Windows installer `Kinovea-2025.2.0.exe`.
  Tags run 2023.1 → 2024.1.0 → 2025.1.0/2025.1.1 → 2025.2. The repo was pushed 2026-10-07.
- **Navigation.** `[OBS S36]` Frame-by-frame stepping. Time shows as frame number, milliseconds or timecode.
  Time-scale adjustment maps high-speed footage to real time. Key images carry rich-text comments.
- **Annotation and measurement.** `[OBS S36]`
  - Lines, arrows, curves, paths, markers, angle, goniometer, human posture model, chronometer, spotlight and
    magnifier.
  - Subpixel measurement with grid or perspective calibration and lens-distortion compensation.
  - Point tracking with kinematics and CSV export.
  - Annotations save as KVA XML files: vector-based and editable.
- **Comparison.** `[OBS S35]`
  - "Two playback screens."
  - Sync works by marking a **time origin** at a common event in each video ("Mark current time as time origin"),
    or with "Synchronize videos on the current frames." A joint timeline drives both.
  - **Linked speed sliders** keep slow motion proportional across different capture frame rates; this can be
    unlinked in preferences. Capture rate is configured via "Configure video timing."
  - **Superposition** blends both videos at 50% and only makes sense with an identical static camera.
  - The two clips may start or end at different times relative to the sync point.
  - Exports render synchronized composite frames `[OBS S36]`.
- `[INF]` Kinovea's model is the cleanest mental model for JOVRA. Each clip owns a time origin (the event), and
  playback is expressed relative to it.

### 2.8 Spark Motion: a clinical and sports-performance tool

- **Features.** `[OBS S4]` iPad-first; postural grid and bullseye; goniometer; line and measurement tools; super
  slow motion; frame-by-frame at 30 or 120 FPS; a screen-recorder voice-over for virtual assessments; 2 GB HIPAA
  cloud (up to 30 GB). An account is required.
- **Status.** `[OBS S42]` The site now advertises "Spark Pro Markerless Analysis." A testimonial in the listing
  comes from the University of Georgia men's tennis head coach `[OBS S4]`.
- **Reviews** `[OBS S14]` (2012–2020): loved by physical therapy clinics. Complaints are login walls and a paid
  standalone app converted to a cloud subscription (2017, 2020).

### 2.9 V1 Sports: golf-first, with useful sync and lesson workflows

- **V1 Golf.** `[OBS S4, S19]` Frame-by-frame up to 240 fps, side-by-side or overlay, drawing tools, Skeletal
  Tracking, Ball Tracing without radar, a pro model-swing library, ground-pressure sensor integration, and remote
  coaching memberships.
- **V1 Pro / V1 Coach** `[OBS S4]` Voice-over-video lessons with telestration, comparison and overlay. V1 Pro
  advertised "Flip videos to show right or left handed view."
- **Sync.** V1's own marketing describes comparison "with sync points at address, top, and impact" `[OBS S40]`,
  which is a competitor's page.
- **Complaints** `[OBS S9]` (2024–2026, 250 reviews).
  - Paywall on basic drawing at $10/mo (2026-05).
  - Upsell pop-ups before you can press play (2026-04).
  - Lines can't be saved and can only be deleted by double-tap in reverse order (v4.17.1, 2026-01).
  - Crash on signup on iPhone 16 Pro (2025-07).
  - Subscription and cancel friction (2024–2026).
- **Positive reviews.** Many praise named support agents. `[INF]` That pattern suggests solicited reviews, so treat
  the 2025–2026 average uplift with caution.

### 2.10 Lightweight frame-by-frame players (simple and well loved)

| App | What it does well | Complaints relevant to JOVRA | Source |
|---|---|---|---|
| SlowMo – Video Analysis | "Scrub wheel gives you total control over playback speed"; telestration; voice-overs; linked side-by-side | Bottom scroll bar triggers the app switcher (2018-12, 2023-03); asks for a reversed wheel direction to match editors (2018-11, 2018-04); asks for pinch zoom (2017–2023) and adjustable lines after placement (2018, 2022); render lost if the phone sleeps (2024-01); recorded scrubs cut off and no mic toggle (2025-02); crash while drawing (2026-03); arrows stay for the whole clip instead of appearing in time (2016) | `[OBS S4, S10]` |
| CoachView | Speeds 1/10, 1/4, 1/2, 3/4, 1×, 1.5×, 2×; **bookmarks/annotations that jump between key moments**; pose view toggle; recorded breakdowns; v1.8.0 long-press anywhere to fast-forward or rewind; Mac keyboard shortcuts | Can't move line or angle endpoints (2026-01); asks for an overlay mode in compare (2025-10); export confusion (2023–2026); long videos won't play (2025-01) | `[OBS S4, S12]` |
| CMV Pro (abandoned 2017) | Capture in "high bit rate iFrame modes for more responsive playback/video scrubbing"; flip a righty into a lefty | Not updated since 2017 | `[OBS S4]` |
| TickScrubo (2026) | Drag the timeline to scrub, and **drag vertically to switch between fast navigation and single-frame precision**; A–B loop; 0.25×–2×; pinch and pan; rotate 90° | New, 1 rating | `[OBS S4]` |
| Coach Video Analysis | Sync and compare side-by-side or overlay; **kinogram export** (choose frames, arrange them in a row or column, save as one image); clip a moment with or without markups | 3.6 from 10 ratings | `[OBS S4]` |
| CoachLens | "Enable/disable drawing mode" as an explicit toggle; link videos in side-by-side; FaceCam overlay; angle tool | Compare is iPad-only | `[OBS S4]` |
| BitBody | 14 body points; angles update as you scroll; charts of joint angles over time; trajectories of body points | 5 ratings | `[OBS S4]` |

### 2.11 Tennis-specific AI technique apps (2025–2026 wave)

All new and small. Listing claims are marketing, and none publish validation data that I could find. `[UNV]` for
accuracy.

| App | Technique-relevant claims and UX | Notes | Source |
|---|---|---|---|
| **TorqAI** | Film up to 60 min; auto-detects every shot; "Add a missed shot manually from a visual timeline"; 17 joints tracked and "reconstructed in 3D"; racket trail, kinetic chain, racket drop, contact point; level estimate "calibrated to the NTRP scale" labeled "Rough estimate"; Form Lab trends; export clips with skeleton overlay; auto-crop vertical reels. Screenshots show a frame counter "24/61," a 0.5× speed chip, a joint-label legend (Left/Right/Center/Trail), trim start and end with ± nudges, and Analyze / Save Clip | 17 joints matches Apple's 3D joint set `[INF]`; whether it uses Vision is `[UNV]` | `[OBS S4, S58]` |
| **AI Tennis Swing Coach** | On-device custom racket detection (Core ML); real-time skeleton with joint angles and spoken cues; fault callouts ("Late contact"); racket path in white vs. a "pro ideal" in yellow; slow motion, frame-by-frame, A–B loop, **zoom with auto-follow**; PDF practice reports; per-player profiles. Screenshot shows the disclaimer that results can be wrong, scores and levels are app estimates, and nothing is medical advice | Good honesty pattern | `[OBS S4, S58]` |
| **ServeFix** | Serve only. Record or upload 3–15 s, standing side-on with the full body visible. Checks toss placement at trophy, elbow height in trophy, hip rotation through contact, contact height and extension, knee bend, stance angle. On-device, no account. Free tier gives the #1 fix plus one strength | 2.1 notes (2026-10-07): the skeleton now keeps "arms and hips… on the correct side of your body at contact" and the head visible through the finish | `[OBS S4]` |
| **INTER TENNIS** | Claims single-video 3D tracking of racket, player and ball; camera beside the net at 1–2 m pointing down the court; AR overlays; v5.0.0 "Diagnose and Fix" **groups shots with the same technical fault** | No ratings | `[OBS S4]` |
| **Toach** | Whole-match rally cuts, serve speed without radar, "Coach Tina" live naming of swings; checks unit turn, takeback, timing, shoulder coil, contact point, follow-through | 1.9.2 fixes: a bump no longer loses the court lock | `[OBS S4]` |
| **TennisCut** | On-device rally detection; a two-phone remote (camera plus controller showing camera battery and storage); 4K/60; "Coach Eye" frame stepping free for everyone | Reviews: rally clips start too early and end 1–2 s short (2026-06); detection unreliable on other footage (2026-08) | `[OBS S4, S15]` |
| SmartHit / NiceShot / CedarX / TennisForm / Tennis AI | Rally auto-cut, ball trails, landing mini-maps, pose overlay vs. pro demos, key-frame comparisons with pros, scores of 0–100 | Tiny or no rating counts | `[OBS S4]` |
| Legacy and adjacent | Zepp Tennis Classic (sensor, last update 2017). Tennis Plus (Apple Watch swing detection with "video playback synced swing recognitions," $9.99). Tennis Coach Plus HD (feedback as a new video **or a PDF coach report with key images**, 2022). Smashpoint 3.4 (second iPhone at the fence; critical-point replays at ½×, ¼× and frame-by-frame) | | `[OBS S4]` |

---

## 3. Cross-app synthesis: what players and coaches praise

1. **Side-by-side and overlay against your own past self or a model**, in sync. This is the single most frequent
   praise theme in Onform (19 positive keyword hits) and V1 Golf reviews `[OBS S6, S9]`.
2. **Voice-over on the analyzed clip.** This is how coaches deliver feedback, together with drawing (Onform, CoachNow,
   SlowMo, Dartfish) `[OBS S6, S8, S10, S13]`.
3. **Frame-by-frame plus slow motion as the core loop.** "Clearest frame by frame" is the top compliment for SlowMo
   and KineVision `[OBS S10, S15]`.
4. **Simple drawing tools: line, circle, angle with degrees, timers.** Degree readouts are praised for release
   angles (Onform 2023) `[OBS S6]`.
5. **Organization** by athlete, tags and a reference library (Onform, VisualEyes, KineVision, CoachNow)
   `[OBS S1, S4]`.
6. **Instant review on court**, with no transfer step `[OBS S6]`.
7. **Free or one-time-priced core tools.** CoachView is praised as "not a subscription model." VisualEyes and
   KineVision win users with free cores `[OBS S12, S11, S15]`.

## 4. Recurring complaints (cross-app), with freshness

| Theme | Evidence (newest first) | Fresh in 2025–2026? |
|---|---|---|
| Paywall and price shock; lapsed users locked out of their own videos | Onform 2026-09 (lockout), 2025-10, 2021 wave; V1 Golf 2026-04/05; Spark Motion 2017 | **Yes** `[OBS S6, S9, S14]` |
| Upload, save and submit unreliability; drawings or annotated videos not saved | Onform 2026-09, 2025-05/06; CoachNow 2025-05; V1 Golf 2026-01; SlowMo 2024-01; VisualEyes 2023 | **Yes** `[OBS S6, S8, S9, S10, S11]` |
| Compare sync unreliable or awkward | Onform 2025-05/07; VisualEyes 2026-04, 2024-12 | **Yes** `[OBS S6, S11]` |
| Scrubber conflicts with the iOS bottom-edge gesture | SlowMo 2023-03, 2018-12; Onform 2023-09 | Probably fixed at Onform `[INF]`; unknown elsewhere `[OBS S6, S10]` |
| Draw vs. scrub mode confusion; lines not editable after placement | Onform 2022-03; CoachView 2026-01; SlowMo 2022, 2018 | **Yes** (editability) `[OBS S6, S12, S10]` |
| Storage bloat and crashes when storage is full | Onform 2026-07, 2025-07, 2022-04 | **Yes** `[OBS S6]` |
| Forced third-party sign-in and privacy concerns | Onform 2026-03, 2024-10, 2022-02 | **Yes** `[OBS S6]` |
| Orientation and aspect handling (auto-crop, sideways imports) | Onform 2021–2023; SlowMo 2015, 2021 | Older `[OBS S6, S10]` |
| AI analysis stuck, wrong, or scoring non-swings | SevenSix 2023–2025; TennisCut 2026 (cut boundaries) | **Yes** `[OBS S7, S15]` |
| Recording reliability (screen sleeps, camera fails on retry, auto-detect misses the swing start) | SevenSix 2023-09, 2025-04; Onform 2021, 2024 | **Yes** `[OBS S7, S6]` |
| Discoverability: no manual, confusing navigation | Onform 2021–2024; CoachNow 2019–2023; Dartfish 2023 | Mixed `[OBS S6, S8, S13]` |

---

## 5. Deep dives

### 5.1 Frame-accurate scrubbing UX

**What exists (observed patterns)**
- **Two-control model.** An absolute bar for coarse navigation plus a relative frame control for fine moves.
  Onform has the Macro Scrubber plus the Frame Scrubber `[OBS S20]`. CoachNow and VisualEyes have a jog strip with a
  time bubble `[OBS S58]`.
- **Precision by vertical drag.** In TickScrubo, a vertical drag switches between fast navigation and single-frame
  precision `[OBS S4]`.
- **Long-press anywhere** to fast-forward or rewind (CoachView 1.8.0) `[OBS S4]`.
- **Time readouts.** Onform shows seconds to three decimals, and TorqAI shows a frame index "24/61" `[OBS S58]`.
  Kinovea offers frame number, milliseconds or timecode `[OBS S36]`.
- **Bookmarks and key moments** to jump between (CoachView; Kinovea key images; USTA.TV/Dartfish key positions;
  V1 sync points; Swing Replay pause positions) `[OBS S4, S36, S40]`.

**Failure modes to design out** `[OBS S6, S10]`
1. The bottom-edge control collides with the home-indicator swipe.
2. An absolute bar is imprecise for long, high-fps clips.
3. Coarse and fine controls sit too close together.
4. The jog loses "engagement" on finger lift and the user must "recapture" it.
5. Scrub direction contradicts editor conventions (film strip).
6. No zoom while stepping.

**iOS implementation facts**
- `AVPlayer.seek(to:toleranceBefore:toleranceAfter:completionHandler:)` with zero tolerances gives sample-accurate
  seeks "may incur additional decoding delay." A new seek immediately finishes the prior one with
  `finished == false` `[OBS S44]`.
- Apple's QA1820 pattern prevents seek pile-ups: keep a `chaseTime` plus `isSeekInProgress`, issue the next seek
  only from the completion handler, and use zero tolerance for accuracy `[OBS S43]`.
- `AVPlayerItem.step(byCount:)` moves by a number of steps sized by the enabled tracks. `canStepForward` and
  `canStepBackward` are fixed once the item is ready `[OBS S45, S46]`.
- `AVAssetImageGenerator` with `requestedTimeToleranceBefore/After = .zero` gives frame-accurate thumbnails (again
  with decode delay) `[OBS S47]`.
- `preferredScreenEdgesDeferringSystemGestures` (iOS 11+) lets an immersive view controller's gestures take
  precedence over system edge gestures `[OBS S48]`.
- Photos: `PHVideoRequestOptionsVersion.original` returns the asset "without adjustments" `[OBS S56]`. `[INF]` For
  Slo-mo clips from Photos, request `.original` to analyze the true high-fps timeline rather than the rendered
  slow-motion ramp. Verify on device.
- CMV advertised capture in "iFrame modes for more responsive playback/video scrubbing" `[OBS S4]`. `[INF]` Long-GOP
  HEVC at 240 fps makes *backward* stepping expensive. Short lab clips (3–15 s, as ServeFix uses) can get an
  all-intra or short-GOP **analysis proxy** generated once, keeping the original untouched. Benchmark first.

**JOVRA scrubbing spec (proposal)** `[INF]`
- **Three tiers**, consistent across Smart Replay (#10), Stroke Lab (#13), Serve Lab (#12) and Compare (#14):
  1. **Event timeline** (absolute). Rally, point or stroke markers; tap a marker to jump to it.
  2. **Jog strip** (relative, frame-quantized). One tick per frame. A selection haptic fires per frame. Drag left
     to advance (film-strip metaphor), with a Settings toggle to invert. Gain is velocity-sensitive, and a
     vertical drag-down drops into single-frame precision (TickScrubo pattern). It engages on touch-down with no
     dwell, and lifting a finger never changes mode.
  3. **Step buttons** at ±1 frame, press-and-hold auto-repeat at about 8 fps, accelerating to about 30 fps.
- **Layout.** Keep the jog strip at least 44 pt tall, with a clear gap of at least 16 pt from the event timeline.
  Place it above the transport row, never on the bottom edge. On analysis screens also defer bottom-edge system
  gestures.
- **Readout.** Always show `f 412 / 1,440 · 1.717 s · 240 fps` (frame, time, capture rate). Make it tappable to
  enter a frame or time, with a zero/origin reset: the Hudl Technique timer reset that a 2021 reviewer missed
  `[OBS S6]`.
- **Speeds.** 1/8×, 1/4×, 1/2×, 1×, plus A–B loop. Long-press anywhere for temporary 2× fast-forward or rewind
  (CoachView).
- **Zoom and pan.** Pinch at any time. Optional **auto-follow** crop on the player's bounding box (AI Tennis Swing
  Coach), which matters for behind-baseline footage.
- **Key moments.** Named bookmarks (Ready, Unit turn, Racket drop, Contact, Finish; for the serve: Toss release,
  Trophy, Racket drop, Contact, Landing). They render as the freeze-frame thumbnail row on screen #13.
- **Engine.** QA1820 chase-seek with zero tolerance while jogging, `step(byCount:)` for the buttons, and a proxy for
  reverse-heavy clips. Test seek latency on the oldest supported device.
- **Accessibility.** Expose the jog strip as an adjustable element (VoiceOver increment and decrement step one
  frame). On iPad, support hardware keys (←/→ for a frame, ⇧←/⇧→ for 10 frames, space to play). Kinovea and
  CoachView both ship keyboard control `[OBS S36, S4]`.

### 5.2 Draw mode vs. scrub conflict

- **Evidence.** `[OBS S6]` The Onform 2022 reviewer: lifting a finger made the flywheel disengage and "the drawing
  button engages." Another reviewer asked for the bar and flywheel to be moved apart. CoachLens markets an explicit
  "Enable/disable drawing mode" `[OBS S4]`. KineVision Max sells "Auto hiding tools during editing" `[OBS S4]`.
  VisualEyes users want an Apple Pencil-only drawing mode (wrist rejection) on iPad `[OBS S11]`. CoachView, SlowMo
  and V1 Golf users want lines and angles that can be adjusted and saved `[OBS S12, S10, S9]`. SlowMo 2016 wanted
  arrows that appear in time rather than for the whole clip `[OBS S10]`.
- **Apple facts.** `PKCanvasView.drawingPolicy` offers `.default`, `.anyInput` and `.pencilOnly` (iOS 14+)
  `[OBS S49]`.
- **JOVRA rules (proposal)** `[INF]`
  1. **Review mode** (default). One finger on the video pans when zoomed, two fingers pinch, and a double tap toggles
     fit or fill. No drawing.
  2. **Draw mode** is entered only with the Draw button (screen #14 already has "Draw"). It is sticky until Done and
     shows a persistent tinted state with the tool rail. In Draw mode the video surface draws, and **the jog strip
     and step buttons keep working** so the user can draw, step, draw. Lifting a finger never exits Draw.
  3. On iPad with a Pencil connected, default to `.pencilOnly`: the Pencil draws and the finger scrubs or pans in
     either mode.
  4. Every shape is an editable object with endpoint and vertex handles, move, delete, recolor and undo/redo. Use
     an object eraser, not only "clear all."
  5. **Annotation lifetime.** Each shape attaches to a frame range (default: from the current frame to +12 frames,
     with "hold until end" as an option). It fades in and out on playback (the Kinovea key-image model). Shapes
     persist locally in a sidecar document and autosave on every change. Never lose drawings.
  6. Hide the transport chrome while a stroke is in progress (KineVision pattern) and restore it on lift.
  7. Ship a minimal tool set first: line, arrow, circle, angle (with a "2D on-screen angle" caption), freehand,
     text, stopwatch (time between two frames), and a spotlight or magnifier.

### 5.3 Comparison and sync

- **Observed models**
  - **Lock-step after manual alignment.** Dartfish: per-clip jog, scrub and nudge, then "Done" locks the sync point
    into one set of controls `[OBS S30]`. CoachNow: independent scrubbing until the link icon is tapped
    `[OBS S26]`. Onform: a "Unlink" control in a stacked compare `[OBS S58]`.
  - **Time origin per clip.** Kinovea: "Mark current time as time origin" or "Synchronize videos on the current
    frames," with linked speed across frame rates and 50% superposition `[OBS S35]`.
  - **Named-phase sync points.** V1 (address, top, impact) `[OBS S40]`; Swing Replay ("automatically sync'd"
    comparison plus pause positions) `[OBS S4]`.
  - **Background-matched overlay** (SimulCam). It requires matching backgrounds and is pro-tier only `[OBS S32]`.
- **Failure evidence** `[OBS S6, S11]` Sync "hit or miss," clips drifting out of sync (Onform 2025-07); sync
  adjustment broken (Onform 2025-05); the compare screen freezes when picking a video (VisualEyes 2026-04); no way to
  play one side to re-align (VisualEyes 2024-12). VisualEyes 2.3.3 fixed compare stutter on resize `[OBS S4]`.
- **JOVRA compare spec (proposal)** `[INF]`, matching screen #14 ("Sync at contact," 0.25×, Draw, Voice note):
  1. **Model.** Each clip stores `syncEventTime` (in its own media timeline) plus `captureFPS`. The shared playhead
     is a *relative time* τ from the sync event. Clip time = `syncEventTime + τ × rateScale`. Never sync by frame
     index, because clips can be 60 fps and 240 fps.
  2. **States.**
     - **Align.** The UI shows "Unlocked" in amber. Each clip has its own jog strip and step buttons; the active
       clip is highlighted.
     - **Lock.** A link icon shows "Synced at Contact." One jog strip moves both clips, and the readout shows each
       clip's frame plus the offset.
     - **Nudge.** In Lock, a ±1-frame nudge on one clip re-aligns without unlocking (Dartfish "nudge").
  3. **Sync event chips.** Contact (default for strokes and serves), Trophy, Toss release, Racket drop, Split step,
     plus a "Custom" event. Auto-suggest the contact frame from (a) the audio transient of ball impact and (b) a
     wrist-speed peak from pose. Always show the suggestion as "Suggested · confirm," and allow a one-tap override.
     Both detectors are hypotheses that need a labeled-footage gate (see the brief's feasibility gate).
  4. **Optional two-anchor phase mode** (advanced). Align both Trophy and Contact by time-warping segment lengths,
     labeled "Phase-normalized (not real time)". It answers "is my racket drop late relative to contact?" without
     tempo differences masking it. Keep real-time as the default.
  5. **Ends.** When one clip runs out, hold its last frame dimmed (Kinovea notes clips start and end at different
     times).
  6. **Layouts.** Stacked in portrait (screen #14; Onform, CoachNow and VisualEyes do the same) and side by side in
     landscape. **Overlay** adds an opacity slider (default 50%), a scale/translate/rotate alignment gesture on the
     top clip, mirror (left/right-hander, as in V1 Pro and CMV), and a warning that overlay needs similar camera
     positions (Kinovea; Dartfish SimulCam constraint).
  7. **Comparison sources.** Your own clips first (screen #14 badge "Your recordings"). Do not ship pro footage or
     likeness without rights (the brief already bans unauthorized professional likeness). Competitors' "compare to
     pros" libraries (V1, SevenSix, NiceShot, CedarX) are a licensing question, not a UX one `[INF]`.
  8. **Save comparison** as a lightweight project: the two clip references, sync events, offset, drawings and voice
     notes, re-openable and exportable as a rendered video. Never duplicate the originals.

### 5.4 Voice-over

- **Observed feature bar**
  - Onform: screen plus mic or screen only; pause, resume and stop; a new file with the original preserved; Coach
    Cam picture-in-picture; mirror and swap the compare clip mid-recording; transcription (v4.7.0) `[OBS S20, S16]`.
  - CoachNow: voice over and CoachCam, a recording bar with pause and stop and elapsed time `[OBS S4, S58]`.
  - Dartfish: voice notes and voice-overs, plus stills-with-notes sharing without sending the whole video `[OBS S4]`.
  - Tennis Coach Plus HD: feedback as a new video **or** as a PDF report with key images `[OBS S4]`.
- **Complaints**
  - Onform: athlete voice-over quotas felt stingy (5/month, 2023) `[OBS S6]`.
  - SlowMo: no mic toggle, and recorded scrubs come out truncated (2025-02) `[OBS S10]`.
  - SlowMo: renders lost when the phone sleeps (2024-01) `[OBS S10]`.
  - VisualEyes: cannot draw and voice-over in the same recording (2023-01) `[OBS S11]`.
  - Onform: audio never recorded (2023-02) `[OBS S6]`.
- **Apple constraints**
  - ReplayKit's `RPScreenRecorder` "can't record video from AVPlayer" `[OBS S50]`.
  - `AVVideoCompositionCoreAnimationTool` renders Core Animation layers on the video timeline. It requires
    `AVCoreAnimationBeginTimeAtZero` and `isRemovedOnCompletion = false` `[OBS S51]`.
  - `AVMutableVideoComposition` supports per-source transforms, opacity and crop ramps, or a custom compositor
    `[OBS S52]`.
- **JOVRA voice-over design (proposal)** `[INF]`
  1. **Two weights.**
     - **Voice note** (screen #14 button): a short audio clip pinned to a frame or sync event. It appears as a pin
       on the timeline, needs no render, and is instant to make and replay.
     - **Voice-over review**: a full narrated walkthrough exported as a video.
  2. **Record a timeline, not the screen.** Capture mic audio through `AVAudioRecorder` or the audio engine plus a
     time-stamped event log: playhead time, rate, pause, step, zoom and pan transform, drawing add/edit/remove,
     compare lock, offset and layout. Review it live in-app with no render. Export with `AVMutableComposition`
     (video segments time-mapped to the log, freeze frames for pauses) plus Core Animation overlays for drawings
     and an optional face-cam track. This sidesteps the ReplayKit limitation, keeps renders deterministic and
     resumable, and lets the user re-record one segment without redoing the whole take.
  3. **Controls.** Mic on/off ("silent walkthrough"), pause and resume, re-record from here, optional front-camera
     PiP (Coach Cam equivalent), captions from on-device speech recognition (screen #10 already has a captions icon).
     Captions need validation; `[UNV]` which speech API to use.
  4. **Durability.** Autosave the event log continuously. Export in the background with resume after interruption.
     Never discard a take because the device slept. Keep the original video untouched.
  5. **No quotas** on voice notes or voice-overs of the user's own videos.

### 5.5 Pose and skeleton overlays and angle tools: keep it honest

- **Apple facts**
  - `VNDetectHumanBodyPoseRequest` (iOS 14+) gives 19 joints: nose, eyes, ears, neck, shoulders, elbows, wrists,
    root, hips, knees, ankles `[OBS S53]`.
  - `DetectHumanBodyPoseRequest` is the Swift API (iOS 18+) `[OBS S55]`.
  - `VNDetectHumanBodyPose3DRequest` (iOS 17+) gives 17 joints (topHead, centerHead, center/left/right shoulder,
    elbows, wrists, hips, knees, ankles, root, spine) in 3D relative to the camera. It uses `AVDepthData` when
    available `[OBS S54]`.
  - The Apple 3D sample needs an A12 or later and an image with all limbs visible `[OBS S54]`.
  - No API covers the racket or ball.
- **Market facts**
  - Onform's skeleton needs an A15 or newer, and its 3D needs 120/240 fps and is golf-only `[OBS S20, S22]`.
  - Tennis AI apps claim custom racket models (AI Tennis Swing Coach "custom-trained AI racket detection"; TorqAI
    racket trail; SevenSix swing curve) `[OBS S4]`.
  - The ServeFix 2.1 fix proves left/right limb confusion at serve contact is real `[OBS S4]`.
  - SevenSix scored an unrecognized swing (2024) `[OBS S7]`.
  - TorqAI labels its NTRP level a "Rough estimate" `[OBS S58]`.
  - AI Tennis Swing Coach shows a can-be-wrong and not-medical disclaimer `[OBS S58]`.
- **JOVRA rules (proposal)** `[INF]`
  - Draw only joints whose confidence passes a threshold. Fade the rest and never interpolate fake joints.
  - Enforce temporal left/right consistency and offer a one-tap "swap sides" correction.
  - Label the overlay "2D pose estimate" (screen #13).
  - Angles from pose or the manual tool are shown as **on-screen 2D angles** whose meaning depends on camera angle.
    Show no decimals and no biomechanical norms.
  - No level, NTRP or score claims until a labeled benchmark exists. The "Review" statuses on #13 implement that.
  - Gate capture for technique: side-on full body for strokes and serves (ServeFix), separate from behind-baseline
    match capture. Setup (#4) should ask the purpose, because match tracking and technique want different camera
    positions (INTER TENNIS uses net-side at 1–2 m) `[OBS S4]`.
  - Racket path, ball contact point and racket-face analysis need a custom model plus their own feasibility gate.
    Do not imply them from Vision.

---

## 6. What JOVRA should adopt, by screen

### Smart replay controls (#10, shared by every player surface)
- Keep "0.5×, frame back, play, frame forward, captions." Add the jog strip from §5.1 between the event timeline and
  the transport row, plus the frame/time/fps readout. `[INF]`
- Event markers stay tappable, and "Edit point" correction stays one tap away. Smart replay adds the pattern TorqAI
  uses for strokes: add a missed stroke manually from the timeline `[OBS S4]`. `[INF]`

### Stroke Lab (#13)
- Auto-clip strokes from a session with **padded boundaries** (default −1.0 s / +1.0 s) and frame-nudge trim handles.
  TennisCut users complain cuts start early and end 1–2 s short; TorqAI shows ± trim nudges `[OBS S15, S58]`.
  `[INF]` for defaults.
- The freeze-frame thumbnail row = named key moments (Ready, Unit turn, Racket drop, **Contact**, Finish). Tap to
  jump. Each is user-correctable, and moving it re-anchors the comparisons. `[INF]`
- The rows "Contact timing / Follow-through / Balance" with a "Review" status, each linking to the exact frames
  that justify it (evidence-linked, matching #15's "Watch evidence"). `[INF]`
- **Group strokes by observed pattern.** "Show me the 5 swings where contact was latest" is the same idea as INTER
  TENNIS's "Diagnose and Fix" grouping `[OBS S4]` and drives the "Compare contact position across 5 swings" focus
  card. `[INF]`
- **Multi-swing contact strip.** Export a kinogram-style strip of the Contact frames across swings: a single image
  for sharing, as in Coach Video Analysis, Kinovea and Dartfish StroMotion `[OBS S4, S36, S31]`. `[INF]`
- Mirror toggle for left-handers and the one-handed vs. two-handed backhand profile (#2). `[INF]`

### Serve Lab (#12)
- Serve phase markers: Toss release, Trophy, Racket drop, Contact, Landing. Expose a **toss-to-contact timer**
  (stopwatch between two frames, a feature users missed from Coach's Eye `[OBS S11]`). It directly supports the
  "Build a repeatable toss" focus. `[INF]`
- **Toss consistency overlay.** Overlay the last N serves at the Trophy or toss-peak frame (opacity stack, same
  camera) to show toss-position scatter. This is an onion-skin use of §5.3 overlay that needs no AI beyond the
  user-confirmed toss-peak frame. `[INF]`
- **Serve strip export.** Six phase frames rendered as one image (StroMotion-lite) `[INF]`.
- Speed numbers stay "Estimated," with the calibration caveat already on #12. Speed is out of scope for this
  research track.

### Video Comparison (#14)
- Implement §5.3. Align (independent jogs) → Lock "Sync at contact" → single jog with per-clip frame readouts and
  ±1-frame nudge. Stacked portrait, side-by-side landscape, overlay with opacity, alignment and mirror. `[INF]`
- "Draw" follows §5.2. Drawings can attach to either clip or to the shared frame. `[INF]`
- "Voice note" follows §5.4 (pinned audio). Add "Record walkthrough" for full voice-over export. `[INF]`
- "Save comparison" = a project file (references plus sync plus annotations) with no duplicate video. Export renders
  on demand. `[INF]`
- Mixed frame rates are supported by time-based sync. Show each clip's fps badge (Kinovea linked-speed model)
  `[OBS S35]`.

### Library, capture and business model (supporting the labs)
- **Record must be globally reachable.** Onform 2022 buried Record under the Library; its current build floats it;
  CoachNow 8.0 uses press-and-hold "+" `[OBS S6, S58, S18]`.
- **Keep the screen awake** during capture with `isIdleTimerDisabled` scoped to capture `[OBS S57]`. That fixes the
  SevenSix 2023 failure `[OBS S7]`. **Re-arm the camera reliably on a second take** (SevenSix 2025) `[OBS S7]`.
  Pre-flight storage and refuse to start with an insufficient-space warning (Onform crash when storage is full;
  SwingVision added a low-storage warning in 11.9.67) `[OBS S6, S3]`.
- Respect orientation and `preferredTransform`. Never auto-crop imports. Allow manual 90° rotation (Onform 2021–2022,
  TickScrubo) `[OBS S6, S4]`. `[INF]`
- **Export to Photos and Files** is a first-class action; Onform users asked for it in 2024 `[OBS S6]`.
- **Resumable backups.** Uploads resume from the server offset (VisualEyes 2.3.3 pattern) `[OBS S4]`, consistent with
  the brief's Google Drive resumable-upload plan.
- **Accounts and pricing.**
  - Local use works without an account; Sign in with Apple is optional. Avoid forced Google/Microsoft login
    (Onform complaints) `[OBS S6]`. `[INF]`
  - Core review tools are free and unlimited on local videos.
  - Never block viewing or exporting the user's own videos after a subscription lapses `[OBS S6]`. `[INF]`
  - Charge for things that cost money to run (cloud, heavy AI) and say plainly what is free. SevenSix's
    pay-per-swing ($1.99/1) and TorqAI's 5 free analyses/month show low-commitment entry points `[OBS S17, S4]`.
- **Discoverability.** In-context, first-run hints for the jog strip, Draw and Lock sync, plus a short help page.
  Onform, CoachNow and Dartfish reviewers repeatedly ask for a manual `[OBS S6, S8, S13]`. `[INF]`

---

## 7. Verification of the prior brief (`design-reference/brief/research.md`)

| Prior claim | Check | Result |
|---|---|---|
| Onform 4.8/5, about 8.7K ratings | iTunes lookup: 4.786, 8,666 `[OBS S1]` | **Confirmed** |
| SevenSix 4.2/5, 68 ratings | 4.191, 68 `[OBS S2]` | **Confirmed** |
| SwingVision 4.7, about 4.9K | 4.706, 4,928 `[OBS S3]` | **Confirmed** |
| A 2022 Onform review cites confusing capture navigation and a scrubber/drawing conflict | Review 2022-03-24, v2.01.3: Record buried under the Library; flywheel disengages and drawing engages `[OBS S6]` | **Confirmed**. Additional 2022 and 2023 scrub complaints exist (bar and flywheel too close; 240 fps imprecision; edge swipe). The current UI appears changed `[OBS S58]` |
| SevenSix 4.0.1 removed the AI assistant; the live listing shows 4.0.2 | 4.0.0 (2026-06-02) added the AI Coach Assistant; **4.0.1 (2026-08-06) removed it**; 4.0.2 released 2026-10-07 `[OBS S17, S2]` | **Confirmed**, with dates |
| SevenSix camera retry trouble (2025); stalled analysis, lost capture (older) | 2025-04-20 v3.3.7 camera on second trial; stalled "analyzing" 2023-11 → 2025-10 `[OBS S7]` | **Confirmed**. The stall complaint recurs as late as 2025-10-12 |
| Onform is multi-sport, not an automatic tennis match tracker | Listing and KB: coaching platform; 3D golf-only `[OBS S1, S22]` | **Confirmed** |

New beyond the prior brief: the Hudl Technique and Coach's Eye status, CoachNow, Dartfish, Kinovea, V1, Spark Motion,
the 2026 tennis AI wave, current prices, Apple API constraints (ReplayKit cannot record AVPlayer; seek and step APIs;
Vision joint sets; PencilKit pencil-only), and the scrub, draw, compare and voice-over specs.

## 8. Open questions and unverified items

- `[UNV]` The exact Coach's Eye retirement date (31 March 2022) comes only from competitor pages (V1 Sports,
  Coachway). I found no TechSmith primary source; the Wayback Machine and BJSM fetches were blocked.
- `[UNV]` The Golf Genius acquisition of Shotzoom/CoachNow (Feb 2024) comes from a search snippet. Only the "Golf
  Genius" seller and branding are observed.
- `[UNV]` Accuracy of every tennis AI app's pose, racket and 3D claims. No published validation was found.
- `[INF → needs device test]` Seek and step latency on 240 fps HEVC, especially backward stepping, on the oldest
  supported iPhone. Whether an all-intra proxy is needed. Whether Photos `.original` returns the raw 240 fps
  timeline for Slo-mo clips.
- `[INF → needs labeled footage]` Auto-sync on the contact frame from the audio impact transient and/or the
  wrist-speed peak, with its error in frames at 60 and 240 fps, indoor vs. outdoor, singles vs. doubles noise.
- `[INF]` Whether a two-anchor phase-normalized compare mode confuses recreational players. Prototype it before
  committing.
- `[UNV]` Which on-device speech API JOVRA should use for voice-over captions. Not researched here.
- Not covered: the Android equivalents of these competitors (Onform and CoachNow have Android apps per their KBs)
  and the Android APIs for frame-accurate seek. Needed before the Android port.

## Sources

All accessed 2026-10-07.

- **S1** Onform iTunes lookup: https://itunes.apple.com/lookup?id=1490334045&country=us. Rating 4.786 (8,666),
  v4.7.3 2026-10-06, min iOS 18.6, size, description, pricing, features.
- **S2** SevenSix iTunes lookup: https://itunes.apple.com/lookup?id=1505604446&country=us. Rating 4.191 (68), v4.0.2
  2026-10-07, release notes, description.
- **S3** SwingVision iTunes lookup: https://itunes.apple.com/lookup?id=989461317&country=us. Rating 4.706 (4,928),
  v11.9.67 notes (low-storage warning, recording stability), Pro price.
- **S4** iTunes batch lookup and search: https://itunes.apple.com/lookup?id=596598472,6761056366,1040982427,552652332,349715369,6476321492,506014662,843274461,1662383024,1643006248,412223222,1054851741,714031170,737665687,6754323620,6774433013,6759643780,6477877180,6758722710,6773094806,6776502111,6774777838,6751442505,1621474922,6752237075,1578921026,1098174650,6766645081,6497227261,6740051429,6769370968,1398461342,6464197714,1610405844,6456571603,1613170747,516298485,1345799441&country=us
  plus https://itunes.apple.com/search?term=<term>&entity=software&country=us&limit=50 for terms: video analysis,
  coach's eye, hudl technique, dartfish, coachnow, spark motion, v1 sports, tennis swing analysis, tennis serve
  analysis, tennis ai coach, slow motion video analysis, kinovea, tennis coach. Supports the listing facts,
  descriptions and release notes for all apps in §1–2 not covered by S1–S3.
- **S6** Onform reviews RSS, pages 1–6: https://itunes.apple.com/us/rss/customerreviews/page=1/id=1490334045/sortby=mostrecent/json
  (297 reviews, 2020-03 → 2026-09). Praise and complaint themes, scrubbing, flywheel, sync, pricing and storage
  complaints, yearly averages.
- **S7** SevenSix reviews RSS: https://itunes.apple.com/us/rss/customerreviews/page=1/id=1505604446/sortby=mostrecent/json
  (11 reviews, 2022-09 → 2025-10). Stalled analysis, camera retry, screen sleep, scoring a non-swing.
- **S8** CoachNow reviews RSS, pages 1–4: https://itunes.apple.com/us/rss/customerreviews/page=1/id=596598472/sortby=mostrecent/json
  (175 reviews). Praise and complaints.
- **S9** V1 Golf reviews RSS, pages 1–5: https://itunes.apple.com/us/rss/customerreviews/page=1/id=349715369/sortby=mostrecent/json
  (250 reviews, 2024-07 → 2026-10). Paywall, drawing persistence, side-by-side praise.
- **S10** SlowMo reviews RSS: https://itunes.apple.com/us/rss/customerreviews/page=1/id=843274461/sortby=mostrecent/json
  (84 reviews). Edge-swipe conflict, wheel direction, zoom, editable lines, render loss.
- **S11** VisualEyes reviews RSS: https://itunes.apple.com/us/rss/customerreviews/page=1/id=1643006248/sortby=mostrecent/json
  (26 reviews). Coach's Eye replacement, compare freeze, pencil-only request, timer and angle requests.
- **S12** CoachView reviews RSS: https://itunes.apple.com/us/rss/customerreviews/page=1/id=1662383024/sortby=mostrecent/json.
  Line and angle endpoint editing, overlay request, export.
- **S13** myDartfish Express reviews RSS: https://itunes.apple.com/us/rss/customerreviews/page=1/id=1040982427/sortby=mostrecent/json.
  Clinic praise, learning curve, tennis drill timing.
- **S14** Spark Motion Pro reviews RSS: https://itunes.apple.com/us/rss/customerreviews/page=1/id=552652332/sortby=mostrecent/json.
  Clinical praise, subscription conversion complaints.
- **S15** Small review sets via the same RSS pattern for ids 6752237075 (KineVision), 6754323620 (TennisCut), 6761056366
  (Gym Art Coach's Eye), 6759643780 (TorqAI), 6776502111 (AI Tennis Swing Coach), 6476321492 (V1 Coach).
  TennisCut cut-boundary complaints, KineVision as an Onform alternative, Coach's Eye successor sentiment.
- **S16** Onform App Store page and version history: https://apps.apple.com/us/app/onform-video-analysis-app/id1490334045.
  IAP prices; v4.7.0 voice-over transcription; v4.4.1 streaming player; scrubbing performance notes.
- **S17** SevenSix App Store page and version history: https://apps.apple.com/us/app/sevensix-tennis-ai-coach/id1505604446.
  IAP ($14.99/mo, $149.99/yr, pay-per-swing); 4.0.0 / 4.0.1 / 3.3.7 / 3.1.0 / 3.0.0 notes.
- **S18** CoachNow App Store page: https://apps.apple.com/us/app/coachnow-sports-coaching-app/id596598472. IAP prices,
  v8.0 notes.
- **S19** V1 Golf App Store page: https://apps.apple.com/us/app/v1-golf-golf-swing-analyzer/id349715369. IAP prices.
- **S20** Onform KB user guide: https://support.onform.com/article/153-user-guide-onform-video-analysis-app. Macro and
  Frame Scrubber, 2×–1/8×, 10 drawing tools, voice-over modes and limits, Coach Cam, A15 requirement.
- **S21** Onform KB analysis tools: https://support.onform.com/article/116-analysis-tools. Tool list.
- **S22** Onform KB 3D FAQ: https://support.onform.com/article/177-3d-faqs. Golf-only 3D, 120/240 fps, device and
  offline requirements, accuracy claim.
- **S23** Onform KB model card: https://support.onform.com/article/179-model-card. Model card PDF v2, 2026-04-13.
- **S24** Onform home: https://www.onform.com. 14-day trial without card, feature overview, KB link.
- **S25** Glenn Paulley, "Moving to OnForm from Hudl Technique" (2021-08-24):
  https://glennpaulley.ca/curling/2021/08/24/moving-to-onform-from-hudl-technique/. Hudl Technique sunset, OnForm
  founders, migration, $299/yr.
- **S26** CoachNow help, Versus Mode (updated 2023-10-13): https://help.coachnow.io/en/articles/6745767-versus-mode.
  V|S entry, link-icon sync, telestration and voice-over in compare.
- **S27** CoachNow blog, foundational video features (2022-06-16): https://coachnow.com/blog/foundational-video-features.
  240 fps in-app, voice-over, V|S, annotation.
- **S28** CoachNow pricing: https://coachnow.com/pricing. Plan prices, 7-day trial, no free plan.
- **S30** Dartfish KB, compare videos in split screen (modified 2025-05-07):
  https://support.dartfish.tv/support/solutions/articles/27000047295-compare-videos-in-split-screen. Jog, scrub,
  nudge, then Done to lock sync.
- **S31** Dartfish plans: https://www.dartfish.com/plans. Plan prices and features (SimulCam and StroMotion in Pro S).
- **S32** Dartfish KB, SimulCam (modified 2024-09-04):
  https://support.dartfish.tv/en/support/solutions/articles/27000048152-comparison-using-simulcam. Background-matching
  requirement.
- **S33** Dartfish KB, blended comparison (modified 2024-09-04):
  https://support.dartfish.tv/en/support/solutions/articles/27000048151-blended-comparison-video-overlay-. Blend vs.
  SimulCam.
- **S34** Dartfish home: https://www.dartfish.com/. Product lineup.
- **S35** Kinovea docs, comparison and synchronization: https://kinovea.org/help/en/observation/comparison.html. Time
  origin sync, joint controls, linked speed, superposition.
- **S36** Kinovea features: https://www.kinovea.org/features.html. Frame stepping, time units, key images, tools,
  calibration, tracking, KVA export.
- **S37** Kinovea home: https://www.kinovea.org/. Version 2025.2.0, free and open source, Windows exe.
- **S38** Kinovea GitHub: https://github.com/Kinovea/Kinovea (via `gh api repos/Kinovea/Kinovea` and `/tags`).
  GPL-2.0, pushed 2026-10-07, tags to 2025.2.
- **S39** Kinovea manual index: https://kinovea.readthedocs.io/en/latest/. Manual sections (0.9.5 manual).
- **S40** V1 Sports, "Switch from Coach's Eye to V1" (competitor page):
  https://swing-analysis.v1sports.com/swing-analysis/switch-from-coachs-eye. Coach's Eye retirement date claim; V1
  sync points (address, top, impact).
- **S41** Coachway, "Coach's Eye alternatives" (competitor page, updated Sep 2026):
  https://coachway.io/articles/coachs-eye-alternatives/. Coach's Eye one-time fee and feature set; discontinuation.
- **S42** Spark Motion home: https://www.sparkmotion.com/. Markerless analysis announcement, goniometer, grid,
  compare.
- **S43** Apple Technical Q&A QA1820, smooth scrubbing: https://developer.apple.com/library/archive/qa/qa1820/_index.html.
  chaseTime and isSeekInProgress pattern with zero tolerance.
- **S44** Apple, `AVPlayer.seek(to:toleranceBefore:toleranceAfter:completionHandler:)`:
  https://developer.apple.com/documentation/avfoundation/avplayer/seek(to:tolerancebefore:toleranceafter:completionhandler:).
  Sample-accurate seek and decode delay; prior seek finishes with false.
- **S45** Apple, `AVPlayerItem.step(byCount:)`: https://developer.apple.com/documentation/avfoundation/avplayeritem/step(bycount:).
- **S46** Apple, `canStepBackward` / `canStepForward`:
  https://developer.apple.com/documentation/avfoundation/avplayeritem/canstepbackward and …/canstepforward.
- **S47** Apple, `AVAssetImageGenerator.requestedTimeToleranceBefore`:
  https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/requestedtimetolerancebefore.
  Frame-accurate thumbnails.
- **S48** Apple, `preferredScreenEdgesDeferringSystemGestures`:
  https://developer.apple.com/documentation/uikit/uiviewcontroller/preferredscreenedgesdeferringsystemgestures.
  iOS 11+ edge-gesture precedence.
- **S49** Apple, `PKCanvasViewDrawingPolicy`: https://developer.apple.com/documentation/pencilkit/pkcanvasviewdrawingpolicy
  (and `PKCanvasView.drawingPolicy`, iOS 14+). default / anyInput / pencilOnly.
- **S50** Apple, `RPScreenRecorder`: https://developer.apple.com/documentation/replaykit/rpscreenrecorder. "Can't
  record video from AVPlayer."
- **S51** Apple, `AVVideoCompositionCoreAnimationTool`:
  https://developer.apple.com/documentation/avfoundation/avvideocompositioncoreanimationtool. Overlay rendering
  constraints.
- **S52** Apple, `AVMutableVideoComposition`: https://developer.apple.com/documentation/avfoundation/avmutablevideocomposition.
  Per-source transform, opacity and crop; custom compositor.
- **S53** Apple, `VNDetectHumanBodyPoseRequest` and `VNHumanBodyPoseObservation.JointName`:
  https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest and
  https://developer.apple.com/documentation/vision/vnhumanbodyposeobservation/jointname. iOS 14+, 19 joints.
- **S54** Apple, `VNDetectHumanBodyPose3DRequest`, `VNHumanBodyPose3DObservation.JointName`, and the "Detecting human
  body poses in 3D with Vision" sample: https://developer.apple.com/documentation/vision/vndetecthumanbodypose3drequest,
  https://developer.apple.com/documentation/vision/vnhumanbodypose3dobservation/jointname and
  https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-3d-with-vision. iOS 17+, 17
  joints, depth use, A12+, all limbs visible.
- **S55** Apple, `DetectHumanBodyPoseRequest`: https://developer.apple.com/documentation/vision/detecthumanbodyposerequest.
  iOS 18+ Swift API.
- **S56** Apple, `PHVideoRequestOptionsVersion` (.original / .current):
  https://developer.apple.com/documentation/photos/phvideorequestoptionsversion. Original vs. edited video versions.
- **S57** Apple, `UIApplication.isIdleTimerDisabled`: https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled.
  Keeping the screen awake.
  (S43–S57 were read via the developer.apple.com/tutorials/data/documentation/… JSON endpoints.)
- **S58** App Store screenshots (mzstatic URLs from the `screenshotUrls` fields in S1, S2 and S4), visually inspected:
  Onform (player, frame scrubber, stacked compare with Unlink, tool rail, floating record), CoachNow (jog strip,
  Versus with dual jogs and link icon, voice-over bar, CoachCam, MultiCam fps, "by Golf Genius"), VisualEyes (tick
  jog, compare link), SevenSix (swing curves, scores), TorqAI (frame counter, trim ±, "Rough estimate"), AI Tennis
  Swing Coach (racket path vs. ideal, disclaimer).
- **S59** Hudl Technique status: https://itunes.apple.com/lookup?id=470428362&country=us (0 results) and
  https://apps.apple.com/us/app/id470428362 (HTTP 404). Id attribution from
  https://justuseapp.com/en/app/470428362/hudl-technique/reviews `[UNV]`. Hudl support URL
  https://twww.hudl.com/support/technique redirects with `ref=support_sunset` to a 404.
- **S60** Local project files: /Users/IDC2.5/jv/docs/handoff/JON-ORIGINAL-PROMPT.md,
  /Users/IDC2.5/jv/design-reference/brief/research.md, /Users/IDC2.5/jv/design-reference/brief/product-brief.md,
  /Users/IDC2.5/jv/design-reference/brief/screens.json. Founder intent, the prior research verified in §7, and screen
  definitions #10, #12, #13 and #14.
