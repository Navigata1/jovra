# JOVRA Studio: premium pricing, multi-camera landscape and unit economics

Research date: 2026-10-07. Scope: price anchors from multi-camera, auto-production and AI-editing products; refreshed
official list prices for the proposed Studio stack; a per-film cost model for 1, 3 and 6 angles × 60 minutes; two to
three pricing structures with margins; and the free/paid line that keeps core JOVRA free.

Labels follow the repository's research convention. **OBSERVED** means read from a primary page on 2026-10-07 (official
pricing page, help centre, rendered storefront or official docs). **INFERRED** means derived by this document's
arithmetic or reasoning. **UNVERIFIED** means a secondary source, a search-result summary or an undated claim. Prices
are USD list prices excluding tax unless stated otherwise.

Nothing here is a decision. No service was provisioned or signed up for, no account was created and no money was
spent. ADR-0013 (no paywall in v1, own-your-footage contract) still governs; paid cloud production needs its own ADR.
Every dollar in sections 4–5 is an estimate to be replaced by measured benchmark jobs (section 8) before retail pricing.

---

## 0. Findings in brief

1. **Multi-phone capture is already sold to consumers, but not as story films.** Veo Go pairs two or three iPhones on
   one rig and stitches a panoramic soccer view in the cloud for $40/month (OBSERVED). SwingVision supports one or two
   recording phones, one behind each baseline, for tracking and line calls (OBSERVED, ITF PAT-25-037). Smashpoint added
   a second iPhone at the fence in September 2026 (OBSERVED in prior research). No product found turns 1–6 consumer
   phones around a tennis court into narrative films in distinct styles (INFERRED from this search; not exhaustive).
2. **Price bands are clear.** Phone-only tennis analytics sell for $40–$300/year (SwingVision Plus/Pro/Max $95.99,
   $179.99, $299.99). Hardware auto-production costs $1,149–$1,599 for the camera plus $999–$1,699/year (Veo, Pixellot).
   Per-use analysis sells at $1.99 (SevenSix) to about $5–$12 per processed hour (PB Vision). Human highlight edits cost
   $200–$800 (UNVERIFIED vendor pages).
3. **Claude Opus 5.5 (`claude-opus-5-5`) lists at $4 input / $20 output per million tokens**, with cache reads at
   $0.20, 5-minute cache writes at $5, and the Batch API at $2 / $10 (OBSERVED, Anthropic pricing page). The API takes
   images, not video files. Frames must be sampled, and a 1280×720 frame costs 1,196 visual tokens (OBSERVED formula).
4. **In the recommended design, the planner is the largest per-film cost, not storage.** The design target is
   **$1.03–$2.32 per film** across 1–6 angles (INFERRED). About $1 of that is the planner. A worst-case envelope reaches
   **$2.99–$9.40** if originals are normalized in the cloud, frames are sent at 720p and plans need repair passes.
   Seven days of R2 staging for six 60-minute angles costs $0.08 (OBSERVED rate, INFERRED arithmetic).
5. **Upload time is the real constraint at six angles.** 21.6 GB at 20 Mbps takes at least 144 minutes. Device-made
   720p proxies plus full-resolution keeper windows cut that to about 54 minutes (INFERRED).
6. **Recommended structure: Studio Credits as the single ledger.** A credit costs about $2. The preflight quote, the
   cap and the idempotent reservation are all denominated in credits. Each credit carries an internal cost budget of
   about $0.80–$1.00, so margin holds even when a job runs to its cap: at least 24% on the smallest film with a
   $0.80 budget. At the design-target cost, contribution is **36–58%** after the 15% App Store fee, a 10%
   support/refund reserve and a fixed-cost share (INFERRED). Apple requires that purchased
   credits never expire (OBSERVED, guideline 3.1.1).
7. **Free/paid line: anything that runs on the phone stays free; anything that costs JOVRA money per use is paid and
   quoted.** On-device multi-angle replay and template films rendered with AVFoundation are free. Cloud upload, the
   model-planned "JOVRA engine" story, cloud render, hosted links and later measured cloud vision are paid (section 6).

---

## 1. Method and limits

- Primary pages were fetched or rendered in a browser on 2026-10-07: Veo, SwingVision, PB Vision and OpusClip
  pricing were JavaScript-rendered and read from the live DOM. Prior JOVRA research (`../competitive-analysis.md`,
  `../raw/landscape.md`, `../raw/swingvision.md`) supplied App Store IAP prices checked the same day. Those are cited
  rather than re-fetched.
- Anthropic model IDs and prices come from the `claude-api` skill (model table cached 2026-09-25) cross-checked
  against the live pricing page fetched 2026-10-07. Where they differ, the live page wins (section 3.5).
- The cost model is a script-checked spreadsheet of assumptions, not a benchmark. The script lives in the session
  scratchpad, not in the repository, and every input is listed in section 4.1.
- Not researched: OpenAI/"Astra" pricing (the founder's preference label; map it to a real model ID and price only at
  activation), Google Play billing fees, taxes, and EU/UK storefront rules.

---

## 2. Competitive landscape

### 2.1 Multi-camera and auto-production sports video

