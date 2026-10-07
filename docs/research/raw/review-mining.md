# App Store review mining: tennis recording and analysis apps

Research notes for JOVRA Tennis. Prepared 2026-10-07 from public App Store data (US storefront).
Builds on `/Users/IDC2.5/jv/design-reference/brief/research.md`, which read a handful of reviews. This pass reads and codes **every written review the public feed returns** for five tennis recording/analysis apps (901 reviews), plus five adjacent apps as a cross-check (414 reviews). It ends with ranked "love" and "pain" lists to drive JOVRA's priorities.

**Evidence labels used throughout**

- **OBSERVED**: seen directly in a source (an App Store listing, the iTunes API, the review feed), or computed by a script from that data.
- **INFERRED**: my reasoning from observed data.
- **UNVERIFIED**: a claim made by a reviewer or another party that I could not check against a primary source.

Review text is quoted only where the exact wording matters, and never more than a few words. Everything else is paraphrased.

---

## 0. Key findings

1. **Reliability is the biggest complaint by a wide margin.** OBSERVED (computed). Across 289 one- and two-star reviews of the five core apps, **44%** mention at least one of: crashes or bugs, recording failing or footage lost, uploads/processing/exports stuck, or cloud playback failing. This holds for all five apps. In SevenSix's small US sample it covers **69%** of reviews.
2. **Money is the second biggest complaint.** OBSERVED (computed). **27%** of one- and two-star core reviews complain about price, paywall changes, trial or billing surprises, or ads. Price complaints about SwingVision went from 2% of reviews (Nov 2019–2022) to 9% (2023–2026). Paywall complaints went from 0% to 6%. Onform's ratings collapsed in 2021 (2.62★ average) when it moved Hudl Technique users onto a paid plan.
3. **Players love the data most, and they love it even when they doubt it.** OBSERVED (computed). Stats depth is the most-praised theme (158 reviews, 127 of them SwingVision). Yet SwingVision complaints about AI accuracy (tracking, line calls, auto-scoring, segmentation, player ID) rose from about 4% of reviews (Nov 2019–2022: 5 of 141) to about 18% (2023–2026: 51 of 287, union of codes). INFERRED: players want the numbers, but they also want to see each number's evidence and be able to correct it.
4. **The second-most-praised outcome is seeing yourself on video, not the AI.** OBSERVED (computed). "It made me better / I finally saw what I actually do" appears in 91 reviews. Praise for replay, slow-motion and self-review in SwingVision reviews grew in 2025–2026: self-review 2%→7%, replay controls 1%→6%. Praise for auto-scoring (7%→2%) and stats (30%→19%) fell. INFERRED: the dependable video core is what keeps people. The AI layer is where trust erodes.
5. **Dead-time removal is SwingVision's single most distinctive feature** (31 praise mentions, almost no other app has it). OBSERVED. **Its failure mode is a top 2025–2026 complaint**: points cut off, rallies skipped, no way to watch the raw time between points (segmentation complaints rose from 1% to 6%). INFERRED: JOVRA needs an always-available raw timeline beside any auto-cut.
6. **Apple Watch is both a reason to buy and a source of failures.** OBSERVED (computed). 33 reviews praise wrist scoring. 55 complain about watch or second-device sync. A recurring pattern is the watch showing "recording" while the phone captured nothing. Several reviewers without a watch struggled to set the app up, needing a second phone or iPad and repeated attempts.
7. **Owning your own footage is a smaller theme but carries a lot of emotion.** OBSERVED (computed). 23 reviews ask for raw or original video, camera-roll copies or backups, or complain about history being locked (SwingVision locked old sessions after 30 days in March 2023, and after 7 days by 2026, per reviewers; UNVERIFIED as policy). INFERRED: this directly supports Jon's "my video, my Drive" requirement.
8. **SwingVision's written reviews are getting worse even though its headline rating holds steady.** OBSERVED. The listing shows **4.71★ from 4,928 ratings**. Its 490 written reviews average **3.58★**; 2026 so far averages **2.98★ (n=50)**, the lowest since 2019. INFERRED: the headline rating hides real, current dissatisfaction that a reliability-first competitor can use. These complaints are not just historical.
9. **Onform's praise is about the coaching workflow, and mostly not tennis.** OBSERVED. 51 of 297 reviews mention golf; only 6 use tennis terms. What reviewers value: per-student folders, messaging, voice-over, side-by-side sync, responsive support. What fails: compare-sync, scrubbing that conflicts with drawing, and uploads.
10. **SwingVision's developer acknowledges the device-level problems in its own release notes.** OBSERVED. Version 11.9.67 (2026-09-27) lists better recording stability in high temperatures, a new low-storage warning, better iPhone–Apple Watch connection reliability, and a fix for recordings ending early. Heat is rarely named in reviews, but it is real.

---

## 1. Scope, app selection and method

### 1.1 Apps

| Role | App | App ID | Listing rating (OBSERVED, iTunes lookup 2026-10-07) | Version / date | Why included |
|---|---|---|---|---|---|
| Core (assigned) | SwingVision: Tennis Pickleball | 989461317 | 4.706★ / 4,928 ratings | 11.9.67 (2026-09-27) | Closest competitor |
| Core (assigned) | Onform: Video Analysis App | 1490334045 | 4.786★ / 8,666 | 4.7.3 (2026-10-06) | Two-video comparison and coaching workflow |
| Core (assigned) | sevensix – Tennis AI Coach | 1505604446 | 4.191★ / 68 | 4.0.2 (2026-10-07) | Tennis stroke AI |
| Core (selected) | Smashpoint Tennis Tracker | 1098174650 | 4.509★ / 462 | 3.4 (2026-09-30) | Most-rated tennis-named analysis app found. A match charting/stats app that **added 4K/60 fps point replays and a second fence camera in v3.4** (2026-09-30), so it is now also a recorder (OBSERVED, listing notes) |
| Core (selected) | PlaySight | 976177330 | 2.873★ / 134 | 11.6.1 (2026-09-14) | Most-rated tennis-origin video recording, analytics and streaming app (SmartCourt) found by search. Many of its reviews concern non-tennis venue livestreams (see 7.3) |
| Supplementary | CoachNow | 596598472 | 4.86★ / 13,023 | 8.0 | Multi-sport coach video app, an Onform analogue |
| Supplementary | Scoreboard Pro: Score & Record | 496758984 | 3.92★ / 358 | 8.0.4 | Records video with the score burned in (multi-sport) |
| Supplementary | VisualEyes: Video Coaching App | 1643006248 | 4.78★ / 402 | 2.3.3 | Coach's Eye replacement |
| Supplementary | MatchTrack Tennis Score Keeper | 977481057 | 4.63★ / 280 | 2026.7 | Tennis charting |
| Supplementary | Tennis Plus (Apple Watch swing analyzer, $9.99) | 1158767577 | 3.65★ / 109 | 1.7.1 | Watch-sensor swing analysis |

**Selection rule for the two extra core apps (INFERRED; my judgement).** I ran about 40 iTunes search queries, of which about 22 returned data and the rest were rate-limited (for example "tennis video analysis", "tennis recording", "tennis line calling", "tennis swing analysis", "tennis stats tracker", "tennis AI coach", "line calling", "slow motion video analysis sports"). From the results I excluded games, live-score and news apps, and court-booking/social apps, then ranked what was left by `userRatingCount`.

- Smashpoint (462) is the most-rated app with tennis in its name that analyzes the user's own play.
- PlaySight (134) is the most-rated tennis-origin video recording and analytics app.
- VisualEyes (402) and Scoreboard Pro (358) have more ratings than PlaySight, but they are generic multi-sport tools. I coded them as supplementary.
- No tennis app found other than SwingVision has more than about 500 ratings and also records video. OBSERVED.

### 1.2 Retrieval (OBSERVED)

