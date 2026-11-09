import JovraCore
import Testing
@testable import Jovra

/// N12 "How this was measured": everything shown comes from the registry (ADR-0004).
@Suite("Capability detail presentation")
struct CapabilityDetailPresentationTests {
    @Test("serve speed from the shipped registry: Estimated, its method version and Not benchmarked")
    func shippedServeSpeed() throws {
        let detail = try #require(CapabilityDetailPresentation(id: "serveSpeed.manualAssisted", registry: try CapabilityRegistry.bundled()))
        #expect(detail.title == "Serve speed (manual-assisted)")
        #expect(detail.status == "Estimated")
        #expect(detail.badge == .provenance(.estimated))
        #expect(detail.methodVersion == "serveSpeed.manualAssisted@1.0.0")
        #expect(detail.benchmark == "Not benchmarked")
        #expect(detail.testedOn == "Not tested yet")
        #expect(detail.needs == ["Video", "Court calibration"])
        #expect(detail.buildsOn == ["Court calibration (4 taps)"])
        #expect(detail.promotionGate == "Radar-paired serves on >= 3 courts")
    }

    @Test("an injected registry changes the status and benchmark shown")
    func injectedRegistry() throws {
        var registry = try CapabilityRegistry.bundled()
        let index = try #require(registry.capabilities.firstIndex { $0.id == "serveSpeed.manualAssisted" })
        registry.capabilities[index].status = .validated
        registry.capabilities[index].lastBenchmark = .init(.init(
            runId: "bench-7", at: "2027-03-02T10:00:00Z", dataset: "Radar-paired serves, 3 hard courts",
            passed: true, results: [.init(name: "Mean absolute error", value: "3.1 mph")]))
        let detail = try #require(CapabilityDetailPresentation(id: "serveSpeed.manualAssisted", registry: registry))
        #expect(detail.status == "Validated")
        #expect(detail.badge == .provenance(.validated))
        #expect(detail.testedOn == "Radar-paired serves, 3 hard courts")
        #expect(detail.benchmark == "Passed on Mar 2, 2027")
        #expect(detail.results == ["Mean absolute error: 3.1 mph"])
    }

    @Test("disabled and unsupported capabilities never show a provenance badge")
    func unavailableStatuses() throws {
        let registry = try CapabilityRegistry.bundled()
        let disabled = try #require(CapabilityDetailPresentation(id: "audio.hitDetection", registry: registry))
        #expect(disabled.status == "Off until it passes testing")
        #expect(disabled.badge == nil)
        let unsupported = try #require(CapabilityDetailPresentation(id: "lineCalling", registry: registry))
        #expect(unsupported.status == "Not available")
        #expect(unsupported.badge == nil)
    }

    @Test("an unknown capability has no detail")
    func unknown() throws {
        #expect(CapabilityDetailPresentation(id: "serve-speed-manual", registry: try CapabilityRegistry.bundled()) == nil)
    }

    @Test("badges map registry status, never a hard-coded provenance")
    func badgeMapping() {
        #expect(ProvenanceBadge.Kind(status: .manual) == .provenance(.manual))
        #expect(ProvenanceBadge.Kind(status: .estimated) == .provenance(.estimated))
        #expect(ProvenanceBadge.Kind(status: .validated) == .provenance(.validated))
        #expect(ProvenanceBadge.Kind(status: .disabled) == nil)
        #expect(ProvenanceBadge.Kind(status: .unsupported) == nil)
    }
}
