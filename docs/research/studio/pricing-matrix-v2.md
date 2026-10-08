# JOVRA Studio: pricing matrix v2 and the quote UX (screens 37 and 57)

Research date: 2026-10-07 (revised the same day: §3.7, §8 and §11 reconcile the quote UX with the shipped quote
contract, the Android and adaptive specs and ADR-0013; see §11). Builds on `pricing-and-premium.md` (the v1 cost model, called **v1** below) and on Jon's
pricing decision of 2026-10-07 (`docs/handoff/JON-ORIGINAL-PROMPT.md`, addendum item 1; ADR-0023). Scope: per-job
cost drivers by story length, capture quality, angles and source minutes; a credit formula with a worked matrix that
keeps at least 30% margin at the design cost and never goes negative at the cap; the quote UX for ST37 (iOS) and
screen 57 (Android); competitor anchors; and recommended wording changes to ADR-0023.

Labels follow the repository convention. **OBSERVED** means read from a primary page on 2026-10-07. **INFERRED** means
derived by this document's arithmetic or reasoning. **UNVERIFIED** means a secondary source, a search summary or an
undated claim. Prices are USD list prices excluding tax.

Nothing here is a decision or a price. No account was created, no service provisioned and no money spent. ADR-0013,
ADR-0019 and ADR-0023 govern: until a pricing ADR exists and the benchmarks in v1 §8 have run on real footage, every
quote is **Sample**. Every credit figure below is a proposal to test, not a number to ship.

---

## 0. Findings in brief

1. **Cloud story planning, not video quality, is most of the cost.** At the design target, the dual-provider planner
   (Claude Opus 5.5 drafts, GPT-6.1 Sol critiques, Opus refines) is 47–85% of a model-planned film's design cost (85% for a short 1080p film, 47% for a six-angle 4K60 one). Capture
   quality mostly changes upload size and render time. A 10-minute film from one 60-minute angle costs about **$1.68
   at 1080p30 and $2.93 at 4K60** with cloud planning, and **$0.32 vs $1.56** without it (INFERRED, §3).
2. **The formula comes in two parts, and the price toggle maps onto them.**
   `credits = ceil(production + planning)`. **Production** depends on story length × capture quality (and the chosen
   film quality) × angles, plus source minutes. **Planning** is an add-on that applies only when "Plan the story in the
   cloud" is on (ST37 default **off**, D-5), and it depends on length, angles and source minutes, not on quality (§4).
3. **The worked matrix holds on every cell.** Across 1,728 combinations (8 length tiers × 9 quality columns, which are
   the seven capture classes plus the two "4K captured → 1080p film" columns of §4.3, × 6 angle counts × 4
   source-duration classes), each with planning on and off, and at both $1.80 and $2.00 per credit: zero
   violations. The minimum design-cost margin is **32%** with rules-planned production and **44%** with cloud planning.
   Contribution at the cap is never negative (minimum $0.00 rules / $0.03 model). Medians are 63% and 57% (INFERRED, §4.6).
4. **Typical prices (1 angle, 60-minute source, at $1.80–$2.00 per credit, all Sample):** a 3-minute 1080p film is
   **1 credit** rules-planned and **3 credits** cloud-planned. A 10-minute "ESPN-style" extended cut from three
   1080p60 phones over a two-hour match is **4 / 8 credits** ($7.20–$8.00 / $14.40–$16.00). A full two-hour match from
   one phone is **6 / 13 credits**. The largest story cell (30 minutes, 4K60, six angles, four-hour source) is **32 / 42
   credits**. The largest Full cell is **42 / 52** (§5).
5. **The cap, not the design cost, sets the price today.** Unbenchmarked render throughput (×2.5 uncertainty, ×1.5
   retries), Android bitrates (×2) and `max_tokens`-bounded planner calls make the cap 2.5–5× the design cost. Once the
   benchmarks cut render uncertainty to ×1.3, the 4K60 30-minute base falls from 10.0 to 6.8 production credits. A
   planner cap tightened to about 1.8× design would cut the planning add-on by roughly a third (§6).
6. **The provider pair moves price more than quality does.** In a single-matrix sensitivity fit, GPT-6 Astra as critic raises
   planning-on prices by about one credit per cell. With Astra drafting, they roughly double: a 3-minute film goes from 3 to 6 credits.
   GPT-6 Astra lists at $10 / $50 per million tokens, against $2 / $10 for GPT-6.1 Sol and $4 / $20 for Opus 5.5
   (OBSERVED). **Recommendation:** default to Opus 5.5 drafting with GPT-6.1 Sol critiquing, and bind the pair and role
   assignment in the quote. A change is a re-quote, never a silent escalation (ADR-0019) (§6).
7. **Policies needed for a finite cap** (proposals for Jon): Full match renders at most **1080p60**, because a
   four-hour 4K60 film is about 120 GB per variant. Re-preparing a whole recording in the cloud is a **separate re-quote**
   and never sits inside the cap. A film's cloud copy for its first **12 months is included** in the price (D-3 keeps
   films until deleted, so storage keeps costing money each month). Story tiers longer than about 60% of the match's
   playable time are not offered (§3.6).
8. **Quote UX:** first a simple path (story → length → the quote in credits). The shipped quote contract shows an
   estimate range and a spending limit (`jovra.quote/1`, `estimate` + `capCredits`); this document **recommends one
   number in credits, which is also the cap** ("the most this can cost"), pending Jon's decision (§10 Q1). Then "What
   sets the price" with four live drivers (length, film quality, angles, source minutes) plus the planning toggle:
   Jon's price toggle. Sample state everywhere until the pricing ADR. The app shows credits, not dollars, and there is
   no purchase flow at all until the pricing ADR (ADR-0013); credit packs are a post-ADR design (§8).
9. **Competitor anchors:** JOVRA's model-planned 10-minute cut from 3 × 2 h of footage works out to **$2.40–$2.67
   per source angle-hour**. That is below PB Vision ($4.95–$12.00 per hour) and well below human highlight editors
   ($20–$250+ per reel, UNVERIFIED). A model-planned Full match from one phone is **$11.70–$13.00 per source hour**,
   the top of the per-hour range. That is the case for keeping Full's planning add-on lean (§7).

---

## 1. Method and limits

- **List prices** were fetched on 2026-10-07 from primary pages (§2). PB Vision, SwingVision and Veo price amounts are
  JavaScript-rendered. Today's fetch returned no amounts, so this document cites v1's rendered read from the same day
  (OBSERVED in v1, not re-rendered here).
- **The cost model is a script, not a benchmark.** `pricing_v2.py`, `fit3.py` and `fit4.py` live in this session's
  scratchpad, not the repository, as v1's script did. Section 4 states the formula and every fitted constant, so the
  matrix can be rebuilt from this page. Throughputs, token counts and capture bitrates are assumptions (§3.1), each
  tagged with how a benchmark replaces it.
- **Margin convention (from v1 §5):** contribution = price − 15% store fee − 10% support/refund reserve − $0.45 fixed
  share per film − variable cost. Prices are tested at **$1.80** (the 25-credit pack, worst case) and **$2.00** (the
  single-film button).
- **Not modelled:** taxes, chargebacks, Remotion per-render fees (v1: at most $0.05 per film, and $0 while IDC has three
  or fewer employees), measured cloud vision (a later, separately priced stage), human support time and
  customer-acquisition cost.

---

## 2. Refreshed list prices (all read 2026-10-07)

