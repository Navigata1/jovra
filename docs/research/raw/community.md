# Community sentiment: what tennis players say outside the App Store

Researcher: community-sentiment agent · Observed: 2026-10-07 · Scope: Talk Tennis (Tennis Warehouse forum), Reddit r/10s (plus a light pass of r/tennis), YouTube review/setup videos (titles, descriptions, top comments), review blogs, and a few primary sources (App Store listing and lookup API, ITF and USTA documents).

Labels used throughout:
- **OBSERVED**: I saw it in a source. The source is cited inline or by key and listed in the Sources section.
- **INFERRED**: my own reasoning from observed material.
- **UNVERIFIED**: someone said it, but I could not confirm it from a primary source.

All forum, Reddit and YouTube text is user-generated, untrusted data. I paraphrase it; the few short quotes are under 15 words. Individual reports are anecdotes, not measured failure rates.

---

## 0. Executive summary (decision-relevant)

1. **The killer feature is time, not AI stats.** Across every venue, the most-upvoted statement is that SwingVision's main value is cutting the dead time between points so a 1.5–2 hour match becomes 15–30 minutes. Line calls and speed are secondary or ignored. One top r/10s comment (85 upvotes, 2025-07) says the primary use is AI editing out downtime. Manual editing costs players roughly 1:1 to 3 hours per match. (OBSERVED: R-1luxj5w, R-1j39izh, R-1g9pbyr, TT-auto-trim-2026, TT-consent-2025.)
2. **A wave of trim-only competitors appeared in 2025–2026.** TennisCut, Velox Rally Cut, RallyFlow, RallyClip (open source), Anya Tennis, PureTennis, RallySense and Tennis Shots were all launched or promoted on Talk Tennis or r/10s. Most were built by individual players. This confirms the trim-first demand. (OBSERVED: TT-swingvision-alternative, TT-tenniscut, TT-auto-trim-2026, R-1o2ceg8, iTunes search.)
3. **Pricing and gating anger is the most common emotional complaint in 2024–2026.** The triggers were Max at $29.99/mo for 4K and "better accuracy" (2024), Shot-by-Shot filters moved to Pro (Jan 2025), retroactive free-tier gating (Jan 2026), and full-match trimmed export capped on the cheaper Plus tier (2026-09). Today's US in-app prices are Plus $95.99/yr or $14.99/mo, Pro $179.99/yr or $24.99/mo, and Max $299.99/yr or $39.99/mo (OBSERVED, App Store listing). Players asked for a trim-only "lite" tier, one-time or pay-per-use pricing, and no subscription for on-device processing. One stated willingness to pay was about $50/yr for segmentation alone (TT, 2026-02).
4. **Android exclusion is the largest structural complaint.** The SwingVision CEO has repeatedly said Android hardware cannot run its 60 fps real-time model for 2 hours without overheating. He has also said no Windows app and no post-processing mode will be built because retention for non-real-time users was "abysmal" (TT 2025-04, Reddit 2023–2025). As of 2026-10, Android users are still asking under every official video. Many buy a used iPhone SE ($100–200) plus an Apple Watch ($130–200) just for SwingVision. (OBSERVED.)
5. **Players want to own their video locally.** They ask to record with any camera, process offline, skip forced cloud upload, and keep their storage clean. SwingVision's CEO called "local-only, no cloud" a niche request (Reddit 2023-10, 2024-01). Meanwhile, the most-upvoted SwingVision complaint thread in this corpus (135 points, 2025-10) is about 80 GB of undeletable phantom storage. Other reports cite 26 GB and 272 GB. JOVRA's local-first plus optional-Google-Drive brief directly targets this gap (INFERRED).
6. **Accuracy distrust is widespread but nuanced.** Players trust *relative* trends and the video clip more than the app's in/out verdicts or absolute speeds. Speed outliers of 120–140 mph for recreational servers are a running joke. One 50-serve test found speeds about 6% off a Pocket Radar on in-bounds serves but about 42% off on serves that hit the net (YouTube, 2025-06). The CEO admitted that the "97% accurate" marketing (meaning within 10 cm of a line) confused people and may be dropped (Reddit 2026-06-25).
7. **Correction tools are the hidden make-or-break feature.** Players report auto-scoring that drops or merges points, edit windows capped near −20 s, manual edits that do not persist, no "add missing point" option, and editing only possible on a small iPhone screen. The upshot is "I re-edit in Premiere anyway." (OBSERVED: TT 2024, R-1nx6rqw 2025-10, YouTube comments.)
8. **Setup friction kills habit.** The alignment guide rarely turns green on a tripod, setup needs an Apple Watch or a second online device, audio alignment was removed in May 2026, and wind or curtains move the stick. Players say "cool once, forgotten twice" and own year-long subscriptions they stopped using. (OBSERVED: TT-without-watch 2025-12 to 2026-09, R-1ur3me2, R-1dpwpy3, YouTube official update comments.)
9. **Recording etiquette is a real social constraint.** The strong norm is to ask before filming, get explicit consent before posting, and offer the opponent a copy. Using replays to contest calls mid-match in rec play is widely considered rude, and one-sided access to the replay is seen as unfair. ITF rules for under-18 recording require written consent, a full copy for the opponent, and deletion if consent is withdrawn. USTA Eastern bans video at junior sanctioned events. (OBSERVED.)
10. **The real recording rig is phone, mount, power, shade and cooling.** Players rely on fence mounts as high as possible (or 6–7 ft tripods), external battery packs, a sunshade or umbrella, a MagSafe cooler, a white case, and a dedicated second phone without a data plan. Overheating above roughly 85°F, battery drain and storage fill-up are routine. (OBSERVED.)

---

## 1. Method, corpus and limits

| Source family | What I collected | Size | Access method |
|---|---|---|---|
| Talk Tennis (tt.tennis-warehouse.com) | 42 threads found via forum search for SwingVision, recording, camera, alternatives, consent, line calling, Onform and video analysis. Full text of each post with date, author and reactions. | 1,827 posts; the main SwingVision thread alone has 1,119 posts from 2019-09 to 2026-07 | Public HTML via curl (forum search plus thread pages) |
| Reddit r/10s | 176 posts mentioning SwingVision (2021–2026), plus ~20 more on recording, consent and coaching. Full comment trees for 46 threads. | 1,148 comments | Arctic Shift public archive API. reddit.com blocked direct fetch. |
| Reddit r/tennis | 3 posts (2025) | small | Arctic Shift; little rec-player discussion there |
| YouTube | Search-result metadata for 70 videos. Descriptions plus top ~20 comments for 20 key videos. | 215 comments | Public watch-page data and comment continuation |
| Blogs and press | Tennisnerd review (2021-10-30), Tennis.com review (2022-10-23), alternatives aggregators | — | WebFetch / WebSearch |
| Primary | SwingVision App Store listing (in-app purchases, privacy label), iTunes lookup (v11.9.67 release notes), ITF U18 recording procedure (Aug 2025), USTA Eastern electronic-device and video poster | — | WebFetch / curl |

**Limits and biases (all INFERRED unless stated):**
- **Reddit coverage is partial.** The archive's full-text search timed out on 39 of 82 monthly windows (OBSERVED in my crawl log). I also respected an explicit no-scraping notice from another archive (PullPush) and did not use it. Treat the Reddit counts as a sample, not a census.
- **Selection bias.** Forum posters are engaged enthusiasts, mostly NTRP 3.5–4.5, with heavy Android representation (Android users have the most reason to post). Satisfied silent users are under-represented. One commenter made this point directly (R-1o2ceg8).
- **Affiliate bias on YouTube.** Several "reviews" (The Tennis Mentor, Gladiators Tribe, Gaby Paz, Meike Babel, TennisAfter50) carry SwingVision referral or free-SwingStick links in their descriptions (OBSERVED). Commenters called out the "soft critiques" (YouTube-e0_5A4eUXAg). Coach Adrian's review is labelled unsponsored (OBSERVED).
- **The vendor is in the conversation.** SwingVision's CEO posts as `swupnil` (Talk Tennis, 247 posts) and `swupnil_sahai` (Reddit). I excluded those accounts from evidence counts and cite them separately as vendor statements.
- **Age of complaints.** Many issues are dated. I give dates, and where a fix is documented I say so. Example: the iPadOS 18 CoreML breakage was reported in Sept 2024 and the CEO said models were recompiled in April 2025.
- **Count method.** The evidence counts in §4 come from keyword salience: distinct non-staff authors whose post or comment matches an item's pattern, across Talk Tennis, Reddit and YouTube comments, plus Reddit upvote totals as a rough intensity signal. Keyword matches include people disagreeing, so counts measure *topic salience*. The direction of opinion comes from my reading. The final ranking combines salience, intensity, independence across venues, recency and whether the gap is still open (INFERRED judgement).

