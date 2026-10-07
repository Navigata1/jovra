# Tennis app landscape sweep: recording, tracking, scoring, line calling, analysis, charting

Researcher notes for JOVRA Tennis. Observed on **2026-10-07** in the US App Store and US Google Play, plus public web sources.
Scope: every product category that records, tracks, scores, calls lines, analyses or charts tennis. Phone-only apps, wearables and sensors, court-installed hardware, robots and generic video-coaching tools are all included. SwingVision, Onform and SevenSix are covered in depth in sibling files (for example `swingvision.md`), so here they appear only as landscape rows.

**Evidence labels.** OBSERVED means I saw it in a cited source on 2026-10-07. INFERRED means it is my reasoning from observed data. UNVERIFIED means it comes from a secondary or summary source I could not confirm against a primary one.
**In the tables,** every cell is OBSERVED from that row's cited source (`[S#]`, see Sources) unless it carries *(I)* for inferred or *(U)* for unverified.
**Ratings.** "4.71 / 4,928" means the average rating and the all-versions rating count from the iTunes Lookup API, US storefront. Android figures are the Google Play average and count. Downloads are Play's install band.
**Pricing.** Prices are App Store in-app purchase (IAP) price points, read from the listing page.

---

## 0. TL;DR (decision-relevant)

1. **The phone-only "full match tracker" tier still has one real incumbent.** SwingVision is at 4.71 / 4,928 on iOS. In my 21 App Store searches, every other phone-camera AI tennis app has fewer than 70 ratings. INFERRED from a keyword classifier over 347 unique results: about 48 apps describe AI plus video for tennis, and **40 of those 48 first shipped in 2025–2026**. No 2025–26 entrant has broken out. The field is a crowded long tail of solo or small-studio apps, each typically with 1–12 ratings. [S1][S2]
2. **Android is the clearest structural gap.** No SwingVision, SevenSix or Toach listing appears in Google Play search (OBSERVED, 2026-10-07). Onform is on Android, but it rates **2.97 / 309** there against **4.79 / 8,666** on iOS. PlaySight's Android app rates 2.84 / 186. The best-rated Android tennis tool is a manual charting app, **Tennis Math** (4.61 / 3,345, 100K+ installs, Wear OS), and it has no iOS version. INFERRED: a well-built JOVRA Android port would land in an under-served market, but Android quality has to match iOS or it inherits Onform's split reputation. [S9][S10]
3. **SwingVision's pricing moved since the prior brief.** There is now a **Free tier** (since v11.9.49, 2026-02-04: 8 h/month HD, Watch line challenges, audio line calls) and **Plus / Pro / Max** tiers: $14.99/mo or $95.99/yr, $24.99/mo or $179.99/yr, and $39.99/mo or $299.99/yr. Max became a family plan for up to 5 people in Nov 2025. SwingVision also holds **ITF PAT approval** (PAT-25-037, issued 2025-10-31), which no other phone app in this sweep shows. [S4][S11]
4. **Rally trimming has become table stakes.** At least 9 products automatically cut dead time: SwingVision, TennisCut, Toach, SmartHit, PerfectSwing, Spherely, SportArc, Wingfield and PlaySight. **On-device processing with no upload** is the 2026 differentiator claim, made by TennisCut, SmartHit, AI Tennis Swing Coach, Swingli and OverRally. [S2]
5. **True line calling is still mostly a hardware business,** with an accuracy bar set by ITF classification. Gold: Hawk-Eye, Foxtenn, Bolt6. Silver: PlayReplay, Zenniz. PlayReplay costs about **$3,200 per court per year** with 4 net-post cameras. Portable options are In/Out v4 ($499) and Baseline Vision. Phone apps that call lines (SwingVision, eyes3) are not ELC-classified. [S12][S14][S18]
6. **The capabilities missing from the market are JOVRA's opening (INFERRED from description text):**
   - **User-owned cloud archive.** Of 347 tennis listings, *zero* mention Google Drive and only 4 mention Dropbox.
   - **Equipment and string tracking** inside a recording app. Only TennisKeeper has a string tracker. String tension measurement lives in separate apps such as RacquetTune (4.62 / 482).
   - **Accessibility.** Only 5 of 347 listings mention VoiceOver or accessibility.
   - **Score correction and charting fidelity,** which are recurring complaints: no "service winner", no editing of past points, lost match history.
   - **Honest confidence labelling** on estimated metrics. TennisServe is the only example I found. [S1][S2][S3]

---

## 1. What changed vs. the prior brief (`design-reference/brief/research.md`)

| Prior claim | Re-check 2026-10-07 | Label |
|---|---|---|
| SwingVision 4.7 / ~4.9K | 4.71 / 4,928; v11.9.67 (2026-09-27); min iOS 18, A12+ | OBSERVED [S2][S4] |
| SevenSix 4.2 / 68 | 4.19 / 68; v4.0.2 shipped **today** (2026-10-07). IAPs: $14.99/mo, $149.99/yr, or pay-per-analysis at $1.99 for 1, $3.99 for 3, $4.99 for 5. Not found in Google Play search | OBSERVED [S2][S7][S9] |
| Onform 4.8 / ~8.7K | 4.79 / 8,666 iOS, **2.97 / 309 on Android** (100K+). Ten IAP tiers from Personal $4.99/mo to Team/Academy $79/mo | OBSERVED [S2][S6][S10] |
| SwingVision "Pro" subscription | Now Free + Plus/Pro/Max (prices above). The listing text still says Pro is "$179.99 USD per year ($14.99 USD per month)", but the actual Pro Monthly IAP is $24.99. The $14.99 figure is the Plus Monthly price | OBSERVED [S2][S4] |
| (not covered) | SwingVision added Ground Mode (v11.9.54, 2026-03-27), Ball Tracer and padel (v11.9.60, 2026-06-26), USTA Connect NTRP/WTN (v11.9.61, 2026-07-11) and Monthly Challenges | OBSERVED [S4] |

---

## 2. Method

- **iTunes Search API, US, limit 50, 21 terms:** tennis video analysis, tennis tracker, tennis line calling, tennis score keeper, tennis stats, tennis ai coach, tennis swing analyzer, tennis match charting, tennis serve speed radar, tennis apple watch, tennis, tennis coach video, tennis ai, tennis line call, tennis scoring, tennis sensor, tennis serve, tennis highlights, swing analysis tennis, tennis recorder.
  - This produced **347 unique apps**.
  - About 30 named-product searches followed: onform, hudl technique, dartfish, playsight, wingfield, playreplay, zepp, babolat, baseline vision, xbotgo, pivo, acemate, spiideo, zenniz, pb vision, pocket radar, string tension, and others. [S1]
- **iTunes Lookup** for 70 app IDs, giving ratings, versions, release dates, descriptions and release notes. [S2]
- **App Store web pages** for about 33 apps, giving IAP price lists and version history. [S4–S8]
- **Reviews RSS** (most recent, up to 3 pages) for 20 secondary apps. [S3]
- **Google Play** search result pages for 12 queries, and Play detail pages for 25 package IDs. [S9][S10]
- **Web sources** for hardware ecosystems, ITF classification and status checks. [S11–S26]
- **Caveats.**
  - The category counts in §0 and §6 come from a regex classifier over listing text (INFERRED). Treat them as directional only.
  - Small rating counts (n<20) are low-signal. Several 2026 entrants have uniformly glowing 5-star sets of 2–6 reviews, which I treat as unproven.
  - Review complaints are user reports, not measured failure rates, and older ones may already be fixed.

---

## 3. Landscape table

