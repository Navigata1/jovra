# Native app per platform, shared contracts instead of shared code

JOVRA is a camera-and-video product: durable long recordings, frame-accurate scrubbing, slow motion, Vision
trajectory and body-pose analysis, audio-onset detection and composited clip export all sit directly on
AVFoundation/Vision (iOS) and CameraX/Media3/ML Kit (Android). We therefore build two native apps — SwiftUI on
iOS first, Kotlin + Jetpack Compose on Android after the iOS capture gates pass — and share **contracts**, not code:
versioned JSON schemas for every persisted record and a cross-platform **conformance suite** of golden fixtures
(scoring sequences, stat computations, unit conversions, archive manifests) in `spec/` that both platforms'
domain modules must pass byte-for-byte on the same inputs.

## Considered Options

- React Native / Expo (used in the Flywheel suite): rejected for this product — capture, frame stepping and
  on-device vision would all be native modules anyway, so the JS layer adds a bridge without removing native work.
- Flutter: same objection; camera/video plugins lag platform APIs we need (fragmented recording, trajectory detection).
- Kotlin Multiplatform for the domain layer: attractive, but it couples the iOS build to Gradle before the iOS app
  has proven its capture path. Revisit once both apps exist if the conformance suite shows duplication pain.

## Consequences

Domain logic (scoring state machine, stat recomputation, units) is written twice, in Swift and Kotlin. The
conformance fixtures are the guard against drift: a rule change lands as a fixture change first.
