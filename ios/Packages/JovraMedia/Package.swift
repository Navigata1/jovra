// swift-tools-version: 6.0
// JovraMedia: AVFoundation / Vision / Accelerate adapters over JovraCore (see docs/adr/0005).
// Apple platforms only; tested on macOS with `swift test`.
//
// This manifest is edited by ticket T10 only (docs/spec/tickets.md, conflict avoidance). Feature tickets add
// folders under Sources/JovraMedia (Capture, Import, Playback, Library, Export, Analysis, ...) and tests
// under Tests/JovraMediaTests or Tests/JovraBenchmarkTests; none of that needs a manifest change.
import PackageDescription

let package = Package(
    name: "JovraMedia",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JovraMedia", targets: ["JovraMedia"]),
        // Media-fixture catalogue, decoded-frame signatures and the benchmark harness. Test support and
        // tooling only: the app target never links it.
        .library(name: "JovraBenchmark", targets: ["JovraBenchmark"]),
        .executable(name: "jovra-benchmark", targets: ["jovra-benchmark"]),
    ],
    dependencies: [
        .package(path: "../JovraCore"),
    ],
    targets: [
        .target(name: "JovraMedia", dependencies: ["JovraCore"]),
        .target(
            name: "JovraBenchmark",
            dependencies: ["JovraMedia", "JovraCore"],
            exclude: ["CLI"]
        ),
        .executableTarget(
            name: "jovra-benchmark",
            dependencies: ["JovraBenchmark"],
            path: "Sources/JovraBenchmark/CLI"
        ),
        .testTarget(name: "JovraMediaTests", dependencies: ["JovraMedia", "JovraCore", "JovraBenchmark"]),
        .testTarget(name: "JovraBenchmarkTests", dependencies: ["JovraBenchmark", "JovraMedia", "JovraCore"]),
    ]
)