### A. Phone-camera match trackers (auto stats, highlights, line calls)

| Name | Platforms | Category | Rating / count | Price model | Standout capability | Notable weakness | Status |
|---|---|---|---|---|---|---|---|
| **SwingVision** [S2][S4][S11] | iOS, iPadOS, macOS, watchOS, visionOS. **No Android app** (an Android phone can act as remote control per sibling notes) | Full-match tracker + line calls | iOS 4.71 / 4,928 | Free (8 h/mo HD); Plus $14.99/mo or $95.99/yr; Pro $24.99/mo or $179.99/yr; Max $39.99/mo or $299.99/yr (family of 5) | Single-camera auto scoring, shot speed/depth, live audio line calls and Watch challenges, Ball Tracer, ITF PAT approved, USTA NTRP/WTN display, padel and pickleball | Release notes over 12 months repeatedly fix lost or interrupted recordings, uploads stuck at 100%, heat stability and Watch sync. iOS-only. Listing price text is confusing | Active, v11.9.67 (2026-09-27) |
| **Toach: AI Tennis Analyzer** [S2][S8] | iOS | Match rally cut + serve speed + live coach | 5.0 / 6 | Free (analyses the first 5 min per match and 3 serve speeds); Pro $9.99/mo or $79.99/yr; 7-day trial | Clocks serve speed with no radar and burns it onto the replay. Spoken real-time "Coach Tina". Court-lock that re-finds the court if the phone is bumped | n=6. A metered free tier. Speed shown only "where it can be measured" | Active, first release 2026-06-15, v1.9.2 (2026-10-07) |
| **SmartHit – AI Tennis Coach** [S2][S8] | iOS | Rally cut + speed + landing map | 5.0 / 3 | Pro $14.99/mo or $119.99/yr; Max $24.99/mo or $199.99/yr | On-device rally detection, estimated serve speed, landing mini-map, "Hawk-Eye style" ball trails, camera-follow crop, any frame rate, zero ads | Tiny user base. Reviews so far are in Chinese only | Active, v1.6.0 (2026-09-19) |
| **eyes3 LineCall & InstantReplay** [S2][S8] | iOS (multi-sport) | Phone line calling | 4.0 / 4 | Annual "Starter" $71.99–$119.99; "Professional" $359.99–$599.99 (several price points listed) | Phone-only IN/OUT calls, timeline, kiosk mode for spectators, no extra hardware | Almost no ratings. Expensive. No independent accuracy evidence *(I)* | Active, v3.0.131 (2026-09-24) |
| **Tennis Blackbox** [S2] | iOS | Dual-device recorder | 0 ratings | Free | 240 fps capture on one iPhone, review on an iPad or second iPhone, gapless segments | No ratings, no AI | Active, v8.3 (2026-09-02) |
| **Line Umpire (ApplicVision)** [S2] | iOS + Watch | Phone line call | 1.0 / 1 | Free | On-device line call | Abandoned *(I)* | Dormant, last update 2022-06-22 |

### B. Phone-camera technique / AI coach (pose, swing, serve)

| Name | Platforms | Category | Rating / count | Price model | Standout capability | Notable weakness | Status |
|---|---|---|---|---|---|---|---|
| **SevenSix** [S2][S7] | iOS (not in Play search) | Stroke analysis | 4.19 / 68 | $14.99/mo, $149.99/yr, or credits at $1.99–$4.99 per 1–5 analyses | Focused stroke workflow, pay-per-analysis option | Small base. Older reviews mention stalled analysis (sibling notes) | Active, v4.0.2 (2026-10-07) |
| **INTER TENNIS: 3D AI Analysis** [S2][S10] | iOS + Android (1K+) | 3D technique + AR | iOS 0 ratings; Android unrated | No IAP shown on either store (pricing unknown) *(U)* | Claims 3D reconstruction of **ball, racket and player from one phone video**. Racket-tip speed path, contact height ("on the rise/fall"), AR stat panels. "Diagnose and Fix" groups shots by shared fault. Claims 1,500+ users in 50+ countries | No ratings. English-only listing. Specific tripod placement (beside the net, 1–2 m high) | Active, v5.0.0 (2026-10-06) |
| **AI Tennis Swing Coach** (Y. Brei) [S2][S3][S8] | iOS | On-device pose and racket coach | 4.88 / 8 | Core free with no account and no limits; Pro $9.99/mo or $79.99/yr; 25 AI credits $4.99 | Live skeleton, joint angles and racket tracking with spoken cues, all **on-device (Core ML)**. Each swing scored 0–100 with a named fault, one fix and one drill. PDF session report. Multi-player hub. Explicit disclaimers (not medical, not an official rating) | Single developer, n=8 | Active, first release 2026-06-15 |
| **TorqAI: Tennis Swing Doctor** [S2][S8] | iOS | 3D pose diagnosis | 5.0 / 4 | $5.99/mo or $49.99/yr | 17 joints in 3D, kinetic chain, level estimate, auto-cut of up to 60 min of film, drill prescription | n=4. "Level" estimate is proprietary | Active, v4.2 (2026-09-26) |
| **TennisServe: Serve Analysis** [S2][S8] | iOS | Serve-only biomechanics | 5.0 / 1 | $6.99/mo or $39.99/yr | 8 serve phases, 30+ checks. Score states what the camera could and could not measure (rare honesty) | Brand new | Active, released 2026-10-01 |
| **ServeLab (Fuzzy Yellow Balls)** [S2][S3][S8] | iOS | Serve AI coach "Bert" | 2.0 / 2 | Bert $29/mo or $299/yr; one lesson $67; ServeLab yearly $99.99 | Brand-led content plus AI serve review | 2025–26 reviews report crashes on iOS 27, inaccurate body tracking, upload breakage, clipped screens and a steep paywall | Active but poorly reviewed |
| **SportAI Open** [S19] | **Web app** (record from a phone browser) | Technique analysis | n/a | Not disclosed | Open beta launched 2026-09-10 for tennis, padel and pickleball. B2B pedigree (clubs, brands, federations) | Beta. Roadmap still lists progress tracking and coach tools as future | Active (beta) |
| **Long tail, 2025–26** [S2][S10] | Mostly iOS; some Android | AI swing/serve coaches | All ≤8 ratings (iOS). AXEL AI Android 1.8 / 53 (10K+). Offcourtz Android 3.6 (1K+) | Mostly subscriptions | e.g. Tennis AI: Swing & Serve Coach, CedarX, NiceShot, TennisACE, Tennis-IA, NextShot, 10Ace, TennisLens, Tekrise, TennisBee, TennisForm | Undifferentiated *(I)*. The AXEL reviewer complains the camera can't be flipped to record hands-free | Mixed |
| **Mouratoglou eCoaching** [S26] | Unknown | Serve biomechanics | — | — | Company-database description only | No US App Store listing found | UNVERIFIED |

### C. Rally-cut / highlight editors (phone)

