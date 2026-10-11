// swift-tools-version: 6.0
// JovraStudioMedia: JOVRA Studio's AVFoundation / CoreMedia layer over JovraStudioCore and JovraMedia (S04;
// docs/studio/DEVELOPING.md). Apple platforms only; tested on macOS with `swift test`.
//
// A sibling package rather than a Studio area of JovraMedia: core ticket T10 alone edits JovraMedia's manifest, and
// Studio media tickets then never touch core-owned folders. Studio tickets add folders under
// Sources/JovraStudioMedia/<Module> and Tests/JovraStudioMediaTests/<Module>; none of that needs a manifest change.
import PackageDescription

let package = Package(
    name: "JovraStudioMedia",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JovraStudioMedia", targets: ["JovraStudioMedia"]),
    ],
    dependencies: [
        .package(path: "../JovraCore"),
        .package(path: "../JovraMedia"),
        .package(path: "../JovraStudioCore"),
    ],
    targets: [
        .target(
            name: "JovraStudioMedia",
            dependencies: [
                .product(name: "JovraCore", package: "JovraCore"),
                .product(name: "JovraMedia", package: "JovraMedia"),
                .product(name: "JovraStudioCore", package: "JovraStudioCore"),
            ]
        ),
        .testTarget(
            name: "JovraStudioMediaTests",
            dependencies: [
                "JovraStudioMedia",
                .product(name: "JovraCore", package: "JovraCore"),
                .product(name: "JovraStudioCore", package: "JovraStudioCore"),
            ]
        ),
    ]
)
