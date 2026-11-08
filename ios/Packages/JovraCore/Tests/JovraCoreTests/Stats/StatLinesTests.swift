import Foundation
import Testing
import JovraCore

private func sampleTimeline() throws -> (SessionDocument, MatchTimeline) {
    let root = try FixtureManifest.repository()
    let document = try ContractCodec.decode(SessionDocument.self,
        from: Data(contentsOf: root.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    return (document, try ScoringEngine.fold(ScoringInput(session: document)))
}

/// Golden stats.csv rows keyed by "stat|side", parsed independently of the exporter.
private func goldenStatsRows() throws -> [String: (n: Int, d: Int?)] {
    let root = try FixtureManifest.repository()
    let text = try String(contentsOf: root.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.stats.csv"), encoding: .utf8)
    var rows: [String: (n: Int, d: Int?)] = [:]
    for line in text.split(separator: "\n").dropFirst() {
        let cells = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        rows[cells[0] + "|" + cells[1]] = (try #require(Int(cells[3])), Int(cells[4]))
    }
    return rows
}

@Test func everyStatsCSVRowIsAFractionWithTraceableContributors() throws {
    let (_, timeline) = try sampleTimeline()
    let lines = try StatsEngine.lines(timeline, sample: true)
    let golden = try goldenStatsRows()
    #expect(lines.count == golden.count, "one line per stats.csv row, singles has no per-server lines")
    for line in lines {
        let row = try #require(golden[line.key.stat + "|" + (line.key.side?.rawValue ?? "")], "\(line.key)")
        switch line.stat.value {
        case .ratio(let r)?:
            #expect(r.n == row.n && r.d == row.d, "\(line.key)")
            // For a rate the contributors are exactly its denominator's points (games-won rates count games).
            if !["serviceGamesWon", "returnGamesWon"].contains(line.key.stat) {
                #expect(line.stat.evidence.contributingPointIDs.count == r.d, "\(line.key)")
            }
        case .count(let n)?: #expect(n == row.n && row.d == nil, "\(line.key)")
        case nil: Issue.record("\(line.key) has contributors in the sample yet no value")
        }
        #expect(line.stat.evidence.sample)
        #expect(Set(line.stat.evidence.contributingPointIDs).count == line.stat.evidence.contributingPointIDs.count)
    }
    // The sample has 8 needs-review points, all manual: the headline rate reports them.
    let won = try #require(lines.first { $0.key == StatKey(stat: "totalPointsWon", side: .a) })
    #expect(won.stat.evidence.unreviewedCount == 8 && won.stat.evidence.provenance == .manual)
    // Service games are standard, complete, non-penalty games; their contributors are those games' points.
    let games = try #require(lines.first { $0.key == StatKey(stat: "serviceGamesWon", side: .a) })
    guard case .ratio(let held)? = games.stat.value else { Issue.record("serviceGamesWon must be a rate"); return }
    let gameIndices = Set(timeline.games.filter { $0.complete && $0.kind == .standard && !$0.byPenalty && $0.serverSide == .a }.map(\.index))
    #expect(held.d == gameIndices.count)
    #expect(games.stat.evidence.contributingPointIDs.count == timeline.points.filter { $0.game.value.map(gameIndices.contains) ?? false }.count)
}

@Test func doublesAddPerServerServeLinesWhoseCountsSumToTheTeam() throws {
    let root = try FixtureManifest.repository()
    let fixture = try JSONDecoder().decode(StatsFixture.self, from: Data(contentsOf: root.appendingPathComponent("spec/fixtures/stats/T03-doubles-per-server.json")))
    let timeline = try ScoringEngine.fold(fixture.input)
    let lines = try StatsEngine.lines(timeline)
    let servers = Set(lines.compactMap(\.key.server))
    #expect(servers == Set(fixture.expected.servers.keys))
    for id in servers {
        let points = try #require(lines.first { $0.key == StatKey(stat: "servicePoints", server: id) })
        #expect(points.stat.value == .count(try #require(fixture.expected.servers[id]).servicePoints))
        #expect(points.stat.evidence.contributingPointIDs.count == fixture.expected.servers[id]?.servicePoints)
    }
    for side in [Side.a, .b] {
        let team = try #require(lines.first { $0.key == StatKey(stat: "servicePoints", side: side) })
        let sum = lines.filter { $0.key.server != nil && $0.key.stat == "servicePoints" }
            .filter { line in timeline.points.contains { $0.server.value == line.key.server && $0.serverSide.value?.rawValue == side.rawValue } }
            .reduce(0) { total, line in if case .count(let n)? = line.stat.value { total + n } else { total } }
        #expect(team.stat.value == .count(sum))
    }
}

/// A stats fixture with one point turned into an unreviewed automatic estimate, folded through the real engine.
@Test func oneEstimatedContributorMakesTheStatEstimatedWithOneUnreviewedPoint() throws {
    let root = try FixtureManifest.repository()
    let data = try Data(contentsOf: root.appendingPathComponent("spec/fixtures/stats/T02-every-end-type.json"))
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var input = try #require(object["input"] as? [String: Any])
    var log = try #require(input["log"] as? [[String: Any]])
    for index in log.indices where log[index]["type"] as? String == "point" { log[index]["reviewState"] = "reviewed" }
    var outcome = try #require(log[0]["reviewed"] as? [String: Any])
    outcome["provenance"] = "estimated"; outcome["source"] = "rule:checkpointSolver@1"
    log[0].removeValue(forKey: "reviewed"); log[0]["detected"] = outcome; log[0]["reviewState"] = "unreviewed"
    input["log"] = log; object["input"] = input
    let fixture = try JSONDecoder().decode(StatsFixture.self, from: JSONSerialization.data(withJSONObject: object))
    let timeline = try ScoringEngine.fold(fixture.input)
    let won = try StatsEngine.stat(.pointsWon(.a), in: timeline)
    #expect(won.value == .ratio(fixture.expected.sides.A.totalPointsWon), "the estimate keeps its observed winner")
    #expect(won.evidence.provenance == .estimated)
    #expect(won.evidence.unreviewedCount == 1)
    #expect(won.evidence.contributingPointIDs.contains("e001"))
    // A stat the estimated point does not feed keeps the stronger provenance.
    let line = try #require(StatsEngine.lines(timeline).first { $0.key == StatKey(stat: "firstServeIn", side: .b) })
    if !line.stat.evidence.contributingPointIDs.contains("e001") {
        #expect(line.stat.evidence.provenance == .manual && line.stat.evidence.unreviewedCount == 0)
    }
}

@Test func flippingSamplePoint42ListsOnlyTheStatsWhoseFractionsChanged() throws {
    var (document, before) = try sampleTimeline()
    var match = try #require(document.match)
    let index = try #require(match.log.firstIndex { $0.seq == 42 })
    guard case .point(var point) = match.log[index] else { Issue.record("Sample seq42 must be a point"); return }
    var observation = try #require(point.reviewed ?? point.detected)
    #expect(observation.winner == .b, "point 42 (Alex serving, 15-30) is Alex's in the sample")
    observation.winner = .a
    point.reviewed = observation
    match.log[index] = .point(point)
    document.match = match
    let after = try ScoringEngine.fold(ScoringInput(session: document))
    let changes = try StatsEngine.diff(before: before, after: after)
    // Reference value (spec/reference jovra_ref: fold + stats.compute of the same edit): Jon wins the game, the
    // match ends earlier, and points won becomes 68/116.
    let won = try #require(changes.first { $0.key == StatKey(stat: "totalPointsWon", side: .a) })
    #expect(won.before == .ratio(.init(n: 72, d: 124, pct: .init(58), display: "58%")))
    #expect(won.after == .ratio(.init(n: 68, d: 116, pct: .init(59), display: "59%")))
    let oldLines = try StatsEngine.lines(before), newLines = try StatsEngine.lines(after)
    let listed = Set(changes.map(\.key))
    for (old, new) in zip(oldLines, newLines) {
        #expect(old.key == new.key)
        #expect(listed.contains(old.key) == (old.stat.value != new.stat.value), "\(old.key)")
    }
    // The reference engine's unchanged stats.csv lines for this edit; everything else must be listed.
    let unchanged: Set<StatKey> = Set(
        ["penaltyPointsAwarded", "servicePoints", "servicePointsWon", "serviceGamesWon", "returnGamesWon",
         "unforcedErrors", "longestPointStreak", "longestGameStreak"].map { StatKey(stat: $0, side: .a) } +
        ["penaltyPointsAwarded", "serviceGamesWon", "returnPointsWon", "returnGamesWon", "unforcedErrors",
         "longestPointStreak", "longestGameStreak"].map { StatKey(stat: $0, side: .b) } +
        ["rallyLength.9+", "rallyLength.unknown", "review.needsReview"].map { StatKey(stat: $0) })
    #expect(Set(oldLines.map(\.key)).subtracting(listed) == unchanged)
    let shots = try #require(changes.first { $0.key == StatKey(stat: "shots.total") })
    #expect(shots.before == .count(386) && shots.after == .count(363))
}

@Test func anEditThatChangesNoNumberListsNoStat() throws {
    let (_, timeline) = try sampleTimeline()
    #expect(try StatsEngine.diff(before: timeline, after: timeline).isEmpty)
    var reviewedOnly = timeline
    reviewedOnly.points[3].provenance = .reviewed
    reviewedOnly.points[3].id = "corrected-id"
    #expect(try StatsEngine.diff(before: timeline, after: reviewedOnly).isEmpty, "evidence alone is not a changed fraction")
}

@Test func compositionRowsRoundIndependentlyAndSayWhenTheyMissOneHundred() throws {
    let placements = try Composition([("Deep", 31), ("Short", 12), ("Out", 7)])
    #expect(placements.rows.map(\.ratio.display) == ["62%", "24%", "14%"])
    #expect(placements.total == 50 && placements.sumsTo100)
    let thirds = try Composition([("Deep", 1), ("Short", 1), ("Out", 1)])
    #expect(thirds.rows.map(\.ratio.pct.value) == [33, 33, 33])
    #expect(thirds.roundedSum == 99 && !thirds.sumsTo100)
    let over = try Composition([("Deep", 1), ("Short", 1), ("Out", 6)])
    #expect(over.rows.map(\.ratio.pct.value) == [13, 13, 75])
    #expect(over.roundedSum == 101 && !over.sumsTo100)
    let none = try Composition([("Deep", 0), ("Short", 0), ("Out", 0)])
    #expect(none.rows.allSatisfy { $0.ratio.display == "—" } && none.roundedSum == nil && !none.sumsTo100)
    #expect(throws: PercentError.invalidFraction) { try Composition([("Deep", -1)]) }
}