- **Feed:** `https://itunes.apple.com/us/rss/customerreviews/page=<1..10>/id=<id>/sortby=mostrecent/json`, fetched page by page until a page came back empty. Raw JSON is kept only in the session scratch directory, not in the repo.
- **SwingVision:** 490 reviews (pages 1–9 full, page 10 had 40). A second pass with `sortby=mosthelpful` returned **exactly the same 490 IDs**. INFERRED: the feed exposes one capped pool of about 500 reviews, and this pool reaches back to 2016.
- **SevenSix:** only 11 US reviews. I added the `gb`, `ca`, `au`, `nz` and `ie` storefronts, which gave one more review each from gb and ca and nothing else (n=13).
- **Ratings vs. written reviews:** the listing rating is computed over all star ratings. The feed only contains written reviews. SwingVision has 4,928 ratings but only 490 written reviews in the feed. Written reviews skew negative (see 2.1).

### 1.3 Coding method

- **Codebook:** defined before coding (section 3). 19 praise codes, 22 complaint codes and 4 context tags. One review can carry several codes.
- **Coder:** a Python rule-based classifier. It splits each review (title + body) into clauses at sentence ends and at contrast words (*but, however, although, except, unfortunately, …*).
  - A theme fires when a clause matches the theme's topic pattern **and** the clause's polarity cues agree with the theme's direction.
  - Some complaint themes are negative by definition (crash, stuck uploading, lost recording) and fire on the topic alone.
  - Accuracy and scoring themes need explicit inaccuracy language ("off", "inaccurate", "80%", "100 mph serve" and similar).
  - If a clause has topic words but no polarity cue, the star rating decides: 5★ counts as praise, 1–2★ as complaint, 3–4★ as neither.
- **Validation (INFERRED from my manual judgement):**
  - **Round 1:** a stratified random sample of 48 reviews (25 SwingVision, 12 Onform, 4 Smashpoint, 4 PlaySight, 3 SevenSix). Precision ≈ **90%** (69 of 77 assigned codes correct). Recall ≈ **83%**. I tuned the rules on the misses.
  - **Round 2:** a fresh holdout of 40 reviews, not used for tuning. Precision ≈ **92%** (74 of 80). Recall ≈ **80%**.
  - **Consequence:** the counts below are **conservative lower bounds** of how often each theme appears. Theme *ranks* are more reliable than exact counts.
  - **Known weak spots:**
    - Generic "doesn't work" lines are coded as crash/bug.
    - Praise for a human coach in Onform reviews sometimes picks up app-praise codes.
    - Player-identification burden is under-counted.
    - Heat is rarely named directly.
- **Reading:** besides the automated coding, I read every SwingVision (490), Onform (297), SevenSix, Smashpoint, PlaySight, VisualEyes, MatchTrack and Tennis Plus review. I skimmed the low-star CoachNow and Scoreboard Pro reviews. The examples in sections 6–8 come from this reading.
- **Reproducibility:** the scripts (`code.py`, `analyze.py`, `validate.py`) are in the session scratchpad (`/private/tmp/claude-502/-Users-IDC2-5-jv/<session>/scratchpad/reviews/`). That directory is temporary and outside the repo, as instructed.

---

## 2. Dataset summary (OBSERVED, computed)

### 2.1 Counts, date range and star distribution

| App | Reviews | Date range | Mean ★ (written) | Listing ★ | 5★ | 4★ | 3★ | 2★ | 1★ | ≤2★ share |
|---|---|---|---|---|---|---|---|---|---|---|
| **SwingVision** | 490 | 2016-10-20 → 2026-10-04 | **3.58** | 4.71 | 235 (48%) | 56 (11%) | 54 (11%) | 46 (9%) | 99 (20%) | 30% |
| **Onform** | 297 | 2020-03-28 → 2026-09-26 | **3.72** | 4.79 | 179 (60%) | 13 (4%) | 16 (5%) | 22 (7%) | 67 (23%) | 30% |
| **SevenSix** | 13 (11 US + 1 GB + 1 CA) | 2022-07-27 → 2026-08-15 | **2.31** | 4.19 | 3 | 0 | 1 | 3 | 6 | 69% |
| **Smashpoint** | 56 | 2016-07-06 → 2026-01-21 | **3.88** | 4.51 | 33 (59%) | 6 | 2 | 7 | 8 | 27% |
| **PlaySight** | 45 | 2015-05-26 → 2026-08-15 | **2.11** | 2.87 | 8 (18%) | 2 | 4 | 4 | 27 (60%) | 69% |
| CoachNow (supp.) | 175 | 2013-02-06 → 2026-09-03 | 4.09 | 4.86 | 121 | 10 | 10 | 7 | 27 | 19% |
| Scoreboard Pro (supp.) | 131 | 2012-01-29 → 2024-04-07 | 3.28 | 3.92 | 42 | 28 | 17 | 13 | 31 | 34% |
| VisualEyes (supp.) | 26 | 2023-01-10 → 2026-09-04 | 4.27 | 4.78 | 16 | 4 | 4 | 1 | 1 | 8% |
| MatchTrack (supp.) | 39 | 2015-07-31 → 2026-02-14 | 3.87 | 4.63 | 19 | 9 | 4 | 1 | 6 | 18% |
| Tennis Plus (supp.) | 43 | 2016-10-12 → 2023-07-28 | 2.33 | 3.65 | 7 | 3 | 7 | 6 | 20 | 60% |

INFERRED: in every app, written reviews average 0.6–1.9★ below the listing rating. Read written reviews as a sample weighted toward complaints. Do not read them as the satisfaction distribution.

### 2.2 Average stars by year (written reviews)

- **SwingVision:**

  | Year | 2016 | 2017 | 2018 | 2019 | 2020 | 2021 | 2022 | 2023 | 2024 | 2025 | 2026 (to Oct 4) |
  |---|---|---|---|---|---|---|---|---|---|---|---|
  | Mean ★ | 5.00 | 3.53 | 3.42 | 3.05 | 3.79 | 4.00 | **4.49** | 3.23 | 3.26 | 3.60 | **2.98** |
  | n | 3 | 15 | 26 | 21 | 34 | 36 | 68 | 69 | 69 | 99 | 50 |

  - **2022 is inflated by review bursts.** OBSERVED: 2022-07-18/19 brought 16 reviews, all 5★, and 2022-10-07/08 brought 12 reviews (11 at 5★, one at 4★). Without those four days, 2022 averages **4.15 (n=40)**. INFERRED: probably an in-app prompt or a community call to review. A smaller burst of 5★ reviews appears in Nov 2025.
  - **Era split.** Reviews before 2019-11 describe "Swing", an Apple Watch shot and score tracker with social features. The video era starts around v5.0 (a 2019-11-01 review notes that SwingVision needed an iPhone XS or later). INFERRED from content. Pre-video era: n=62, mean 3.45. Video era: n=428, mean 3.59.
- **Onform:** 2020 **5.00** (7) · 2021 **2.62** (73) · 2022 3.68 (47) · 2023 **4.32** (44) · 2024 4.29 (48) · 2025 4.17 (52) · 2026 3.62 (26). The 2021 trough matches the Hudl Technique migration: 53 reviews mention Hudl or Technique, 42 of them from 2021.
- **SevenSix:** 2022 5.00 (2) · 2023 1.50 (2) · 2024 2.00 (6) · 2025 1.50 (2) · 2026 2.00 (1). Every review since 2023 is 3★ or lower except one 5★ ("amazing", 2024).
- **Smashpoint:** 2016–2019 averages 4.1–5.0 · 2020 3.43 · 2022 1.60 (5) · then one review a year. Reviews show the app stayed on v2.6 from about 2023 until v3.x; one 2024 review worried the app had no updates for years.
- **PlaySight:** 2019–2022 averages 1.0–1.5 · 2026 2.86 (7).

### 2.3 Prices on the listings (OBSERVED via App Store page fetch, 2026-10-07)

| App | In-app purchases listed |
|---|---|
| SwingVision | Plus $14.99/mo or $95.99/yr · Pro $24.99/mo or $179.99/yr · Max $39.99/mo or $299.99/yr |
| Onform | Personal $4.99/mo or $49.99/yr · Coach $29.99/mo or $299.99/yr · Individual Standard $9.99/mo, Premium $14.99/mo · Coach Basic $19.99/mo, Standard $39.99/mo, Pro $59.99/mo · Team/Academy $79/mo |
| SevenSix | $14.99/mo · $149.99/yr (also a 14-day-trial SKU and a Wilson promo SKU) · per-analysis packs: 1 for $1.99, 3 for $3.99, 5 for $4.99 |
| Smashpoint | Pro $5.99/mo, $14.99/3 mo, $39.99/yr · Elite $149/yr |