| Product | What it does | Multi-camera model | Hardware | Subscription | Label |
|---|---|---|---|---|---|
| **Veo Cam 3** | AI follow-cam soccer and multi-sport recording; panoramic + interactive view; event detection; Veo Analytics 2 add-on for football | One dual-lens panoramic camera | Cam 3 **$1,299**; Cam 3 5G **$1,599** | Starter **$149/mo** or **$999/yr** (10 rec h); Team **$215/mo** or **$1,399/yr** (20 rec h); Club **$255/mo** or **$1,699/yr** (card says "Unlimited rec hrs", comparison table says 200 h; the page contradicts itself) | OBSERVED (rendered en-us page, excl. taxes) |
| **Veo Go** | Phone-based Veo: "only need two iPhones"; a three-phone mode adds a controller; "AI merges the footage into a panoramic pitch view" | 2 camera phones side by side on one rig at the centre line, stitched, not separate angles | Rig and tripod free on yearly plans; tripod $39 | **$40/mo**, 20 rec h, 15 users | OBSERVED |
| **Pixellot Air NXT** | Portable AI tracking camera, Pixellot You app, VidSwap breakdowns | One panoramic camera | **$1,149** at one retailer; search snippets show $849–$999 | Team and Club plans exist, but prices render blank on `you.pixellot.tv/plans` | OBSERVED (retailer), subscription UNVERIFIED |
| **Trace PlayerFocus** | Per-player youth soccer highlights from a Trace camera | One camera system | n/a here | Basic **$25/mo or $180/yr** (last 5 games); Pro **$40/mo or $300/yr** (all games, unlimited downloads, edit highlights) | OBSERVED (Trace support page); a search snippet's "$35/mo" is superseded |
| **Hudl Assist** | Human-tagged game breakdowns | n/a | n/a | Football: **$250–$1,700 per team per season** across Standard/Express and Assist/Assist+ | OBSERVED |
| **Hudl Focus** | Fixed smart camera for schools | Fixed install | "Contact us" | Bundled into club packages | OBSERVED (no public price) |
| **Hudl Balltime** (volleyball AI) | Downtime removal, AI vertical highlight reels, "AI-generated Recruiting Videos" | Single upload | n/a | Player **$20/mo** (15 h/mo); Recruiting **$25/mo billed $299/yr** (200 h/yr); Team on request | OBSERVED |
| **Mevo (Logitech)** | Live multi-camera switching and streaming | Several Mevo cameras plus phones (Mevo Go) into Mevo Studio | Mevo Core body **$999** | Mevo Pro **$19/mo or $149/yr** | Pro OBSERVED; Core price UNVERIFIED (search summary of a 2024 launch) |
| **PlaySight SmartCourt** | Club smart-court recording, multi-angle replay, streaming | Fixed multi-camera install | ≈$12.5K + $500/mo per secondary source | ≈$10 per match (one 2026 user review) | UNVERIFIED (from `../raw/landscape.md`) |
| **Spiideo** | Venue cameras and streaming | Fixed install | Sales-led | "from ≈$3,125/yr" | UNVERIFIED (secondary) |
| **XbotGo** | Phone gimbal or standalone camera with AI tracking | One device | Chameleon ≈$300; Falcon $699 | None per a vendor-blog summary; prior research saw "$15/match" IAP | UNVERIFIED, contradictory |

### 2.2 Premium tennis analytics

| Product | Premium price | Multi-camera | Notes | Label |
|---|---|---|---|---|
| **SwingVision** | Free (8 h/mo, ads, 7-day access); Plus **$14.99/mo · $95.99/yr** (16 h); Pro **$24.99/mo · $179.99/yr** (30 h); Max **$39.99/mo · $299.99/yr** (60 h, family of 5, 4K). Web offer: Pro first year **$143.99** ($11.99/mo), Max **$22.99/mo** | **Yes, one or two recording phones, one behind each baseline** (ITF PAT-25-037). A second phone can also act as remote. The compare page lists no tier gate for two devices (gating UNVERIFIED) | Tracking, line calls, trimming, cloud storage on paid tiers. Not a story-film product | OBSERVED (compare page rendered 2026-10-07; IAP from prior research) |
| **Smashpoint** | Pro $39.99/yr; Elite $149/yr | Second iPhone at the fence (v3.4, Sep 2026) | Charting app with new 4K60 critical-point replays | OBSERVED (prior research) |
| **Wingfield** | App Pro $9.99/mo or $89.99/yr; club hardware on request | Club camera hardware | Needs Wingfield courts for most features | OBSERVED (App Store IAP, prior research); hardware UNVERIFIED |
| **Baseline Vision** | Monthly subscription to clubs and federations; no public price; app free | Single net-post smart camera | Line calling; UTR Pro Tennis Tour partner (Mar 2026) | UNVERIFIED (secondary summaries) |
| **SevenSix** | $14.99/mo, $149.99/yr; **$1.99 per analysis** (1), $3.99 (3), $4.99 (5) | No | Per-use pricing exists in tennis | OBSERVED (prior research) |
| **PB Vision** (pickleball, closest per-minute model) | Monthly Starter **$19.99 for 100 min**; Premium **$49.99 for 400 min**; annual Starter **$99.99** (limited offer, list $240) for 1,200 min; annual Premium **$396** for 4,800 min | No | "AI Coach", automatic highlights, ratings; minutes are the unit | OBSERVED (rendered pricing page) |

**Does SwingVision support two phones?** Yes for recording: the ITF approval report describes one or two devices
mounted behind one or both baselines (OBSERVED). It uses them for ball tracking and line calls, not for assembling
alternate-angle replays into an edited film (INFERRED from the feature list and compare page). Whether a specific tier
is required is UNVERIFIED.

### 2.3 AI film, highlight and creator editors (price anchors)

| Product | Price | Unit of value | Label |
|---|---|---|---|
| **OpusClip** | Free (60 credits/mo, watermark, 3-day export); Starter **$15/mo** (150 credits); Pro **$29/mo** or **$14.50/mo billed $174/yr** (300 credits, roll over 2 months, AI B-roll); Business custom | 1 credit = 1 minute of imported video | Prices OBSERVED; credit definition UNVERIFIED (secondary) |
| **CapCut Pro** | $19.99/mo or $179.99/yr (US); Standard $9.99/mo in the US App Store | Subscription | UNVERIFIED (secondary; official pricing URL returned 404) |
| **Magic Hour** | Free; $10 / $30 / $66 per month | Subscription | UNVERIFIED (secondary) |
| **Veo Analytics 2 / Hudl Balltime / Trace** | Bundled into the subscriptions above | Player highlight reels and recruiting videos from AI | OBSERVED (features) |
| **Human highlight editors** | ≈$200 recruiting highlight; $350–$1,200 packages; $500–$5,000 full-service recruiting | Per video | UNVERIFIED (vendor pages via search) |

