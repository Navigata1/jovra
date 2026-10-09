# T04 native scoring contracts — prerequisite 1 of 3

Concrete Foundation-only Codable output types and authoritative `ScoringInput(session:)` bridge. Public decoder returns typed refusals for unsupported event/mode discriminators. Nullable output fields retain JSON null; optional `changes` distinguishes absent from explicit null.

Public contract tests were compiler-red before introducing the types. All scoring fixture inputs and 107 complete output checkpoints now round-trip without field/value loss; sample SessionDocument bridging preserves stored players/log/format/mode. Core package tests pass; existing SessionStore XCTest are skipped in this slice's repeat because their full 6-test 201.7s run passed at the assembled native source head 6cdfe34 immediately before splitting. Fresh CI will run the entire package.

`TimelineModels.swift` (531 lines) are generated concrete schema mapping, not a generic runtime document. Model/input/generator/template bytes exactly match 6cdfe34; generator reproduces source bytes. Manual source/test changes are approximately 150 lines. Replay state and public fold are subsequent buildable prerequisites; this PR does not close T04 or claim a functional native score UI. No simulator/device/ML validation is claimed.

Fresh-main publication reconciliation includes PR339: 105 typed inputs and 107 complete outputs round-trip; 36 Swift Testing tests pass (existing store XCTest repeats deferred to fresh full CI). The original compiler-red seam is preserved in file 01.