**Reviewer-reported SwingVision price and plan history (UNVERIFIED):**

- About $100/yr, then $120/yr, then $150–160/yr in 2023, then $179.99/yr from 2024.
- A $60/yr "semi-pro" tier existed in 2021.
- Free tier: 2 hours of processing per month.
- Pro cap: "30 hours/month" (several reviewers). One 2026-10 reviewer says a Pro account was blocked after about 4 hours.
- Free-tier history lock: sessions older than 30 days (March 2023), sessions older than 7 days (a 2026 review).
- A stick + 1 free month bundle converted to a $179 annual charge (2026-04).

---

## 3. Codebook (defined before coding; multi-label)

**Praise codes (P_)**

| Code | Definition (what counts) | Typical cues |
|---|---|---|
| P_AUTOEDIT | Dead time removed; match auto-segmented into points or rallies; time saved editing | "dead time", "only the points", "2-hour match in 20 minutes" |
| P_AUTOSCORE | Score keeping (AI auto-score or live/watch scoring) works or is valued | auto scoring, keep score, track matches |
| P_LINECALL | Line calling or challenges valued | line calls, challenge, Hawk-Eye-like |
| P_HIGHLIGHT | Highlights, favorites, best or longest rallies, sharing/export to social | highlight reels, share, Instagram |
| P_ACCURACY | Tracking, speed or calls perceived as accurate | "scary accurate", checked vs Hawk-Eye |
| P_STATS | Depth of stats: speed, spin, placement, heat maps, match stats, insights | stats, mph, placement, heat map |
| P_SELFREVIEW | Seeing yourself on video as the learning mechanism | "seeing yourself on video", "video showed I…" |
| P_REPLAY | Replay controls: slow-mo, frame stepping, zoom, speed control, replay point | slow motion, 0.1x, double-tap replay |
| P_ANNOTATE | Drawing, angles, voice-over, skeleton or wireframe, timers | voice-over, markup, skeleton |
| P_COMPARE | Side-by-side or overlay comparison, synced clips, comparing to pros | side by side, overlay, sync |
| P_COACH | Value for coaches, students or parents; coach communication | coach, students, lessons, parents |
| P_EASE | Easy, simple, intuitive, quick to set up | easy, intuitive, user friendly |
| P_VIDEOQ | Video quality | HD, crystal clear, great quality |
| P_SUPPORT | Customer support praised | responsive, support from the CEO |
| P_IMPROVE | Outcome: the player or student improved; "game changer" | improved my serve, UTR went up |
| P_MOMENTUM | Product keeps getting better; frequent updates | "keeps getting better" |
| P_VALUE | Worth the money | worth every penny |
| P_WATCH | Apple Watch integration praised | scoring from my wrist |
| P_ORGANIZE | Library organization: folders, tags, per-athlete storage, notes | folders, each athlete |

**Complaint codes (C_)**

| Code | Definition | Typical cues |
|---|---|---|
| C_PRICE | Price or subscription too high | too expensive, $180??, priced out |
| C_PAYWALL | Paywall or plan changes; features removed or locked; quotas; forced upgrade | 10-video limit, locked after 30 days, took away |
| C_BILLING | Trial converted unexpectedly, surprise charges, refunds, can't cancel | charged $179, free trial scam |
| C_ACC_CALLS | Line-call accuracy | line calls not reliable, way off |
| C_ACC_STATS | Accuracy of tracking or stats: speed, placement, spin, shot type, counts, swing detection; also general "inaccurate" | serve 120 mph, placement off by feet |
| C_SCORE | Auto-scoring wrong, or correcting the score is hard or impossible | can't edit score, AI scoring never right |
| C_SEGMENT | Auto-edit cuts off, skips or misses points or rallies | clips cut too soon, skipped 2 minutes |
| C_RECFAIL | Recording stopped or failed; footage, session or data lost | stopped recording, only 1 of 3 sets |
| C_VIDEOQ | Resolution or fps caps, export degradation, orientation or flip problems | limited to HD, compressed export |
| C_CRASH | Crashes, freezes, bugs, broken after update, general "doesn't work" | crashes, glitchy, unusable after update |
| C_SLOW | Upload, processing, analysis, export or import slow or stuck | stuck uploading, hours to process |
| C_DEVICE | Heat, battery, device storage, cache, memory | 100 GB of storage, cache can't be cleared |
| C_SETUP | Setup, mounting, framing or calibration difficulty, hardware stick | alignment, court undetected, ladder |
| C_WATCHSYNC | Apple Watch or second-device dependency and sync failures | watch said recording, remote feed drops |
| C_SUPPORT | Support poor, slow or bot-only | no response, AI bot, weeks |
| C_CLOUD | Cloud sync and playback problems | "slow internet" error, black video on Chrome |
| C_OWNERSHIP | Access to own video or data: raw or original video, camera-roll copy, backup, export, lock-in | can't access raw video, export every session |
| C_UI | UI confusion, learning curve, no manual, hard to find things | not intuitive, flywheel, no instructions |
| C_DOUBLES | Doubles weakness and manual player-identification burden | misattributed hitter, tag every player |
| C_PLATFORM | No Android or iPad support, old devices dropped, desktop/web gaps | no Android, iPad not supported |
| C_ADS | Ads | ads during scoring |
| C_LOGIN | Login or account problems | forced Google login, locked out |

**Context tags (X_):** X_REQUEST (contains a feature request) · X_PICKLEBALL · X_NONTENNIS (golf, baseball, track and similar) · X_TENNIS (tennis-specific terms).

---

## 4. Theme counts per app

Counts are reviews with the code. Percentages are of that app's reviews. "Recent" means 2025-01-01 to 2026-10-07. OBSERVED (computed); lower bounds (see 1.3).

