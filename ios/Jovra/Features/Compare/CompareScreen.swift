import SwiftUI

/// Placeholder for the comparison of two recordings (S14), handed to T45. T45 replaces this file and keeps
/// `CompareScreen(comparison:)`, so the router (App/Destinations.swift) never changes.
struct CompareScreen: View {
    var comparison: ComparisonID?

    var body: some View {
        RoutePlaceholder(.fullScreen(.compare(comparison)))
    }
}