| Input | Rate | Label and source |
|---|---|---|
| Claude Opus 5.5 | $4 input · $5 5-min cache write · **$0.20 cache read** (0.05× input) · $20 output · Batch $2 / $10 · `inference_geo: "us"` ×1.1 | OBSERVED, platform.claude.com pricing |
| Claude Sonnet 5.5 / Haiku 5.5 (alternates) | $2 / $10; Haiku 5.5 $0.10 / $0.50 for prompts ≤ 100k tokens | OBSERVED, same page |
| **GPT-6 Astra** | $10 input · $1.00 cached · **$50 output**; prompts over 272k input tokens: $20 / $2 / $75; Batch and Flex 50% | OBSERVED, developers.openai.com/api/docs/pricing |
| **GPT-6.1 Sol** | $2 input · $0.10 cached · $10 output; over 272k: $4 / $0.20 / $15; Batch and Flex 50% | OBSERVED, same page |
| GPT-6 Sol (older) | $2 · $0.20 cached · $10 | OBSERVED, same page |
| Cloudflare R2 Standard | $0.015 / GB-month; Class A $4.50/M; Class B $0.36/M; egress free; billing rounds up to the next unit | OBSERVED |
| R2 Infrequent Access | $0.01 / GB-month; $0.01/GB retrieval; 30-day minimum | OBSERVED |
| Cloudflare Containers | $0.000020 / vCPU-s; $0.0000025 / GiB-s; $0.00000007 / GB-s disk; largest **standard-4: 4 vCPU, 12 GiB, 20 GB** → **$0.401/h** | OBSERVED rates; hourly INFERRED |
| Modal (alternative host) | CPU $0.0000131 / core-s; memory $0.00000222 / GiB-s; **network egress $0.04 / GiB** (not in v1); Starter $30 credit | OBSERVED |
| Apple App Store | 15% (Small Business Program) | OBSERVED in v1 §3.6 |
| Google Play | "15% for the first $1M (USD) revenue earned by the developer each year". In the US, UK, EEA, Japan and Australia, the page shows "10% + 5% billing fee" for in-app purchases by new install users (15% in total, INFERRED) | OBSERVED, Play Console help 112622 |
| Output bitrates (finished films) | YouTube SDR: 480p 2.5 / 4; 720p 5 / 7.5; 1080p 8 / 12; 2160p 35–45 / 53–68 Mbps (30 / 60 fps) | OBSERVED, YouTube Help 1722171 |
| Capture bitrates (iPhone HEVC) | iOS Settings text: 720p30 40 MB/min; 1080p30 60; 1080p60 90; 4K30 170; 4K60 400; slo-mo 1080p120 170 MB/min | **UNVERIFIED** (secondary summaries of the Settings text) |

**ADR-0023 model naming check (OBSERVED):** OpenAI's pricing page lists "GPT-6 Astra", "GPT-6 Sol" and "GPT-6.1 Sol".
The exact API model ids were not shown in the fetched text, so they stay configuration, verified at activation, as
ADR-0023 says.

---

## 3. Per-job cost drivers

### 3.1 Inputs and assumptions

| # | Driver | Design value | Cap value | Replaced by |
|---|---|---|---|---|
| C1 | **Capture quality classes** (pixel-rate factor *p* vs 1080p30) | SD 480p30 *p*=0.20 · HD 720p30 0.44 · 1080p30 1.0 · 1080p60 2.0 · 1080p120 4.0 · 4K30 4.0 · 4K60 8.0 | same | n/a |
| C2 | Capture bitrate (Mbps) | 2.5 · 5.3 · 8 · 12 · 22.7 · 22.7 · 53.3 (C2 row of §2; SD INFERRED) | **×2** (Android H.264, high-bitrate modes) | Device capture metadata per source |
| C3 | Film quality (output) | Equal to capture by default, never above it. 1080p120 capture → 1080p60 film. "4K captured → 1080p film" is a choice | same | n/a |
| C4 | Output bitrate | YouTube SDR row (4K uses the upper value) | same | Measured film sizes |
| C5 | Film variants stored | Master + 1 alternate at ≤ 1080p30 8 Mbps | Master + 2 alternates | Product decision |
| C6 | Upload (proxy-first, v1 §4.2) | Every angle: whole-span 720p proxy at 3 Mbps (SD/HD sources upload themselves). Primary angle: full-resolution windows of min(source, 1.5 × film length). Each extra angle: min(source, 0.5 × film length) | Every angle uploads full-resolution windows of min(source, 1.5 × film length) | Benchmark: real uploads |
| C7 | Staging retention | 7 days | 30 days | Player's choice (D-3) |
| C8 | **Film library** | **12 months included** in the price (see §3.6) | same | Jon's decision on D-3 |
| C9 | Render compute per output minute (4 vCPU) | 0.0083 h × *p*out × (1 + 0.1 × extra angles) compose/encode + 0.0017 h × *p*out verify + 0.0020 h × *p*src × (1.2 + 0.3 × extra angles) source decode; + 0.05 h fixed; + 0.01 h per angle-hour of sync | ×2.5 uncertainty × 1.5 retries; plus keeper-window cloud normalization 0.5 h per angle-hour × *p*src | Benchmark: render wall time (v1 §8) |
| C10 | Design retries | ×1.2 on compute | (in C9) | Failure rate |
| C11 | **Planner, bounded handoff** (ADR-0023) | Drafter → critic → refine (×1.25 for repairs). Opus 5.5 drafts and refines, GPT-6.1 Sol critiques | Same pair; every call at its `max_tokens`; refine plus one repair (×2); ×1.25 for a billed retry | Benchmark: plan usage (v1 §8) |
| C12 | Planner input | 15k static prefix (cached after the first call) + 100 tokens per source minute of point events + 1,000 per planned film minute of keeper candidates + frames per angle min(20 + 2 × L, 80) at 640×360 (299 tokens each); the critic sees ≤ 24 frames per angle | 150 tokens per source minute of events; same frames | Usage logs |
| C13 | Planner output (thinking included) | Draft 8k + 900 × L; critique 3k + 300 × L | `max_tokens`: draft 16k + 2,000 × L; critique 8k + 800 × L | Usage logs |
| C14 | "Planned length" *L* | Film minutes, capped at 30. For Full, the model plans chapters, replays and titles; chronology cuts stay rule-based (v1 §4.5 lever) | same | n/a |
| C15 | Full match output | 0.6 × source (dead time trimmed) | 1.0 × source | Measured live-play ratio |

`max_tokens` is a hard limit on output, and input size is known before each call, so the planner's cap is computable
exactly. That is why the cap can be enforced rather than estimated (INFERRED from the API contract; OBSERVED that
thinking bills as output, v1 §3.5).

### 3.2 Design and cap cost, cloud planning on (1 angle, 60-minute source, USD, INFERRED)

| Film length | SD 480p30 | HD 720p30 | 1080p30 | 1080p60 | 1080p120 | 4K30 | 4K60 |
|---|---|---|---|---|---|---|---|
| 3 min | 0.95 / 2.80 | 0.98 / 2.90 | 1.01 / 2.95 | 1.05 / 3.09 | 1.06 / 3.23 | 1.22 / 3.46 | 1.39 / 4.03 |
| 5 min | 1.10 / 3.28 | 1.15 / 3.41 | 1.20 / 3.54 | 1.26 / 3.76 | 1.27 / 4.00 | 1.55 / 4.38 | 1.83 / 5.33 |
| 10 min | 1.48 / 4.46 | 1.57 / 4.69 | 1.68 / 5.00 | 1.80 / 5.44 | 1.82 / 5.93 | 2.37 / 6.67 | 2.93 / 8.58 |
| 15 min | 1.86 / 5.65 | 1.99 / 5.98 | 2.16 / 6.46 | 2.33 / 7.12 | 2.37 / 7.85 | 3.19 / 8.97 | 4.03 / 11.84 |
| 20 min | 2.24 / 6.83 | 2.41 / 7.26 | 2.64 / 7.92 | 2.87 / 8.80 | 2.92 / 9.77 | 4.01 / 11.27 | 5.13 / 15.09 |
| 25 min | 2.62 / 8.02 | 2.83 / 8.54 | 3.12 / 9.38 | 3.40 / 10.48 | 3.47 / 11.70 | 4.83 / 13.56 | 6.23 / 18.34 |
| 30 min | 2.99 / 9.20 | 3.24 / 9.82 | 3.59 / 10.84 | 3.94 / 12.17 | 4.02 / 13.62 | 5.65 / 15.86 | 7.33 / 21.60 |
| Full (60 min) | 3.04 / 9.51 | 3.34 / 10.43 | 3.76 / 11.84 | 4.18 / 13.33 | 4.27 / 13.91 | 3.91 / 12.68 ¹ | 4.48 / 15.19 ¹ |

