// fixture-kind: jovra.fixture.rally
import Foundation
import Testing
import JovraCore

/// spec/fixtures/rally/R*.json: every segment and plan case the Python reference generated (and the validator
/// re-runs) must come out of JovraCore identically, refused inputs with the same error code.
struct RallyRunner: FixtureRunner {
    let kind = "jovra.fixture.rally"

    private struct Fixture: Decodable { var id: String; var cases: [Case] }
    private struct Params: Decodable {
        var durationMs: Int
        var rallyGapMs: Int?, pointGapMs: Int?, preRollMs: Int?, postRollMs: Int?
        var excludedSide: FrameHalf?
    }
    private struct Case: Decodable {
        var op: String
        var name: String
        var hits: [HitCandidate]?
        var marks: [RallyBookmark]?
        var params: Params?
        var targets: [RallyTarget]?
        var rolls: SessionRallyPlayback?
        var durationMs: Int?
        var expectedError: String?
        var expectedSegmentation: RallySegmentation?
        var expectedPlan: RallyOnlyPlan?

        enum CodingKeys: String, CodingKey { case op, name, hits, marks, params, targets, rolls, durationMs, expectedError, expected }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            op = try c.decode(String.self, forKey: .op)
            name = try c.decode(String.self, forKey: .name)
            hits = try c.decodeIfPresent([HitCandidate].self, forKey: .hits)
            marks = try c.decodeIfPresent([RallyBookmark].self, forKey: .marks)
            params = try c.decodeIfPresent(Params.self, forKey: .params)
            targets = try c.decodeIfPresent([RallyTarget].self, forKey: .targets)
            rolls = try c.decodeIfPresent(SessionRallyPlayback.self, forKey: .rolls)
            durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
            expectedError = try c.decodeIfPresent(String.self, forKey: .expectedError)
            if op == "segment" { expectedSegmentation = try c.decodeIfPresent(RallySegmentation.self, forKey: .expected) }
            if op == "plan" { expectedPlan = try c.decodeIfPresent(RallyOnlyPlan.self, forKey: .expected) }
        }
    }

    func run(_ data: Data, path: URL) throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        for c in fixture.cases {
            let outcome: Result<AnyEquatable, RallyError>
            switch c.op {
            case "segment":
                let p = try #require(c.params)
                let parameters = RallySegmentParameters(
                    durationMs: p.durationMs,
                    rallyGapMs: p.rallyGapMs ?? RallySegmentParameters.defaultRallyGapMs,
                    pointGapMs: p.pointGapMs ?? RallySegmentParameters.defaultPointGapMs,
                    preRollMs: p.preRollMs ?? RallyRolls.defaultPreRollMs,
                    postRollMs: p.postRollMs ?? RallyRolls.defaultPostRollMs,
                    excludedSide: p.excludedSide)
                do { outcome = .success(AnyEquatable(try RallySegmenter.segment(hits: c.hits, bookmarks: c.marks ?? [], parameters: parameters))) }
                catch { outcome = .failure(error) }
                check(outcome, c, expected: c.expectedSegmentation.map(AnyEquatable.init), fixture: fixture.id)
            case "plan":
                let duration = try #require(c.durationMs)
                do { outcome = .success(AnyEquatable(try RallyOnlyPlan.build(targets: c.targets ?? [], rolls: c.rolls, durationMs: duration))) }
                catch { outcome = .failure(error) }
                check(outcome, c, expected: c.expectedPlan.map(AnyEquatable.init), fixture: fixture.id)
            default:
                Issue.record("Unknown rally operation \(c.op) in \(fixture.id)")
            }
        }
        print("rally vectors \(fixture.id): \(fixture.cases.count)")
    }

    private func check(_ outcome: Result<AnyEquatable, RallyError>, _ c: Case, expected: AnyEquatable?, fixture: String) {
        switch outcome {
        case .success(let value):
            #expect(c.expectedError == nil, "\(fixture) '\(c.name)': expected \(c.expectedError ?? "") but got a result")
            #expect(value == expected, "\(fixture) '\(c.name)'")
        case .failure(let error):
            #expect(error.code == c.expectedError, "\(fixture) '\(c.name)': refused with \(error.code)")
        }
    }
}

/// Lets one helper compare either result type.
private struct AnyEquatable: Equatable {
    private let value: any Equatable
    private let equals: (any Equatable) -> Bool
    init<T: Equatable>(_ value: T) {
        self.value = value
        self.equals = { ($0 as? T) == value }
    }
    static func == (lhs: AnyEquatable, rhs: AnyEquatable) -> Bool { lhs.equals(rhs.value) }
}