### 2.4 Processing-price anchors per hour of footage

| Offer | $ per hour of footage processed | Label |
|---|---|---|
| PB Vision monthly Starter / Premium | $12.00 / $7.50 | INFERRED from OBSERVED prices |
| PB Vision annual Starter (promo) / Premium | $5.00 / $4.95 | INFERRED |
| OpusClip Starter / Pro annual | $6.00 / $2.90 | INFERRED (credit = 1 min, UNVERIFIED) |
| Veo Go | $2.00 (includes rig on yearly) | INFERRED |
| Hudl Balltime Player | $1.33 | INFERRED |
| SwingVision Pro / Max (allowance, mostly on-device) | $0.83 / $0.67 | INFERRED |
| **JOVRA design-target cost** (section 4.4), 1 angle × 60 min, short film | **$1.03–$1.12** cost, before fees and margin | INFERRED |
| **JOVRA design-target cost**, 6 angles × 60 min, short film | **$0.23–$0.26** per source hour ($1.39–$1.53 per film) | INFERRED |

**What it implies (INFERRED).** JOVRA's cost scales mostly per film (planner tokens) and only weakly per source hour.
Per-minute pricing like PB Vision or OpusClip would overcharge multi-angle users and undercharge single-angle users.
Per-film pricing in credits fits the cost shape better.

---

## 3. Refreshed list prices (model inputs, all checked 2026-10-07)

### 3.1 Cloudflare (OBSERVED)

| Item | Rate | Notes |
|---|---|---|
| R2 Standard storage | **$0.015 / GB-month** | Free tier 10 GB-month; billing rounds **up** to the next unit (1.1 GB → 2 GB) |
| R2 Infrequent Access | $0.01 / GB-month; retrieval $0.01/GB; 30-day minimum | Not used for staging |
| R2 Class A / Class B ops | **$4.50 / M** · **$0.36 / M** (Standard) | Free 1 M A, 10 M B per month |
| R2 egress | **Free** | Connected providers can still charge |
| Workers Paid | **$5/month minimum**; 10 M requests then $0.30/M; 30 M CPU-ms then $0.02/M | 128 MB memory per isolate; queue consumers up to 15 min |
| Durable Objects | 1 M requests then $0.15/M; 400,000 GB-s then $12.50/M GB-s | For job state if used |
| Queues | 1 M operations/month included, then **$0.40 / M** | One op per 64 KB; a delivery is about 3 ops |
| Containers | CPU **$0.000020 / vCPU-s**; memory **$0.0000025 / GiB-s**; disk $0.00000007 / GB-s; Workers Paid includes 375 vCPU-min, 25 GiB-h, 200 GB-h per month | Largest instance **standard-4: 4 vCPU, 12 GiB, 20 GB disk** → **$0.401/hour** (INFERRED). Egress $0.025/GB after 1 TB in NA/EU. No GPU ("coming soon", UNVERIFIED secondary) |

Design consequence (INFERRED): a 20 GB container disk cannot hold six 3.6 GB originals plus outputs. The renderer
should stream byte ranges from R2 or work from proxies and keeper windows.

### 3.2 Supabase (OBSERVED)

Pro **$25/month** includes $10 compute credit (covers one Micro project), 100,000 MAU (then $0.00325), 8 GB disk
(then $0.125/GB), 100 GB file storage (then $0.0213/GB), 250 GB egress (then $0.09/GB). Compute add-ons: Micro $10,
Small $15, Medium $60 per month. Team from $599/month. Media stays in R2, so file storage and egress should stay small
(INFERRED).

### 3.3 Render and analysis host candidates

| Host | Rate | Label |
|---|---|---|
| Cloudflare Containers standard-4 | $0.401/h (4 vCPU, 12 GiB), per-second billing | OBSERVED rates, INFERRED hourly |
| Modal CPU | $0.0000131 per physical core-s, $0.00000222 per GiB-s → **4 cores + 16 GiB ≈ $0.317/h**; $30/month free credit on Starter | OBSERVED rates, INFERRED hourly |
| Modal GPU (for later measured vision) | T4 $0.000164/s; **L4 $0.000222/s ≈ $0.80/h**; A10 $0.000306/s; L40S $0.000542/s; A100 40 GB $0.000583/s; H100 $0.001097/s | OBSERVED |
| Fly.io performance-2x (4 GB) | ≈$66/month always-on; volumes $0.15/GB-month; outbound $0.02/GB NA/EU | OBSERVED monthly; hourly figure on the page was ambiguous |
| Hetzner Cloud dedicated vCPU | Repriced 15 June 2026 (CCX33 €62.49 → €138.49/month, +122%) | UNVERIFIED (secondary article; official page rendered no prices) |
| Remotion Lambda (reference) | Remotion's own example: a 10-minute HD render ≈ $0.103 on AWS Lambda; "rendering a video inside your video increases the cost significantly" | OBSERVED (Remotion docs; their sample composition, not tennis footage) |

### 3.4 Remotion licence (OBSERVED)

Free for individuals, non-profits and **for-profit organisations with up to 3 employees**. Above that a Company
License is needed: Creators $25/month per seat; **Automators $0.01 per render with a $100/month minimum**; Enterprise
from $500/month. Whether a hosted render for paying end users counts as Automator use is not stated (UNVERIFIED). Ask
Remotion before the first paid cloud render. Whether Island Development Crew qualifies for the free tier is an open
question.