¹ Full renders at most 1080p (policy §3.6), so a 4K Full costs less to render than a 4K story tier.

### 3.3 Production only, rules-planned (planning off), same jobs (design / cap, USD, INFERRED)

| Film length | SD 480p30 | HD 720p30 | 1080p30 | 1080p60 | 1080p120 | 4K30 | 4K60 |
|---|---|---|---|---|---|---|---|
| 3 min | 0.06 / 0.18 | 0.09 / 0.28 | 0.12 / 0.33 | 0.16 / 0.46 | 0.16 / 0.61 | 0.33 / 0.83 | 0.49 / 1.41 |
| 10 min | 0.12 / 0.30 | 0.20 / 0.53 | 0.32 / 0.84 | 0.43 / 1.28 | 0.46 / 1.77 | 1.00 / 2.51 | 1.56 / 4.42 |
| 30 min | 0.27 / 0.65 | 0.53 / 1.27 | 0.87 / 2.29 | 1.22 / 3.62 | 1.30 / 5.07 | 2.93 / 7.31 | 4.61 / 13.05 |
| Full (60 min) | 0.32 / 0.96 | 0.62 / 1.88 | 1.04 / 3.29 | 1.46 / 4.78 | 1.55 / 5.36 | 1.19 / 4.13 | 1.77 / 6.64 |

### 3.4 What drives each job (INFERRED)

| Job | Case | Total | Planner | Compute | Film library (12 mo) | Staging + ops | Upload | Compute h | Planner tokens |
|---|---|---|---|---|---|---|---|---|---|
| 10 min · 1080p60 · 3 angles · 2 h source | design | $2.19 | 77% | 9% | 12% | 2% | 10.3 GB | 0.50 | 96k |
| | cap | $7.09 | 66% | 25% | 5% | 3% | 16.2 GB | 4.37 | 131k |
| 15 min · 4K60 · 6 angles · 3 h source | design | $5.54 | 47% | 22% | 28% | 3% | 48.3 GB | 3.09 | 167k |
| | cap | $27.90 | 24% | **62%** | 6% | 7% | 132 GB | **43.4** | 213k |
| Full · 1080p30 · 1 angle · 2 h source | design | $4.84 | 58% | 10% | **32%** | 1% | 9.2 GB | 1.16 | 128k |
| | cap | $15.20 | 57% | 15% | 26% | 2% | 17.1 GB | 5.84 | 195k |

Reading the table:

- **Quality changes the answer only at 4K, and only through compute at the cap.** A 43-hour cap is far above the
  15-minute stop warning on a Containers instance (`studio-v1-spec.md` SD notes, OBSERVED). A 4K multi-angle render
  has to be segmented and resumable whatever the price.
- **The film library is real money for long films.** Twelve months of a Full film is a third of its design cost. That
  is why C8 is a decision for Jon, not a rounding error.
- **Upload size is the user's cost, not JOVRA's.** R2 ingress is free, and seven days of staging is pennies. Upload
  size decides turnaround (§3.5) and must be shown, but it barely moves credits.
- **The context limits hold.** The largest critic input in the grid is 200k tokens at the cap, under GPT's 272k
  long-context threshold. The largest drafter input is 333k, which is fine for Opus (1M context at standard rates,
  OBSERVED). A role swap putting Astra on drafting must keep inputs at or below 272k, or that call doubles in price.

### 3.5 Upload by capture quality (proxy-first; 10-minute film, 60-minute source; design; INFERRED)

| Captured as | Raw per angle-hour | 1 angle upload | at 20 Mbps | 6 angles upload | at 20 Mbps |
|---|---|---|---|---|---|
| SD 480p30 | 1.1 GB | 1.1 GB | 8 min | 6.8 GB | 45 min |
| HD 720p30 | 2.4 GB | 2.4 GB | 16 min | 14.3 GB | 95 min |
| 1080p30 | 3.6 GB | 2.3 GB | 15 min | 10.5 GB | 70 min |
| 1080p60 | 5.4 GB | 2.7 GB | 18 min | 11.7 GB | 78 min |
| 1080p120 | 10.2 GB | 3.9 GB | 26 min | 14.9 GB | 99 min |
| 4K30 | 10.2 GB | 3.9 GB | 26 min | 14.9 GB | 99 min |
| 4K60 | 24.0 GB | 7.4 GB | 49 min | 24.1 GB | 161 min |

HD uploads the whole source, because a 720p proxy would be the source again. That makes six-angle HD larger than
six-angle 1080p, where only windows go up at full resolution.

**Lever (INFERRED):** where the film quality is below capture (4K captured, 1080p film, and every Full match), the
phone should transcode its full-resolution windows to the film's resolution before upload. That cuts 4K60 upload by
about 4× and removes most of the cap's normalization term. This model does not assume it, so its 4K numbers are
conservative.

### 3.6 Policies that make the cap finite (proposals for Jon, each INFERRED)

1. **Full match renders at most 1080p60.** A 4K60 Full film of a four-hour match is about 120 GB per variant at
   YouTube's recommended bitrate, beyond what a phone should download or a viewer can play smoothly. 4K stays
   available for every story tier (3–30 minutes).
2. **Re-preparing a whole recording in the cloud is a re-quote.** If the phone's proxies or windows fail the
   renderer's constant-frame and dimension checks (v1 §4.5 evidence gate), the cap covers re-preparing keeper windows
   only. Re-preparing the whole span is offered as a new, separately consented quote ("Your phone's copies need
   preparing in the cloud: +N credits"), consistent with `budget_exceeded` plus a resumable offer (ADR-0019).
3. **Twelve months of the film's cloud copy are included.** D-3 keeps cloud films until the player deletes them. The
   price can only include a bounded period. After 12 months, either the film moves to R2 Infrequent Access
   ($0.01/GB-month) or the player is reminded to download it, and nothing is ever deleted without the player's action.
   This needs Jon's call (§10, Q3).
4. **A story tier is offered only when it fits the match.** Tier ≤ about 60% of the source span, or better ≤ the
   playable time measured from point events. "Longer than this match's play" disables the chip with a reason.
5. **Mixed-quality angles price at the highest class among them** (simple and conservative). Per-angle pricing is a
   later refinement.
6. **Source classes:** ≤ 60, ≤ 120, ≤ 180 and ≤ 240 minutes per angle. Longer recordings are split or custom-quoted.

---

### 3.7 Sources outside the seven classes, and the output axis (INFERRED; proposals)

Jon listed SD, HD, 30 and 60 fps, UHD, 4K30, 4K60 and 1080p120 and added "whatever it is"; core capture also allows
240 fps for practice, and phones record HDR. Neither fits the seven classes, so "mixed quality prices at the highest
class" had nowhere to place them. Proposal, until benchmarks replace it:

- **Classify by pixel rate, rounding up.** A source's class is the cheapest class whose pixel rate *p* is at least the
  source's (width × height × fps ÷ 1080p30's). **1080p240** has the same pixel rate as 4K60 (1920 × 1080 × 240 =
  3840 × 2160 × 60 ≈ 498 Mpx/s), so it prices as **4K60** (*p* = 8); 720p240 (*p* ≈ 3.6) prices as 1080p120.
- **High frame rate is for slow motion, not a higher film rate.** A 240 fps source makes ⅛-speed clean replays in a
  30 fps film (`sourceFPS × s ≥ outputFPS`); the film itself is at most 60 fps.
- **HDR (10-bit HLG or Dolby Vision) prices one class up** from its resolution and frame rate until the tone-mapping
  render time is measured (the normalizer tone-maps to SDR with a declared method, android-v1-spec "ProxyNormalizer");
  an HDR 4K60 source has no class above it and is priced as 4K60 with the measured tone-mapping cost added once known.