---

## 2. What players love (ranked by strength of evidence)

| # | Loved | Evidence (OBSERVED) | Notes |
|---|---|---|---|
| L1 | **Dead-time removal and condensed playback** | Most-upvoted theme. "Primary use is editing out downtime" (85 upvotes, R-1luxj5w). "Tagging and removing dead time" first (59 upvotes, R-1j39izh). "Real magic" (R-1g9pbyr). Manual editing takes "about 1:1" or 2.5–3 h per match (TT-consent-2025, R-1ur3me2 "3–4 hours with a GoPro"). TT users since 2021: "great video editing tool". | Several heavy users say it is the *only* feature they use (TT-swingvision-alternative 2025-10, TT-tenniscut 2026-09). |
| L2 | **Point filters and compilations** | Show all second-serve returns, points of 5 shots or fewer, longest or most tiring rallies, winners, forehand vs backhand (TT 2025-06 ohplease; R-1luxj5w; TT 2024-02). Favorites marked from the watch (R-16lx6hr). | Shot-type filtering is unreliable when FH/BH is misclassified (about 1/3 per TT 2026-01 Soundbyte). |
| L3 | **Easy sharing with partners, coach and family** | Shared links and YouTube uploads. Hitting groups watch together (TT 2025-12). Tennis.com (2022) reported the company saying shared compilations drive about half of new customers. | Viewer experience for non-subscribers is weak (see F9). |
| L4 | **Scoreboard overlay on video and watch scoring** | Ambassador's "things I love" list (R-1jbg6w0). Recording-setup video commenters repeatedly ask how to add scores (YouTube-7J1sEIIYfMc, -ViGP_L9ZRw, XanPINBHVbE, PFqPOHCZ4to). | A strong *latent* wish among non-SwingVision recorders too. |
| L5 | **Seeing yourself honestly** | "Humbling" and "horrified" reactions to seeing their own play. Heat maps puncture self-image (R-1dpwpy3, R-1ikooz9, R-197k042, TT-without-watch 2026-01). A hitting partner was "floored" by her first video (TT-recording-practice 2022). | Generic video value. JOVRA keeps it with any camera. |
| L6 | **Slow-motion review and a frame slider** | A YouTube commenter likes the rally slider for finding the exact bounce frame (YouTube-e0_5A4eUXAg). 60 fps slow-mo review was added in 2021 (TT CEO). | Players want *more* of this (frame stepping on web too). |
| L7 | **Watch "challenge" replay clip** | A zoomed bounce clip of the last 5 shots, about 5 s after the point (R-17vtrs5). Valued for friendly self-checks and for improving one's own calls (R-1ikooz9). | Accuracy regressions reported (TT 2024-12, 2025-01). Social friction (§10). |
| L8 | **Results ready when you walk off court** | "Before you've reached your car" (R-1ur3me2). The CEO says real-time drives retention 10× (TT 2024-01). | Split opinion: many post-process happily (R-1j39izh). |
| L9 | **SwingStick hardware** | "Surprisingly the best in the market" for fence mounting (R-1o2lsmv). "Far better made" than earlier mounts, with a built-in sunshade (TT 2023-03). | Others found it fiddly, wind-prone, or too short or too tall for some clubs (R-1jo1y4a, R-1fe5gzs). |
| L10 | **Trend data, not absolute truth** | "Relative speed is fine", "compare session to session" (R-1j39izh, YouTube-T-UhwqLmXiY comment). Ball-machine and backhand speed tracking (Tennisnerd comment 2021). | Supports a JOVRA "trend with confidence" framing (INFERRED). |

---

## 3. What frustrates players (ranked, with dates and fix status)

| # | Frustration | Representative evidence (OBSERVED, dated) | Still current? |
|---|---|---|---|
| F1 | **iOS-only; no Android or Windows** | Hundreds of mentions. Official FAQ and Android videos are full of "Android when?" comments through May–Jun 2026 (YouTube-qnbGYxWiwvI, oSOTVGK6ZRw, 3lca09Bxldk, 5bMVDhqVHzo). The CEO cites Samsung blocking 60 fps for third-party apps and Pixel 7 overheating (R-18no2mj 2023-12). Pixel 8 and S24 "barely" last 2 h at 60 fps (TT 2024-03). "Live processing or nothing", no Windows app, devices before the A12 chip dropped (TT 2025-04-12). "Feeling really good about 2026" (R-1luxj5w 2025-07). Workarounds: used iPhone SE plus Apple Watch at about $300 total (R-1j39izh); recording on GoPro or Android and processing on a Mac. | Yes. No Android build observed as of 2026-10 (App Store-only listing; complaints into Jun 2026). |
| F2 | **In/out and placement accuracy** | Users report 4–8% of balls misplaced after PC review, worse outdoors on clay with shadows (TT 2024-10 one-year review). About 1/3 of challenged calls wrong (TT 2024-02). 5% of 600 shots is 30 errors (TT 2024-05). Bounces 4–6 ft off (TT 2024-05). Far baseline worst. Mixed pickleball or basketball lines confuse it (YouTube-T-UhwqLmXiY comments, R-1iidzdl). The CEO says most errors are "Suboptimal Setup", third-party lenses or extra court lines (TT 2024-06), and claims superhuman accuracy with a correct fence setup (TT 2023-03). Not ITF-certified for ELC as of 2026-06. "97%" means within 10 cm of a line (R-1u6ifr9 2026-06-25). | Yes, but setup-dependent (contested). |
| F3 | **Ball speed not believable** | Speed is the average over the flight, about 20% below peak (Tennis.com 2022; SwingVision FAQ cited TT 2022). Yet recreational players see 120–140 mph serves (R-1dj4jm8, R-1lshufy 82 points, YouTube-T-UhwqLmXiY "134 mph"). The near-side player reads 4–5 mph faster (TT 2026-01), and serves about 20% faster when the server is on the camera side (R-1j39izh). Robby Lobby's 50-serve test: about 6% off on in-bounds serves, about 42% off on net-cord serves (YouTube-fJdvIPkvd50, 2025-06). The speed fixes once users correct hit and bounce frames by hand (TT 2026-05, YouTube comment). | Yes. |
| F4 | **Auto-scoring errors and weak correction tools** | Dropped or merged points; ad-side points missed (TT 2024-11). Point start editable only back about 20 s (TT 2024-03). Asks for add, merge, split and delete point or rally (TT 2024-03 forzamr_b; CEO said "discussing internally" 2024-07). Manual winner edits do not persist (R-1nx6rqw 2025-10). Cannot override the score; server changes mid-game (YouTube-e0_5A4eUXAg comments). Editing hundreds of shots only on the iPhone, not the web (TT 2024-10). The workaround is downloading the raw video, trimming in Photos and re-importing (R-1nx6rqw). | Yes (2025-10 reports). |
| F5 | **Setup friction** | The alignment outline never turns green on a tripod; tips are hidden behind a tap; "set up higher on fence" advice is shown even in tripod mode (TT-without-watch 2025-12 to 2026-01). Audio-assisted alignment is "currently missing" (TT 2026-05) and called "a huge downgrade" (YouTube-5bMVDhqVHzo 2026-05). Without a watch, setup needs a second device with *internet on both* (CEO, TT 2024-05). Data use was about 2 GB per 90 min (TT 2024-04). Setup can take 5–10 min and eats court time (TT 2024-10). Wind, tarps and curtains move the stick (R-1jo1y4a, R-1fe5gzs, R-1fmch2f). | Yes. A motorized stick was promised and delayed (R-1luxj5w 2025-09). |
| F6 | **Lost or failed recordings** | "Saving video" for an hour, then gone (TT 2024-01, R-18xu4ph 2024-01; fix 11.4.1). Videos deleted after analysis trouble (TT 2022-11, still reported 2024-02). A 2-hour match recorded *zero* video with no error shown (TT 2026-05). Sessions stuck in "live" after a watch end (TT 2026-06). The iPhone SE plus battery pack crashes after about 1 h (R-1d2c359 2024-05). Import crashes on the SE 2 (TT 2025-01). | Partly. The 2026-09 release notes fix "recordings ending early" and crashes on camera interruptions (OBSERVED, App Store). |
| F7 | **Storage bloat and upload pain** | 80 GB undeletable after offloading (R-1o2ceg8, 135 points, 2025-10). 26 GB held "hostage" while an upload stalled for 12 h (R-1lij6k7). 272 GB on an old phone (2025-06). 20–50 GB of temp files; reinstall is the only fix (TT 2024-09 to 2024-11). Uploads stall at 95% for a day or for weeks (TT 2021-12, 2022-03). About 5 GB/h at HD (CEO 2023) and about 20 GB/h at 4K (R-1jbg6w0). The CEO says a fix was verified on Mac import (2025-10). | Partly. The 2026-09 release adds a low-storage warning only. |
| F8 | **Pricing, tiers and stealth gating** | Max at $29.99/mo for 4K and "better accuracy" was called disgusting by one user (TT 2024-02). Pro renewal CAD 209 to 250 (R-18x4rqb 2024-01). Basic stats briefly hidden in a "bug" (TT 2025-04). Shot-by-Shot restricted to Pro in Jan 2025 and noticed only in Jan 2026 (R-1q1e4i1). Plus-tier trimmed export capped at about 15 min (TT-tenniscut 2026-09). Upsell nags; a "Manage subscription" button led into a Max purchase (R-1o2lsmv; fixed 2025-11-23). Lower prices shown only to new accounts. Regional pricing complaints (Brazil about 3× Netflix, R-16lx6hr). | Yes (2026-01 and 2026-09 reports). |
| F9 | **Poor experience for viewers and non-subscribers** | Tagged friends get free-tier access only (TT 2025-02). Browser playback lags. An H.265-to-H.264 conversion backlog took up to 2 days (CEO, TT 2024-01). The website is weaker than the app and poor in Firefox (TT 2025-12). Link playback failed for an opponent (TT-problems-playback 2024-05). | Partly. |
| F10 | **Heat and battery** | Phones overheat over about 85°F; the fix was tying on an ice pack (R-13jkxgf). East Texas cameras shut down (TT-heat 2023). 4K drains a 12 Pro before a 2-hour match ends (R-1jbg6w0). A 13 Pro Max uses about 35% per 2 h indoors (TT 2022). An SE 3 uses about 50% per 1.5 h (TT 2024-05). An XS died at 1.5–2 h with no warning in 2019, and the CEO said battery alerts would come. | Partly. The 2026-09 notes improve "recording stability in high temperatures". |
| F11 | **Support, communication and roadmap opacity** | Slow support, AI-bot replies, only email (R-1lij6k7, R-1nx6rqw). Breaking changes without notice: 30 fps imports blocked (TT 2024-09); watchOS 11 required, so a Watch SE 1 stopped working mid-court (TT 2025-10). No public roadmap (TT 2024-04). Several users perceive the CEO as dismissive (R-1o2ceg8, 79 upvotes). | Yes (perception). |
| F12 | **Doubles weaknesses** | Partners mis-tagged; "Me/My partner" reverts (TT 2023-01, 2023-02). Team-combined stats only (TT 2022-01). AI scoring for doubles is "OK" but drifts (R-1jbg6w0). 1x zoom misses the near corners in doubles, so 0.8x ultra-wide is needed (TT 2024-07). Australian or Canadian doubles need hacks (TT 2021-11, R-150zrqa). | Yes. |
| F13 | **Rigid formats and session types** | No standalone tiebreaks or custom formats (YouTube comment 2025; R-1jbg6w0). Session type cannot be changed after starting (TT 2024-03). Watch offers only Rally and Match (TT 2024-06). 50 fps footage rejected for 50 Hz lighting (YouTube-3lca09Bxldk). The May 2026 Record tab redesign was called confusing (YouTube-5bMVDhqVHzo). | Yes. |
| F14 | **The camera angle is wrong for technique** | A behind-baseline fence view is "not the best view" for subtle mechanics (TT 2026-09 Robert F). Users want a side- or front-view technique mode (TT 2026-01, 2026-09; R-1jbg6w0 thread). Serve clips cut off the first half of the motion (TT 2024-12; the CEO promised extra time 2025-04). | Partly. The CEO promised technique feedback "in 2026" (R-1luxj5w). |