| Code | SwingVision (490) | Onform (297) | SevenSix (13) | Smashpoint (56) | PlaySight (45) | **Core total (901)** | Recent |
|---|---|---|---|---|---|---|---|
| P_STATS | 120 (24%) | 10 (3%) | 1 | 16 (29%) | 3 (7%) | **150** | 34 |
| P_EASE | 62 (13%) | 64 (22%) | 1 | 12 (21%) | 5 (11%) | **144** | 35 |
| P_COACH | 35 (7%) | 94 (32%) | 1 | 8 (14%) | 2 | **140** | 38 |
| P_IMPROVE | 60 (12%) | 15 (5%) | 2 | 0 | 1 | **78** | 23 |
| P_HIGHLIGHT | 38 (8%) | 17 (6%) | 0 | 1 | 5 (11%) | **61** | 13 |
| P_VALUE | 36 (7%) | 20 (7%) | 0 | 0 | 1 | **57** | 17 |
| P_SUPPORT | 20 (4%) | 29 (10%) | 0 | 5 (9%) | 0 | **54** | 15 |
| P_WATCH | 29 (6%) | 1 | 0 | 3 | 0 | **33** | 5 |
| P_AUTOEDIT | 31 (6%) | 1 | 0 | 0 | 0 | **32** | 6 |
| P_AUTOSCORE | 24 (5%) | 0 | 0 | 6 (11%) | 0 | **30** | 3 |
| P_COMPARE | 9 (2%) | 20 (7%) | 1 | 0 | 0 | **30** | 6 |
| P_MOMENTUM | 19 (4%) | 8 (3%) | 1 | 1 | 0 | **29** | 7 |
| P_ACCURACY | 21 (4%) | 3 | 0 | 0 | 0 | **24** | 8 |
| P_ANNOTATE | 2 | 18 (6%) | 1 | 0 | 1 | **22** | 3 |
| P_REPLAY | 14 (3%) | 6 (2%) | 0 | 0 | 1 | **21** | 11 |
| P_SELFREVIEW | 16 (3%) | 2 | 0 | 0 | 0 | **18** | 12 |
| P_ORGANIZE | 2 | 15 (5%) | 0 | 0 | 1 | **18** | 6 |
| P_VIDEOQ | 12 (2%) | 2 | 0 | 0 | 1 | **15** | 7 |
| P_LINECALL | 9 (2%) | 0 | 0 | 0 | 0 | **9** | 4 |
| C_CRASH | 99 (20%) | 26 (9%) | 8 (62%) | 8 (14%) | 10 (22%) | **151** | 40 |
| C_PRICE | 29 (6%) | 31 (10%) | 0 | 0 | 0 | **60** | 18 |
| C_WATCHSYNC | 49 (10%) | 3 | 0 | 3 (5%) | 0 | **55** | 16 |
| C_SLOW | 32 (7%) | 9 (3%) | 4 (31%) | 0 | 3 (7%) | **48** | 20 |
| C_UI | 21 (4%) | 20 (7%) | 0 | 1 | 6 (13%) | **48** | 16 |
| C_RECFAIL | 29 (6%) | 5 (2%) | 1 | 3 (5%) | 1 | **39** | 15 |
| C_PAYWALL | 15 (3%) | 21 (7%) | 0 | 1 | 0 | **37** | 15 |
| C_SUPPORT | 28 (6%) | 3 | 1 | 2 | 3 (7%) | **37** | 17 |
| C_ACC_STATS | 33 (7%) | 0 | 1 | 1 | 1 | **36** | 13 |
| C_PLATFORM | 25 (5%) | 5 (2%) | 0 | 0 | 1 | **31** | 8 |
| C_CLOUD | 19 (4%) | 5 (2%) | 0 | 0 | 3 (7%) | **27** | 9 |
| C_OWNERSHIP | 17 (3%) | 6 (2%) | 0 | 0 | 0 | **23** | 6 |
| C_LOGIN | 10 (2%) | 6 (2%) | 0 | 2 | 4 (9%) | **22** | 8 |
| C_SCORE | 18 (4%) | 0 | 0 | 1 | 0 | **19** | 6 |
| C_SETUP | 16 (3%) | 1 | 0 | 0 | 1 | **18** | 6 |
| C_BILLING | 12 (2%) | 2 | 0 | 0 | 3 (7%) | **17** | 6 |
| C_SEGMENT | 15 (3%) | 0 | 0 | 0 | 0 | **15** | 9 |
| C_ACC_CALLS | 12 (2%) | 0 | 0 | 0 | 0 | **12** | 6 |
| C_DEVICE | 6 (1%) | 4 (1%) | 0 | 0 | 0 | **10** | 4 |
| C_VIDEOQ | 6 (1%) | 2 | 0 | 0 | 1 | **9** | 2 |
| C_DOUBLES | 6 (1%) | 0 | 0 | 1 | 0 | **7** | 2 |
| C_ADS | 2 | 2 | 0 | 0 | 0 | **4** | 1 |
| X_REQUEST | 54 (11%) | 26 (9%) | 2 | 9 (16%) | 3 | 94 | 19 |
| X_PICKLEBALL | 27 (6%) | 0 | 0 | 0 | 0 | 27 | 17 |
| X_NONTENNIS | 8 | 89 (30%) | 0 | 0 | 6 (13%) | 103 | 28 |

**Umbrella view.** A review counts once per umbrella. OBSERVED (computed).

| Umbrella | SwingVision | Onform | SevenSix | Smashpoint | PlaySight | Core total | Share of 289 ≤2★ core reviews |
|---|---|---|---|---|---|---|---|
| **Reliability** (crash ∪ rec-fail ∪ slow/stuck ∪ cloud) | 133 (27%) | 36 (12%) | 9 (69%) | 9 (16%) | 16 (36%) | 203 | **127 (44%)** |
| **Money** (price ∪ paywall ∪ billing ∪ ads) | 51 (10%) | 47 (16%) | 0 | 1 | 3 (7%) | 102 | **79 (27%)** |
| **Capture friction** (setup ∪ watch/2nd device ∪ heat/storage) | 63 (13%) | 7 (2%) | 0 | 3 | 1 | 74 | **41 (14%)** |
| **AI accuracy** (stats ∪ calls ∪ score ∪ segmentation ∪ player ID) | 60 (12%) | 0 | 1 | 2 | 1 | 64 | **33 (11%)** |
| **Data ownership** | 17 (3%) | 6 (2%) | 0 | 0 | 0 | 23 | **13 (4%)** |

INFERRED: AI-accuracy complaints come mostly from 3★ reviews, not 1★. Their share of ≤2★ reviews is only 11%, while 18% of 2023–26 SwingVision reviews raise them. These are users who stay but don't trust the numbers. Reliability and money drive the 1★ reviews.

**Keyword spot counts for JOVRA-specific signals.** Simple regex counts, not coder output. OBSERVED.

| Signal | SwingVision video era (n=428) | SwingVision 2025–26 (n=149) | Onform (297) | SevenSix + Smashpoint + PlaySight (114) |
|---|---|---|---|---|
| Stick, mount or tripod hardware mentioned | 35 | 16 | 4 | 1 |
| Ball machine or serve-practice modes | 17 | 6 | 0 | 0 |
| iPad, large-screen or desktop review | 16 | 5 | 10 | 2 |
| Post-match score or point correction | 14 | 5 | 0 | 1 |
| Raw or original video, camera-roll copy | 12 | 3 | 2 | 0 |
| Phone storage, GB, cache | 11 | 3 | 7 | 0 |
| Heat or battery | 8 | 1 | 1 | 0 |
| Resolution or fps (4K, 1080p, fps) | 8 | 3 | 1 | 1 |
| Needs Apple Watch or a second device | 7 | 2 | 1 | 0 |
| Doubles | 7 | 4 | 0 | 2 |
| Android or Windows wanted | 6 | 1 | 1 | 1 |
| Manual player identification burden | 6 (under-counted) | 2 | 0 | 0 |
| Pause recording | 5 | 1 | 2 | 0 |
| Left-handed support | 1 | 1 | 0 | 0 |

---

## 5. Trends: are the complaints recent or old?

### 5.1 SwingVision, video era only

Each cell shows reviews with the code and the share of that period's reviews. Direction compares the first and last periods. OBSERVED (computed).

| Code | Nov 2019–2022 (n=141, mean 4.15) | 2023–2024 (n=138, mean 3.25) | 2025–Oct 2026 (n=149, mean 3.39) | Direction |
|---|---|---|---|---|
| C_PRICE | 3 (2%) | 13 (9%) | 13 (9%) | ↑ |
| C_PAYWALL | 0 | 5 (4%) | 9 (6%) | ↑ |
| C_SUPPORT | 0 | 12 (9%) | 15 (10%) | ↑ |
| C_ACC_STATS | 4 (3%) | 13 (9%) | 13 (9%) | ↑ |
| C_ACC_CALLS | 0 | 6 (4%) | 6 (4%) | ↑ |
| C_SEGMENT | 1 (1%) | 5 (4%) | 9 (6%) | ↑ (still rising) |
| C_SCORE | 1 (1%) | **11 (8%)** | 6 (4%) | peaked 2023–24 |
| C_RECFAIL | 4 (3%) | 12 (9%) | 12 (8%) | ↑ |
| C_SLOW | 7 (5%) | 13 (9%) | 12 (8%) | ↑ |
| C_CLOUD | 1 (1%) | **11 (8%)** | 4 (3%) | peaked 2023–24 |
| C_OWNERSHIP | 3 (2%) | **9 (7%)** | 5 (3%) | peaked 2023–24 |
| C_SETUP | 1 (1%) | **10 (7%)** | 5 (3%) | peaked 2023–24 |
| C_UI | 1 (1%) | 7 (5%) | 10 (7%) | ↑ |
| C_WATCHSYNC | 10 (7%) | 16 (12%) | 13 (9%) | persistent |
| C_CRASH | 26 (18%) | 34 (25%) | 23 (15%) | persistent (high) |
| C_PLATFORM | 4 (3%) | 10 (7%) | 5 (3%) | → |
| P_STATS | 42 (30%) | 31 (22%) | 28 (19%) | ↓ |
| P_AUTOSCORE | 10 (7%) | 5 (4%) | 3 (2%) | ↓ |
| P_AUTOEDIT | 12 (9%) | 13 (9%) | 6 (4%) | ↓ |
| P_WATCH | 11 (8%) | 4 (3%) | 4 (3%) | ↓ |
| P_SUPPORT | 10 (7%) | 4 (3%) | 4 (3%) | ↓ |
| P_SELFREVIEW | 3 (2%) | 2 (1%) | 11 (7%) | ↑ |
| P_REPLAY | 1 (1%) | 4 (3%) | 9 (6%) | ↑ |
| P_IMPROVE | 20 (14%) | 15 (11%) | 21 (14%) | → |
| X_PICKLEBALL | 0 | 10 (7%) | 17 (11%) | ↑ |