- **The output axis ("the way it's rendered and brought back").** The film quality is its own driver (C3, §8.2 Film
  quality): resolution and frame rate of the delivered film, never above the capture, with Full at most 1080p60 if
  Jon adopts policy 1. The downscale columns of §4.3 price it. ADR-0023 names neither the angle count, cloud planning
  nor the output quality as drivers (§9 items 1–2 recommend adding them); until its owner amends it, ADR-0023
  under-specifies this axis (open finding F-ADR-0023 in `docs/spec/adaptive-open-findings.md`).

## 4. The credit formula

### 4.1 The two constraints, made exact (INFERRED)

With price per credit *P* (worst case $1.80), a job priced at *n* credits must satisfy:

- **Design margin ≥ 30%:** *n · P* · (1 − 0.15 − 0.10 − 0.30) ≥ design cost + $0.45 → **n ≥ (design + 0.45) / (0.45 *P*)**
  (= /0.81 at $1.80)
- **Never negative at the cap:** *n · P* · (1 − 0.15 − 0.10) ≥ cap cost + $0.45 → **n ≥ (cap + 0.45) / (0.75 *P*)**
  (= /1.35 at $1.80)

At $2.00 per credit, both hold with more room. Today the second constraint binds in nearly every cell, because the
cap is 2.5–5× the design cost (§3.2). As benchmarks shrink the cap, prices can come down (§6).

**Consequence for ADR-0019's internal budget.** v1 set a fixed $0.80 internal cost budget per credit. Under v2, the
per-job internal cost cap (micro-USD, always enforced) is the job's computed **cap cost**. The formula guarantees
**cap cost ≤ n × $1.35 − $0.45**. Keeping the fixed $0.80 per credit instead would need about 1.7× the credits for
the same jobs.

### 4.2 The formula

```
credits = ceil( production + planning )                       # one number; it is also the cap

story tiers (3, 5, 10, 15, 20, 25, 30 min):
  production = R[length][quality] × angleMult[band][angles]
             + perExtraSourceHour[band] × angles × (sourceMinutes − 60) / 60     # 0 for sources ≤ 60 min
Full match:
  production = FullPerSourceHour[quality] × (sourceMinutes / 60) × FullAngleMult[angles]

planning (only when "Plan the story in the cloud" is on):
  planning = PL[length] × planAngleMult[angles] × planSourceMult[sourceClass]
```

`quality` is the pricing column: the capture class, or one of the two downscale columns when the player picks a
1080p film from a 4K capture. `band` groups columns that share an angle curve: **≤1080p30** (SD, HD, 1080p30, 4K30 →
1080p film), **1080p60/120** (1080p60, 1080p120, 4K60 → 1080p60 film) and **4K** (4K30, 4K60).

### 4.3 Worked matrix: production base R (credits; 1 angle; source ≤ 60 min; before rounding)

| Film length | SD 480p30 | HD 720p30 | 1080p30 | 1080p60 | 1080p120 | 4K30 | 4K60 | 4K30 captured → 1080p film | 4K60 captured → 1080p60 film |
|---|---|---|---|---|---|---|---|---|---|
| 3 min | 0.7 | 0.7 | 0.8 | 0.8 | 0.8 | 1.0 | 1.4 | 0.8 | 1.1 |
| 5 min | 0.7 | 0.8 | 0.8 | 0.9 | 1.1 | 1.4 | 2.1 | 1.0 | 1.4 |
| 10 min | 0.7 | 0.9 | 1.0 | 1.3 | 1.7 | 2.2 | 3.7 | 1.5 | 2.4 |
| 15 min | 0.8 | 1.0 | 1.3 | 1.8 | 2.3 | 3.1 | 5.3 | 2.1 | 3.4 |
| 20 min | 0.8 | 1.1 | 1.5 | 2.2 | 2.9 | 4.0 | 6.9 | 2.6 | 4.4 |
| 25 min | 0.9 | 1.2 | 1.8 | 2.6 | 3.5 | 4.9 | 8.5 | 3.1 | 5.4 |
| 30 min | 0.9 | 1.3 | 2.1 | 3.1 | 4.1 | 5.8 | 10.0 | 3.7 | 6.4 |
| **Full, per source hour** | 1.1 | 1.8 | 2.8 | 3.9 | 4.4 | 4.4 | 5.3 | 3.4 | 5.3 |

The columns are monotone in capture quality by construction. 1080p120 and 4K30 have the same pixel rate (*p* = 4).
The 4K columns cost more because their film is 4K (encode, verification, library). The downscale columns show what
the "Film quality: 1080p" choice saves.

### 4.4 Multipliers

**Angle multiplier (story tiers), by band:**

| Angles | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| ≤1080p30 band | 1.00 | 1.55 | 2.10 | 2.65 | 3.20 | 3.75 |
| 1080p60/120 band | 1.00 | 1.65 | 2.30 | 2.90 | 3.55 | 4.20 |
| 4K band | 1.00 | 1.45 | 1.85 | 2.25 | 2.70 | 3.10 |

**Source duration (story tiers):** + **0.10** credits (≤1080p30 band) or + **0.05** (other bands) per extra source hour
per angle above 60 minutes. For story tiers, a longer match adds mostly proxy upload and sync, not film. An additive
term fits the cost shape: the multiplicative fit (§4.7) overcharged by a median 1.6–2.3×.

**Full match angle multiplier:** 1.00 · 1.20 · 1.40 · 1.60 · 1.75 · 1.95 (1–6 angles). Full is already priced per
source hour.

**Planning add-on (credits; 1 angle; source ≤ 60 min):**

| Film length | 3 | 5 | 10 | 15 | 20 | 25 | 30 | Full |
|---|---|---|---|---|---|---|---|---|
| PL | 2.0 | 2.3 | 3.1 | 3.9 | 4.8 | 5.6 | 6.4 | 6.4 |

Planning angle multiplier 1.00 · 1.10 · 1.15 · 1.20 · 1.25 · 1.30 (1–6 angles; frames grow sub-linearly). Planning
source multiplier 1.00 · 1.10 · 1.15 · 1.20 (≤ 60 · ≤ 120 · ≤ 180 · ≤ 240 min). Planning is the same for every quality
column, because frames are sampled at 640×360 whatever the capture.

**Equivalent multipliers (for the "what drives the price" panel; 10-minute 1080p30 film, planning on, INFERRED):**
source 60 → 120 → 180 → 240 min = ×1.00 → 1.10 → 1.16 → 1.22 (5 → 5 → 5 → 6 credits). Angles 1 → 6 = ×1.00 → 1.21 →
1.38 → 1.55 → 1.73 → 1.90 (5 → 5 → 6 → 7 → 8 → 8 credits).

### 4.5 The price grid players would see (credits after rounding; 1 angle; 60-minute source; Sample)

Planning **on** / **off**:

| Film length | SD | HD | 1080p30 | 1080p60 | 1080p120 | 4K30 | 4K60 | 4K30 → 1080p | 4K60 → 1080p60 |
|---|---|---|---|---|---|---|---|---|---|
| 3 min | 3 / 1 | 3 / 1 | 3 / 1 | 3 / 1 | 3 / 1 | 3 / 1 | 4 / 2 | 3 / 1 | 4 / 2 |
| 5 min | 3 / 1 | 4 / 1 | 4 / 1 | 4 / 1 | 4 / 2 | 4 / 2 | 5 / 3 | 4 / 1 | 4 / 2 |
| 10 min | 4 / 1 | 4 / 1 | 5 / 1 | 5 / 2 | 5 / 2 | 6 / 3 | 7 / 4 | 5 / 2 | 6 / 3 |
| 15 min | 5 / 1 | 5 / 1 | 6 / 2 | 6 / 2 | 7 / 3 | 7 / 4 | 10 / 6 | 6 / 3 | 8 / 4 |
| 20 min | 6 / 1 | 6 / 2 | 7 / 2 | 7 / 3 | 8 / 3 | 9 / 4 | 12 / 7 | 8 / 3 | 10 / 5 |
| 25 min | 7 / 1 | 7 / 2 | 8 / 2 | 9 / 3 | 10 / 4 | 11 / 5 | 15 / 9 | 9 / 4 | 11 / 6 |
| 30 min | 8 / 1 | 8 / 2 | 9 / 3 | 10 / 4 | 11 / 5 | 13 / 6 | 17 / 10 | 11 / 4 | 13 / 7 |
| Full (60 min) | 8 / 2 | 9 / 2 | 10 / 3 | 11 / 4 | 11 / 5 | 11 / 5 | 12 / 6 | 10 / 4 | 12 / 6 |