---

## 4. Ranked wishlist with evidence counts

Salience counts come from my keyword pass over 1,574 Talk Tennis posts, 1,131 Reddit posts and comments, and 215 YouTube comments, excluding SwingVision staff. Columns:
- **Authors**: distinct authors mentioning the topic.
- **Thr/Vid**: number of distinct threads or videos.
- **Rec**: authors posting in 2025 or later, plus all YouTube comments.
- **R-up**: total Reddit upvotes on matching comments.

The rank is my INFERRED judgement combining breadth, intensity, recency, independence across venues and whether the gap is open. Counts are approximate.

| Rank | Wish (what players ask for) | Authors | Thr/Vid | Rec | R-up | Key sources | JOVRA screen(s) |
|---|---|---|---|---|---|---|---|
| **1** | **Reliable automatic dead-time trimming.** Do not clip serves or points; adjustable lead-in (the existing "−2 s" setting); one full condensed-match file to download, on every paid tier; fix cuts by hand quickly. | 79 | 39 | 51 | 413 | R-1luxj5w, R-1j39izh, R-1g9pbyr, R-1j84e6g; TT-swingvision-alternative, TT-tenniscut, TT-auto-trim-2026, TT-SV-main (2024-12 −2 s tip, 2025-04 CEO serve padding); 8 indie trim apps | 7 Import/queue, 8 Library, 10 Smart replay |
| **2** | **Fair, transparent pricing.** A trim-only or "lite" tier; no retroactive gating; pay-per-use or one-time options; free core review; regional pricing; full export never paywalled by length. | 161 | 58 | 87 | 305 | R-1o2lsmv, R-1q1e4i1, R-1g9pbyr, R-18x4rqb, R-16lx6hr, R-1luxj5w (CEO: Strava-like tier coming); TT-SV-main 2024-02, TT-swingvision-alternative ($50/yr idea), TT-tenniscut; YouTube-oSOTVGK6ZRw ("price has doubled") | 19 Storage, 20 Settings, paywall copy |
| **3** | **Android (and Windows or web) support**, ideally with post-processing when real-time is not possible | 147 | 37 | 67 | 318 | R-18no2mj, R-1cfrs6d, R-1j39izh (84 comments), R-1jv96ai; TT-SV-main 2023–2025; YouTube-qnbGYxWiwvI (106-like top comment), oSOTVGK6ZRw, 3lca09Bxldk, 5bMVDhqVHzo; TT-android-alternative | Roadmap (brief: Android after iOS) |
| **4** | **Local-first ownership.** Record anywhere (native camera, GoPro, any phone); offline processing; optional cloud; export originals; no phantom storage; a visible storage dashboard and cleanup. | 127 (local) / 65 (storage) | 49 / 15 | 55 / 22 | 212 / 153 | R-1o2ceg8 (135 points), R-1lij6k7, R-16lx6hr (CEO "niche"), R-18x4rqb; TT-baseline-vision 2024-11 ("no desire for cloud storage"), TT-SV-main storage 2024; TT-auto-trim-2026 (local vs cloud debate) | 4 Setup ("Estimated space"), 7, 19 Cloud archive |
| **5** | **Correction tools that work.** Add, split, merge or delete a point or rally; override the score; edits persist; re-score from a point forward; frame-accurate bounce and hit editing; big-screen editing with mouse and keyboard. | 27 (+79 big-screen) | 14 | 12 | 47 | TT-SV-main 2024-03 (forzamr_b, mptennis), 2024-10 (partycamel2002); R-1nx6rqw, R-1luxj5w (20 upvotes); YouTube-e0_5A4eUXAg comments | 10 Smart replay and point correction |
| **6** | **Never lose a recording.** Continuous raw save; recovery after crash, low battery or heat; a clear "really recording" signal; warnings for heat, battery and storage *before* failure. | 22 (+66 heat/battery) | 8 | 7 | 12 / 112 | TT-SV-main 2024-01, 2026-05, 2026-06; R-18xu4ph, R-1d2c359, R-1me1onr; TT-current-problems (2022–2025); App Store notes 2026-09 | 5 Calibration checklist, 6 Live capture status |
| **7** | **Setup that works without extra devices.** Actionable framing feedback (tells you exactly what to move); works for tripod *and* fence; audio and haptic cues; remote framing from any phone, including Android, over local Wi-Fi without internet; under 2 minutes. | 41 | 20 | 17 | 62 | TT-without-watch (31 posts 2025-12 to 2026-09); R-1j84e6g ("finicky green contour"); R-1afjlsm, R-198bn63 (titles); YouTube-5bMVDhqVHzo (audio alignment removed); TT-SV-main 2024-01 (Android companion request) | 5 Court framing and calibration |
| **8** | **Honest metrics.** Label average vs peak speed; confidence per shot; flag outliers; account for near and far camera bias; line calls framed as "review the clip" aids, not verdicts. | 103 (speed) / 184 (line calls) | 29 / 49 | 51 / 95 | 238 / 558 | R-1lshufy, R-1dj4jm8, R-1u6ifr9, R-1fm8eut, R-17vtrs5; YouTube-fJdvIPkvd50, T-UhwqLmXiY; TT-zenniz, TT-swingvision.731741 (MPH) | 11 Shot map ("Needs review"), 12 Serve Lab ("Estimated") |
| **9** | **Sharing that respects viewers.** Links that play smoothly in any browser; opponents and partners get the full-quality copy *and* stats; export with a burned-in score overlay; YouTube-ready output; vertical clips; captions. | 117 | 51 | 48 | 204 | TT-current-problems 2025-02 (tagged users get free tier); TT-SV-main 2024-01 (browser lag); R-1ikooz9; TT-consent-2025 (manual captions); YouTube score-overlay questions | 9 Match overview, 10 Clip export |
| **10** | **Score overlay plus flexible formats**: standalone or 10-point match tiebreak, no-ad, best-of-1, Canadian or Australian doubles, practice sets, rotating groups | 37 | 16 | 15 | 47 | YouTube comments (6 "how do you add scores?"); YouTube-e0_5A4eUXAg (standalone tiebreak); R-1jbg6w0; TT-SV-main 2021-08, 2024-03; R-150zrqa | 4 Session setup ("Best of 3 · Advantage") |
| **11** | **Privacy and consent built in.** Pre-match consent prompt or record; private by default; mute or omit audio; blur bystanders or opponents; share-a-copy with the opponent; delete on request; a junior mode that follows ITF U18 and section rules | 52 | 17 | 29 | 149 | TT-consent-2025 (111 posts), TT-recording-practice 2022; R-1b2vdat (63-upvote "ask first"), R-154ej7m (audio), R-17vtrs5; ITF U18 PDF; USTA Eastern poster | 20 Settings and privacy; *new* consent sheet |
| **12** | **Technique mode.** Side or front camera presets; frame-by-frame stepping (app *and* web); scrubbing; slow-mo; side-by-side compare; keep the full serve motion. | 36 | 23 | 18 | 36 | TT-SV-main 2024-04/05 (frame stepping), 2024-12 (serve clip); TT-forth-back 2026-06; TT-without-watch 2026-09; R-1jbg6w0; YouTube-e0_5A4eUXAg (wants technique AI) | 13 Stroke Lab, 14 Compare |
| **13** | **Doubles done right.** Four-player identity that is easy to fix; per-player stats; wide-view guidance | 47 | 17 | 12 | 98 | TT-SV-main 2021–2024; R-1jbg6w0; Robby Lobby comment ("tagging players in doubles"); TT-baseline-vision 2026-02 | 4 Setup ("Doubles match"), 10 |
| **14** | **Coach workflow.** Send selected clips, not an hour of footage; coach annotation or voice; async remote review; coach-side Android or web access; pricing that suits coaches (no per-student hour traps) | 58 | 29 | 24 | 127 | TT-SV-main 2021-03 (export a few shots to coach), 2021-06 (hour caps for coaches), 2022-09 (CEO: coaches use Android); R-1d5zxrp, R-1gg1im2; TT-video-analysis-feedback; TT-spintip | 14 Compare (Draw / Voice note), 15 Coaching plan |
| **15** | **Actionable "so what" insights and long-term trends.** Lifetime stats; patterns vs specific opponents; causes of errors (shot type, height, position); serve+1 and return+1 | 57 | 35 | 31 | 74 | R-1j84e6g, R-1luxj5w (lifetime stats), R-1j39izh (dashboard request); TT-SV-main 2025-06 (serve+1); Tennisnerd 2021 ("turn data into insight") | 9, 15, 16 Progress |
| **16** | **Junior and parent support.** Multiple profiles; record while away on a dedicated device; live score to family and coach; recruiting reels; tournament-rule awareness | 60 | 38 | 21 | 88 | R-1d2c359, R-1fmch2f, R-1i600ly, R-1gg1im2; TT-camera-for-recording 2025-09; TT-SV-main 2022-05 (second profile), 2021-04 (scouts) | 2 Onboarding, 8 Library |
| **17** | **Two-phone or multi-camera merge** (both baselines, better calls, one merged session) | 12 | 5 | 8 | — | TT-current-problems 2025-02; TT-SV-main 2024-06, 2024-10; R-1j39izh; R-1swn2bn (two independent phones) | Later phase (INFERRED) |
| **18** | **Instant replay or delayed loop for practice** (review on a second device without taking the camera down) | 12 | 7 | 3 | 4 | R-1ur3me2 (2026-07); TT-dash-camera 2024-10; TT-video-app-android 2022-12; TT-SV-main 2024-10 (serve practice) | *New*: practice replay mode |
| **19** | **Integrations and capture options**: Strava, Apple Health, Garmin or Wear OS; 50 fps for 50 Hz lights; sensible 4K | 10 / 41 | 5 / 24 | 6 / 15 | 9 / 79 | TT-SV-main 2024-03, 2024-05 (Strava); R-1jbg6w0 (Garmin); YouTube-3lca09Bxldk (50 fps); R-1j84e6g (4K price) | 20 Settings |

