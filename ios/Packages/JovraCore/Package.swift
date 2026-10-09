// swift-tools-version: 6.0
// JovraCore: Foundation-only domain layer (see docs/adr/0005). Must build and test on Linux.
import PackageDescription

let package = Package(
    name: "JovraCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JovraCore", targets: ["JovraCore"]),
    ],
    targets: [
        .target(name: "JovraCore", resources: [.process("Export/Contracts")]),
        .testTarget(name: "JovraCoreTests", dependencies: ["JovraCore"], plugins: ["FixtureDiscoveryPlugin"]),
        .executableTarget(name: "FixtureRunnerGenerator", path: "Tools/FixtureRunnerGenerator"),
        .plugin(name: "FixtureDiscoveryPlugin", capability: .buildTool(), dependencies: ["FixtureRunnerGenerator"]),
    ]
)
