import SwiftUI

/// Placeholder for the shot placement map (S11), handed to T41. T41 replaces this file and keeps
/// `ShotMapScreen(session:)`, so the router (App/Destinations.swift) never changes.
struct ShotMapScreen: View {
    var session: SessionID?

    var body: some View {
        RoutePlaceholder(.push(.insights(.shotMap(session))))
    }
}