### 3.5 Anthropic Claude API (OBSERVED, live pricing page; IDs from the `claude-api` skill)

| Model (ID) | Input | 5m cache write | 1h cache write | Cache read | Output | Batch in / out |
|---|---|---|---|---|---|---|
| **Claude Opus 5.5 (`claude-opus-5-5`)** | **$4** | $5 | $8 | **$0.20** | **$20** | **$2 / $10** |
| Claude Sonnet 5.5 (`claude-sonnet-5-5`) | $2 | $2.50 | $4 | $0.10 | $10 | $1 / $5 |
| Claude Haiku 4.5 (`claude-haiku-4-5`) | $1 | $1.25 | $2 | $0.10 | $5 | $0.50 / $2.50 |
| Claude Fable 5.1 (`claude-fable-5-1`) | $10 | $12.50 | $20 | $0.25 | $50 | $5 / $25 |

All prices are per million tokens. Other terms that matter for Studio:

- **Fast mode** on Opus 5.5 costs $8 / $40, is Claude API only and has no batch. **US-only inference**
  (`inference_geo: "us"`) multiplies every token category by **1.1×**. The 1M-token context window is billed at
  standard rates throughout.
- **Thinking tokens bill as output.** Opus 5.5 cannot disable thinking. Effort defaults to `medium` and is the cost
  control.
- **Vision.** Cost is `ceil(w/28) × ceil(h/28)` visual tokens. The Opus 4.7-and-later high-resolution tier caps at
  2576 px on the long edge and 4,784 tokens. 640×360 costs 299 tokens, 1280×720 costs 1,196 and 1920×1080 costs 2,691.
  Inputs are JPEG/PNG/GIF/WebP only; animations use their first frame. The vision page lists no video input, so the
  pipeline must sample frames (INFERRED).
- **Discrepancies.** The skill's cached table gives Sonnet 5.5 cache reads at $0.20, while the live page says $0.10.
  The live page also lists **Claude Haiku 5.5** at $0.10 / $0.50 for prompts up to 100k tokens, a model absent from
  the skill's cached table. Confirm its ID through the Models API before relying on it (UNVERIFIED).
- **"Astra" (GPT)** is not priced here. Keep the planner adapter configurable and price it at activation.

### 3.6 Payments and store rules (OBSERVED)

