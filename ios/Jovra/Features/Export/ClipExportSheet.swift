import SwiftUI

/// Placeholder for the clip export sheet, handed to T36. T36 replaces this file and keeps
/// `ClipExportSheet(session:point:)`, so the router (App/Destinations.swift) never changes.
struct ClipExportSheet: View {
    var session: SessionID
    var point: PointID?

    var body: some View {
        RoutePlaceholder(.sheet(.clipExport(session, point)))
    }
}
