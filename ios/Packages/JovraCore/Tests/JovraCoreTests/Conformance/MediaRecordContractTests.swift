import Foundation
import Testing
@testable import JovraCore

@Test func mediaFixtureRecordsHaveRealTypesAndExactRoundTrips() throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec").path) { root.deleteLastPathComponent() }
    let urls = FileManager.default.enumerator(at: root.appendingPathComponent("spec/fixtures"), includingPropertiesForKeys: nil)!.allObjects.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
    for url in urls {
        let data = try Data(contentsOf: url)
        let header = try JSONDecoder().decode(RecordHeader.self, from: data)
        func check<T: Codable>(_ type: T.Type) throws { #expect(try CanonicalJSON.encode(ContractCodec.decode(type, from: data)) == CanonicalJSON.canonicalize(data)) }
        switch header.kind {
        case "jovra.groundTruth": try check(GroundTruthRecord.self)
        case "jovra.benchmarkRecord": try check(BenchmarkRecord.self)
        case "jovra.benchmarkBindings": try check(BenchmarkBindings.self)
        default: break
        }
    }
}
private struct RecordHeader: Decodable { var kind: String }
