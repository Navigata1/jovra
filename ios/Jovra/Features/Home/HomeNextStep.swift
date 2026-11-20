import Foundation
import JovraCore

/// The next useful action Home surfaces (story 37), driven only by the session's independent status facets
/// (GLOSSARY: Session status). Each opens a typed route (or the placeholder its ticket replaces).
enum HomeNextStep: Equatable, Sendable, Identifiable {
    /// The newest session stopped early (saved with gaps, or partially saved after an interruption): open it to carry
    /// on from what was kept.
    case resume(sessionID: String, title: String, savedSeconds: Int)
    /// A match whose review is not complete still has points awaiting the player's decision.
    case finishReviewing(sessionID: String, title: String, points: Int)
    /// The player's own recordings that exist only on this iPhone (archive facet `localOnly`); `sessionID` and
    /// `title` are the newest of them.
    case backUp(sessionID: String, title: String, count: Int)

    var id: String {
        switch self {
        case .resume(let session, _, _): "resume.\(session)"
        case .finishReviewing(let session, _, _): "review.\(session)"
        case .backUp(let session, _, _): "backUp.\(session)"
        }
    }

    var destination: AppDestination {
        switch self {
        case .resume(let session, _, _):
            .fullScreen(.replay(ReplayRequest(session: SessionID(rawValue: session), point: nil, filter: nil)))
        case .finishReviewing(let session, _, _):
            .fullScreen(.pointReview(SessionID(rawValue: session), .needsReview))
        case .backUp:
            .push(.profile(.storage))
        }
    }

    /// The steps for the sessions in scope, newest first within each kind; at most one of each kind.
    static func steps(for sessions: [SessionDocument]) -> [HomeNextStep] {
        let newestFirst = Array(sessions.reversed())
        var steps: [HomeNextStep] = []
        if let newest = newestFirst.first, let state = newest.original?.state, interrupted.contains(state),
           newest.review?.state != .complete {
            steps.append(.resume(sessionID: newest.id, title: newest.title,
                                 savedSeconds: HomeDashboard.duration(of: newest) / 1000))
        }
        for document in newestFirst where document.review?.state != .complete && document.match != nil {
            guard let timeline = try? ScoringEngine.fold(ScoringInput(session: document)),
                  let flagged = try? StatsEngine.compute(timeline).review.needsReview, flagged > 0 else { continue }
            steps.append(.finishReviewing(sessionID: document.id, title: document.title, points: flagged))
            break
        }
        let local = newestFirst.filter { document in
            document.sample == nil && document.archive.state == .localOnly
                && document.original.map { backupable.contains($0.state) } ?? true
        }
        if let newest = local.first {
            steps.append(.backUp(sessionID: newest.id, title: newest.title, count: local.count))
        }
        return steps
    }

    /// Original states of a recording that stopped before the player chose to stop it.
    private static let interrupted: Set<SessionOriginalStateState> = [.savedWithGaps, .partial]
    /// Original states with a whole or partial original on this iPhone to copy.
    private static let backupable: Set<SessionOriginalStateState> = [.saved, .savedWithGaps, .partial]
}
