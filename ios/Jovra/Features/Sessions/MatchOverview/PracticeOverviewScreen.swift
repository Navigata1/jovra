import SwiftUI

/// Placeholder for the practice overview (S09 variant), handed to T22. T22 replaces this file and keeps
/// `PracticeOverviewScreen(session:)`, so the router (App/Destinations.swift) never changes.
struct PracticeOverviewScreen: View {
    var session: SessionID

    var body: some View {
        RoutePlaceholder(.push(.sessions(.practiceOverview(session))))
    }
}
