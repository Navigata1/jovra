import SwiftUI

/// Placeholder for the welcome screen (S01), handed to T18. T18 replaces this file and keeps
/// `WelcomeScreen()`, so the router (App/Destinations.swift) never changes.
struct WelcomeScreen: View {
    var body: some View {
        RoutePlaceholder(.preShell(.welcome))
    }
}
