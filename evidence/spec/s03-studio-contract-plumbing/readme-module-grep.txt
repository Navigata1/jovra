# Module references in spec/studio/README.md (page path, reference/cases file name, or module.attribute)
$ grep -nE 'modules/bundle\.md|bundle(_cases)?\.py|bundle\.[A-Za-z_]' spec/studio/README.md
(no match)
$ grep -nE 'modules/core\.md|core(_cases)?\.py|core\.[A-Za-z_]' spec/studio/README.md
(no match)
$ grep -nE 'modules/edl\.md|edl(_cases)?\.py|edl\.[A-Za-z_]' spec/studio/README.md
(no match)
$ grep -nE 'modules/jobstate\.md|jobstate(_cases)?\.py|jobstate\.[A-Za-z_]' spec/studio/README.md
(no match)
$ grep -nE 'modules/ledger\.md|ledger(_cases)?\.py|ledger\.[A-Za-z_]' spec/studio/README.md
(no match)
$ grep -nE 'modules/normalization\.md|normalization(_cases)?\.py|normalization\.[A-Za-z_]' spec/studio/README.md
(no match)
$ grep -nE 'modules/records\.md|records(_cases)?\.py|records\.[A-Za-z_]' spec/studio/README.md
(no match)
$ grep -nE 'modules/sync\.md|sync(_cases)?\.py|sync\.[A-Za-z_]' spec/studio/README.md
(no match)
$ grep -nE 'syncfit\.py|syncfit\.[A-Za-z_]' spec/studio/README.md
(no match)
$ grep -nE 'generate_studio_records\.py|generate_studio_records\.[A-Za-z_]' spec/studio/README.md
(no match)

# The only line that links the module pages
$ grep -n 'modules/' spec/studio/README.md
14:spec/studio/modules/          one page per reference module: the kinds it owns, its coverage and its Swift/Kotlin status
45:what is not covered yet) lives on one page per module under `spec/studio/modules/`, linked from the generated index
46:[`modules/README.md`](modules/README.md). This README holds no per-module text, and the validator fails if it does.
52:module: <name>                       # the file name, spec/studio/modules/<name>.md
68:2. Add its page `spec/studio/modules/<name>.md` with `swift: pending` and `kotlin: pending`.

# Plain word matches (domain vocabulary, not module lines)
$ grep -niw bundle spec/studio/README.md
$ grep -niw core spec/studio/README.md
3:The Studio layer (multi-angle capture, sync, story films, lessons, optional cloud production) follows the core rule
39:the module index). Per-kind counts come from `--list`. The core gate `scripts/spec/validate.py` and its shared
76:**Why the fixtures are not in `spec/fixtures/studio/`.** The core validator walks every `spec/fixtures/**/*.json` and
77:fails on any `kind` it does not know. That script belongs to the core workflow and must not be edited from here, so
112:2. Versions follow `jovra.<name>/<major>` rather than the core's `kind` + semver.
114:   of input (Python's `$` also accepts a trailing newline). The core gate's `scripts/spec/jsonschema_subset.py` still
$ grep -niw edl spec/studio/README.md
$ grep -niw jobstate spec/studio/README.md
$ grep -niw ledger spec/studio/README.md
$ grep -niw normalization spec/studio/README.md
$ grep -niw records spec/studio/README.md
5:shipped contract data, golden fixtures (valid records, deliberately invalid cases and reference vectors) and a
16:  records/                    valid records for one Sample project (sample-court-day)
35:Current result (2026-10-07, ticket S03): `RESULT: PASS`, with 20 schemas (ECMA-262 pattern anchors), 31 records, 19
$ grep -niw sync spec/studio/README.md
3:The Studio layer (multi-angle capture, sync, story films, lessons, optional cloud production) follows the core rule
8:Everything here is a **proposal plus checked fixtures**. Nothing in it is a renderer, a live backend, a measured sync
90:digits, stale overlay/event/sync revisions, gaps, overruns, forged session time, integral floats, transitions
91:that are too long, lack handles or cover a contact, audio that is out of sync or missing during live play,
94:too fast, out-of-order points, a forged sync offset or residual, an auto-approved map, an incomplete review,
103:project, a bed returning to the primary mid-segment, an alternate bed switching hard at a dissolve, a failed sync
106:primary bed returning hard (0 ms fade) at a cut, a `no-overlap` sync state, a from-hints offset that is not the
136:- `docs/research/studio/{film-engine,multicam-sync,backend-architecture,pricing-and-premium}.md`.
