// swift-tools-version: 6.0
// JOVRA Label: the macOS labelling tool of the benchmark kit (V01, docs/fixtures/labelling.md). It plays a
// local recording frame by frame and writes benchmark labels (spec/schemas/benchmark-labels.schema.json)
// with one key per label. Local only: no network, no upload, nothing but times and points leaves it.
//
// The label format, the hash-fixed split and the scorer live in JovraBenchmark (ios/Packages/JovraMedia);
// this package is the tool around them. `project.yml` wraps the same sources in an app bundle for
// XCUITest; day-to-day use is `scripts/benchmarks/label.sh`.
import PackageDescription

let package = Package(
    name: "JovraLabelTool",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JovraLabelKit", targets: ["JovraLabelKit"]),
        .executable(name: "jovra-label", targets: ["jovra-label"]),
    ],
    dependencies: [
        .package(path: "../../ios/Packages/JovraMedia"),
    ],
    targets: [
        .target(
            name: "JovraLabelKit",
            dependencies: [
                .product(name: "JovraBenchmark", package: "JovraMedia"),
                .product(name: "JovraMedia", package: "JovraMedia"),
            ]
        ),
        .executableTarget(name: "jovra-label", dependencies: ["JovraLabelKit"]),
        .testTarget(
            name: "JovraLabelKitTests",
            dependencies: ["JovraLabelKit", .product(name: "JovraBenchmark", package: "JovraMedia")]
        ),
    ],
    // AppKit and AVFoundation callbacks are annotated differently across the SDKs this builds with (the build
    // Mac and the hosted runner), so the tool stays in the Swift 5 language mode; UI state is main-actor bound.
    swiftLanguageModes: [.v5]
)
