# Dual-provider film planner, and Studio pricing by story length and capture quality

Founder decision (Jon, 2026-10-07). The cloud film planner uses two providers that hand work back and forth:
Anthropic **Claude Opus 5.5** (`claude-opus-5-5`) and OpenAI **GPT-6 Astra** / **GPT-6.1 Sol**, both of which Jon's
organisations can access through their APIs. Exact OpenAI model ids are configuration, verified against each provider's
Models API at activation, never hardcoded. The handoff is a bounded, recorded pipeline: one provider drafts the
StoryPlan (IDs and fixed choices only, per ADR-0015) and the other critiques and refines it against the same evidence,
with a deterministic validator between every step and the renderer as the only executor. Both stay behind the
per-project consent of ADR-0016. The on-device rule-based planner remains the free default.

Studio films are priced in credits (ADR-0019) by the length of the finished story — **3, 5, 10, 15, 20, 25 and 30
minute** extended-highlight tiers (an "ESPN extended highlights" cut with data and metrics) plus **Full match** — scaled
by input duration and capture quality (SD, HD/1080p30, 1080p60, 1080p120, UHD/4K30, 4K60). Credit prices are set
only after the benchmarks in `docs/research/studio/pricing-and-premium.md` §8; until then every quote is Sample.

Remotion: IDC is a one-person company, which is under Remotion's three-employee threshold for its free licence
(re-check if the team grows beyond three or if Remotion's terms change).
