import Foundation
import JovraBenchmark
import JovraCore
import Testing

/// T13: the court-calibration benchmark task scores exactly (hand-worked), and the committed record
/// (spec/benchmarks/court-calibration/fourTap.gate.json) is what the harness writes today. Re-running needs the
/// rendered corpus serves clips (`python3 scripts/media/render.py --set corpus`); without them that test is skipped.
@Suite("Court calibration benchmark")
struct CourtCalibrationTaskTests {
    static let catalog = MediaFixtureCatalog.repository()
    static let recordURL = catalog.root.appendingPathComponent("spec/benchmarks/court-calibration/fourTap.gate.json")
    static let nearHalfRecordURL = catalog.root.appendingPathComponent("spec/benchmarks/court-calibration/fourTap.nearHalf.gate.json")

    static var corpusRendered: Bool {
        ["corpus/serves-s221", "corpus/serves-s222"].allSatisfy { id in
            (try? catalog.mediaURL(for: catalog.truth(id: id))) != nil
        }
    }

    @Test("scoring is exact and split by half: 100 mm off counts as within, 101 mm does not")
    func handWorkedScore() throws {
        let truth = try Self.catalog.truth(id: "corpus/serves-s221")
        let task = CourtCalibrationTask(catalog: Self.catalog)
        var intersections = CourtCalibrationTask.untapped.map { [Int64(($0.point.x * 1000).rounded()), Int64(($0.point.y * 1000).rounded())] }
        // Untapped order: near singles corners, far singles corners, near service corners, far service corners, ...
        intersections[0][0] += 60; intersections[0][1] += 80     // near half, 100 mm: within
        intersections[1][1] += 101                                 // near half, 101 mm: outside
        intersections[2][1] -= 150                                 // far half, 150 mm: outside
        // Bounces read back exactly at the truth: 12 serves in this clip.
        let serves = try JSONDecoder().decode(Serves.self, from: Data(contentsOf: Self.catalog.truthDirectory.appendingPathComponent("corpus/serves-s221.truth.json")))
        let bounces = serves.serves.map { [$0.bounce.courtMm.x, $0.bounce.courtMm.y - 11_885] }
        let draw = CourtCalibrationDraw(tapsMillipx: [], intersectionsMm: intersections, bouncesMm: bounces)
        let metrics = try task.score(truths: [truth], outputs: [[draw]])
        #expect(metrics.map(\.name) == [
            "intersections within 0.10 m", "intersection MSE",
            "near-half intersections within 0.10 m", "near-half intersection MSE", "near-half worst squared error",
            "far-half intersections within 0.10 m", "far-half intersection MSE", "far-half worst squared error",
            "bounces within 0.10 m", "bounce MSE",
        ])
        #expect(metrics[0].exact == Rational(10, 12))
        #expect(metrics[1].exact == Rational(10_000 + 10_201 + 22_500, 12))
        // Six untapped intersections on each side of the net.
        #expect(metrics[2].exact == Rational(5, 6) && metrics[3].exact == Rational(10_000 + 10_201, 6))
        #expect(metrics[4].exact == Rational(10_201) && metrics[4].unit == "mm2")
        #expect(metrics[5].exact == Rational(5, 6) && metrics[6].exact == Rational(22_500, 6))
        #expect(metrics[7].exact == Rational(22_500))
        #expect(metrics[8].exact == Rational(1) && metrics[9].exact == Rational(0))
        #expect(metrics[1].value == "3558.417" && metrics[1].unit == "mm2")
    }

    @Test("the untapped intersections split six and six across the net")
    func halves() {
        let near = CourtCalibrationTask.untapped.filter { $0.point.y < 0 }, far = CourtCalibrationTask.untapped.filter { $0.point.y > 0 }
        #expect(near.count == 6 && far.count == 6)
        #expect(Set(near) == [.nearLeftSingles, .nearRightSingles, .nearLeftService, .nearRightService, .nearServiceT, .nearCentreMark])
    }

    @Test("a draw with the wrong number of estimates is refused")
    func wrongCount() throws {
        let truth = try Self.catalog.truth(id: "corpus/serves-s221")
        let draw = CourtCalibrationDraw(tapsMillipx: [], intersectionsMm: [[0, 0]], bouncesMm: [])
        #expect(throws: CourtCalibrationTask.TaskError.self) {
            _ = try CourtCalibrationTask(catalog: Self.catalog).score(truths: [truth], outputs: [[draw]])
        }
    }

    @Test("the committed record is reproduced by the harness", .enabled(if: corpusRendered))
    func committedRecordReproduces() async throws {
        let committed = try JSONDecoder().decode(JovraBenchmark.BenchmarkRecord.self, from: Data(contentsOf: Self.recordURL))
        #expect(committed.capabilityId == nil, "court.calibration is manual and ungated: the record promotes nothing")
        #expect(committed.verdict?.passed == false, "the literal T13 claim fails at the far baseline (see evidence)")
        let fresh = try await EstimatorRegistry.rerun(committed, harness: BenchmarkHarness(catalog: Self.catalog))
        #expect(try fresh.content.encoded() == committed.content.encoded())
    }

    @Test("the near-half record is reproduced and passes; the far half is reported, not gated", .enabled(if: corpusRendered))
    func nearHalfRecordReproduces() async throws {
        let committed = try JSONDecoder().decode(JovraBenchmark.BenchmarkRecord.self, from: Data(contentsOf: Self.nearHalfRecordURL))
        #expect(committed.capabilityId == nil, "court.calibration is manual and ungated: the record promotes nothing")
        #expect(committed.verdict?.passed == true)
        #expect(committed.floor?.metrics.map(\.name) == ["near-half intersections within 0.10 m"])
        let fresh = try await EstimatorRegistry.rerun(committed, harness: BenchmarkHarness(catalog: Self.catalog))
        #expect(try fresh.content.encoded() == committed.content.encoded())
    }

    private struct Serves: Decodable {
        struct Serve: Decodable { struct Bounce: Decodable { struct MM: Decodable { let x: Int64; let y: Int64 }; let courtMm: MM }; let bounce: Bounce }
        let serves: [Serve]
    }
}
