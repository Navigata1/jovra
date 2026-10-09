import SwiftUI

/// Placeholder for the consent attach sheet (N4), handed to T58. T58 replaces this file and keeps
/// `ConsentAttachSheet(session:)`, so the router (App/Destinations.swift) never changes.
struct ConsentAttachSheet: View {
    var session: SessionID

    var body: some View {
        RoutePlaceholder(.sheet(.consentAttach(session)))
    }
}
