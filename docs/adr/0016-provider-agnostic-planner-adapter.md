# One provider-neutral planner adapter: rules by default; Opus 5.5 only with the player's consent; Astra off until configured

Status: accepted (2026-10-07); amended 2026-10-07 after review: no model is the default planner until the fixture
comparison has run (spec story 248, SD18). The first title called `claude-opus-5-5` "the model default", which
contradicted that story. Amended again 2026-10-07 (review round 3, spec decision D-5): the rules planner is the
default; the Anthropic adapter runs only with the player's explicit per-job consent; the Astra adapter ships disabled
until a real model ID is configured.

Jon names two planners: Opus 5.5 through the Anthropic API, and GPT "Astra". Both sit behind one `PlannerProvider`
interface that runs **server-side only**, behind the gateway. No model API key ever ships in an app (CLAUDE.md
rule 5). The interface has two calls:

- `capabilities()` returns the pinned model ID, image limits, schema limits, batch and cache support, and a versioned
  price table.
- `plan(request)` returns `ok | refused | truncated | invalid` together with the story plan JSON, usage, request and
  response hashes, and latency.

There are three providers:

- **HeuristicProvider** (the spec's **RulesPlanner**; contract planner kind `heuristic`). A deterministic planner
  built from the story-profile grammar. It is the default planner everywhere, the S1 planner on the device, and the
  fallback whenever a model refuses, truncates, fails validation after one repair attempt, or is unavailable.
- **AnthropicMessagesProvider** (part of the spec's **ModelPlanner**). The one enabled model adapter:
  `claude-opus-5-5` at effort `medium`, using the Batch API for non-urgent films. It runs **only** for a job whose
  player switched on "Plan the story in the cloud" and gave explicit consent at quote acceptance
  (`consent.modelProvider = true`); otherwise the job's plan comes from the heuristic planner. It is never the default
  planner. Making any model the default would need the S4 comparison on shared fixtures (schema-valid rate, grounding
  precision, repair rate, cost, latency) against the heuristic planner, recorded as evidence, and still could not
  skip the per-job consent, because a model-planned story sends frames off the phone. OBSERVED 2026-10-07: $4/$20 per
  million tokens, $2/$10 on batch, 1M context, up to 600 images per request with no video input. Forced
  `tool_choice` is rejected, so the plan comes back through `output_config.format` JSON schema.
- **OpenAIResponsesProvider** (also under ModelPlanner). For "Astra". It ships **disabled with no model ID
  configured** and answers `unavailable` until the founder configures a real model ID that its `capabilities()` probe
  accepts. The research names OpenAI's GPT-6 Astra (`gpt-6-astra`, $10/$50 per million tokens, text and image input,
  no video; OBSERVED on the OpenAI model page), but Jon's API access, its structured-output limits and its image-token
  formula are UNVERIFIED, so no ID is assumed.

**Rules.**
- One shared JSON Schema fits both vendors' limits. All fields are required, `"none"` sentinels replace nullable
  unions, and enum values never differ only by case. Numeric bounds are enforced by our validator (ADR-0015), not by
  the vendor.
- The provider, model ID, effort and price-table version are configuration, pinned per job and written into every
  film revision's receipt. Nothing escalates automatically to a costlier model, a higher effort or more attempts.
- Evidence is bounded. The model sees point events, keeper IDs, sampled, ID-labelled frames (768×432 or contact
  sheets) and only the note text classes the owner consented to at quote acceptance (`consent.textClasses`:
  `ownerNotes`, `ownerLessonNotes`, `coachNotes`; default the first two). Coach-authored text (observation bodies,
  coach notes) belongs to another person and is excluded unless that class is named in the consent (amended
  2026-10-07, review round 2; `docs/backend/security-model.md` §12, §13.14). It never sees originals, R2 URLs or
  secrets, and frames go inline rather than through a persisted Files upload.
- Frames sent to a model provider are user media leaving the phone. That happens only after the explicit cloud
  consent on the preflight screen (ADR-0019) and the App Privacy review (ADR-0014 gate 5).

## Considered Options

- **Hard-wire one vendor.** Rejected. Jon asked for a choice, and vendor prices, limits and access change.
- **Call the model from the app with a user-supplied key.** Rejected. It puts secrets in the client and breaks the
  spend controls.
- **Treat the model as the planner of record with no heuristic fallback.** Rejected. A refusal or outage would block
  a film the device can already make.

## Consequences

S1 needs no model, account or network. Model planning is part of the paid, opt-in cloud line (spec D-4 and D-5, a
working default until Jon answers spec open question 9); until a
pricing ADR it is quoted only as a Sample quote. Model planning arrives with the S4 backend. Its quality is measured
by a planner evaluation (plan validity rate, repair rate, beats omitted) before any claim about it is made. No vendor
or model name appears in the normal player flow: the player sees "Plan the story in the cloud" and the consent copy
names the planning service and its retention, and each film's receipt names the planner that made it.

Sources: `docs/research/studio/film-engine.md` §§5.1–5.6; `docs/spec/studio-v1-spec.md` (D-4, D-5);
`docs/research/studio/pricing-and-premium.md` §§6, 8 (its "default the planner to Opus 5.5" recommendation is not
taken);
https://platform.claude.com/docs/en/build-with-claude/vision ;
https://platform.claude.com/docs/en/about-claude/pricing ;
https://platform.claude.com/docs/en/build-with-claude/structured-outputs ;
https://platform.claude.com/docs/en/build-with-claude/files ;
https://developers.openai.com/api/docs/models/gpt-6-astra ;
https://developers.openai.com/api/docs/guides/structured-outputs .
