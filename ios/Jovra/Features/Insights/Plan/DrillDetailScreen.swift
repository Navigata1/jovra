import SwiftUI

/// Placeholder for the drill detail (S15 auxiliary), handed to T47. T47 replaces this file and keeps
/// `DrillDetailScreen(drill:)`, so the router (App/Destinations.swift) never changes.
struct DrillDetailScreen: View {
    var drill: DrillID

    var body: some View {
        RoutePlaceholder(.push(.insights(.drillDetail(drill))))
    }
}
