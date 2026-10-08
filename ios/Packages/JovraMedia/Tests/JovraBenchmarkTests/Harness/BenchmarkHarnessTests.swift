import Foundation
import JovraBenchmark
import Testing

/// The harness against the committed harness ground truth (scripts/media set `harness`): seed 11 is the
/// tuning seed and seed 23 the held-out seed.
@Suite("Benchmark harness")
struct BenchmarkHarnessTests {
    static let catalog = MediaFixtureCatalog.repository()
    let harness = BenchmarkHarness(catalog: Self.catalog)
    let task = EventTimesTask(tolerance: RationalTime(value: 50, timescale: 1000))
    let at = Date(timeIntervalSince1970: 1_791_331_200)

    @Test("the oracle passes the floor on the held-out seed")
    func oraclePasses() async throws {
        let record = try await harness.run(OracleEventEstimator(), task: task, clipIDs: ["harness/events-s23"],
                                           mode: .gate, floor: .harnessSelfTest, runId: "oracle-test", at: at)
        let verdict = try #require(record.verdict)
        #expect(verdict.passed)
        #expect(verdict.checks.allSatisfy { $0.passed })
        #expect(record.metrics.map(\.value) == ["1.0000", "1.0000", "0.000"])
        #expect(record.estimator == EstimatorIdentity(id: "oracle.eventTimes", methodVersion: "1.0.0", role: .oracle))
        #expect(record.clips.map(\.split) == [.heldOut])
    }

    @Test("the null estimator fails the floor: recall 0, precision and MAE undefined")
    func nullFails() async throws {
        let record = try await harness.run(NullEventEstimator(), task: task, clipIDs: ["harness/events-s23"],
                                           mode: .gate, floor: .harnessSelfTest, runId: "null-test", at: at)
        let verdict = try #require(record.verdict)
        #expect(!verdict.passed)
        #expect(verdict.checks.map(\.passed) == [false, false, false])
        #expect(record.metrics.map(\.value) == [nil, "0.0000", nil])
    }

    @Test("gating on a tuning seed is refused before the estimator runs")
    func tuningSeedCannotGate() async throws {
        let spy = CountingEstimator()
        await #expect(throws: HarnessError.tuningSeedCannotGate(clipIDs: ["harness/events-s11"])) {
            _ = try await harness.run(spy, task: task, clipIDs: ["harness/events-s11", "harness/events-s23"],
                                      mode: .gate, floor: .harnessSelfTest, runId: "refused", at: at)
        }
        #expect(spy.calls.value == 0)
    }

    @Test("a clip with no benchmark split cannot be gated on")
    func unsplitClipCannotGate() async throws {
        await #expect(throws: HarnessError.clipHasNoSplit(clipIDs: ["fixtureCamera/fixture-camera"])) {
            _ = try await harness.run(OracleEventEstimator(), task: task, clipIDs: ["fixtureCamera/fixture-camera"],
                                      mode: .gate, floor: .harnessSelfTest, runId: "refused", at: at)
        }
    }

    @Test("a gating run needs a floor")
    func gateNeedsFloor() async throws {
        await #expect(throws: HarnessError.gateNeedsFloor) {
            _ = try await harness.run(OracleEventEstimator(), task: task, clipIDs: ["harness/events-s23"],
                                      mode: .gate, floor: nil, runId: "refused", at: at)
        }
    }

    @Test("tuning runs use tuning seeds only and carry no verdict")
    func tuningRun() async throws {
        let record = try await harness.run(NullEventEstimator(), task: task, clipIDs: ["harness/events-s11"],
                                           mode: .tuning, floor: .harnessSelfTest, runId: "tuning-test", at: at)
        #expect(record.verdict == nil)
        #expect(record.mode == .tuning)
        await #expect(throws: HarnessError.heldOutSeedInTuning(clipIDs: ["harness/events-s23"])) {
            _ = try await harness.run(NullEventEstimator(), task: task, clipIDs: ["harness/events-s23"],
                                      mode: .tuning, floor: nil, runId: "refused", at: at)
        }
    }

    @Test("the record carries the truth-events digest the reference validator recomputes")
    func truthDigest() async throws {
        let record = try await harness.run(OracleEventEstimator(), task: task, clipIDs: ["harness/events-s23"],
                                           mode: .gate, floor: .harnessSelfTest, runId: "digest", at: at)
        let truth = try Self.catalog.truth(id: "harness/events-s23")
        #expect(record.clips[0].truthEventsSha256 == EventTimesTask.truthEventsSha256(truth))
        #expect(record.clips[0].seed == 23)
        #expect(record.clips[0].outputs == .array(try #require(truth.events).map { .time($0.time) }))
    }
}

/// Counts calls so a refusal can be shown to happen before any estimation.
final class CountingEstimator: BenchmarkEstimator, @unchecked Sendable {
    let calls = Counter()
    let role: EstimatorRole
    init(role: EstimatorRole = .candidate) { self.role = role }
    var identity: EstimatorIdentity { EstimatorIdentity(id: "spy.eventTimes", methodVersion: "0", role: role) }
    func estimate(_ clip: BenchmarkClip) async throws -> [RationalTime] {
        calls.increment()
        return []
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
