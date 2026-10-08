# One provider-neutral planner adapter: heuristic by default; Opus 5.5 and Astra as model candidates, compared before either is the default

Status: accepted (2026-10-07); amended 2026-10-07 after review: no model is the default planner until the fixture
comparison has run (spec story 248, SD18). The first title called `claude-opus-5-5` "the model default", which
contradicted that story.

Jon names two planners: Opus 5.5 through the Anthropic API, and GPT "Astra". Both sit behind one `PlannerProvider`
interface that runs **server-side only**, behind the gateway. No model API key ever ships in an app (CLAUDE.md
rule 5). The interface has two calls:

- `capabilities()` returns the pinned model ID, image limits, schema limits, batch and cache support, and a versioned
  price table.
- `plan(request)` returns `ok | refused | truncated | invalid` together with the story plan JSON, usage, request and
  response hashes, and latency.

There are three providers:

- **HeuristicProvider** (the spec's **RulesPlanner**; contract planner kind `heuristic`). A deterministic planner
  built from the story-profile grammar. It is the default planner everywhere until a comparison says otherwise, the
  S1 planner on the device, and the fallback whenever a model refuses, truncates, fails validation after one repair
  attempt, or is unavailable.
- **AnthropicMessagesProvider** (part of the spec's **ModelPlanner**). The first model candidate is `claude-opus-5-5`
  at effort `medium`, using the Batch API for non-urgent films. It becomes the default model planner only after the S4
  comparison on shared fixtures (schema-valid rate, grounding precision, repair rate, cost, latency) against the
  heuristic planner and any verified Astra adapter, recorded as evidence. OBSERVED 2026-10-07: $4/$20 per million tokens, $2/$10 on batch, 1M context, up to 600
  images per request with no video input. Forced `tool_choice` is rejected, so the plan comes back through
  `output_config.format` JSON schema.
- **OpenAIResponsesProvider** (also under ModelPlanner). For "Astra", which we take to mean OpenAI's GPT-6 Astra (`gpt-6-astra`, $10/$50 per
  million tokens, text and image input, no video; OBSERVED on the OpenAI model page). It is **disabled until verified**:
  Jon's API access, its structured-output limits and its image-token formula are UNVERIFIED.

**Rules.**
- One shared JSON Schema fits both vendors' limits. All fields are required, `"none"` sentinels replace nullable
  unions, and enum values never differ only by case. Numeric bounds are enforced by our validator (ADR-0015), not by
  the vendor.
- The provider, model ID, effort and price-table version are configuration, pinned per job and written into every
  film revision's receipt. Nothing escalates automatically to a costlier model, a higher effort or more attempts.
- Evidence is bounded. The model sees point events, keeper IDs, sampled, ID-labelled frames (768×432 or contact
  sheets) and only the note text classes the owner consented to at quote acceptance (`consent.textClasses`, e.g.
  `ownerNotes`). Coach-authored text (observation bodies, coach notes) belongs to another person and is excluded
  unless that class is named in the consent (amended 2026-10-07, review round 2; `docs/backend/security-model.md`
  §12). It never sees originals, R2 URLs or secrets, and frames go inline rather than through
  a persisted Files upload.
- Frames sent to a model provider are user media leaving the phone. That happens only after the explicit cloud
  consent on the preflight screen (ADR-0019) and the App Privacy review (ADR-0014 gate 5).

## Considered Options

- **Hard-wire one vendor.** Rejected. Jon asked for a choice, and vendor prices, limits and access change.
- **Call the model from the app with a user-supplied key.** Rejected. It puts secrets in the client and breaks the
  spend controls.
- **Treat the model as the planner of record with no heuristic fallback.** Rejected. A refusal or outage would block
  a film the device can already make.

## Consequences

S1 needs no model, account or network. Model planning arrives with the S4 backend. Its quality is measured by a
planner evaluation (plan validity rate, repair rate, beats omitted) before any claim about it is made. Model choice is
never shown in the normal player flow unless it is a real choice for the user.

Sources: `docs/research/studio/film-engine.md` §§5.1–5.6;
https://platform.claude.com/docs/en/build-with-claude/vision ;
https://platform.claude.com/docs/en/about-claude/pricing ;
https://platform.claude.com/docs/en/build-with-claude/structured-outputs ;
https://platform.claude.com/docs/en/build-with-claude/files ;
https://developers.openai.com/api/docs/models/gpt-6-astra ;
https://developers.openai.com/api/docs/guides/structured-outputs .
