import Foundation

/// The little the router needs to know about a stored session to resolve a deep link.
struct SessionSummary: Equatable, Sendable {
    var id: SessionID
    var kind: SessionKind
    var startedAt: Date
    /// Sample data (GLOSSARY: Sample data) is never "your last match".
    var isSample: Bool
}

/// Read access to the library's index, for deep links. The session library ticket (T20) provides the
/// live value from the session store's index in `SessionLookupKey` (Features/Sessions/Library).
protocol SessionLookup: Sendable {
    func summaries() async -> [SessionSummary]
}

extension SessionLookup {
    /// The newest match that is the player's own: sample sessions and practice sessions never count.
    func newestRealMatch() async -> SessionSummary? {
        await summaries()
            .filter { !$0.isSample && $0.kind.isMatch }
            .max { ($0.startedAt, $0.id.rawValue) < ($1.startedAt, $1.id.rawValue) }
    }
}

/// A fixed list of sessions: the stand-in before the store exists, and the fake in tests.
struct FixedSessionLookup: SessionLookup {
    var sessions: [SessionSummary] = []

    func summaries() async -> [SessionSummary] { sessions }
}