- **Apple App Store Small Business Program:** 15% commission on IAP for developers under $1 M prior-year proceeds.
- **US storefront:** guideline 3.1.1(a) lets US-storefront apps link to other purchase methods ("except for the
  United States storefront, where this prohibition does not apply"). Other storefronts still require IAP for in-app
  digital goods.
- **Guideline 3.1.1:** "Any credits or in-game currencies purchased via in-app purchase may not expire." Paid credit
  packs therefore never expire.
- **Guideline 3.1.2(a):** subscriptions must provide ongoing value.
- **Stripe:** 2.9% + 30¢ per domestic card transaction; +1.5% for international cards; +1% when converting currency.

---

## 4. Unit-economics model for one JOVRA Studio film

### 4.1 Assumptions (all INFERRED unless marked)

| # | Assumption | Value |
|---|---|---|
| A1 | Source per angle | 60 min at 8 Mbps (the brief's planning figure) → **3.6 GB** per angle. Audio and container overhead excluded |
| A2 | Analysis/render proxy | 720p at 3 Mbps → 1.35 GB per angle-hour |
| A3 | Film outputs | "Short" story film = 5 min; "Broadcast" = up to 60 min of full chronology (a worst case; dead-time removal usually shortens it). 8 Mbps output; 2 variants (clean + effects) in the low case, 3 (adds portrait) in the high case |
| A4 | Retention | Staging 7 days (low) or 30 days (high); films 30 days in the cloud, then the user's own download |
| A5 | Upload parts | 64 MB multipart; about 3,000 ranged reads per angle |
| A6 | Planner input | Static skill/profile prefix + events + keepers + lesson notes = 23k tokens (low) to 38k (high); plus 40 frames per angle at 640×360 (low) or 80 at 1280×720 (high) |
| A7 | Planner output incl. thinking | 15k (low) to 50k (high) tokens; validation-repair factor 1.0× (low) to 1.5× (high) |
| A8 | Render compute | Short film 0.1–0.5 h; broadcast 0.5–2.0 h of a 4-vCPU host; +10% per extra angle for decode; includes output full-decode verification |
| A9 | Cloud normalization (high case only) | 0.15–0.5 h per angle-hour when originals are normalized in the cloud |
| A10 | Retry overhead | +10% (low) to +50% (high) on compute |
| A11 | Compute price | Cloudflare Containers standard-4, $0.401/h (OBSERVED rates). Modal at $0.317/h would be about 21% cheaper |
| A12 | Excluded from variable cost | Optional measured vision analysis (later stage, shown separately); Remotion per-render fee (≤ $0.05/film if it applies); payment fees and reserves (section 5) |

### 4.2 Data volume and upload time (INFERRED arithmetic)

| Angles | Originals | Upload ≥ at 20 Mbps | Upload ≥ at 100 Mbps | Proxy-first upload (720p) at 20 Mbps | 7-day R2 originals |
|---|---|---|---|---|---|
| 1 | 3.6 GB | 24 min | 4.8 min | 1.35 GB, 9 min | $0.013 |
| 3 | 10.8 GB | 72 min | 14.4 min | 4.05 GB, 27 min | $0.038 |
| 6 | 21.6 GB | **144 min** | 28.8 min | 8.1 GB, **54 min** | $0.076 |

Proxy-first means the phone encodes proxies with its hardware encoder at no cloud cost and uploads full-resolution
bytes only for the selected keeper or rally windows. A full-length Match Broadcast still needs full resolution for
every live-play window of the chosen angle.

### 4.3 Worst-case envelope: per-film variable cost (INFERRED)

Low = 7-day staging, small frame sheets, no cloud normalization, one plan pass. High = 30-day staging, 720p frame
sheets, cloud normalization of every angle, 1.5× plan passes and +50% retries.

| Angles × 60 min | Film | Storage | R2 ops + Workers + Queues | Planner (Opus 5.5) [input / output tokens] | Compute [hours] | **Total** |
|---|---|---|---|---|---|---|
| 1 | Short | $0.03 – $0.09 | $0.002 | $0.44 [35k/15k] – $2.30 [134k/50k] | $0.04 [0.1] – $0.60 [1.0] | **$0.51 – $2.99** |
| 1 | Broadcast | $0.13 – $0.24 | $0.002 | $0.44 – $2.30 | $0.22 [0.5] – $1.50 [2.5] | **$0.79 – $4.04** |
| 3 | Short | $0.06 – $0.24 | $0.005 | $0.54 [59k/15k] – $3.45 [325k/50k] | $0.05 [0.12] – $1.26 [2.1] | **$0.65 – $4.95** |
| 3 | Broadcast | $0.16 – $0.39 | $0.005 | $0.54 – $3.45 | $0.26 [0.6] – $2.35 [3.9] | **$0.96 – $6.19** |
| 6 | Short | $0.11 – $0.46 | $0.009 | $0.68 [95k/15k] – $5.17 [612k/50k] | $0.07 [0.15] – $2.26 [3.75] | **$0.87 – $7.90** |
| 6 | Broadcast | $0.21 – $0.61 | $0.009 | $0.68 – $5.17 | $0.33 [0.75] – $3.61 [6.0] | **$1.23 – $9.40** |

### 4.4 Recommended design target (INFERRED)

The target design uses device-made proxies, 7-day staging, Opus 5.5 planning over events, keepers and 640×360
contact sheets (30k output tokens, 1.25× passes), cloud rendering and verification only, and +20% retries.

| Angles × 60 min | Short film | Broadcast (≤ 60 min out) | Of which planner |
|---|---|---|---|
| 1 | **$1.03 – $1.12** | **$1.32 – $1.68** | $0.96 |
| 3 | **$1.17 – $1.29** | **$1.50 – $1.93** | $1.08 |
| 6 | **$1.39 – $1.53** | **$1.78 – $2.32** | $1.26 |

### 4.5 What dominates, and the levers

- **Planner tokens dominate** in the target design (about 70–90% of the short-film cost). Levers, using the
  6-angle high case ($5.17) as the base:
  - Batch API: $2.59. Plans are not interactive; batch fits the "you can leave this screen" queue.
  - Sonnet 5.5 planner: $2.59.
  - Two-stage planning (Haiku 4.5 captions frames, Opus 5.5 plans on text): $2.94.
  - Sampling frames only for B-roll and uncertain keepers, while angle choice for Match Broadcast stays rule-based in
    code: the frame term grows sub-linearly with angles.
  - Prompt caching of the static skill/profile prefix saves only about $0.015 per repair pass. It helps latency more
    than cost here.
- **Cloud normalization is the second-largest cost and the largest time cost.** Moving it to the phone (AVFoundation
  hardware encode) removes 0.9–3 compute-hours at six angles. Hold an evidence gate: the phone proxy must pass the
  renderer's constant-frame/dimension/rotation checks (`garnet-remotion/PIPELINE.md` limits) before the cloud trusts it.
- **Storage and operations are rounding errors** ($0.002–$0.61 per film) unless retention is extended. Retention
  stays explicit, and a longer period is never applied automatically (backend brief).
- **Optional measured vision analysis (later stage)** on an L4 GPU at 0.1–0.5 h per angle-hour adds **$0.08–$0.40 per
  angle**: $0.24–$1.20 at three angles and $0.48–$2.40 at six. Price it as its own credit line once a benchmark passes.
- **Revisions.** A new revision of a delivered film reuses staged sources, so it costs one planner delta plus one
  render: about $0.4–$1.0 (INFERRED). The reservation must still be a new one (brief: "a new revision must have its own
  bounded reservation").

### 4.6 Fixed monthly floor (OBSERVED list; INFERRED amortization)

| Line | $/month |
|---|---|
| Supabase Pro + Micro compute (covered by the $10 credit) | $25 (Small +$5; Medium +$50) |
| Workers Paid (covers Queues, Containers allowances) | $5 |
| Remotion Company License (only if more than 3 employees) | $0 or $100 minimum |
| Modal Starter | $0 (includes $30 credit) |
| **Floor** | **≈ $30 – $180** |

Per film, that is $0.60–$3.60 at 50 films/month, $0.15–$0.90 at 200 and $0.03–$0.18 at 1,000. The margins below use
$0.45 per film (the 200-films/month midpoint). Below about 50 films a month, the fixed floor exceeds the variable cost.

### 4.7 Not in the model

Sales tax/VAT, Google Play fees, chargebacks, refund handling labour, human support time, licensed music (none by
default), legal review, monitoring and logging tools, the Apple Developer fee, customer-acquisition cost and salaries.
The 10% reserve in section 5 is a placeholder for the variable part of these.

---

## 5. Pricing structures (proposals for Jon; all margins INFERRED)

Margin convention: **contribution = price − store/payment fee − 10% support/refund reserve − $0.45 fixed share −
variable cost**, as a percentage of the gross price. The fee is 15% (App Store Small Business Program) unless noted.
A US web checkout via Stripe at 2.9% + 30¢ would add about 8–12 points of margin on these price points.

### 5.1 Option A: Studio Credits (recommended primary)

The credit is the unit of the quote, the cap, the reservation and the receipt. Credits are bought in fixed-price packs
(IAP consumables, never expiring per guideline 3.1.1, restorable through the account ledger).

| Film class | Credits (cap) | At $2.00/credit | Design-target cost | Contribution at target | Contribution at worst case |
|---|---|---|---|---|---|
| Story film, 1 angle (≤ 10 min out) | 2 | $4.00 | $1.03–$1.12 | **$1.43 (36%)** | −$0.44 (−11%) |
| Story film, 2–3 angles | 4 | $8.00 | $1.17–$1.29 | **$4.26 (53%)** | $0.59 (7%) |
| Story film, 4–6 angles | 6 | $12.00 | $1.39–$1.53 | **$7.01 (58%)** | $0.65 (5%) |
| Match Broadcast, 1 angle | 3 | $6.00 | $1.32–$1.68 | **$2.37 (40%)** | $0.00 (0%) |
| Match Broadcast, 2–3 angles | 5 | $10.00 | $1.50–$1.93 | **$5.11 (51%)** | $0.86 (9%) |
| Match Broadcast, 4–6 angles | 8 | $16.00 | $1.78–$2.32 | **$9.23 (58%)** | $2.15 (13%) |
| New revision of a delivered film | 1 | $2.00 | ≈$0.4–$1.0 | ≈20–45% | — |

Suggested packs: **10 credits $19.99** and **25 credits $44.99** ($1.80/credit). Do not offer deeper discounts until
costs are measured. A 60-for-$89.99 pack ($1.50/credit) goes negative on every film class at worst-case costs.

**How the cap protects margin.** Each credit carries an internal cost budget of **$0.80–$1.00** of metered cost. The
preflight estimate sets the quote at `max(class minimum, ceil(estimated maximum cost / credit budget))` credits. The
UI shows the quote, cap, retention and expiry, then the user consents. The ledger writes an idempotent reservation of
that many credits. The job checks the remaining budget before each stage and retry, and stops at
`budget_exceeded` rather than overrunning. Unused reserved credits return to the balance, and a failed render returns
everything not consumed. Under this rule the worst-case rows above cannot occur as written: such a job would be quoted
more credits up front or declined. The user is never charged above the cap they accepted.

- **Pros:** one ledger for all three options; fixed App Store price points coexist with variable real quotes; matches
  the cost shape (per film, not per minute); no recurring commitment, which fits community complaints about
  subscriptions (`../competitive-analysis.md` §8).
- **Cons:** credits are abstract, so the UI must always show the film's credit price before selection. Non-expiring
  credits are a liability on the books.

### 5.2 Option B: JOVRA Studio membership

**$12.99/month or $119.99/year**, including **6 credits per month** (about three single-angle story films, or one
3-angle story plus one single). Included credits roll over one month. Extra credits cost $1.50 for members. All
on-device Studio features stay free with or without membership (section 6).

Contribution per month, with a fixed share of $0.45 per film (three films at full use):

| Plan | Net after fee and reserve | Full use at a $0.80 credit budget | Full use at a $1.00 budget | Full use at target (≈$0.55/credit) | Half use at target |
|---|---|---|---|---|---|
| Monthly $12.99 | $9.74 | **$3.59 (28%)** | $2.39 (18%) | **$5.09 (39%)** | $7.42 (57%) |
| Annual $119.99 ($10.00/mo) | $7.50 | **$1.35 (13%)** | $0.15 (1%) | **$2.85 (28%)** | $5.17 (52%) |

The "≈$0.55 per credit" figure is the conservative single-angle target ($1.03–$1.12 for 2 credits). Multi-angle films
cost less per credit. The first scenario computed was $99.99/year with 8 credits per month, which lost money at full
use under worst-case envelope costs (−73%). That is why this proposal uses 6 credits and $119.99. Even so, the annual
plan is thin at full use and needs the $0.80 credit budget.

- **Pros:** predictable revenue; can bundle membership-only conveniences that cost money (longer cloud retention,
  hosted share links, later measured cloud analysis).
- **Cons:** a subscription for an occasional activity (match films) invites churn and the paywall resentment
  ADR-0013 was written to avoid. Guideline 3.1.2(a) requires ongoing value. Launch it only after Option A data shows
  repeat monthly use.

### 5.3 Option C: Per-film purchase

| Film | Price | Contribution at target | Contribution at worst case |
|---|---|---|---|
| Story film, 1 angle | **$4.99** | $2.17 (44%) | $0.30 (6%) |
| Story film, 2–6 angles (≤3 / ≤6 shown separately) | **$9.99 / $14.99** | $5.76 (58%) / $9.26 (62%) | $2.09 (21%) / $2.90 (19%) |
| Match Broadcast, 1 angle | **$7.99** | $3.86 (48%) | $1.50 (19%) |
| Match Broadcast, 2–3 / 4–6 angles | **$12.99 / $19.99** | $7.36 (57%) / $12.22 (61%) | $3.11 (24%) / $5.14 (26%) |

The worst-case column assumes no cap rule. With the $0.80-per-credit budget applied to the same credit counts as
Option A, the floor is **34% on the $4.99 film and 38–41%** on the others (INFERRED).

Implement it as a one-film credit bundle on the same ledger: "Create this film — $4.99" buys exactly the quoted
credits and reserves them in one step. The price shown is the most the user pays. If the preflight estimate exceeds
the film's budget, the app offers a smaller job (fewer angles, shorter output) instead of a surprise price.

- **Pros:** simplest to understand, closest to SevenSix ($1.99/analysis) and far below human editors ($200+).
- **Cons:** small IAP transactions lose relatively more to the fixed share and fees; no volume relationship.

### 5.4 Comparison and recommendation

| | A: Credits | B: Membership | C: Per film |
|---|---|---|---|
| Fits quote → consent → cap → reservation | **Natively** | Through included credits | Through a one-film bundle |
| Margin at design target | 36–58% | 42–62% | 44–62% |
| Margin floor with the cap rule (smallest film, $0.80 credit budget) | ≥ 24% at $2.00/credit; ≥ 18% at the 25-pack's $1.80 (7–14% at a $1.00 budget) | ≥ 28% monthly; ≥ 13% annual | ≥ 34% ($4.99 film) to 41% |
| Risk to the "core stays free" promise | Low | Medium (subscription optics) | Low |
| Recommended timing | **First paid launch** | After measured repeat use | Same launch as A, as the default storefront button |

**Recommendation (INFERRED).** Launch A + C together on one credit ledger: per-film buttons for first-time buyers,
packs for repeat buyers. Defer B. Set the credit's internal cost budget at $0.80 until benchmarks narrow the planner
and render ranges, then revisit the price per credit.

---

## 6. The free/paid boundary (keeps core JOVRA free)

Rule of thumb: **if it runs on the user's phone, it is free; if it costs JOVRA money each time it runs, it is opt-in,
quoted and paid; nothing the user already has is ever locked.**

| Free forever (on device, no marginal cost to JOVRA) | Paid, opt-in, quoted (cloud cost per use) | Never locked or charged (ADR-0013 contract) |
|---|---|---|
| Recording, replay, manual scoring, stats with provenance, lessons and journal, clips, notes | Uploading selected sources to private cloud staging | Originals on the phone; "Save original to Photos or Files" |
| "Build your match" capture: every phone records locally with no account | Cloud normalization/proxies when the phone cannot make them | Full data export (JSON/CSV) |
| Import of other angles onto one device; manual sync markers; on-device alignment | JOVRA engine planning: the model-proposed, source-grounded story and typed edit plan | Local films already rendered; cloud films already downloaded |
| Synchronized multi-angle replay of footage on the device | Cloud render, verification and a hosted private preview or expiring share link | Cancelling a job: unused reservations return; local media is untouched |
| The five story profiles rendered **on device** with AVFoundation from a deterministic, rule-based template planner (no model call, no upload) | Later: measured cloud vision analysis per angle-hour, priced separately | Watching, trimming or exporting any footage after a membership lapses |
| "Prepare for YouTube" files for local films (file, cover, chapters, draft copy) | Later: extended cloud retention beyond the default | No ads, no watermark, no hour caps on device |
| Files/iCloud Drive/Google Drive archive (user-owned storage) | | |

Notes:

- **The model planner is the paid line, not the profiles.** All five profiles have free on-device templates. The
  paid tier adds the model-written story, multi-angle cloud assembly and hosted delivery. That keeps the moat (the
  JOVRA engine) monetizable without paywalling the app (INFERRED).
- **A trial costs money.** One free cloud short film costs JOVRA about $1.0–$1.1 at design target (INFERRED). A
  one-time "first film free" is a defensible acquisition cost. A free monthly allowance is not, until revenue exists.
- **Demo/tester identities never spend.** Sample quotes stay labelled "Sample quote" and no real reservation is
  written (backend brief).
- **A new ADR is required** before any of the paid column ships. It must restate ADR-0013's contract and record the
  chosen structure.

---

## 7. Pricing guardrails tied to the job state machine (from the backend brief, made concrete)

1. The quote is computed server-side from actual source bytes, angles, profile, output spec and current rates. Client
   or model price fields are never authoritative.
2. Quote expiry is about 30 minutes. An expired quote moves to `quote_expired` and is re-quoted, never auto-accepted.
3. Reservation = credits × idempotency key `(project, plan revision, output spec)`. A retry under the same key cannot
   charge twice.
4. Budget is checked before every stage and retry. Model, effort, quality and retention are never escalated
   automatically. Over budget means `budget_exceeded` plus a resumable offer.
5. Receipts separate estimate, cap, actual usage and refunds. Taxes and fees appear only once their real policy exists.
6. Failure before `ready` releases every unconsumed credit. A film that fails verification is never charged as
   delivered.

---

## 8. Benchmarks required before retail prices (evidence gates)

| Measure | How | Why it moves price |
|---|---|---|
| Planner tokens per film, by profile and angle count | 20+ real plans on Jon's old match and synthetic fixtures; read `usage` (input, cache, output incl. thinking) at effort `medium` and `low` | 70–90% of target cost |
| Validation-repair rate | Share of plans that need a repair pass | Multiplies the planner cost (1.0–1.5×) |
| Render wall time | 5-min and full-chronology films on Containers standard-4 vs Modal 4-core; with and without Remotion overlays; include full-decode verification | The second-largest line |
| Phone proxy acceptance | Share of phone proxies passing the strict constant-frame and dimension checks | Decides whether cloud normalization is needed |
| Upload success and time | Real 1/3/6-angle uploads on 20 and 100 Mbps links, with resume | Turnaround promises; abandonment |
| Retry and failure rate | Failed attempts per 100 jobs | The retry multiplier and refund reserve |
| Actual R2 bill vs model | One month of tester jobs | Validates billing-unit rounding and ops counts |

---

## 9. Decisions recommended and open questions

Recommended decisions (for Jon):

1. Adopt **Studio Credits** as the single ledger. Sell them as **per-film buttons** ($4.99 single-angle story up to
   $19.99 six-angle broadcast) **plus packs** (10 for $19.99, 25 for $44.99). Defer the membership.
2. Set the **free/paid line at on-device vs per-use cloud cost**. Keep on-device template films and multi-angle replay
   free. Charge for the model-planned story and cloud production. Record this in a new ADR that restates ADR-0013.
3. Make **device-side proxies plus keeper-window upload** the default architecture. It sets both cost and turnaround.
4. Default the planner to **Opus 5.5 at effort `medium` via the Batch API** for non-urgent films. Keep the adapter
   configurable (Sonnet 5.5; a two-stage Haiku caption pass; "Astra" once priced).
5. Start with **Modal CPU or Cloudflare Containers** for rendering (both per-second billing). Neither needs a GPU until
   measured vision ships. Avoid always-on VMs until volume justifies them.
6. Set the internal credit cost budget at **$0.80**. Do not publish any credit price until section 8's benchmarks run
   on real footage.

Open questions:

- Does Island Development Crew have three or fewer employees (free Remotion licence)? Does a hosted render for end
  users count as Remotion Automator use?
- Is the App Store Small Business Program rate (15%) in place for the publishing account? Will US web checkout
  (allowed by guideline 3.1.1(a)) be offered, given its extra build and support cost?
- Which real model and price does "Astra" map to?
- Is "first film free" acceptable as the only trial?
- Should hosted share links (24-hour expiry) be free for paid films, and for how long does the cloud copy persist by
  default (7 vs 30 days)?
- Haiku 5.5 appears on the live pricing page but not in the skill's model table. Should its ID be confirmed through
  the Models API before it enters the adapter list?

---

## Sources

Primary (fetched or rendered 2026-10-07):

- Cloudflare R2 pricing: https://developers.cloudflare.com/r2/pricing/
- Cloudflare Workers pricing: https://developers.cloudflare.com/workers/platform/pricing/
- Cloudflare Workers limits: https://developers.cloudflare.com/workers/platform/limits/
- Cloudflare Queues pricing: https://developers.cloudflare.com/queues/platform/pricing/
- Cloudflare Containers pricing: https://developers.cloudflare.com/containers/pricing/
- Cloudflare container limits changelog (2026-02-25): https://developers.cloudflare.com/changelog/2026-02-25-higher-container-resource-limits
- Supabase pricing: https://supabase.com/pricing
- Modal pricing: https://modal.com/pricing
- Fly.io pricing: https://docs.fly.io/about/pricing
- Remotion licence: https://github.com/remotion-dev/remotion/blob/main/LICENSE.md and https://www.remotion.pro/license
- Remotion Lambda cost example: https://www.remotion.dev/docs/lambda/cost-example
- Anthropic pricing: https://platform.claude.com/docs/en/about-claude/pricing
- Anthropic vision (token formula, formats, limits): https://platform.claude.com/docs/en/build-with-claude/vision
- `claude-api` skill model table (cached 2026-09-25), bundled with Claude Code 2.1.289
- Apple App Store Small Business Program: https://developer.apple.com/app-store/small-business-program/
- Apple App Review Guidelines 3.1.1, 3.1.1(a), 3.1.2(a): https://developer.apple.com/app-store/review/guidelines/
- Stripe pricing: https://stripe.com/pricing
- Veo pricing (rendered, en-us): https://www.veo.com/pricing
- Veo Go product page: https://veo.com/product/veo-go
- SwingVision compare page (rendered): https://swing.vision/subscribe/compare
- SwingVision ITF approval report PAT-25-037: https://www.itftennis.com/media/15294/pat-25-037-approval-report-swingvision.pdf
- Trace PlayerFocus plans: https://support.traceup.com/content/how-to-subscribe-to-trace-highlights-playerfocus
- Hudl Assist pricing (football): https://www.hudl.com/pricing/assist/football
- Hudl Balltime pricing: https://www.hudl.com/pricing/balltime
- Pixellot plans page (prices not rendered): https://you.pixellot.tv/plans
- Pixellot Air NXT retailer listing: https://videoguys.com/products/pixellot-air-nxt-portable-ai-sports-camera
- Mevo Pro: https://www.mevo.com/pages/pro
- PB Vision pricing (rendered): https://pb.vision/subscribe
- OpusClip pricing (rendered): https://www.opus.pro/pricing

Secondary (UNVERIFIED; used only where labelled):

- Hetzner June 2026 repricing: https://privatedevops.com/news/hetzner-june-2026-cloud-price-increase-what-to-do
- Hetzner CCX33 price tracker: https://spendark.com/instances/ccx33/
- OpusClip credit definition: https://www.castmagic.io/blog/opus-clip-pricing
- CapCut pricing: https://www.hooked.so/compare/capcut-pricing and https://costbench.com/software/video-editing/capcut/
- Magic Hour and sports-editor roundup: https://magichour.ai/blog/sports-video-editing-software
- Mevo Core launch price: https://www.businesswire.com/news/home/20240319877017/en
- Spiideo pricing summary: https://www.trustradius.com/products/spiideo/pricing
- XbotGo hardware (vendor blog): https://xbotgo.com/blogs/buying-guide/xbotgo-vs-hudl-football
- Baseline Vision business model: https://www.hcs-capital.com/portfolio/baseline/
- Recruiting/highlight video costs: https://www.veo.com/article/how-much-does-a-recruiting-video-cost and https://samuellongproductions.mypixieset.com/sportsprice/
- Cloudflare Containers alternatives / GPU status: https://northflank.com/blog/top-cloudflare-containers-alternatives

Repository inputs (read-only):

- `/Users/IDC2.5/jv/design-reference/studio/brief/backend-media-design.md` (earlier cost arithmetic, job state machine)
- `/Users/IDC2.5/jv/docs/adr/0013-no-paywall-ads-or-tracking-in-v1.md` and `0002-local-first-document-store.md`
- `/Users/IDC2.5/jv/docs/research/competitive-analysis.md`, `raw/landscape.md`, `raw/swingvision.md` (App Store IAP prices, PlaySight/Wingfield/Smashpoint/SevenSix)
- `/Users/IDC2.5/jv/.claude/skills/jovra-cloud-production/SKILL.md`, `docs/handoff/studio/*`
- `/Users/IDC2.5/Desktop/you-link-x/garnet-remotion/PIPELINE.md` and `production_preview.py` (renderer constraints, read only)
