// swift-tools-version: 6.0
// JovraStudioCore: JOVRA Studio's Foundation-only domain layer (S04; docs/studio/DEVELOPING.md).
// Depends on JovraCore only. Must build and test on Linux (CI job `jovra-studio-core` in .github/workflows/studio.yml):
// never import an Apple-only framework here (AVFoundation, UIKit, SwiftUI, ...); media code lives in
// JovraStudioMedia.
//
// Studio tickets add folders under Sources/JovraStudioCore/<Module> and Tests/JovraStudioCoreTests/<Module>; none of
// that needs a manifest change.
import PackageDescription

let package = Package(
    name: "JovraStudioCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JovraStudioCore", targets: ["JovraStudioCore"]),
    ],
    dependencies: [
        .package(path: "../JovraCore"),
    ],
    targets: [
        .target(name: "JovraStudioCore", dependencies: [.product(name: "JovraCore", package: "JovraCore")]),
        .testTarget(
            name: "JovraStudioCoreTests",
            dependencies: ["JovraStudioCore", .product(name: "JovraCore", package: "JovraCore")]
        ),
    ]
)
