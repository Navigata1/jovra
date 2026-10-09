import Foundation

/// The `jovra://` links App Intents, Shortcuts and Share Pack opens use (screen spec §0.1, P1-26).
/// A link names an intent; it resolves to typed routes only when opened, against the library as it is
/// then (the newest match changes as sessions are recorded).
///
/// | Link | Meaning | Routes |
/// |---|---|---|
/// | `jovra://record/singles` | "Start singles recording" | Record tab, then `capture(singles)` (framing; the camera never starts in the background) |
/// | `jovra://record/doubles`, `/serve`, `/stroke` | start that session kind | Record tab, then `capture(kind)` |
/// | `jovra://sessions/last-match` | "Show last match" | the newest real (not sample) match's overview; the library when there is none |
/// | `jovra://share-pack/<session>` | open a session's Share Pack | that session's overview, then the Share Pack sheet |
enum DeepLink: Equatable, Sendable {
    case startRecording(SessionKind)
    case showLastMatch
    case sharePack(SessionID)

    static let scheme = "jovra"
    /// Session ids in links: letters, digits, `-`, `_` and `.`, at most this long.
    static let maximumIDLength = 128

    private static let recordPaths: [String: SessionKind] = [
        "singles": .singlesMatch, "doubles": .doublesMatch, "serve": .servePractice, "stroke": .strokePractice,
    ]

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        switch (host, path.count) {
        case ("record", 1):
            guard let kind = Self.recordPaths[path[0].lowercased()] else { return nil }
            self = .startRecording(kind)
        case ("sessions", 1) where path[0].lowercased() == "last-match":
            self = .showLastMatch
        case ("share-pack", 1):
            guard let id = Self.sessionID(path[0]) else { return nil }
            self = .sharePack(id)
        default:
            return nil
        }
    }

    var url: URL {
        switch self {
        case .startRecording(let kind):
            let path = Self.recordPaths.first { $0.value == kind }?.key ?? "singles"
            return URL(string: "\(Self.scheme)://record/\(path)")!
        case .showLastMatch:
            return URL(string: "\(Self.scheme)://sessions/last-match")!
        case .sharePack(let session):
            return URL(string: "\(Self.scheme)://share-pack/\(session.rawValue)")!
        }
    }

    /// The routes this link opens, given the library now.
    func destinations(sessions: any SessionLookup) async -> [AppDestination] {
        switch self {
        case .startRecording(let kind):
            return [.tab(.record), .fullScreen(.capture(SessionSetupDraft(kind: kind)))]
        case .showLastMatch:
            guard let match = await sessions.newestRealMatch() else { return [.tab(.sessions)] }
            return [.push(.sessions(.matchOverview(match.id)))]
        case .sharePack(let id):
            guard let session = await sessions.summaries().first(where: { $0.id == id }) else { return [.tab(.sessions)] }
            let overview: SessionsRoute = session.kind.isMatch ? .matchOverview(id) : .practiceOverview(id)
            return [.push(.sessions(overview)), .sheet(.sharePack(id))]
        }
    }

    private static func sessionID(_ text: String) -> SessionID? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard !text.isEmpty, text.count <= maximumIDLength,
              text.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII }) else { return nil }
        return SessionID(rawValue: text)
    }
}