INFERRED reading:

- **Recent and current:** price, paywall moves, support quality, segmentation misses, accuracy distrust, recording/upload failures, UI confusion. JOVRA can still win on these today.
- **Peaked in 2023–24, possibly partly fixed:** score correction, cloud playback, setup/framing, raw-video access. Possible fixes: an "Edit Point" path (cited in prior research), upload fixes (one 2023 reviewer updated to say slow uploads were fixed), the newer stick. They still show up in 2025–26, just less often.
- **Praise has shifted from the AI magic** (auto-score, stats) **to the basic video experience** (self-review, slow-mo replay).
- **Pickleball is diluting the reviews:** 27 reviews, mean 3.37★. Reviewers say pickleball lacks the ball-machine and serve modes, misclassifies spin and shots, and misattributes hitters in doubles. INFERRED: multi-sport expansion seems to have spread quality thin. JOVRA should stay tennis-first, as the brief says.

### 5.2 Onform

| Code | 2020–2021 (n=80, mean 2.83) | 2022–2023 (n=91, mean 3.99) | 2024–Oct 2026 (n=126, mean 4.10) |
|---|---|---|---|
| C_PRICE | **20 (25%)** | 5 (5%) | 6 (5%) |
| C_PAYWALL | **14 (18%)** | 0 | 7 (6%) |
| C_UI | 6 (8%) | 9 (10%) | 5 (4%) |
| C_CRASH | 9 (11%) | 8 (9%) | 9 (7%) |
| C_CLOUD | 0 | 0 | 5 (4%) |
| P_COACH | 19 (24%) | 27 (30%) | 48 (38%) |
| P_SUPPORT | 4 (5%) | 10 (11%) | 15 (12%) |
| P_COMPARE | 3 (4%) | 7 (8%) | 10 (8%) |
| P_MOMENTUM | 0 | 1 | 7 (6%) |

INFERRED: Onform's money complaints are mostly old (the 2021 Hudl migration). Free-tier removal returned in 2025: reviews from 2025-04 to 2025-10 report the free version removed and all features paywalled. Its recent complaints are upload/playback reliability and lag after updates. Its praise is increasingly about coach workflow and support.

---

## 6. Top themes with paraphrased examples

### 6.1 What players love

1. **Stats depth, from one phone (P_STATS 150; P_ACCURACY 24).**
   - SwingVision 5★, 2025-12-07: a 63-year-old 4.0 player and former D1 athlete values the match and shot stats, and filtering by shot type (return of serve, forehands) to review a two-hour match in 15–20 minutes.
   - SwingVision 4★, 2025-11-21: compared serve speed against a Hawk-Eye reading and found about 2% difference. Groundstroke speeds ran about 10% low, and the reviewer calls the line-call accuracy claim misleading.
   - INFERRED: accuracy praise and accuracy doubt often sit in the same review.
2. **Coach and student loop (P_COACH 140; P_ORGANIZE 18).**
   - SwingVision 5★, 2025-07-24: a USPTA Elite pro running a junior program shares sessions with parents and saves hours of manual analysis.
   - Onform 5★, 2024-04-07: a coach praises per-student folders, in-app messaging, private lesson notes, two-video analysis, voice-over, and adding parents or another coach to the thread.
3. **Ease of use (P_EASE 144).**
   - SwingVision 5★, 2020-09-15: press record and the app does the rest.
   - Onform 5★, 2023-11-22: simpler than competing tools; wants more voice commands so the phone needs no handling during sessions.
4. **It actually made me better / seeing myself (P_IMPROVE 78; P_SELFREVIEW 18).**
   - SwingVision 5★, 2024-07-11: reports going from about 9 UTR to as high as 10.9 after filming and analyzing every match. UNVERIFIED.
   - SwingVision 5★, 2025-08-07: video showed the forehand falling away and a late split step that the player had not felt.
5. **Highlights, favorites, sharing (P_HIGHLIGHT 61).**
   - SwingVision 5★, 2024-02-17: instant best rallies, rallies over 5 shots, favorites and social sharing replaced hours of manual editing; hitting partners now ask for it.
   - SwingVision 3★, 2024-06-15: auto-generated shorts export quickly to Instagram and TikTok, called a big value add even in a critical review.
6. **Worth the money (P_VALUE 57).**
   - SwingVision 5★, 2021-05-31: compares the cost to a roughly $400 radar gun and $25–50/hour lessons.
   - SwingVision 5★, 2025-11-08: worth every penny for recreational players chasing the next NTRP level.
7. **Responsive team and steady improvement (P_SUPPORT 54; P_MOMENTUM 29).**
   - SwingVision 5★, 2021-06-23: support came from the CEO.
   - Onform 5★, 2025-05-08: a support rep joined a call at short notice.
   - INFERRED: SwingVision support praise fell from 7% to 3% of reviews while support complaints rose to 10% (see 5.1).
8. **Wrist and live scoring (P_WATCH 33; P_AUTOSCORE 30).**
   - SwingVision 5★, 2025-11-04: scoring each point on the watch helps the player reset between points and ends score disputes.
   - SwingVision 5★, 2018-01-18: watch swipe gestures log winners and errors without opponents noticing.
9. **Analysis tools: slow-mo and frames, drawing, compare (P_REPLAY 21, P_ANNOTATE 22, P_COMPARE 30).**
   - SwingVision 5★, 2025-11-08: slow-motion replay lets the player pause mid-swing to find racket-drop issues.
   - Onform 5★, 2024-10-09: a javelin coach puts a best-practice example side by side or superimposed, in sync with the athlete's throw.
10. **Dead time removed (P_AUTOEDIT 32).**
    - SwingVision 5★, 2025-11-02: 1.5–2 hours of play becomes 15–20 minutes.
    - SwingVision 3★, 2023-08-02: a three-year user who no longer trusts the stats still keeps paying, mainly to strip non-tennis time.

Less frequent but notable:

- Video quality (15).
- Line-call challenges (9). SwingVision 5★, 2022-10-21: friends overturned bad calls with the challenge feature.

### 6.2 What players complain about

1. **Crashes, bugs, broken updates (C_CRASH 151; all 5 apps).**
   - SwingVision 3★, 2026-10-04: a near-daily user hits bugs at every step: exports fail repeatedly, only about 10 points detected in hour-long matches, reprocessing fails, and an iPhone 16e ran out of memory. Asks the team to fix bugs before shipping features.
   - Onform 1★, 2025-04-30: after an update everything lags, and the app closes when editing a video.
2. **The capture-to-playback pipeline fails (C_RECFAIL 39 + C_SLOW 48 + C_CLOUD 27 → 98 unique).**
   - SwingVision 1★, 2026-07-15: recording stopped after about 10 seconds of a one-hour session. The reviewer wants the original video kept in Photos regardless, so they can retry later.
   - SwingVision 1★, 2026-08-06: the watch showed recording, but only 1 of 3 sets was saved.
   - SwingVision 1★, 2025-10-31: a Max subscriber had every session stuck uploading for 4 days.
   - SevenSix 1★, 2025-10-12: more than half the serve videos stuck "being analyzed."
   - PlaySight 3★, 2026-03-17: recordings stuck at 0% uploading.
3. **AI accuracy (C_ACC_STATS 36, C_SCORE 19, C_SEGMENT 15, C_ACC_CALLS 12, C_DOUBLES 7 → 64 unique).**
   - SwingVision 5★ (!), 2024-06-29: AI scoring gets 1–2 games and 10+ points wrong per set across 20+ sets. Asks for post-match score correction, which would also produce training data.
   - SwingVision 3★, 2026-02-22: everything works about 80% of the time (recording, editing, scoring, processing), and line calls aren't good enough.
   - SwingVision 1★, 2025-05-05: every processed video drops 1–3 rallies, and editing 150 rallies by hand defeats the purpose.
   - SwingVision 3★, 2024-08-25: had to identify players 170+ times despite different shirt colors, and found no way to fix a false point caused by a ball fed between points.
