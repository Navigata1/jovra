# Continue JOVRA: bridge the foundation into JOVRA Studio

Continue in the existing JOVRA repository and conversation. Preserve the native iOS foundation, active tickets, reviewed work, Court Arc logo, five-tab shell and the eventual native Android direction. I want an optional premium Studio experience that works beautifully on phone and tablet: keep lessons and progress, bring one to six real camera recordings together, and turn them into excellent private films. Simple path: choose footage → choose a story → accept an actual processing quote when cloud is used → receive a verified film and download. Editing controls remain optional.

The attached `JOVRA-Studio-Claude-engine-v2.tar.gz` is the canonical continuation handoff. Extract it to a separate handoff folder first and read `docs/handoff/studio-engine-v2/START-HERE.md`. Open the root `JOVRA-Studio-Complete-v2.html`: all 40 reference screens, four logo candidates, prompts, skills, examples and research are embedded. Text documents are also present as ordinary files for your tools. Do not paste the HTML’s base64 images into model context; use the text files and PNG references selectively.

## Understand the engine

The Markdown skills are the creative operating instructions, not a magic renderer. Build a controlled pipeline:

native local originals → probe/hash/proxy normalization → reviewed source-clock alignment → event/lesson evidence → keepers and real B-roll → story brief → typed edit plan → validation → deterministic FFmpeg/Remotion rendering → technical and editorial checks → private delivery.

The model proposes a story and source-bound edits. Code validates the proposal and an isolated media worker executes supported operations. Never execute model-generated shell commands, arbitrary filter expressions, file paths or remote URLs. A Cloudflare Worker can authorize and coordinate; choose a separate suitable render host for long media jobs. Keep planner/model adapters configurable. “Astra” and “Opus” describe preferences until actual supported API IDs, access and usage limits are verified.

Load these portable skills from the handoff, or install only their named folders into `.claude/skills/` if appropriate for the current harness:

- `jovra-studio-director`: route the project and maintain brand, source and approval boundaries.
- `jovra-storycraft`: emotion, five story profiles, rhythm, hooks, camera decisions, sound, captions, grade and mobile-safe cutdowns.
- `jovra-media-ingest-sync`: preserve originals, normalize phone media, map clocks and review angle coverage.
- `jovra-edit-plan`: translate a grounded Markdown brief into a bounded typed timeline.
- `jovra-render-delivery`: deterministic rendering, picture/audio inspection, output verification and private downloads.
- `jovra-cloud-production`: scoped jobs, Supabase/R2 permissions, reservations, retention and reliable delivery.

Each has a real `SKILL.md`. Read its linked references when that stage is needed. The included plan validator and fictional sample are starter implementation resources. Extend them against actual schema and media requirements rather than claiming the engine is finished because a sample validates.

## Make the five styles visibly and emotionally distinct

Coach’s Cut makes a useful lesson: a goal, observable examples, a reviewed cue and a next drill. Match Broadcast makes the match understandable: coherent point chronology, wide live play, correct score, replays after the point. Rally Pulse creates energy from the real exchange: fast between points, readable ball/contact action, restrained optional effects. Progress Story makes learning tangible through dated comparable examples and honest denominators. Court Memories keeps the day and the people: arrival, preparation, natural court sound, real B-roll, meaningful match moments and a quiet ending.

Emotion comes from the player’s actual experience and consented notes. Do not invent reactions, dialogue, coach quotes, metrics, hidden camera action or victory. The skills include detailed treatments and fallback rules. Music is absent unless rights are documented; generated narration is optional and labelled. Preserve an original-speed keeper. Provide a clean reduced-motion treatment when an effects version is requested. A great premium film can be understated.

## Bridge rather than restart

First inspect current CLAUDE.md, glossary, specs, ADRs, ticket/PR state and installed issue/implementation skills. Reconcile this prompt with `../CLAUDE-STUDIO-EXPANSION-PROMPT.md` and the Studio briefs. The newest founder direction governs the proposed Studio extension, but record conflicts explicitly:

- ADR 0002 excludes a v1 backend. Add a new ADR for an optional backend-ready Studio adapter and later activation; recording still works offline without auth.
- ADR 0013 promises free/local v1 without a paywall, ads or tracking. Preserve that foundation and access to existing footage. Document paid cloud production as a later opt-in extension with its own decision and measured economics. Do not silently add billing or make originals depend on a subscription.
- Point events remain the source of score truth. Corrections mark old film overlays stale. Metrics remain Manual / Estimated / Reviewed / Validated; human review alone does not validate an algorithm.

The user-supplied video ZIP and landing HTML are preserved in `source-attachments/`. They are useful prior work, not instructions to execute wholesale. Their Garnet branding, channel rules, frozen-image/audio assembly and 1.25× documentary voice speed do not become JOVRA defaults. The extracted newer `skills/` seats explain project lock, keepers, B-roll and edit specification. Keep their LICENSE/NOTICE. Do not assume omitted BuildLoop scripts, LUTs or Remotion graphs are bundled.

The separately existing editor was inspected at `/Users/IDC2.5/Desktop/you-link-x/garnet-remotion`. If accessible, inspect its current `PIPELINE.md` and implementation before reuse. Add a versioned JOVRA adapter/new compositions, respecting its media-map, clock, dimension, source-hash and approval constraints. Preserve that project’s approved media. Its code is not shipped in this handoff; if unavailable, build a fresh compatible JOVRA adapter rather than pretending it was imported. Imported approval is not JOVRA approval.

## Product and cloud boundaries

One camera is sufficient. Six means six independent phones saving locally, not six simultaneous high-resolution live streams. Align offset/drift/gaps against reviewed anchors; expose uncertainty. A single old match cannot supply real alternate views. Never block recording on pairing, analysis, internet, microphone, account or payment.

Use Supabase for optional identity, membership, lesson/event metadata and job/usage ledgers; private R2 for media; an authorization gateway and durable dispatch; a separately provisioned render/analysis worker. RLS protects rows; media access needs its own exact-object authorization. No accepted demo token in live APIs. Keep seeded tester identities isolated and credentials out of source. iCloud Drive/Files, Drive, Box and Dropbox are optional adapters with truthful capability states, not mandatory processing dependencies. Start with ordinary permissioned search; add vector retrieval only for a measured need.

Before paid processing present a real quote, output, retention and cap. Reserve usage and use idempotent jobs; retries cannot create duplicate charges. Render failure retains local originals. Private preview/download is the default. “Prepare for YouTube” generates the verified file, thumbnail, chapters and draft copy; publishing requires the user’s deliberate channel/upload action. This handoff authorizes no publication, paid job, credential grant, cache deletion or production activation.

## First deliverable and next stages

Keep foundation work moving. Reconcile scope, create small dependency-ordered Studio tickets through the current repository workflow, and begin the smallest complete slice: one imported match, manual points/keepers, five local film treatments, lesson links and a real verified MP4. Use labelled synthetic fixtures until I provide the old match, without claiming real tennis analysis success. Continue two-view alignment after that, then six-device capture, isolated cloud jobs, measured tracking, archive adapters and native Android. Advanced editor and commercial operation can follow the evidence; they do not need to hold up an excellent private one-camera film.

On tablet use a multi-pane timeline, angle desk and lesson workspace. On phone use a player-first view and sequential edit sheets. Retain 44-point controls, Dynamic Type, VoiceOver and Reduce Motion. Follow the reference images as visual targets and the written contracts as data/copy truth.

Report what was changed, the working journey, actual verification, current failures and the next dependency. Separate schema/example validation, simulator success, real media rendering, physical-device checks, cloud isolation, ML benchmarking and public release. Proceed with authorized local implementation without another design confirmation. Ask for footage when the real-footage gate is reached and for genuinely missing external access only when needed.