### 4.6 Verification (INFERRED, script-checked)

| Mode | Cells | Violations | Design margin min / median | Cap contribution min | Credits range | Overcharge vs required, median / max |
|---|---|---|---|---|---|---|
| Rules-planned, story tiers | 1,512 | 0 | 32% / 63% | $0.00 | 1–32 | 1.48× / 4.41× |
| Rules-planned, Full | 216 | 0 | 45% / 60% | $0.17 | 2–42 | 1.31× / 2.27× |
| Cloud-planned, story tiers | 1,512 | 0 | 44% / 57% | $0.03 | 3–42 | 1.26× / 2.02× |
| Cloud-planned, Full | 216 | 0 | 50% / 57% | $0.37 | 8–52 | 1.21× / 1.57× |

Each cell was checked at $1.80 and $2.00 per credit. "Overcharge" is the formula's credits divided by the minimum
credits the two constraints require. The largest overcharges are rules-planned 1-credit films, where rounding up to a
whole credit dominates.

### 4.7 Alternatives tested and rejected

- **One multiplicative matrix** (tier × quality, then × angle × source multiplier, planning folded in): safe, but it
  compounds. A 15-minute 4K60 six-angle job came out at 46 credits against a $27.90 cap. Median overcharge was 2.33×
  (rules) and 1.62× (model).
- **Additive source term for Full:** overshot up to 14.6× on short Full matches. Per-source-hour pricing fits Full.
- **The dearest role assignment in every cap** (Astra drafting): doubles every price to protect a configuration that
  should be a re-quote instead.

---

## 5. Worked examples (Sample; INFERRED)

Planning off / on. Price at $1.80–$2.00 per credit. "Design margin" is at $1.80. "Cap contribution" is the worst
case, at $1.80.

| | Job | Credits | Price | Design cost | Cap cost | Design margin | Cap contribution | Upload (20 Mbps) |
|---|---|---|---|---|---|---|---|---|
| A | Quick share: 3 min · 1080p30 · 1 phone · 1 h | 1 / 3 | $1.80–$2.00 / $5.40–$6.00 | $0.12 / $1.01 | $0.33 / $2.95 | 43% / 48% | $0.57 / $0.65 | 1.6 GB (11 min) |
| B | **"ESPN-style" extended: 10 min · 1080p60 · 3 phones · 2 h** | 4 / 8 | $7.20–$8.00 / $14.40–$16.00 | $0.51 / $2.19 | $2.38 / $7.09 | 62% / 57% | $2.57 / $3.26 | 10.3 GB (69 min) |
| C | Slow-replay cut: 10 min · 1080p120 · 2 phones · 2 h | 3 / 7 | $5.40–$6.00 / $12.60–$14.00 | $0.51 / $2.06 | $2.76 / $7.28 | 57% / 55% | $0.84 / $1.72 | 8.8 GB (59 min) |
| D | Long extended: 30 min · 1080p30 · 1 phone · 2 h | 3 / 10 | $5.40–$6.00 / $18.00–$20.00 | $0.88 / $3.67 | $2.33 / $11.03 | 50% / 52% | $1.27 / $2.02 | 5.4 GB (36 min) |
| E | Full match: 1080p30 · 1 phone · 2 h | 6 / 13 | $10.80–$12.00 / $23.40–$26.00 | $2.06 / $4.84 | $6.49 / $15.20 | 52% / 52% | $1.16 / $1.90 | 9.2 GB (61 min) |
| F | Club final, Full: 1080p60 · 4 phones · 3 h | 19 / 28 | $34.20–$38.00 / $50.40–$56.00 | $4.90 / $8.44 | $18.30 / $28.30 | 59% / 57% | $6.90 / $9.05 | 45.4 GB (5 h) |
| G | 4K showcase: 15 min · 4K60 · 6 phones · 3 h | 18 / 23 | $32.40–$36.00 / $41.40–$46.00 | $2.96 / $5.54 | $21.11 / $27.90 | 64% / 61% | $2.74 / $2.70 | 48.3 GB (5.4 h) |
| H | Same as G, 1080p60 film | 15 / 21 | $27.00–$30.00 / $37.80–$42.00 | $1.21 / $3.79 | $18.06 / $24.85 | 69% / 64% | $1.74 / $3.05 | 48.3 GB ¹ |
| I | Old SD match: 20 min · SD · 1 phone · 1 h | 1 / 6 | $1.80–$2.00 / $10.80–$12.00 | $0.19 / $2.24 | $0.48 / $6.83 | 39% / 50% | $0.42 / $0.82 | 1.1 GB (8 min) |
| J | Largest story cell: 30 min · 4K60 · 6 phones · 4 h | 32 / 42 | $57.60–$64.00 / $75.60–$84.00 | $5.77 / $9.84 | $41.72 / $52.62 | 64% / 61% | $1.03 / $3.63 | 80.4 GB |
| K | Largest Full cell: 4K60 capture · 6 phones · 4 h | 42 / 52 | $75.60–$84.00 / $93.60–$104.00 | $9.93 / $14.00 | $53.17 / $64.07 | 61% / 60% | $3.08 / $5.68 | 263 GB ² |
| S | The ST37 / 57 Sample job: 5 min · 1080p30 · 3 phones · 1 h | 2 / 5 | $3.60–$4.00 / $9.00–$10.00 | $0.21 / $1.42 | $0.79 / $4.15 | 57% / 54% | $1.46 / $2.15 | 4.8 GB (32 min) |

¹ With the downscale-before-upload lever (§3.5) this falls to about 15 GB. ² The policy and lever matter most here: a
Full film renders at 1080p, so the phones should not upload 4K bytes for it.

Breakdown of B with planning on, as the "What sets the price" panel would show it: length and quality 1.3 (10 min,
1080p60) × angles 2.30 (3 phones) = 2.99; + source minutes 0.05 × 3 × 1 extra hour = 0.15; + story planning 3.1 ×
1.15 × 1.10 = 3.92. Total 7.06, rounded up to **8 credits**.

**The Sample fixture.** `quote.sample-illustrative.json` shows "$4 – $8, limit $12" for a 5-minute, three-angle,
model-planned job. Under v2 the same job is **5 credits** ($9.00–$10.00). The fixture's dollar figures are
illustrative and already labelled Sample, so nothing is wrong today. When the Studio contracts move to v2 (owned by
the Studio contracts workflow; not edited here), the recommendation is a Sample quote of **"5 credits · most it can
cost: 5 credits"** with no dollars (§8.5).

---

## 6. Sensitivities (INFERRED)

| Change | Effect on the matrix |
|---|---|
| **Benchmarks narrow render uncertainty from ×2.5 to ×1.3** | Production base falls most at 4K: 30-min 4K60 10.0 → 6.8; 30-min 1080p30 2.1 → 1.7; 3-min 4K60 1.4 → 1.2. Full 4K60 per source hour about 5.3 → 4.0. In the unbanded fit, the six-angle production multiplier falls from 4.20 to 3.85. Planning is unchanged |
| Planner cap tightened to about 1.8× design (from about 2.8×) after usage logs | Planning add-on falls by roughly a third (for example, the 10-min PL 3.1 → about 2.0) |
| Batch API for planning (non-interactive "you can leave this screen" jobs) | Planner cost halves in both design and cap (OBSERVED 50% discount for both providers); planning add-on about halves; turnaround becomes hours, not minutes |
| GPT-6 Astra as critic (Opus drafts); single-matrix fit | Planning-on prices rise by about 1 credit per cell (3-min 1080p30: 3 → 4; 30-min 4K60: 17 → 19) |
| GPT-6 Astra drafts, Opus critiques; single-matrix fit | Planning-on prices about double at short lengths (3-min: 3 → 6; 30-min 1080p30: 9 → 18) |
| `inference_geo: "us"` on Anthropic calls (×1.1) | About +0 to +1 credit per cell, mostly at 4K and long tiers |
| Fixed $0.80 per-credit internal budget (v1 rule) instead of a per-job cap | About 1.7× credits wherever the cap binds (nearly every cell); median design margin rises from about 60% to about 66% |
| Price per credit $2.00 instead of $1.80 | Each cell gains up to about 4–5 design-margin points; the matrix can stay as is |