| Name | Platforms | Category | Rating / count | Price model | Standout capability | Notable weakness | Status |
|---|---|---|---|---|---|---|---|
| **TennisCut: AI Tennis Analysis** [S2][S3][S8][S10] | iOS + Android (10K+) | On-device rally cut | iOS 4.08 / 12; Android 4.09 / 52 | Free core; Pro $4.99/wk, $8.99/mo or $44.99/yr | **All on-device, no upload.** A second phone works as remote (QR pairing, live preview, camera battery and storage shown). 1080p/4K at 30/60 fps with HDR kept through export. Ball trajectory overlay. Free frame-step "Coach Eye". 16:9 or 9:16 export | 2026 reviewers say rally boundaries start too early and detection is sometimes off | Active, v2.0.0 (2026-09-19) |
| **PerfectSwing: Rally Highlights** [S2][S8][S9] | iOS + Android | Cloud rally cut | iOS 5.0 / 6; Android 4.2 | Pro, several price points $3.99–$59.99 | Upload and get notified when done. Chapters built from scores. Merge clips | Cloud upload required | Active, v2.4.0 (2026-10-03) |
| **Spherely** [S2][S3] | iOS | Multi-racket highlights + community | 4.08 / 12 | $7.99/mo or $59.99/yr | AI rally editing across 6 racket sports, cloud storage, 3D tactics demos | Reviews call the coaching content generic and LLM-made, with weak rally recognition | Active, v1.8.1 (2026-10-03) |
| **SportArc** [S2][S8] | iOS | Auto Cut + coach | 5.0 / 5 | Plus $14.99/mo or $99.99/yr | 4K60 export. Tennis rally cut | Deep analysis covers table tennis only | Active |

### D. Manual charting / score keeping

| Name | Platforms | Category | Rating / count | Price model | Standout capability | Notable weakness | Status |
|---|---|---|---|---|---|---|---|
| **Smashpoint Tennis Tracker** [S2][S3][S5][S10] | iOS, iPadOS, macOS, watchOS, tvOS, visionOS; Android (100+) | Charting + **new video replays** | iOS 4.51 / 462 | Pro $5.99/mo, $14.99/3 mo or $39.99/yr; **Elite $149/yr** | **Five tracking depths**, from games only up to full shot tracking. Private by default. Live shareable match pages. ELO, head-to-head, momentum and pressure analysis. **Sep 2026: "Critical Point" replays in 4K60** with ½× and ¼× slow motion, a **second iPhone camera at the fence**, and Watch scoring while the phone films | 2022–25 reviews describe a long gap with no updates, Watch crashes, matches not saving after match point, and a request for per-point notes | Active, v3.4 (2026-09-30) |
| **MatchTrack** [S2][S3] | iOS | Charting | 4.63 / 280 | Free plus paid upgrade (reviewers mention paying for matches over 1 set) | No account needed. Charting designed with a Penn State associate head coach. Live score broadcast | Reviews ask for a **service-winner** button, deleting and editing past matches and points, and PDF export by set. Data loss after a 2024 update | Active, v2026.7 |
| **Tennis Math: score & stats** [S10] | **Android only** + Wear OS | Charting | Android **4.61 / 3,345** (100K+) | IAP $4.99–$49.99 | Live online broadcast, "Tracking Depth" setting, **fix score while tracking**, undo/redo, comments, Wear OS. Lists an iOS version as "to come" | Doubles detail listed as future work | Active, updated 2026-08-16 |
| **Tennis Scorecard App** [S2] | iOS + Watch | Score keeper | 4.67 / 67 | Free | Watch scoring | — | Active |
| **Tennis Notes – Match Tracker** [S2][S8] | iOS + Watch | Match log | 4.81 / 16 | Pro lifetime $12.99 | One-time price | — | Active |
| **Tennis Score Keeper: ScoreBot** [S2][S8] | iOS + Watch | Score keeper | 4.94 / 16 | $2.99/wk, $24.99/yr or $39.99–$59.99 lifetime | Watch-first | Weekly pricing *(I: dark-pattern risk)* | Active |
| **Racketly** [S2] | iOS (watchOS 26 min) | Watch score keeper | 4.79 / 42 | Subscription | Siri/Shortcuts: ask about results and rating changes | — | Active, v5.0.0 (2026-10-05) |
| **135 Tennis Analytics** [S2][S8] | iOS | Coach charting | 4.42 / 12 | $10.49–$16.49/mo; Remote Mode $5.99 | Charts for juniors and coaches | Sync complaints. Last update 2024-03-06 | Stale *(I)* |
| **TennisLocker (Coach / Player)** [S2] | iOS | Coach–player platform | 4.38 / 65 and 4.03 / 33 | Free | Team/college workflows | — | Active |
| **ProTracker Tennis** [S2] | iOS | Pro charting | 4.25 / 4 | **$89.99** paid | Since 2010 | Niche | Active |
| **Tennis • Tracker** [S10] | Android (+iOS) | Score/stats | Android 3.2 / 89 (10K+); iOS 2.61 / 18 | — | — | Low ratings | Active |
| **Tennis Umpire App** [S2][S9] | iOS + Android | Umpire scoring | iOS 4.3 / 10; Android 3.8 | Subscription | — | Last iOS update 2023-10-14 | Stale *(I)* |

### E. Wearables and sensors

| Name | Platforms | Category | Rating / count | Price model | Standout capability | Notable weakness | Status |
|---|---|---|---|---|---|---|---|
| **OverRally** [S2][S8] | iOS + Watch | Watch swing analytics | 5.0 / 4 | Lite $3.99, Pro $4.99 or $39.99, lifetime $79.99 | Swing speed, **contact timing ± ms**, 3D swing path, **stroke-consistency spreads**, one-tap Watch scoring tied to swings | n=4. A reviewer wants shot-by-shot browsing | Active, first release 2026-07-24 |
| **Swingli** [S2] | Watch-only | Swing counter | 5.0 / 4 | **Completely free**, no account, data on device | Forehand, backhand and serve counts. Heart rate | Basic | Active |
| **TennisKeeper** [S2][S3] | iOS + Watch | Activity + swing tracker | 2.83 / 40 | Pro one-time + add-on subscriptions | **String-life tracker**, H2H, CSV export, iCloud with no account | Reviews: shot misclassification (e.g. 150 groundstrokes logged as about 440 strokes with volleys), Watch-to-phone count mismatch, sync failures, layered fees | Active, v3.29 (2025-10-24) |
| **Tennis Plus** [S2][S3] | iOS + Watch | Watch swing analyzer | 3.65 / 109 | **$9.99 paid** | Shot type, swing speed and spin from the Watch | Reviews 2017–23: inaccurate speed, sync breaking on iOS updates, data loss, slow dev response | Active (redesign v1.7.1, 2026-03-12) |
| **RacketMate** [S2] | iOS + Watch | Watch stroke recognition | 3.56 / 18 | Subscription | Multi-racket | Table-tennis-centric | Active |
| **Garmin "Tennis AI" (Connect IQ)** [S25] | Garmin | 3rd-party watch app | — | — | Counts forehand, backhand, serve and slice | Third-party, not native | Active *(U)* |
| **Zepp Tennis / Zepp Tennis Classic** [S2][S13] | iOS (+Android historically) | Racket sensor | 2.45 / 20 and 4.0 / 7 | Hardware | Swing speed, spin, sweet spot. ITF PAT report 15-012 exists | Hardware discontinued per retailers *(U)* | **Dormant**, last updates 2019-01-14 and 2017-08-17 |
| **Sony Smart Tennis Sensor** [S13] | — | Racket sensor | — | Hardware | ITF PAT report 14-008 exists | No US App Store app found. Retailers list it as archived | **Discontinued** *(U)* |
| **Babolat Play / POP** [S13] | — | Sensor racket / wristband | — | Hardware | ITF PAT report 13-004 exists | No Babolat tracking app found in US store search | **Discontinued** *(U)* |

### F. Court-installed / portable hardware (line calling, smart courts)

