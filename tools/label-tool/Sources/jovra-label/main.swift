// jovra-label: the JOVRA benchmark labelling tool (V01). See docs/fixtures/labelling.md.
//
//   scripts/benchmarks/label.sh [VIDEO]
//   swift run --package-path tools/label-tool jovra-label --open VIDEO --labels-dir spec/benchmarks/labels
import JovraLabelKit

// The process starts on the main thread; say so, so the app can be built in either language mode.
MainActor.assumeIsolated { LabelToolMenu.runApplication() }
