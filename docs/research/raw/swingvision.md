# SwingVision deep dive (primary benchmark)

Research date: 2026-10-07. App Store id 989461317. Researcher: JOVRA research agent.
Builds on and checks `design-reference/brief/research.md`. Section 10 lists what changed from that brief.

**Labels.** **OBSERVED** means I saw it in a cited source. **INFERRED** means it is my own reasoning. **UNVERIFIED** means it is claimed or likely but I did not confirm it. Review content is paraphrased. Reviews are user reports, not measured failure rates.

**Method.**
- iTunes lookup API, in the US and 6 other storefronts.
- The App Store web page, including its embedded JSON: IAP list, rating histogram, privacy labels, platforms, version history and featured reviews with developer responses.
- Wayback Machine snapshots of the App Store page from Oct 2024 and Oct 2025, for older release notes.
- All 10 pages of the App Store customer-review RSS. This gave 490 written reviews, dated 2016-10-20 to 2026-10-04.
- All 37 App Store screenshots (iPhone, iPad, Mac, Watch, iMessage), viewed as images.
- The official site, read in a browser because it renders client-side: plans comparison, FAQ, how-to guides, Teams, Swing Court, Swing Stick shop and the newsletter archive.
- The ITF Player Analysis Technology (PAT) approval report.
- One peer-reviewed validity study.
- Tennis.com and TennisNerd coverage.

---

## 0. Decision-relevant summary

1. **The 4.7 headline hides a much harsher written-review signal.** The listing shows 4.7 from 4,928 ratings, and 86.7% of them are 5-star (OBSERVED). The 165 written reviews from the last two years average **3.39**. In 2026 so far they average **2.98**, and 1-star reviews are 24% of the window (OBSERVED, computed from the RSS).
   - INFERRED: most of the rating comes from star-only taps. Text reviewers are the dissatisfied minority, and they are the ones naming specific failures.
2. **The main complaint is reliability, not features.** About 1 in 5 recent written reviews describe one of these failures (OBSERVED, manual coding):
   - a recording that stopped or was lost
   - an Apple Watch that said "recording" when the phone was not
   - stuck uploads or processing
   - failed exports
   - playback that broke after an update

   Two years of release notes are dominated by fixes for exactly these (Section 5).
3. **Price and paywall moves are the second complaint.** Monthly recording-hour caps by tier are 8, 16, 30 and 60 hours (OBSERVED). Pricing and access have changed several times:
   - Free users can only open recordings from the last 7 days, even when the file is still on the device.
   - Ads were added to the free tier in Jan/Feb 2026.
   - Features were removed from mid-tier plans.
   - Trial flows charged a full year.
4. **Accuracy is "good enough for review, not for trust".** The vendor claims 97% for close line calls (within 10 cm) and speed within 10% (OBSERVED, vendor). One independent study (n=5 elite juniors) found good-to-very-good validity (OBSERVED). Users report:
   - AI scoring about 80–90% correct
   - unreliable player identification
   - rallies that get cut
   - speed outliers

   The ITF approval explicitly does **not** certify line-call accuracy (OBSERVED).
5. **Correction exists but is slow and buried.** Edit Point, then Point Details, lets you flip the point winner (OBSERVED, developer response). Users still describe:
   - minutes of manual player identification
   - edits that jump to the wrong shot
   - no way to watch the raw video between detected points
   - no bulk operations
6. **Heat is a vendor-side problem more than a review theme.** It appears in release notes (11.9.47, 11.9.65, 11.9.67) and the FAQ (overheating shows up as a "System Pressure" stop, and the FAQ recommends an umbrella). It is almost absent from written US reviews: zero overheating mentions in two years (OBSERVED).
7. **The biggest structural openings for JOVRA (INFERRED):**
   - local-first ownership of the original video, with no time or tier gating
   - no recording-hour cap
   - recording that keeps going even when analysis fails
   - correction built into replay
   - honest confidence labels
   - Android (SwingVision has no Android app; the FAQ suggests buying a used iPhone SE)

---

## 1. Current listing facts (US, 2026-10-07)

| Field | Value | Label |
|---|---|---|
| Name | SwingVision: Tennis Pickleball | OBSERVED (lookup) |
| Seller | SwingVision, Inc. (Saratoga, CA). CEO and co-founder Swupnil Sahai | OBSERVED (lookup, ITF report) |
| Rating | 4.70556 (shown as 4.7) | OBSERVED |
| Rating count | 4,928 | OBSERVED |
| Histogram (5 to 1 star) | 4,275 / 290 / 113 / 65 / 185, which is 86.7% / 5.9% / 2.3% / 1.3% / 3.8% | OBSERVED (page JSON `ratingCounts`) |
| Other storefronts | GB 4.61 (428) · AU 4.65 (299) · CA 4.79 (425) · DE 4.53 (210) · FR 4.63 (198) · JP 4.55 (205) | OBSERVED (lookup) |
| Price | Free with IAP | OBSERVED |
| Version | 11.9.67, released 2026-09-27 (11.9.66 was 2026-09-23 with identical notes) | OBSERVED |
| First release | 2016-10-18 | OBSERVED |
| Size | 752 MB (752,001,024 bytes) | OBSERVED |
| Minimum OS | iOS 18.0 and an A12 Bionic or later chip | OBSERVED (listing) |
| Real-time analysis | Needs an A13 or newer chip (iPhone 11 / SE 2020 or later, 2020 iPad Pro or later) | OBSERVED (FAQ, guides) |
| Platforms | iPhone, iPad, Mac (Catalyst; needs macOS 15+; Max/Ultra M-chips recommended for exports), Apple Watch (Series 6 / SE 2nd gen+, watchOS 11+), iMessage sticker pack | OBSERVED (listing media, FAQ) |
| Android | None. No official Play Store listing; only unofficial "guide" apps appear in Play search. FAQ says it is "working closely with Google engineers" and suggests a used iPhone SE, or importing footage via Mac/iPad | OBSERVED |
| Languages | EN, FR, DE, IT, JA, KO, PT, ZH, ES | OBSERVED |
| Age rating | 4+ | OBSERVED |
| Categories | Sports, Health & Fitness | OBSERVED |
| Badges | Editors' Choice on the listing. Screenshots say Apple Design Award (June 2023) | OBSERVED |
| Capabilities | Siri and Wallet are listed. The purpose of Wallet is UNVERIFIED | OBSERVED |
| Accessibility labels | Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion. **No VoiceOver, Voice Control, Larger Text or Captions declared** | OBSERVED |
| Privacy label | "Data Used to Track You": Usage Data. "Not Linked to You": Usage Data and Diagnostics (analytics, personalization, app functionality) | OBSERVED |
| Official partners (per listing) | Official player and ball tracking app of Tennis Australia, LTA and ITA. Backed by Andy Roddick and Lindsay Davenport | OBSERVED (vendor claim) |
| Scale claims | "Over 200,000 players & coaches" record each month; ">$10m" raised (Sony, Tennis Australia, ATP/WTA pros); "500K+ happy players"; trained on "500 million shots", while newsletters say "86 million tracked shots" | OBSERVED (vendor; the two shot counts are inconsistent) |

