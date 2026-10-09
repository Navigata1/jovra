import SwiftUI

/// Placeholder for the smart replay (S10), handed to T28. T28 replaces this file and keeps
/// `ReplayScreen(request:)`, so the router (App/Destinations.swift) never changes.
struct ReplayScreen: View {
    var request: ReplayRequest

    var body: some View {
        RoutePlaceholder(.fullScreen(.replay(request)))
    }
}
