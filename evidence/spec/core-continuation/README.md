# Core continuation: existing reference verification

2026-10-09. Commands run from an isolated checkout reconciled to main d36e170.

- `python3 scripts/spec/validate.py`: existing core contract fixtures pass.
- `python3 scripts/spec/validate_studio.py`: deterministic fixture and reference checks pass.
- `python3 scripts/spec/validate_room.py`: 232 cases pass.
- `python3 -m unittest discover -s scripts/spec -p 'test_*.py' -v`: 79 core/Studio/canonical discovery, drift and deliberate-rejection tests pass after integrating T02.

These are reference-contract checks. They do not establish native Studio, watch apps, device connectivity, hosted
backend readiness, film rendering or real-tennis metric accuracy. The merged T02 PR adds its `spec` CI job to repeat these checks on every PR; this follow-up does not add a
redundant second job.

ADR-0029 resolves the court origin and new key-moment naming without changing source fixtures or schema versions,
and distinguishes sorted canonical conformance bytes from the cosmetic fixture printer.

Independent review correction: unpaired Unicode surrogates in keys or values are refused before producing invalid
UTF-8. Correct escaped pairs remain valid; nested duplicate keys and escape-equivalent duplicate keys are rejected.
The canonical suite contains 13 hand-derived positive byte vectors and explicit invalid-value tests.
