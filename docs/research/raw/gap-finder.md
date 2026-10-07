# JOVRA gap finder and opportunities

Researcher: gap finder / product strategy. Date: 2026-10-07. Builds on `design-reference/brief/research.md` (prior brief), `product-brief.md`, `screens.json` (20 screens), `implementation-states.md`, `CLAUDE-BUILD-PROMPT.md` and the founder's own words in `docs/handoff/JON-ORIGINAL-PROMPT.md`.

**Claim labels.** **OBSERVED** means I saw it in a cited source, numbered [S#] in the Sources section. **INFERRED** means my reasoning from observed facts. **UNVERIFIED** means plausible but not confirmed, and it needs a spike or a legal or product decision.

**Effort scale (INFERRED, one experienced iOS engineer).** S is one week or less. M is 2–4 weeks. L is more than a month, or it needs a labeled-footage ML project.

**Priority scale.** P0 means v1 defines JOVRA. P1 means first update after v1, or v1 if cheap. P2 means after the core is trusted. *Later* needs a validated prerequisite. *Never* is a deliberate non-goal.

---

## 0. The headline (read this if nothing else)

1. **SwingVision already has most of the "obvious" opportunities.** (OBSERVED [S1][S2][S11].) These include an Apple Watch app (scoring, line-call challenges, a Target Practice haptic), Siri start, HealthKit workouts, dead-time trimming, highlights with a burned-in score, Target/Serve/Ball-machine practice, pickleball, padel (July 2026), ground mode (April 2026), USTA Connect verified NTRP/WTN (July 2026), background exports with a Live Activity on iOS 26 (May 2026), two-device recording, and ITF Player Analysis Technology approval (31 Oct 2025). For JOVRA these are **parity items, not differentiators**. Building them only makes JOVRA a cheaper clone. (INFERRED)
2. **The real gap is trust and ownership, not features.** (INFERRED from OBSERVED reviews [S3][S9].) In SwingVision's written App Store reviews, 2026 is the worst year in the sample: 38% of 2026 written reviews are 1-star, against 15% in 2025 and 25% in 2024. The complaints repeat:
   - price and tier confusion;
   - the free tier locking access to the user's *own* on-device videos older than 7 days;
   - ads on personal video (Feb 2026);
   - recording-hour quota lockouts;
   - Watch/phone desync ("watch said recording, phone had nothing");
   - AI scoring and player identification that need long manual cleanup;
   - lost or stuck uploads;
   - weak support.

   None of these needs a better neural network to beat. Each needs a different *contract* with the player.
3. **Ranked bets for JOVRA v1.** (INFERRED)
   1. **Own-your-footage contract.** No hour caps, no paywall on your own video, no ads, no tracking, no mandatory account.
   2. **Fast Point Review.** A swipe deck plus changeover "checkpoint scoring", which makes a 124-point match reviewable in minutes without trusting AI.
   3. **Rally-only playback that never hides anything.** Collapsed gaps stay visible and can be expanded, with adjustable pre/post-roll.
   4. **On-device audio+motion rally detection** as the first gated ML capability: cheap, private, and research-backed.
   5. **Never-lose-a-recording capture.** Fragment-safe files, a dark "court mode" screen, and recording status on the wrist through a Live Activity, without a Watch app.
   6. **Heat-aware deferred analysis** that runs while charging.
   7. **VoiceOver-first review**, declaring all applicable App Store Accessibility Nutrition Labels. No major competitor currently declares VoiceOver.
   8. **Handedness for both players**, so lefty forehands aren't labelled backhands.
   9. **Space Saver for Drive.** A rally-only archive copy, because a free 15 GB Google account holds only about three 54-minute 1080p60 sessions.
4. **Founder's Google Drive idea has a hidden cost cliff.** (INFERRED, computed from [S43][S44].) At about 90 MB/min (1080p60 HEVC), the 54-minute sample session is about 4.9 GB, and a 2-hour match is about 10.8 GB. The free Google tier is 15 GB, shared with Gmail and Photos. A rally-only archive copy is roughly 1.7 GB for the sample match, which turns Drive from a toy into a workable archive.
5. **Recording other people is regulated, and nobody designs for it.** (OBSERVED [S12].) Since Aug 2025, ITF requires written parental consent from *both* sides to record an under-18 match. The recording must be shared with the opponent, and real-time analysis apps need ITF PAT approval. SwingVision's own ITF report bans the Apple Watch in competition [S11]. A consent-and-competition mode is a genuine, cheap differentiator for the junior-parent segment, which reviews show is a real and happy SwingVision audience [S3].

---

## 1. Competitive reality check, 2025–2026 (verifies and extends the prior brief)

### 1.1 Prior-brief claims re-verified today

| Prior-brief claim | Today's check (2026-10-07) | Label |
|---|---|---|
| SwingVision 4.7/5, ~4.9K ratings | 4.706 avg, 4,928 ratings, v11.9.67 (2026-09-27), min iOS 18, 752 MB [S1] | OBSERVED, confirmed |
| SevenSix 4.2/5, 68 ratings; AI assistant removed in 4.0.1 | 4.19, 68 ratings. **v4.0.2 shipped today (2026-10-07)**: 7 languages, Facebook login removed, redesigned score screen. 4.0.1 (Aug 6, 2026) removed the AI Coach [S4][S5] | OBSERVED, confirmed and extended |
| Onform 4.8, ~8.7K ratings | 4.786, 8,666 ratings, v4.7.3 (2026-10-06), min iOS 18.6 [S7] | OBSERVED, confirmed |
| SwingVision is "single-camera" | Marketing says single camera, but the ITF approval report describes **one or two devices** at one or both ends, plus an optional on-court tablet [S11] | OBSERVED, correction |
| Prior brief silent on SwingVision pricing, free tier, Watch, Siri, HealthKit, padel, ITF | See 1.2 | Gap filled |

### 1.2 SwingVision: what shipped recently (OBSERVED from version history [S2]; dates as displayed, year 2026 unless stated; note-to-version mapping inferred from page order)

- **Pricing (IAP list) [S2].**
  - Plus: $14.99/mo or $95.99/yr.
  - Pro: $24.99/mo or $179.99/yr.
  - Max: $39.99/mo or $299.99/yr; Max became a family plan for up to 5 members (Nov–Dec 2025).
  - The description text still says Pro is "$179.99/yr ($14.99/mo)" [S1], which conflicts with the IAP list. (OBSERVED inconsistency.)
  - "Web subscription discounts" now show in-app (Sep 2026) [S1]. This is enabled by the May 2025 US anti-steering guideline change [S31].
- **New free tier (Feb 2026):** 8 recording hours per month in HD, Watch line-call challenges, and real-time audio line calls [S2].
- **Hour quotas exist on paid tiers.** One review cites a 30 h/month Pro limit [S3]; third-party pages cite 20 h for Plus and 60 h for Max. (UNVERIFIED, not on an official page I could render.)
- **Features shipped Dec 2025 – Sep 2026 [S2]:**
  - pickleball serve and ball-machine modes;
  - Ground Mode (record from the ground: trimming, rally filters, vertical highlights);
  - background video exports on iOS 26 with a Live Activity;
  - low-storage alerts before recording;
  - Ball Tracer;
  - padel for all players;
  - Monthly Challenges;
  - USTA Connect verified NTRP/WTN;
  - Sign in with Google;
  - larger playback controls;
  - full-match exports continue in the background;
  - a redesigned scoreboard in exports;
  - a Target Practice watch vibration;
  - a verbal warning when real-time audio feedback is disabled by overheating.
- **Fixes that reveal pain points [S2]:**
  - "interrupted recordings saved without any playable video";
  - "videos awaiting upload being deleted when storage is low";
  - "recordings ending early";
  - "sessions stuck on processing";
  - "watch-only sessions staying Live";
  - camera refocusing on iPhone 16+;
  - uploads stuck at 100%;
  - recording stability in high temperatures.
- **Platform reach [S2]:** iPhone, iPad, Mac, Apple Watch (watchOS 10+), visionOS. 9 languages.
- **App privacy label [S2]:** "Usage Data" is **used to track you** across other companies' apps and sites.
- **Accessibility label [S2]:** declares only Dark Interface, Differentiate Without Color Alone, Sufficient Contrast and Reduced Motion. It does **not** declare VoiceOver, Voice Control, Larger Text, Captions or Audio Descriptions.
- **ITF PAT approval PAT-25-037 (issued 31 Oct 2025) [S11]:**
  - 60 fps rear camera;
  - ML outputs 3D ball positions at hit, net and bounce, plus shot type, spin type and speed;
  - data goes to a backend server over Wi-Fi;
  - devices must share one password-protected account;
  - the Apple Watch is **not permitted** in competition;
  - approval explicitly does not establish line-call accuracy.

### 1.3 SevenSix and Onform deltas (OBSERVED [S5][S8])

- **SevenSix IAP:** $14.99/mo, $149.99/yr, plus pay-per-swing ($1.99 for 1, $3.99 for 3, $4.99 for 5). Accessibility is not declared. The privacy label shows User Content, Identifiers and Usage Data used to track. Rated 9+.
- **Onform:**
  - 4.6.0 (Aug 2, 2026) added a filmstrip frame scrubber, 20-language localization and automatic multicam angle detection. Its release notes claim full VoiceOver (including an adjustable video scrubber), Dynamic Type and WCAG AA contrast. **But the App Store accessibility label is still "not yet indicated."**
  - 4.7.0 (Sep 26, 2026) added shared notes, **voice-over transcription with an AI summary**, and "Made for iPad & iOS 27".
  - Individual plans are $9.99/$14.99 a month; coach plans run $19.99–$59.99 a month.

### 1.4 New entrants (OBSERVED via iTunes Search API [S10]): the market moved in 2026

- **A flood of "AI tennis coach" apps in 2026.** About 40 tennis, padel or pickleball analysis or tracker apps released Jan–Sep 2026, mostly with 0–8 ratings (TennisLens, Toach, FlowState, CedarX, TorqAI, ServeFix and more). Single-swing "AI feedback" is commoditized. (INFERRED.) JOVRA should not lead with it.
- **Privacy-first indies set a new baseline.**
  - **RallyTrim** (Aug 2026): on-device hit and rally detection, no account, no upload, rally review and export.
  - **TennisServe** (Oct 1, 2026): on-device serve analysis, "no account, no upload, no ads, no tracking", $6.99/mo or $39.99/yr, and it states honestly what the camera cannot measure.

  "Local and private" is becoming table stakes among challengers. JOVRA must *integrate* it with match review, not merely claim it. (INFERRED)
- **Parent/junior trackers:** **Tennis Seed: Junior Tracker** (Mar 2026), built by parents of junior players for tap-along scoring, stats and coach sharing.
- **Logging and social apps:** Slice, CourtzClub (restring reminders by minutes played, NTRP forecast) and Rally (multi-sport) offer head-to-head records and social feeds.
- **Wrist-only analysis:** **OverRally** (Jul 2026) recognizes swings on the Apple Watch with no phone filming. In a Jul 2026 review, a SwingVision user complained that SwingVision *removed* watch-only shot analysis [S3].
- **Embedded scoreboard video:** ScoreCam (1,826 ratings) records and streams with a scoreboard burned in.
- **Pickleball:** **PB Vision** (rally-only video, partner and side dynamics, skill ratings). Its feedback board shows its models assume right-handed players; a handedness setting has been "planned" since Dec 2024 with 21 votes [S38].

---

## 2. What players actually complain about and praise (quantified)

Data: the US App Store review RSS, the 10 most-recent pages. That gives SwingVision 490 written reviews (Oct 2016 – Oct 4, 2026), Onform 297 and SevenSix 11 [S3][S6][S9]. Theme counts come from keyword matching, so they are crude (INFERRED from OBSERVED text). Written reviews skew negative compared with star-only ratings: written-review averages are 3.26 (2024), 3.60 (2025) and 2.98 (2026), while the overall rating is 4.7.

**SwingVision written reviews 2024–2026 (n=218).** Each cell gives the theme count, with the count at 3 stars or below in brackets.

| Theme | Count (≤3★) | Interpretation |
|---|---|---|
| Price / subscription / trial | 59 (37) | #1 theme. Trial-to-annual surprise, tier confusion, "$180 too much for occasional players" |
| Apple Watch | 49 (32) | Loved when it works; desync and "watch said recording" failures; non-Watch owners feel excluded |
| Scoring / correction / edit | 44 (25) | AI scoring "fights you"; editing a missed point takes about as long as manual editing |
| Line-call accuracy | 39 (19) | Mixed; "about 80% right" is not good enough at the price |
| Upload / processing / sync | 36 (26) | Stuck uploads and processing; "lost my session" |
| Customer support | 33 (24) | Slow or generic; an AI chatbot that only sends links |
| Setup / mount / angle | 29 (14) | SwingStick, alignment, "court undetected", needs a second device without a Watch |
| Crash / lost recording | 21 (14) | Recording stops after 10 s; lost sets |
| Dead-time trim | 12 (7) | Praised ("2 h match in 15–20 min") but AI skips real points |
| Storage | 8 (6) | 20 GB cache with no way to clear; low-storage deletion |
| Kids / junior | 5 (0) | All positive: parents of junior players |
| Battery | 0 | Not a voiced complaint (heat appears in release notes, not reviews) |
| Privacy | 0 | Not voiced by SwingVision users; voiced by Onform users (forced third-party login) |

Representative 2025–2026 reviews (OBSERVED [S3][S9], paraphrased, with date and stars):

- 2026-05-04, 1★: free plan can't open videos older than 7 days **even though the file is on the device**.
- 2026-02-07/08, 1–2★: many ads after watching your own match video.
- 2026-10-01, 1★: a Pro user was blocked after about 4 h against a claimed 30 h quota, then upsold to a higher tier.
- 2026-04-16, 1★: a $50 stand "with a free month" led to a $179 annual charge.
- 2026-03-09, 4★: AI player identification works about 20% of the time; manual identification takes 5–10 minutes. Still worth it.
- 2026-09-10, 1★: fixing a missed point takes about as long as doing it in your own editor.
- 2026-08-06, 1★: the watch showed recording but only 1 of 3 sets was saved. Hard to know the phone's state when it is mounted high on the fence.
- 2026-04-17, 1★: without an Apple Watch, "Court Undetected" every time when using a second device.
- 2026-07-15, 1★: recording stopped after 10 s. Asks that the original at least be kept in Photos.
- 2026-01-25, 4★: asks for a 30 fps mode outside line-calling (storage).
- 2026-07-25, 4★: wants "uncheck all rallies" for exports; the app now opens on the front camera.
- 2026-05-11, 2★: removal of the audio-guided setup aid means a second device is required for alignment. Reviewing on a big screen is easier.
- 2025-05-28, 2★: AI skipped almost 2 minutes of play, with no way to view the time between detected rallies.
- 2025-11-30, 3★: point clips cut off too soon.
- 2025-10-04, 2★: sharing a video took 15 minutes to prepare and was too large to message.
- 2025-08-17, 2★: the "upload trimmed video" option was removed, so whole sessions are uploaded.
- 2025-07-04, 1★: 20 GB of app data with no way to clear it except reinstalling.
- 2025-04-15, 1★: why is there a recording limit if processing is on device?
- 2024-10-10 and 2025-01-05: users who switched to iPhone, or bought an iPad, because there is no Android app.
- 2026-09-13 and 09-14, 5★: parents say it transformed their junior son's game.
- Onform:
  - 2024-10-17 and 2026-03-09: complaints that login forces Google, Microsoft or Apple.
  - 2026-01-14: no metric units.
  - 2026-09-26: can't see videos they had made after the subscription lapsed.
  - 2024-05-15: can't save analysed video to the camera roll.
  - 2024-08-03: "I just want to share a swing with my coach".
- SevenSix:
  - 2023-09-02: the screen auto-locked during recording.
  - 2024–2025: analyses stuck for days.

**Praise to preserve (OBSERVED [S3]):**

- watching a 2-hour match in 15–20 minutes;
- filtering by shot;
- seeing yourself in slow motion;
- stats against preset objectives;
- sharing matches with a coach or with colleagues;
- junior development.

---

## 3. Platform capabilities that matter (Apple 2024–2026, plus Android parity)

| Capability | What it enables for JOVRA | Constraints / caveats | Label |
|---|---|---|---|
| `BGContinuedProcessingTask` / `BGContinuedProcessingTaskRequest(identifier:title:subtitle:)` (iOS 26) | User-tapped "Analyze now" or "Export highlights" keeps running after leaving the app, with **system-provided progress UI** | Must start from an explicit user action; must report `Progress` or it is expired; `.fail` vs queue strategy; background GPU via entitlement on supported devices only [S13] (a forum report says the GPU is not available on iPhone [S14], UNVERIFIED on iOS 27) | OBSERVED |
| `BGProcessingTaskRequest.requiresExternalPower` | "Analyze while charging" overnight, without user waiting | System-scheduled, no timing guarantee [S13] | OBSERVED |
| `AVCaptureEventInteraction` (iOS 17.2+) | Volume buttons, Action button and Camera Control start/stop or bookmark | In iOS 26, **AirPods (H2) stem clicks work automatically** for apps that adopted it [S15] | OBSERVED |
| Remote range of AirPods/Watch from a far baseline | Far-side player marking points | Bluetooth range vs a 23.77 m court is unknown | UNVERIFIED, device spike |
| LockedCameraCapture extension (iOS 18) | Launch JOVRA capture from the Lock Screen, Control Center or Action button without unlocking | Extension has no network and limited data access [S17] | OBSERVED |
| Live Activities (ActivityKit) | Recording/analysis/backup status on Lock Screen and Dynamic Island | Up to 8 h active, plus up to 4 h more on the Lock Screen [S19] | OBSERVED |
| **iPhone Live Activities appear on Apple Watch Smart Stack automatically** (iOS 18 / watchOS 11) | "REC 32:10 · saved 4 s ago" on the wrist **without building a watchOS app** | Whether it shows while the iPhone app is foreground-recording is UNVERIFIED (device spike) [S18] | OBSERVED (feature) / UNVERIFIED (our case) |
| HealthKit `HKWorkoutSession` + `HKLiveWorkoutBuilder` **on iPhone** (iOS 26) | Log tennis or pickleball workouts from the phone; crash recovery of an active workout | iPhone has no HR sensor (needs external); padel has no dedicated type (SwingVision saves padel as "Other" [S2]) [S16] | OBSERVED |
| `CMBatchedSensorManager` (watchOS 10) | 800 Hz accelerometer / 200 Hz device motion: swing counts, impact timing on the wrist | Needs an active HealthKit workout session; batched about 1/s [S25] | OBSERVED |
| watchOS double tap: `.handGestureShortcut(.primaryAction)` (watchOS 11) | Hands-free "mark point" or "point won" on the Watch | One primary action per scene [S24] | OBSERVED |
| `AVCaptureDevice.SystemPressureState` | Detect thermal or power pressure; throttle 60→30 fps instead of dying | At `.shutdown` capture stops [S26] | OBSERVED |
| Apple operating range 0–35 °C (32–95 °F) ambient | Summer courts exceed this. Heat is physics, not just bugs | Display dims, charging stops, frame rates drop [S27] | OBSERVED |
| `movieFragmentInterval` (AVCaptureMovieFileOutput, default 10 s) | Crash/interrupt-safe partial files; set about 1 s for the first fragment | Before the first fragment, the file is unplayable [S28] | OBSERVED |
| Vision `VNDetectTrajectoriesRequest` (iOS 14) | Candidate primitive for ball arcs | Built for parabolic paths from a stable camera; tennis ball size, speed and blur are unproven [S37] | OBSERVED (API) / UNVERIFIED (tennis) |
| Speech `SpeechAnalyzer` / `SpeechTranscriber` (iOS 26) | On-device transcription of voice notes and coach voice-overs; searchable | Court noise for live voice commands untested [S22] | OBSERVED |
| Foundation Models framework (iOS 26; expanded in iOS 27 with image input, server models, Dynamic Profiles) | Free on-device natural-language match recaps with guided generation | Apple Intelligence devices only (about A17 Pro and later); hallucination risk [S20][S21] | OBSERVED |
| Wi-Fi Aware framework (iOS 26) | Phone-to-phone high-throughput link for a 2-angle rig, no router | iPhone 12+ [S23] | OBSERVED (secondary source) |
| Audio Graphs (`AXChartDescriptor`, iOS 15) | VoiceOver users "hear" trend charts | Must supply descriptors per chart [S29] | OBSERVED |
| App Store Accessibility Nutrition Labels (2025) | Public, comparable accessibility claims | Developer-declared, not verified by Apple [S30] | OBSERVED |
| Declared Age Range API (iOS 26; age bands, regulatory signals) | Age-appropriate defaults if JOVRA ever has accounts or sharing | Utah age categories shareable from May 6, 2026; Louisiana from Jul 1, 2026; Texas law enforcement blocked Dec 2025 [S32] | OBSERVED (secondary) |
| Android 16 `Notification.ProgressStyle` (Live Updates) | Android equivalent of the progress Live Activity for the later port | Android 16+ [S45] | OBSERVED |

---

## 4. Ranked opportunity list

The ranking is by (player value × evidence strength × on-device feasibility) ÷ (effort × risk) (INFERRED). Each entry says whether it is a **differentiator**, **parity** (a competitor already has it) or **hygiene**.

### Summary table

| Rank | Opportunity | Type | Effort | Risk | Rec |
|---|---|---|---|---|---|
| 1 | Own-your-footage contract (no caps / paywalled own video / ads / tracking / mandatory account) | Differentiator | S | Med (business) | **P0** |
| 2 | Fast Point Review deck + changeover checkpoint scoring | Differentiator | M | Low | **P0** |
| 3 | Rally-only playback with visible, expandable gaps and adjustable pre/post-roll | Parity+ | M | Low | **P0** |
| 4 | On-device audio+motion rally detection (gated benchmark) | Parity (cheaper, private) | M–L | Med | **P0 (gated)** |
| 5 | Never-lose-a-recording capture + court-mode display + status on the wrist | Differentiator | M | Med | **P0** |
| 6 | Heat- and battery-aware pipeline (capture-only on court, analyze on charger) | Hygiene → differentiator | S–M | Low | **P0** |
| 7 | VoiceOver-first match review + full Accessibility Nutrition Labels | Differentiator | M | Low | **P0** |
| 8 | Handedness for player *and* opponent; mirrored diagrams | Differentiator | S | Low | **P0** |
| 9 | Storage planner + Space Saver archive (rally-only copy, 30 fps option, cache control) | Differentiator | S–M | Low | **P0** |
| 10 | Coach / opponent Share Pack (Drive link with expiry, AirDrop zip, small proxy video) | Differentiator | M | Med | **P1** |
| 11 | Consent, competition and junior-parent mode | Differentiator | M | Med (legal) | **P1** |
| 12 | Open data export (CSV + versioned JSON) and import | Parity+ | S | Low | **P1** |
| 13 | Hands-free inputs: volume / Action / Camera Control / AirPods / Watch double tap | Parity+ | S–M | Med | **P1** |
| 14 | Highlight reel with burned-in score and stats; vertical crop | Parity | M | Low | **P1** |
| 15 | App Intents / Siri / Shortcuts / Control Center / processing Live Activity | Parity | S–M | Low | **P1** |
| 16 | Doubles manual scoring with server rotation and court sides | Parity | S–M | Low | **P1** |
| 17 | Head-to-head and opponent history (local) | Parity (loggers) | S | Low | **P1** |
| 18 | HealthKit workout logging (phone and Watch) | Parity | S–M | Low | **P1** |
| 19 | Transparent pricing (no hour caps, honest trials, restore, family) | Differentiator | S | Med (revenue) | **P1** (decision) |
| 20 | In-app diagnostics bundle + human-readable failure states | Hygiene | S | Low | **P1** |
| 21 | Localization foundation (String Catalogs; ES first; metric units) | Parity | S + per language | Low | **P1** |
| 22 | iPad and Mac big-screen review | Parity | M | Low | **P1** |
| 23 | On-device recap text (Foundation Models, numbers verified) | Differentiator | M | Med | **P2** |
| 24 | Practice counters: ball machine, rally streaks, serve counts; Watch-only swing counts | Parity | M | Med | **P2** |
| 25 | Voice-note transcription; experimental voice bookmarks | Parity (Onform) | S–M | Med | **P2** |
| 26 | UTR / USTA logging (copy-score + UTR self-post link; USTA Connect later) | Parity | S | Low | **P2** |
| 27 | Pickleball mode | Parity | M | Med | **P2** |
| 28 | Lock Screen / Camera Control quick record (LockedCameraCapture) | Parity+ | M | Med | **P2** |
| 29 | Two-phone multi-angle (Wi-Fi Aware / Multipeer, audio-clap sync) | Parity | L | High | **Later** |
| 30 | Serve-target games with bounce localization | Parity | L | High | **Later** |
| 31 | Doubles positioning analytics | Parity | L | High | **Later** |
| 32 | Padel mode | Parity | L | High | **Later** |
| 33 | ITF PAT approval for competition use | Parity | M (process) | Med | **Later** |
| 34 | Live line calling / challenges presented as officiating | Parity | L | Very high | **Never (v1)** |
| 35 | Ads, cross-app tracking, default training-data sharing | n/a | n/a | n/a | **Never** |
| 36 | Live streaming matches | Parity | L | High (minors, cost) | **Never (v1)** |
| 37 | Pro-player comparison library, spin RPM, injury prediction | Parity | L | Very high | **Never** |

### Detail per opportunity

#### 1. Own-your-footage contract: **P0**, S, differentiator

- **User value:** players never lose access to a recording they made on their own phone, whatever their plan, quota or login state. No ads on personal video. No hour caps for on-device work.
- **Evidence (OBSERVED):**
  - SwingVision's free plan blocks videos older than 7 days though they are on-device; ads were added to personal video; a quota lockout [S3].
  - Onform video access was lost after the subscription lapsed [S9].
  - SwingVision's privacy label lists Usage Data used for tracking [S2].
  - App Store guideline 5.1.1(v): apps without significant account-based features must work without login [S31].
- **Feasibility:** architectural, not technical. Originals in the app container, an always-available "Save original to Photos/Files", and no server. (INFERRED)
- **Risk:** monetization must come from value-added analysis, not hostage footage. Requires the pricing decision (#19).
- **Recommendation:** P0. Write it as an in-app promise on the Storage screen (screen 19) and the Welcome screen (screen 1).
  - "Get started" must work with **no account**; Sign in with Apple stays optional, for multi-device features only.
  - Target an App Privacy label of "Data Not Collected" for v1 (no third-party analytics SDKs). Crash diagnostics are opt-in (#20).

#### 2. Fast Point Review deck + checkpoint scoring: **P0**, M, differentiator

- **User value:** turn an unscored or mis-scored match into a correct point-by-point record in about 5 minutes, without trusting AI.
  - Each detected rally (or each manual "Mark point" bookmark) becomes a card with a 3–4 s looping preview, and the player swipes it:
    - right: I won;
    - left: opponent won;
    - up: let / not a point;
    - down: unsure, revisit.
  - **Checkpoint scoring:** during play the user optionally enters only the game score at changeovers (every odd game, about 10 taps per match).
  - The scoring state machine then uses tennis rules to **constrain and auto-fill** point winners between checkpoints, and flags only the inconsistent stretches for review.
- **Evidence (OBSERVED [S3]):**
  - AI scoring unreliable across 2024–2026 reviews;
  - player identification "works about 20% of the time", with 5–10 min of manual ID;
  - "editing takes as long as my own software";
  - "auto scoring fights you".

  The prior brief already found correction friction but only proposed an Edit Point button (screen 10).
- **Feasibility:** fully on-device, with no ML required: SwiftUI gesture deck, AVPlayer looping (`AVPlayerLooper`), and a deterministic rules engine. The constraint solver over game/set boundaries is a small search problem: a game ends at ≥4 points with a 2-point margin, plus tie-breaks. (INFERRED)
- **Risk:** low. The UX must keep an "undo" stack and preserve both the original detection and the user edits (already required by the build prompt).
- **Recommendation:** P0. Add a dedicated **Point Review** route reachable from Match overview ("Review 8 flagged points", screen 9) and Smart replay (screen 10). VoiceOver: each card exposes custom actions "I won / Opponent won / Let" (#7).

#### 3. Rally-only playback that never hides anything: **P0**, M, parity+

- **User value:** watch a 2-hour match in about 20 minutes while still being able to see what the detector skipped.
- **Evidence:**
  - Effective playing time in tennis is roughly 20–30% of match time on clay and 10–15% on fast courts [S35] (OBSERVED).
  - SwingVision reviewers praise watching a 2 h match in 15–20 min, but complain that AI skipped about 2 min of play with no way to see the gaps, and that clips cut off too soon [S3] (OBSERVED).
  - SwingVision removed "upload trimmed video" (2025 review) [S3].
- **Feasibility:** `AVMutableComposition` of rally time ranges over the untouched original, plus a timeline showing collapsed gaps as tappable "+0:42" chips. Pre-roll and post-roll default to 1.5 s / 2.5 s, adjustable per session and per clip. Bulk select or deselect rallies (a 2026 review asked for "uncheck all"). (INFERRED)
- **Risk:** low; depends on segmentation quality (#4) but works with manual bookmarks too.
- **Recommendation:** P0. The build prompt's requirement that full-video scrubbing remain available is necessary but not sufficient: make gaps *visible*.

#### 4. On-device audio+motion rally detection (the first gated ML capability): **P0 (gated)**, M–L, parity at lower cost

- **User value:** automatic dead-time removal and point candidates with no server, no upload and no quota.
- **Evidence:**
  - A padel multimodal (audio+video) hit detection paper reports about 92% average F1 [S36] (OBSERVED via the paper's abstract and summary; replicate before relying on it).
  - RallyTrim ships on-device hit and rally detection today [S10].
  - SwingVision used to offer an audio-based setup aid and real-time audio line calls [S2][S3].
- **Feasibility:** feasible on-device. Audio onset energy plus a small Create ML / Core ML sound classifier for racket impact, fused with frame-difference motion in the court region. Racket contact lasts about 1–2 ms, so energy-peak detection plus a CNN beats frame-based sound event detection (reported in literature summaries, UNVERIFIED in detail). (INFERRED)
- **Risk (INFERRED):**
  - hits from adjacent courts at public venues;
  - wind;
  - indoor echo;
  - the brief's rule that the microphone is optional.

  **Resolution:** offer "Use microphone for rally detection; audio is analyzed then discarded (not saved in the video)" as an explicit opt-in. Visual-only fallback works with a lower quality bar.
- **Recommendation:** P0 as a **benchmark gate**, shipped only if it passes, consistent with the brief's capability registry. Suggested gate: ≥95% of real points covered by detected segments and ≤10% false segments, on ≥10 labeled sessions from ≥3 venues (public multi-court, indoor, windy). This is a starting proposal, not a validated threshold.

#### 5. Never-lose-a-recording capture, court-mode display and status on the wrist: **P0**, M, differentiator

- **User value:** the phone on the fence is out of sight and out of reach; the player needs certainty it is still recording and that saved footage survives anything.
- **Evidence:**
  - 2024–2026 reviews: watch showed recording but the phone saved nothing; recording stopped after 10 s; lost sets; recovered sessions with no playable video [S3].
  - SwingVision's own 2026 fixes list "interrupted recordings saved without any playable video" [S2].
  - SevenSix screen auto-lock during recording [S6].
- **Feasibility (OBSERVED APIs, INFERRED design):**
  - (a) `movieFragmentInterval` about 1 s for the first fragment, then about 10 s, plus rolling segment files and a write-ahead session journal [S28];
  - (b) `isIdleTimerDisabled` during capture, plus **court mode**: a near-black OLED screen (dim brightness, show only REC, timer and "saved n s ago") to cut heat and battery and reduce glare distraction;
  - (c) a **Live Activity** started at REC showing elapsed time, last-flush age and storage left. On watchOS 11+ it appears in the Watch Smart Stack automatically, with no Watch app [S18]. Whether it shows while the iPhone app is foreground is UNVERIFIED and needs a device spike;
  - (d) a haptic or audible confirmation for every remote start, stop or bookmark command (lesson from SwingVision's Watch desync);
  - (e) default to the back camera, lock focus, exposure and white balance after calibration, and **disable video stabilization on a tripod**, since stabilization crops and shifts geometry and harms court calibration (INFERRED; SwingVision fixed unwanted refocusing in 2025–26 [S2]);
  - (f) auto-end a session after N minutes of no motion and no hits, with confirmation, to prevent "sessions that never end" [S3].
- **Risk:** medium. Real-device validation is required (simulator cannot prove it).
- **Recommendation:** P0. Extend screen 6 (Live capture) with court mode and "Saved · 4 s ago". Add a Live Activity design.

#### 6. Heat- and battery-aware pipeline: **P0**, S–M, hygiene that becomes a differentiator

- **User value:** recordings finish on hot days; analysis never cooks the phone mid-match.
- **Evidence:**
  - Apple's stated ambient operating range is 0–35 °C, and in heat it dims the display, stops charging and lowers frame rates [S27].
  - SwingVision release notes repeatedly address high-temperature recording, and in Sep 2026 added a verbal warning when overheating disables real-time feedback [S2].
  - **Players don't complain about battery in reviews** (0 mentions, 2024–2026 [S3]), so this is about reliability, not marketing.
- **Feasibility:**
  - On court: capture only, with no live inference. JOVRA deliberately has no live line calls (#34).
  - Monitor `SystemPressureState` and throttle 60→30 fps at `.serious`/`.critical`, logging a marker so analysis knows the frame rate changed [S26].
  - Deep analysis runs via `BGProcessingTaskRequest(requiresExternalPower: true)` overnight, or a user-tapped `BGContinuedProcessingTask` with system progress UI [S13].
  - Show "Analysis waits for charger" as a user choice. (INFERRED)
- **Risk:** low. Background GPU may be iPad-only [S14], so iPhone analysis may be CPU/ANE-bound. Benchmark it.
- **Recommendation:** P0. Screen 6 already shows "Phone warming · Analysis paused"; extend screen 7 with an "Analyze now / when charging" choice.

#### 7. VoiceOver-first match review + full Accessibility Nutrition Labels: **P0**, M, differentiator

- **User value:** blind, low-vision and motor-impaired players and coaches (and every player at 2× Dynamic Type) can review points, correct the score and read trends.
- **Evidence:**
  - SwingVision declares only 4 of the 9 label features (no VoiceOver, Voice Control, Larger Text, Captions or Audio Descriptions) [S2]. SevenSix and Onform declare none [S5][S8], though Onform's Aug 2026 notes claim VoiceOver work.
  - App Store labels are developer-declared [S30].
- **Feasibility:**
  - A VoiceOver **rotor of points** (each point announced: "Point 42, 4–3, 30–15, Jon serving, 8 shots, Jon won, needs review");
  - custom actions for swipe-review outcomes (#2);
  - an adjustable timeline (`accessibilityAdjustableAction`) stepping point-by-point and frame-by-frame;
  - `AXChartDescriptor` Audio Graphs for progress charts [S29];
  - shot maps with shape and text, not color alone (already required);
  - captions on exported highlights that carry speech (#25).
- **Risk:** low, but needs real VoiceOver testing; the claims must be honest.
- **Recommendation:** P0 for structure and labels; Audio Graphs in P1. Declare every label JOVRA genuinely passes at launch.

#### 8. Handedness for player and opponent: **P0**, S, differentiator

- **User value:** lefties (and their opponents) get correct forehand and backhand stats and drills.
- **Evidence:** PB Vision's models assume right-handers, and a fix has been "planned" since Dec 2024 (21 votes, comments into 2025) [S38]. Onboarding (screen 2) captures *the user's* handedness but not opponents'.
- **Feasibility:** a data-model field on every Player, used by stroke labeling, shot-map filters, drills and the Stroke Lab overlay. Mirrored side-view diagrams. (INFERRED)
- **Risk:** low.
- **Recommendation:** P0. Add opponent handedness to setup (screen 4) and to player records.

#### 9. Storage planner + Space Saver archive: **P0**, S–M, differentiator

- **User value:** know before recording whether the session fits, and keep years of matches in a free or cheap Drive.
- **Evidence:**
  - 1080p60 HEVC is about 90 MB/min (secondary source quoting iOS Settings [S44], UNVERIFIED against Apple's own page).
  - A free Google account has 15 GB shared across Gmail, Drive and Photos [S43].
  - SwingVision storage complaints (20 GB of uncleared data; uploads deleted at low storage; the trimmed-upload option removed) and a request for a 30 fps mode [S3].
- **Arithmetic (INFERRED):**
  - The 54-min sample is about 4.9 GB.
  - A rally-only copy (124 points × about 9 s with padding, about 18.6 min) is about 1.7 GB, a 65% saving.
  - A 15 GB free Drive holds about 3 full sample sessions, or about 8 rally-only versions.
- **Feasibility:** a passthrough export of rally ranges (`AVAssetExportSession` with `AVAssetExportPresetPassthrough`, so no re-encode, fast and cool), a 30 fps capture preset for non-analysis practice, a cache manager with per-session sizes, and a Drive quota check via the Drive `about` endpoint (UNVERIFIED with the drive.file scope).
- **Risk:** low. Never delete the original without explicit confirmation and a verified archive (already a brief rule).
- **Recommendation:** P0. Extend screen 19 with "Archive full / rallies only", a quota bar and per-session sizes. Replace the hardcoded "3.2 GB" estimate in screen 4 with preset bitrate × planned duration.

#### 10. Coach / opponent Share Pack: **P1**, M, differentiator

- **User value:** send a coach, partner or opponent exactly the points that matter, with notes and stats, without them needing an app, an account or a $20–60/mo coach plan.
- **Evidence:**
  - "Took 15 minutes to prepare and too large to message" [S3].
  - "I just want to share a swing with my coach" [S9].
  - Onform coach plans cost $19.99–$59.99/mo [S7].
  - ITF U18 rules require the full recording to be made available to the opponent [S12].
- **Feasibility:**
  - Pack = selected clips (720p proxy or rally-only), notes, `match.json`, `points.csv` and a static `index.html` viewer.
  - Delivery via AirDrop or Files as `.zip`, or as a Drive folder link.
  - Drive permissions support `type` user/group/domain/anyone, and `expirationTime` (user/group only, maximum one year) [S41].
  - Whether `drive.file` lets the app share folders it created is UNVERIFIED and needs an API spike [S42].
- **Risk:** medium. Sharing minors' video (see #11); link leakage. Default to expiring person-specific shares, not anyone-with-link.
- **Recommendation:** P1. Add a "Share pack" sheet from Match overview (screen 9) and Smart replay (screen 10).

#### 11. Consent, competition and junior-parent mode: **P1**, M, differentiator

- **User value:** parents and juniors can record legally and respectfully; adults get a courteous consent flow; tournament players don't break rules.
- **Evidence:**
  - ITF (Aug 2025): written consent is required from the recording player's parent **and** the opponent's parent for U18 matches; consent can be withdrawn mid-match, which means deletion; the full recording must be given to the opponent; no public posting; real-time-analysis tech needs PAT approval under Rule 31 [S12].
  - SwingVision's PAT report bans the Apple Watch in competition [S11].
  - Junior-parent reviews are uniformly positive [S3]; Tennis Seed exists for this segment [S10].
  - COPPA amendments (effective Jun 23, 2025; compliance by Apr 22, 2026) widen "personal information" to biometrics such as faceprints and gait, and add retention limits [S33].
  - The EU household exemption does not cover publishing to an unlimited audience [S34].
- **Feasibility (INFERRED):**
  - a pre-record "Recording consent" row in setup (informed / written form attached / not required);
  - a **Competition mode** (no real-time feedback, Watch shows only the clock, a reminder of local rules);
  - **Parent mode** (child profiles live under the parent's local data, there is no child account, and sharing defaults to private);
  - "Delete this recording now" one tap away during capture (consent withdrawal);
  - on-device face blur for bystanders in shared exports (Vision face rectangles plus a blur filter).

  Local-first means JOVRA (the operator) may never *receive* children's data, which **may** greatly simplify COPPA/GDPR exposure. UNVERIFIED: this needs legal review before any marketing claim.
- **Risk:** medium (legal wording); must not imply legal compliance for users.
- **Recommendation:** P1. Add a consent row to screen 4 and Competition/Parent mode to screen 20. Use Declared Age Range only if JOVRA ever adds accounts or social features [S32].

#### 12. Open data export (CSV + versioned JSON) and import: **P1**, S, parity+

- **User value:** coaches use spreadsheets; players own their stats; no lock-in.
- **Evidence:** SwingVision has stats export (a 2026 fix mentions a crash exporting stats) [S2]; the founder wants Drive-based ownership [founder prompt].
- **Feasibility:** trivial on top of the framework-independent domain schema the build prompt already requires. Publish the JSON schema in the repo.
- **Risk:** low.
- **Recommendation:** P1, and possibly v1 since it is cheap. Screen 19 already has "Export video + analysis".

#### 13. Hands-free inputs: **P1**, S–M, parity+

- **User value:** mark points or start and stop without walking to the fence and without a Watch.
- **Evidence:** "Not everybody has an Apple Watch" and "court undetected without a Watch" [S3]; Watch desync complaints [S3].
- **Feasibility:**
  - `AVCaptureEventInteraction` for volume, Action and Camera Control, with AirPods H2 stem clicks free on iOS 26 [S15];
  - Watch double tap via `.handGestureShortcut(.primaryAction)` [S24];
  - haptic confirmation is mandatory.

  Bluetooth range to the far baseline is UNVERIFIED.
- **Risk:** medium (range, accidental presses).
- **Recommendation:** P1, with a device spike first. The Watch app itself is a P1/P2 decision; the Live Activity mirror (#5) may cover status without one.

#### 14. Highlight reel with burned-in score and stats: **P1**, M, parity

- **User value:** a shareable 60–90 s reel of the best rallies with the scoreboard.
- **Evidence:** SwingVision lists highlights with scores and stats overlaid, plus vertical highlights in Ground Mode [S1][S2]; ScoreCam's embedded scoreboard has 1,826 ratings [S10].
- **Feasibility:** `AVVideoComposition` with Core Animation overlay layers from the event model (score at each point, computed, never typed), a vertical crop that keeps the player box, on-device export with `BGContinuedProcessingTask` for long reels. (INFERRED)
- **Risk:** low. Ranking "best" rallies needs a heuristic (length, bookmarks, break points).
- **Recommendation:** P1. Mark exports as user-reviewed versus automatic.

#### 15. App Intents / Siri / Shortcuts / Control Center + processing Live Activity: **P1**, S–M, parity

- **Evidence:** SwingVision supports Siri to start sessions and background exports with a Live Activity [S1][S2]. iOS 27 expands App Intents (entity schemas, View Annotations, a testing framework) [S20].
- **Recommendation:** P1. Intents: "Start singles recording", "Mark point", "Show last match", "Analyze when charging". Controls for Control Center and the Action button.

#### 16. Doubles manual scoring with rotation and sides: **P1**, S–M, parity

- **Evidence:** SwingVision supports doubles and pickleball doubles, but reviewers say shot attribution struggles in doubles [S3]; PB Vision shows partner and side dynamics [S10].
- **Recommendation:** P1. A correct scoring state machine (serving order, deuce/ad sides, tie-break rotation) with manual winners is honest and cheap. Automatic doubles attribution is *Later* (#31).

#### 17. Head-to-head and opponent history: **P1**, S, parity with loggers

- **Evidence:** Slice and Rally ship head-to-head records [S10]; SwingVision added frequent hitting partners (Jun 2026) [S2].
- **Recommendation:** P1. Purely local queries over sessions; shown as a card on Match overview.

#### 18. HealthKit workout logging: **P1**, S–M, parity

- **Evidence:** SwingVision saves workouts to Activity and HealthKit [S1]. iOS 26 brings `HKWorkoutSession` to iPhone with crash recovery [S16]. Padel lacks a dedicated type (SwingVision saves it as "Other" [S2]).
- **Recommendation:** P1. Write a tennis workout spanning the recording with sample-free metadata (session ID). Never block recording on Health permission.

#### 19. Transparent pricing: **P1 decision**, S, differentiator

- **Evidence:**
  - Price is the #1 SwingVision review theme (59 mentions, 37 negative) [S3].
  - Trial-to-annual surprises on both SwingVision and Onform [S3][S9].
  - TennisServe sells honest on-device analysis at $6.99/mo or $39.99/yr [S10].
  - US apps may link to web purchase without the in-app ban since May 2025 [S31] (the current commission status after later appeals is UNVERIFIED).
- **Straw man (INFERRED, a product decision for Jon):**
  - Free forever: record, replay, manual scoring, Point Review, rally-only playback with manual bookmarks, export, Drive archive.
  - JOVRA Pro, one-time or low annual: automatic rally detection, highlights, Serve and Stroke Labs, recap.
  - No hour caps, no ads, and no trial that converts to annual without an explicit second confirmation.
  - Family Sharing for parents.

  Server-free architecture is what makes this sustainable.
- **Risk:** revenue; ongoing model R&D cost.

#### 20. In-app diagnostics bundle + human-readable failures: **P1**, S, hygiene

- **Evidence:** customer support is mentioned 33 times (24 negative) in 2024–26 SwingVision reviews [S3].
- **Feasibility:** local structured log (OSLog export) plus a session manifest, zipped and attached to an email *only when the user taps it*. No telemetry SDK.
- **Recommendation:** P1. It is the support strategy for a small team.

#### 21. Localization foundation: **P1**, S (+ per language)

- **Evidence:** SwingVision has 9 languages [S1], Onform 21 (20 added Aug 2026) [S7][S8], and SevenSix added 7 today [S4]. An Onform review asks for metric units [S9].
- **Recommendation:** P1. String Catalogs from day 1, with units through `Measurement`. Ship English plus Spanish first (padel and LatAm growth; INFERRED), then FR/DE/PT-BR/IT/JA.

#### 22. iPad and Mac review: **P1**, M, parity

- **Evidence:** a reviewer prefers big-screen review [S3]; SwingVision ships iPad and Mac [S2]; Onform is "Made for iPad & iOS 27" [S8].
- **Recommendation:** P1. A SwiftUI split view for Point Review and Compare; iPhone remains the capture device.

#### 23. On-device recap text (Foundation Models): **P2**, M, differentiator

- **Value:** a 3-sentence "what decided this match" summary in plain words.
- **Feasibility:** guided generation (`@Generable` struct whose fields reference computed stat IDs and point IDs). Post-check that every number in the text equals a computed stat, otherwise fall back to a template. Free on-device on Apple Intelligence devices [S20][S21]; the template path covers older phones. (INFERRED design)
- **Risk:** hallucinated tennis advice. Keep it descriptive and evidence-linked, not prescriptive coaching.
- **Recommendation:** P2. Do not lead marketing with "AI coach": SevenSix removed its AI Coach in Aug 2026 [S5], and 2026 saw about 40 near-identical AI-coach apps [S10].

#### 24. Practice counters: ball machine, rally streaks, serve counts; Watch-only swing counts: **P2**, M, parity

- **Evidence:**
  - SwingVision has ball-machine, serve-practice and Target Practice modes [S2].
  - A 2026 reviewer misses watch-only shot analysis that SwingVision removed [S3].
  - OverRally does wrist-only swing recognition [S10].
  - `CMBatchedSensorManager` gives 800 Hz accelerometer data during a workout [S25].
- **Recommendation:** P2. Audio-hit counters reuse #4. Watch-only swing counting needs its own labeled dataset (L if pursued).

#### 25. Voice notes transcription; experimental voice bookmarks: **P2**, S–M, parity

- **Evidence:** Onform shipped voice-over transcription with an AI summary in Sep 2026 [S8]; `SpeechAnalyzer` is on-device and handles distant speakers [S22].
- **Recommendation:** P2. Transcribe comparison voice notes (screen 14) for search and captions. Live voice bookmarks ("mark that") on a noisy court are an *experiment*, not a promise; the hardware button and AirPods (#13) are more reliable.

#### 26. UTR / USTA logging: **P2**, S, parity

- **Evidence:** UTR allows self-posting of casual scores, which count only after the opponent confirms and never toward Verified UTR [S39]. USTA Connect APIs are offered to vetted partners "with established user bases" [S40]; SwingVision integrated it in Jul–Aug 2026 [S2].
- **Recommendation:** P2. "Copy result" in UTR's format plus a link to UTR's post-score flow. USTA Connect partnership is *Later*, after traction.

#### 27. Pickleball mode: **P2**, M, parity

- **Evidence:** SwingVision supports pickleball (with complaints about doubles attribution) [S3]. PB Vision and many 2026 pickleball apps exist [S10].
- **Recommendation:** P2. Sport-agnostic domain enums now (S); pickleball scoring and court geometry after tennis is trusted.

#### 28. Lock Screen / Camera Control quick record: **P2**, M, parity+

- **Evidence:** LockedCameraCapture lets third-party camera apps launch from the Lock Screen, Control Center or Action button without unlocking [S17].
- **Risk:** the extension cannot use the network and must hand off to the app; adds complexity.
- **Recommendation:** P2.

#### 29–33. Later

- **Two-phone multi-angle (L):** SwingVision supports two devices [S11] and Onform has multicam [S8]. Wi-Fi Aware [S23] or Multipeer plus an audio-clap sync. Needs the single-camera pipeline validated first.
- **Serve-target games (L):** needs validated ball bounce localization. A trajectory primitive exists [S37] but is unproven for tennis.
- **Doubles positioning analytics (L):** needs 4-player tracking.
- **Padel (L):** glass walls and reflections; many dedicated apps [S10]. SwingVision added it in Jul 2026 [S2].
- **ITF PAT approval (process M):** valuable for juniors and college. Requires a stable product version [S11][S12].

#### 34–37. Never (for v1, or permanently)

- **Live line calls and challenges as officiating:** the ITF says PAT approval "does not establish accuracy" [S11]; reviewers report about 80% reliability [S3]; contradicts JOVRA's honesty principle.
- **Ads, cross-app tracking, default training-data sharing:** this is the differentiator, so never trade it [S2][S3].
- **Live streaming:** server cost; minors (ITF bans posting U18 footage) [S12].
- **Pro-player comparison library, spin RPM, injury prediction:** licensing, and unsupported by single-camera evidence (already excluded by the brief).

---

## 5. Founder/assignment checklist: every suggested idea, with a verdict

| Idea | Verdict | Where |
|---|---|---|
| Post-match fast point review (swipe winners) | **P0**, differentiator | #2 |
| Dead-time removal / rally-only playback | **P0**, parity+ (gaps visible) | #3, #4 |
| Auto highlight reels with burned-in score | P1, parity | #14 |
| Sharing with a coach (package / link) | P1, differentiator | #10 |
| Apple Watch scoring / bookmarks | P1 inputs; a full Watch app is a P1/P2 decision; Live Activity mirror first | #5, #13 |
| Voice bookmarks | P2 experiment (noise); voice-note transcription P2 | #25 |
| Live Activities / Lock Screen status | **P0** for recording status, P1 for processing | #5, #15 |
| Siri / App Intents | P1, parity | #15 |
| HealthKit workouts | P1, parity | #18 |
| Drill / ball-machine counters | P2, parity | #24 |
| Serve-target practice games | Later (needs ball tracking) | #30 |
| Doubles positioning | Manual doubles scoring P1; positioning Later | #16, #31 |
| Multi-angle / two-phone | Later | #29 |
| Padel / pickleball | Pickleball P2, Padel Later; sport-agnostic schema now | #27, #32 |
| Junior / parent mode, minors' privacy | P1, differentiator | #11 |
| Consent for recording opponents | P1, differentiator | #11 |
| Offline-first, no-account | **P0** | #1 |
| Transparent pricing | P1 decision | #19 |
| Battery/heat-aware deferred analysis | **P0** | #6 |
| CSV/JSON export | P1 (cheap, maybe v1) | #12 |
| UTR/USTA logging | P2 | #26 |
| Localization | P1 | #21 |
| Accessibility (VoiceOver-first review) | **P0** | #7 |
| Left-handed support | **P0** | #8 |
| *New:* checkpoint scoring at changeovers | **P0** (inside #2) | #2 |
| *New:* court-mode dark display + wrist status without a Watch app | **P0** | #5 |
| *New:* Space Saver + Drive quota math | **P0** | #9 |
| *New:* audio used for detection then discarded | **P0 (gated)** | #4 |
| *New:* competition mode (ITF Rule 31, no Watch) | P1 | #11 |
| *New:* diagnostics bundle (support without telemetry) | P1 | #20 |
| *New:* head-to-head history | P1 | #17 |
| *New:* iPad/Mac big-screen review | P1 | #22 |
| *New:* Foundation Models recap with number verification | P2 | #23 |
| *New:* Lock Screen quick record | P2 | #28 |

---

## 6. Proposed changes to the 20-screen spine (INFERRED; for the build ticket author)

| Screen (screens.json) | Change |
|---|---|
| 1 Welcome | "Get started" works with no account; add the line "Your videos stay yours: no hour limits, no ads." |
| 2 Onboarding | Keep handedness; add "Usually play: singles / doubles" and units (metric / imperial) |
| 4 Session setup | Add opponent handedness, a "Recording consent" row, a Competition mode toggle, a microphone choice ("Use for rally detection · audio not saved"), and computed storage from preset × planned length (not a hardcoded 3.2 GB) |
| 6 Live capture | Court-mode dark display; "Saved · 4 s ago"; changeover score entry (checkpoint); one-tap "Delete this recording" for withdrawn consent |
| 7 Import/processing | "Analyze now (keeps running in background) / when charging" |
| 9 Match overview | "Review 8 flagged points" opens the new **Point Review** deck; Share pack; head-to-head card |
| 10 Smart replay | Collapsed-gap chips on the timeline; pre/post-roll control; bulk rally select; VoiceOver point rotor |
| 19 Storage | Archive full vs rallies-only; Drive quota bar; per-session sizes; cache cleanup; 30 fps practice preset |
| 20 Settings | Parent mode, Competition mode, diagnostics export (opt-in), accessibility statement, language |
| **New: Point Review deck** | Swipe cards with loop previews, an undo bar and a progress counter "41 / 124" |
| **New: Share pack sheet** | Recipient (coach / opponent / me), contents, expiry, size estimate |

---

## 7. Open questions and required spikes

1. **Device spike:** does the iPhone Live Activity appear in the Watch Smart Stack *while the JOVRA app is foreground-recording*? If not, a minimal Watch app may be needed for status. (UNVERIFIED)
2. **Device spike:** what is the AirPods H2 stem-click and Apple Watch command range from the far baseline (about 24–30 m) to a fence-mounted iPhone? (UNVERIFIED)
3. **Labeled-footage benchmark** for audio+motion rally detection at public multi-court venues, indoors and in wind (≥10 sessions, ≥3 venues). (UNVERIFIED)
4. **API spike:** can the `drive.file` scope create permissions (share links, expiring user grants) on app-created folders, and read quota (`about.storageQuota`)? (UNVERIFIED)
5. Is background GPU for `BGContinuedProcessingTask` available on iPhone in iOS 27 (reported iPad-only in iOS 26)? (UNVERIFIED)
6. **Legal review:** whether local-first processing materially reduces COPPA/GDPR obligations for JOVRA; audio-recording consent rules for US states (two-party consent) on public courts; consent wording. (UNVERIFIED)
7. **Pricing decision** (#19): one-time versus annual Pro; whether to use US web checkout. (Decision for Jon)
8. **Minimum OS:** iOS 26 unlocks `BGContinuedProcessingTask`, `SpeechAnalyzer`, iPhone `HKWorkoutSession`, AirPods capture control and Foundation Models. iOS 27 appears to be shipping as of late Sep 2026 (Onform's "Made for iOS 27" note [S8]). SwingVision supports iOS 18+ [S2]. Recommend an iOS 26 minimum (INFERRED); confirm with adoption data.
9. The SwingVision hour quotas per tier (20 / 30 / 60 h) are third-party or user-reported. (UNVERIFIED)

---

## Sources

All accessed 2026-10-07.

- [S1] https://itunes.apple.com/lookup?id=989461317&country=us — SwingVision v11.9.67 (2026-09-27), 4.706 / 4,928 ratings, min iOS 18, 752 MB, 9 languages, description (features, Apple Watch / Siri / HealthKit, "$179.99/yr ($14.99/mo)" text), latest release notes (web subscription discounts, high-temperature recording, camera-interruption crash).
- [S2] https://apps.apple.com/us/app/id989461317 — SwingVision IAP list (Plus / Pro / Max prices), version history Nov 2025 – Sep 2026 (free tier 8 h/mo, Ground Mode, padel, Ball Tracer, USTA Connect, background export with Live Activity, Max family plan, overheating notice, playback/recording fixes), privacy label (Usage Data used to track), accessibility label (4 features), platforms (iPhone / iPad / Mac / Watch / visionOS).
- [S3] https://itunes.apple.com/us/rss/customerreviews/page=1..10/id=989461317/sortby=mostrecent/json — 490 SwingVision written reviews (Oct 2016 – Oct 4, 2026); year distributions, theme counts and paraphrased examples in §2.
- [S4] https://itunes.apple.com/lookup?id=1505604446&country=us — SevenSix v4.0.2 (2026-10-07), 4.19 / 68, 7 languages, Facebook login removed.
- [S5] https://apps.apple.com/us/app/id1505604446 — SevenSix IAP (subscription and pay-per-swing), accessibility not declared, tracking label, version history (AI Coach added 4.0.0 Jun 2, 2026; removed 4.0.1 Aug 6, 2026).
- [S6] https://itunes.apple.com/us/rss/customerreviews/page=1/id=1505604446/sortby=mostrecent/json — 11 SevenSix reviews (stuck analysis, screen auto-lock during recording).
- [S7] https://itunes.apple.com/lookup?id=1490334045&country=us — Onform v4.7.3, 4.786 / 8,666, pricing (individual $9.99 / $14.99; coach $19.99–$59.99), multicam, Watch, 21 languages.
- [S8] https://apps.apple.com/us/app/id1490334045 — Onform version history (4.6.0 Aug 2, 2026: accessibility claims, 20 languages, auto multicam angles; 4.7.0 Sep 26, 2026: voice-over transcription + AI summary, shared notes, iOS 27), accessibility label not declared, data-linked privacy label.
- [S9] https://itunes.apple.com/us/rss/customerreviews/page=1..10/id=1490334045/sortby=mostrecent/json — 297 Onform reviews (price, forced third-party login, metric units, lost access after lapse, share with coach).
- [S10] https://itunes.apple.com/search?term=<tennis+video+analysis | tennis+tracker | tennis+score | tennis+ai | pickleball+video | padel+video | padel+tracker | tennis+serve | tennis+coach | ball+machine | tennis+swing | tenniskeeper | racketly | swingiq | scorecam | tennis+ai+coach | tennis+watch>&entity=software&country=us — new 2026 entrants and descriptions: RallyTrim (id6794673497), TennisServe (id6800581766), Tennis Seed (id6760556364), OverRally (id6789373943), Slice (id6758102988), CourtzClub (id6757488806), Rally (id6780990982), SportArc (id6768219425), PB Vision (id6467020610), ScoreCam (id862175401); count of 2026 AI-coach apps.
- [S11] https://www.itftennis.com/media/15294/pat-25-037-approval-report-swingvision.pdf — ITF PAT-25-037 SwingVision approval (issued 31/10/2025): one or two devices, 60 fps, backend server, password-protected accounts, Watch not permitted in competition, accuracy not established.
- [S12] https://www.itftennis.com/media/15017/itf-performance-analysis-video-u18-august-2025.pdf — ITF U18 performance-analysis recording process (Aug 2025): dual parental written consent, withdrawal means deletion, recording made available to opponent, no posting, PAT approval for real-time analysis tech (Rule 31).
- [S13] https://developer.apple.com/videos/play/wwdc2025/227/ — WWDC25 "Finish tasks in the background": `BGContinuedProcessingTask` (user-initiated, progress required, title/subtitle, `.fail` strategy, background GPU on supported devices) and `BGProcessingTaskRequest` charger-only option.
- [S14] https://developer.apple.com/forums/thread/816774 — developer-forum report that background GPU `supportedResources` lacks `.gpu` on tested iPhones (iOS 26). Forum report, not documentation.
- [S15] https://developer.apple.com/videos/play/wwdc2025/253/ — WWDC25 capture controls: `AVCaptureEventInteraction`, volume / Action / Camera Control, AirPods (H2) remote capture free on iOS 26, long-press video.
- [S16] https://developer.apple.com/videos/play/wwdc2025/322 — WWDC25 HealthKit workouts on iPhone/iPad (iOS 26): `HKWorkoutSession`, `HKLiveWorkoutBuilder`, crash recovery, no built-in HR sensor.
- [S17] https://developer.apple.com/videos/play/wwdc2024/10204/ and https://developer.apple.com/documentation/lockedcameracapture — LockedCameraCapture extension (Lock Screen / Control Center / Action button launch; restrictions).
- [S18] https://developer.apple.com/videos/play/wwdc2024/10068 — iOS 18 / watchOS 11: iPhone Live Activities appear automatically in the Apple Watch Smart Stack; `supplementalActivityFamilies`.
- [S19] https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities — Live Activity duration (8 h active, plus up to 4 h on the Lock Screen).
- [S20] https://developer.apple.com/wwdc26/guides/ios/ — WWDC26 / iOS 27 developer guide: Foundation Models expansion (multimodal, Dynamic Profiles, PCC for Small Business Program), Core AI, App Intents schemas / View Annotations / testing, camera improvements.
- [S21] https://machinelearning.apple.com/research/introducing-apple-foundation-models — Apple on-device foundation model (about 3B parameters). Used via search summary for size and device scope.
- [S22] https://developer.apple.com/videos/play/wwdc2025/277/ — `SpeechAnalyzer` / `SpeechTranscriber`: on-device, long-form, distant-speaker transcription (iOS 26).
- [S23] https://www.macrumors.com/2025/06/21/ios-26-adding-two-new-wi-fi-features/ — Wi-Fi Aware framework for third-party peer-to-peer (iOS 26; iPhone 12+). Secondary source; WWDC25 session 228 is the primary.
- [S24] https://developer.apple.com/documentation/watchos-apps/enabling-double-tap — watchOS double tap via `handGestureShortcut(.primaryAction)`.
- [S25] https://developer.apple.com/videos/play/wwdc2023/10179/ (summary at https://wwdcnotes.com/documentation/wwdc23-10179-whats-new-in-core-motion/) — `CMBatchedSensorManager` 800 Hz accelerometer / 200 Hz device motion, requires an active workout, swing-impact example.
- [S26] https://developer.apple.com/documentation/avfoundation/avcapturedevice/systempressurestate-swift.property — capture system pressure levels; frame-rate throttling guidance; shutdown stops capture.
- [S27] https://support.apple.com/118431 — iPhone/iPad ambient operating range 0–35 °C; heat effects (dimming, charging stops, lower frame rates).
- [S28] https://developer.apple.com/documentation/avfoundation/avcapturemoviefileoutput — `movieFragmentInterval` (default about 10 s; file unplayable if interrupted before the first fragment; shorter initial interval advised).
- [S29] https://developer.apple.com/documentation/accessibility/representing-chart-data-as-an-audio-graph — Audio Graphs / `AXChartDescriptor`.
- [S30] https://support.apple.com/123073 — App Store accessibility information (9 feature labels; developer-declared).
- [S31] https://developer.apple.com/app-store/review/guidelines/ — 5.1.1(v) (no login unless account-based; in-app account deletion) and US storefront 3.1.1(a) external purchase links (May 2025 update, summarized at https://mjtsai.com/blog/2025/05/02/app-review-guidelines-updated-for-epic-anti-steering).
- [S32] https://9to5mac.com/2026/02/24/apple-expands-age-assurance-tools-as-new-app-store-requirements-roll-out-in-several-regions/ and https://techcrunch.com/2025/12/24/apple-pauses-app-store-changes-in-texas-after-court-blocks-age-assurance-law/ — Declared Age Range updates; Utah (May 6, 2026) and Louisiana (Jul 1, 2026) dates; Texas blocked. Secondary sources.
- [S33] https://www.whitecase.com/insight-alert/unpacking-ftcs-coppa-amendments-what-you-need-know — COPPA amendments (effective Jun 23, 2025; compliance Apr 22, 2026; biometric identifiers; retention). Law-firm summary, not the Federal Register text.
- [S34] https://www.dataprotection.ie/en/dpc-guidance/video-recording — Irish DPC: GDPR household exemption limits (publication to an indefinite audience is not covered).
- [S35] https://pmc.ncbi.nlm.nih.gov/articles/2653872/ — Fernandez, Mendez-Villanueva & Pluim (2006), Br J Sports Med, "Intensity of tennis match play": effective playing time about 20–30% on clay, 10–15% on fast courts; rallies about 5–10 s; rest 10–20 s.
- [S36] https://openaccess.thecvf.com/content/CVPR2024W/CVsports/papers/Decorte_Multi-Modal_Hit_Detection_and_Positional_Analysis_in_Padel_Competitions_CVPRW_2024_paper.pdf — multimodal (audio+video) padel hit detection; about 92% average F1 reported (via search summary; replicate before relying).
- [S37] https://developer.apple.com/videos/play/wwdc2020/10099/ — Action & Vision app: `VNDetectTrajectoriesRequest`, a stateful parabolic trajectory detection over frame sequences.
- [S38] https://pbvision.featurebase.app/p/shot-explorer-for-left-handed-players — PB Vision: models assume right-handed; handedness setting "Planned", 21 votes, posted Dec 23, 2024.
- [S39] https://support.universaltennis.com/en/support/solutions/articles/9000167002-post-a-score-self-posting — UTR self-posting: casual play, opponent confirmation, not counted toward Verified UTR.
- [S40] https://www.usta.com/en/home/about-usta/usta-connect/usta-connect-press-release.html — USTA Connect partner program (APIs for WTN / NTRP, SSO; vetted partners with established user bases). Via search summary.
- [S41] https://developers.google.com/workspace/drive/api/guides/manage-sharing — Drive permission types and roles; `expirationTime` (user/group only, maximum one year; folders reader-only).
- [S42] https://developers.google.com/workspace/drive/api/guides/api-specific-auth — Drive scopes, including narrow `drive.file` (also cited by the prior brief).
- [S43] https://support.google.com/accounts/answer/9312312 — a Google Account includes 15 GB shared across Gmail, Drive and Photos.
- [S44] https://www.videoproc.com/iphone-video-processing/iphone-video-size-per-minute.htm — about 90 MB/min for 1080p60 HEVC (secondary source quoting iOS Settings; verify on device).
- [S45] https://developer.android.com/about/versions/16/features/progress-centric-notifications — Android 16 `Notification.ProgressStyle` progress-centric notifications (Live Updates) for the Android port.
- Local inputs: `/Users/IDC2.5/jv/docs/handoff/JON-ORIGINAL-PROMPT.md`, `/Users/IDC2.5/jv/docs/handoff/CLAUDE-BUILD-PROMPT.md`, `/Users/IDC2.5/jv/design-reference/brief/research.md`, `/Users/IDC2.5/jv/design-reference/brief/product-brief.md`, `/Users/IDC2.5/jv/design-reference/brief/screens.json`, `/Users/IDC2.5/jv/design-reference/brief/implementation-states.md` — founder intent, the prior brief and the 20-screen spine being extended.
