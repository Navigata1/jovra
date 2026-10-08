# Studio fixtures live in `spec/studio/fixtures/`

The Studio golden fixtures are kept outside this folder on purpose. They are valid records, deliberately invalid
cases and reference vectors for `jovra.edit-plan/2`, SyncMap, RenderJob, the quote/reservation ledger and the other
Studio contracts.

`scripts/spec/validate.py`, the core gate, validates every `spec/fixtures/**/*.json` and fails on any `kind` it does
not know. That script belongs to the core workflow, so the Studio set sits beside it instead:

- fixtures: `spec/studio/fixtures/` (`records/`, `invalid/`, `vectors/`)
- schemas: `spec/schemas/studio/`
- reference: `spec/reference/studio/`
- validator: `python3 scripts/spec/validate_studio.py`
- documentation: `spec/studio/README.md`

To move them here, add a skip for `studio` paths to `validate_instances` in `scripts/spec/validate.py`, then move the
folder and update `FIX` in `validate_studio.py` and `OUT` in `generate_studio_fixtures.py`.
