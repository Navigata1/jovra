// swift-tools-version: 6.0
// JovraVision: the on-device analysis pipeline (V track, ADR-0031). Analysis stages read windows of a saved
// recording and write typed observations; the runner checkpoints every window so analysis resumes after an
// app kill, and suggestions reach the session only as `estimated` events (ADR-0003, ADR-0004).
// Apple platforms only; tested on macOS with `swift test`.
//
// Feature tickets (V02–V08) add a folder under Sources/JovraVision/Stages and tests under
// Tests/JovraVisionTests; none of that needs a manifest change.
import PackageDescription

let package = Package(
    name: "JovraVision",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JovraVision", targets: ["JovraVision"]),
    ],
    dependencies: [
        .package(path: "../JovraCore"),
    ],
    targets: [
        .target(name: "JovraVision", dependencies: ["JovraCore"]),
        .testTarget(name: "JovraVisionTests", dependencies: ["JovraVision", "JovraCore"]),
    ]
)
