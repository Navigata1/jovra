import Foundation
import JovraBenchmark
import Testing

/// Provenance rules the harness enforces before any estimator runs (ADR-0004): only a candidate estimator can
/// back a capability, a run that names a capability is gated by that capability's registry gate, and every
/// clip counts once.
@Suite("Benchmark harness provenance")
struct HarnessProvenanceTests {
    static let catalog = MediaFixtureCatalog.repository()
    let harness = BenchmarkHarness(catalog: Self.catalog)
    let task = EventTimesTask(tolerance: RationalTime(value: 50, timescale: 1000))
    let at = Date(timeIntervalSince1970: 1_791_331_200)

    @Test("an oracle or null run cannot name a capability", arguments: [EstimatorRole.oracle, .null])
    func selfTestEstimatorCannotBackCapability(role: EstimatorRole) async throws {
        let spy = CountingEstimator(role: role)
        await #expect(throws: HarnessError.selfTestEstimatorCannotBackCapability(role: role, capabilityId: "audio.hitDetection")) {
            _ = try await harness.run(spy, task: task, clipIDs: ["harness/events-s23"], mode: .gate,
                                      floor: try Floor.capabilityGate("audio.hitDetection", catalog: Self.catalog),
                                      capabilityId: "audio.hitDetection", runId: "refused", at: at)
        }
        #expect(spy.calls.value == 0)
    }

    @Test("a run that names a capability must use that capability's registry gate")
    func capabilityNeedsItsRegistryGate() async throws {
        let spy = CountingEstimator(role: .candidate)
        await #expect(throws: HarnessError.floorIsNotCapabilityGate(capabilityId: "audio.hitDetection")) {
            _ = try await harness.run(spy, task: task, clipIDs: ["harness/events-s23"], mode: .gate,
                                      floor: .harnessSelfTest, capabilityId: "audio.hitDetection", runId: "refused", at: at)
        }
        #expect(spy.calls.value == 0)
    }

    @Test("an unknown capability or one without a gate is refused")
    func unknownOrUngatedCapability() async throws {
        await #expect(throws: HarnessError.unknownCapability("audio.nothing")) {
            _ = try await harness.run(CountingEstimator(role: .candidate), task: task, clipIDs: ["harness/events-s23"],
                                      mode: .gate, floor: .harnessSelfTest, capabilityId: "audio.nothing", runId: "refused", at: at)
        }
        #expect(throws: HarnessError.capabilityHasNoGate("scoring.manual")) {
            _ = try Floor.capabilityGate("scoring.manual", catalog: Self.catalog)
        }
    }

    @Test("a candidate run on the registry gate is accepted and carries the capability")
    func candidateOnRegistryGate() async throws {
        let gate = try Floor.capabilityGate("audio.hitDetection", catalog: Self.catalog)
        #expect(gate.metrics.map(\.name) == ["own-court hit precision", "own-court hit recall", "onset MAE"])
        #expect(gate.metrics.map(\.threshold) == ["0.95", "0.90", "10"])
        let record = try await harness.run(CountingEstimator(role: .candidate), task: task, clipIDs: ["harness/events-s23"],
                                           mode: .gate, floor: gate, capabilityId: "audio.hitDetection", runId: "candidate", at: at)
        #expect(record.capabilityId == "audio.hitDetection")
        #expect(record.floor == gate)
        #expect(record.verdict?.passed == false)
    }

    @Test("a clip listed twice is refused before the estimator runs")
    func duplicateClips() async throws {
        let spy = CountingEstimator(role: .candidate)
        await #expect(throws: HarnessError.duplicateClips(["harness/events-s23"])) {
            _ = try await harness.run(spy, task: task, clipIDs: ["harness/events-s23", "harness/events-s23", "harness/events-s23"],
                                      mode: .gate, floor: .harnessSelfTest, runId: "refused", at: at)
        }
        #expect(spy.calls.value == 0)
    }
}
