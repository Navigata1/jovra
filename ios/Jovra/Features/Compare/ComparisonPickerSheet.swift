import SwiftUI

/// Placeholder for the pair picker sheet (S14), handed to T45. T45 replaces this file and keeps
/// `ComparisonPickerSheet()`, so the router (App/Destinations.swift) never changes.
struct ComparisonPickerSheet: View {
    var body: some View {
        RoutePlaceholder(.sheet(.comparisonPicker))
    }
}