## 2. Subscriptions, prices, caps

### 2a. App Store IAPs (US)

| IAP | Price |
|---|---|
| Plus Monthly | $14.99 |
| Plus Yearly | $95.99 |
| Pro Monthly | $24.99 |
| Pro Yearly | $179.99 |
| Max Monthly | $39.99 |
| Max Yearly | $299.99 |

OBSERVED (page JSON "In-App Purchases").

The description says Pro is "$179.99 per year ($14.99 per month)". That $14.99 equals the annual price divided by 12; the actual Pro Monthly IAP is $24.99. INFERRED: the description quotes a monthly equivalent, so it reads like a cheaper monthly plan than really exists.

### 2b. Web prices (Fall Sale banner, swing.vision/subscribe/compare)

| Plan | First-year web price | Shown per month | Year 2 renewal | Bundle |
|---|---|---|---|---|
| Plus | $77.99/yr | $6.49 (list $7.99) | $95.99/yr | Swing Stick + Plus $113.99 |
| Pro | $143.99/yr | $11.99 (list $14.99) | $179.99/yr | Swing Stick + Pro $143.99 (stick "free") |
| Max | $239.99/yr | $19.99 (list $24.99) | $299.99/yr | Swing Stick + Max $239.99 |

All OBSERVED. Also observed:
- a 60-day money-back guarantee on yearly-plus-stick bundles
- 30 days on a stick bought alone
- "Swing Stick + 1 Month of Pro" for $49.99

Version 11.9.67 (Sep 2026) added "web subscription discounts now show in-app & upgrading takes you straight to checkout" (OBSERVED). INFERRED: this steers users to web checkout, avoiding App Store commission.

### 2c. Feature matrix (compare page)

| Feature | Free | Plus | Pro | Max |
|---|---|---|---|---|
| Monthly recording hours | 8 | 16 | 30 | 60 (per family member) |
| Video trimming (dead time removed) | yes | yes | yes | yes |
| Shot stats and heatmaps | yes* | yes | yes | yes |
| Shot-by-shot analysis, raw data export | – | – | yes | yes |
| Scoring and match stats | – | – | yes | yes |
| Full-court line calls | – | – | yes | yes |
| Unlimited sharing (no logos, highlights longer than 5 min) | – | – | yes | yes |
| Unlimited cloud storage ("every recording, forever") | 7-day access only | yes | yes | yes |
| Strategy Insights (best and worst patterns) | – | – | – | yes |
| 4K video | – | – | – | yes |
| Family Sharing (up to 5) | – | – | – | yes |

OBSERVED (compare page; the free column comes from the Jan 2026 newsletter and release notes 11.9.49/50).

Free tier as of Jan/Feb 2026: 8 h/month (up from 2 h) in HD, Apple Watch line challenges and real-time audio line calls. In exchange, users get only the last 7 days of recordings, a 5-minute export cap and "occasional in-app ads" (OBSERVED).

\*Version 11.9.12 (Apr 2025) fixed shot stats being wrongly locked on "Basic" accounts.

**Price and tier history (OBSERVED unless marked):**
- **Jan 2023:** a developer response cites Pro annual at $149.99.
- **Mar 2023:** sessions older than 30 days were locked for non-Pro users. Later, v10.1 grandfathered "lifetime cloud storage" for prior customers (developer response, Apr 2023).
- **Jan 2024:** Max launched at $29.99/mo, billed $359.99/yr.
- **2025:** a "Semi-Pro" tier existed. Reviews say its hours were cut and its shot filters removed mid-subscription (Mar 2025). The developer partly reversed the hours cut.
- **Sep 2025:** 11.9.33 introduced Pro Monthly.
- **Nov 2025:** 11.9.43 made Max a family plan for 5.
- **Reviewer account of Pro yearly:** about $100, then $120, then $180 (May 2025).
- INFERRED: "Plus" replaced "Semi-Pro". UNVERIFIED.

**Teams:** price on request. 60 h/month per player, lifetime cloud storage, team dashboards, live streaming of "15 dual matches per season" in 1080p with scoreboard. "AI Officiating (2025)" is still shown as coming soon (OBSERVED, swing.vision/teams).

**Swing Court:** a permanent facility install with one camera, a kiosk, two power cables and about an hour of installation, sold as an annual license. It is pitched as revenue for clubs: ELC, lessons, leaderboards, live streaming and paid video unlocks (OBSERVED).

**Coach Reviews (Jun/Jul 2025):** a marketplace of certified coaches (RSPA/USPTA, Tennis Australia, Tennis Canada). Each review has timestamped comments in the video plus a screen recording, delivered within 7 days. Price not shown (OBSERVED; price UNVERIFIED).

## 3. Feature inventory

All OBSERVED, from the listing, release notes, guides, FAQ and screenshots, unless marked.

**Session types and sports.**
- Sport is selected at the top of the Record tab: tennis, pickleball (since Nov 2023) and padel (available to all since 11.9.60, Jun 2026).
- Session types: Match, Rally, Serve Practice, Ball Machine (including a doubles ball-machine variant where alleys count as in, from 11.5.2). Singles or doubles.
- Ground Mode, Fence Mount and Swing Stick are "equipment" choices that unlock different features (Section 4).

**Match tracking and scoring.**
- AI Scoring builds a scoreboard. The user enters only the final set scores at the end.
- Alternatively, score on Apple Watch in one of three modes: Game by Game, Point by Point, or Point by Point+.
- Watch scoring uses swipe gestures (Fault / Service winner), undo, and Favorite Point for highlights.
- The how-to says the Watch gives "the most accurate stats and scoreboard".
- Match stats include: winners, unforced errors, forehand/backhand winners and errors, break points saved and won (shown as butterfly bars), rally length, serve stats and Point History with how each point finished.
- A "Switch point winner" control has existed since 2024. Its path is Edit Point, then Point Details (developer response, Sep 2024).

**Line calling.**
- Live Line Calls (beta Dec 2024): the phone or a Bluetooth speaker calls "Out!" in real time. Since 11.9.36 the audio is standardized to English.
- Line Challenges: the last few shots can be reviewed from the Watch (Digital Crown frame-by-frame, double-tap zoom), from a second iPhone or Android phone acting as Remote Control, or from an on-court iPad.
- The challenge view shows a ball-trail composite and an "Out!" or "In" badge (screenshots).
- Coverage depends on equipment: Fence Mount gives half-court line calls; Swing Stick unlocks full-court line calls.
- ITF tournament format: three incorrect challenges per set; the last four shots can be challenged.

**Highlights and auto-edited replay.**
- Dead-time removal is the core feature.
- AI Highlights and winner/error filters arrived in 11.6 (May 2024); Doubles AI Highlights in 11.9.31 (Aug 2025).
- Filters can be chained point-by-point and shot-by-shot, presented as a natural-language sentence builder (screenshot 7).
- Exports: scores overlaid, auto-pan, vertical exports with the ball kept centered (Ground Mode), Ball Tracer animation (11.9.60), redesigned scoreboard (11.9.63/64).
- Background exports with an iOS 26 Live Activity (11.9.56); full-match background exports (11.9.64).
- Watermark removal is Max-only (11.9.27).