4. **Price too high (C_PRICE 60).**
   - SwingVision 2★, 2026-03-11: $50/yr would be fine; $180 is not.
   - Onform 1★, 2026-09-26: $100/yr is too much, and old videos became inaccessible after the subscription lapsed.
5. **Paywall moves, billing and trial surprises, ads (C_PAYWALL 37 + C_BILLING 17 + C_ADS 4 → 55 unique).**
   - SwingVision 1★, 2023-03-16: sessions older than 30 days locked for non-Pro users without notice.
   - SwingVision 1★, 2026-04-16: a stick bundle's "free month" turned into a $179 annual charge.
   - Onform 1★/2★, 2021-09: Hudl Technique users moved to a 10-video free cap or $29.99/mo.
   - SwingVision 2★, 2026-02-08: many ads shown at the end of videos.
6. **Apple Watch and second-device dependency (C_WATCHSYNC 55).**
   - SwingVision 1★, 2025-10-04: more than half the time the watch start button does nothing, and the user learns this only after the set.
   - SwingVision 1★, 2026-04-17: without an Apple Watch, the second-device setup returned "Court Undetected" for four matches, leaving video with no analytics.
7. **UI confusion and no manual (C_UI 48).**
   - SwingVision 1★, 2023-08-19: after 3 warnings and 4 steps, couldn't find the recording; leaderboards got in the way.
   - Onform 2★, 2022-03-24: the frame flywheel disengages and drawing activates whenever the finger lifts. Onform 2★ (2023-09-12) reports the scrub bar colliding with the iOS app-switch gesture.
8. **Support unresponsive or bot-only (C_SUPPORT 37).**
   - SwingVision 1★, 2026-03-08: an AI bot gatekeeps human support and replies take weeks.
   - SwingVision 1★, 2026-10-01: a Pro account was blocked at about 4 hours of a claimed 30-hour quota and got five generic replies.
9. **Capture setup and device burden (C_SETUP 18 + C_DEVICE 10 + C_VIDEOQ 9 → 34 unique).**
   - SwingVision 1★, 2024-06-09: over an hour trying to align; the camera needs to be 10–12 ft up, which would take a ladder.
   - SwingVision 1★, 2024-07-18: voice-guided setup loops; the remote preview lags 3–4 s at low resolution and drops about 3 in 4 times.
   - SwingVision 1★, 2024-08-30: processed HD videos grew toward 100 GB of hidden storage on the phone.
   - SwingVision 2★, 2025-08-29: capped at HD even on 4K-capable phones.
10. **Platform gaps (C_PLATFORM 31).**
    - SwingVision 1★, 2025-01-05: uses an iPad only because there's no Android version, and the iPad zooms into the near baseline.
    - SwingVision 1★, 2025-05-05: no iPad support, so all editing happens on a small screen.
11. **Access to own data (C_OWNERSHIP 23).**
    - SwingVision 1★, 2023-03-28: advises exporting every session and expecting data to be locked eventually.
    - SwingVision 1★, 2025-04-28: raw video can't be viewed in-app, and lapsed subscribers lose videos unless they download hours of raw footage.
12. **Login and account (C_LOGIN 22).**
    - Onform 1★, 2022-02-10: forced Google or Microsoft sign-in, with price shown only after signup.
    - SwingVision 1★, 2026-08-12: locked out after a typo and unable to cancel a paid subscription.

---

## 7. App-specific notes

### 7.1 SevenSix (n=13; small sample, treat as anecdotal)

OBSERVED:

- 8 of 13 reviews describe broken or stuck analysis, or camera failures on retry. Examples: 2023-11 analysis freeze; 2024-06 uploads stuck for days at "analyzing"; 2024-10 the AI evaluator errors and deletes the video; 2024-12 zero analyses after 10 videos; 2025-04 the camera dies on the second attempt; 2025-10 more than half of videos still analyzing.
- 2023-09: the screen auto-locks during recording, and tripod users capture themselves walking back to the camera.
- 2026-08 (CA, 2★): the joint wireframe is liked but missing from exports; only the first shot of a series is analyzed.
- 2024-06: a 1★ reviewer says the app didn't recognize the swing but still gave a score of 81. INFERRED: a confident score with no evidence is worse than no score.
- Prior research noted v4.0.1 removed an AI assistant. v4.0.2 (2026-10-07) adds 7 languages and plain-language swing descriptions (OBSERVED, release notes).

### 7.2 Smashpoint (charting app → recorder)

OBSERVED:

- Praise: easy live charting on phone or watch, stats for junior-tennis parents and coaches, a responsive solo developer.
- Requests: log **how** an error happened (long, wide, net) and which shot caused a forced error (2020-06, 2020-10); a service-winner button (2019-11); simple two-button scoring and no-ad scoring on the watch (2019-02/03); doubles on the watch (2018-08); notes per point (2022-02).
- Failures: matches not saved at match point (2017-12, 2019-01); watch crashes on watchOS updates (2025-09); "no updates in years, will my data survive?" (2024-11).
- v3.4 (2026-09-30) adds Elite 4K/60 fps replays of "Critical Points" and a second fence iPhone. INFERRED: the charting apps are converging on video, the same convergence JOVRA plans.

### 7.3 PlaySight (n=45)

OBSERVED:

- Most low-star reviews concern paid livestreams of venue events (baseball, basketball, college tennis streams): stuttering video, wrong scoreboards, no support.
- Tennis-relevant points: in-app clip editing is tedious and there's no simple trim (2019-11, 2020-07, 2026-03); recordings stuck at 0% uploading (2026-03); the AI kept one 12-second rally from a 40-minute match the user paid $10 for (2026-08); login and password loops (2025-08, 2026-07); video flips upside down when the phone moves (2025-05).
- Early tennis users (2016–2018) liked SmartCourt highlights, voice-over and drawing.

### 7.4 Supplementary apps (cross-check)

OBSERVED (computed and read):

| App | n | Mean ★ | Notes |
|---|---|---|---|
| CoachNow | 175 | 4.09 | Coach value dominates (90 reviews). Complaints: uploads/playback, crashes after iOS updates, a 2025 watchOS 26 regression that removed watch camera control. Same pattern as Onform. |
| Scoreboard Pro | 131 | 3.28 | Ads that cover the scoring buttons (15) and crashes (15). Also a vertical-scoring request (2019) and losing the score when switching apps (2018). Lessons for JOVRA's live scoreboard: never interrupt scoring, support portrait one-hand scoring, persist state. |
| VisualEyes | 26 | 4.27 | Praised as a free Coach's Eye replacement. Asks: compare freezes (2026-04), sync playback for misaligned clips (2024-12), Apple Pencil palm rejection (2026-09), angle protractor and on-screen timers (2023). |
| MatchTrack | 39 | 3.87 | Data loss after an update (2024-03/07); service-winner button requested three times; edit score after the fact (2022-06); raw-data backup to iCloud or Dropbox (2022-03); per-player doubles stats (2019-04). |
| Tennis Plus | 43 | 2.33 | Watch-sensor swing apps broke with every iOS/watchOS release in 2017–2019 (sync failures, splash-screen crashes). Shot counts and speeds wildly off (15 serves logged in a 2-set match; speed "much slower after update"). Warns that sensor-only analysis is brittle. |

---

## 8. Feature requests worth considering

All OBSERVED in reviews. These are reviewer asks, not validated needs.

- **Post-match correction:**
  - Enter or edit the score point by point after the match, without needing a watch (SwingVision 2023-01, 2024-04, 2024-06 ×3, 2025-10).
  - Switch the point winner (2024-09).
  - Create your own rallies, delete rallies, jump to rally N (2025-05).
  - Uncheck all rallies before export (2025-07).
- **Raw access:**
  - Keep the original in Photos even if processing fails (2026-07).
  - A raw-video file system (2022-11).
  - Upload a trimmed video instead of the whole session (2025-08).
  - Export to SD card (2025-08).
