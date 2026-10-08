# JOVRA Studio contracts (`spec/schemas/studio`, `spec/studio`)

The Studio layer (multi-angle capture, sync, story films, lessons, optional cloud production) follows the core rule
from ADR-0001: iOS, Android and any server share **contracts, not code**. This folder holds versioned JSON Schemas,
shipped contract data, golden fixtures (valid records, deliberately invalid cases and reference vectors) and a
dependency-free Python reference that every implementation must agree with.

Everything here is a **proposal plus checked fixtures**. Nothing in it is a renderer, a live backend, a measured sync
result, a price or a charge. All fixture data is fictional and labelled Sample (implementation-states.md).

```
spec/schemas/studio/          JSON Schema 2020-12, one file per record; studio-common.schema.json holds shared $defs
spec/studio/contracts/        data apps read: story-profiles.v1.json, render-job-transitions.v1.json, credit-classes.v1.json
spec/studio/modules/          one page per reference module: the kinds it owns, its coverage and its Swift/Kotlin status
spec/studio/fixtures/
  records/                    valid records for one Sample project (sample-court-day)
  invalid/                    patches to a valid record that must be rejected (by the schema or by the reference)
  vectors/                    reference vectors, one file per kind: inputs, reference output and hand assertions
spec/reference/studio/        reference package `studio`, and generate_studio_fixtures.py (builds the Sample project
                              and writes what every cases module declares)
  cases/                      cases modules (`*_cases.py`), discovered by file name: the fixtures each writes and the
                              schemas, reference rules and vector checkers each registers
scripts/spec/validate_studio.py   validates all of the above and re-runs the reference; non-zero exit on any failure
```

Run from the repo root:

```
python3 spec/reference/studio/generate_studio_fixtures.py   # rewrites spec/studio/fixtures and the module index (same bytes every run)
python3 scripts/spec/validate_studio.py                      # add -v for detail
python3 scripts/spec/validate_studio.py --list               # every registered kind: type, count, module, coverage, swift, kotlin
python3 scripts/spec/test_validate_studio.py                 # black-box tests of the plumbing (in a temporary copy)
```

Current result (2026-10-07, ticket S03): `RESULT: PASS`, with 20 schemas (ECMA-262 pattern anchors), 31 records, 19
cross-record mutations rejected, 185 invalid cases rejected (155 by the reference with the expected code, 30 by the
schema), 140 vector cases in 7 kinds, 4 trusted-context self-tests, 4 capture-hint self-tests, 8 module pages, 28
registered kinds each claimed by one page, and 65 generated files current (63 fixtures, the story-profile catalog and
the module index). Per-kind counts come from `--list`. The core gate `scripts/spec/validate.py` and its shared
`jsonschema_subset.py` are untouched.

## Module pages

The per-module documentation (what each record and vector kind means, the reference's rules, the decisions taken and
what is not covered yet) lives on one page per module under `spec/studio/modules/`, linked from the generated index
[`modules/README.md`](modules/README.md). This README holds no per-module text, and the validator fails if it does.

Each page starts with front matter that the validator (and the Swift and Kotlin manifest tests) read:

```
---
module: <name>                       # the file name, spec/studio/modules/<name>.md
reference: [<reference files>]       # repository paths; [] for a module not covered yet
cases: [<cases modules>]             # the cases modules that register this module's kinds
kinds: [<vector kinds and schemaVersions>]
coverage: covered | not-covered      # not-covered: a planned module with no fixtures yet, and no kinds
swift: pending | consumed            # consumed: a registered Swift test reproduces every kind on the page
kotlin: pending | consumed
---
```

## Adding a contract (files only, no shared list)

1. Add the reference module under `spec/reference/studio/` and a cases module `spec/reference/studio/cases/<name>_cases.py`.
   It declares the files it writes with `fixtures(sample)` and registers its `VECTOR_CHECKERS`, `SCHEMAS` and
   `RECORD_RULES` (the contract is in `spec/reference/studio/cases/__init__.py`). Add a new schema file under
   `spec/schemas/studio/` if the contract needs one.
2. Add its page `spec/studio/modules/<name>.md` with `swift: pending` and `kotlin: pending`.
3. Run the generator (it writes the new fixtures and adds the page to the index) and the validator.

The validator fails on a vector file whose kind has no checker (`no checker for kind <name>`), on a registered kind or
schemaVersion that no page claims (`kind <name> has no module page`), on a page that names a kind nobody registers,
on a generated file that is missing (`generated file missing: <path>`) or stale, and on a stale index. A platform
ticket that starts consuming a module's fixtures flips only that page's `swift:` or `kotlin:` line.

