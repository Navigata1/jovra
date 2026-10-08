import Foundation
import JovraBenchmark
import Testing

/// A candidate record is tied to the media it analysed: the harness refuses a candidate run whose clip is not
/// rendered, or whose rendered clip does not decode to the committed decoded-frame hash, before estimating,
/// and every record clip carries the renderer source hash and decoded-frame hash of its ground truth.
@Suite("Benchmark media provenance")
struct MediaProvenanceTests {
    static let catalog = MediaFixtureCatalog.repository()
    let task = EventTimesTask(tolerance: RationalTime(value: 50, timescale: 1000))
    let at = Date(timeIntervalSince1970: 1_791_331_200)

    /// A scratch repository with the committed truth, registry and bindings, and a render cache of its own.
    static func scratchRepository() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("jovra-media-provenance-\(UUID().uuidString)")
        for path in ["spec/fixtures/media/harness/events-s23.truth.json", "spec/fixtures/media/harness/events-s11.truth.json",
                     "spec/fixtures/media/benchmark-bindings.json", CapabilityRegistryGates.path] {
            let target = root.appendingPathComponent(path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: catalog.root.appendingPathComponent(path), to: target)
        }
        return root
    }

    @Test("a candidate run on a clip that is not rendered is refused before the estimator runs")
    func candidateNeedsRenderedMedia() async throws {
        let root = try Self.scratchRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let scratch = MediaFixtureCatalog(root: root)
        let truth = try scratch.truth(id: "harness/events-s23")
        let spy = CountingEstimator(role: .candidate)
        await #expect(throws: MediaFixtureError.notRendered(path: truth.media.path)) {
            _ = try await BenchmarkHarness(catalog: scratch).run(spy, task: task, clipIDs: ["harness/events-s23"], mode: .gate,
                                                                 floor: .harnessSelfTest, runId: "refused", at: at)
        }
        #expect(spy.calls.value == 0)
    }

    @Test("a candidate run on a rendered clip that is not the committed media is refused before the estimator runs")
    func candidateNeedsTheCommittedMedia() async throws {
        let source = try Self.catalog.mediaURL(for: try Self.catalog.truth(id: "harness/events-s11"))
        let root = try Self.scratchRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let scratch = MediaFixtureCatalog(root: root)
        let truth = try scratch.truth(id: "harness/events-s23")
        let impostor = root.appendingPathComponent(truth.media.path)
        try FileManager.default.createDirectory(at: impostor.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: impostor)   // seed 11's media under seed 23's name
        let spy = CountingEstimator(role: .candidate)
        let decoded = try await DecodedFrameReader.signatureHash(of: impostor, truth: truth).sha256
        await #expect(throws: HarnessError.mediaDoesNotMatchTruth(clipID: "harness/events-s23",
                                                                 expected: truth.signature.decodedFramesSha256, decoded: decoded)) {
            _ = try await BenchmarkHarness(catalog: scratch).run(spy, task: task, clipIDs: ["harness/events-s23"], mode: .gate,
                                                                 floor: .harnessSelfTest, runId: "refused", at: at)
        }
        #expect(spy.calls.value == 0)
    }

    @Test("a candidate reads the verified media file")
    func candidateGetsMediaURL() async throws {
        let truth = try Self.catalog.truth(id: "harness/events-s23")
        let probe = MediaURLProbe()
        _ = try await BenchmarkHarness(catalog: Self.catalog).run(probe, task: task, clipIDs: ["harness/events-s23"], mode: .gate,
                                                                  floor: .harnessSelfTest, runId: "media", at: at)
        #expect(probe.seen.value == [try Self.catalog.mediaURL(for: truth)])
    }

    @Test("every record clip carries its truth's renderer source hash and decoded-frame hash",
          arguments: [EstimatorRole.candidate, .oracle])
    func recordCarriesMediaHashes(role: EstimatorRole) async throws {
        let truth = try Self.catalog.truth(id: "harness/events-s23")
        let record = try await BenchmarkHarness(catalog: Self.catalog).run(
            CountingEstimator(role: role), task: task, clipIDs: ["harness/events-s23"], mode: .gate,
            floor: .harnessSelfTest, runId: "hashes", at: at)
        #expect(record.clips.map(\.rendererSourceHash) == [truth.renderer.sourceHash])
        #expect(record.clips.map(\.decodedFramesSha256) == [truth.signature.decodedFramesSha256])
    }

    @Test("an overflowing tolerance names itself in the error")
    func overflowNamesTheTolerance() async throws {
        let huge = EventTimesTask(tolerance: RationalTime(value: .max, timescale: 1))
        do {
            _ = try await BenchmarkHarness(catalog: Self.catalog).run(OracleEventEstimator(), task: huge, clipIDs: ["harness/events-s23"],
                                                                      mode: .gate, floor: .harnessSelfTest, runId: "overflow", at: at)
            Issue.record("expected RationalOverflow")
        } catch let error as RationalOverflow {
            #expect(String(describing: error).contains("tolerance 9223372036854775807/1"), "\(error)")
            #expect(!String(describing: error).contains("RationalOverflow("), "\(error)")
        }
    }
}

/// Records the media URL each clip was handed. Test-only.
final class MediaURLProbe: BenchmarkEstimator, @unchecked Sendable {
    let seen = Box<[URL?]>([])
    var identity: EstimatorIdentity { EstimatorIdentity(id: "probe.eventTimes", methodVersion: "0", role: .candidate) }
    func estimate(_ clip: BenchmarkClip) async throws -> [RationalTime] {
        seen.update { $0.append(clip.mediaURL) }
        return []
    }
}

final class Box<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func update(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
}
