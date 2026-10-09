# T04 native scoring contracts — prerequisite1 of3

Concrete Foundation-only Codable output types and authoritative `ScoringInput(session:)` bridge. Public decoder returns typed refusals for unsupported event/mode discriminators. Nullable output fields retain JSON null; optional `changes` distinguishes absent from explicit null.

Public contract tests were compiler-red before introducing the types. All scoring fixture inputs and105 complete output checkpoints now round-trip without field/value loss; sample SessionDocument bridging preserves stored players/log/format/mode. Core package tests pass; existing SessionStore XCTest are skipped in this slice's repeat because their full6-test201.7s run passed at the assembled native source head6cdfe34 immediately before splitting. Fresh CI will run the entire package.

`TimelineModels.swift`531 lines are generated concrete schema mapping, not a generic runtime document. Model/input/generator/template bytes exactly match6cdfe34; generator reproduces source bytes. Manual source/test changes are~150 lines. Replay state and public fold are subsequent buildable prerequisites; this PR does not close T04 or claim a functional native score UI. No simulator/device/ML validation is claimed.
