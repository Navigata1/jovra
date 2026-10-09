import Foundation
import Testing
@testable import JovraCore

struct ScoringTests {
    @Test func loveHoldMatchesIndependentFold() throws {
        let root = try FixtureManifest.repository()
        let path = root.appendingPathComponent("spec/fixtures/scoring/S01-love-hold.json")
        let data = try Data(contentsOf: path)
        let fixture = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let input = try JSONDecoder().decode(ScoringInput.self, from: JSONSerialization.data(withJSONObject: fixture["input"]!))
        var result = try ScoringEngine.fold(input)
        result.changes = .null
        let expected = (((fixture["checkpoints"] as! [[String: Any]])[0])["expected"] as! [String: Any])["fold"]!
        #expect(try CanonicalJSON.encode(result) == CanonicalJSON.canonicalize(JSONSerialization.data(withJSONObject: expected)))
    }
}

@Test func publicScoringBoundaryRefusesInvalidContexts() throws {
    let path = try FixtureManifest.repository().appendingPathComponent("spec/fixtures/scoring/S01-love-hold.json")
    let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
    let object = fixture["input"] as! [String: Any]
    let data = try JSONSerialization.data(withJSONObject: object)
    var input = try ScoringInput.decode(data)
    input.sides.A = []
    #expect(throws: ScoringError(.invalidSetup, "sides")) { try ScoringEngine.fold(input) }
    var zero = try ScoringInput.decode(data)
    if case .point(var point) = zero.log[0] { point.seq = 0; zero.log[0] = .point(point) }
    #expect(throws: ScoringError(.seqNotIncreasing, "e001")) { try ScoringEngine.fold(zero) }
    var unknown = object
    var log = unknown["log"] as! [[String: Any]]; log[0]["type"] = "futurePoint"; unknown["log"] = log
    do { _ = try ScoringInput.decode(JSONSerialization.data(withJSONObject: unknown)); Issue.record("Unknown event decoded") }
    catch let error as ScoringError { #expect(error.code == .unknownEventType) }
    var mode = object; mode["resolutionMode"] = "future"
    do { _ = try ScoringInput.decode(JSONSerialization.data(withJSONObject: mode)); Issue.record("Unknown mode decoded") }
    catch let error as ScoringError { #expect(error.code == .invalidResolutionMode) }
}

@Test func timelineKeepsAbsentAndExplicitNullChangesDistinct() throws {
    let path = try FixtureManifest.repository().appendingPathComponent("spec/fixtures/scoring/S01-love-hold.json")
    let fixture = try JSONDecoder().decode(ScoringFixture.self, from: Data(contentsOf: path))
    var timeline = try ScoringEngine.fold(fixture.input)
    let absent = try CanonicalJSON.encode(timeline)
    #expect(try ContractCodec.decode(MatchTimeline.self, from: absent).changes == nil)
    timeline.changes = .null
    let explicit = try CanonicalJSON.encode(timeline)
    #expect(try ContractCodec.decode(MatchTimeline.self, from: explicit).changes == .null)
    #expect(absent != explicit)
}

@Test func sampleSessionUsesSamePublicFold() throws {
    let root = try FixtureManifest.repository()
    let document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: root.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    let input = try ScoringInput(session: document)
    let result = try ScoringEngine.fold(input)
    let expectedFile = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.expected.json"))) as! [String: Any]
    let expected = (expectedFile["expected"] as! [String: Any])["fold"]!
    #expect(try CanonicalJSON.encode(result) == CanonicalJSON.canonicalize(JSONSerialization.data(withJSONObject: expected)))
    #expect(result.match.pointsPlayed == 124)
    #expect(try ScoringEngine.fold(input) == result)
}

private func loveHoldInput() throws -> ScoringInput {
    let path = try FixtureManifest.repository().appendingPathComponent("spec/fixtures/scoring/S01-love-hold.json")
    return try JSONDecoder().decode(ScoringFixture.self, from: Data(contentsOf: path)).input
}

@Test func negativeCheckpointIndexRefusesBeforeLookup() throws {
    var input = try loveHoldInput()
    input.log.append(.checkpoint(.init(id: "bad-checkpoint", seq: 5, setIndex: -1, games: .zero)))
    #expect(throws: ScoringError(.invalidSetup, "bad-checkpoint")) { try ScoringEngine.fold(input) }
}

@Test func cyclicFutureCorrectionAnchorRefuses() throws {
    var input = try loveHoldInput()
    input.log = Array(input.log.prefix(3))
    if case .point(var p) = input.log[0] { p.insertBefore = input.log[1].id; input.log[0] = .point(p) }
    if case .point(var p) = input.log[1] { p.supersedes = input.log[2].id; input.log[1] = .point(p) }
    if case .point(var p) = input.log[2] { p.supersedes = input.log[1].id; input.log[2] = .point(p) }
    if let path = ProcessInfo.processInfo.environment["JOVRA_CYCLE_PROBE_MARKER"] {
        try Data("ENTERED_NATIVE_PUBLIC_FOLD\n".utf8).write(to: URL(fileURLWithPath: path))
    }
    #expect(throws: ScoringError(.insertTargetMissing, "e001")) { try ScoringEngine.fold(input) }
}