| Name | Platforms | Category | Rating / count | Price model | Standout capability | Notable weakness | Status |
|---|---|---|---|---|---|---|---|
| **Hawk-Eye Live** [S12][S20] | Pro venues | ELC (Gold) | n/a | Enterprise. About $60K/court per a secondary source *(U)* | ITF Gold, live and review, all surfaces. Replaced all Wimbledon line judges from 2025 | Elite only | Active |
| **Foxtenn, Bolt6 Sentinel** [S12] | Pro venues | ELC (Gold) | n/a | Enterprise | ITF Gold | Elite only | Active |
| **PlayReplay** [S2][S12][S14][S15] | iOS app (released 2026-06-02) + courtside monitor | ELC (Silver) + stats | iOS 0 ratings | About **$3,200 per court per year**. USTA Missouri Valley funded the first year at a pilot site | 4 cameras on the net posts. Live line calls and challenge replay, serve speed, placement and trajectory, drills. **ITF Silver** (live hard courts; review only on grass/clay). Raised $12M (May 2026). About 350K matches and ~150M line calls | One player per side in sessions. Club purchase required | Active, scaling |
| **Zenniz Smart Court** [S2][S12][S23] | iOS + Android app | ELC (Silver) | iOS 4.4 / 5 | Club hardware | Cameras plus microphones, 3D ball tracking, net-post LED scoreboards. ITF Silver | Club-bound | Active |
| **Wingfield** [S2][S8][S10][S16] | iOS + Android (10K+) | Smart court + app | iOS 4.80 / 61; Android 4.38 / 114 | App Pro $9.99/mo or $89.99/yr. Club hardware Cam+ / AI Pro with "prices on request" (upfront hardware plus monthly fee) | Auto highlights, dead-time skip, placement maps, **net clearance**, Match IQ, **gamified drills scored 0–100**, club leaderboards, **DUPR and German LK rating integrations** (LK can be validated from your own phone footage) | Most features need Wingfield Pro courts. Needs 5 Mbit/s upload | Active, v2.19.4 (2026-10-06) |
| **PlaySight SmartCourt** [S2][S3][S10] | iOS + Android (100K+) | Smart court + streaming | iOS **2.87 / 134**; Android **2.84 / 186** | Club hardware plus per-match purchases (a 2026 reviewer paid $10 for one match). About $12.5K + $500/mo per secondary source *(U)* | Multi-sport live streaming, multi-angle replay, telestration | 2025–26 reviews: AI found 1 rally in a 40-min match, uploads stuck at 0%, login loops, forced updates, subscribe button failures | Active. Ownership went Slinger (2021) → Connexa → management buyout + APEX investment *(U)* |
| **Baseline Vision** [S2][S10][S17] | iOS + Android (5K+) | Portable net-post camera | iOS 4.67 / 6 | Hardware (price not on site) | Net-post camera with no power or Wi-Fi, 20-second setup. Voice line calls with 3D view, challenges, drills with light/sound, Target Zone, net clearance. UTR Pro Tennis Tour partner. ITF PAT report 23-029 | A 2025 reviewer was stuck on a permissions loop | Active, v0.6.28 (2026-08-16) |
| **In/Out v4** [S18] | Phone app + net/line devices | Portable line calling | Legacy iOS app 2.4 / 5 (last update 2018) | **$499** (net + 2 line devices) or $299 (net only) | Line devices look straight down the lines. "Too Close To Call" alert. Claims "millimetre accuracy" (manufacturer) | Current companion app unclear *(U)* | Active (v4 hardware, Apr 2026) |
| **Mojjo** [S26] | Club | Single-camera smart court | — | — | Claims full-match data from one camera | Small (company DB) | UNVERIFIED |
| **Spiideo** [S2] | iOS | Venue cameras | 4.33 / 9 | Venue | Always-on arena recording | Not tennis-specific | Active |

### G. Robots and ball machines with apps

| Name | Platforms | Rating / count | Price model | Standout | Weakness | Status |
|---|---|---|---|---|---|---|
| **Acemate Tennis** [S2] | iOS | 4.67 / 3 | Hardware | 100+ drill templates. Drill, Rally, Serve, Battle and ball-machine modes. Placement distribution, ball speed, AI training score | Robot required | Active |
| **Tenniix (T-Apex)** [S24] | App + robot | — | Basic $899, Pro $1,299 *(U)* | Dual-camera AI vision, UWB position, opponent-style drills | Secondary source only | Shipping *(U)* |
| **Kai Tennis** [S2][S3] | iOS + Watch | 4.88 / 42 | App free; module "coming soon" | Smart control of Playmate iGenie/iSmash, 3D drill visualization | Hardware module not yet shipping per listing | Active |
| **PONGBOT** [S2] | iOS | 3.36 / 11 | Hardware | Position-aware "Smart Pace" | — | Active |

### H. Generic video coaching platforms (multi-sport)

| Name | Platforms | Rating / count | Price model | Standout | Weakness | Status |
|---|---|---|---|---|---|---|
| **Onform** [S2][S6][S10] | iOS, Android, Watch | iOS 4.79 / 8,666; **Android 2.97 / 309** | $4.99/mo up to $79/mo (10 tiers) | Comparison, markup, voice-over, skeleton. Successor of Hudl Technique *(U)* | Android parity | Active, v4.7.3 |
| **CoachNow** [S2][S8] | iOS + Watch | 4.86 / 13,023 | Analyze $9.99/mo up to PRO $49.99/mo | Coach–athlete spaces, side-by-side, skeleton | Golf-centric owner | Active |
| **VisualEyes** [S2][S8] | iOS + Android | 4.78 / 402; Android 3.9 | $4.99–$14.99/mo | Accessibility mention, side-by-side | — | Active |
| **Hudl Technique** [S22] | — | — | — | — | Discontinued; users migrated to OnForm *(U, secondary)* | Discontinued |
| **myDartfish Express** [S1] | iOS | 2.79 / 29 | — | Pro tagging heritage | Low rating | Active |
| **Video-delay tools** [S1] | iOS | BaM Video Delay 4.77 / 84 ($7.99); Video Delay Instant Replay 4.48 / 535 | Paid / free | Instant self-review between serves | No tennis intelligence | Active |
| **Auto-tracking mounts** [S2][S8] | iOS + Android | XbotGo 4.52 / 1,508; Pivo Track 4.78 / 2,482 | XbotGo $15/match or $24.99–$42.99/mo; Pivo Lesson+ $24.99 | Motorised follow-cam | Not tennis-aware. Descriptions don't mention tennis | Active |

### I. Speed / radar

| Name | Platforms | Rating / count | Price | Note | Status |
|---|---|---|---|---|---|
| **Stalker Sport Radar** [S2][S3] | iOS | 3.52 / 40 | Hardware + "Max" sub | Real radar with spin (Pro 3s), CSV, video overlays. Reviews cite many setup clicks and short Bluetooth range | Active |
| **Pocket Radar Sports** [S1] | iOS | 3.59 / 256 | Hardware | Multi-sport radar | Active |
| **Speed Gun for Tennis** [S2][S3] | iOS | 3.92 / 63 | Free | Manual tap timing. Reviews note human error and a max distance shorter than a court | Dormant (2022) |
| **SpeedClock – Video Radar** [S2] | iOS | 2.42 / 83 | $2.99 | Video-based | Dormant (2021) |
| **Tennis Serve Speed Tracker** [S2][S10] | iOS + Android | iOS 5.0 / 2; **Android 1.6** (5K+) | Subscription | Sensor and Bluetooth mentions | Active |

### J. Adjacent (worth knowing)

