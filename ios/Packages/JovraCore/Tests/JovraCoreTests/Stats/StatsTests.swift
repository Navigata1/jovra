import Foundation
import Testing
import JovraCore

@Test func sampleOverviewStatsMatchIndependentValues() throws {
    let root = try FixtureManifest.repository()
    let document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: root.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    let timeline = try ScoringEngine.fold(ScoringInput(session: document))
    let stats = try StatsEngine.compute(timeline)
    #expect(stats.countedPoints == 124)
    #expect(stats.sides.A.totalPointsWon == RateRatio(n: 72, d: 124, pct: .init(58), display: "58%"))
    #expect(stats.sides.A.firstServeIn == RateRatio(n: 40, d: 60, pct: .init(67), display: "67%"))
    #expect(stats.sides.A.firstServePointsWon == RateRatio(n: 28, d: 40, pct: .init(70), display: "70%"))
    #expect(stats.shots.total == 386)
}

@Test func estimatedContributorKeepsHeadlineStatProvisionalAndTraceable() throws {
    let root = try FixtureManifest.repository()
    let document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: root.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    var timeline = try ScoringEngine.fold(ScoringInput(session: document))
    timeline.points[0].provenance = .estimated
    timeline.points[0].reviewState = .unreviewed
    let stat = try StatsEngine.stat(.pointsWon(.a), in: timeline, sample: true)
    #expect(stat.value == .ratio(.init(n: 72, d: 124, pct: .init(58), display: "58%")))
    #expect(stat.evidence.provenance == .estimated)
    #expect(stat.evidence.contributingPointIDs.count == 124)
    #expect(stat.evidence.contributingPointIDs.first == timeline.points[0].id)
    #expect(stat.evidence.unreviewedCount == 9) // Changed first point plus eight existing needs-review points.
    #expect(stat.evidence.sample)
    for index in timeline.points.indices { timeline.points[index].reviewState = .reviewed }
    timeline.points[0].reviewState = .unreviewed
    let singleUnreviewed = try StatsEngine.stat(.pointsWon(.a), in: timeline)
    #expect(singleUnreviewed.evidence.provenance == .estimated && singleUnreviewed.evidence.unreviewedCount == 1)
}

@Test func missingShotObservationsAreUnknownRatherThanMeasuredZero() throws {
    let root = try FixtureManifest.repository()
    let document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: root.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    var timeline = try ScoringEngine.fold(ScoringInput(session: document))
    for index in timeline.points.indices { timeline.points[index].strokeCount = .init(nil) }
    let numeric = try StatsEngine.compute(timeline)
    #expect(numeric.shots.total == 0 && numeric.shots.pointsWithStrokeCount == 0)
    let stat = try StatsEngine.stat(.shots, in: timeline)
    #expect(stat.value == nil && stat.evidence.provenance == nil)
    #expect(stat.evidence.contributingPointIDs.isEmpty)
    timeline.points[0].strokeCount = .init(0)
    let observedZero = try StatsEngine.stat(.shots, in: timeline)
    #expect(observedZero.value == .count(0))
    #expect(observedZero.evidence.contributingPointIDs == [timeline.points[0].id])
}

@Test func serveRateUsesDenominatorContributorsFromOnlyTheChosenSide() throws {
    let root = try FixtureManifest.repository()
    let document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: root.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    var timeline = try ScoringEngine.fold(ScoringInput(session: document))
    for index in timeline.points.indices {
        timeline.points[index].provenance = timeline.points[index].serverSide.value == .a ? .validated : .estimated
    }
    let stat = try StatsEngine.stat(.firstServeIn(.a), in: timeline)
    #expect(stat.value == .ratio(.init(n: 40, d: 60, pct: .init(67), display: "67%")))
    #expect(stat.evidence.contributingPointIDs.count == 60)
    #expect(stat.evidence.provenance == .validated)
    #expect(!stat.evidence.sample)
}

@Test func momentumAndRequiredNullableDurationKeepTheirClosedContract() throws {
    for invalid in ["[1]", "[1,2,3]", "[1,1.5]"] {
        #expect(throws: (any Error).self) { try ContractCodec.decode(StatsMomentumPair.self, from: Data(invalid.utf8)) }
    }
    let root = try FixtureManifest.repository()
    let fixture = try JSONDecoder().decode(StatsFixture.self, from: Data(contentsOf: root.appendingPathComponent("spec/fixtures/stats/T04-tiebreak-not-a-service-game.json")))
    let encoded = try CanonicalJSON.encode(fixture.expected)
    #expect(try ContractCodec.decode(StatsResult.self, from: encoded) == fixture.expected)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "durationMs")
    #expect(throws: (any Error).self) { try ContractCodec.decode(StatsResult.self, from: JSONSerialization.data(withJSONObject: object)) }
}