- **Capture control:**
  - Pause during drills (2019-01, 2021-02, 2021-07).
  - Use the front camera for setup (2022-07, 2024-06).
  - Explicit "still recording" indicator after the screen dims (2021-10).
  - Error warning at the start of a match, not at the end (2024-02).
  - Rear camera as default (2025-07 regression).
  - Music playback while recording (2023-09).
  - Allow mic-off recording (2023-05).
- **Formats and quality:**
  - 4K or higher frame rates at lower tiers (2021-03, 2023-01, 2025-08).
  - A 30 fps mode outside line calling (2026-01).
- **Review UX:**
  - 10-second rewind (2025-01).
  - View rally highlights by speed (2020-11).
  - Show only my missed shots (2023-08).
  - Aggregate stats across matches over time (2024-12).
  - Points won on 1st and 2nd serve (2023-06).
  - Session comparison only within the same session type (2023-04).
  - Apple TV and desktop viewing (2021-12, 2023-03).
- **Coaching (Onform, VisualEyes):**
  - Loop between markers and more slow-mo speeds (2026-07).
  - Text captions on video (2024-09) and a blur tool (2024-06).
  - Metric units (2026-01).
  - Pencil-only drawing mode (VisualEyes 2026-09).
  - Synced compare that actually stays in sync (Onform 2025-07, VisualEyes 2024-12).
- **Tennis specifics:**
  - Left-handed support in filters and framing (2025-04).
  - Sideline camera angle (2024-11).
  - Two phones at opposite ends (2020-12).
  - Wall-practice mode (2022-06).
  - Service winner, error direction, no-ad scoring and 10-point tiebreaks (Smashpoint and MatchTrack).
- **Pricing:**
  - A lighter tier for occasional players, for example about $30/yr for about 6 hours/month (SwingVision 2023-04).
  - One-time purchase or lifetime options (Smashpoint 2017-08; SwingVision early-adopter lifetime $500, UNVERIFIED).

---

## 9. Ranked lists across apps

These lists drive JOVRA priorities. Counts are reviews across the 5 core apps (n=901), de-duplicated per row, with per-app splits. "Recent" = 2025–26. For pains, "≤2★ share" is the share of the 289 one- and two-star core reviews. Counts are OBSERVED (computed, lower bounds). The JOVRA implications are INFERRED.

### 9.1 Top 10 things players love

