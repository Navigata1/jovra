import SwiftUI

/// Placeholder for the point editor sheet, handed to T29. T29 replaces this file and keeps
/// `PointEditorSheet(session:point:)`, so the router (App/Destinations.swift) never changes.
struct PointEditorSheet: View {
    var session: SessionID
    var point: PointID?

    var body: some View {
        RoutePlaceholder(.sheet(.pointEditor(session, point)))
    }
}
