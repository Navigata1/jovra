import SwiftUI

struct SessionsView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, matches, practice
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: String(localized: "All", table: "Sessions", comment: "Session filter")
            case .matches: String(localized: "Matches", table: "Sessions", comment: "Session filter")
            case .practice: String(localized: "Practice", table: "Sessions", comment: "Session filter")
            }
        }
    }

    @State private var filter = Filter.all

    var body: some View {
        JovraScreen(title: String(localized: "Your sessions", table: "Sessions"), subtitle: String(localized: "Review. Improve. Keep going.", table: "Sessions")) {
            FilterPills(options: Filter.allCases, selection: $filter) { $0.title }
            ComingLaterCard(
                symbol: "calendar",
                message: String(localized: "Recorded and imported sessions will be listed here. Originals are saved on this device before anything else happens.", table: "Sessions")
            )
        }
    }
}
