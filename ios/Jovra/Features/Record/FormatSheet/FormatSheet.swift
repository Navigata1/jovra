import SwiftUI

/// Placeholder for the match format sheet (reused by the match overview), handed to T21. T21 replaces this file and keeps
/// `FormatSheet(context:)`, so the router (App/Destinations.swift) never changes.
struct FormatSheet: View {
    var context: FormatSheetContext

    var body: some View {
        RoutePlaceholder(.sheet(.matchFormat(context)))
    }
}
