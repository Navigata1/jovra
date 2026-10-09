// fixture-kind: jovra.fixture.scoring
import Foundation
import Testing
@testable import JovraCore

struct ScoringFixture: Decodable {
    let id: String
    let input: ScoringInput
    let checkpoints: [Checkpoint]?
    let expectError: Refusal?
    struct Checkpoint: Decodable {
        let afterSeq: Int
        let expected: Expected
    }
    struct Expected: Decodable { let fold: MatchTimeline }
    struct Refusal: Decodable { let code: String }
}

struct ScoringRunner: FixtureRunner {
    let kind = "jovra.fixture.scoring"
    func run(_ data: Data, path: URL) throws {
        let fixture = try JSONDecoder().decode(ScoringFixture.self, from: data)
        if let error = fixture.expectError {
            do { _ = try ScoringEngine.fold(fixture.input); Issue.record("Expected \(error.code): \(fixture.id)") }
            catch let actual as ScoringError { #expect(actual.code.rawValue == error.code, "\(fixture.id)") }
            return
        }
        let checkpoints = fixture.checkpoints ?? []
        let results = try ScoringEngine.checkpoints(fixture.input, afterSeqs: checkpoints.map(\.afterSeq))
        for (index, result) in results.enumerated() {
            #expect(result == checkpoints[index].expected.fold, "\(fixture.id) checkpoint \(index)")
            if let directory = ProcessInfo.processInfo.environment["JOVRA_SCORING_OUTPUT_DIR"] {
                let folder = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try CanonicalJSON.encode(result).write(to: folder.appendingPathComponent("\(fixture.id)-\(index).json"), options: .atomic)
            }
        }
        // T05 adds the independent stats comparison; consuming the scoring kind means fold coverage.
    }
}
