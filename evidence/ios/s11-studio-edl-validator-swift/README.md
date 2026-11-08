# S11 evidence: EDL validator in Swift (issue #80)

Package-only ticket (`ios/Packages/JovraStudioCore`); no app screen, so no simulator and no screenshots.

| File | What it shows |
|---|---|
| `swift-test-filter-EDL-macos.txt` | `swift test --filter EDL` on macOS, with the per-code parity table: 79 edit-plan invalid cases, 79 match, 0 mismatches; 7 valid records pass; 4 edl-context vectors; both clean-alternate pairs byte for byte |
| `swift-test-package-macos.txt` | The whole JovraStudioCore suite on macOS (60 tests), including the fixture manifest with `edl` at `swift: consumed` |
| `scratch-revert-transcript.txt` | Each regression rule (findings 0, 1, 2, 7, 8) disabled in a scratch build: its test fails; restored: the suite passes |
| `linux-ci-jovra-studio-core.txt` | The `jovra-studio-core` job log (swift:6.1 container on ubuntu-latest) for this PR |

How the parity count is made: each case under `spec/studio/fixtures/invalid/edit-plan.*.invalid.json` is patched onto
its base record and validated against the trusted context built from the stored Sample records. Reference-layer cases
compare with the stored `expect.code`; the 9 schema-layer cases compare with the code `edl.validate` gives them
(listed in `EDLParityTests.schemaLayerCodes`), so the validator refuses them itself, not only through the decoder.
