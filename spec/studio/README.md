# JOVRA Studio contracts (`spec/schemas/studio`, `spec/studio`)

The Studio layer (multi-angle capture, angle alignment, story films, lessons, optional cloud production) follows the
rule from ADR-0001: iOS, Android and any server share **contracts, not code**. This folder holds versioned JSON
Schemas, shipped contract data, golden fixtures (valid Sample documents, deliberately invalid cases and reference
vectors) and a dependency-free Python reference that every implementation must agree with.

Everything here is a **proposal plus checked fixtures**. Nothing in it is a renderer, a live backend, a measured
alignment result, a price or a charge. All fixture data is fictional and labelled Sample (implementation-states.md).

```
spec/schemas/studio/          JSON Schema 2020-12, one file per document type; studio-common.schema.json holds shared $defs
spec/studio/contracts/        data apps read: story-profiles.v1.json, render-job-transitions.v1.json, credit-classes.v1.json
spec/studio/modules/          one page per reference module: the kinds it owns, its coverage and its Swift/Kotlin status
spec/studio/fixtures/         generated fixtures: valid Sample documents, invalid cases and reference vectors (the
                              formats and folders are described on the module pages)
spec/reference/studio/        reference package `studio`, and generate_studio_fixtures.py (builds the Sample project
                              and writes what every cases module declares)
  cases/                      cases modules (`*_cases.py`), discovered by file name: the fixtures each writes and the
                              schemas, reference rules, vector checkers and self-tests each registers
scripts/spec/validate_studio.py   validates all of the above and re-runs the reference; non-zero exit on any failure
```

Run from the repo root:

```
python3 spec/reference/studio/generate_studio_fixtures.py   # rewrites spec/studio/fixtures and the module index (same bytes every run)
python3 scripts/spec/validate_studio.py                      # add -v for detail; prints a count per check and RESULT
python3 scripts/spec/validate_studio.py --list               # every registered kind: type, count, module, coverage, swift, kotlin
python3 scripts/spec/test_validate_studio.py                 # black-box tests of the plumbing (in a temporary copy)
```

The current numbers (schemas, documents, invalid cases, vector cases, self-tests, module pages and generated files)
are whatever the validator prints; per-kind counts come from `--list`. This README keeps none of them, so no
contract ticket has to edit it.

## Module pages

The per-module documentation (what each document and vector kind means, the reference's rules, the invalid cases each
review round added, the decisions taken and what is not covered yet) lives on one page per module under
`spec/studio/modules/`, linked from the generated index [`modules/README.md`](modules/README.md). This README holds
no per-module text, and the validator fails if it does: a line that names a module (its name as a whole word in any
case, as `grep -iw` finds it, its page path, or one of its reference or cases files) is a failure.

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
   It declares the files it writes with `fixtures(sample)` and registers its `VECTOR_CHECKERS`, `SCHEMAS`,
   `RECORD_RULES` and `SELF_TESTS` (the contract is in `spec/reference/studio/cases/__init__.py`). Add a new schema
   file under `spec/schemas/studio/` if the contract needs one.
2. Add its page `spec/studio/modules/<name>.md` with `swift: pending` and `kotlin: pending`.
3. Run the generator (it writes the new fixtures and adds the page to the index) and the validator.

The validator fails on a vector file whose kind has no checker (`no checker for kind <name>`), on a case a checker
neither passes nor fails, on a self-test that neither passes nor fails, on a registered kind or schemaVersion that no
page claims (`kind <name> has no module page`), on a page that names a kind nobody registers, on a generated file
that is missing (`generated file missing: <path>`) or stale, and on a stale index. A platform ticket that starts
consuming a module's fixtures flips only that page's `swift:` or `kotlin:` line. A later round of review adds its
invalid cases, mutations or self-tests in the owning cases module and notes them on that module's page.

The one shared piece a contract may need to extend is the validator's context `Ctx` (a new contract file or a new
role in the Sample project); `validate_studio.py` holds no per-module check.

**Why the fixtures are not in `spec/fixtures/studio/`.** The app contract gate `scripts/spec/validate.py` walks every
`spec/fixtures/**/*.json` and fails on any `kind` it does not know. That script belongs to the app workflow and must
not be edited from here, so Studio fixtures live in `spec/studio/fixtures/`. `spec/fixtures/studio/README.md` points
here. Moving them only takes a one-line skip in `scripts/spec/validate.py` (for example,
`if "studio" in path.parts: continue`), made by the owner of that file.

## Conventions

The shared conventions (versions, strictness, ids, time, rounding, hashes and provenance) are on the module page of
the helpers that implement them; see the index.

## Decisions taken where the brief left room (change only through a fixture change)

1. Studio fixtures live in `spec/studio/fixtures/`, not `spec/fixtures/studio/` (see above).
2. Versions follow `jovra.<name>/<major>` rather than the app contracts' `kind` + semver.
3. Schema `pattern`s use ECMA-262 anchors: `validate_studio.py` runs the shared subset checker with `$` meaning end
   of input (Python's `$` also accepts a trailing newline). The app gate's `scripts/spec/jsonschema_subset.py` still
   uses Python semantics and should be fixed by its owner; Swift and Kotlin ports follow ECMA.

Decisions that belong to one module are on its page.

## Not covered yet (needs fixtures before any app relies on it)

Each module page ends with what its module does not cover yet. A planned module with no fixtures yet has a page with
`coverage: not-covered` and no kinds (`--list` shows it). Outside the module pages:

- **Backend:** RLS and gateway authorization (`docs/backend/security-model.md`), the queue, claim, lease and fencing
  protocol (`docs/backend/architecture.md` §7), and story plans written by a real model. These are designed, not code.

None of it is validated on field footage.

## Sources

Repository material (OBSERVED, read 2026-10-07):
- `design-reference/studio/brief/backend-media-design.md`, `implementation-states.md`, `story-profiles.json` and
  `screens.json`.
- `docs/handoff/studio/*` and `.claude/skills/jovra-*`.
- `tools/studio-plan/scripts/validate_edit_plan.py`.
- The Studio research under `docs/research/studio/` (film engine, multi-camera alignment, backend architecture,
  pricing and premium); each module page cites the sections it relies on.
- `docs/adr/0001`, `0003`, `0004`, `0011`, `0013`.
- `/Users/IDC2.5/Desktop/you-link-x/garnet-remotion/production_preview.py` (`MAX_SEGMENTS = 128`), read only.

External references carried over from those documents, not re-fetched for this task:
- JSON Schema 2020-12: https://json-schema.org/draft/2020-12/schema
- RFC 8785 JSON canonicalization: https://www.rfc-editor.org/rfc/rfc8785
- ITF court dimensions: https://www.itftennis.com/en/about-us/governance/rules-and-regulations/
- WCAG 2.3.1 three flashes: https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold.html
- R2 pricing: https://developers.cloudflare.com/r2/pricing/
- App Review 3.1.1: https://developer.apple.com/app-store/review/guidelines/#in-app-purchase
