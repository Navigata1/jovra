// swift-tools-version: 6.0
// JovraMedia: AVFoundation / Vision / Accelerate adapters over JovraCore (see docs/adr/0005).
// Apple platforms only; tested on macOS with `swift test`.
import PackageDescription

let package = Package(
    name: "JovraMedia",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JovraMedia", targets: ["JovraMedia"]),
    ],
    dependencies: [
        .package(path: "../JovraCore"),
    ],
    targets: [
        .target(name: "JovraMedia", dependencies: ["JovraCore"]),
        .testTarget(name: "JovraMediaTests", dependencies: ["JovraMedia", "JovraCore"]),
    ]
)
