import Foundation
import JovraCore

/// The score of a project's match, computed by the core fold (ScoringEngine) from the primary session's event log;
/// Studio never keeps a score of its own.
public struct StudioMatchScore: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        /// The side's players' display names, joined with " / " for doubles.
        public let name: String
        /// Games per set, in set order.
        public let games: [Int]

        public init(name: String, games: [Int]) {
            self.name = name
            self.games = games
        }
    }

    public let rows: [Row]
    public let status: TimelineMatchSummaryStatus

    /// "Final" once the match is over by play, "Live" otherwise (core scoreboard wording).
    public var statusLabel: String { status == .completed ? "Final" : "Live" }

    /// The score of `project`'s match from `session`, which must be the project's primary source's session.
    public static func compute(project: StudioProject, session: SessionDocument) throws -> StudioMatchScore {
        guard project.kind == .match, let primary = project.primarySource?.sessionId, primary == session.id,
              let sides = session.sides else {
            throw StudioProjectStoreError.invalidRecord("primary session")
        }
        let timeline = try ScoringEngine.fold(ScoringInput(session: session))
        func name(_ ids: [String]) -> String {
            ids.map { id in session.players.first { $0.id == id }?.displayName ?? id }.joined(separator: " / ")
        }
        return StudioMatchScore(
            rows: [Row(name: name(sides.A), games: timeline.sets.map { $0.games.A }),
                   Row(name: name(sides.B), games: timeline.sets.map { $0.games.B })],
            status: timeline.match.status)
    }
}
