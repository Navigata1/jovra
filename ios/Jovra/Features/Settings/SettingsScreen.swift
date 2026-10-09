import SwiftUI

/// Placeholder for the settings and privacy screen (S20), handed to T56. T56 replaces this file and keeps
/// `SettingsScreen()`, so the router (App/Destinations.swift) never changes.
struct SettingsScreen: View {
    var body: some View {
        RoutePlaceholder(.push(.profile(.settings)))
    }
}
