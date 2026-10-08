import Foundation
import JovraBenchmark
import Testing

/// A record that names a capability is judged by that capability's registry gate, so its task, tolerance and
/// metric names come from `spec/fixtures/media/benchmark-bindings.json`, never from the caller.
@Suite("Capability bindings")
struct CapabilityBindingTests {
    static let catalog = MediaFixtureCatalog.repository()
    let harness = BenchmarkHarness(catalog: Self.catalog)
    let at = Date(timeIntervalSince1970: 1_791_331_200)

    @Test("audio.hitDetection is bound to eventTimes 1.0.0 at 50 ms, with the gate's metric names")
    func hitDetectionBinding() throws {
        let binding = try BenchmarkBindings.binding(for: "audio.hitDetection", catalog: Self.catalog)
        #expect(binding.task == TaskDescriptor(id: "eventTimes", version: "1.0.0", tolerance: RationalTime(value: 50, timescale: 1000)))
        #expect(binding.metrics.map(\.task) == ["precision", "recall", "onset MAE"])
        #expect(binding.metrics.map(\.gate) == ["own-court hit precision", "own-court hit recall", "onset MAE"])
    }

    @Test("every binding maps each gate metric of its capability exactly once")
    func bindingsCoverTheirGates() throws {
        let bindings = try BenchmarkBindings.load(from: Self.catalog)
        #expect(!bindings.isEmpty)
        for binding in bindings {
            let gate = try Floor.capabilityGate(binding.capabilityId, catalog: Self.catalog)
            #expect(binding.metrics.map(\.gate).sorted() == gate.metrics.map(\.name).sorted(), "\(binding.capabilityId)")
        }
    }

    @Test("a perfect candidate passes the real audio.hitDetection registry gate")
    func perfectCandidatePassesTheRealGate() async throws {
        let binding = try BenchmarkBindings.binding(for: "audio.hitDetection", catalog: Self.catalog)
        let gate = try Floor.capabilityGate("audio.hitDetection", catalog: Self.catalog)
        let record = try await harness.run(PerfectCandidate(), task: EventTimesTask(tolerance: try #require(binding.task.tolerance)),
                                           clipIDs: ["harness/events-s23"], mode: .gate, floor: gate,
                                           capabilityId: "audio.hitDetection", runId: "perfect-candidate", at: at)
        let verdict = try #require(record.verdict)
        #expect(verdict.passed)
        #expect(verdict.checks.map(\.name) == ["own-court hit precision", "own-court hit recall", "onset MAE"])
        #expect(verdict.checks.allSatisfy { $0.passed })
        #expect(record.metrics.map(\.name) == ["own-court hit precision", "own-court hit recall", "onset MAE"])
        #expect(record.metrics.map(\.value) == ["1.0000", "1.0000", "0.000"])
    }

    @Test("a capability run with any other tolerance is refused before the estimator runs")
    func toleranceIsBound() async throws {
        let spy = CountingEstimator(role: .candidate)
        let binding = try BenchmarkBindings.binding(for: "audio.hitDetection", catalog: Self.catalog)
        await #expect(throws: HarnessError.taskIsNotCapabilityBinding(capabilityId: "audio.hitDetection", expected: binding.task)) {
            _ = try await harness.run(spy, task: EventTimesTask(tolerance: RationalTime(value: 200, timescale: 1000)),
                                      clipIDs: ["harness/events-s23"], mode: .gate,
                                      floor: try Floor.capabilityGate("audio.hitDetection", catalog: Self.catalog),
                                      capabilityId: "audio.hitDetection", runId: "refused", at: at)
        }
        #expect(spy.calls.value == 0)
    }

    @Test("a gated capability without a binding is refused before the estimator runs")
    func capabilityWithoutBinding() async throws {
        let spy = CountingEstimator(role: .candidate)
        await #expect(throws: HarnessError.capabilityHasNoBinding("camera.movedDetection")) {
            _ = try await harness.run(spy, task: EventTimesTask(tolerance: RunRequest.defaultTolerance),
                                      clipIDs: ["harness/events-s23"], mode: .gate,
                                      floor: try Floor.capabilityGate("camera.movedDetection", catalog: Self.catalog),
                                      capabilityId: "camera.movedDetection", runId: "refused", at: at)
        }
        #expect(spy.calls.value == 0)
    }

    @Test("a run request takes the binding's tolerance unless one is given")
    func requestTolerance() throws {
        let capability = RunRequest(clipIDs: ["harness/events-s23"], mode: .gate, floor: nil, capabilityId: "audio.hitDetection",
                                    runId: "r", at: at)
        #expect(try capability.resolvedTolerance(catalog: Self.catalog) == RationalTime(value: 50, timescale: 1000))
        let selfTest = RunRequest(clipIDs: ["harness/events-s23"], mode: .gate, floor: .harnessSelfTest, runId: "r", at: at)
        #expect(try selfTest.resolvedTolerance(catalog: Self.catalog) == RunRequest.defaultTolerance)
        let explicit = RunRequest(clipIDs: ["harness/events-s23"], mode: .gate, floor: .harnessSelfTest,
                                  tolerance: RationalTime(value: 20, timescale: 1000), runId: "r", at: at)
        #expect(try explicit.resolvedTolerance(catalog: Self.catalog) == RationalTime(value: 20, timescale: 1000))
    }
}

/// A candidate that happens to be perfect: it returns the truth's event times. Test-only.
struct PerfectCandidate: BenchmarkEstimator {
    var identity: EstimatorIdentity { EstimatorIdentity(id: "perfect.eventTimes", methodVersion: "0", role: .candidate) }
    func estimate(_ clip: BenchmarkClip) async throws -> [RationalTime] {
        (clip.truth.events ?? []).map(\.time)
    }
}