| # | Theme | Evidence (reviews) | Split | Recent | JOVRA implication (INFERRED) |
|---|---|---|---|---|---|
| 1 | **Rich stats from a single phone** (speed, placement, spin, heat maps, match stats; accurate when it works) | **158** | SV 127 · Smashpoint 16 · Onform 11 · PlaySight 3 · SevenSix 1 | 35 | Keep deep stats, but compute them from events the user can see and correct. Label estimates (as the screens.json "Estimated" tags already do). |
| 2 | **Coach–player loop and organization** (share with coach or parents, per-athlete folders, messaging, notes) | **146** | Onform 97 · SV 37 · Smashpoint 8 · PlaySight 3 · SevenSix 1 | 40 | Share a point or clip with a coach via link; coach notes; optional coach seat. Onform's success is the template. |
| 3 | **Easy to use / quick to start** | **144** | Onform 64 · SV 62 · Smashpoint 12 · PlaySight 5 · SevenSix 1 | 35 | One-tap start; setup in seconds; no forced login before the first recording. |
| 4 | **It made me better; seeing myself on video** | **91** | SV 71 · Onform 17 · SevenSix 2 · PlaySight 1 | 33 | Make "watch yourself" the hero loop: point → slow-mo → drill. Rising in 2025–26. |
| 5 | **Responsive team and visible improvement** | **75** | SV 34 · Onform 34 · Smashpoint 6 · SevenSix 1 | 21 | Fast human support, a public changelog, close the loop on feedback. Cheap differentiation now that SwingVision support praise is falling. |
| 6 | **Analysis tools**: slow-mo/frame step, drawing/angles/voice-over, side-by-side compare | **63** | Onform 36 · SV 24 · SevenSix 2 · PlaySight 1 | 19 | Stable frame-step controls separate from drawing mode; synced compare that holds sync (Onform and VisualEyes complaints). |
| 7 | **Highlights, favorites, social sharing** | **61** | SV 38 · Onform 17 · PlaySight 5 · Smashpoint 1 | 13 | Favorites while playing; best and longest rallies; vertical social export with the score burned in. |
| 8 | **Worth the money** | **57** | SV 36 · Onform 20 · PlaySight 1 | 17 | Value is judged against lessons and radar guns. Price an occasional-player tier accordingly. |
| 9 | **Wrist and live scoring** (Apple Watch, auto-score) | **52** | SV 43 · Smashpoint 8 · Onform 1 | 7 | Watch scoring is loved. Keep it optional and verifiable (see pain #6). |
| 10 | **Dead time removed / auto-segmented points** | **32** | SV 31 · Onform 1 | 6 | Ship auto-cut, but with an always-available raw timeline and manual rally edits (see pain #3). |

Just outside the top 10: video quality (15) and line-call challenges (9, SwingVision only). INFERRED: line calling gets few reviews relative to its marketing weight, and accuracy complaints about it (12) outnumber praise (9). Treat it as a later, feasibility-gated feature, as the existing brief already does.

### 9.2 Top 10 pain points

| # | Pain | Evidence (reviews) | Split | Recent | ≤2★ share | JOVRA implication (INFERRED) |
|---|---|---|---|---|---|---|
| 1 | **Crashes, freezes, bugs, broken updates** | **151** | SV 99 · Onform 26 · PlaySight 10 · SevenSix 8 · Smashpoint 8 | 40 | **33%** | Reliability is the product. Crash-free capture as a release gate, staged rollouts, no feature work while P0 capture bugs are open. |
| 2 | **Capture-to-playback pipeline fails**: recording stops, footage lost, uploads/processing/exports stuck, cloud playback errors | **98** | SV 67 · Onform 17 · PlaySight 7 · SevenSix 4 · Smashpoint 3 | 37 | **22%** | Local-first, crash-safe segmented recording. Original kept in the user's library. Playback never depends on analysis or upload. Visible per-session state (recorded/saved/analyzing/backed up) with resume and retry. Matches the brief's separate-states rule. |
| 3 | **AI accuracy and the cost of correcting it** (tracking/speed/spin, line calls, auto-score, cut points, player ID) | **64** | SV 60 · Smashpoint 2 · SevenSix 1 · PlaySight 1 | 24 | 11% (mostly 3★ churn risk) | Manual-first scoring with frictionless post-match edits. AI as suggestions with confidence. One-tap "this point is wrong". Never hide the raw time between points. Make player ID sticky (tag once per match, not per shot). |
| 4 | **Price too high** | **60** | Onform 31 · SV 29 | 18 | **15%** | A cheap or free core (on-device capture, replay, manual scoring cost almost nothing to serve). Charge for compute-heavy extras. An occasional-player tier. |
| 5 | **Paywall moves, trial/billing surprises, ads** | **55** | SV 27 · Onform 24 · PlaySight 3 · Smashpoint 1 | 19 | **16%** | Never lock a user's own history. Grandfather features. Plain trial terms with monthly as default. No ads on personal content. |
| 6 | **Apple Watch / second-device dependency and sync** | **55** | SV 49 · Onform 3 · Smashpoint 3 | 16 | **10%** | Phone-only must be a first-class path. Watch is optional, with a confirmed "phone is recording" heartbeat on the wrist. |
| 7 | **UI confusion / no manual** | **48** | SV 21 · Onform 20 · PlaySight 6 · Smashpoint 1 | 16 | **12%** | Record reachable from everywhere. Recordings easy to find. Edit controls discoverable. In-app help. |
| 8 | **Support unresponsive / bot-only** | **37** | SV 28 · PlaySight 3 · Onform 3 · Smashpoint 2 · SevenSix 1 | 17 | **10%** | Human reply SLA. In-app diagnostics bundle so support can act without back-and-forth. |
| 9 | **Capture setup and device burden** (mount and framing, court detection, storage bloat, heat, resolution caps) | **34** | SV 25 · Onform 7 · PlaySight 2 | 12 | 8% | Framing that tolerates typical fence heights. Allow calibration on the recorded footage afterward. Storage dashboard with cleanup. Thermal-aware capture. Don't cap resolution artificially. |
| 10 | **Platform gaps** (no Android, no iPad editing, old devices dropped, desktop/web playback) | **31** | SV 25 · Onform 5 · PlaySight 1 | 8 | 6% | iPad review layout early. Android after iOS capture is proven (already planned). Standard exports so any device can play them. |

Also ranked, just outside the top 10:

- **Own-data access** (raw video, camera-roll copy, export, lock-in): 23 reviews (SV 17 · Onform 6), 4% of ≤2★. INFERRED: few reviews, but they map directly to Jon's Google Drive ownership requirement and reinforce pains #2 and #5. Treat it as a design principle rather than a feature.
- **Login and account friction:** 22 reviews. Allow first recording without an account; offer Sign in with Apple; never strand a user who wants to cancel.

---

## 10. Checks against the prior brief (`design-reference/brief/research.md`)

| Prior claim | Check | Result |
|---|---|---|
| SwingVision 4.7/5, about 4.9K ratings | iTunes lookup: 4.706 / 4,928 | **Confirmed** (OBSERVED) |
| SevenSix 4.2/5, 68 ratings; version 4.0.2 live | lookup: 4.191 / 68; v4.0.2 dated 2026-10-07 | **Confirmed** (OBSERVED) |
| Onform 4.8/5, about 8.7K ratings | lookup: 4.786 / 8,666 | **Confirmed** (OBSERVED) |
| Selected 2024 SwingVision reviews describe scoring-correction difficulty | C_SCORE appears 11 times in 2023–24 vs 1 in Nov 2019–22 and 6 in 2025–26 | **Confirmed, and quantified**: it peaked in 2023–24 and still appears (OBSERVED) |
| Recent SwingVision release notes describe recording, heat and sync fixes | 11.9.67 (2026-09-27) notes: high-temperature recording stability, low-storage warning, iPhone–Watch connection reliability, recordings ending early, crash on camera interruption, stats sync stuck | **Confirmed** (OBSERVED) |
| SevenSix: a 2025 review on camera retry; older reviews on stalled analysis or lost capture | 2025-04-20 camera retry; stalled analysis also on **2025-10-12** (recent, not only old) | **Confirmed, with a correction**: stalled analysis is recent too |
| Onform: a 2022 review on confusing capture navigation and scrubber/drawing conflict | 2022-03-24 (flywheel and drawing), 2022-03-22 (scroll bar vs flywheel), 2022-11-08 (new scrubber), 2023-09-12 (scrub bar vs iOS gesture) | **Confirmed and broadened**: four separate reviews (OBSERVED) |
| "Use complaints to motivate resilience tests, not to claim competitors are broken" | 2026 SwingVision written reviews average 2.98★; reliability umbrella in 23%, 33% and 24% of SwingVision reviews in the three periods | **Nuance**: complaints are current, not just historical. The headline rating still says 4.7. Both framings hold. |

---

## 11. Limitations and open questions

- **Feed coverage.** The public feed returns at most about 500 written reviews per storefront and none of the star-only ratings. Developer replies are not included, so some complaints may have been answered or fixed. OBSERVED.
- **US-centric.** SevenSix's US sample (11) is too small to generalize. A multi-storefront pull (gb, au, ca, de, es, fr, no; translation needed) would add volume. UNVERIFIED how much.
- **Coder limits.** Precision ≈ 90%, recall ≈ 80% on two manual validation rounds (88 reviews). Treat counts as lower bounds and rank order as the robust signal. INFERRED.
- **Onform relevance.** Onform reviews are mostly golf and other sports. Its counts measure workflow sentiment, not tennis needs.
- **Review bursts.** 5★ bursts in July/Oct 2022 and Nov 2025 for SwingVision suggest solicited reviews. Year averages are sensitive to them.
- **Open questions:**
  - SwingVision's current free-tier limits and history lock: reviewers cite a 2 h/month free tier and a 7-day lock in 2026; the listing does not state them. UNVERIFIED.
  - The actual Pro recording-hour cap. UNVERIFIED.
  - Whether a Google Play pull for SwingVision exists to compare. Reviewers say it is iOS-only; one 2024 review chose an iPad because there was no Android app. UNVERIFIED.
  - How often heat ends recordings in practice. Reviews rarely name it, but release notes do. Needs on-court testing.
  - Whether player-ID burden is mainly a doubles or pickleball problem or also singles. Reviews show both. Needs a larger sample or the Reddit/forums lane.

---

## Sources

All accessed 2026-10-07.

- https://itunes.apple.com/lookup?id=989461317&country=us: SwingVision rating 4.706 / 4,928, version 11.9.67, release date and release notes (heat, storage, watch fixes).
- https://itunes.apple.com/lookup?id=1490334045&country=us: Onform rating 4.786 / 8,666, version 4.7.3.
- https://itunes.apple.com/lookup?id=1505604446&country=us: SevenSix rating 4.191 / 68, version 4.0.2 and its release notes (7 languages).
- https://itunes.apple.com/lookup?id=1098174650&country=us: Smashpoint 4.509 / 462, v3.4 notes (Elite 4K/60 replays, second camera).
- https://itunes.apple.com/lookup?id=976177330&country=us: PlaySight 2.873 / 134, description (SmartCourt, livestreams).
- https://itunes.apple.com/lookup?id=596598472&country=us, …id=496758984, …id=1643006248, …id=977481057, …id=1158767577: supplementary app ratings and versions.
- https://itunes.apple.com/search?term=<term>&entity=software&country=us&limit=50: candidate discovery and rating counts. Terms used: tennis video analysis, tennis recording, tennis line calling, tennis swing analysis, tennis stats tracker, tennis AI coach, tennis match video, tennis score keeper video, slow motion video analysis sports, line calling, tennis shot tracker, tennis ball speed, serve speed radar, tennis highlights, tennis coach video, tennis in out, wingfield tennis, baseline vision tennis, tenniix, hudl technique, dartfish. Some further queries (playsight, zepp tennis, pickleball video analysis, mustard tennis) were rate-limited and returned no data.
- https://itunes.apple.com/us/rss/customerreviews/page=1..10/id=989461317/sortby=mostrecent/json (also sortby=mosthelpful): 490 SwingVision reviews.
- https://itunes.apple.com/us/rss/customerreviews/page=1..7/id=1490334045/sortby=mostrecent/json (also mosthelpful): 297 Onform reviews.
- https://itunes.apple.com/us/rss/customerreviews/page=1/id=1505604446/sortby=mostrecent/json, plus the /gb/, /ca/, /au/, /nz/, /ie/ variants: 13 SevenSix reviews.
- https://itunes.apple.com/us/rss/customerreviews/page=1..3/id=1098174650/sortby=mostrecent/json: 56 Smashpoint reviews.
- https://itunes.apple.com/us/rss/customerreviews/page=1..2/id=976177330/sortby=mostrecent/json: 45 PlaySight reviews.
- https://itunes.apple.com/us/rss/customerreviews/page=1..5/id=596598472/sortby=mostrecent/json (CoachNow, 175), id=496758984 (Scoreboard Pro, 131), id=1643006248 (VisualEyes, 26), id=977481057 (MatchTrack, 39), id=1158767577 (Tennis Plus, 43): supplementary reviews.
- https://apps.apple.com/us/app/swingvision-tennis-pickleball/id989461317: in-app purchase list (Plus/Pro/Max prices), 4.7★ and 4.9K ratings, Editors' Choice.
- https://apps.apple.com/us/app/onform-video-analysis-app/id1490334045: in-app purchase list (Personal, Coach, Team prices).
- https://apps.apple.com/us/app/sevensix-tennis-ai-coach/id1505604446: in-app purchase list ($14.99/mo, $149.99/yr, per-analysis packs).
- https://apps.apple.com/us/app/smashpoint-tennis-tracker/id1098174650: in-app purchase list (Pro, Elite) and v3.4 notes.
- Local: /Users/IDC2.5/jv/design-reference/brief/research.md (prior claims checked in section 10); /Users/IDC2.5/jv/docs/handoff/JON-ORIGINAL-PROMPT.md (founder intent: pros and cons, Google Drive ownership, iOS then Android); /Users/IDC2.5/jv/design-reference/brief/product-brief.md and screens.json (the 20 planned screens, used to frame implications).
