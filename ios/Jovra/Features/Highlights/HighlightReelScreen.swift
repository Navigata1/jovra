import SwiftUI

/// Placeholder for the highlight reel (N10), handed to T37. T37 replaces this file and keeps
/// `HighlightReelScreen(session:)`, so the router (App/Destinations.swift) never changes.
struct HighlightReelScreen: View {
    var session: SessionID

    var body: some View {
        RoutePlaceholder(.fullScreen(.highlightReel(session)))
    }
}
