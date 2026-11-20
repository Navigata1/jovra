import Foundation
import JovraCore

/// The library's All / Matches / Practice filter (story 121).
enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, matches, practice
    var id: String { rawValue }

    /// Matches groups the three kinds with a scoring format; Practice contains the remaining practice and
    /// lesson kinds. A bounded UI grouping, not a schema change.
    func includes(_ kind: SessionDocumentSessionKind) -> Bool {
        let isScored = kind == .match || kind == .tiebreakOnly || kind == .practiceSet
        switch self {
        case .all: return true
        case .matches: return isScored
        case .practice: return !isScored
        }
    }

    var title: String {
        switch self {
        case .all: String(localized: "All", table: "Sessions.Library", comment: "Session filter")
        case .matches: String(localized: "Matches", table: "Sessions.Library", comment: "Session filter")
        case .practice: String(localized: "Practice", table: "Sessions.Library", comment: "Session filter")
        }
    }
}

/// Which sessions the list shows: search over titles, player names and notes, then the filter, newest first
/// (stories 120, 121 and 135).
enum LibraryListing {
    static func visible(_ entries: [LibraryEntry], search: String, filter: LibraryFilter) -> [LibraryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries
            .filter { filter.includes($0.kind) && (query.isEmpty || matches($0, query)) }
            .sorted { lhs, rhs in
                let (left, right) = (lhs.createdAt ?? .distantPast, rhs.createdAt ?? .distantPast)
                return left == right ? lhs.id < rhs.id : left > right
            }
    }

    private static func matches(_ entry: LibraryEntry, _ query: String) -> Bool {
        ([entry.title, entry.notes ?? ""] + entry.playerNames).contains {
            $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