**Shot placement and stats.**
- Heatmaps show placement and hitting position, with depth zones (screenshot: 33% / 22% / 45% across the court, 82% / 18% deep and short).
- Overall stats: shots in %, shots per hour, longest rally, % of rallies above 5 shots.
- Serve stats: in % and average speed for Ad and Deuce.
- Returns, groundstrokes (forehand and backhand in %).
- Spin types: topspin, slice, flat, and kick for serves.
- Shot types: forehand, backhand, serve, volley, overhead.
- Comparison with the previous session is shown as green or red deltas.
- Stats can be exported (11.9.65 fixed a stats-export crash).
- Users can tap an opponent's avatar to "scout" their stats.

**Speed.**
- Speed for every trajectory. It is defined as average speed along the flight, about 10% below a radar gun (FAQ). Units: mph or km/h.
- Overlays for shot speed and stroke can be toggled; exports respect the settings since 11.9.65.

**Coaching and insights.**
- "AI Coach / AI Coaching" (Jun 2024): best and worst serve and return strategies, with playable evidence clips. It covers singles only; doubles was promised "later this year" and is not confirmed shipped (UNVERIFIED).
- "Strategy Insights" is Max-only.
- Goals, Trends: about 13 metric sparklines with 4W / 3M / 6M / 1Y / YTD ranges.
- Swing Streak (100+ shots a week).
- Monthly Challenges with rewards (Jun–Aug 2026).
- Data-driven blog content benchmarking NTRP levels from aggregate user data (Sep–Oct 2026).

**Practice and drills.**
- Goal Mode / Target Practice: the user picks numbered target zones.
- Real-time audio feedback (shot speed, accuracy, in/out chime), per half of the court in Rally mode (May 2026).
- Apple Watch vibrates when a shot lands outside the target (11.9.63).
- Ball Machine and Serve Practice modes; pickleball versions added in 11.9.43 (Nov 2025).

**Apple Watch.**
- Camera preview and zoom for setup, start and stop, scoring, challenges, favorite last rally, Goal Mode tally, heart rate.
- Saves workouts to Activity and HealthKit; Siri start.
- A Jul 2026 review says watch-only shot analysis without a phone recording was removed (user report).

**Multi-device.**
- One or two recording phones, one behind each baseline (ITF report).
- An on-court iPad as the officiating and score UI.
- Remote Control from another iPhone or Android phone, paired by QR code (Mar 2024). It needs Wi-Fi or cellular.
- Mac app for imports, review and exports.
- Live streaming: Teams, and courts in "Ready mode".

**Sharing, export and social.**
- A share link plays on the web for non-users; a May 2025 review says the video is black in Chrome.
- Tagged players get the session on their own profile.
- Privacy levels: Public, Friends or Participants, set per profile and per session.
- Post directly to Stories and Reels (2023). Shareable stat card (Oct 2026 blog).
- Group Chats with nearby active subscribers at a similar level (11.8, Oct 2024).
- Leaderboards (Mac screenshot "compete against the world"); referrals with QR (11.9.31).
- USTA Connect with verified NTRP/WTN (11.9.61); UTR-P for pickleball (11.9.21).
- Sign in with Google (11.9.61) and Facebook (a review says broken, Apr 2026).

**Import.** GoPro, Android and other files on iOS or Mac. Recommended: 1080p at 60 fps, from behind the baseline, at least 5 ft up, both baselines visible. On iOS the app must stay in the foreground and the screen must stay unlocked while importing (OBSERVED, import guide).

**Cloud.**
- Uploads happen over Wi-Fi only.
- The app auto-removes local copies older than 1 week once they are backed up. "Optimize Storage" deletes all cloud-synced local videos.
- Original upload versus "trimmed" upload: a user says "Upload trimmed Video" was removed (Aug 2025).
- Recording files are 70% smaller and uploads 3x faster since 11.9.27/28 (Jul 2025).

**Coach and team.** Teams dashboards, Coach Reviews marketplace, "Become a Coach" program, remote coaching (2022). Coaches and parents are explicitly targeted in the description.

## 4. How it captures

**Camera and processing (OBSERVED, ITF PAT-25-037 report, issued 2025-10-31 against v11.9.6).**
- Rear camera at **60 fps**.
- Several ML models track the ball, the court and the players.
- Each trajectory records the ball's 3D position at racket contact, net contact and bounce, plus shot type, spin type and speed.
- Data goes to a backend server over Wi-Fi (cellular as a fallback).
- Ball trajectories go to the on-court tablet for line calls.
- Devices must share an account to pair.

**On-device real-time analysis.** Works on A13 or newer (FAQ), and has been "patented" since 2022 (vendor claim).

**Resolution.**
- HD by default; 4K on Max.
- Import resolution limits exist: 11.9.46 improved the error message, and 11.9.48 fixed some 4K imports.
- A Jan 2026 user asks for a 30 fps option outside line-call mode. INFERRED: 60 fps is effectively fixed.

**Orientation and lens.**
- Setup screens are landscape (OBSERVED in the guide images and Watch preview).
- Controls: HD/4K, Zoom (1.0x shown) and Flip camera.
- 1x zoom is recommended for live line calls.
- A clip-on wide-angle lens is sold for phones without an ultra-wide camera that cannot see the whole court at 1x.
- INFERRED: the app can use the ultra-wide where available.
- A Jul 2026 review says recording now starts on the front camera and cannot be flipped from the Watch.

**Placement (OBSERVED, how-to guide).** Three tiers:

| Tier | Setup | What it unlocks |
|---|---|---|
| **Ground** | Lean the phone against a water bottle, centered behind the baseline; align the top of the net inside an on-screen pink band | Trimming, rally and stroke filters, vertical highlights. No stats. Added in 11.9.54, Mar 2026 |
| **Fence Mount** | Clamp centered behind the baseline; align the near service line inside the pink band | Adds speed, depth, consistency and half-court line calls |
| **Swing Stick** | Patented telescoping fence pole that "fits in your sports bag"; a green full-court outline with a check confirms framing | Full-court line calls |

General guidance:
- Place the camera centered and high ("top of the fence"), with the sun behind it and on the side opposite a windscreen.
- Avoid the net tape overlapping the far service line or baseline.
- Keep a few feet behind each baseline visible.

Setup aids:
- "Audio-Guided" versus "Manual" setup toggle, as seen in the guide image.
- A May 2026 review says the audio auto-setup was removed and a second device is now needed to check alignment. This conflicts with the guide image; UNVERIFIED which is current.
- Court-angle feedback during setup (11.9.30, Aug 2025).
- Watch camera preview, and "Remote Control" from a second phone.

Swing Stick physical specs (height, weight) are UNVERIFIED; they were not found on the shop page.

