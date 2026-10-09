# Independent T08 query/migration review

Reviewed exact candidate dae78525618d51676c3373a29a0d50ad5046b823, diff against its parent. Fresh detached checkout: reviews/t08-query. No modifications to the implementation/store checkout. Reviewer-only test controls are preserved in public-controls.patch and removed from the checkout after execution. No native builds, simulator, hosted writes or physical tests.

## Standards

No blocking documented-standard breach identified. The changed files remain Foundation-only package code; no app dependency, project/configuration edit, client secret or public-contact violation. Transactions contain no suspension. Known load corruption and unsafe path errors are distinct from operational filesystem failures. Folder truth and disposable index remain explicit. No actionable baseline smell beyond the existing single store module's several cohesive operations.

## Spec

Accept this bounded query/index/quarantine/migration slice. Folder enumeration is authoritative; titles, player names and notes search correctly; independent original/analysis/review/archive filters remain separate. Sample sessions are excluded from opponent queries and doubles teammates are not treated as opponents. Unsupported future versions and unknown fields retain their original bytes in quarantine; no lossy rewrite is accepted. Existing versions migrate additively to current 1.2.0. Quarantine relocates the session entry/link itself, without following external originals. Migration write failures propagate without misclassifying a healthy original as corrupt.

This does not close full T08: trash/restore/purge and MediaLibrary custody are separate planned slices. There is no structured court field in the current SessionDocument; court search presently works only for court text stored in title/notes. UI quarantine presentation and retention behavior are outside this package slice. Linux CI is still an owner gate, not established by this macOS run.

## Verification

- 01-swift.txt: exact candidate's 12 XCTest pass (including 1,000 interleavings), plus 31 Swift Testing tests pass; 197.5 seconds for XCTest. The initial build/test consumed the unmodified candidate before reviewer controls were compiled.
- 02-public-controls.txt: 3 independent public API tests pass. Migration out-of-space keeps original bytes and no quarantine entry; future version plus unknown nested JSON remains byte-exact in quarantine while healthy session lists; malicious index symlink does not modify the external file.
- 03-migration-output.txt: public migration path emits actual current-version document.
- 04-migrated-reference.txt: emitted migrated document temporarily added as a standalone records fixture, full Python schema/reference validator PASS; temporary removed and original fixtures unchanged.
- Diff whitespace check passed. Final detached checkout source is clean.

The code-review skill requests parallel Standards/Spec agents. All four agent slots were occupied; both axes are recorded separately by this independent reviewer, without pretending a second reviewer ran.
