import SwiftUI

/// Placeholder for the capture route: framing (S05), then recording (S06), handed to T17. T17 replaces this file and keeps
/// `CaptureScreen(setup:)`, so the router (App/Destinations.swift) never changes.
struct CaptureScreen: View {
    var setup: SessionSetupDraft?

    var body: some View {
        RoutePlaceholder(.fullScreen(.capture(setup)))
    }
}