- **RacquetTune** measures string tension from sound. iOS 4.62 / 482, $2.99. **String Master – Tennis Log** is a stringing log at 5.0 / 7. These are the only notable string tools. [S1]
- **CourtNotes** transcribes lesson audio from a lavalier mic on-device and extracts the coach's advice. $4.99 for unlimited sessions. [S2][S8]
- **Mindset / chat coaches:**
  - **Tennis IQ** (4.58 / 40, $14.99–$19.99/mo; Mouratoglou Academy Zephyrhills partner).
  - **FlowState** ("Charly" memory coach, $17.99/mo).
  - These have no video but signal demand for a coach that remembers your history. [S2][S8]
- **PB Vision (pickleball)**: iOS 4.68 / 138; Android 4.56 / 40 (10K+). A usage-based model priced per minute processed, with clubs able to mark it up *(U)*. A useful analog for metered server analysis. [S1][S10]

---

## 4. The five most relevant competitors beyond SwingVision / Onform / SevenSix

How I chose them (INFERRED): closeness to JOVRA's outcome chain of record → find the point → understand the evidence → one practice action → own the video. I also weighed fit with the 20 planned screens and the iOS-then-Android plan, not just popularity.

### 4.1 Smashpoint: best scoring and charting spine, now with video
- **Does best.** It scores at the depth you choose, from **five tracking levels** up to full shot tracking. It is **private by default**: no public feed, and links exist only when created. It turns charted matches into ELO, head-to-head, momentum and pressure analysis. [S2]
- **Video since Sep 2026 (v3.3.5–3.4).**
  - Replays of **Critical Points**.
  - An optional **second iPhone at the fence** whose clips land on the same point tile, with a one-tap camera switch.
  - Watch scoring while the phone films.
  - Replays run 2 s past the point end so the finish isn't cut.
  - Pro allows 1 extra camera at 1080p. Elite allows 2 cameras in 4K60 and films every tiebreak point.
  - A match stopped early can be saved with "No winner". [S5]
