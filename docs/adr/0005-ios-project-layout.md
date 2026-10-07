# Generated Xcode project and a two-layer Swift package

`ios/project.yml` (XcodeGen) generates the Xcode project; sources are globbed per folder, so parallel feature work
never conflicts on `project.pbxproj`, which is not committed. Domain code lives in the `JovraKit` Swift package with
two libraries: **JovraCore** (Foundation-only: domain model, scoring engine, stats, units, manifests, capability
registry; builds and tests on Linux CI) and **JovraMedia** (AVFoundation/Vision/Accelerate: audio onset detection,
trajectory and pose pipelines, homography, export composition; tested on macOS with `swift test`). The app target
holds SwiftUI features and platform adapters only. Deployment target iOS 17.
