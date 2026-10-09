import SwiftUI

/// Placeholder for the Share Pack sheet (N3), handed to T38. T38 replaces this file and keeps
/// `SharePackSheet(session:)`, so the router (App/Destinations.swift) never changes.
struct SharePackSheet: View {
    var session: SessionID

    var body: some View {
        RoutePlaceholder(.sheet(.sharePack(session)))
    }
}
