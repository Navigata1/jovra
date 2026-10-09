import SwiftUI

/// Placeholder for the match overview (S09), handed to T22. T22 replaces this file and keeps
/// `MatchOverviewScreen(session:)`, so the router (App/Destinations.swift) never changes.
struct MatchOverviewScreen: View {
    var session: SessionID

    var body: some View {
        RoutePlaceholder(.push(.sessions(.matchOverview(session))))
    }
}
