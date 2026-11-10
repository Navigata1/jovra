# ADR-0031: Automatic analysis is in v1 as estimated capabilities, and iPhone ships first

Status: accepted by the founder on 2026-11-09. Supersedes decision D10 of `docs/spec/ios-v1-spec.md` where they
conflict. Context and evidence: [the 2026-11-09 reassessment](../reports/2026-11-09/REASSESSMENT.md).

## Context

D10 fixed the v1 analysis scope at manual tagging plus benchmark-gated audio hits. It marked ball tracking, automatic
stroke classification, automatic serve detection and speed, automatic bounce maps and AI point suggestions
`unsupported`. The founder's goal is an automatic tennis analysis app in the class of the commercial single-phone
products. Under D10, v1 could not meet that goal however well it was built.

Work was also open on four platforms, Studio and a backend at once, while most iPhone screens were placeholders.

## Decision

1. **Automatic analysis is in v1.** A new ticket track, V, builds an on-device analysis engine in stages:
   a labelled benchmark (V1), automatic court calibration (V2), player tracking and pose (V3), ball detection (V4),
   shot and rally detection (V5), stroke type (V6), placement and serve speed (V7).
2. **Every automatic result is `estimated`.** It is a suggestion the player can review and correct, stored separately
   from the correction (ADR-0003, ADR-0004). A capability moves from `disabled` to `estimated` in the registry only
   when its benchmark gate passes on held-out data. The gates in `docs/research/technical-feasibility.md` §0 stand.
   Reaching `validated` needs a separate, larger benchmark.
3. **Still unsupported:** officiating-grade line calls, spin RPM, 3D biomechanics, and any injury or medical claim.
   CLAUDE.md hard rule 1 is unchanged.
4. **Footage rules are unchanged.** The founder's recordings are labelled and measured locally. They are never
   committed, uploaded or sent to a model API (`docs/fixtures/real-footage.md`). Only hashes, label files without
   imagery, and aggregate metrics may enter the repository.
5. **iPhone first.** No new Android, Wear OS, watchOS or Studio ticket starts until the iPhone loop (setup,
   calibration, record, live scoring, replay, review, overview, export) and V1–V5 have passed a signed run on a
   physical iPhone. Open pull requests on those tracks stay open and are not closed by this decision. This restates
   ADR-0001's "port after the iOS gates".

## Consequences

- The registry entries D10 listed as `unsupported` for the capabilities in decision 1 become `disabled` until gated.
  That is a contract change and lands with the V-track ticket that first needs it, with shared fixtures.
- Capture guidance changes: ball detection needs 1080p at 60 fps or 4K, and a high mount behind the baseline.
  Recordings that do not meet it still save, play and score; analysis reports reduced coverage instead of guessing.
- Model weights and training data need a licence review before they enter the repository or the app bundle.
- The Android, watch and Studio specifications remain valid. Their schedule moves behind the iPhone gates.
