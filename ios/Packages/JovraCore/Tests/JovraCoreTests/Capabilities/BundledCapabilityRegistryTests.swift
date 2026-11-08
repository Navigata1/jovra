import Foundation
import Testing
@testable import JovraCore

/// The app reads its badges and capability pages from the registry bundled with JovraCore (ADR-0004);
/// that copy must be byte-identical to the shared contract in spec/contracts.
@Suite("Bundled capability registry")
struct BundledCapabilityRegistryTests {
    @Test("the bundled registry is the shared contract, byte for byte")
    func matchesSharedContract() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shared = try Data(contentsOf: repoRoot.appendingPathComponent("spec/contracts/capability-registry.v1.json"))
        let bundled = try #require(CapabilityRegistry.bundledData())
        #expect(bundled == shared)
    }

    @Test("the bundled registry decodes and names serve speed as estimated with no benchmark yet")
    func decodes() throws {
        let registry = try CapabilityRegistry.bundled()
        let serveSpeed = try #require(registry.capability(id: "serveSpeed.manualAssisted"))
        #expect(serveSpeed.status == .estimated)
        #expect(serveSpeed.lastBenchmark.value == nil)
        #expect(registry.capability(id: "lineCalling")?.status == .unsupported)
    }
}