**Observations on the ranking (INFERRED):**
- Ranks 1, 4, 5 and 6 together describe a product that **records reliably, trims reliably, lets you fix what the AI got wrong, and keeps your files yours**. That is nearly word-for-word JOVRA's brief outcome ("record safely, find the point, … keep ownership of the video"). The community evidence strongly supports that ordering over leading with AI line calls.
- Line-call accuracy is the most *discussed* topic, but much of the discussion is skeptical or etiquette-negative (§10). A JOVRA that leads with "review the clip" rather than "the app decides" avoids the trust trap.
- Instant replay (rank 18) is low-volume but appears independently in three venues. No incumbent serves it well, and it is cheap to build. It is a plausible differentiator.

---

## 5. How players actually record (hardware, positioning, power, workflow)

**Camera position (OBSERVED, consistent across venues):**
- Behind the baseline, centered or between the center hash and singles sideline, **as high as possible**. "Top of the fence", "10–15 ft" (R-1lt3wy1). The far service line should be visible *above* the net tape (R-1lt3wy1, R-1afjlsm). All four singles corners should be in frame "plus a few pixels" (CEO, TT 2024-06).
- Low angles produce bad tracking: "way too low" at 1.8 m on a tripod (R-1wwc0ll 2026-10). Tripods reach about 60–84 in and rarely get the "green" optimal badge (TT-without-watch).
- Zoom: 1x wide lens preferred. 0.9x or 0.8x ultra-wide (iPhone 13 Pro and later) if needed, and generally right for doubles. Clip-on wide lenses (Xenvo) are a last resort, soft at the edges and add baseline curvature that hurts accuracy (CEO, TT 2024-06/07; TT 2025-06; YouTube-suYO5y5ebTw comments). Ultra-wide makes the far court small and blurry (YouTube-PFqPOHCZ4to, suYO5y5ebTw comments).
- Indoors: curtain rails can be very high (David Lloyd clubs, R-1ikooz9, R-1jo1y4a). The stick shakes or rotates when balls hit the curtain (TT 2024-05, R-1fmch2f). Bubbles need tall tripods (CEO, TT 2025-04).
- Outdoors: windscreens and tarps push the stick; wind moves it (R-1fe5gzs, R-1jo1y4a). Face the camera toward a windscreen (R-1lt3wy1). European fences differ from US fences (CEO, R-1fe5gzs).
- Technique: side view on a tripod for stroke detail (R-1jbg6w0 replies, R-16lx6hr). Props such as a ball hopper or chair for short clips (TT-what-do-you-use 2021).