- **Price.** Pro $39.99/yr; Elite $149/yr. That is cheaper than SwingVision Pro ($179.99) and far cheaper than Max ($299.99). [S5]
- **Weak spots.** Watch crashes (2024–25 reviews), saves failing after match point (2019), and a long no-update period before 2025 (a 2024 review worries about the app's future). [S3]
- **For JOVRA (INFERRED).**
  - Smashpoint is the closest analog to JOVRA's *manual-score-first plus replay* P0.
  - Copy the selectable tracking depth, the "No winner" save and the +2 s point padding.
  - Beat it on full-video scrubbing (it replays only critical points), on correction UX, and on Drive ownership.

### 4.2 TennisCut: best on-device capture ergonomics, and cross-platform
- **Does best.**
  - Automatic rally detection and trimming run **entirely on the phone**, with no upload or internet needed.
  - A **second phone becomes the remote**: QR pairing, live preview, start/stop, zoom and quality, plus the camera phone's battery and free space on screen.
  - Records **4K/60 with HDR preserved** through export.
  - Ball-trajectory overlay. A free frame-step "Coach Eye". 9:16 social export.
  - Live scoring with a recap card that adds Watch heart rate and calories. [S2]
- **Traction.** On **Android and iOS**. Android is at 10K+ installs, 4.09 / 52. [S10]
- **Price.** $44.99/yr. One of the cheapest AI tiers. [S8]
- **Weak spots.** 2026 reviewers report point clips starting too early (during the pre-serve bounce) and unreliable detection on some footage. A reviewer also wanted one free import to test before paying. [S3]
- **For JOVRA (INFERRED).**
  - The two-phone remote with camera-health telemetry is a cheap, high-value fix for "who presses record on the far fence".
  - Fold it into screens 5–6 (court framing, live capture).
  - Make clip boundaries user-adjustable to avoid TennisCut's complaint.

### 4.3 INTER TENNIS: highest technique ceiling from a single phone
- **Does best.**
  - Claims to reconstruct **ball, racket and player in 3D from one smartphone video**.
  - Shows a racket-tip speed path, the contact point and racket face, and contact height relative to the bounce (on the rise or the fall).
  - An attack/defence top-down view. Swing-consistency overlay. AR stat panels in your own video.
  - **"Diagnose and Fix" groups shots that share the same fault**, so you train the pattern rather than one clip. Trends across sessions.
  - Ships on iOS and Android, with 1K+ installs on Android. [S2][S10]
- **Weak spots.**
  - No public ratings on either store, and no pricing shown (UNVERIFIED model).
  - The "3D from one phone" accuracy is a vendor claim (UNVERIFIED).
  - Requires a specific placement: a tripod beside the net, 1–2 m high.
- **For JOVRA (INFERRED).**
  - Fault grouping is the right model for Coaching Plan (screen 15) and for Stroke Lab (screen 13): cluster swings by fault, then link the drill to the clip set as evidence.
  - JOVRA's brief already requires per-capability feasibility gates. INTER's claims are the bar to test against, not to assume.

### 4.4 AI Tennis Swing Coach: best privacy-first, no-account technique loop
- **Does best.**
  - Live on-court **skeleton, joint angles and racket tracking with spoken cues**, using a proprietary **on-device Core ML** racket and ball detector.
  - Each swing gets a **0–100 score with a named fault**, then **one fix plus one drill**. Exportable **PDF practice report**.
  - Annotated clip export with the skeleton, callouts and voice.
  - Multi-player hub (self, kids, students).
  - The free core needs **no account and has no limit**.
  - It carries explicit non-medical and non-official-rating disclaimers. [S2]
- **Price.** Pro $79.99/yr, plus $4.99 credit packs for deep written coaching. [S8]
- **Weak spots.** Brand new (first release 2026-06-15) with only n=8 ratings. Accuracy is unproven. Single developer.
- **For JOVRA (INFERRED).**
  - Benchmark for Stroke Lab (screen 13) and Coaching Plan (screen 15). "One fix, one drill, linked to timestamps" matches JOVRA's evidence-linked coaching.
  - The no-account free core and on-device stance match JOVRA's local-first storage decision.
  - JOVRA's "2D pose estimate" label is more honest than unqualified 0–100 scores. Keep it.

### 4.5 Tennis Math: the Android charting benchmark JOVRA's port must beat
- **Does best.**
  - The most-rated tennis tracking tool on Google Play that I found: **4.61 / 3,345, 100K+ installs**.
  - Many scoring-rule options. **Fix score while tracking**. **Advanced undo/redo**. Comments, delays and cancellations. Return winners and rally length. Configurable "Tracking Depth".
  - **Live online score broadcast** and **Wear OS** support.
  - The developer lists an iOS version as coming. [S10]
- **Weak spots.** Play reviews ask for:
  - a fuller per-point log (e.g. player position);
  - multi-device access (since fixed);
  - court-side tracking with automatic side switching. [S10]
- **For JOVRA (INFERRED).**
  - Correction-friendly manual scoring (undo/redo, fix-in-place) is what wins Android ratings without any AI.
  - JOVRA's P0 manual scoring plus recovery should meet this bar on day one of the Android port, including a Wear OS companion.

### Honourable mentions (why they matter)

- **Wingfield.** Gamified drills scored 0–100, net clearance, and the only DUPR plus German LK **official rating integrations**. It proves rating hooks drive usage. Hardware-bound. [S2][S16]
- **Baseline Vision / In/Out v4.** Portable line calling in 20 s with no power or Wi-Fi, for $299–$499. This is the realistic "accuracy upgrade" path if JOVRA ever partners for line calls. [S17][S18]
- **Toach and SmartHit.** Phone-only serve-speed estimation overlaid on the replay, and landing mini-maps. Direct analogs to the Serve Lab "104 mph · Estimated" card. [S2]
- **MatchTrack.** Clean iOS charting UX. Its review backlog (service winner, editing past points, deleting matches) is a free requirements list. [S3]
- **PlayReplay.** Sets the accuracy and ITF-classification bar, and how clubs price it (about $3.2K per court per year). [S14]

---

## 5. Pricing benchmarks (US, annual where offered, OBSERVED [S4–S8])

| Tier | Products |
|---|---|
| Free / no account | Swingli (free), AI Tennis Swing Coach core, TennisCut core, MatchTrack basic, SwingVision Free (8 h/mo) |
| ≤ $50/yr | Smashpoint Pro $39.99; TennisServe $39.99; TennisCut $44.99; TorqAI $49.99; Onform Personal $49.99; Spherely $59.99 |
| $50–$130/yr | Toach $79.99; AI Swing Coach $79.99; Wingfield app $89.99; SwingVision Plus $95.99; SportArc $99.99; SmartHit Pro $119.99; 135 Tennis $124.99 |
| $130–$200/yr | FlowState $139.99; Smashpoint Elite $149; SevenSix $149.99; SwingVision Pro $179.99; SmartHit Max $199.99; Tennis IQ Pro $199 |
| > $200/yr | SwingVision Max $299.99 (family of 5); ServeLab Bert $299; Onform Coach $299.99; eyes3 Pro up to $599.99 |
| Paid up front | ProTracker $89.99; Tennis Plus $9.99; RacquetTune $2.99; Tennis Notes lifetime $12.99; OverRally lifetime $79.99 |
| Per-use | SevenSix $1.99/analysis; XbotGo $15/match; PlaySight about $10/match (review); AI Swing Coach 25 credits $4.99 |

INFERRED: the market median for an AI tennis subscription is about **$80–$120/yr**. SwingVision Pro and Max sit at the top. A JOVRA tier around $60–$100/yr undercuts the incumbent. Pricing could also be split so that capture, replay and manual scoring stay free forever while compute-heavy analysis is paid, which matches the local-first architecture.

---

## 6. Table stakes vs. differentiators vs. white space

### Table stakes (commonly offered; JOVRA must have them)
- **Record or import, slow motion, frame-step and trim.** Offered by every video app.
- **Automatic dead-time removal and rally list.** At least 9 products (§0.4). OBSERVED.
- **Share a highlight with the score overlaid.** SwingVision, Smashpoint, TennisCut, Toach, SmartHit, PerfectSwing, Wingfield. OBSERVED.
- **Manual point-by-point scoring** with tiebreak, no-ad and match-tiebreak options. Every charting app; reviews punish missing options. OBSERVED.
- **Basic match stats:** first-serve %, aces and double faults, winners and errors, plus a session history. OBSERVED.
- **Apple Watch scoring or start/stop.** SwingVision, Smashpoint, TennisCut, Racketly, Tennis Notes, ScoreBot, Tennis Scorecard, TennisKeeper, OverRally. OBSERVED.
- **Stroke-type labelling** (forehand / backhand / serve) wherever AI is claimed. OBSERVED.
- **Free trial plus monthly or annual subscription.** OBSERVED.
- **Multi-sport (pickleball/padel).** Common among the leaders. Optional for JOVRA's tennis-first brief *(I)*.

### Differentiators (offered by only a few)
- **ITF PAT approval of a phone app.** SwingVision only, among phone apps (PAT-25-037). Hardware systems also hold PAT reports. [S11][S13]
- **Live line calls from a phone.** SwingVision (audio calls, Watch challenge), eyes3. Not ELC-classified. [S2][S4]
- **3D racket tracking from one phone.** INTER TENNIS (claim). [S2]
- **Multi-phone synchronised angles.** Smashpoint (2nd camera), SwingVision (1–2 devices per the ITF report), Tennis Blackbox (dual device), TennisCut (remote, not a 2nd angle). [S2][S5][S11]
- **On-device / no-upload AI.** TennisCut, SmartHit, AI Tennis Swing Coach, Swingli; also OverRally on the Watch. [S2]
- **Official rating integrations.** SwingVision USTA Connect (NTRP/WTN), Wingfield DUPR and LK. [S2][S4]
- **Live public score link.** Smashpoint, MatchTrack, Tennis Math, eyes3 kiosk. [S2][S10]
- **Evidence-linked practice.**
  - Wingfield: drills scored 0–100.
  - AI Swing Coach: one fault, one fix, one drill.
  - INTER: fault clusters.
  - Toach: spoken next fix. [S2]
- **Family / multi-player plans.** SwingVision Max (5 seats), AI Swing Coach player hub, Toach. [S2][S4]
- **Watch micro-timing.** OverRally (contact timing in ms, consistency spreads). [S2]
- **Honest confidence copy.** TennisServe (states what the camera measured). Rare and worth copying. [S2]

### White space (rare or absent; INFERRED from listing text)
- **User-owned archive in Google Drive or Dropbox.** 0 of 347 tennis listings mention Google Drive; 4 mention Dropbox. Incumbents keep video in their own clouds (SwingVision "unlimited cloud storage", PerfectSwing, Spherely). JOVRA's Drive archive (screen 19) is genuinely unusual. [S1][S2]
- **Equipment and string journal tied to sessions.** Only TennisKeeper has a string-life tracker. Tension measurement (RacquetTune) is a separate app. JOVRA's Racket Vault and String Journal (screens 17–18) could link a string setup to performance trends. Nobody does this. [S1][S2]
- **Accessibility as a feature.** 5 of 347 listings mention VoiceOver or accessibility. [S1]
- **Left-handed and one-handed backhand awareness.** Only Tennis Plus mentions left-handed support in its listing. JOVRA's onboarding (screen 2) captures handedness and backhand type. [S1]
- **Score correction as a first-class flow.** No listing markets it, while reviews in MatchTrack, Smashpoint and Tennis Math, and sibling SwingVision notes, all ask for it. [S3][S10]
- **A strong Android full-match tracker.** None found (§0.2). [S9][S10]
- **Calibrated "estimated" metrics with stated error.** Speed claims (Toach, SmartHit, Tennis Plus) carry no stated error bars. Tennis Plus reviews complain speeds drifted lower after an update. [S2][S3]

---

## 7. Cross-landscape complaint themes → JOVRA design implications

| Theme (user-reported) | Where seen | JOVRA implication (INFERRED) |
|---|---|---|
| Recording lost or truncated; uploads stuck at 0% or 100%; processing stalls | PlaySight 2026 reviews; SwingVision release notes 2025–26; TennisKeeper "save failed and data gone" [S3][S4] | Keep the brief's separate states for video, analysis, review and archive. Never delete a local original until the provider confirms the upload. Retry once from a queue |
| AI misses rallies or mis-trims (1 rally found in 40 min; clips start too early) | PlaySight 2026, TennisCut 2026 [S3] | User-adjustable clip in/out points. Show the detection confidence. Full-video scrubbing always available |
| Shot classification or counts badly wrong | TennisKeeper, Tennis Plus, ServeLab [S3] | Gate each automatic metric behind a labeled-footage benchmark (already in brief). Show "estimate" plus an edit control |
| Can't edit past points; no service-winner or forced-error categories; can't delete matches | MatchTrack, Smashpoint, Tennis Math reviews [S3][S10] | Edit point (winner, outcome, shot) anywhere in the timeline. Include service-winner and forced-error categories. Allow deleting matches and players |
| Data loss after updates or sync | MatchTrack (2024), Tennis Plus (iOS 13), TennisKeeper [S3] | Local-first persistence, migration tests and an export (CSV/JSON) |
| Watch app crashes or loses the match | Smashpoint (watchOS 2024–25), SwingVision notes, TennisKeeper [S3][S4] | Watch state must survive app termination (Smashpoint now advertises this). The phone stays the source of truth |
| Paywall layering and nickel-and-diming | TennisKeeper, ServeLab, PlaySight [S3] | One clear free tier plus one paid tier. No weekly plans. Show the price on the feature before it is used |
| Login and account friction | PlaySight, Smashpoint "Welcome NULL" [S3] | Sign in with Apple, plus optional local-only use with no account (MatchTrack, Swingli, AI Swing Coach prove the demand) |
| Hands-free recording (can't reach the record button on the fence) | AXEL AI review; TennisCut remote solves it [S3][S2] | Watch or second-phone remote start/stop, with camera battery and storage telemetry |
| Heat / thermal shutdown on court | SwingVision notes ("high temperatures", overheating disables audio feedback) [S4] | Thermal-state monitoring with graceful degradation: keep recording and drop real-time analysis |

---

## 8. Mapping to JOVRA's 20 planned screens (quick reference, INFERRED)

| Screen | Best external reference | Note |
|---|---|---|
| 4 Session setup | Smashpoint tracking depth; Tennis Math scoring rules | Offer depth: score only, then serve stats, then outcomes |
| 5 Court calibration | Toach "court lock" re-find; SwingVision Ground Mode | Detect the camera being bumped and re-lock |
| 6 Live capture | TennisCut remote with camera health; Smashpoint Watch scoring | "Manual score" badge is correct; add undo |
| 7 Import queue | PerfectSwing "notify when done"; SwingVision upload retry | Stage-by-stage states |
| 10 Smart replay | Smashpoint +2 s point padding, multi-angle tile; TennisCut rally list | Full-video scrub plus point list |
| 11 Shot map | SmartHit mini-map; Wingfield placement | Requires a ball-tracking feasibility gate |
| 12 Serve Lab | Toach and SmartHit phone speed; TennisServe phase checks | Keep "Estimated" and a calibration caveat |
| 13 Stroke Lab | AI Swing Coach skeleton; TorqAI 17 joints; INTER 3D | Keep "2D pose estimate" labelling |
| 14 Compare | Onform and CoachNow (table stakes) | Linked dual timeline is table stakes |
| 15 Coaching plan | INTER fault grouping; AI Swing Coach one fix and one drill; Wingfield 0–100 drills | Evidence link is the differentiator |
| 16 Progress | Smashpoint trends and ELO; OverRally consistency spreads | Consider consistency (spread) metrics, not only averages |
| 17–18 Racket Vault / String journal | TennisKeeper string life; RacquetTune | Rare. Link strings to performance |
| 19 Storage & backup | — (none found) | White space |
| 20 Settings / privacy | Smashpoint private-by-default; Swingli no account | Keep it local-first |

---

## 9. Open questions / unverified

- INTER TENNIS pricing and real-world accuracy of single-phone 3D racket tracking (UNVERIFIED; no ratings).
- Which companion app In/Out v4 uses. The legacy iOS app was last updated 2018 (UNVERIFIED).
- Exact hardware pricing for Wingfield (summary sources mention €6,999 and £95/month; UNVERIFIED), PlaySight ($12.5K + $500/mo; UNVERIFIED, undated) and Hawk-Eye (about $60K/court; UNVERIFIED).
- Status of the Mouratoglou eCoaching app and of Mojjo (company-database descriptions only).
- Whether SwingVision will ship Android. Sibling notes cite an FAQ saying it is "working closely with Google engineers". If it does, §0.2 weakens.
- Play Store data for apps whose package names I didn't find, and per-country availability (US storefront only here).
- The keyword-classifier counts (40 of 48 AI-video entrants since 2025; 0 Google Drive mentions) depend on listing text. An app may support Drive without saying so in its description.

---

## Sources

All accessed 2026-10-07.

- **[S1]** iTunes Search API, US. `https://itunes.apple.com/search?term=<term>&entity=software&country=us&limit=50` for the 21 terms in §2, plus named searches (onform, hudl technique, dartfish, playsight, wingfield, playreplay, zepp, babolat, baseline vision, xbotgo, pivo, acemate, spiideo, zenniz, pb vision, pocket radar, bam video delay, racket string tension, tennis stringing, racquet tune, sevencourts, Tennis Math score stats, smart tennis sensor sony, foxtenn). Supported: the 347-app universe; ratings and counts for search-only rows (Pocket Radar, Dartfish, BaM, Video Delay, RacquetTune, String Master, PB Vision, Zenniz); the absence of Babolat, Sony and Tennis Math iOS apps; and description-text counts in §0 and §6.
- **[S2]** iTunes Lookup API, US. `https://itunes.apple.com/lookup?id=989461317,1490334045,1505604446,1098174650,977481057,976177330,1417782417,1529296863,1511793266,1298138902,1248208481,738455328,1158767577,1097388824,596598472,1643006248,6754323620,6743446008,6738239839,6743368519,6748925788,6503030439,348758017,1478586247,1473778493,400876654,1446168061,6736381821,6504378328,1636033912,6753039051,6789373943,6774433013,6768219425,6751231905,6746733042,6477877180,1581355712,1567512653,1381218249,1433835828,1060696990,6761056366,1592978649,1316338557,6741385759,6762805167,6758722710,6776502111,6774777838,6769370968,6751442505,6740051429,6497227261,6736619440,6738391148,6474873410,1310424950,1570477197,412223222,6754282617,6451323049,6765685415,6761398799,6757488806,6759643780,6771581715,6800581766,6785981158&country=us`. Supported: ratings and counts, versions, current-version and first-release dates, min OS, Watch support, descriptions (feature claims) and release notes for every App Store row.
- **[S3]** App Store customer reviews RSS. `https://itunes.apple.com/us/rss/customerreviews/page=<1..3>/id=<id>/sortby=mostrecent/json` for PlaySight 976177330, Smashpoint 1098174650, Tennis Plus 1158767577, TennisKeeper 1097388824, MatchTrack 977481057, TennisCut 6754323620, Toach 6774433013, Wingfield 1417782417, Baseline Vision 1511793266, ServeLab 6746733042, Spherely 6743446008, AI Tennis Swing Coach 6776502111, Speed Gun 1446168061, Stalker 1473778493, Kai 6748925788, OverRally 6789373943, SmartHit 6751442505, AXEL 6738391148 and 135 Tennis 1381218249. Supported: the complaint themes in §3, §4 and §7 (paraphrased).
- **[S4]** SwingVision App Store page. `https://apps.apple.com/us/app/id989461317`. Supported: the IAP list (Plus, Pro, Max prices) and the version history 11.9.43–11.9.67 (free tier, Ground Mode, Ball Tracer, padel, USTA Connect, Max family plan, and reliability fixes).
- **[S5]** Smashpoint App Store page. `https://apps.apple.com/us/app/id1098174650`. Supported: Pro and Elite IAPs, platforms, and version history 3.2.5–3.4 (Critical Point video, second camera).
- **[S6]** Onform App Store page. `https://apps.apple.com/us/app/id1490334045`. Supported: the 10 IAP tiers.
- **[S7]** SevenSix App Store page. `https://apps.apple.com/us/app/id1505604446`. Supported: membership and per-analysis IAPs.
- **[S8]** App Store pages (IAP sections), `https://apps.apple.com/us/app/id<id>` for 6754323620 (TennisCut), 6774433013 (Toach), 6776502111 (AI Tennis Swing Coach), 6759643780 (TorqAI), 6751442505 (SmartHit), 6751231905 (PerfectSwing), 1478586247 (eyes3), 1417782417 (Wingfield), 1097388824 (TennisKeeper), 6789373943 (OverRally), 1581355712 (XbotGo), 1567512653 (Pivo), 596598472 (CoachNow), 1643006248 (VisualEyes), 6746733042 (ServeLab), 1381218249 (135 Tennis), 1636033912 (Tennis Notes), 6754282617 (ScoreBot), 6503030439 (Tennis IQ), 6768219425 (SportArc), 6771581715 (FlowState), 6800581766 (TennisServe), 6785981158 (CourtNotes), 6477877180 (INTER, no IAP shown), 1529296863 (PlayReplay), 976177330 (PlaySight) and 1511793266 (Baseline Vision). Supported: §3 price columns and §5.
- **[S9]** Google Play search pages. `https://play.google.com/store/search?q=<q>&c=apps&hl=en_US&gl=US` for q = swingvision, tennis video analysis, tennis tracker, tennis ai coach, tennis line calling, onform video analysis, sevensix tennis, tennis math, playsight, baseline vision tennis, zenniz, playreplay, pb vision, xbotgo, perfectswing, toach tennis and smarthit tennis. Supported: that no SwingVision Inc., SevenSix or Toach listing appears; long-tail Android AI apps; PerfectSwing Android rating.
- **[S10]** Google Play detail pages. `https://play.google.com/store/apps/details?id=<pkg>&hl=en_US&gl=US` for com.tennismath.ui.android, com.app.OnForm, com.wingfield, com.tenniscut.mobile, com.inter.tennis, net.smashpoint.android, com.tennis.ai, com.offcourtz, com.playsight.tennis, com.baselinevision, com.pb.vision.app, com.nabocorp.tennistracker.android.tennistracker, com.DrAndreZenner.TennisServeSpeedTracker, com.getmatchpointai.app, com.racketstats, com.smartennis.app, com.tennasity.app, com.toptennistracker, com.v1sports.coach and com.tennisia.app. Supported: Android ratings, counts, install bands, update dates, IAP ranges, the Tennis Math feature list ("iOS version" to come) and Play review themes.
- **[S11]** ITF PAT approval report, SwingVision PAT-25-037 (issued 31/10/2025, v11.9.6). `https://www.itftennis.com/media/15294/pat-25-037-approval-report-swingvision.pdf`, with certificate at `https://www.itftennis.com/media/15293/pat-approval-certificate-swingvision.pdf`. Supported: ITF PAT approval; 60 fps rear-camera capture; one or two devices; 3D ball location at hit, net and bounce; shot and spin type; backend server; Watch not permitted in competition; approval does not establish accuracy.
- **[S12]** ITF Classified ELC Systems. `https://www.itftennis.com/en/about-us/tennis-tech/classified-elc-systems/`. Supported: Gold (Hawk-Eye, Foxtenn, Bolt6) and Silver (PlayReplay, Zenniz) classifications and their surface scope.
- **[S13]** ITF PAT report URLs (existence of approvals only). Wingfield `https://m.itftennis.com/media/6223/pat-19-019-pat-approval-report-wingfield-final-rev-0.pdf`; Baseline Vision `https://www.itftennis.com/media/16306/baseline-vision-pat-approval-report-pat-23-029.pdf`; Zenniz `https://m.itftennis.com/media/14160/pat-24-035-pat-approval-report-zenniz.pdf`; Babolat `https://m.itftennis.com/media/6205/pat-13-004-pat-approval-report-babolat-rev-1.pdf`; Sony `https://m.itftennis.com/media/6221/pat-14-008-pat-approval-report-sony-final-rev-1.pdf`; Zepp `https://m.itftennis.com/media/6225/pat-15-012-pat-approval-report-zepp-v0.pdf`. Also retailer "discontinued" pages for Zepp, Sony and Babolat sensors via tennisnuts.com search results (UNVERIFIED).
- **[S14]** USTA Missouri Valley, "Edmond Center Court … PlayReplay" (2026-03-25). `https://www.usta.com/en/home/stay-current/missourivalley/oklahoma/edmond-center-court-playreplay-electronic-line-calling-system.html`. Supported: 4 net-post cameras, about $3,200 per court per year, first year USTA-funded, and the feature list.
- **[S15]** Wamda, "Sweden's PlayReplay targets MENA expansion with new $12m investment" (2026-05-19). `https://www.wamda.com/en/2026/05/sweden-playreplay-targets-mena-expansion-new-12m-investment`. Supported: the $12M raise, about 350K matches, ~150M line calls and ITF Silver.
- **[S16]** Wingfield products. `https://www.wingfield.io/en/products`. Supported: Cam+ / AI Pro, hybrid pricing (hardware plus monthly fee), requirements (power, 5 Mbit/s upload) and sports.
- **[S17]** Baseline Vision. `https://www.baselinevision.com/`. Supported: net-post camera with no power or Wi-Fi, 20 s setup, feature list and the UTR Pro Tennis Tour partnership.
- **[S18]** Gadgets & Wearables, In/Out v4 (2026-04-26). `https://gadgetsandwearables.com/2026/04/26/in-out-tennis-line-calling/`. Supported: $499 / $299 pricing, the net and line device design, the manufacturer accuracy claim and the "Too Close To Call" alert.
- **[S19]** SportAI, "SportAI Open beta is live". `https://sportai.com/news/sportai-open-beta-is-live`. Supported: web-app beta launched 2026-09-10 for tennis, padel and pickleball, and its roadmap.
- **[S20]** Al Jazeera, "Wimbledon to replace tennis line judges with electronic system from 2025" (2024-10-09). `https://www.aljazeera.com/sports/2024/10/9/wimbledon-to-replace-tennis-line-judges-with-electronic-system-from-2025`. Supported: Hawk-Eye Live ELC at Wimbledon from 2025 and ATP tour-wide ELC from 2025.
- **[S21]** PlaySight ownership (search-result summaries only; UNVERIFIED). `https://onthemoney.sportbusiness.com/news/playsight-targets-racket-sports-expansion-with-apex-investment/`; `https://www.calcalistech.com/ctech/articles/0,7340,L-3919547,00.html`. Supported: Slinger acquisition, then Connexa, then management buyout with APEX investment.
- **[S22]** Glenn Paulley, "Moving to OnForm from Hudl Technique" (2021-08-24). `https://glennpaulley.ca/curling/2021/08/24/moving-to-onform-from-hudl-technique/`. Supported: Hudl Technique discontinued and migration to OnForm (secondary).
- **[S23]** We Are College Tennis, Zenniz. `https://wearecollegetennis.com/zenniz/` (search summary). Supported: cameras plus microphones, the app on both stores and net-post LED units (secondary).
- **[S24]** Gadgets & Wearables, Tenniix (2025-05-12). `https://gadgetsandwearables.com/2025/05/12/tenniix-ball-launcher/` (search summary). Supported: Kickstarter over $240K, Basic $899 and Pro $1,299 (UNVERIFIED).
- **[S25]** Garmin forums, "App: Tennis AI" (Connect IQ). `https://forums.garmin.com/developer/connect-iq/f/showcase/350591/app-tennis-ai`. Supported: third-party Garmin stroke counting.
- **[S26]** CB Insights company pages (UNVERIFIED company-database descriptions). `https://www.cbinsights.com/company/mojjo`; `https://www.cbinsights.com/company/mouratoglou-ecoaching`. Supported: Mojjo single-camera smart court and the Mouratoglou eCoaching description.
- **[S27]** Prior focused research. `/Users/IDC2.5/jv/design-reference/brief/research.md` (local). Supported: the baseline claims re-checked in §1.
