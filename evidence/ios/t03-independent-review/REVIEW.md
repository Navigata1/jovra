# Independent T03 review

Reviewed/tested exact commit: `192f53f6094ce150dd523981910fb6c5398c4dc3`.
Fixed point: merged reference-contract main `15bc44a`; diff uses `git diff 15bc44a...HEAD`.
Fresh isolated worktree: `/Users/IDC2.5/.codex/worktrees/jovra-core-continuation/reviews/t03`, branch `codex/review-t03`.
Review checkout remains clean at the published candidate. No corrective commit, external comment, push or merge.

## Standards

No blocking or actionable documented-standard violations found. Reviewed CLAUDE.md, issue-tracker, ADR-0029, Foundation-only package boundaries, public contact/metadata and the code-review smell baseline independently of the acceptance checklist. Models are concrete generated Codable properties/enums, not generic maps bypassing contracts. The only opaque JSON value is scoped to the benchmark field whose schema deliberately leaves outputs unconstrained. Generated model maintenance reproduces 347 declarations without any diff. No new native UI/platform/network/hosted work in this ticket.

## Spec

No blocking defects found against issue #5. Every current record fixture, all T02 optional fields and Jon-vs-Alex session round-trip through real types. Runner registration is deterministically generated from separate source files, and runtime dispatch consumes the actual kind header independently of folders. Pending list is exactly scoring/stats/sample. Percent, unit, rational, provenance and capability registry boundaries are represented.

`ContractCodec` deliberately refuses unknown fields rather than silently dropping them; an otherwise representable future minor version retains its literal version text. Unknown major is a typed refusal. Full JSON Schema constraint enforcement is explicitly outside this codec; callers must enforce domain invariants, and the independent Python validator remains the schema gate. This matches the ticket and prevents lossy read-and-rewrite of future fields, but must not be advertised as arbitrary future-field preservation or full runtime schema validation.

## Fresh evidence

- `swift-final.txt`: clean-candidate package rerun, 30 Swift Testing tests in four suites; all 14 runners invoked, 13 canonical / 32 pct / 31 unit vectors; pending exactly three intended kinds.
- `encoded-final.txt`: 36 emitted record documents independently schema-valid and canonical byte-identical to original source fixtures.
- `python.txt`: 82 Python tests pass.
- `core-validator.txt`, `studio-validator.txt`, `room-validator.txt`: all existing core/Studio/Room contract gates pass.
- `independent-controls.txt` with retained `IndependentReviewTests.swift`: additional escaped/nested duplicate keys, nonfinite, invalid syntax/UTF-8, paired/lone surrogate, Unicode-distinct key ordering, negative-zero/exponent canonicalization; unknown/missing/null fields; major refusal/future-minor literal preservation; exact >2^53 rational, Int64 overflow and Decimal precision refusal; all pass.
- `unknown-kind-process.txt`: injecting an unclaimed fixture into this review checkout makes the **actual SwiftPM invocation** fail on unconsumedKind, not merely a helper test. Probe removed.
- `duplicate-owner-process.txt`: adding a duplicate runner makes the **actual build plugin** fail before tests on duplicate ownership. Probe removed.
- `decimal-newline-refusal-green.txt` with `IndependentNewlineTests.swift`: additional display/convert probes for trailing LF, CRLF and CR all reject correctly on macOS. The proposed issue did not reproduce; retaining equivalent Linux regression tests is useful.
- `schema-extra-negative.txt`, `value-change-negative.txt`, `noncanonical-negative.txt`: encoded-dir subprocess gate refuses added invalid fields, schema-valid changed source values, and noncanonical bytes respectively.

Independent review probes were copied to external evidence and removed from the repo before the final exact-head rerun. Original fixture/spec/model files are unchanged. No Xcode, simulator or physical-device work was run here.

## Verdict

Accept for root-controlled PR publication and fresh required CI at this exact head. Linux `jovra-core` success remains a required external merge gate; local macOS package success does not prove it. No corrective commit is needed. Keep native testing with T07 and media implementation blocked until T03 merge/resource release.