**Why the fixtures are not in `spec/fixtures/studio/`.** The core validator walks every `spec/fixtures/**/*.json` and
fails on any `kind` it does not know. That script belongs to the core workflow and must not be edited from here, so
Studio fixtures live in `spec/studio/fixtures/`. `spec/fixtures/studio/README.md` points here. Moving them only takes
a one-line skip in `scripts/spec/validate.py` (for example, `if "studio" in path.parts: continue`), made by the
owner of that file.

## Conventions

The shared conventions (versions, strictness, ids, time, rounding, hashes and provenance) are on the module page of
the helpers that implement them; see the index.

## Invalid cases: what the review rounds added

These include executable fields, approval or URL fields, unlabelled speeds, copied score
digits, stale overlay/event/sync revisions, gaps, overruns, forged session time, integral floats, transitions
that are too long, lack handles or cover a contact, audio that is out of sync or missing during live play,
hold-bed over live or over shown time, alt-bed mid-segment, missing consent or disclosure, music outside the
profile, interpolated slow motion, replays before or outside their original, blind portrait crops, pans that are
too fast, out-of-order points, a forged sync offset or residual, an auto-approved map, an incomplete review,
extrapolated coverage, double consumption, live charging, an accepted illustrative quote, a client-set cap,
readiness without full decode, a 48 h link, auto-publishing, a laundered cue provenance, invite escalation and
provider overclaims. Review round 1 added: score digits or unknown ids as overlay refs, a relabelled overlay kind, a
re-pointed cue keeping `reviewed`, unresolved card text and narration notes, self-attested consent and rights,
rights scope overclaim, forged coverage with matching session time, an anchor outside its piece, a ghost artifact
on a ready job, a resume stage of `ready`, a stage charged on two attempts, acceptance 0.5 s after expiry (quote
and invite), an unbound quote, and reference-catalog duplicates, kind and revision errors. Review round 2 added:
an unlabelled live re-showing of a moment, contact protection switched off by a null keeper, a plan of another
project, a bed returning to the primary mid-segment, an alternate bed switching hard at a dissolve, a failed sync
piece with coverage, an invented reference restart, reserve/consume/release entry keys of another output, job or
stage (or with the wrong prefix or outcome), and ids and hashes with a trailing newline. Review round 3 added: a
primary bed returning hard (0 ms fade) at a cut, a `no-overlap` sync state, a from-hints offset that is not the
journal's, and a 400 ppm map stored as `estimated`.

## Decisions taken where the brief left room (change only through a fixture change)

1. Studio fixtures live in `spec/studio/fixtures/`, not `spec/fixtures/studio/` (see above).
2. Versions follow `jovra.<name>/<major>` rather than the core's `kind` + semver.
3. Schema `pattern`s use ECMA-262 anchors: `validate_studio.py` runs the shared subset checker with `$` meaning end
   of input (Python's `$` also accepts a trailing newline). The core gate's `scripts/spec/jsonschema_subset.py` still
   uses Python semantics and should be fixed by its owner; Swift and Kotlin ports follow ECMA.

Decisions that belong to one module are on its page.

## Not covered yet (needs fixtures before any app relies on it)

Each module page ends with what its module does not cover yet. A planned module with no fixtures yet has a page with
`coverage: not-covered` and no kinds (`--list` shows it). Outside the module pages:

- **Backend:** RLS and gateway authorization (`docs/backend/security-model.md`), the queue, claim, lease and fencing
  protocol (`docs/backend/architecture.md` §7), and real model planner output. These are designed, not code.

None of it is validated on field footage.

## Sources

Repository material (OBSERVED, read 2026-10-07):
- `design-reference/studio/brief/backend-media-design.md`, `implementation-states.md`, `story-profiles.json` and
  `screens.json`.
- `docs/handoff/studio/*` and `.claude/skills/jovra-*`.
- `tools/studio-plan/scripts/validate_edit_plan.py`.
- `docs/research/studio/{film-engine,multicam-sync,backend-architecture,pricing-and-premium}.md`.
- `docs/adr/0001`, `0003`, `0004`, `0011`, `0013`.
- `/Users/IDC2.5/Desktop/you-link-x/garnet-remotion/production_preview.py` (`MAX_SEGMENTS = 128`), read only.

External references carried over from those documents, not re-fetched for this task:
- JSON Schema 2020-12: https://json-schema.org/draft/2020-12/schema
- RFC 8785 JSON canonicalization: https://www.rfc-editor.org/rfc/rfc8785
- ITF court dimensions: https://www.itftennis.com/en/about-us/governance/rules-and-regulations/
- WCAG 2.3.1 three flashes: https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold.html
- R2 pricing: https://developers.cloudflare.com/r2/pricing/
- App Review 3.1.1: https://developer.apple.com/app-store/review/guidelines/#in-app-purchase
