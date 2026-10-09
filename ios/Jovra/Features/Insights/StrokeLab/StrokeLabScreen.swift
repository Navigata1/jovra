import SwiftUI

/// Placeholder for the Stroke Lab (S13), handed to T42. T42 replaces this file and keeps
/// `StrokeLabScreen(session:)`, so the router (App/Destinations.swift) never changes.
struct StrokeLabScreen: View {
    var session: SessionID?

    var body: some View {
        RoutePlaceholder(.push(.insights(.strokeLab(session))))
    }
}
