# V01 evidence: the analysis benchmark kit

Build Mac, macOS 27.2, Xcode 27.2, 2026-11-09. This ticket adds no iPhone screen, so no simulator was used. Every
image and number here comes from synthetic material: the rendered sample video ("Sample video (synthetic)") and the
hand-written fixtures in `spec/fixtures/labels`. The founder's recordings were not opened; one test reads the sound
of a private excerpt on this Mac and prints a count (see `tests.txt`).

| File | What it shows |
|---|---|
| `scorer-cli.txt` | `jovra-benchmark score` on fixture L01: precision, recall, timing and placement error, tuning beside held-out. The same run at a 50 ms hit tolerance (different numbers), and observations for another recording refused with exit 2 |
| `label-set-status.txt` | `jovra-benchmark labels status`: the label set is founder-pending, 0 of each target, exit 4 |
| `tests.txt` | `validate.py` (2 label scoring fixtures, the label set), the Python tooling tests (20), `swift test` for JovraMedia (125 + 67 tests, the four label suites named) and for the label tool (6 XCTest with the evidence writer skipped, 20 Swift Testing tests) |
| `label-tool-{light,dark}-1-empty.jpg` | The window before a recording is open |
| `label-tool-{light,dark}-2-placing-bounce.jpg` | Frame 115 of the sample video after `B` with the pointer off the picture: the tool asks for the point. A serve is marked, the four corners are placed, a rally is open, 6 hit candidates wait |
| `label-tool-{light,dark}-3-labelled.jpg` | After the click: the bounce ring on the picture, its badge, and the counts |
| `label-tool-{light,dark}-4-refusal.jpg` | `]` pressed twice: the second one is refused, with the reason on the status line |

The images are the real window's content rendered by `LabelToolWindowTests.testSnapshotsForEvidence`
(`JOVRA_LABEL_SNAPSHOT_DIR=<folder> swift test --package-path tools/label-tool --filter testSnapshotsForEvidence`),
driven with the same key and mouse events as the flow test. macOS has no Dynamic Type, so there is no
accessibility-text-size image; the window is resizable and the key legend scrolls.

Reported separately, not merged into one "passed":

- **In-process UI test, build Mac: passed.** `LabelToolWindowTests.testFounderFlowOnTheSyntheticSampleVideo` sends real
  key-down and mouse-down events to the real window.
- **XCUITest on the built app, build Mac: not run.** This Mac asks for an administrator password before UI automation
  (`automationmodetool`: "requires user authentication"), which an agent must not answer. The app and the UI test
  bundle build here (`xcodebuild build-for-testing`: TEST BUILD SUCCEEDED). The hosted run is the `label-tool` workflow
  on the pull request; its result is in the pull request body.
- **Founder labels: founder-pending.** No label file for a real recording exists yet.
- **Physical iPhone: not applicable.** **Benchmark of any capability: none** (this ticket turns nothing on).
