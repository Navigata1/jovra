// swift-tools-version: 6.0
// JovraRoom: the Foundation-only port of spec/room (JOVRA Room v1 and the watch bridge). Must build and test on
// Linux. It depends on JovraCore only for the canonical JSON writer (ADR-0029); it never imports a UI or watch-transport
// framework (PackageHygieneTests and the room.yml grep enforce it).
import PackageDescription

let package = Package(
    name: "JovraRoom",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JovraRoom", targets: ["JovraRoom"]),
    ],
    dependencies: [
        .package(path: "../JovraCore"),
    ],
    targets: [
        .target(name: "JovraRoom", dependencies: [.product(name: "JovraCore", package: "JovraCore")]),
        // One test target; each ticket owns a folder (Part1 = W01, Part2 = W02).
        .testTarget(
            name: "JovraRoomTests",
            dependencies: ["JovraRoom", .product(name: "JovraCore", package: "JovraCore")],
            path: "Tests"
        ),
    ]
)
