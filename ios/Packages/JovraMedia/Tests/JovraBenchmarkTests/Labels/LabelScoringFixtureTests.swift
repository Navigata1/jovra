import Foundation
import JovraBenchmark
import Testing

/// `spec/fixtures/labels/L*.json`: synthetic labels, a stage's observations and the rows worked by hand. The
/// Swift scorer must print exactly those rows (the Python reference is spec/reference/jovra_ref/labels.py).
@Suite("Label scorer reproduces the hand-computed fixtures")
struct LabelScoringFixtureTests {
    struct Fixture: Decodable {
        let id: String
        let tolerances: LabelScoringTolerances
        let labels: BenchmarkLabels
        let observations: StageObservations
        let expected: LabelScoreReport
    }

    static let folder = MediaFixtureCatalog.repository().root.appendingPathComponent("spec/fixtures/labels")

    static var files: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix("L") && $0.hasSuffix(".json") }.sorted()
    }

    static func load(_ file: String) throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: folder.appendingPathComponent(file)))
    }

    @Test("both fixtures are committed")
    func committed() {
        #expect(Self.files == ["L01-every-kind-both-splits.json", "L02-undefined-and-open.json"])
    }

    @Test("every row of every split equals the hand-computed one", arguments: files)
    func reproduces(file: String) throws {
        let fixture = try Self.load(file)
        let report = try LabelScorer.score(labels: fixture.labels, observations: fixture.observations, tolerances: fixture.tolerances)
        for (name, actual, expected) in [("tuning", report.tuning, fixture.expected.tuning), ("heldOut", report.heldOut, fixture.expected.heldOut)] {
            #expect(actual.windows == expected.windows, "\(name) windows")
            #expect(actual.durationMs == expected.durationMs, "\(name) duration")
            #expect(actual.rows.count == expected.rows.count, "\(name) row count")
            for (got, want) in zip(actual.rows, expected.rows) {
                #expect(got == want, "\(name) \(want.group) / \(want.name)")
            }
        }
    }

    @Test("the headline numbers of L01, spelled out")
    func headline() throws {
        let fixture = try Self.load("L01-every-kind-both-splits.json")
        let report = try LabelScorer.score(labels: fixture.labels, observations: fixture.observations, tolerances: fixture.tolerances)
        func value(_ rows: [LabelScoreRow], _ group: String, _ name: String) -> String? {
            rows.first { $0.group == group && $0.name == name }?.value
        }
        #expect(value(report.tuning.rows, "hits", "precision") == "0.7500")
        #expect(value(report.tuning.rows, "hits", "recall") == "0.8571")
        #expect(value(report.tuning.rows, "hits", "timing MAE") == "46.667")
        #expect(value(report.heldOut.rows, "hits", "precision") == "0.6000")
        #expect(value(report.heldOut.rows, "hits", "recall") == "0.7500")
        #expect(value(report.heldOut.rows, "hits", "timing bias") == "+13.333")
        #expect(value(report.tuning.rows, "bounces", "placement error median") == "16.00")
        #expect(value(report.heldOut.rows, "bounces", "placement error mean") == "45.00")
        #expect(value(report.heldOut.rows, "rally boundaries", "F1") == "0.5000")
        #expect(value(report.heldOut.rows, "coverage", "analysed share") == "0.6667")
    }

    @Test("observations for another recording are refused before scoring")
    func wrongRecording() throws {
        let one = try Self.load("L01-every-kind-both-splits.json"), two = try Self.load("L02-undefined-and-open.json")
        #expect(throws: LabelScoringError.self) {
            try LabelScorer.score(labels: one.labels, observations: two.observations, tolerances: one.tolerances)
        }
    }

    @Test("the printed report names both splits and never a combined number")
    func text() throws {
        let fixture = try Self.load("L01-every-kind-both-splits.json")
        let report = try LabelScorer.score(labels: fixture.labels, observations: fixture.observations, tolerances: fixture.tolerances)
        let text = report.text()
        #expect(text.contains("tuning"))
        #expect(text.contains("held-out"))
        #expect(text.contains("precision"))
        #expect(text.contains("0.7500"))
        #expect(text.contains("0.6000"))
        #expect(!text.lowercased().contains("overall"))
        #expect(!text.lowercased().contains("combined"))
    }
}
