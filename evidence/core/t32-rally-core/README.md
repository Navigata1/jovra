# T32 evidence: rally segmentation core and rally-only composition

Package-only ticket (no screen). Captured on the build Mac, macOS 27.2, 2026-11-08. No simulator or device was used.
Paths are shown as `<repo>` (the worktree) and `<scratch>` (a session scratch folder outside the repository).

| File | What it shows |
|---|---|
| `01-reference-red.txt` | The hand-written rally cases ran before `jovra_ref/rally.py` existed: the generator failed. |
| `02-swift-core-red.txt` | `RallyRunner` and the roll-writer tests compiled against no Rally sources: JovraCore failed to build. |
| `03-swift-core-green.txt` | JovraCore `swift test` green: 5 rally fixtures (37 vectors) consumed by `RallyRunner`, the writer suite passed, 80 Swift Testing tests plus 12 XCTest cases. |
| `04-swift-mutation-caught.txt` | Mutation: ending a rally only when the gap is *above* 3 s (instead of at 3 s) fails the `R02` threshold-edge case. |
| `05-native-session-validated.txt` | The Swift-written `session.rolls.json` (per-session 2 s / 3 s, a per-clip pre-roll, a per-clip post-roll, a deselected clip) validates with the reference validator and has the reference's exact canonical bytes. CI repeats this in the `native-data-export` job. |
| `06-swift-media-red.txt` | `RallyCompositionTests` compiled against no `RallyComposition`: red. |
| `07-swift-media-green.txt` | JovraMedia `swift test --no-parallel` green. The composition lasts 1100/1000 s for a 1100 ms plan on both the 60 and 240 fps frame-counter fixtures (the tolerance is one frame); frame codes read from pixels prove each range starts on its own source frame and the skipped time never plays. |
| `08-spec-green.txt` | Fixtures regenerate deterministically, `validate.py` PASS (re-running every rally case through `CHECKS`), the 10 rally tooling tests and all 111 contract-tooling tests OK, Studio and Room validators PASS. |

Linux: the `jovra-core` CI job runs the same JovraCore suite on `swift:6.1` (link in the PR). RallyComposition is
macOS only, as the ticket says.
