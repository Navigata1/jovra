import SwiftUI

/// Placeholder for the Trash sheet (S08), handed to T20. T20 replaces this file and keeps
/// `TrashSheet()`, so the router (App/Destinations.swift) never changes.
struct TrashSheet: View {
    var body: some View {
        RoutePlaceholder(.sheet(.trash))
    }
}
