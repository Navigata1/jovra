// fixture-kind: jovra.fixture.sample
import Foundation
import Testing
import JovraCore

struct SampleFixture: Decodable {
    let sessionFile: String
    let csv: Files
    let expected: Expected
    struct Files: Decodable { let points: String; let stats: String }
    struct Expected: Decodable { let fold: MatchTimeline; let stats: StatsResult }
}
struct SampleRunner: FixtureRunner {
    let kind = "jovra.fixture.sample"
    func run(_ data: Data, path: URL) throws {
        let fixture = try JSONDecoder().decode(SampleFixture.self, from: data)
        let folder = path.deletingLastPathComponent()
        let source = folder.appendingPathComponent(fixture.sessionFile)
        let document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: source))
        let timeline = try ScoringEngine.fold(ScoringInput(session: document))
        #expect(timeline == fixture.expected.fold)
        #expect(try StatsEngine.compute(timeline) == fixture.expected.stats)
        let exported = try DataExporter.exportSession(document)
        #expect(exported.pointsCSV == (try Data(contentsOf: folder.appendingPathComponent(fixture.csv.points))))
        #expect(exported.statsCSV == (try Data(contentsOf: folder.appendingPathComponent(fixture.csv.stats))))
        if let directory = ProcessInfo.processInfo.environment["JOVRA_DATA_EXPORT_OUTPUT_DIR"] {
            let root = try FixtureManifest.repository()
            let relative = String(source.path.dropFirst(root.path.count + 1))
            let target = URL(fileURLWithPath: directory).appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try exported.sessionJSON.write(to: target, options: .atomic)
        }
    }
}
