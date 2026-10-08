import Foundation
import JovraBenchmark
import Testing

/// The committed harness self-test records (spec/fixtures/media/benchmark) are exactly what the current
/// harness writes: re-running each record's estimator reproduces everything but the run id and time.
@Suite("Committed benchmark records are reproducible")
struct CommittedRecordTests {
    static let catalog = MediaFixtureCatalog.repository()
    static let folder = catalog.truthDirectory.appendingPathComponent("benchmark")

    static var recordFiles: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
    }

    @Test("oracle gate, null gate and a tuning run are committed")
    func expectedRecords() {
        #expect(Set(Self.recordFiles).isSuperset(of: ["null.gate.json", "oracle.gate.json", "oracle.tuning.json"]))
    }

    @Test("re-running the estimator reproduces the record", arguments: recordFiles)
    func reproducible(file: String) async throws {
        let data = try Data(contentsOf: Self.folder.appendingPathComponent(file))
        let committed = try JSONDecoder().decode(BenchmarkRecord.self, from: data)
        let fresh = try await EstimatorRegistry.rerun(committed, harness: BenchmarkHarness(catalog: Self.catalog))
        #expect(fresh.content == committed.content)
        #expect(try fresh.content.encoded() == committed.content.encoded())
    }

    @Test("the committed gate records pass and fail as the self-test requires")
    func verdicts() throws {
        let decode = { (name: String) throws -> BenchmarkRecord in
            try JSONDecoder().decode(BenchmarkRecord.self, from: Data(contentsOf: Self.folder.appendingPathComponent(name)))
        }
        #expect(try decode("oracle.gate.json").verdict?.passed == true)
        #expect(try decode("null.gate.json").verdict?.passed == false)
        #expect(try decode("oracle.tuning.json").verdict == nil)
    }
}
