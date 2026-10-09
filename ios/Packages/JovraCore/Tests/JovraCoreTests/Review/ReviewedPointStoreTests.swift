import Foundation
import JovraCore
import Testing

@Test func durableReviewedPointsAndCorrectionsRecomputeLaterScoresAndStats() async throws {
    let root = try FixtureManifest.repository()
    var document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: root.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    document.match?.log = []
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(root: directory)
    try await store.create(document)
    var events: [SessionPointEvent] = []
    for (index, winner) in [Side.a, .a, .a, .b].enumerated() {
        events.append(try await store.appendReviewedPoint(winner: winner, startMs: index * 1000,
                                                         endMs: (index + 1) * 1000, for: document.id))
    }
    let before = try await store.load(document.id)
    let originalLog = try #require(before.match?.log)
    let correction = try await store.correctReviewedWinner(pointID: events[0].id, winner: .b, for: document.id)
    let reopened = try SessionStore(root: directory)
    let edited = try await reopened.load(document.id)
    #expect(Array(try #require(edited.match?.log).prefix(4)) == originalLog)
    #expect(correction.supersedes == events[0].id)
    let timeline = try ScoringEngine.fold(ScoringInput(session: edited))
    #expect(timeline.points.count == 4)
    #expect(timeline.points[1].call == .init(.points(.init(server: .value0, receiver: .value15))))
    let stats = try StatsEngine.compute(timeline)
    #expect(stats.sides.A.totalPointsWon.n == 2 && stats.sides.A.totalPointsWon.d == 4)
    #expect(timeline.points.allSatisfy { $0.reviewState == .reviewed && $0.provenance == .reviewed })
    _ = try await reopened.correctReviewedWinner(pointID: correction.id, winner: .a, for: document.id)
    let restored = try await reopened.load(document.id)
    let restoredStats = try StatsEngine.compute(ScoringEngine.fold(ScoringInput(session: restored)))
    #expect(restoredStats.sides.A.totalPointsWon.n == 3)
    if let output = ProcessInfo.processInfo.environment["JOVRA_REVIEW_SESSION_OUTPUT"] {
        try CanonicalJSON.encode(restored).write(to: URL(fileURLWithPath: output))
    }
    #expect(restored.recording == document.recording && restored.archive == document.archive)
    let bytes = try Data(contentsOf: directory.appendingPathComponent("sessions/\(document.id)/session.json"))
    await #expect(throws: PointReviewError.invalidRange) {
        _ = try await reopened.appendReviewedPoint(winner: .a, startMs: -1, endMs: 500, for: document.id)
    }
    await #expect(throws: PointReviewError.pointUnavailable) {
        _ = try await reopened.correctReviewedWinner(pointID: events[0].id, winner: .b, for: document.id)
    }
    #expect(try Data(contentsOf: directory.appendingPathComponent("sessions/\(document.id)/session.json")) == bytes)
}

@Test func winnerOnlyCorrectionDoesNotPromoteAnUnreviewedEstimate() async throws {
    let root = try FixtureManifest.repository()
    var document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: root.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    guard case .point(var point) = try #require(document.match?.log.first) else {
        Issue.record("Sample first entry must be a point"); return
    }
    var estimated = try #require(point.reviewed)
    estimated.provenance = .estimated
    point.detected = estimated; point.reviewed = nil; point.reviewState = .unreviewed
    document.match?.log = [.point(point)]
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(root: directory)
    try await store.create(document)
    await #expect(throws: PointReviewError.reviewedOutcomeRequired) {
        _ = try await store.correctReviewedWinner(pointID: point.id, winner: .b, for: document.id)
    }
    #expect(try await store.load(document.id) == document)
}
