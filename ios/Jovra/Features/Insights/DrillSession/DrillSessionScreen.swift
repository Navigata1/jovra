import SwiftUI

/// Placeholder for the drill session (S15 auxiliary), handed to T47. T47 replaces this file and keeps
/// `DrillSessionScreen(drill:)`, so the router (App/Destinations.swift) never changes.
struct DrillSessionScreen: View {
    var drill: DrillID

    var body: some View {
        RoutePlaceholder(.fullScreen(.drillSession(drill)))
    }
}