---

## 7. Competitor anchors

| Offer | Unit | Price | Per source hour | Label |
|---|---|---|---|---|
| **Human highlight editor** ("ESPN-style" reel by hand) | Per reel | $20–$75 for 1–3 min mixes; $50 for a 30–45 s reel; $50–$250+ per match; $200–$800 recruiting packages | n/a | UNVERIFIED (Fiverr and vendor pages via search; v1 §2.3) |
| **Hudl Assist** (human-tagged breakdowns) | Per team per season | $250–$1,700 (football) | n/a | OBSERVED in v1 |
| **Hudl Balltime** (AI downtime removal, highlight reels, "AI-generated Recruiting Videos") | Subscription | Player **$20/mo, 15 h/mo**; Recruiting **$25/mo billed $299/yr, 200 h/yr**; Team on request | $1.33 · $1.50 | OBSERVED today (hudl.com/pricing/balltime) |
| **Veo** (camera) / **Veo Go** (2–3 iPhones, stitched panorama) | Subscription | Starter $149/mo (10 rec h) … Club $255/mo; Veo Go **$40/mo, 20 rec h** | Veo Go $2.00 | Plans and hours OBSERVED today; amounts OBSERVED in v1 (rendered) |
| **PB Vision** (pickleball; per-minute) | Minutes of processed video | $19.99 / 100 min; $49.99 / 400 min; annual $99.99 / 1,200 min; $396 / 4,800 min | $12.00 · $7.50 · $5.00 · $4.95 | OBSERVED in v1 (rendered) |
| **SwingVision** (tennis; tiers by hours, 4K on Max) | Subscription | Plus $95.99/yr (16 h/mo); Pro $179.99/yr (30 h); **Max $299.99/yr (60 h, 4K, family)** | $0.42–$0.50 (allowance; mostly on device) | OBSERVED in v1 (rendered) |
| **OpusClip** (AI clip editor) | Credits | Starter $15/mo; Pro $29/mo | $2.90–$6.00 if 1 credit = 1 min | Plan prices OBSERVED today; credit definition UNVERIFIED |
| **JOVRA v2, rules-planned** | Credits | 10-min 3-phone ESPN-style cut over 2 h: 4 credits | **$1.20–$1.33** per angle-hour | INFERRED (Sample) |
| **JOVRA v2, cloud-planned** | Credits | Same job: 8 credits; Full 2 h, 1 phone: 13 credits | **$2.40–$2.67** per angle-hour; Full **$11.70–$13.00** per hour | INFERRED (Sample) |

**What the anchors say (INFERRED).**

- **Story tiers are well placed.** They sit between creator tools ($3–$6 per hour) and per-minute sports AI
  ($5–$12 per hour), and far below a human editor, while producing an edited film with data and metrics.
- **Full match plus cloud planning is the expensive outlier per hour,** because the planning add-on is sized for 30
  planned minutes. Since Full's cuts are rule-based chronology (C14), the case to benchmark first is a cheaper
  Full-specific planning add-on covering chapters, replays and titles only.
- **Quality tiers have precedent.** SwingVision gates 4K to its top tier, and Smashpoint markets 4K60 critical-point
  replays (v1 §2.2). Pricing by quality is familiar to tennis players. Pricing by angle is not: no competitor found
  sells 1–6 phone angles cut into a story.

---

## 8. Quote UX for ST37 (iOS) and screen 57 (Android)

Both screens keep ST37's contract (`docs/spec/studio-screens.md` ST37): summary card, QuoteCard, rows, consent
checkbox, "Create film" disabled until a valid quote and consent, and "Use local replay" always present. v2 changes
what the QuoteCard says and adds one expandable panel. Copy follows Studio copy rules §0.2: no provider names in the
normal flow, Sample in demo and test, and no amount shown as a price until the pricing ADR.

### 8.1 Simple path (default, one screen)

1. **Film summary card:** story profile, "10 min · 3 angles", thumbnail. Tapping it changes the story.
2. **Length chips:** `3 · 5 · 10 · 15 · 20 · 25 · 30 min · Full match`. The current tier is selected. Unavailable tiers
   stay visible but disabled, with a reason in the hint ("Longer than this match's play").
3. **QuoteCard.** Kicker "Sample quote" or "Quote · expires in 28 min". **Today (shipped contract):** "2–4 credits"
   and "Spending limit · 4 credits" (`estimate` and `capCredits`), as A57 and ST37 render it. **Recommended (pending
   §10 Q1):** one figure **"8 credits"** with **"Most it can cost: 8 credits"**; the contract then sets min = max =
   cap and the same card shows one number with no other change. Never a dollar range. **After the pricing ADR only**
   (no purchase flow before it, ADR-0013): a third line "You have 12 credits", or "You need 3 more credits" plus "Get
   credits".
4. Rows as in ST37: "Cloud processing · Private upload" (bytes and upload time), "Plan the story in the cloud"
   (toggle, off by default), "Temporary media · Delete after 7 days", "Finished film · Kept until you delete it"
   (subtitle: "Cloud copy included for 12 months", if Jon adopts C8).
5. **Consent checkbox**, then **"Create film"** and **"Use local replay"**.

### 8.2 "What sets the price" (expandable; live recalculation)

Below the QuoteCard is a disclosure row, "What sets the price". Expanded, it shows five driver rows, each with its
current value, its share in credits and a control:

| Driver | Control | Shown value | Credit share (B) |
|---|---|---|---|
| Film length | The length chips (moved here when expanded) | "10 min (extended highlights)" | 1.3 base (with quality) |
| Quality | Read-only "Captured as 1080p60" + a **Film quality** picker for 4K captures: "4K" / "1080p" | "1080p60 · 3 phones" | in base |
| Angles | Per-angle switches (each camera's thumbnail; at least one) | "3 angles" | ×2.30 → 2.99 |
| Source minutes | Read-only (from the sync map): "2 h 4 min of match, each angle" | "2 h 4 min" | +0.15 |
| Story planning | The same toggle as the row above, mirrored | "Planned on iPhone (free)" or "Planned in the cloud" | +3.92 |

**Live recalculation rule.** The app computes an instant preview from a **versioned price table** shipped as a contract
(`pricing-matrix.v2.json`, proposed for `spec/studio/contracts/`, owned by the Studio contracts workflow). The preview is
labelled "Updating quote…" until the server returns the authoritative quote, debounced at about 400 ms. Prices from the
client are never authoritative (ADR-0019). "Create film" binds only the server's `priceCredits`. If the server differs
from the preview, the server wins and the card animates nothing (see Reduce Motion). Changing any driver clears consent
and starts a new quote, because the output-spec hash changes.

**What each driver's explainer says** (an info button per row opens a sheet; copy proposals):

- **Length:** "Longer films need more planning and more rendering. 'Full match' keeps every point in order, with the
  waiting time trimmed."
- **Quality:** "Your film can't be sharper than what your cameras recorded. A 1080p recording makes a great 1080p film.
  Choosing 4K for it would add size, not detail, so JOVRA doesn't offer it." For 4K captures: "A 4K film keeps the
  detail your cameras captured. A 1080p film from the same video is smaller, faster to upload and costs less."
- **120 fps:** "Recording at 120 frames per second lets JOVRA show clean slow-motion replays, up to ¼ speed in a
  standard film, with every frame real. It doesn't make normal-speed video sharper." The rule is the film engine's
  clean-frame rule: speed *s* is allowed only when `sourceFPS × s ≥ outputFPS` (`film-engine.md`, OBSERVED). So 60 fps
  gives ½-speed replays in a 30 fps film, and 120 fps gives ¼-speed in a 30 fps film or ½-speed in a 60 fps film.
- **Angles:** "Each extra phone adds its video to prepare and gives the film more replay angles."
- **Source minutes:** "Longer matches add a little for preparing and lining up every camera. The film length matters
  more."
- **Story planning:** "Off: your phone's rules plan the story, as in a local film. On: two planning services write the
  story from your points and sampled frames, one drafting and one reviewing, then JOVRA checks it before anything is
  rendered." The A5 consent detail names **both** services (the quote's bound drafter–critic pair, §8.6) and each one's
  retention, only when this is on (copy rule 5), and the player consents to both.

**Never in this panel:** dollars, model or vendor names, token counts, "GPU", or any claim that 4K or 120 fps "improves"
analysis or line calls (hard rule 1).

### 8.3 States (additions to ST37's table)

| State | Treatment |
|---|---|
| **Sample (demo, test, any build before the pricing ADR)** | Kicker "Sample quote"; figure "5 credits" with a `ProvenanceBadge(.sample)`; footnote "Sample pricing. Real prices appear here once they're set." Create runs the demo job: "Demo mode does not upload or charge." The breakdown still recalculates, also labelled Sample |
| Not enough credits (**after the pricing ADR only**; no purchase flow exists in v1) | Figure stays. Helper "You need 3 more credits." `.jovraAccent` "Get credits" opens the credit-pack sheet (store-localized prices). Create stays disabled |
| Tier unavailable | Chip disabled with a hint; never removed, so the layout doesn't jump |
| 4K film not available for Full | Film quality picker shows "Full match films are made in 1080p" |
| Whole-recording preparation needed (§3.6 policy 2) | QuoteCard attention: "Your phone's copies need preparing in the cloud." Separate line "+N credits"; new consent |
| Quote above a player-set limit | ST37's "The estimate is above your limit." remains; actions "Change limit", "Choose fewer angles", "Shorter film" |
| Updating | Figure dimmed with "Updating quote…"; Create disabled; no spinner over the number |

### 8.4 Accessibility (Studio §0.4 plus)

- The QuoteCard reads as one element: "Sample quote. 8 credits. Most it can cost, 8 credits. You have 12 credits." It
  never says "cr", "8c" or a bare number.
- Recalculation is announced politely after the server confirms, not on every chip tap: iOS
  `AccessibilityNotification.Announcement("Price updated, 8 credits")`; Android `liveRegion = LiveRegionMode.Polite` on
  the figure.
- Length chips: `.isSelected` trait / `Role.RadioButton`, with selection shown by fill + check + weight, never colour
  alone. At AX5 / 200% font scale, chips wrap to two rows and breakdown rows stack label over value.
- Reduce Motion / "Remove animations": no rolling-number animation; the figure swaps.
- Targets: 44 pt (iOS) and 48 dp (Android) for chips, toggles, the checkbox and info buttons.
- The disabled "Create film" explains why in its hint: "Tick the box to upload these videos", "You need 3 more
  credits" or "Quote is updating".
- Driver explainers are plain text, not tooltips, so screen readers and Switch Control reach them.

### 8.5 Platform notes

- **iOS (ST37):** the breakdown is an inline `DisclosureGroup` on iPhone. On iPad, the summary and QuoteCard sit side by
  side (ST37 spec), with the breakdown under the QuoteCard. Credit packs use StoreKit consumables with localized prices.
  The quote never prints a currency (App Store 3.1.1: purchased credits never expire, OBSERVED in v1). StoreKit
  credit packs are a post-pricing-ADR design; v1 ships no purchase flow (ADR-0013, D2).
- **Android (screen 57, "Android processing quote"):** Material 3. Length via `SingleChoiceSegmentedButtonRow` on
  expanded widths and `FilterChip`s in a `FlowRow` on compact widths. The breakdown opens as a `ModalBottomSheet`
  (screen 57's "native Material bottom sheet"). "Plan the story in the cloud" is a `Switch`, consent a `Checkbox`, and
  "Create film" a filled `Button` disabled until valid. On tablets and unfolded foldables, use a two-pane list-detail
  layout (summary | quote) with the pane boundary off the hinge (`WindowInfoTracker` folding features). After the pricing ADR,
  credit packs would use Play Billing with localized prices; in v1 Play Billing is not a dependency
  (android-v1-spec AD4) and no purchase flow exists. The quote itself is a full screen and the breakdown is the modal
  bottom sheet (`adaptive-screens.md` A57).
- **Watch companions:** no pricing, quote, consent or job surface. The watch has exactly five surfaces (ADR-0026,
  watch spec); quotes, consent and job progress stay on the phone.

### 8.6 Quote contract additions (recommendations to the Studio contracts owner; not edited here)

The quote's `lineItems` already carry `sourceCount`, `uploadBytes`, `storageDays`, `outputSeconds`,
`renderMinutesEstimate` and `plannerTokensEstimate` (`spec/studio/fixtures/records/quote.sample-illustrative.json`,
OBSERVED). v2 needs:

- **Drivers:** `lengthTier` (`3|5|10|15|20|25|30|full`), `captureQualityClass` (seven classes), `filmQuality`
  (resolution and fps; ≤ capture), `angleCount`, `sourceSeconds` (per-angle maximum), `priceTableVersion`.
- **Price and breakdown:** `priceCredits`, and `breakdown { baseCredits, angleMultiplier, sourceCredits,
  planningCredits }` (decimals before the final ceil, so the panel's numbers add up).
- **Internal cap:** `internalCostCapMicroUsd` (the computed cap cost), with the invariant `internalCostCapMicroUsd ≤
  priceCredits × netPerCredit − fixedShare`.
- **Planner binding:** `plannerPair` (drafter and critic roles, as configuration ids), so a pair change is a new
  output-spec hash and a re-quote.
- **Per-provider consent:** the shipped `consent.modelProvider` is one boolean, but cloud planning sends frames and
  point events to two processors. Recommended: `consent.planningProviders[]` (one entry per bound provider: configured
  display name, role, retention text version, accepted) so the consent names and records each. Until this lands, the
  cloud-planning state of the quote does not ship (F-QUOTE-CONSENT).
- **Supersede the v1 class minimums.** `credit-classes.v1.json` (story-1 = 2 … broadcast-4-6 = 8) and its
  `capCredits = max(classMinimum, ceil(cost / 800 000 µUSD))` rule do not fit length tiers. v2's floor is 1 credit for
  rules-planned and 3 for cloud-planned.

---

## 9. Recommended wording changes to ADR-0023 (do not edit the ADR here)

1. **Quality classes.** "SD, HD/1080p30, 1080p60, 1080p120, UHD/4K30, 4K60" merges HD 720p into 1080p30 and drops a
   class Jon listed. Proposed: "capture quality in seven classes, **SD 480p30, HD 720p30, 1080p30, 1080p60, 1080p120,
   4K30 and 4K60**, and the chosen film quality, which is never above the capture quality."
2. **Name the missing drivers.** Add "and by the **number of angles (1–6)**", which Jon's model and the task include
   but the ADR omits. Add "and by whether the story is **planned in the cloud** (an opt-in add-on; rules planning is
   the free default)".
3. **Define Full match.** "Full match: every point in chronological order with dead time trimmed, priced per source
   hour, rendered at up to 1080p60" (if Jon accepts §3.6 policy 1).
4. **Bind the provider pair in the quote.** "Each quote binds one drafter–critic assignment. A different pair or role
   assignment is a new quote, never an automatic escalation (ADR-0019). The cap is computed from that pair's prices
   and each call's `max_tokens`." The default is Opus 5.5 drafting with GPT-6.1 Sol critiquing. GPT-6 Astra costs 5×
   Sol per token (OBSERVED), so it is an explicit option, not the default.
5. **Model naming.** Keep "exact model ids are configuration". Note that OpenAI's pricing page lists GPT-6 Astra,
   GPT-6 Sol and GPT-6.1 Sol (OBSERVED 2026-10-07), so "GPT-6 Astra / GPT-6.1 Sol" is accurate as display names.
6. **One number for the player.** "A quote shows one price in credits, which is also its cap. JOVRA absorbs cost
   variance up to the internal cost cap. Anything beyond it is a new, consented quote." This replaces the estimate
   range plus separate cap in the UI, though the ledger keeps both fields.
7. **The internal budget.** Point ADR-0019's fixed "$0.80 per credit" to a per-job computed cap with the invariant in
   §8.6. (ADR-0019 is outside this task, so this is a recommendation to its owner.)
8. **The Remotion sentence** is consistent with the licence: free for organisations with **up to three employees**
   (OBSERVED in v1 §3.4). Jon's question was whether more people or fewer people qualify. Fewer: a one-person company
   qualifies, and a fourth employee would require a Company License (Automators $0.01 per render, $100/month minimum).
   Add "re-check whether hosted renders for paying users count as Automator use (UNVERIFIED in v1)".

---

## 10. Open questions and evidence gates

Decisions for Jon:

1. Is **one number, the price equal to the cap**, the right player promise, or should the card show an estimate range
   below a cap?
2. Should **Full match render at most 1080p60** (§3.6, policy 1)?
3. **Cloud film retention (D-3):** include 12 months in the price, then move to Infrequent Access or remind the player
   to download? Or charge a yearly storage credit for films over a size threshold?
4. **The provider pair:** Opus 5.5 drafting with GPT-6.1 Sol critiquing as the default? Is GPT-6 Astra a "premium
   planning" choice at a higher price, or only an internal fallback?
5. Should there be a **"ready later" (Batch) option** that roughly halves the planning add-on?
6. Should the price **per credit** stay at about $2 ($1.80 in the 25-pack)? Every margin here is tested at $1.80.

Benchmarks that replace assumptions (extend v1 §8):

| Measure | Replaces | Expected effect |
|---|---|---|
| Render wall time per output minute at 1080p30/60 and 4K30/60 on a 4-vCPU container, with overlays and full-decode verification | C9 and the ×2.5 uncertainty | 4K prices fall about 30% (§6) |
| Planner `usage` per tier (3–30 and Full) and per angle count, for both providers, including repair rate | C11–C13 | Planning add-on falls by up to a third |
| Real capture bitrates per class on 3+ iPhones and 3+ Android phones (CameraX), including 1080p120 | C2 and its ×2 cap factor | Upload and cap compute narrow |
| Phone proxy and window acceptance rate (constant frame rate, dimensions, rotation) | §3.6 policy 2 frequency | Whether whole-recording re-quotes are rare |
| Live-play share of real matches | C15 | Full output length and tier availability |
| Film sizes per story profile and quality | C4, C5 | Library cost per film |

Evidence status: every number in §§3–6 is **INFERRED** from the stated assumptions. No benchmark has run, and no
matrix cell is verified against a real job. The only verified claim is the script check that the formula meets both
constraints for the modelled costs (§4.6).

---


## 11. Review findings (2026-10-07)

A review of this document against `adaptive-screens.md` A57, `android-v1-spec.md`, ADR-0013, ADR-0023 and the watch
spec raised these findings. Each was checked against the cited text:

- **Three incompatible quote screens; the price toggle only in research** (HIGH): confirmed. §8.1 now separates the
  shipped range + cap from the recommended single number (Jon's §10 Q1), and A57 and the Android spec render the same
  screen with the drivers in a modal bottom sheet.
- **"Get credits", "You have 12 credits" and Play Billing as v1 features** (HIGH): confirmed; marked post-pricing-ADR
  only (§0 item 8, §8.1, §8.3, §8.5).
- **Dual-provider consent** (MEDIUM): confirmed; §8.2 and §8.6 now name both providers and recommend per-provider
  consent fields (F-QUOTE-CONSENT for the contract owner).
- **"9 quality columns" vs seven-column tables** (MEDIUM, part): **partly rejected.** §4.3 does have nine columns (the
  seven capture classes plus two downscale columns), so §0 was not wrong; the wording was unclear and now says so.
  §3.2 and §3.3 show seven because they price capture classes only.
- **No class for 240 fps or HDR; the output axis under-specified in ADR-0023** (MEDIUM): confirmed; §3.7 proposes the
  pixel-rate rule and the HDR rule; the ADR-0023 wording is outside this document (F-ADR-0023).
- **"A watch shows job progress only (watch skill)"** (LOW): confirmed unsupported (the watch skill, ADR-0026 and the
  watch spec define five surfaces and no job surface); removed (§8.5).

## Sources

Primary (fetched 2026-10-07):

- Anthropic pricing: https://platform.claude.com/docs/en/about-claude/pricing
- OpenAI API pricing (GPT-6 Astra, GPT-6 Sol, GPT-6.1 Sol; Batch, Flex, 272k long-context threshold): https://developers.openai.com/api/docs/pricing
- Cloudflare R2 pricing: https://developers.cloudflare.com/r2/pricing/
- Cloudflare Containers pricing: https://developers.cloudflare.com/containers/pricing/
- Modal pricing: https://modal.com/pricing
- Google Play service fees: https://support.google.com/googleplay/android-developer/answer/112622
- YouTube recommended upload encoding settings: https://support.google.com/youtube/answer/1722171
- Hudl Balltime pricing: https://www.hudl.com/pricing/balltime
- Veo pricing (plan names and hours; amounts not in fetched text): https://www.veo.com/pricing
- OpusClip pricing (plan prices; credit definition not in fetched text): https://www.opus.pro/pricing

Cited from v1 (rendered or fetched on the same day; not re-rendered here): PB Vision, SwingVision, Veo amounts, Hudl
Assist, Smashpoint, Remotion licence, Apple App Store Small Business Program and guideline 3.1.1. See
`docs/research/studio/pricing-and-premium.md` §§2–3 and its source list.

Secondary (UNVERIFIED):

- iPhone capture sizes per minute (iOS Settings text, as reported): https://www.videoproc.com/iphone-video-processing/iphone-video-size-per-minute.htm and https://thedigitalstory.com/2021/02/IPhone-Video-techniques-TDS-Podcast.html
- Human highlight editing prices: https://fiverr.com/vex12345/edit-your-sport-highlights , https://clipoutmedia.carrd.co/ , https://sophiecress.com/blog/cost-of-sports-clip-cuts
- GPT-6 family price summaries (cross-check only; the official page above is authoritative): https://anotherwrapper.com/tools/llm-pricing/gpt-6-astra , https://pricepertoken.com/pricing-page/model/openai-gpt-6-astra

Repository inputs (read-only):

- `/Users/IDC2.5/jv/docs/research/studio/pricing-and-premium.md` (v1 cost model, margins, levers, benchmarks)
- `/Users/IDC2.5/jv/docs/adr/0019-paid-cloud-production-is-opt-in.md`, `0023-dual-provider-planner-and-length-quality-pricing.md`
- `/Users/IDC2.5/jv/docs/spec/studio-screens.md` (ST37, §0.2 copy rules, §0.4 accessibility), `docs/spec/studio-v1-spec.md` (D-3, D-4, D-5)
- `/Users/IDC2.5/jv/design-reference/adaptive/brief/screen-specs.json` (screen 57), `visual-review.md`
- `/Users/IDC2.5/jv/spec/studio/contracts/credit-classes.v1.json`, `spec/studio/fixtures/records/quote.sample-illustrative.json`, `spec/studio/README.md`
- `/Users/IDC2.5/jv/docs/research/studio/film-engine.md` (clean-frame rule for slow replays)
- `/Users/IDC2.5/jv/docs/handoff/JON-ORIGINAL-PROMPT.md` (addendum item 1)
