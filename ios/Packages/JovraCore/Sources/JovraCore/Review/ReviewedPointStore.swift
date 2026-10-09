import Foundation

public enum PointReviewError: Error, Equatable, Sendable {
    case invalidRange, pointUnavailable, reviewedOutcomeRequired, matchEnded, sequenceExhausted
}

/// Each edit folds and appends inside the SAME SessionStore actor, without suspension.
/// Original events survive; stale or superseded point selections fail rather than losing an edit.
public extension SessionStore {
    @discardableResult
    func appendReviewedPoint(winner: Side, startMs: Int, endMs: Int, for id: String) throws -> SessionPointEvent {
        let document = try load(id)
        guard startMs >= 0, endMs > startMs, let duration = document.recording.durationMs,
              endMs <= duration else { throw PointReviewError.invalidRange }
        let input = try ScoringInput(session: document)
        let timeline = try ScoringEngine.fold(input)
        guard timeline.match.status == .notStarted || timeline.match.status == .inProgress else {
            throw PointReviewError.matchEnded
        }
        let point = SessionPointEvent(id: UUID().uuidString, seq: try nextReviewSequence(input.log),
            tStartMs: startMs, tEndMs: endMs,
            reviewed: .init(winner: winner == .a ? .a : .b, endType: .unknown,
                            provenance: .reviewed, source: "user"), reviewState: .reviewed)
        try commitReview(point, input: input, sessionID: id)
        return point
    }

    @discardableResult
    func correctReviewedWinner(pointID: String, winner: Side, for id: String) throws -> SessionPointEvent {
        let document = try load(id)
        let input = try ScoringInput(session: document)
        let timeline = try ScoringEngine.fold(input)
        guard timeline.points.contains(where: { $0.id == pointID && $0.kind == .point }),
              let event = input.log.first(where: { $0.id == pointID }), case .point(var point) = event else {
            throw PointReviewError.pointUnavailable
        }
        // Winner-only edits preserve facts already reviewed. Confirming a detected block is a
        // separate, fuller review operation; this path never upgrades unexamined estimates.
        guard var outcome = point.reviewed, point.reviewState == .reviewed else {
            throw PointReviewError.reviewedOutcomeRequired
        }
        outcome.winner = winner == .a ? .a : .b
        point.id = UUID().uuidString; point.seq = try nextReviewSequence(input.log)
        point.supersedes = pointID; point.insertBefore = nil
        point.at = Date.now.ISO8601Format(); point.reviewed = outcome
        try commitReview(point, input: input, sessionID: id)
        return point
    }

    private func nextReviewSequence(_ log: [SessionLogEvent]) throws -> Int {
        let previous = log.map(\.seq).max() ?? 0
        guard previous < Int.max else { throw PointReviewError.sequenceExhausted }
        return previous + 1
    }

    private func commitReview(_ point: SessionPointEvent, input: ScoringInput, sessionID: String) throws {
        var proposed = input
        proposed.log.append(.point(point))
        _ = try ScoringEngine.fold(proposed)
        try append([.point(point)], to: sessionID)
    }
}
