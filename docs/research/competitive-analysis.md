# Competitive analysis: SwingVision, Onform, SevenSix and the five that matter next

Status: synthesized analysis, 2026-10-07. This is the comparison Jon asked for: take the best of the top apps, list
their pros and cons from real ratings and reviews, and build the app that keeps what players praise and fixes what
they complain about (`docs/handoff/JON-ORIGINAL-PROMPT.md`).

**Evidence base.** 901 coded App Store reviews across five core apps plus 414 cross-check reviews
(`raw/review-mining.md`); 490 hand-read SwingVision reviews, 52 recovered release notes and the ITF approval report
(`raw/swingvision.md`); 1,827 Talk Tennis posts, 1,148 r/10s comments and 215 YouTube comments (`raw/community.md`);
a 347-app App Store sweep plus Google Play checks (`raw/landscape.md`); 25+ video-analysis apps
(`raw/video-analysis-apps.md`); stringing apps (`raw/equipment-stringing.md`); and platform/strategy notes
(`raw/gap-finder.md`, `raw/ios-tech.md`, `raw/drive-android-tech.md`). Listing facts and SwingVision's IAP prices were
re-checked live on 2026-10-07.

**Labels.** **OBSERVED** = seen in a cited source or computed from it. **INFERRED** = reasoning. **UNVERIFIED** = not
confirmed. Review counts are **lower bounds** from a rule-based coder with ≈90% precision and ≈80% recall on two hand
validation rounds (88 reviews); **rank order is the reliable signal**. Written reviews skew negative (every app's
written mean is 0.6–1.9★ below its listing rating), so they show *what* people complain about, not *how many* users are
unhappy. Reviews are paraphrased, never reproduced.

---

## 0. Bottom line

1. **SwingVision is the only phone-only full-match tracker with traction** (4.71★ / 4,928 ratings; every other
   phone-camera AI tennis app found has < 70 ratings). OBSERVED. It is the benchmark JOVRA must beat.
2. **Its headline rating hides current unhappiness.** Written reviews average 3.58★ overall, **2.98★ in 2026 (n=50)**,
   the lowest year since 2019; 38% of 2026 written reviews are 1★. OBSERVED (re-fetched 2026-10-07; the RSS feed is a
   capped pool of the ~500 most recent written reviews, back to 2016, not every review). The 4.7 comes mostly from
   star-only ratings (INFERRED).
3. **What players actually love is time and video, not AI verdicts.** The most-upvoted community statement is that
   SwingVision's value is removing dead time so a 1.5–2 h match plays in 15–30 min (rank-1 wish: 79 authors, 413
   Reddit upvotes). In 2025–26, praise shifted toward seeing yourself on video and slow-motion replay while praise for
   auto-scoring and stats fell. OBSERVED.
4. **The biggest pains are reliability and money, not missing features.** Of 289 one- and two-star reviews across
   five researcher-selected apps (SwingVision supplies 145 of them), a rule-based multi-label classifier flags **44% as
   mentioning at least one reliability problem** (crashes, lost recordings, stuck uploads/processing, cloud playback)
   and **27% as mentioning money** (price, paywall moves, billing surprises, ads). OBSERVED (reproduced 2026-10-07).
   The groups overlap (20 reviews in both, 36 uncoded) and the split depends on the coder: a simpler keyword pass gives
   ≈37% reliability and up to ≈38% money. So reliability and money are the two biggest complaint groups, but the
   evidence does **not** show reliability clearly ahead of money (see Verification log).
5. **Users want the numbers but don't trust them.** Stats are the most-praised theme (158 reviews), yet SwingVision AI-
   accuracy complaints rose from ≈4% of reviews (2019–22) to ≈18% (2023–26). OBSERVED. The fix is evidence and
   correction, not more confident numbers.
6. **Onform wins on coaching workflow** (compare, voice-over, per-student folders), **but mostly for golf** (51 golf
   mentions vs 6 tennis) and it is paywall-heavy, with lapsed users locked out of their own videos (2026-09). OBSERVED.
7. **SevenSix is a cautionary tale**: 8 of its 13 written reviews describe stuck or broken analysis, and it added then
   removed an AI Coach within two months of 2026. OBSERVED.
8. **Android is the clearest structural gap**: no SwingVision, SevenSix or Toach listing found on Google Play; Onform
   is 2.97★ on Android vs 4.79★ on iOS; among the Android tennis apps checked, the best-rated is a manual scorekeeping
   and stats app with no video (Tennis Math 4.61★ / 3,345), so it is not a like-for-like SwingVision equivalent.
   OBSERVED (Play search fetched without JavaScript plus guessed package names: strong evidence of absence, not
   exhaustive proof). Re-check before marketing against it.
9. **White space JOVRA can own** (from 347 listings): zero mention Google Drive, only one has a string tracker, five
   mention VoiceOver/accessibility, none markets score correction, and only one states honestly what its camera cannot
   measure. OBSERVED (keyword classifier over listing text; directional).
10. **JOVRA's winning contract (INFERRED):** record reliably, trim reliably without hiding anything, fix any point in
    seconds, label every number honestly, keep the user's files theirs (local + their Google Drive), never lock or ad-
    wrap their own video, and ship Android.

---

## 1. Who we compared and why

