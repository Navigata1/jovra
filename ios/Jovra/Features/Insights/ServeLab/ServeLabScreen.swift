import SwiftUI

/// Placeholder for the Serve Lab (S12), handed to T43. T43 replaces this file and keeps
/// `ServeLabScreen(session:)`, so the router (App/Destinations.swift) never changes.
struct ServeLabScreen: View {
    var session: SessionID?

    var body: some View {
        RoutePlaceholder(.push(.insights(.serveLab(session))))
    }
}