**Power, heat and storage (OBSERVED, FAQ).**
- At least **80% battery** for a 2-hour session (suggests a battery case).
- At least **10 GB free**.
- Turn on **Focus Mode**, with an automation guide, so calls and alarms don't interrupt.
- The hazard icon on a session thumbnail means iOS ended the recording. The four causes the FAQ lists:
  - App Backgrounded
  - Audio in Use
  - Low Battery (below 5%)
  - **System Pressure, meaning overheated.** The FAQ recommends attaching an umbrella to the mount.
- Pre-record low-storage alerts (11.9.56), with loosened thresholds (11.9.62).

**Mounts and accessories.** Swing Stick ($50 value; second phone holder included), fence-mount clamp, umbrella, wide-angle lens, tripod (recommended for indoor players since 11.9.21). Reviews complain about stick stability when it is pushed through a fence hole, and that the clamp covers buttons on iPhone 17-series phones (OBSERVED, user reports).

## 5. Release-note history, Oct 2024 to Sep 2026

**Coverage.** I have 52 releases with notes:
- 11.8 to 11.8.1 (Oct 2024)
- 11.9.3 to 11.9.36 (Jan to Sep 2025), from the Wayback snapshot of 2025-10-05
- 11.9.43 to 11.9.67 (Nov 2025 to Sep 2026), from the live page

Two gaps are UNVERIFIED: 11.8.2 to 11.9.2 (about Oct 2024 to Jan 2025) and 11.9.37 to 11.9.42 (Oct to Nov 2025). Cadence: about one release every 10–14 days (INFERRED from version numbers and dates).

### By theme (OBSERVED; version, month)

- **Recording durability and interruptions:**
  - 11.9.47 (Dec 2025): crash when recording ended "under critical system pressure"; back-to-back recording stability.
  - 11.9.56 (May 2026): "mid-recording crashes or lost video recordings".
  - 11.9.58: saving and uploading interrupted recordings.
  - 11.9.59: a finished recording reappearing as in progress after force-quit.
  - 11.9.64 (Aug 2026): "interrupted recordings being saved without any playable video"; in-progress recordings disappearing.
  - 11.9.65: crash while recording live-streamed sessions.
  - 11.9.67 (Sep 2026): crash during camera interruptions; recordings ending early when Target Practice settings change.
- **Heat:**
  - 11.9.47: system-pressure crash.
  - 11.9.65: spoken notice when real-time audio feedback is disabled "due to device overheating". INFERRED: they shed analysis load to keep recording.
  - 11.9.67: "improved recording stability in high temperatures".
- **Camera focus:** constant refocusing on 2024/2025 iPhones (11.9.45), touch refocus blocked during recording (11.9.47), unwanted refocusing on iPhone 16+ (11.9.56).
- **Storage and data loss:**
  - 11.9.9 (Mar 2025): local videos deleted when switching accounts.
  - 11.9.64: videos awaiting upload deleted when storage was low.
  - Low-storage warnings in 11.9.56, 11.9.62 and 11.9.67.
  - Imported files not cleaned up after a failed import (11.9.59).
- **Upload and sync:**
  - Backups dashboard (11.8/11.8.1).
  - Uploads made chronological (11.9.24); upload stability (11.9.24/25); 3x faster and 70% smaller files (11.9.27/28).
  - Retrying stuck uploads and uploads freezing partway (11.9.31); uploads stuck (11.9.51); one-tap retry (11.9.59); stuck at 100% (11.9.62).
  - Sessions stuck on the processing screen (11.9.65); stats sync stuck (11.9.67).
- **Apple Watch:**
  - Phone/watch data sync (11.9.21).
  - Watch sessions stuck after undoing match point (11.9.52).
  - Ending from the Watch switched the scoring mode (11.9.58).
  - Watch froze at the end of long matches (11.9.62).
  - Watch showed "Recording Failed" instead of the preview (11.9.64).
  - Watch-only sessions stuck "Live" (11.9.65). This matches a user's session showing 600+ hours.
  - Connection reliability (11.9.67).
- **Accuracy:**
  - 11.9.3 (Jan 2025): "new AI models with vastly improved line calling & auto scoring".
  - Half-volley line calls, back-to-back volleys, serves misdetected as overheads (11.9.4/6).
  - Kick shown as topspin (11.9.8/9, again 11.9.59).
  - Doubles player identification (11.9.13); AI Scoring reliability (11.9.25).
  - Pickleball tracking revamp (11.9.43); pickleball line calls (11.9.53).
  - Serve speed (11.9.58).
  - Serves dying at the net scored "in" (11.9.63).
  - Auto-scoring at 5–6 and volleys called out by audio (11.9.64).
- **Editing and correction:**
  - Click directly on the heatmap to fix placement (11.7.1).
  - Start time of serves can be adjusted (11.9.27).
  - Faster shot-edit replay and heatmap taps (11.9.63).
  - Favorites and challenges are kept on reprocess (11.9.63).
  - Scoreboard disappearing after editing timing (11.9.65).
  - Playback buttons covering edits (11.9.67).
- **Exports:**
  - 4K exports dropping to 30 fps (11.9.4); over-saturation (11.9.13); stability (11.9.55).
  - Background exports (11.9.56/64); blurry overlays (11.9.62).
- **Monetization changes** shipped as "features": Pro Monthly (11.9.33), new free tier (11.9.49/50), Max family plan (11.9.43), web discounts in-app (11.9.67).
- **New features:**
  - Coach Reviews (11.9.25); court-angle feedback (11.9.29/30).
  - Doubles AI Highlights (11.9.31).
  - Ground Mode (11.9.54); new Record tab (11.9.57).
  - Padel, Ball Tracer and Monthly Challenges (11.9.60).
  - USTA Connect and Google sign-in (11.9.61).
  - Target Practice haptics (11.9.63).

**Takeaway (INFERRED).** For two years the vendor has repeatedly patched the same failure classes: lost or truncated recordings, upload and processing stalls, and Watch/phone state disagreements. This points to an architecture where recording, analysis, upload and Watch state are tightly coupled, so a failure in one corrupts the session. JOVRA's brief already separates the video, analysis, review and archive states. That separation is the single most important architectural differentiator to protect.

## 6. App Store screenshots: what they emphasize

