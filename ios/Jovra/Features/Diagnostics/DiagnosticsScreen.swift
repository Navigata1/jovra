import SwiftUI

/// Placeholder for the diagnostics screen (N5), handed to T57. T57 replaces this file and keeps
/// `DiagnosticsScreen()`, so the router (App/Destinations.swift) never changes.
struct DiagnosticsScreen: View {
    var body: some View {
        RoutePlaceholder(.push(.profile(.diagnostics)))
    }
}
