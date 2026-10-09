import SwiftUI

/// Placeholder for the Space Saver (N6), handed to T55. T55 replaces this file and keeps
/// `SpaceSaverScreen()`, so the router (App/Destinations.swift) never changes.
struct SpaceSaverScreen: View {
    var body: some View {
        RoutePlaceholder(.push(.profile(.spaceSaver)))
    }
}
