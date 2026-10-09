// fixture-kind: jovra.fixture.stats
import Foundation
import Testing
import JovraCore

struct StatsFixture: Decodable {
    let id: String
    let input: ScoringInput
    let expected: StatsResult
}
struct StatsRunner: FixtureRunner {
    let kind = "jovra.fixture.stats"
    func run(_ data: Data, path: URL) throws {
        let fixture = try JSONDecoder().decode(StatsFixture.self, from: data)
        let result = try StatsEngine.compute(ScoringEngine.fold(fixture.input))
        #expect(result == fixture.expected, "\(fixture.id)")
        try emitStats(result, name: "\(fixture.id).json")
    }
}
func emitStats(_ result: StatsResult, name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["JOVRA_STATS_OUTPUT_DIR"] else { return }
    let folder = URL(fileURLWithPath: directory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try CanonicalJSON.encode(result).write(to: folder.appendingPathComponent(name), options: .atomic)
}
