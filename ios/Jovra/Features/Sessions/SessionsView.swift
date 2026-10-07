import SwiftUI

struct SessionsView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", matches = "Matches", practice = "Practice"
        var id: String { rawValue }
    }

    @State private var filter = Filter.all

    var body: some View {
        JovraScreen(title: "Your sessions", subtitle: "Review. Improve. Keep going.") {
            FilterPills(options: Filter.allCases, selection: $filter) { $0.rawValue }
            ComingLaterCard(
                symbol: "calendar",
                message: "Recorded and imported sessions will be listed here. Originals are saved on this device before anything else happens."
            )
        }
    }
}