| Tier | App | Why it is here |
|---|---|---|
| Big three (founder's ask) | **SwingVision** | The product Jon named; full-match tracking, trimming, stats, line calls |
| | **Onform** | Best-in-class comparison, frame tools, voice-over, coach workflow |
| | **SevenSix** | The incumbent tennis-specific AI stroke coach |
| Next five (chosen in `raw/landscape.md` §4 for fit with JOVRA's record → find point → evidence → practice → own-video chain) | **Smashpoint** | Best scoring/charting spine; added 4K60 point replays and a second fence camera in Sep 2026 |
| | **TennisCut** | On-device rally trimming, two-phone remote with camera telemetry, on iOS **and** Android |
| | **AI Tennis Swing Coach** | Privacy-first, no-account technique loop with honest disclaimers |
| | **INTER TENNIS** | Highest technique ceiling claimed from one phone; "Diagnose and Fix" fault grouping |
| | **Tennis Math** | The Android charting benchmark (fix-score-while-tracking, undo/redo, Wear OS) |
| Context only | PlaySight, Wingfield, PlayReplay, Baseline Vision; CoachNow, VisualEyes, Kinovea, Dartfish; RacquetTune | Hardware line-calling bar, coaching-tool patterns, string-tension benchmark |

---

## 2. Fact sheet (US storefront, 2026-10-07)

| App | iOS rating / count | Written-review mean (n) | Version · date | Min iOS | Price (IAP) | Platforms | Android |
|---|---|---|---|---|---|---|---|
| SwingVision | **4.706 / 4,928** (86.7% 5★) | **3.58 (490)**; 2026: **2.98 (50)** | 11.9.67 · 2026-09-27 | 18.0 (A12+; real-time needs A13+) | Free (8 h/mo HD, last-7-days access, 5-min exports, ads; announced 2026-01-15, shipped in 11.9.49 on 2026-02-04); Plus $14.99/mo · $95.99/yr; Pro $24.99/mo · $179.99/yr; Max $39.99/mo · $299.99/yr (family of 5). The listing description's "Pro … $14.99/mo" is stale copy; the web compare page also showed a first-year Pro Yearly offer of $143.99 and Max at $22.99/mo | iPhone, iPad, Mac, Watch | **None** (an Android phone can act as a remote) |
| Onform | **4.786 / 8,666** | 3.72 (297) | 4.7.3 · 2026-10-06 | 18.6 | Ten IAP tiers from Personal $4.99/mo ($49.99/yr) to Team/Academy $79/mo; individual Standard $9.99 / Premium $14.99 per month; Coach $19.99–$59.99/mo; 14-day trial | iPhone, iPad, Watch | Yes, **2.97 / 309** |
| SevenSix | **4.191 / 68** | 2.31 (13, US+GB+CA) | 4.0.2 · 2026-10-07 | 15.6 | $14.99/mo, $149.99/yr; per analysis $1.99 (1), $3.99 (3), $4.99 (5) | iPhone | Not found |
| Smashpoint | 4.509 / 462 | 3.88 (56) | 3.4 · 2026-09-30 | 16.2 | Pro $5.99/mo, $14.99/3 mo, $39.99/yr; Elite $149/yr | iPhone, iPad, Mac, Watch, tvOS, visionOS | Yes (100+ installs) |
| TennisCut | 4.083 / 12 | n/a (small) | 2.0.0 · 2026-09-19 | 17.0 | Free core; Pro $4.99/wk, $8.99/mo, $44.99/yr | iPhone | Yes, 4.09 / 52 (10K+) |
| AI Tennis Swing Coach | 4.88 / 8 | n/a | 2.5.2 · 2026-09-25 | — | Free core (no account, no limits); Pro $9.99/mo or $79.99/yr; 25 credits $4.99 | iPhone | Not found |
| INTER TENNIS | no ratings | n/a | 5.0.0 · 2026-10-06 | — | No IAP shown (pricing UNVERIFIED) | iPhone | Yes (1K+, unrated) |
| Tennis Math | — (no iOS app) | — | updated 2026-08-16 | — | IAP $4.99–$49.99 | Android, Wear OS | **4.61 / 3,345** (100K+) |

Sources: iTunes lookup (re-checked 2026-10-07: SwingVision 4.706/4,928; Onform 4.786/8,666; SevenSix 4.191/68;
Smashpoint 4.509/462; TennisCut 4.083/12), SwingVision App Store IAP list (re-checked: Plus $14.99/$95.99, Pro
$24.99/$179.99, Max $39.99/$299.99), Google Play detail pages (raw/landscape.md S10), review means from
raw/review-mining.md §2.1.

**SwingVision extras worth knowing (OBSERVED, raw/swingvision.md):** 752 MB; first release 2016-10-18; ~one release
every 10–14 days; ITF PAT approval **PAT-25-037** (2025-10-31, v11.9.6 tested Feb 2025; a Rule 31 Player Analysis
Technology approval, not an ITF electronic line-calling certification) which explicitly does **not** establish the accuracy
of its data or in/out calls and does not permit the Apple Watch in competition; the approved system does include line
calls on an optional on-court tablet with challenges on the last four shots (three incorrect challenges per set by
default); capture at 60 fps from the rear camera of one or two iPhones, with data sent to a backend server over Wi-Fi
(cellular fallback); three
equipment tiers (Ground = trimming only; Fence Mount = stats and half-court line calls; Swing Stick = full-court line
calls); recording-hour caps Free 8 / Plus 16 / Pro 30 / Max 60 h per month; privacy label lists Usage Data "used to
track you"; accessibility label declares 4 features and **not** VoiceOver, Voice Control, Larger Text or Captions;
vendor accuracy claims 97% for calls within 10 cm and speeds within 10% (method unpublished); one peer-reviewed study
(n = 5 elite juniors, 2023) found good-to-very-good validity.

### 2.1 What the App Store screenshots show (founder asked for this explicitly)

Jon asked us to "look at the App Store screen shots". Each core listing's US iPhone screenshot set was pulled from the
iTunes lookup `screenshotUrls` field and viewed as images on 2026-10-07 (SwingVision 10 iPhone + 10 iPad + Mac/Watch/
iMessage in raw/swingvision.md §6; Onform 10, SevenSix 10, Smashpoint 10, TennisCut 7 re-viewed for this section).
Captions are paraphrased. OBSERVED unless marked.

| App | What the screenshots sell (in order) | What they never show | Lesson for JOVRA (INFERRED) |
|---|---|---|---|
| SwingVision | Awards and investors; AI line-call dispute screen with "Out!" badge; broadcast-style highlights with a mini-court inset and speed tag (pickleball footage); dense placement heat map with depth %; doubles butterfly-bar match stats; strengths/weaknesses by side; a sentence-style point filter builder; Goal Mode targets; Point History list; 1-year trends with sparklines | Correction, storage, reliability, data ownership, what the camera cannot measure | Copy the Point History list and sentence filter; differentiate by showing provenance ("Manual / Estimated / Needs review") and a source clip one tap from every number |
| Onform | Multi-sport coaching platform (golf first); 3-step record → annotate/voice-over → share; live skeleton and line drawings (the only tennis frame); golf-only 3D slide/sway/rotation; hands-free AI auto-detect recording; launch-monitor and pressure-plate integrations; private and group messaging; library folders and tags; wireless multi-cam; per-student roster | Pricing, tennis match play, anything about lapsed access | The player chrome (three-decimal time readout, 1× speed chip, frame-step transport with the scrubber above it, right-edge tool rail) is the model for screens 10, 13, 14 |
| SevenSix | "World's first AI coach for tennis"; 2020 awards and App of the Day; landscape record frame; a 0–100 overall score plus swing-curve, timing and impact-point scores with upbeat text; "pro curve vs your curve"; a testimonial | Any limitation or confidence; screens look dated (iPhone X-era frames) | Single opaque 0–100 scores are the pattern JOVRA's honesty labels replace |
| Smashpoint | Track + broadcast live, critical-point video replays, ELO rankings, published results, and "Connect AI agents (MCP)"; live point-by-point page; head-to-head by surface; one-tap point entry (Ace / Return winner / Ball in / Serve fault / Undo); momentum and pressure charts; winner map and an **error map with long / wide / net counts**; serve/return tables with fractions ("21/28 (75%)") | Full-video scrubbing (video is critical points only) | Best manual-charting UI in the set: copy fraction-plus-percent tables and the large tap targets; error direction is now shipped there, so JOVRA's charting should match it |
| TennisCut | Tripod capture; Watch score plus workout metrics; AI rally trimming; tennis video library filtered by Matches / Serve practice / Rally; trim with start/end; a result card "46:59 → 27:09, ~2.88 GB → 1.66 GB, 164 rallies found"; record or import with an AI Trimming toggle and a Do Not Disturb tip | Accuracy of the trim (reviews say clips start early and end short) | Show the storage saved by rally-only copies the way TennisCut does (feeds Space Saver, P0-17); state trim accuracy honestly |

**Correction from this pass (OBSERVED):** Smashpoint's screenshots show an Error Map with long / wide / into-the-net
counts, so "error direction" is no longer a missing Smashpoint feature (its review complaints predate this). §3.4
is updated.

---

## 3. Competitor profiles: pros and cons

Counts are reviews carrying a theme in the coded sets (raw/review-mining.md §4) unless another source is named.
"Recent" = 2025-01-01 to 2026-10-07.

### 3.1 SwingVision

**PROS (what users praise)**

| Pro | Evidence |
|---|---|
| Dead-time removal: a 1.5–2 h match watched in 15–30 min | 31 praise reviews (most distinctive feature; almost no other app has it); community rank-1 wish (79 authors, 413 upvotes; top r/10s comment 85 upvotes); several users keep paying only for this |
| Rich stats from one phone (placement, speed, heat maps, match stats) | 120 reviews (24% of SwingVision reviews); 127 incl. accuracy praise |
| It made me better / seeing myself on video | 60 "improve" + 16 self-review; self-review rose 2% → 7% and replay controls 1% → 6% of reviews from 2019–22 to 2025–26 |
| Easy to start ("press record") | 62 reviews |
| Highlights, favorites, social sharing | 38 reviews; the company told Tennis.com shared compilations drive about half of new customers (2022) |
| Coach, junior and parent use | 35 reviews; 2024–26 junior-parent mentions all positive (5/5) |
| Worth the money (vs radar guns, lessons) | 36 reviews |
| Apple Watch wrist scoring and favorites | 29 reviews (wrist scoring as a between-point reset) |
| Point filters (e.g. all second-serve returns, ≤5-shot points) and a sentence-style filter builder | Community L2; screenshot 7 |
| Live audio line calls and Watch challenge replay | 9 praise reviews (vs 12 accuracy complaints) |
| Fast-moving product, broad platform reach, ITF approval | 52 releases in two years; iPhone/iPad/Mac/Watch; PAT-25-037 |

**CONS (what users complain about)**

| Con | Evidence | Still current? |
|---|---|---|
| Crashes, bugs, broken updates | 99 reviews (20%) | Yes: a 2026-10-04 3★ review lists failed exports, ~10 points detected in hour-long matches, reprocessing out of memory |
| Capture → playback pipeline fails (recording stopped/lost, uploads/processing stuck, cloud playback) | 67 unique (rec-fail 29, slow 32, cloud 19); ≈35 of 165 hand-coded 2024–26 reviews | Yes; release notes 11.9.47–11.9.67 keep patching it |
| Apple Watch / second-device dependency and desync ("watch said recording, phone saved nothing") | 49 reviews (10%); community setup thread 31 posts | Yes (2026-08: only 1 of 3 sets saved) |
| Price too high, paywall moves, trial/billing surprises, ads | 51 reviews (price 29, paywall 15, billing 12, ads 2); price #1 theme in 2024–26 keyword pass (59); community pricing wish 161 authors | Yes: Free tier 7-day lock and ads (announced 2026-01-15, shipped 11.9.49 on 2026-02-04), Pro blocked at ~4 of 30 h (2026-10), stick bundle → $179 charge (2026-04) |
| AI accuracy and the cost of correcting it (stats/speed, scoring, cut-off points, line calls, player ID) | 60 reviews (stats 33, score 18, segmentation 15, calls 12, doubles 6); users estimate scoring ≈80–90% right; manual player ID "works about 20%" and takes 5–10 min; speed outliers 120–140 mph a running joke | Yes; segmentation complaints still rising (1% → 6%) |
| Correction tools slow and limited (no add/split/merge point, ~20 s edit window, edits not persisting, iPhone-only editing) | ≈10 hand-coded 2024–26; community 27 authors (+79 wanting big-screen editing) | Partly: Edit Point → Point Details flip-winner path exists since 2024 |
| Support slow or bot-gated | 28 reviews; support praise fell 7% → 3% while complaints rose 0% → 10% | Yes |
| No Android / weak iPad editing / old devices dropped | 25 reviews; community 147 authors; CEO says Android can't sustain the 60 fps real-time model | Yes |
| UI confusion, hard-to-find recordings | 21 reviews (rising) | Yes |
| Own-data access: history locks, raw video, phantom storage | 17 reviews; community storage thread **135 points** (80 GB undeletable), other reports 26 GB and 272 GB | Partly (low-storage warning added Sep 2026) |
| Setup friction (alignment never turns green, needs a second online device, audio setup removed) | 16 reviews; community 41 authors | Yes (May 2026 reports) |
| Heat | 0 written reviews in two years, but in release notes (11.9.47, .65, .67), the FAQ ("System Pressure", umbrella) and forums (>85°F, ice packs) | Yes (vendor-acknowledged) |
| Feature removals mid-subscription | ≈8 (watch-only analysis, audio setup, trimmed upload, Semi-Pro filters) | n/a |
| Privacy/accessibility posture | Usage Data used for tracking; VoiceOver not declared | Yes |

### 3.2 Onform

**PROS**

| Pro | Evidence |
|---|---|
| Coach–athlete workflow (per-student folders, messaging, notes, add parents/coaches) | 94 reviews (32%); rising 24% → 38% of reviews 2020–21 → 2024–26 |
| Easy to use | 64 reviews (22%) |
| Side-by-side and overlay compare against your past self or a model | 20 reviews; most frequent positive keyword theme (19 hits) |
| Drawing, degree angles, voice-over, Coach Cam | 18 annotate reviews; 10 drawing tools; voice-over writes a new file and keeps the original; transcription since 4.7.0 (2026-09-26) |
| Responsive support, steady improvement | 29 support reviews |
| Frame-precise player (Macro + Frame Scrubber, 2× to 1/8×, three-decimal time) | Onform KB |
| Capture up to 240 fps, multicam, Watch app | Listing |

**CONS**

| Con | Evidence | Still current? |
|---|---|---|
| Price and paywall | 31 price + 21 paywall; 28 of 43 one/two-star reviews in 2021 (Hudl migration) and 11 of 26 in 2024–26 | Yes: free version removed (2025), "every feature paywalled" (2025-10, 2026-07) |
| Lapsed subscribers can't open their own videos | 2026-09 review | Yes |
| Crashes, lag after updates, videos not saving | 26 reviews; 2026-09 "half the time" not saving | Yes |
| Compare sync "hit or miss", sync adjustment broken, drawings not saved | 2025-05, 2025-07 | Yes |
| Scrub/draw conflict (flywheel disengages, drawing engages), scrub bar hits the iOS app switcher | 4 reviews 2022–2023 | Probably fixed (current screenshots show the scrubber above the transport) |
| Forced Google/Microsoft/Apple login | 2022, 2024, 2026 | Yes |
| Android quality | 2.97★ / 309 on Play | Yes |
| Mostly not tennis | 89 non-tennis reviews (30%); 51 golf vs 6 tennis; 3D is golf-only | Structural |
| Voice-over quotas for athletes (5/mo Standard) | KB; 2023 complaint | Yes |

### 3.3 SevenSix

**PROS**: focused stroke-feedback workflow; pay-per-analysis entry ($1.99) (OBSERVED); 4.0.2 (2026-10-07) added 7
languages and a plain-language score screen; praise is for the concept only (3 positive reviews of 13).

**CONS**: 8 of 13 reviews describe stuck or broken analysis or camera failure on retry (reliability umbrella 69%);
analysis stuck "analyzing" from 2023-11 through **2025-10**; a swing it did not recognise was scored 81 (2024); screen
auto-locked during recording (2023-09); joint wireframe missing from exports and only the first shot of a series
analysed (2026-08, CA); AI Coach added in 4.0.0 (2026-06-02) and **removed in 4.0.1 (2026-08-06)**; dated screenshots;
not on Android; written mean 2.31★. OBSERVED.

### 3.4 Smashpoint

**PROS**: stats from charting (16 reviews, 29%), easy live charting on phone or Watch (12), five selectable tracking
depths, private by default, ELO/head-to-head/momentum/pressure analysis, Sep 2026 "Critical Point" 4K60 replays at
½× and ¼×, second iPhone at the fence, replays padded 2 s past point end, "No winner" save for stopped matches, cheap
($39.99/yr Pro). OBSERVED.

**CONS**: crashes (8) and Watch crashes on watchOS updates (2025-09); matches not saved at match point (2017, 2019); a
long no-update period (2024 review worried about data survival); requested in older reviews: service-winner button, error
direction (long/wide/net; **now shown as an Error Map in the 2026 screenshots**, §2.1), per-point notes, no-ad on the
Watch. Video covers critical points only, not full-video
scrubbing. OBSERVED.

### 3.5 TennisCut

**PROS**: rally detection and trimming **entirely on device**; a second phone as remote with live preview and the
camera phone's battery and free space; 1080p/4K at 30/60 fps with HDR kept; free frame-step "Coach Eye"; 16:9 or 9:16
export; on iOS and Android; $44.99/yr. OBSERVED.

**CONS**: 2026 reviews say clips start too early (pre-serve bounce) and end 1–2 s short, and detection is unreliable on
some footage; a reviewer wanted one free import to test before paying; tiny rating base (12 iOS). OBSERVED.

### 3.6 AI Tennis Swing Coach

**PROS**: free core with **no account and no limits**; on-device Core ML racket/ball detection with live skeleton,
joint angles and spoken cues; one named fault + one fix + one drill per swing; PDF practice report; multi-player hub;
explicit "can be wrong / not medical / not an official rating" disclaimers. OBSERVED.

**CONS**: first released 2026-06-15, n = 8 ratings, single developer; accuracy unproven; still issues 0–100 scores per
swing. OBSERVED / INFERRED.

### 3.7 INTER TENNIS

**PROS (claims)**: 3D reconstruction of ball, racket and player from one phone; racket-tip speed path; contact height
relative to bounce; "Diagnose and Fix" groups shots sharing a fault; trends; iOS + Android. OBSERVED as listing claims.

**CONS**: no ratings on either store, no published validation, pricing not shown, requires a tripod beside the net at
1–2 m. Accuracy UNVERIFIED.

### 3.8 Tennis Math (Android)

**PROS**: 4.61★ / 3,345, 100K+ installs; many scoring formats; **fix the score while tracking**; advanced undo/redo;
comments, delays, cancellations; return winners and rally length; configurable tracking depth; live online broadcast;
Wear OS. OBSERVED.

**CONS**: Android only (iOS "to come"), no video; Play reviewers want a fuller per-point log and automatic side
switching. OBSERVED.

### 3.9 Context players (one line each)

- **PlaySight** (smart-court hardware): 2.87★ / 134 iOS, 2.84★ / 186 Android; AI kept one 12 s rally of a paid 40-min
  match (2026-08); uploads stuck at 0%. Club kiosks described as broken or unused. OBSERVED.
- **Wingfield**: 4.80★ / 61; gamified drills scored 0–100, net clearance, DUPR and German LK rating integrations;
  needs Wingfield courts. OBSERVED.
- **PlayReplay / Hawk-Eye / Baseline Vision / In/Out**: real line calling is hardware with ITF Gold/Silver
  classification; PlayReplay ≈$3,200 per court per year; In/Out v4 $299–$499. OBSERVED.
- **CoachNow** (4.86★ / 13,023) and **VisualEyes** (4.78★ / 402): coach-first analysis kits; compare via a link icon;
  VisualEyes 2.3.3 resumes uploads from the server offset. OBSERVED.
- **RacquetTune** (4.62★ / 482, $2.99): the string-tension benchmark; praised for relative tracking, criticised for
  absolute readings 7–15 lb below machine settings; reviews since 2020 average 3.1★. OBSERVED.
- **Hudl Technique** discontinued (2021, users moved to OnForm); **Coach's Eye** (TechSmith) retired — competitor
  pages date it 2022-03-31 (UNVERIFIED; no TechSmith primary page found); a different 2026 app now uses the name.

---

## 4. Feature matrix

Legend: **Y** = yes (OBSERVED); **P** = partial or with conditions; **–** = no / not found; **?** = UNVERIFIED.
JOVRA column = target, with backlog priority (`feature-backlog.md`) and the honesty label the number carries.

| Capability | SwingVision | Onform | SevenSix | Smashpoint | TennisCut | AI Swing Coach | Tennis Math | **JOVRA target** |
|---|---|---|---|---|---|---|---|---|
| Record full matches in-app | Y (60 fps, HD; 4K on Max) | Y (up to 240 fps; not match-oriented) | – (short clips, ≤1 min / 5 swings since 3.1) | Y (Critical Points only, Sep 2026) | Y (4K60, HDR) | P (practice swings) | – | **P0** 1080p60 default, 4K60 optional, crash-safe |
| Survives crash/interruption with playable file | P (repeated fixes in 2025–26 notes) | ? | – (reviews) | ? | ? | ? | n/a | **P0** fragments + journal; "Saved through mm:ss" |
| Thermal handling visible to user | P (spoken notice Sep 2026) | ? | ? | ? | ? | ? | n/a | **P0** heat ladder + court mode |
| Import external footage | Y (GoPro, Android files; foreground-only) | Y | P | – | P | Y (upload) | – | **P0** Photos/Files/Drive via Files, any fps |
| Automatic dead-time trim | Y (core) | – | – | P (critical points) | Y (on-device) | – | – | **P0** from bookmarks; auto-detect **P0-gated** (Estimated after benchmark) |
| Trimmed view shows skipped gaps / raw time | – (complaint) | n/a | n/a | – | ? | n/a | n/a | **P0** visible "+0:42" gap chips |
| Live manual scoring | Y (Watch) | – | – | Y (phone/Watch) | Y | – | Y | **P0** phone, with undo; Manual |
| AI auto-scoring | Y (≈80–90% per users) | – | – | – | – | – | – | **Later** (not promised); checkpoint auto-fill Estimated |
| Post-match point correction | P (flip winner via Edit Point → Point Details) | n/a | n/a | P (complaints) | ? | n/a | Y (fix while tracking, undo/redo) | **P0** flip/add/split/merge/delete, propagates |
| Fast swipe review of every point | – | – | – | – | – | – | – | **P0 NEW** Point Review deck |
| Shot placement map | Y (estimated from video) | – | – | P (manual charting) | P (trajectory overlay) | – | – | **P1** manual taps (Manual); video-derived **Later** (gated) |
| Line calls | Y (live audio + challenges; not ELC-certified) | – | – | – | – | – | – | **Never** (officiating); clip review only |
| Serve speed | Y (avg flight speed, ~10% below radar per FAQ) | – | – | – | – | – | – | **P2-gated** Estimated with ± range, else relative only |
| Stroke type labels | Y | – | Y | Manual | ? | Y | Manual | **P1** manual tags; auto **P2-gated** |
| Pose / skeleton overlay | – | Y (A15+, golf 3D) | Y (stickman) | – | – | Y (live) | – | **P2-gated** "2D pose estimate", near/side-on only |
| Frame-step + slow motion | Y | Y (best in class) | P | Y (½×, ¼×) | Y | Y | – | **P0** 3-tier scrub, ±1 frame, readout |
| Synced side-by-side compare | – | Y (sync "hit or miss" 2025) | P (vs pro curve) | – | – | P (vs "pro ideal") | – | **P0** manual contact sync (Align/Lock/Nudge); auto-sync **P2-gated** |
| Drawing / angles | – | Y (10 tools) | – | – | – | P (auto angles) | – | **P0** basic tools in sticky Draw mode; full set P1 |
| Voice-over / voice notes | – (Coach Reviews marketplace) | Y (+ transcription) | – | – | – | Y (spoken cues) | – | **P1** pinned voice notes; walkthrough export P2 |
| Highlights with burned-in score | Y | – | – | P (live pages) | P (recap card) | P (annotated clips) | – | **P1** score from the fold, never typed |
| Coach / opponent sharing | Y (web link; black in Chrome 2025) | Y (messaging, plans $19.99–$59.99/mo) | – | Y (live links) | ? | P (PDF) | Y (live broadcast) | **P1** Share Pack (clips + stats, expiring links) |
| Vendor cloud storage | Y ("every recording, forever" on paid tiers) | Y | Y (Premium) | ? | – | – | – | **None** (no JOVRA cloud) |
| User-owned cloud (Google Drive) | – | – | – | – | – | – | – | **P0** optional Drive archive, verified backups |
| Own video never locked by tier/time | – (Free: last 7 days only) | – (lapsed lockout) | ? | Y (private by default) | Y (local) | Y | n/a | **P0** contract |
| Works without account | – (shared account required for pairing per ITF) | – (forced login complaints) | ? | ? | ? | Y | ? | **P0** no account; Sign in with Apple optional |
| No recording-hour caps | – (8/16/30/60 h) | n/a | – (per-analysis) | Y | ? | Y | n/a | **P0** none for on-device work |
| No ads on personal video | – (free tier ads since 11.9.49, 2026-02-04) | Y | Y | Y | ? | Y | ? | **P0** never |
| No cross-app tracking (privacy label) | – (Usage Data used to track) | ? | – (tracking label) | ? | ? | ? | ? | **P0** target "Data Not Collected" |
| VoiceOver declared on App Store | – | – (claimed in notes, not declared) | – | ? | ? | ? | ? | **P0** VoiceOver-first review, declare honestly |
| Racket / string tracking linked to sessions | – | – | – | – | – | – | – | **P1** Racket Vault + String Journal (Manual; logged hours computed) |
| Handedness (player and opponent) | P (FH/BH filters assumed right-handed, 2025 review) | P (mirror) | ? | ? | ? | ? | ? | **P0** both players |
| Consent / junior / competition mode | – (Watch not permitted in ITF competition) | – | – | – | – | – | – | **P1 NEW** |
| CSV/JSON export | Y (stats export, Pro+) | ? | – | Y | ? | P (PDF) | ? | **P1** open versioned schema |
| Android app | – | Y (2.97★) | – | Y (small) | Y | – | Y | **P2 (next)** after iOS gates |
| Entry price | Free (capped) → $95.99–$299.99/yr | $49.99/yr → $79/mo | $1.99/analysis or $149.99/yr | $39.99/yr | $44.99/yr | Free → $79.99/yr | $4.99–$49.99 | **Decision** (straw man: free core forever; paid analysis) |

---

## 5. Praised → how JOVRA highlights and improves it

| # | What players praise (evidence) | How JOVRA keeps it and makes it better | Screens | Priority |
|---|---|---|---|---|
| 1 | **Dead-time removal** — 31 SV praise reviews; community rank-1 (79 authors, 413 upvotes); 8+ trim-only indie apps in 2025–26 | Rally-only playback from day one using manual bookmarks (no AI dependency), auto-detection added only after its benchmark; collapsed gaps stay visible and expandable; adjustable pre/post-roll; one full condensed-match file exportable on every tier (SwingVision capped Plus trimmed export at ~15 min, 2026-09) | 7, 8, 10 | P0 |
| 2 | **Stats depth** — 158 reviews (SV 127) | Every stat computed from point events with its fraction one tap away ("28 / 40"), provenance badge (Manual / Estimated / Reviewed) and a "watch evidence" link to the source clips; integer half-up rounding identical on iOS and Android | 9, 11, 12, 16 | P0 (match stats), P1 (labs, trends) |
| 3 | **Seeing yourself; "it made me better"** — 91 reviews; self-review and replay praise rising in 2025–26 | Make replay the hero loop: point → slow-mo → frame step → compare → drill. Frame-accurate three-tier scrubbing, 0.25×–2×, frame/time/fps readout | 10, 13, 14 | P0 |
| 4 | **Coach–player loop** — 146 reviews (Onform 97) | Share Pack: selected clips + notes + stats + `match.json`, delivered by AirDrop, Files or an expiring Drive link; viewers need no app or account; no per-student hour traps | 9, 10, 14, 15 | P1 |
| 5 | **Easy to start** — 144 reviews | No account, one tap to Record from every tab, framing that tells you exactly what to move, works on tripod or fence, pre-flight checklist (storage, battery, heat, Focus) | 1, 3, 4, 5 | P0 |
| 6 | **Compare in sync** — 30 reviews (Onform 20); Onform's single most frequent praise | Time-based sync (never frame index) with Align → Lock "Synced at Contact" → ±1-frame Nudge; mixed 60/240 fps; overlay with opacity and mirror; saved as a project, no duplicated video | 14 | P0 (manual), P2 (auto-sync) |
| 7 | **Drawing, angles, voice-over** — 22 annotate reviews; voice-over now standard | Sticky Draw mode where the jog still scrubs; editable shapes with handles attached to frame ranges; pinned voice notes; walkthrough rendered from an event timeline (ReplayKit can't capture AVPlayer) | 13, 14 | P0 basic, P1/P2 rest |
| 8 | **Highlights and sharing** — 61 reviews | Highlight reel with the score burned in from the fold (corrections re-render it), vertical crop, captions; user picks favourites with "Mark point" during play | 10 | P1 |
| 9 | **Wrist/live scoring** — 52 reviews (SV 43) | Phone-first manual scoring that never depends on a Watch; hands-free "Mark point" via volume/Action/Camera Control/AirPods stem; changeover checkpoint scoring (~10 taps a match) | 4, 6 | P0 (manual), P1 (hands-free) |
| 10 | **Worth the money vs lessons/radar** — 57 reviews | Free core forever (record, replay, manual scoring, review, export, Drive); charge only for compute-heavy analysis; no hour caps, no ads (pricing decision for Jon) | 19, 20 | P0 contract, P1 pricing |
| 11 | **Responsive support / visible improvement** — 75 reviews | In-app diagnostics bundle the user sends deliberately (no telemetry SDK), human reply target, public changelog | 20 | P1 |
| 12 | **Charting precision (Tennis Math, Smashpoint)** — Tennis Math 4.61★/3,345 on Play; Smashpoint 16 stats praise | Correct rules engine (ad/no-ad, tie-breaks, match tie-breaks, doubles rotation), fix-in-place, undo/redo, selectable tracking depth, "No winner" save | 4, 6, 9, 10 | P0 |
| 13 | **Junior development** — 5/5 positive junior-parent reviews; community 60 authors | Parent mode, child profiles local to the parent, private by default, ITF U18 consent helpers, opponent copy | 2, 4, 20 | P1 |
| 14 | **Live audio line calls / challenge replay** — 9 praise vs 12 accuracy complaints; mid-match replay widely seen as rude in rec play | Keep the useful part (a mutually agreed "review the clip" for both players), drop the verdict: no officiating claims | 10 | P2 (clip review); line calls Never |

## 6. Complaint → how JOVRA fixes it

| # | What players complain about (evidence) | How JOVRA fixes it | Screens | Priority |
|---|---|---|---|---|
| 1 | **Crashes / broken updates** — 151 core reviews, 33% of ≤2★ (crash code is the classifier's known weak spot: it absorbs generic "doesn't work" lines); all five apps | Crash-free capture as a release gate (device soak test), staged rollouts, no feature work while a P0 capture bug is open | all | P0 |
| 2 | **Recording stopped, footage lost, interrupted recording with no playable video** — 39 rec-fail + SV release notes 11.9.47–11.9.67 | Fragmented recording (~2 s) + write-ahead journal; session = segments + gaps; validate recovery by decoding; "Saved through mm:ss"; original kept even if analysis fails; one-tap "Save original to Photos" | 5, 6, 7 | P0 |
| 3 | **Uploads/processing stuck, sessions stuck "analyzing"** — 48 slow + 27 cloud; SevenSix 2023-11 → 2025-10 | No upload needed to review; separate, visible states for video / analysis / review / archive; resumable Drive uploads with persisted offsets; "Backed up" only after size + MD5 match; analysis waits for charger or continues via `BGContinuedProcessingTask` | 7, 8, 19 | P0 |
| 4 | **Price too high** — 60 reviews; "$50/yr would be fine" (2026-03); community: ~$50/yr for trimming alone, "<$10/mo I'd subscribe" | Free core forever; paid tier priced against the $40–$80/yr challengers, not SwingVision's $180–$300; one-time option considered | 19, 20 | Decision (P1) |
| 5 | **Paywall moves, trial-to-annual surprises, ads, own video locked** — 55 reviews; SV Free last-7-days lock and ads (announced 2026-01-15, shipped 11.9.49 on 2026-02-04), Onform lapsed lockout (2026-09) | Written "own-your-footage" promise: never lock, ad-wrap or quota a user's own video; grandfather features; trials never convert to annual without a second explicit confirmation; no weekly plans | 1, 19, 20 | P0 |
| 6 | **Recording-hour caps** — SV 8/16/30/60 h; Pro blocked at ~4 h (2026-10); "why a limit if processing is on device?" (2025-04) | No caps on anything that runs on the phone | 19 | P0 |
| 7 | **Apple Watch / second-device dependency; "watch said recording"** — 55 reviews | Phone-only is the first-class path; remote surfaces show the recorder's heartbeat and last-write time, never an assumed "Recording"; haptic/tone confirmation for every remote command | 6 | P0 (heartbeat), P1 (remotes) |
| 8 | **AI accuracy distrust** (speed outliers, cut points, wrong calls, player ID) — 64 reviews; rising to ≈18% of SV reviews | Capability registry: nothing automatic ships until a benchmark passes; numbers carry "Estimated" with ranges; speed defined explicitly (average flight speed); outliers flagged (net-cord serves); far-court values hidden below gate; no line calls | 9, 11, 12, 13 | P0 (registry), gates per capability |
| 9 | **Correcting the AI takes as long as editing by hand** — "fixing a missed point takes about as long as my own editor" (2026-09); player ID 170+ times (2024-08) | Fast Point Review deck (swipe winner per point, ~5 min per match) + changeover checkpoints that auto-fill consistent points; add/split/merge/delete; edits persist across reprocessing; player identity set once per match by court side, not per shot | 9, 10, new deck | P0 |
| 10 | **Scrub/draw conflicts, edge-gesture collisions, imprecise long-clip scrubbing** — Onform 2022–23 (4 reviews), SlowMo 2018/2023 | Jog strip above the transport row (never the bottom edge), ≥44 pt, ≥16 pt gap; lifting a finger never changes mode; Draw is a sticky explicit mode; Pencil-only on iPad | 10, 13, 14 | P0 |
| 11 | **Compare sync unreliable** — Onform 2025-05/07, VisualEyes 2026-04 | Time-origin model (Kinovea), per-clip Align then Lock (Dartfish), play one side alone to re-align, regression test sync on 60 vs 240 fps fixtures | 14 | P0 |
| 12 | **Setup friction, alignment never turns green, needs a second online device** — 18 reviews + 41 community authors | Concrete move-the-camera instructions, tripod and fence profiles, audio/haptic cues, camera-moved detection, calibration can be redone on the recorded footage later | 4, 5 | P0 (guidance), P1 (remote viewfinder, camera-moved) |
| 13 | **Storage bloat, undeletable app data, "videos deleted at low storage"** — community 135-point thread (80 GB), SV 11.9.64 fix | Per-session sizes, one-tap derived-cache cleanup, computed space estimate before recording, Space Saver rally-only archive, never delete an original without explicit confirmation and a verified backup | 4, 8, 19 | P0 |
| 14 | **Heat shuts recordings down** — SV release notes and FAQ; forums >85°F; 0 written reviews | Capture-only on court, no live inference; pressure ladder (helpers off → preview off → 30 fps) logged into metadata; "Phone warming · Recording safe" | 6 | P0 |
| 15 | **No Android** — 31 reviews; 147 community authors; Onform 2.97★ on Play | Shared JSON contracts and conformance fixtures from day one; Android (CameraX 1.6, Media3) after iOS capture gates; match Tennis Math's correction bar on day one of the port | — | P2 (next) |
| 16 | **Support bot-gated or slow** — 37 reviews | In-app diagnostics bundle sent only when the user taps it; human replies; no AI-only gate | 20 | P1 |
| 17 | **Login friction, forced third-party login, lockout before cancel** — 22 reviews | No account required; Sign in with Apple optional; Google sign-in only to connect Drive | 1, 20 | P0 |
| 18 | **Right-handed assumptions** — SV FH/BH filters (2025-04); PB Vision handedness "planned" since Dec 2024 | Handedness and backhand type for both players in setup; mirrored diagrams; stroke logic reads handedness | 2, 4, 13 | P0 |
| 19 | **Rigid formats; can't change session type later** — 37 community authors | Format presets incl. match tie-break, no-ad, short sets, standalone tie-breaks; format and session type editable after the match with recompute | 4, 9 | P0 (engine), P1 (all presets) |
| 20 | **Recording other people without consent; junior bans** — 52 community authors; ITF U18 rules (Aug 2025) | Consent row in setup, competition mode (no Watch, no live feedback), one-tap delete on withdrawal, audio off by default for match exports, opponent-copy link | 4, 6, 20 | P1 |
| 21 | **Score-overlay "how do I add scores?"** — repeated YouTube questions | Burned-in scoreboard export driven by the fold | 10 | P1 |
| 22 | **No racket/string context; string apps give misleading absolute tension** — zero equipment features in the big three; RacquetTune absolute readings 7–15 lb low | Racket Vault + String Journal linked to sessions; tension stored exactly as entered; logged court time computed; no tension "sensor" or life prediction in v1 | 4, 17, 18 | P1 |

---

## 7. Where JOVRA should not compete

| Area | Why not (evidence) | JOVRA stance |
|---|---|---|
| Line calling / officiating | Single phone: far baseline ≈0.2–0.4 m per pixel vs 5–10 cm lines (raw/ios-tech.md); ITF approval explicitly does not certify accuracy; 12 accuracy complaints vs 9 praise; mid-match replay viewed as rude; real ELC is hardware at ~$3,200/court/yr | Never. Offer "review the clip together" only |
| "AI coach" chat | ~40 near-identical AI-coach apps launched Jan–Sep 2026, none with >70 ratings; SevenSix removed its AI Coach after two months | Descriptive, evidence-linked suggestions only; optional on-device recap later (P2) |
| Live streaming | Server cost, minors (ITF bans posting U18 footage) | Not in v1 |
| Pro-player comparison libraries, spin RPM, injury prediction | Licensing/likeness; unsupported by single-camera evidence | Never (brief already bans) |
| Pickleball/padel breadth | SwingVision's pickleball reviews average 3.37★ with attribution and spin complaints; breadth spread quality thin | Tennis first; sport-agnostic schema; pickleball P2, padel Later |

---

## 8. Pricing benchmarks and the decision for Jon

| Tier | Products (annual unless noted) |
|---|---|
| Free / no account | Swingli, AI Tennis Swing Coach core, TennisCut core, MatchTrack basic, SwingVision Free (8 h/mo, 7-day access, ads) |
| ≤ $50 | Smashpoint Pro $39.99; TennisServe $39.99; TennisCut $44.99; TorqAI $49.99; Onform Personal $49.99 |
| $50–$130 | Toach $79.99; AI Swing Coach $79.99; Wingfield $89.99; SwingVision Plus $95.99; SmartHit $119.99 |
| $130–$200 | Smashpoint Elite $149; SevenSix $149.99; SwingVision Pro $179.99 |
| > $200 | SwingVision Max $299.99 (5 seats); Onform Coach $299.99 |
| Per use | SevenSix $1.99/analysis; PlaySight ≈$10/match; AI Swing Coach credits |

Market median for an AI tennis subscription ≈ $80–$120/yr (INFERRED, raw/landscape.md §5). Stated willingness to pay:
≈$50/yr for trimming alone; "under $10 a month"; $150–170/yr only if tracking were accurate (raw/community.md §7).
**Straw man (INFERRED, decision for Jon):** free forever = record, replay, manual scoring, Point Review, rally-only
playback from bookmarks, export, Drive archive; paid (one-time or ≈$40–$80/yr) = gated automatic detection, highlights,
labs, recaps; Family Sharing; no hour caps, ads or silent trial conversions. JOVRA runs no servers, which is what makes
this sustainable.

---

## 9. Contradictions between sources, resolved

| Topic | Conflict | Resolution (which source wins, why) |
|---|---|---|
| SwingVision written-review mean | 3.58 (review-mining) vs 3.39 (swingvision) vs 3.26/3.60/2.98 per year (gap-finder) | All consistent: different windows (all 490; 2024-10→2026-10 n=165; per year). Use 3.58 overall and 2.98 for 2026 |
| SwingVision 1★ share | 24% (swingvision, two-year window) vs 38% (gap-finder, 2026 only) | Both correct for their windows |
| SwingVision free tier | 2 h/month (older reviews, 2021–2025 forum) vs 8 h/month (vendor newsletter, v11.9.49) | **8 h/month**, still shown on swing.vision/subscribe on 2026-10-07. Announced in the newsletter dated **2026-01-15**; the App Store version history shows "New Free Tier!" first in **11.9.49 (2026-02-04)**. The 7-day access, 5-minute export and ads limits come from the newsletter only (not in release notes or the listing) |
| Recording-hour caps | Free 8 / Plus 16 / Pro 30 / Max 60 (swingvision, compare page) vs Plus 20 / Pro 30 / Max 60 (gap-finder, third-party) | **Compare page wins** (primary, rendered in a browser); gap-finder had marked its figures UNVERIFIED |
| Pro monthly price | $14.99/mo in the listing description vs $24.99 IAP | **$24.99 IAP wins** (re-checked live). $14.99 equals Plus Monthly, not Pro; the description is most likely copy written before the Plus/Pro/Max tiers (INFERRED). A developer reply quoting a $149.99 annual price is also stale. Do not use the description or replies as pricing sources |
| Speed vs radar | ~10% below radar (current FAQ) vs ~20% below peak (Tennis.com 2022) | **FAQ wins** as the current vendor definition; independent tests show ~6% error on in-bounds serves, ~42% on net-cord serves |
| "Single camera" | Marketing vs ITF report (one or two devices) | **ITF report wins**: 1–2 devices plus optional tablet |
| Audio-guided setup | Guide image shows it vs May 2026 review + forum + YouTube comments say removed | Three independent 2026-05 user reports suggest removal (INFERRED); status UNVERIFIED |
| Onform pricing | $9.99/$14.99 individual + $19.99–$59.99 coach (listing) vs ten tiers $4.99–$79/mo (IAP list) | Both OBSERVED: the IAP list is the full set, the description quotes a subset |
| Coach's Eye retirement date | 2022-03-31 cited as OBSERVED (community) vs UNVERIFIED (video-analysis) | **UNVERIFIED**: only competitor pages state it; no TechSmith primary source |
| Heat as a pain | 0 written reviews vs many release notes and forum posts | Real and current (vendor keeps patching it); reviewers attribute the symptom to "lost recording", not heat |
| Android: SwingVision presence | "Working closely with Google engineers" (FAQ) vs "Android can't sustain 60 fps real-time" (CEO, forums) | No Android build observed as of 2026-10; re-check before marketing against it |

---

## 10. Freshness caveats (complaints that may already be fixed)

- SwingVision's flip-winner path (Edit Point → Point Details) exists since 2024; score-correction complaints peaked in
  2023–24 (8% of reviews) and fell to 4% in 2025–26. Still present, less often.
- The SwingVision subscription upsell bug (manage button led into a Max purchase) was fixed 2025-11-23 per the CEO.
- Onform's 2022–23 scrub/edge-gesture complaints are probably fixed (current screenshots show the scrubber above the
  transport row).
- SwingVision added a low-storage warning (11.9.56, 11.9.62, 11.9.67), Ground Mode (11.9.54) and court-angle feedback
  (11.9.30) — setup complaints peaked in 2023–24.
- The public review feed omits developer replies; some issues may have been answered privately.
- Re-verify any competitor claim before it appears in marketing copy.

---

## 11. Verification log

An independent verification pass (2026-10-07) tried to refute ten load-bearing claims against primary sources; a
completeness critic then applied the verdicts across all synthesized files. Verdict key: **confirmed** = could not be
refuted; **partially true** = numbers hold but wording overstated or a detail was wrong. No claim was refuted outright.

| # | Claim (short) | Verdict | Correction applied (where) | Primary source |
|---|---|---|---|---|
| V1 | SwingVision listing: 4.706★ / 4,928, v11.9.67 (2026-09-27), iOS 18.0; IAP Plus $14.99/$95.99, Pro $24.99/$179.99, Max $39.99/$299.99; description wrongly quotes Pro at $14.99/mo | Confirmed | Added that the description and a developer reply ($149.99/yr) are stale and must not be used as price sources; added the web compare page's first-year Pro Yearly $143.99 and Max $22.99/mo offer (§2, §9). Ratings change daily; US storefront only | iTunes lookup id 989461317; apps.apple.com/us/app/id989461317; swing.vision/subscribe/compare |
| V2 | Written-review means 3.58 (n=490) and 2.98 in 2026 (n=50); 44% of 289 ≤2★ reviews are reliability, 27% money | Partially true | Means reproduce exactly (feed is a capped ~500-review pool). 44%/27% are multi-label "mentions at least one" shares from one rule-based coder (20 overlap, 36 uncoded, 64 crash-only); a simpler pass gives ≈37% / up to ≈38%. Rewrote as "the two biggest groups, reliability not clearly ahead" (§0.4; feature-backlog P0-01; technical-feasibility §1) | RSS feeds for ids 989461317, 1490334045, 1505604446, 1098174650, 976177330; raw/review-mining.md |
| V3 | Hour caps Free 8 / Plus 16 / Pro 30 / Max 60; since February 2026 Free shows only the last 7 days, caps exports at 5 min, shows ads | Partially true | Caps confirmed live. The newsletter announcing the Free tier is dated **2026-01-15**. This pass additionally found the App Store version history showing "New Free Tier!" first in **11.9.49 on 2026-02-04** (OBSERVED), so "announced Jan 15, shipped Feb 4" replaces "since Feb 2026" everywhere (§2, §3.1, §4, §6, §9; feature-backlog P0-18, N-02; README). The 7-day / 5-min / ads limits are newsletter-only (not in release notes or the listing) and were not re-confirmed inside the current app | swing.vision/subscribe, /subscribe/compare, /newsletters/free-tier; apps.apple.com version history |
| V4 | ITF PAT-25-037 (2025-10-31, v11.9.6) does not establish accuracy, does not permit the Watch in competition; 60 fps rear camera, one or two devices, backend server | Confirmed | Added that it is a Rule 31 PAT approval (not ELC certification), that the approved system includes tablet line calls with challenges, and that v11.9.6 is the tested build (§2) | itftennis.com/media/15294/pat-25-037-approval-report-swingvision.pdf |
| V5 | `movieFragmentInterval` 10 s default, must be set before recording; `initialMovieFragmentInterval` only on AVAssetWriter (iOS 17+); delegate always called; `AVErrorRecordingSuccessfullyFinishedKey` decides playability; `pauseRecording()` iOS 18+ | Partially true | Setting mid-recording is allowed but only affects the next file; the delegate guarantee does not hold on crash/jetsam/power loss, so recovery must read the fragmented file at next launch; nil error = success, otherwise read the key; AVAssetWriter's own fragment interval defaults to off; pause is unavailable on visionOS/watchOS (technical-feasibility §1, §17; feature-backlog P0-01). Device crash survival remains **UNVERIFIED** until the soak test | iPhoneOS26.5.sdk AVCaptureFileOutput.h, AVAssetWriter.h, AVError.h |
| V6 | ReplayKit can't record AVPlayer, so voice-over must be an event timeline rendered with AVMutableComposition + Core Animation; the Core Animation tool is export-only | Partially true | Both API facts hold; "must" softened: a custom `AVVideoCompositing` compositor or Metal/Core Image + AVAssetWriter also works; live preview uses `AVSynchronizedLayer`; `AVPlayerItem.videoComposition` does not work with HLS (technical-feasibility §4, §17; feature-backlog P2-06) | developer.apple.com: RPScreenRecorder, animationTool, AVSynchronizedLayer, AVPlayerItem.videoComposition |
| V7 | `drive.file` non-sensitive → no unverified screen, no 100-user cap; brand verification still needed; Testing tokens expire in 7 days; 256 KiB chunks; 308 + Range = resume; `about.get` accepts `drive.file` | Partially true | "No 100-user cap" holds only in production (Testing status is limited to 100 listed test users); brand verification is **optional** for non-sensitive scopes (needed only to show name/logo); chunks are 256 KiB multiples except the last; 308 without Range = restart at 0 (technical-feasibility §13; feature-backlog intro, P0-17, Decisions) | developers.google.com Drive api-specific-auth, manage-uploads, about/get; support.google.com/cloud 15549945, 7454865, 13463073 |
| V8 | Play requires target API 36 since 2026-08-31 (extension 2026-11-01); CameraX 1.6 Media3 muxer default with crash resilience and 60 fps via SessionConfig; dataSync FGS capped 6 h / 24 h since Android 15 | Confirmed (with refinements) | SessionConfig / `GroupableFeature.FPS_60` arrived in CameraX **1.5.0** and are device-dependent (`isSessionConfigSupported`); Media3 muxer default in 1.6.0 stable (2026-03-25); dataSync limit applies to apps targeting 35+, is shared across the app's dataSync services, resets on foreground, and requires `onTimeout` handling; Wear OS/Automotive need 35+, TV/XR 34+ (technical-feasibility §14, §18; feature-backlog P2-01) | developer.android.com target-sdk, camera release notes, fgs/timeout, GroupableFeature |
| V9 | Platform rounding: NumberFormatter and FormatStyle percent and Java DecimalFormat are half-even; Swift `rounded()`/Kotlin `roundToInt()` round ties up; use `pct(n,d) = (200n+d) div 2d`; fixture 58/67/70 under any rule | Partially true | Plain `.formatted(.percent)` shows "12.5%" (no integer rounding); half-even only once `.precision(.fractionLength(0))` is set. Formula valid for n ≥ 0, d > 0. Android ICU `DecimalFormat` default rounding is **UNVERIFIED** (tennis-rules-and-stats rule 4, §7) | Local Swift 6.3.3 run; Oracle DecimalFormat docs; Kotlin roundToInt docs |
| V10 | No SwingVision/SevenSix/Toach on Google Play; Onform 2.97/309 Android vs 4.79/8,666 iOS; best-rated Android tracker Tennis Math 4.61/3,345, no iOS app | Confirmed (with refinements) | Tennis Math is a scorekeeping/stats app, not a video tracker; "absent" rests on a no-JavaScript Play search plus guessed package names, strong but not exhaustive (§0.8; technical-feasibility §14) | play.google.com search and detail pages; iTunes lookup/search |

---

## Sources

All accessed 2026-10-07.

| URL / file | What it supported |
|---|---|
| https://itunes.apple.com/lookup?id=989461317&country=us | SwingVision 4.706 / 4,928, v11.9.67 (2026-09-27), iOS 18.0, description price text (re-checked live) |
| https://apps.apple.com/us/app/id989461317 | SwingVision IAP prices (re-checked live), histogram, privacy and accessibility labels, version history |
| https://itunes.apple.com/lookup?id=1490334045&country=us | Onform 4.786 / 8,666, v4.7.3, iOS 18.6 (re-checked) |
| https://itunes.apple.com/lookup?id=1505604446&country=us | SevenSix 4.191 / 68, v4.0.2 (2026-10-07), iOS 15.6 (re-checked) |
| https://itunes.apple.com/lookup?id=1098174650&country=us | Smashpoint 4.509 / 462, v3.4, iOS 16.2 (re-checked) |
| https://itunes.apple.com/lookup?id=6754323620&country=us | TennisCut 4.083 / 12, v2.0.0, iOS 17.0 (re-checked) |
| https://itunes.apple.com/lookup?id=365729342&country=us | RacquetTune 4.624 / 482, $2.99, v7.7 (re-checked) |
| https://itunes.apple.com/us/rss/customerreviews/page=1..10/id=989461317/sortby=mostrecent/json | 490 SwingVision written reviews (theme counts, means) |
| https://itunes.apple.com/us/rss/customerreviews/page=1..7/id=1490334045/sortby=mostrecent/json | 297 Onform reviews |
| https://itunes.apple.com/us/rss/customerreviews/page=1/id=1505604446/sortby=mostrecent/json (+gb, ca) | 13 SevenSix reviews |
| https://itunes.apple.com/us/rss/customerreviews/page=1..3/id=1098174650/sortby=mostrecent/json | 56 Smashpoint reviews |
| https://swing.vision/subscribe/compare and https://swing.vision/faq | Hour caps, tiers, 7-day access, speed definition, heat/System Pressure guidance |
| https://swing.vision/newsletters/free-tier | Free tier 8 h, 7-day access, 5-min exports, ads (Jan 2026) |
| https://www.itftennis.com/media/15294/pat-25-037-approval-report-swingvision.pdf | PAT-25-037: 60 fps, 1–2 devices, backend, Watch not permitted, accuracy not certified |
| https://doi.org/10.3390/app13106195 | Bilić et al. 2023 validity study (n = 5) |
| https://play.google.com/store/apps/details?id=com.tennismath.ui.android | Tennis Math 4.61 / 3,345, features |
| https://play.google.com/store/apps/details?id=com.app.OnForm | Onform Android 2.97 / 309 |
| https://play.google.com/store/search?q=swingvision&c=apps&hl=en_US&gl=US | No official SwingVision Android app |
| https://support.onform.com/article/153-user-guide-onform-video-analysis-app | Onform scrubbers, tools, voice-over modes and quotas |
| https://support.dartfish.tv/support/solutions/articles/27000047295-compare-videos-in-split-screen and https://kinovea.org/help/en/observation/comparison.html | Compare sync models |
| https://www.itftennis.com/media/15017/itf-performance-analysis-video-u18-august-2025.pdf | ITF U18 consent, opponent copy, deletion on withdrawal |
| https://www.itftennis.com/en/about-us/tennis-tech/classified-elc-systems/ | ITF ELC Gold/Silver systems |
| https://www.usta.com/en/home/stay-current/missourivalley/oklahoma/edmond-center-court-playreplay-electronic-line-calling-system.html | PlayReplay ≈$3,200 per court per year |
| https://tt.tennis-warehouse.com/index.php?threads/swing-vision-ai-line-calls-and-analysis.653818/ | 1,119-post SwingVision thread (CEO statements, complaints) |
| https://www.reddit.com/r/10s/comments/1luxj5w/ , /1o2ceg8/ , /1j39izh/ , /1lshufy/ , /17vtrs5/ | Trimming as primary use; 80 GB storage; Android; speed disbelief; replay etiquette (via Arctic Shift archive) |
| https://www.youtube.com/watch?v=fJdvIPkvd50 | 50-serve speed test vs Pocket Radar |
| https://pbvision.featurebase.app/p/shot-explorer-for-left-handed-players | Right-handed model assumption |
| /Users/IDC2.5/jv/docs/research/raw/review-mining.md | Coded counts, umbrellas, trends, ranked love/pain lists |
| /Users/IDC2.5/jv/docs/research/raw/swingvision.md | SwingVision listing, pricing history, release notes, hand-coded window, steal/improve/avoid |
| /Users/IDC2.5/jv/docs/research/raw/community.md | Forum/Reddit/YouTube wishlist with author counts and upvotes |
| /Users/IDC2.5/jv/docs/research/raw/landscape.md | 347-app sweep, Android gap, next-five selection, pricing tiers, white space |
| /Users/IDC2.5/jv/docs/research/raw/video-analysis-apps.md | Onform/SevenSix/coaching-tool detail and UX failure modes |
| /Users/IDC2.5/jv/docs/research/raw/gap-finder.md | 2026 shipped features, ranked opportunities, 2024–26 keyword pass |
| /Users/IDC2.5/jv/docs/research/raw/equipment-stringing.md | Equipment white space, RacquetTune review analysis |
| /Users/IDC2.5/jv/design-reference/brief/research.md | Prior brief (all its rating claims confirmed) |
| https://apps.apple.com/us/app/id989461317 (version history, fetched 2026-10-07) | "New Free Tier!" first in 11.9.49, 2026-02-04 (also 11.9.50, 2026-02-09) |
| https://itunes.apple.com/lookup?id=1490334045,1505604446,1098174650,6754323620&country=us (`screenshotUrls`) and the mzstatic images they list | §2.1 screenshot review of Onform (10), SevenSix (10), Smashpoint (10), TennisCut (7) |
| https://swing.vision/subscribe and https://swing.vision/subscribe/compare (rendered in a browser by the verifier) | Free 8 / Plus 16 / Pro 30 / Max 60 h; first-year Pro Yearly $143.99; Max $22.99/mo web offer |
| https://www.itftennis.com/media/15294/pat-25-037-approval-report-swingvision.pdf (re-read by the verifier) | Rule 31 PAT approval, tablet line calls with challenges, Watch not permitted, accuracy not established |
| https://itunes.apple.com/us/rss/customerreviews/id=976177330/sortby=mostrecent/json | PlaySight reviews in the 289-review low-star pool |
| https://play.google.com/store/search?q=sevensix%20tennis&c=apps&hl=en_US&gl=US and ?q=toach%20tennis | No SevenSix or Toach listing on Play |
