# iOS 18.0 deployment target, iOS 26 features behind availability checks

Status: accepted; amends ADR-0005 (deployment target line only).

The iOS app targets **iOS 18.0**, superseding ADR-0005's iOS 17. iOS 18 gives the capture path what it needs on every
supported phone: `pauseRecording()`, control of `isAutoVideoFrameRateEnabled`, the Swift Vision API, SwiftUI camera
capture events and `LockedCameraCapture`. Features that exist only on iOS 26 (`BGContinuedProcessingTask`, AirPods
capture events, `SpeechAnalyzer`, iPhone `HKWorkoutSession`, lens-smudge detection) sit behind `#available` checks and
degrade to a stated fallback, never to a silent gap. The start-PTS callback (iOS 18.2) is likewise gated.

## Considered Options

- iOS 17 (ADR-0005): loses recording pause and frame-rate control in the capture engine for little reach.
- iOS 26 (the research recommendation, technical-feasibility §16.1): every code path testable on the build Mac, but
  drops roughly a fifth of iPhones. The lead chose reach.

## Consequences

The build Mac has only the iOS 26.5 Simulator runtime, so **iOS 18 runtime behaviour is unverified locally**: CI and
simulator evidence prove the iOS 26 branch only. Every `#available` fallback is reported as `unverified` until it runs
on an iOS 18 simulator or device, and the hardware phase should include an iOS 18 device. On iOS 18, analysis runs in
the foreground with resumable checkpoints and the import screen says "Analysis pauses if you leave JOVRA".
