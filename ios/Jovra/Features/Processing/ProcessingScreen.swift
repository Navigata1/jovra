import SwiftUI

/// Placeholder for the processing screen (S07), handed to T27. T27 replaces this file and keeps
/// `ProcessingScreen(session:)`, so the router (App/Destinations.swift) never changes.
struct ProcessingScreen: View {
    var session: SessionID

    var body: some View {
        RoutePlaceholder(.fullScreen(.processing(session)))
    }
}
