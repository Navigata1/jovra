# JOVRA Label

The macOS labelling tool of the benchmark kit (V01). It plays a local recording frame by frame and writes benchmark
labels with one key per label. How to label, seal and score: [`docs/fixtures/labelling.md`](../../docs/fixtures/labelling.md).

```sh
scripts/benchmarks/label.sh /path/to/recording.mp4     # build and open the tool
swift test --package-path tools/label-tool             # unit tests and the founder flow through the real window
scripts/benchmarks/label-tool-ui-test.sh               # XCUITest on the built app (CI: workflow "Label tool")
```

Local only: the tool reads the recording where it is, makes no network call, and writes one file,
`rec-<hash>.labels.json`, holding times and points. The founder's recordings are private
([`docs/fixtures/real-footage.md`](../../docs/fixtures/real-footage.md)); tests use the synthetic sample video.

| Folder | What is in it |
|---|---|
| `Sources/JovraLabelKit/Model` | `LabelDocument` (every edit as a value, so undo is a swap), `LabelSession` (the state the window renders), `LabelKeymap` (the one table of shortcuts: keys, menus and the on-screen legend read it) |
| `Sources/JovraLabelKit/Media` | `FramePlayer` (the frame on screen with its own presentation time, so labels are exact on variable-frame-rate files), `RecordingFingerprint` (SHA-256 and the picture's shape), `OnsetCandidateFinder` (hit candidates from the sound) |
| `Sources/JovraLabelKit/UI`, `App` | The SwiftUI window, and the AppKit window that routes every key and every click on the picture |
| `UITests`, `project.yml` | The XCUITest and the XcodeGen spec that wraps the package in an app bundle for it |

The label format, the hash-fixed split, the scorer and the label set live in `JovraBenchmark`
(`ios/Packages/JovraMedia/Sources/JovraBenchmark/Labels`), with the Python reference in
`spec/reference/jovra_ref/labels.py`.

`OnsetCandidateFinder` is a labelling aid. It is not the audio hit detection capability (T34), it has no benchmark,
and its candidates are never ground truth.
