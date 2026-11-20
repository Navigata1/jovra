import Foundation
import JovraCore
import JovraVision
import Testing

/// V00: observations reach the session only as suggestions: point events whose detected outcome is
/// `estimated` with a `model:` source, in needs review. A reviewed point is never overwritten (T04, spec
/// decision 24, fixture S67), whether the converter or the event log is asked to.
@Suite struct SessionSuggestionsTests {
    let capability = AnalysisCapability(id: "pointOutcome.auto", version: "0.1.0")

    /// S67's match through its third event: e001 and e002 are unreviewed suggestions, e003 is the player's
    /// reviewed decision on e001 (B won, unforced error). Times added: e001/e003 0–5 s, e002 10–15 s.
    func reviewedLog() throws -> ScoringInput {
        var input = try S67.input()
        input.log = input.log.filter { $0.seq <= 3 }.map { event in
            guard case .point(var point) = event else { return event }
            (point.tStartMs, point.tEndMs) = point.id == "e002" ? (10_000, 15_000) : (0, 5_000)
            return .point(point)
        }
        return input
    }

    let candidates = [
        PointCandidate(startMs: 200, endMs: 5_200, winner: .a, confidence: 0.7),       // the reviewed point
        PointCandidate(startMs: 10_100, endMs: 15_000, winner: .b, confidence: 0.8),   // the unreviewed e002
        PointCandidate(startMs: 20_000, endMs: 25_000, winner: .unknown),             // a point not in the log
    ]

    @Test func everySuggestionIsAnEstimatedNeedsReviewPointWithAModelSource() throws {
        let batch = try SessionSuggestions.pointEvents(for: candidates, by: capability, in: reviewedLog())
        #expect(batch.events.count == 2)
        for case .point(let point) in batch.events {
            let detected = try #require(point.detected)
            #expect(detected.provenance == .estimated)
            #expect(detected.source == "model:pointOutcome.auto@0.1.0")
            #expect(detected.capabilityId == "pointOutcome.auto")
            #expect(detected.capabilityVersion == "0.1.0")
            #expect(point.reviewed == nil)
            #expect(point.reviewState == .needsReview)
        }
        #expect(batch.events.map(\.seq) == [4, 5])
        guard case .point(let replacing) = batch.events[0], case .point(let added) = batch.events[1] else {
            Issue.record("point events expected"); return
        }
        #expect(replacing.supersedes == "e002")
        #expect(replacing.detected?.winner == .b)
        #expect(replacing.detected?.confidence == 0.8)
        #expect([replacing.tStartMs, replacing.tEndMs] == [10_100, 15_000])
        #expect(added.supersedes == nil && added.insertBefore == nil)
        #expect(batch.keptReviewed == ["e003"])
    }

    @Test func theScoreKeepsTheReviewedPointAndTakesTheOtherSuggestions() throws {
        var input = try reviewedLog()
        input.log += try SessionSuggestions.pointEvents(for: candidates, by: capability, in: input).events
        let points = try ScoringEngine.fold(input).points
        #expect(points.count == 3)
        #expect(points[0].id == "e003")
        #expect(points[0].winner.value == .b)
        #expect(points[0].endType == .unforcedError)
        #expect(points[0].provenance == .reviewed)
        #expect(points[1].winner.value == .b)
        #expect(points[1].provenance == .estimated)
        #expect(points[1].reviewState == .needsReview)
        #expect(points[2].provenance == .estimated)
    }

    @Test func aSuggestionAimedAtAReviewedPointChangesNothingEvenIfItIsWritten() throws {
        var input = try reviewedLog()
        let before = try ScoringEngine.fold(input).points
        // As if a stage wrote a suggestion straight at the reviewed point (and at its original id).
        for (seq, target) in [(4, "e003"), (5, "e001")] {
            input.log.append(.point(SessionPointEvent(
                id: "forced-\(seq)", seq: seq, supersedes: target, tStartMs: 0, tEndMs: 5_000,
                detected: SessionOutcome(winner: .a, endType: .winner, provenance: .estimated,
                                         source: "model:pointOutcome.auto@0.1.0", capabilityId: "pointOutcome.auto"),
                reviewState: .needsReview)))
        }
        let after = try ScoringEngine.fold(input).points
        #expect(after == before)
        #expect(after[0].winner.value == .b && after[0].provenance == .reviewed)
    }

    @Test func runningTheSameMethodAgainAddsNothing() throws {
        var input = try reviewedLog()
        input.log += try SessionSuggestions.pointEvents(for: candidates, by: capability, in: input).events
        let again = try SessionSuggestions.pointEvents(for: candidates, by: capability, in: input)
        #expect(again.events.isEmpty)
        #expect(again.alreadySuggested == 2)
        #expect(again.keptReviewed == ["e003"])
    }

    @Test func aNewerMethodVersionReplacesItsOwnEarlierSuggestion() throws {
        var input = try reviewedLog()
        input.log += try SessionSuggestions.pointEvents(for: candidates, by: capability, in: input).events
        let newer = AnalysisCapability(id: "pointOutcome.auto", version: "0.2.0")
        let batch = try SessionSuggestions.pointEvents(for: [PointCandidate(startMs: 10_000, endMs: 15_000, winner: .a)],
                                                       by: newer, in: input)
        guard case .point(let point) = try #require(batch.events.first) else { Issue.record("point expected"); return }
        #expect(point.detected?.source == "model:pointOutcome.auto@0.2.0")
        input.log += batch.events
        let points = try ScoringEngine.fold(input).points
        #expect(points[1].winner.value == .a)
        #expect(points[1].id == point.id)
    }

    @Test func aPointFoundBetweenTwoLoggedPointsIsInsertedInTimeOrder() throws {
        let batch = try SessionSuggestions.pointEvents(for: [PointCandidate(startMs: 6_000, endMs: 9_000)],
                                                       by: capability, in: reviewedLog())
        guard case .point(let point) = try #require(batch.events.first) else { Issue.record("point expected"); return }
        #expect(point.insertBefore == "e002")
        var input = try reviewedLog()
        input.log += batch.events
        #expect(try ScoringEngine.fold(input).points.map(\.id) == ["e003", point.id, "e002"])
    }

    @Test func aSourceOutsideTheContractGrammarIsRefused() {
        #expect(throws: SessionSuggestionsError.invalidCapability) {
            try SessionSuggestions.pointEvents(for: candidates, by: AnalysisCapability(id: "point outcome", version: "1"),
                                               in: try reviewedLog())
        }
    }
}

enum S67 {
    static func input(filePath: String = #filePath) throws -> ScoringInput {
        var root = URL(fileURLWithPath: filePath)
        while root.path != "/", !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/scoring").path) {
            root.deleteLastPathComponent()
        }
        let url = root.appendingPathComponent("spec/fixtures/scoring/S67-reanalysis-keeps-reviewed.json")
        let document = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try ScoringInput.decode(JSONSerialization.data(withJSONObject: try #require(document["input"])))
    }
}
