import SwiftUI

/// Placeholder for the progress screen (S16), handed to T48. T48 replaces this file and keeps
/// `ProgressScreen()`, so the router (App/Destinations.swift) never changes.
struct ProgressScreen: View {
    var body: some View {
        RoutePlaceholder(.push(.insights(.progress)))
    }
}