OBSERVED. I viewed all 10 iPhone (6.5"), 10 iPad, 6 Mac, 7 Watch and 4 iMessage screenshots.

**Visual system.** Bright green gradient panels, dark-mode UI inside phone frames, and callout cards that pop out of the device. The accent colors are green (good) and orange (bad / opponent).

**iPhone order (captions paraphrased).**
1. Credibility panel: Apple Design Award June 2023, investors Roddick and Davenport, press (BBC, NYT, Tennis Channel, Forbes), split court image with speed tags.
2. AI line calling to settle disputes: Line Challenge screen with a ball-trail composite, an "Out!" badge and a frame slider.
3. TV-quality highlights: a rally video with a mini-court placement inset and a "Backhand Volley · 11 MPH" tag, plus Favorited Rallies and Longest Rallies reels. The footage is pickleball.
4. Your shot placement: a dense placement heatmap with depth and width percentages, Shot Stats / Smart Insights / My Notes tabs, and overall stats (78% in, 276 shots per hour, longest rally 18, 41% of rallies above 5 shots) with deltas.
5. Auto-generated match stats: doubles names (4 players), score 4-6 6-3 7-5, and butterfly bars for winners, UE, FH/BH winners and errors, break points saved and won.
6. Strengths and weaknesses: per-player avatars, serve in % and average speed for Ad and Deuce, returns, groundstrokes, deltas.
7. Focus on important points: a **natural-language filter builder** that reads like a sentence (game points, rallies above 5 shots, a chosen player, finishing shot, server), with colored token chips.
8. Practice with audio feedback: Goal Mode with 4 target zones and toggles for shot speed, accuracy and in/out chime.
9. The whole story of any point: Point History list with set score per point, finishing shot type (winner or UE icon) and play buttons.
10. Improvement over time: Trends showing 1st-serve speed over 1 year, plus sparklines with values for about 12 metrics.

**Watch screenshots.**
- "Official review" challenge with an Out badge.
- Zoom and alignment with a pink band ("Align the near service line…"), for tennis and pickleball.
- Scoring screens with Fault / Service Winner side swipes, avatars, heart rate, undo and stats.
- Goal Mode tally (57/70, 81%).
- Health rings with "Favorite Last Rally".

**Mac screenshots.** Shot placement, highlights, match stats, trends and a **global leaderboard** ("Shots Hit"). **iMessage:** branded tennis-ball stickers.

**What this tells us (INFERRED).**
- SwingVision sells on three things: line-call dispute resolution, broadcast-style highlights, and stats density.
- It never shows correction, data ownership, recording reliability or storage.
- Its screenshots overstate how ready doubles and pickleball are, compared with what reviews report.
- JOVRA can differentiate visually by showing evidence and confidence ("needs review"), with source video one tap from every number. The planned screens already do this (shot-map legend "Needs review", Serve Lab "Estimated").

## 7. User reviews

### Dataset

490 written US reviews from the RSS (10 pages, sorted most recent), dated 2016-10-20 to 2026-10-04. The analysis window is **2024-10-01 to 2026-10-04: n = 165**.

| | Count |
|---|---|
| 5 stars | 72 |
| 4 stars | 16 |
| 3 stars | 21 |
| 2 stars | 17 |
| 1 star | 39 |
| **Mean** | **3.39** |

By year: Q4 2024 is 3.44 (n=16), 2025 is 3.60 (n=99), 2026 so far is **2.98** (n=50). The yearly mean across all written reviews peaked in 2022 at 4.49 (n=68) and dropped to 3.23 in 2023 (OBSERVED). INFERRED: the 2023 drop coincides with the March 2023 30-day history lock.

**Coding method.** I read every review in the window and coded it by hand, with keyword assistance. A review can carry several themes. Counts are approximate (about ±3).

### Praised strengths (from roughly 88 four- and five-star reviews)

1. **Seeing yourself on video** (about 25): technique, footwork, "reality versus perception", slow motion and frame-by-frame.
2. **Stats, placement and heatmaps, filters** (about 20): self-described "data nerds"; scouting opponents; progress against match objectives.
3. **Coaching, junior and parent use** (about 12): PTR/USPTA pros, parents of college-bound juniors, film sessions with students.
4. **Dead-time removal** (about 10): a 2-hour match watched in 15–20 minutes. Several call this worth the price on its own.
5. **Sharing** with partners and coaches, and fun "blooper" highlights (about 8).
6. **Line calling** liked (about 6), especially live audio "Out" calls.
7. **Apple Watch scoring** as an on-court habit (a few). One long-time user values point-by-point wrist scoring as a mental reset between points.

### Recurring complaints (whole window, any rating)

| Theme | Approx. count (of 165) | Representative paraphrased reports (date, stars) | Status per release notes |
|---|---|---|---|
| **Recording, processing, upload, export or playback reliability** | ~35 | Long matches detected as only ~10 points; re-processing failed on low memory (2026-10, 3★). Recording stopped after 10 seconds of a 1-hour session; user wanted the raw file kept (2026-07, 1★). Recording froze in every match for a year on iPhone 17 Pro (2026-03, 1★). Uploads stuck for days on Max (2025-10, 1★). Exported videos dark and over-compressed after an update (2025-02, 1★). App cache grew to 20 GB with no way to clear it except reinstalling (2025-07, 1★). Old videos skip and glitch (2024-12, 2★) | Repeatedly patched (Section 5); still reported in Sep–Oct 2026 |
| **Price, paywall, tier changes, ads, billing** | ~28 | $180/yr too much for occasional players (several). Blocked at 4 of 30 Pro hours, then upsold a $19.99 tier (2026-10, 1★). Stick bundle with "1 free month" charged $179 (2026-04, 1★). Second "free trial" charged $180 at once (2025-07, 3★). Free users can't open videos older than 7 days even when on device (2026-05, 1★). Ads at the end of videos (2026-02, 1★ and 2★). Semi-Pro lost hours and filters mid-year (2025-03, 1★). Constant reminders of locked higher-tier features (2025-02, 4★) | Ongoing; driven by business model |
| **AI scoring, point detection, rally trimming** | ~18 | Scoring "about 80%" right, same for trimming and processing (2026-02, 3★). AI tags 85–90% correctly; fixing mis-tags takes serious time (2025-06, 4★). Clips cut off too soon (2025-11, 3★). Rallies skipped up to about 2 minutes, with no way to watch the gaps (2025-05, 2★). Auto scoring never worked across about 20 matches (2024-12, 1★) | Model updates in 11.9.3, 11.9.25, 11.9.63/64 |
| **Apple Watch reliability** | ~16 | Watch said recording but only 1 of 3 sets was captured (2026-08, 1★). Watch start button does nothing about half the time (2025-10, 1★). Watch app keeps hijacking the watch face (2026-06, 1★). Watch Series 5 support dropped, then restored (2026-01, edited to 5★) | Many fixes; still reported in Aug 2026 |
| **Support quality** | ~16 negative / ~5 positive | AI chatbot gate, generic replies, waits of days to weeks, no phone support. Some praise named agents and fast refunds | n/a |
| **Pickleball immaturity** | ~11 | Doubles shot attribution wrong; everything labeled "flat"; speed outliers (pickleball serves over 100 mph); no ball-machine or serve mode until Nov/Dec 2025; one says PB Vision is better | Revamped tracking in 11.9.43; line-call tweaks in 11.9.53 |
| **Setup and alignment difficulty** | ~10 | "Court Undetected" on iPad without a Watch (2026-04, 1★). Alignment hard without a second device after audio setup was removed (2026-05, 2★). iPad zooms into the near baseline (2025-01, 1★). Stick stability and clamp fit (2024–2025) | Court-angle feedback added in 11.9.30; Ground Mode in 11.9.54 |
| **Editing and correction friction** | ~10 | Editing a shot jumps to a random shot; no "uncheck all rallies" (2026-07, 4★). Correcting a missed point takes about as long as manual editing (2026-09, 1★). Manual player identification works about 20% of the time and takes 5–10 minutes (2026-03, 4★). Needed to mark players for nearly every point (2026-05, 2★). Wants to edit the score while watching (2025-10, 4★). Wants 10-second skip (2025-01, 4★). Couldn't find the flip-winner button (2024-09, 5★) | Incremental fixes only |
| **Speed accuracy** | ~8 | Serve speeds over 110 mph that weren't real (2025-08, 3★). One user compared against Hawk-Eye: serves within about 2%, groundstrokes about 10% low; says the 99% line-call claim is misleading because it includes easy calls (2025-11, 4★). Identical shots get very different speeds (2025-06, 1★) | 11.9.58 "improved serve speed accuracy" |
| **Line-call accuracy** | ~8 negative / ~6 positive | Close calls sometimes wrong. Returns of out balls get flagged for challenge (2025-08, 3★) | 11.9.3, 11.9.4, 11.9.64 |
| **Feature removals** | ~8 | Watch-only shot analysis removed (2026-07, 1★). Audio setup removed (2026-05, 2★). "Upload trimmed video" and direct SD transfer removed (2025-08, 2★). Semi-Pro filters removed (2025-03, 1★). Back camera no longer the default (2026-07, 4★) | n/a |
| **Platform gaps** | ~6 | No Android (one user switched to iPhone for the app; others use an iPad as a workaround). Weak iPad editing experience. Web share video black in Chrome. Forehand/backhand filters assume right-handers (2025-04, 4★). Padel wanted (2025-06; shipped Jun 2026) | Padel shipped; Android still missing |
| **Account and sign-in** | ~3 | Lockout after 1–2 failed logins, so the user can't cancel (2026-08, 1★). Facebook login broken (2026-04, 1★). Camera permission prompt loops (2025-01, 1★) | 11.9.60 "sign-in reliability" |
| **Heat and battery** | **0 in window** | Overheating is not mentioned in two years of US written reviews. Battery drain appears only pre-2024 | Vendor still patching heat (11.9.47, 11.9.65, 11.9.67) |
| **Doubles (tennis)** | rare | Tennis doubles complaints are sparse. Doubles problems surface mainly in pickleball attribution | AI Coaching was singles-first; doubles highlights shipped Aug 2025 |

Not about the app itself: Swing Stick orders unshipped for weeks (2025-11, 1★), and a pre-2024 merch order.

## 8. Developer responses and support posture

Featured reviews on the App Store page carry these developer responses (OBSERVED):

- **2024-09-09.** Explains the correction path: tap Edit Point, then Point Details, to change who won the point. Directs scoring questions to support@swing.tennis.
- **2024-07-01.** Replies to a "Terrible Scoring" review (20+ sets, 10+ points wrong per match). Apologizes and asks the user to email failed sessions to support.
- **2023-01-25.** Defends price with "unlimited cloud storage for life" (compares it with iCloud) and time saved by dead-time removal. Mentions annual at $149.99 ("50% discount vs monthly") and that auto-scoring is in beta with score editing.
- **2023-04-01.** Previous customers were grandfathered into lifetime cloud storage as of v10.1, after the 30-day lock backlash.
- **2025-05-07.** "Fixed this bug" on the never-ending session report. The review text was later updated in 2026-06 describing the issue again. INFERRED: a regression, or the review was edited.

Other support signals:
- Contact moved from support@swing.tennis to support@swing.vision (ITF report).
- Support is email and form-based, behind an AI assistant (several 2025–2026 reviews).
- One user said their critical comments were deleted from the moderated Facebook group (2025-01).
- Mar 2025 reviewer: the company bumped Semi-Pro hours back up after complaints.

INFERRED: the developer's public stance treats accuracy issues as data to submit and price as justified by cloud storage. It rarely acknowledges reliability problems publicly; those show up only as release notes.

## 9. Accuracy evidence: claims versus independent data

| Claim or measurement | Source | Label |
|---|---|---|
| Line calls "over 99%" overall; 97% for calls within 10 cm of a line; human eye about 90% | FAQ, Swing Court page, Tennis.com (Dec 2024) | OBSERVED (vendor claim; method not published) |
| Shot speeds within 10% with an ideal setup at 60 fps; speed is the average along the trajectory, about 10% below radar | FAQ | OBSERVED (vendor) |
| A 2-camera option to reach 99% on close calls "later this year" | Swing Court page | OBSERVED (vendor; not seen shipped) |
| ITF PAT approval (Rule 31), PAT-25-037, issued 2025-10-31, v11.9.6 | ITF certificate and report | OBSERVED. **The approval explicitly does not establish data accuracy or in/out reliability.** Apple Watch is not permitted in competition; fence iPhone and iPad are |
| Concurrent validity versus video analysis: placement ICC 0.83–0.87, serve speed ICC 0.76–0.80, stroke detection ICC 0.97, spin recognition ICC 0.76 | Bilić et al., *Applied Sciences* 13(10):6195, 2023 | OBSERVED (n = 5 elite male juniors aged about 15.6; small sample, pre-2024 models) |
| USTA SoCal tournament pilots: an iPhone on the fence plus an iPad at the net post; needs staff, Wi-Fi and spare batteries; some shots uncallable with one camera; about $10 per match | Tennis.com (2024-12-08), TennisNerd (2024-12-20) | OBSERVED (reporting, not independent testing) |
| User estimates: AI scoring about 80–90%; serve speed within about 2% of Hawk-Eye, groundstrokes about 10% low | App Store reviews 2025–2026 | OBSERVED (anecdotal) |

INFERRED for JOVRA:
- No independent, current, large-sample benchmark of SwingVision exists in what I found. JOVRA should not claim superiority without its own labeled test footage (consistent with the existing brief).
- JOVRA should define speed explicitly (average versus peak/radar-equivalent), as SwingVision's FAQ does. Its users still get confused.
- Close-call accuracy should be reported separately from overall accuracy.

## 10. Corrections and additions to `design-reference/brief/research.md`

- **Confirmed:** 4.7 from about 4.9K ratings (exactly 4.70556 / 4,928). The developer's Edit Point correction path (2024-09-09). Recent recording, heat and sync fixes.
- **Added:**
  - The written-review sentiment gap (3.39 over the last two years, versus 4.71 overall).
  - The full tier and IAP price list.
  - Recording-hour caps.
  - The 7-day free-tier access limit and auto-offload of local originals.
  - ITF PAT approval and its accuracy disclaimer.
  - The capture spec (60 fps rear camera, server backend, 1080p60 at 5 ft+ for imports).
  - Ground / Fence / Stick equipment tiers.
  - Interruption causes.
  - Two years of release notes by theme.
  - Watch and Mac platform features.
  - No Android.
- **Nuance:**
  - "Heat" is real in release notes but rare in user reviews. Prioritize graceful thermal degradation, but the bigger user pain is lost or truncated recordings and stalled pipelines, whatever the cause.
  - Tennis doubles complaints are rare; pickleball doubles attribution is the weak spot. That said, SwingVision gated AI Coaching to singles, and its player identification is reportedly the most manual step.

## 11. Steal / Improve / Avoid for JOVRA

Screen numbers refer to `design-reference/brief/screens.json`.

### Steal

Proven patterns users praise or the vendor invested in.

1. **Dead-time removal as the default replay.** It is the most consistently praised feature and works even with Ground Mode (no stats). Put it in screens 10 (smart-replay) and 7 (import queue). OBSERVED value; INFERRED placement.
2. **Sentence-style filter builder** ("Show me the [game points] where [Jon] won with a [forehand winner] on [Alex's] serve"). It is more learnable than a filter sheet. Use it for screen 10's filter chips.
3. **Point History list.** Each row shows the score, how the point finished (winner or UE icon) and a play button. Use it on screen 9 (match-overview), linked to "Review 8 flagged points".
4. **Butterfly bars for head-to-head match stats**, and **Trends sparklines** with 4W / 3M / 6M / 1Y / YTD ranges. Use them on screens 9 and 16.
5. **Framing aid.** Align a court landmark (near service line, or the net top for ground placement) inside a highlighted band, then a full-court outline with a green check. Add court-angle feedback. Use it on screen 5 (court-calibration). Keep **audio-guided setup**; users missed it when it was removed.
6. **Equipment-tiered expectations.** Ground gives trimming only; fence adds stats; high centered mount adds line calls. Tell users up front what each placement can deliver (screen 4 or 5).
7. **Real-time favorite/bookmark of a point.** JOVRA's "Mark point" on screen 6 is equivalent. Also offer it from a wrist or second phone.
8. **Second-phone remote control via QR,** including Android. It solves the "no Apple Watch" setup and challenge gap.
9. **Interruption taxonomy shown on the session card** (backgrounded, audio in use, low battery, system pressure). Pair it with a Focus Mode automation prompt.
10. **Pre-flight checks before recording:** storage (at least 10 GB per 2 h at their bitrate), battery (at least 80% for 2 h), and a Focus/Do Not Disturb hint. These match screen 5's checklist.
11. **Target zones with real-time audio feedback** (speed, accuracy, in/out chime), and per-half targets for partner rallies. Use it for drills on screen 15.
12. **Background export with a Live Activity**; vertical export with auto-pan keeping the ball centered.
13. **Share link playable on the web for non-users,** and tagging so the session appears for each tagged player. Privacy levels: Public / Friends / Participants.
14. **Import of external footage** with a stated capture spec: 1080p60, behind the baseline, at least 5 ft high, both baselines visible, a few feet of runoff, net not overlapping the far lines.

### Improve

Where SwingVision is weak and JOVRA can win. All INFERRED recommendations, grounded in the observations above.

1. **Recording never depends on analysis, upload or the Watch.**
   - Write the original continuously so a crash or interruption still leaves a playable file. For example, set `AVCaptureMovieFileOutput.movieFragmentInterval`, or write rolling segments with `AVAssetWriter`.
   - Never auto-stop because "nothing is happening".
   - If analysis fails, the video stays watchable.

   This directly targets about 35 recent complaints and two years of patches. (Apple API names are from my knowledge; I did not re-verify them in this session.)
2. **Thermal handling as a visible state, not a crash.**
   - Observe `ProcessInfo.thermalState` and `AVCaptureDevice.systemPressureState`.
   - Shed load in order: live audio and line calls first, then real-time analysis, then the preview frame rate. Keep recording for as long as possible.
   - Show this on screen 6: "Phone warming · Analysis paused · Recording safe". SwingVision only added a spoken notice in Sep 2026.
3. **Truthful remote state.** Any Watch or remote UI shows the recorder's heartbeat and the last-written timestamp, not an assumed "Recording". Several users lost sets because the Watch said it was recording.
4. **Correction built into replay (screen 10).**
   - Flip winner, add a missed point, split or merge a rally, nudge start and end, mark "Needs review".
   - Bulk select/deselect, edit the score while watching, 10-second skip.
   - Always allow scrubbing the full untrimmed video between detected points.
   - Corrections must survive reprocessing (SwingVision fixed this only in 11.9.63).
5. **Player identification once per match.** Use clothing color or side-of-court hints, set during setup (screen 4), instead of per-point thumbnail tagging. Store **handedness** from onboarding (screen 2 already asks) so forehand/backhand logic works for left-handers.
6. **Confidence and definitions on every number.**
   - Speed labeled "estimated · average flight speed" with a calibration note. Screen 12 already says "Estimated · Camera calibration affects speed".
   - Line calls show margin and uncertainty.
   - Accuracy is never marketed without the close-call breakdown.
7. **Ownership and storage (screens 7, 19, 20).**
   - Originals stay on the device until the user chooses otherwise. No time-based lockout of the user's own files.
   - Show the app's storage use and offer one-tap clearing of derived caches. A SwingVision user had 20 GB stuck.
   - Resumable uploads to Google Drive or other storage, with Wi-Fi-only as a **toggle** rather than forced, and a retry that is visible and reliable.
8. **No recording-hour caps for on-device capture.** If a server tier ever exists, meter only server analysis or storage, and show the meter. Users were confused and blocked by SwingVision's hour quotas.
9. **Cross-session aggregates.** Stats across all matches or a date range, filterable by opponent and surface. A Dec 2024 user couldn't find this.
10. **Platform breadth.** Real iPad layouts for review, and Android planned from the data model up. SwingVision has none after 10 years, and Android users are actively asking.
11. **Doubles done honestly.** Ship doubles review and trimming first. Gate per-player doubles stats behind validated identification and label it "beta". This matches JOVRA's brief.
12. **Support you can reach.** In-app "Send diagnostics" bundles session state, device thermals and logs; a human reply SLA. Never make an AI chatbot the only path.

### Avoid

1. **Gating the user's own videos by age or tier.** Examples: the 7-day free window, the 30-day lock in 2023, and auto-offloading local originals after one week.
2. **Silently removing features from paying tiers** mid-subscription, or shipping removals as "improvements". Examples: Semi-Pro filters and hours, watch-only analysis, audio setup, trimmed upload.
3. **Ads on personal video content,** especially stacked at video end.
4. **Trial and bundle flows that convert to a full year at once,** or re-offer "free trials" that charge. Also avoid quoting an annual-divided monthly figure next to a much higher real monthly price.
5. **Accuracy marketing without context.** "99%" that includes easy calls draws expert pushback. The ITF approval does not certify accuracy.
6. **Constant upsell reminders** of locked higher-tier features for people who already pay.
7. **Requiring cloud upload before review.** SwingVision's guide says review comes after upload.
8. **Destructive storage behavior.** SwingVision shipped fixes for videos awaiting upload being deleted on low storage, and local files deleted on account switch. JOVRA should never delete an original without explicit user confirmation.
9. **Front-camera defaults on the record screen;** hard-coded right-handed assumptions; login lockouts that block cancellation.
10. **Watch-only failure modes.** The core flow must work fully with one iPhone and no Watch.

## 12. Open questions

- Release notes for 11.8.2 to 11.9.2 (about Oct 2024 to Jan 2025) and 11.9.37 to 11.9.42 (Oct to Nov 2025) were not retrieved. Wayback snapshots for those dates lacked embedded history, and AppsHunter blocks automated access.
- Swing Stick physical specs (extended height, weight, clamp range): UNVERIFIED.
- Which analysis runs on device and which on the server. The FAQ says real-time on device for A13+; the ITF report says data goes to a backend. Both may be true (live versus post-processing).
- Whether Audio-Guided setup is currently present. The guide image shows it; a May 2026 review says it was removed.
- Prices for Teams and Coach Reviews; whether "Plus" equals the former "Semi-Pro".
- Purpose of the "Wallet" capability on the listing.
- Whether SwingVision prompts for in-app ratings in ways that inflate star-only ratings. Not determinable from public data.
- Android timeline: FAQ only, no date.

## Sources

All accessed 2026-10-07.

| URL | What it supported |
|---|---|
| https://itunes.apple.com/lookup?id=989461317&country=us | Rating 4.70556, 4,928 ratings, version 11.9.67 (2026-09-27), size, min iOS 18.0, languages, description (Pro $179.99/yr, "$14.99/mo"), release notes, screenshot URLs |
| https://itunes.apple.com/lookup?id=989461317&country=gb (also au, ca, de, fr, jp) | Storefront ratings comparison |
| https://itunes.apple.com/us/rss/customerreviews/page=1..10/id=989461317/sortby=mostrecent/json | 490 written reviews (2016-10-20 to 2026-10-04); theme coding; rating means by year |
| https://apps.apple.com/us/app/swingvision-tennis-pickleball/id989461317 | IAP list and prices, rating histogram, A12 requirement, privacy labels, accessibility labels, Siri/Wallet capabilities, Editors' Choice, platforms (iPhone, iPad, Mac, Watch, iMessage), version history 11.9.43–11.9.67, featured reviews with developer responses (2023-01, 2023-04, 2024-07, 2024-09, 2025-05) |
| https://web.archive.org/web/20241012051708id_/https://apps.apple.com/us/app/swingvision-tennis-pickleball/id989461317 | Version history 11.4.5–11.8.1 (Feb–Oct 2024) |
| https://web.archive.org/web/20251005162451id_/https://apps.apple.com/us/app/swingvision-tennis-pickleball/id989461317 | Version history 11.9.3–11.9.36 (Jan–Sep 2025) |
| https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/39/0d/f7/390df74a-d606-8ece-377d-1759a0b4e553/1_App_Store_iPhone15Pro_Awards.png/600x1298bb.jpg (and the other 36 media items listed in the page JSON) | Screenshot content (Section 6) |
| https://swing.vision/subscribe/compare | Plus/Pro/Max hours (16/30/60), feature matrix, Fall-sale web prices, year-2 renewals, 60-day guarantee |
| https://swing.vision/shop/swing-stick-offer | Swing Stick bundles ($49.99 with 1 month Pro; $143.99 with Pro yearly), Pro benefits (30 h, exports longer than 5 min) |
| https://swing.vision/faq | Device requirements, accuracy claims (97% within 10 cm; speed within 10%; average speed about 10% below radar), free 8 h, import, Android status, 80% battery, 10 GB, real-time on A13+, Focus Mode, interruption causes including System Pressure/umbrella, Wi-Fi-only uploads, auto-removal of local videos after 1 week, Watch compatibility, Mac requirements, privacy levels, Max family details |
| https://swing.vision/guides/set-up-your-recording | Ground / Fence Mount / Swing Stick tiers and steps, sun and windscreen tips, wide-angle lens, Remote Control, Apple Watch requirement; setup UI images (landscape, HD/zoom/flip, Audio-Guided toggle) |
| https://swing.vision/guides/track-your-match | Scoring modes (AI Scoring with final set scores; Watch Game by Game / Point by Point / Point by Point+), favorites, highlight filter flow, A13 requirement |
| https://swing.vision/guides/challenge-line-calls | Challenge flow on Watch and on iOS/Android remote via QR pairing; Digital Crown frame-by-frame |
| https://swing.vision/guides/what-to-do-after-your-recording | Player identification after the match, Wi-Fi backup steps, review after upload |
| https://swing.vision/guides/import-existing-footage | Import spec 1080p60, at least 5 ft, both baselines; iOS must stay foreground |
| https://swing.vision/guides/review-your-shot-stats | Shot stats definitions, deltas versus last session, opponent scouting |
| https://swing.vision/teams | Teams features: 60 h per player, dashboards, streaming 15 duals per season, AI Officiating "coming 2025" |
| https://swing.vision/swing-court | Swing Court hardware; 99% / 97% claims; 500M shots; 200K monthly users; >$10M raised; 2-camera plan |
| https://swing.vision/newsletters | Dated announcement archive 2021–2026 |
| https://swing.vision/newsletters/free-tier | Jan 2026 free tier: 2 h to 8 h, HD; 7-day access, 5-min exports, ads |
| https://swing.vision/newsletters/introducing-max | Max launch Jan 2024 at $29.99/mo ($359.99/yr), 60 h, 4K |
| https://swing.vision/newsletters/ai-coaching | AI Coaching Jun 2024, singles only |
| https://swing.vision/newsletters/live-line-calls | Live Line Calls beta Dec 2024; 1x zoom tip |
| https://swing.vision/newsletters/coach-reviews | Coach Reviews marketplace (Jun 2025), 7-day turnaround, timestamped comments plus screen recording; "86 million tracked shots" |
| https://swing.vision/newsletters/group-chats | Group Chats in v11.8 (Oct 2024) |
| https://swing.vision/newsletters/ground-mode | Ground Mode (Apr 2026), vertical highlights with ball centered |
| https://swing.vision/newsletters/record-tab-background-exports | New Record tab, background exports, Rally-mode Target Practice (May 2026) |
| https://swing.vision/newsletters/itf-tournament-approval | ITF approval messaging: iPhone allowed, Watch not |
| https://www.itftennis.com/media/15293/pat-approval-certificate-swingvision.pdf | PAT-25-037 approved 2025-10-31, v11.9.6; component permissions |
| https://www.itftennis.com/media/15294/pat-25-037-approval-report-swingvision.pdf | 60 fps rear camera, ML tracking, 3D ball positions, backend server, 3 incorrect challenges per set, accuracy explicitly not certified |
| https://doi.org/10.3390/app13106195 (abstract via https://api.crossref.org/works/10.3390/app13106195) | Bilić et al. 2023 validity study, n=5, ICC values |
| https://www.tennis.com/news/articles/fair-play-swingvision-puts-its-electronic-line-calling-to-the-test-in-tournament-play | USTA SoCal ELC pilots, setup, limitations, about $10 per match (2024-12-08) |
| https://www.tennisnerd.net/?p=43158 | Live line calling coverage, single-camera limits (2024-12-20) |
| https://blog.swing.vision/ | Data-driven content strategy (NTRP benchmarks); stat-card sharing post (2026-10-06) |
| https://play.google.com/store/search?q=swingvision&c=apps&hl=en_US&gl=US | No official SwingVision Android app; PB Vision present |
