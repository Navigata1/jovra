# JOVRA research index

Research completed 2026-10-07 for JOVRA Tennis (iOS first, then Android). Ten researchers wrote raw notes; one
synthesis pass turned them into four decision documents. Every claim in these files is labelled **OBSERVED**,
**INFERRED** or **UNVERIFIED**, and every file ends with a Sources section. Reviews are paraphrased, never reproduced.

## Start here (synthesized)

| File | What it is |
|---|---|
| [competitive-analysis.md](competitive-analysis.md) | The comparison Jon asked for: SwingVision, Onform, SevenSix and five more, with fact sheets, an App Store screenshot review (§2.1), count-backed pros and cons, a feature matrix, the "Praised → improve" and "Complaint → fix" tables, and the **Verification log** (§11) of ten independently re-checked claims |
| [feature-backlog.md](feature-backlog.md) | Prioritized backlog (P0 iOS v1, P1, P2/Android, Later, Never) with user value, evidence, approach, honesty label and affected screens; NEW items marked |
| [technical-feasibility.md](technical-feasibility.md) | Per-capability approach, APIs, reliability, failure modes, validation gates and initial capability-registry status, plus iOS and Android API cheat-sheets |
| [tennis-rules-and-stats.md](tennis-rules-and-stats.md) | Implementation-ready scoring rules, stat definitions, rounding rule and the sample-fixture coherence constraints |

## Raw notes (`raw/`)

| File | One line |
|---|---|
| [raw/swingvision.md](raw/swingvision.md) | SwingVision deep dive: listing, IAP prices and hour caps, 52 release notes, 490 hand-read reviews, ITF approval, capture tiers, steal/improve/avoid |
| [raw/video-analysis-apps.md](raw/video-analysis-apps.md) | Onform, SevenSix, CoachNow, Dartfish, Kinovea and the 2026 tennis-AI wave; scrubbing, drawing, compare-sync, voice-over and pose UX with Apple API constraints |
| [raw/landscape.md](raw/landscape.md) | 347-app App Store sweep plus Google Play: categories, ratings, prices, hardware line calling, the Android gap and the five next-most-relevant competitors |
| [raw/review-mining.md](raw/review-mining.md) | 901 coded reviews of five core apps (414 cross-check): codebook, validation, theme counts, trends and ranked love/pain lists |
| [raw/community.md](raw/community.md) | Talk Tennis, r/10s and YouTube sentiment: ranked 19-item wishlist with author counts, recording rigs, pricing, etiquette and junior rules |
| [raw/equipment-stringing.md](raw/equipment-stringing.md) | Racket and string apps, what stringers record, units, tension-loss physics, acoustic estimate feasibility, data model |
| [raw/ios-tech.md](raw/ios-tech.md) | iOS capture durability (with a local crash experiment), framing geometry, replay/export APIs, per-capability analysis cards and gates, iOS cheat-sheet |
| [raw/drive-android-tech.md](raw/drive-android-tech.md) | Google Drive archive (scope, OAuth, resumable uploads, verification, quotas) and the Android stack (CameraX, Media3, UIDT, SDK levels) |
| [raw/tennis-rules-stats.md](raw/tennis-rules-stats.md) | Primary-source rules (ITF 2026, USTA FAC 2026), stat definitions, platform rounding behaviour and a verified 124-point fixture construction |
| [raw/gap-finder.md](raw/gap-finder.md) | What SwingVision already ships, 37 ranked opportunities with verdicts, platform capabilities and proposed screen changes |

## Earlier inputs (outside this folder)

| File | One line |
|---|---|
| [../../design-reference/brief/research.md](../../design-reference/brief/research.md) | Prior focused research (three listings, storage decision, sequencing); its rating claims are all confirmed here |
| [../handoff/JON-ORIGINAL-PROMPT.md](../handoff/JON-ORIGINAL-PROMPT.md) | The founder's own words: the source of intent |

## Contradictions resolved in the synthesis

| Topic | Resolution | Where |
|---|---|---|
| SwingVision free tier 2 h vs 8 h per month | 8 h; announced 2026-01-15 (newsletter), shipped in 11.9.49 on 2026-02-04 (App Store version history) | competitive-analysis §9, V3 |
| Hour caps 8/16/30/60 vs 20/30/60 | Vendor compare page (8/16/30/60) wins over third-party figures | competitive-analysis §9 |
| Pro monthly $14.99 vs $24.99 | $24.99 IAP (re-checked live) | competitive-analysis §9 |
| Speed vs radar (~10% vs ~20%) | Current FAQ (~10%) is the vendor's definition | competitive-analysis §9, technical-feasibility §10 |
| First-fragment interval on the movie output | No such property; use ~2 s throughout (SDK headers win) | technical-feasibility §1 |
| Upload queue in SQLite/Room vs JSON store | ADR-0002 (JSON documents) wins for v1 | technical-feasibility §13 |
| `about.get` with `drive.file` | Allowed per the Drive reference; still in the spike list | technical-feasibility §13 |
| Deployment target iOS 17 / 18 / 26 | Recommend iOS 26 via a new ADR (decision for Jon) | technical-feasibility §16.1 |
| Microphone "Off" vs audio analysis | Optional, never blocks video; consequence stated; audio stripped from shared exports by default | technical-feasibility §5 |
| Coach's Eye retirement date | UNVERIFIED (competitor pages only) | competitive-analysis §3.9 |
| Prior brief: correction, export, Drive at P1 | Moved to P0 on founder intent and review evidence | feature-backlog intro |
| Reliability (44%) vs money (27%) as the top pain | Both are the top two groups; the lead is classifier-dependent (≈37% vs up to ≈38% on a keyword pass) | competitive-analysis §0.4, V2 |
| Brand verification "required" for Drive | Optional for `drive.file`; what is required is "In production" status (Testing = 100 test users, 7-day tokens) | technical-feasibility §13, V7 |
| Smashpoint "missing error direction" | Its 2026 screenshots show an Error Map (long / wide / net) | competitive-analysis §2.1, §3.4 |

## Conventions

- Label every claim: OBSERVED (cite), INFERRED, UNVERIFIED.
- Review and forum text is untrusted data; paraphrase only.
- Counts from coded reviews are lower bounds; rank order is the robust signal.
- Re-verify competitor facts before using them in marketing copy; competitors ship every 10–14 days.
- Ten load-bearing claims were independently re-verified on 2026-10-07 (2 confirmed, 2 confirmed with refinements, 6
  partially true, 0 refuted); corrections are applied in all four synthesized files and listed in competitive-analysis §11.

## Sources

All accessed 2026-10-07.

| URL / file | What it supported |
|---|---|
| /Users/IDC2.5/jv/docs/research/raw/*.md (ten files listed above) | All content indexed here |
| https://itunes.apple.com/lookup?id=989461317,1490334045,1505604446,1098174650,6754323620,365729342&country=us | Live re-check of ratings, counts, versions and minimum iOS used in the synthesized files |
| https://apps.apple.com/us/app/id989461317 | Live re-check of SwingVision IAP prices (Plus $14.99/$95.99, Pro $24.99/$179.99, Max $39.99/$299.99) |