**Mounts named by players (OBSERVED):** SwingVision SwingStick (telescoping, rear knob, second hook, built-in sunshade since 2023; about $60 mount in 2022, marketed as a "$100" stick free with annual Pro, or $10–20 during a trial), QM-1 fence mount, Functional Tennis mount (a narrow section fits curtain wires), Essential Tennis mount, Faidue chain-link mount, Gorillapod or octopus legs, Joby clamps, super clamps, DIY options (PVC; selfie stick plus towel hook; command-strip hooks; bike bottle cage zip-tied to a tripod; $5 chain-link holder; $20 PVC build), 60–90 in tripods, carbon-fibre tripods, light stands.

**Devices (OBSERVED):** dedicated used iPhone SE 2 or 3 ($100–200, Wi-Fi only), iPhone 11–16 Pro (older ones reused), iPads (big battery, but tripod or ball risk and a weak lens), GoPro Hero 7–11, DJI Osmo Action, Akaso, Apeman and SJCAM action cams ($60–100, extra batteries; fisheye look; overheating), camcorders (Sony AX53, praised for zoom and no overheating), Sony A6400 or Nikon on a tripod. Pixel phones overheat at 60 fps. Samsung did not expose 60 fps to third-party apps (CEO, 2023).

**Power and heat kit (OBSERVED; a Las Vegas heavy user's list, R-1jbg6w0):** a 20,000 mAh multi-port USB-C power bank per phone, a strap to hold the pack on the stick, a MagSafe Peltier cooler on *cable* power (wireless charging adds heat), a thin white case, and the stick's sunshade. Others use a baby or mini umbrella (wind risk), a windshield-style shade, an ice pack tied to the phone, low-power mode, airplane mode, fixed low brightness, and an "automate Focus and Low Power mode" shortcut (YouTube-QMGvN_VFAJY, official).

**Storage and file sizes (OBSERVED):** about 5 GB/h at HD (CEO 2023); about 20 GB/h at 4K (R-1jbg6w0); a 2-hour 4K match can exceed 40 GB (CEO, TT 2024-03). Players buy 256 GB phones or offload to YouTube. Unverified YouTube accounts are limited to 15-minute uploads (TT 2022-01). One person live-streams to YouTube as storage (TT-camera-for-recording 2025-09).

**Workflows (OBSERVED):**
- Record in the native camera and import later to avoid losing a session (TT 2024-02, 2025-02; R-18xu4ph).
- Manual editing in LosslessCut, Handbrake, Premiere, DaVinci, InShot or CapCut takes 2–4 hours per match (R-1jbg6w0, R-1ur3me2, TT-consent-2025).
- Unlisted YouTube channels for sharing (TT-recording-practice 2022; TT-consent-2025).
- Shotgun or lav microphones for content creators (YouTube-XanPINBHVbE comments).

**INFERRED design implications:** a pre-flight checklist (height, four corners, lens, battery, heat, storage), a "dedicated camera phone" mode (Wi-Fi-only, no account needed on the camera device), a local-network remote viewfinder from any second phone, and stated battery and heat budgets per preset. JOVRA screens 4–6 already sketch "Estimated space" and a "Phone warming" status; the community evidence supports making these first-class.

---

## 6. How coaches use (or want to use) these tools

- **Async review of selected clips.** Players send short cut clips of their mistakes to a coach (YouTube-e0_5A4eUXAg comment). A coach reviews a 1.5-hour match in 20 minutes using filters (R-1jbg6w0). Players ask to export a few shots rather than an hour of ball-machine footage (TT 2021-03). (OBSERVED)
- **Goal setting from stats.** Meike Babel (former WTA pro) uses SwingVision stats for client goals (YouTube-l4i_VrZTang, affiliate). Some commenters push back on "SMART goals" jargon (OBSERVED).
- **Model-stroke overlays.** Tennis Australia gave registered coaches an app to overlay player clips on model strokes (TT 2021-10). John Yandell's advice is to film at 240 fps, show side-by-side with pro models, and reduce to 2–3 positions (TT 2021-10). (OBSERVED)
- **Paid video-analysis services** exist (Meike Babel, 2minutetennis, Intuitive Tennis; Full Court Tennis's "Brian Teacher" promo; Spintip at $4.99/mo or $59.99 Pro with coach video responses). Users praise asking a coach about specific points (TT-spintip 2025-06; R-1d5zxrp). (OBSERVED)
- **Coach tool landscape.** Coach's Eye was retired on 2022-03-31 (OBSERVED, coachway.io). Onform descends from Hudl Technique (OBSERVED, secondary). One user called Onform great for mechanics but did not need its communication features (TT 2024-08). Coach Adrian's unsponsored review (2026-02) calls it expensive, and a commenter says free iPhone slow-mo plus CapCut covers much of it (YouTube-Wv7VY2go7Qg). Kinovea (free, desktop) is praised but has a learning curve (TT 2022-12).
- **Pain points (OBSERVED):** monthly hour caps, which the CEO said exist partly to stop coaches using one subscription for many students (TT 2021-06). Per the CEO, "private coaches tend to use Android", which blocked the US coaching market (TT 2022-09). Coaches want to review serve-practice footage without taking the phone down (TT 2024-10) and need a mount for bubbles (TT 2025-01). High-school coaches chose Baseline Vision for team practice (TT 2024-10).
- **INFERRED:** a coach-share link (web, any OS, no account) carrying selected clips with Draw and Voice notes would serve the screen 14/15 flow and sidestep the Android-coach gap even before a native Android app.

---

## 7. Price sensitivity

**Price history players reference (OBSERVED; dates are when posted):**

| When | Price point | Source |
|---|---|---|
| 2019-09 | About $149/yr after discount; seen as "very expensive" | TT-SV-main |
| 2020-08/10 | $9.99–$10/mo considered worth it | TT-SV-main; TT-apple-watch-vs-tenniskeeper |
| 2021 | Basic 2 h/mo free · Semi-Pro 10 h/mo $59.99/yr · Pro 60 h/mo $119.99/yr; yearly plan only (the CEO said a monthly plan would be about $20–25) | SERP snippet (justuseapp); TT-SV-main 2021-06/08 |
| 2022-03 | Pro limit cut to 30 h/mo for new subscribers | TT-SV-main |
| 2022-11 | About €150/yr (EU) | TT-baseline-vision |
| 2023-09 | Free tier 2 h/mo at 480p (per a 2024-08 user screenshot) | R-16lx6hr, R-1dpwpy3 |
| 2024-01 | Max launched at $29.99/mo (4K, doubled hours); Pro about $15/mo; Pro yearly CAD 209 to 250 | TT-SV-main; R-18x4rqb |
| 2025-03 | $150 bundle (Pro year plus stick); stick about $99 alone or $10–20 during a trial | R-1jbg6w0, R-1j5mfqt |
| 2025-10 | $99/yr shown to new accounts only; web purchase cheaper than in-app | R-1o2lsmv |
| 2026-02 | New Free tier: 8 h/mo HD, watch challenges, audio line calls; Family Sharing for up to 5 | YouTube-3lca09Bxldk (official) |
| 2026-09/10 | US in-app: Plus $95.99/yr or $14.99/mo · Pro $179.99/yr or $24.99/mo · Max $299.99/yr or $39.99/mo. The listing description still says Pro is $179.99/yr or $14.99/mo (internal inconsistency). | App Store listing (OBSERVED 2026-10-07) |

**What players say they would pay or do (OBSERVED):**
- About $50/yr is "reasonable" for segmentation only, and $15/mo is "not worth it" (TT-swingvision-alternative 2026-02).
- "Under $10 a month I'd subscribe" (R-1j39izh). A tiered model was suggested: free, then about $60 one-time or $15/mo, then $200–300 hardware (R-1j39izh).
- $150–170/yr *if* line calls and tracking were accurate (TT 2024-10 one-year review).
- A heavy daily user (2,400+ sessions) says about $1/day is fine (R-1jbg6w0).
- A pay-once trim-only feature with no cloud or stats was requested repeatedly (R-1j84e6g, R-1luxj5w, R-1o2ceg8). The CEO rejected one-time purchase pricing (R-1luxj5w 2025-07) and hinted at an ad-supported model for Android and non-US markets (R-18x4rqb 2024-02).
- Pay-as-you-go: Velox Rally Cut charges only for auto-detection, with no subscription (TT 2026-06). RallyClip floated about $1 per 10 hours of segmentation (TT 2026-02).
- Anchors players compare against: a new racket and strings (R-16lx6hr, R-1o2lsmv), the Adobe suite (R-1g9pbyr), Netflix in Brazil (R-16lx6hr), iCloud (CEO), and Strava (CEO).

**Churn signals (OBSERVED):**
- "Haven't used it in 6 months" on a yearly plan (R-1dpwpy3).
- "Cool once, forgotten twice" (R-1ur3me2).
- Robert F's four reasons for not renewing: setup laziness, no watch, review time, wrong angle (TT 2026-09).
- A UX student's claim that 73 of 130 interviewed Seattle players deleted the app after the trial is **UNVERIFIED**; the poster gave no method (R-1luxj5w).
- The CEO claims renewal rates "approaching industry highs" (R-18x4rqb, 2024-01) and that 95% of revenue comes from individual players (R-1luxj5w).

**INFERRED:** a generous free core (record, manual mark, trim, play back, export) plus paid analysis or cloud fits the evidence better than tier-gated trimming. Any price change must never remove a feature a user already relies on. Gating is the strongest reputational trigger in this corpus.

---

## 8. Doubles and club play

- **Doubles is common but under-served** (OBSERVED; see F12): wide framing (0.8x), partner mis-tagging, team-only stats, drifting AI scoring. Rotating groups (8 players over 2 courts) need one-tap new sessions from the wrist (TT 2022-05). Players playing 2-on-1 or Australian or Canadian doubles hacked profiles to make sharing work (TT 2021-11, R-150zrqa).
- **Club installs are mostly unused or broken.** PlaySight kiosks were "broken for years" (R-1dj4jm8). "Almost no one uses" a club's PlaySight (R-1mdx9db). Club owners report these systems are used for recording, live-streaming and cropping, not for the AI features (R-1dj4jm8). A club chair wants a permanent built-in system that is cheaper than today's options (TT 2024-02). Zenniz has no public pricing, which users read as expensive (TT-zenniz 2026-05). Baseline Vision costs about $1,500–2,000. One email floated removing line detection from single-camera units, which drew backlash (TT-baseline-vision 2025-07). In/Out costs $549–1,245 for club tiers but some found it unreliable (TT-baseline-vision 2023). (OBSERVED; prices as stated by users)
- **League and tournament context.** SoCal USTA paid SwingVision for ELC at events; a 14-court outdoor L3 was run by 2 staff (CEO, TT 2025-04; R-1u6ifr9). A Reddit user says their section instead got a USTA National grant for PlayReplay (UNVERIFIED). ITF ELC certification is not yet achieved (CEO, R-1u6ifr9 2026-06). Community understanding is that USTA league rules do not let an app overrule calls (TT-challenge-line-calls 2024-07; consensus, not a cited rule). The USTA "Friend at Court" excerpt on the Eastern poster bars devices capable of receiving communication during play without referee permission (OBSERVED). That may constrain on-watch challenges in sanctioned matches (INFERRED).
- **Two-phone setups** (one per baseline) are used by enthusiasts for clearer calls on both sides, but the sessions do not merge (R-1jbg6w0, R-1swn2bn, TT-current-problems 2025-02).

---

## 9. Juniors and parents

- **Parents are a real recording segment (OBSERVED).** GoPro on a fence mount for a kid's junior tournaments (TT-camera-for-recording 2025-09). Recording kids while the parent drops them off and leaves; wanting a camera that does not tie up the parent's phone; dedicated used iPhone plus battery pack plus a cardboard shade (R-1d2c359). Keeping the stick from rotating on curtains (R-1fmch2f). A second profile for a daughter (TT 2022-05). A U14 parent wants one tool for live score updates to family *and* notes for the coach (R-1i600ly). Recording a 17-year-old (UTR 6.x) for free coaching feedback because lessons are unaffordable (R-1gg1im2).
- **Juniors drive adoption (OBSERVED, vendor/user claims).** The CEO says nearly all college and junior players use iOS (TT 2022-09). A Reddit user reports one or two phones on the back fence of most courts at L3/L4 junior tournaments (R-1luxj5w, 2025-07; UNVERIFIED as a measurement). Highlight reels go to scouts and colleges (TT 2021-04). Parents want line-call help in junior events (TT 2025-02, TT-automated-line-calling 2025-08).
- **Rules are strict (OBSERVED, primary):**
  - The ITF U18 process (Aug 2025) requires written consent from the recording player's parent *and* the opponent's parent on a form endorsed by the Tournament Supervisor. The opponent can withdraw at any time, after which recording stops and is deleted. The full recording must be given to the opponent. It cannot be used to dispute officiating. It must not be posted except per regulations, must be stored securely, and must be deleted when no longer needed.
  - USTA Eastern prohibits videotaping and photography at all junior sanctioned events; contact the section for recruiting recordings.
  - Some tournaments a parent attends "specifically prohibit recording" (R-1b2vdat).
- **INFERRED:** a junior or tournament mode should show a rules reminder, capture a consent record, default to private, generate an opponent-copy link, and support "delete on withdrawal". This also helps JOVRA's App Store review posture around minors.

---

## 10. Privacy and etiquette around recording opponents

- **The norm is to ask first, and ask again before posting (OBSERVED).** "If you film, ask; if you upload, definitely ask" (63 upvotes, R-1b2vdat). Players offer to share the raw video or link afterwards because opponents appear in half the footage (TT-recording-practice 2022, R-17vtrs5). Many recorders keep footage unlisted and share it only with people on court (TT 2022, R-1b2vdat). Some people will always say no (TT-consent-2025, esgee48). Others feel pressured when asked in person; one suggestion is to ask by email beforehand (TT-consent-2025, sureshs).
- **Withdrawn consent is a live scenario (OBSERVED).** In a 111-post Talk Tennis thread (Feb–Jul 2025), an opponent who misbehaved later emailed to "rescind consent". Most replies said not to post it, and lawyers disagreed on the legal position. One user wished recorders would at least ask even when the law does not require it. **Legal opinions in that thread are UNVERIFIED and jurisdiction-dependent** (US public courts vs private clubs; GDPR regions; Germany and Japan were cited as stricter, R-1b2vdat).
- **Audio privacy (OBSERVED).** A player wanted to record without capturing personal conversations. Disabling the microphone permission silently resulted in *no recording* (R-154ej7m, 2023). Background audio from a nearby concert ended up in clips.
- **Visibility settings.** SwingVision offers public, private or friends-only sessions, and public sessions can appear in feeds (R-1b2vdat). Users noted the auto-cloud backup risk (OBSERVED).
- **Mid-match replay etiquette (OBSERVED).** In a 61-comment thread (R-17vtrs5), most rec players called stopping for watch review rude, a pace killer, or an attack on character. The replay is one-sided: only the device owner has it. Some would walk off. A minority use it with friends who opted in, 0–2 times a match. Players also flag stalling abuse and suggest challenge limits. A doubles group happily used the owner's watch as an agreed referee (R-17vtrs5). Overruling a stranger's call in doubles drew pushback (R-1fm8eut).
- **INFERRED design implications for JOVRA:**
  1. A consent step in session setup with options to "ask / note who agreed / share copy with".
  2. Audio off by default for match sessions, with a working mute that never blocks video capture.
  3. Private by default; share links scoped per person.
  4. An optional face-blur export.
  5. Line-call review framed as a mutually agreed mode that shows the clip to both sides (for example a second-device viewer) rather than the app's verdict.
  6. A visible indicator on the camera phone that recording is happening.

  JOVRA's settings screen (20) already has "Microphone · Optional · Off" and "Training data sharing · Off", which matches this evidence.

---

## 11. Implications for JOVRA's 20 planned screens (INFERRED, evidence-linked)

| JOVRA screen | Community evidence it should answer | Suggested emphasis |
|---|---|---|
| 4 Record setup | Format rigidity (F13), doubles framing, storage estimate, consent norm | Custom formats (tiebreak-only, no-ad, Canadian doubles), a consent row, a "dedicated camera phone" toggle, battery and heat budget per preset |
| 5 Court framing | Green-never-happens frustration, Watch dependency, audio alignment removed | Specific move-the-camera instructions; works on tripod and fence; haptic and audio cues; remote viewfinder from any phone over local Wi-Fi |
| 6 Live recording | Lost recordings, silent failures, heat, mic privacy | Persistent "video saving on this iPhone" heartbeat; heat, battery and storage early warnings; "Mark point" for manual scoring (players dislike constant watch scoring, TT 2025-12) |
| 7 Import and queue | Native-camera-then-import workflow, GoPro or Android footage, 30/50 fps imports | Accept any common format and frame rate; resumable; "you can leave this screen" (already in screens.json) |
| 8 Session library | Storage bloat, offload confusion | Per-session size, an "on device / backed up / cleaned" state, one-tap cleanup that actually frees space |
| 9 Match overview | Sharing to opponents; "so what" insights | Opponent-copy share; error-cause insight with evidence counts |
| 10 Smart replay and point correction | Correction pain (F4), trim lead-in, filters | Add, split, merge and delete points; score override that persists; adjustable lead-in; filters (second-serve returns, 5-shot points) |
| 11 Shot map / 12 Serve Lab | Speed and in/out distrust | "Estimated" labels, confidence, near and far bias note, outlier flag, tap to see the clip (screens.json already uses "Needs review" and "Estimated") |
| 13 Stroke Lab / 14 Compare | Side-view technique wish, frame stepping, coach sharing | Side- or front-view preset, frame stepper, scrubbing, Draw and Voice; coach link |
| 15 Coaching plan / 16 Progress | Lifetime stats, trends over absolutes, AI-coach skepticism | Evidence-linked drills (already in the brief); trends with confidence; no generic "continental grip" advice |
| 19 Storage and backup | Local-first demand; cloud upload pain | Local originals by default; Wi-Fi-only resumable Drive uploads; a "verified backed up" state (already in the brief) |
| 20 Settings and privacy | Audio privacy, training-data consent, deletion | Mic off; training-data opt-in; export everything; delete account and data |
| **Gaps (new surfaces)** | Ranks 11, 17 and 18 | Consent and opponent-share sheet; practice instant-replay loop; doubles player-tagging sheet; format editor |

---

## 12. Contrary evidence and open tensions

- **Many users are happy.** Examples: "literally the best mobile application I've ever used" (a former Android user, R-1o2ceg8), "great tool, 99% of the time it does what it promises" (YouTube-T-UhwqLmXiY comment, 32 likes), "insane value" (R-1bzzn9v), and the 2,400-session ambassador (R-1jbg6w0). Negative posts are over-represented (OBSERVED: a commenter made this point; INFERRED: a general forum effect).
- **Real-time vs post-processing.** The CEO cites large-sample retention data showing that non-real-time users churn and that a Mac import path produced 10× worse retention (TT 2024-01, R-1cfrs6d). Forum users insist post-processing is fine for them (R-1j39izh; TT 2024-12, 2025-06). Both can be true: the forum is a self-selected minority (a user made this point, TT 2025-06 chic). INFERRED: JOVRA should give instant playback and trimming right after recording, and treat deeper analysis as asynchronous. That honours both camps.
- **Accuracy disputes hinge on setup.** The CEO attributes most errors to suboptimal setup, lenses or non-standard courts. Users with "optimal" setups still report errors (TT 2024-06). Without a labelled benchmark neither side is verified (UNVERIFIED either way). JOVRA's brief already requires per-capability feasibility gates.
- **SwingVision is actively shipping.** Releases include the Feb 2026 free-tier expansion, the May 2026 Record tab and background exports, and the Sept 2026 heat, storage and watch-connection fixes (OBSERVED). Older complaints may be resolved. Re-verify before marketing claims.

---

## Sources

All accessed 2026-10-07. Talk Tennis URLs follow `https://tt.tennis-warehouse.com/index.php?threads/<slug>/`. Reddit content was retrieved through the Arctic Shift archive API (`https://arctic-shift.photon-reddit.com/api/...`) because reddit.com blocked direct fetches; canonical Reddit URLs are listed.

**Primary / vendor**
- https://apps.apple.com/us/app/swingvision-tennis-pickleball/id989461317 — In-app prices (Plus/Pro/Max), privacy label, description price text.
- https://itunes.apple.com/lookup?id=989461317&country=us — v11.9.67 (2026-09-27): release notes on high-temperature stability, low-storage warning and watch connection; 4.71 rating from 4,928 ratings; minimum iOS 18.0; description price.
- https://itunes.apple.com/lookup?id=1505604446&country=us — SevenSix v4.0.2 (2026-10-07), 4.19 from 68 ratings.
- https://itunes.apple.com/lookup?id=1490334045&country=us — Onform v4.7.3, 4.79 from 8,666 ratings.
- https://itunes.apple.com/search?term=tennis%20cut&entity=software&country=us (and related searches) — TennisCut (side-of-court tripod, on-device AI), PureTennis, RallySense, Tennis Shots, Smashpoint.
- https://www.itftennis.com/media/15017/itf-performance-analysis-video-u18-august-2025.pdf — ITF U18 recording consent, opponent-copy, withdraw-and-delete and no-dispute rules.
- https://usta725.americaneagle.com/assets/636/15/Electronic_Device_-_Video_Poster_Edited.pdf — USTA Eastern junior video ban; Friend at Court device rule excerpt (undated poster).

**Talk Tennis threads (TT-…)**
- swing-vision-ai-line-calls-and-analysis.653818 (TT-SV-main) — 1,119 posts 2019-09 to 2026-07: CEO statements (Android, Windows, real-time-only, A12 cutoff, 4K/Max rationale, ELC events, storage), user complaints and requests cited throughout §2–§9.
- swingvision-alternative.792377 — Trim-only demand, RallyClip, $50/yr willingness to pay, TennisCut quality issues (2025-10 to 2026-06).
- tenniscut-recording-app-alternative-to-swingvision.803757 — Trimmed export moved to a higher tier; Plus capped at about 15 min (2026-09).
- imagine-theres-an-app-that-auto-trims-your-match-videos-how-should-it-work.794873 (TT-auto-trim-2026) — Local vs cloud, website vs app, deliverables, willingness to pay; RallyFlow (2026-01/02).
- swingvision-alternative-especially-for-android.800652 (TT-android-alternative) — Velox Rally Cut: offline, manual marking, scoreboard, no subscription (2026-06).
- swingvision-without-an-apple-watch.794353 (TT-without-watch) — Alignment frustration, tripod vs stick, reasons for not renewing (2025-12 to 2026-09).
- zenniz-competitor-to-swingvision.799101 (TT-zenniz) — Serve-speed distrust, lighting and camera height (2026-05).
- camera-for-recording-tennis.791199 (TT-camera-for-recording) — Action cams, used iPhone, GoPro for junior tournaments (2025-09).
- can-someone-rescind-consent-to-a-match-being-filmed-after-giving-the-ok-to-be-filmed.781658 (TT-consent-2025) — Consent norms; editing takes 2.5–3 h per match (2025).
- recording-practice-matches.722181 (TT-recording-practice) — Etiquette, battery and overheating, mounts (2022).
- baseline-vision.737423 (TT-baseline-vision) — Hardware alternatives, prices, CEO cloud-cost rationale, local-storage requests (2022–2026).
- swing-vision-great-app-appalling-customer-support.772610 — Finicky UI, basic stats paywalled (2024–2025).
- swingvision-current-problems-with-videos.739133 (TT-current-problems) — Lost videos, tagged-user access, dual-camera wish (2022–2025).
- using-swingvision-to-challenge-line-calls-is-it-allowed.772753 (TT-challenge-line-calls) — League use not allowed (community understanding) (2024-07).
- electronic-line-calling-retail-version.787168 — Two-phone idea; In/Out; Baseline price (2025).
- if-you-had-to-guess-will-we-get-automated-line-calling-in-rec-leagues-tournaments-any-time-soon.790266 (TT-automated-line-calling) — Junior line-call problems; cost (2025).
- camera-that-does-well-in-the-heat.752627 (TT-heat) — Overheating fixes (2023).
- budget-camera-for-dedicated-court-recording.738223 — Action cams vs camcorders; wide-angle blur (2022).
- what-do-you-use-to-record-yourself.710708 (TT-what-do-you-use) — Phones, tripods, action cams, YouTube storage (2021).
- swingvision-users.699003 — Early sentiment: editing yes, speed no (2021–2023).
- swingvision.731741 — MPH average-speed explanation (2022–2025).
- has-anyone-tried-spintip-app.786863 (TT-spintip) — Coach-feedback app pricing ($4.99/mo, $59.99) (2025-06).
- software-for-video-recording-in-dash-camera-style.777238 (TT-dash-camera) — Delayed-replay loop request (2024-10).
- video-app-for-sport-analysis-android.741317 (TT-video-app-android) — Android slow-mo, looping, Kinovea (2022-12).
- any-free-video-analysis-apps.773458 — Onform praised for mechanics; wants a free equivalent (2024-08).
- video-analysis-feedback-how-many-of-you-do-this.711723 (TT-video-analysis-feedback) — Coach practices; Tennis Australia app; 240 fps advice (2021).
- forth-back-display-of-tennis-stroke-videos.800932 (TT-forth-back) — Scrubbing and frame review wish (2026-06).
- will-swingvision-still-work-with-an-android.760414; problems-with-swing-vision-video-playback.768422 (TT-problems-playback); swingvision-support.762029; where-is-the-section-on-swing-vision.744943 — Android import, viewer playback, support access.
- nerd-using-swingvision-ai-to-evaluate-racquets.694616; match-charting-software-and-apps.697769; what-is-the-best-way-to-estimate-service-speed.696888; how-fast-to-most-rec-players-serve.786350; line-calling-i-dread-it.699688; apple-watch-swingvision-app-vs-tenniskeeper-app.682159; practice-match-with-usual-hitting-partner-w-and-w-o-swingvision-ai-looking-for-most-important-areas-to-work-on.718348; ai-auto-trimming-non-playing-time-from-videos.710543; recording and speed context used in salience counts.

**Reddit r/10s (R-…)**, canonical `https://www.reddit.com/r/10s/comments/<id>/`
- 1luxj5w (2025-07) — Dead-time trimming as the primary use (85 upvotes); CEO: Strava-like tier, lite tier, motorized stick, technique feedback in 2026, Android 2026 hopes, 95% of revenue from individuals.
- 1j39izh (2025-03) — Android-clone advice thread (84 comments): ranked must-haves, real-time not needed, hardware rejected.
- 1o2ceg8 (2025-10) — 80 GB phantom storage (135 points); alternatives (PureTennis, TennisCut).
- 1o2lsmv (2025-10) — Subscription upsell bug (fixed 2025-11-23); new-account pricing; Semi Pro tier mention.
- 1q1e4i1 (2026-01) — Shot-by-Shot gating backlash; CEO explanation.
- 1lij6k7 (2025-06) — 26 GB storage hostage; support complaints.
- 1jbg6w0 (2025-03) — Worth it? Heavy-user love/wish list and heat/power kit.
- 1j84e6g (2025-03) — Love/wish thread: precision, 4K price, wall training, upload time, setup, pay-once trim.
- 1ur3me2 (2026-07) — Wished-for apps: near-real-time segment replay; editing took 3–4 h per match.
- 1g9pbyr (2024-10) — Cost vs features; trimming is "the real magic".
- 18x4rqb (2024-01) — Max 4K price; CAD renewal increase; CEO on storage costs and ads.
- 16lx6hr (2023-09) — Cheaper alternatives; CEO on hour caps, 5 GB/h, one-time fees, regional pricing.
- 1dpwpy3 (2024-06) — Worth it? Forgetting to use it; free tier 2 h at 480p.
- 1u6ifr9 (2026-06) — Line calls in matches; CEO on certification and "97% within 10 cm" confusion; iPhone 14+ for ELC.
- 1lshufy (2025-07) — Serve speed disbelief (82 points).
- 1dj4jm8 (2024-06) — Club AI systems mostly used for recording; 140 mph serve jokes; PlaySight kiosks broken.
- 17vtrs5 (2023-11) — Etiquette of video replay to contest calls (61 comments).
- 1b2vdat (2024-02) — Recording and uploading without consent.
- 154ej7m (2023-07) — Audio privacy; mic off broke recording.
- 1fm8eut (2024-09) — Doubles line-call overrule with strangers.
- 1swn2bn (2026-04) — Two-phone ELC experience.
- 1bzzn9v, 18xu4ph, 1jo1y4a, 1j5mfqt, 13jkxgf, 1lt3wy1, 1fe5gzs, 1fmch2f, 1d2c359, 1wwc0ll, 1iidzdl — Recording hardware, mounts, positioning, heat, curtains, kids' matches.
- 1afjlsm (2024-01, "Need SwingVision set up tips"), 198bn63 (2024-01, "Tips on aligning phone"), 1me1onr (2025-07, "corrupted recording?"), 197k042 (2024-01, "I've Been Humbled - Video Review") — Setup and alignment struggles, lost or corrupted video, the value of seeing yourself. Comment trees were fetched only for 197k042; the other three are post title and body only.
- 1i600ly, 1gg1im2, 1d5zxrp — Junior parent workflow; coaching feedback demand.
- 150zrqa, 1nx6rqw, 1kbdlql, 1ikooz9, 1oims0n, 1txji0e, 1mdx9db, 1jv96ai, 18no2mj, 1cfrs6d — Formats, correction bugs, free tier, rating-from-video idea, rec ELC outlook, Android app attempts, CEO Android explanations.
- r/tennis 1kw6jy6, 1ot85oq (2025) — Low-engagement "is it worth it" and "build a competitor" posts (context only).

**YouTube (YouTube-…)**, `https://www.youtube.com/watch?v=<id>`
- e0_5A4eUXAg — The Tennis Mentor, "Is The SwingVision App Worth It?" (2025-09-20, about 39K views, affiliate): description and comments (soft-critique callout, scoring override, standalone tiebreaks, wind on the stick, technique AI wish).
- T-UhwqLmXiY — Coach Adrian, unsponsored review (2024-12-13, about 25K views): comments on 134 mph serves, mixed court lines, bugs and support delays.
- fJdvIPkvd50 — Robby Lobby, SwingVision vs Pocket Radar (2025-06-04): 50 serves; about 6% error in-bounds, about 42% on net serves.
- 9pIStuFs_Mo — Robby Lobby, mount setup tips (2025-02-15): asking permission, sun and wind orientation, doubles tagging complaint.
- l4i_VrZTang — Meike Babel, product review (2024-07-11, affiliate): coach goal-setting use; Android waits.
- 3lca09Bxldk — SwingVision official, Free tier (8 h HD) and Family Sharing (2026-02-20): comments on 50 fps and Android.
- 5bMVDhqVHzo — SwingVision official, May 2026 update (Record tab, background exports, target practice): audio-alignment removal complaint.
- qnbGYxWiwvI — SwingVision official, Android explainer (2024-04-22): import-first Android requests (28 likes), e-waste objection.
- oSOTVGK6ZRw — SwingVision official, FAQs (2025-03-19): Android demand; "price has doubled"; web-review tier idea.
- 9UPlvHKQTv0 — Gladiators Tribe (2025-08-17, affiliate): stats distrust, clay issues.
- Avt2UkR07eA, 64qS763dWy4 — Free-version and beginner reviews (affiliate).
- XanPINBHVbE — Essential Tennis, "You're recording your tennis matches WRONG" (2021): framing, angle, mic; score-overlay questions.
- suYO5y5ebTw — Tennis Files, how to record (2022): devices and mounts; wide-angle complaints.
- -ViGP_L9ZRw, PFqPOHCZ4to, 7J1sEIIYfMc — DIY mounts, overheating umbrella tip, repeated "how do I add scores?" questions.
- Wv7VY2go7Qg — Coach Adrian, Onform unsponsored review (2026-02-11): "expensive"; Coach's Eye nostalgia.
- -sQ_XP1HxXs, QMGvN_VFAJY — SwingVision official setup video (about 142K views) and Low-Power/Focus automation (metadata only).

**Blogs, press and secondary**
- https://www.tennisnerd.net/tennis-tools/swingvision-review-and-interview/25702 — 2021-10-30 review: dead-time trimming as core value; average-speed caveat; 2 h free and $149.99/yr Pro at the time.
- https://prod.tennis.com/news/articles/swingvision-delivers-pro-level-insights-for-recreational-players — 2022-10-23 review: $60 mount, watch-assisted setup, speed about 20% below peak, slice and flat misclassification, shared highlights driving acquisition.
- https://justuseapp.com/en/app/989461317/swingvision-a-i-tennis-app/reviews — (search snippet) 2021-era tier prices (Basic/Semi-Pro/Pro); third-party aggregator.
- https://coachway.io/articles/coachs-eye-alternatives/ — Coach's Eye retirement date (2022-03-31); Hudl Technique and OnForm lineage (secondary).
- https://alternativeto.net/software/swingvision/?p=2 and https://www.toolify.ai/alternative/swingvision — Alternative lists (Kinovea, PB Vision, Baseline Vision, Wingfield) (secondary, context only).
