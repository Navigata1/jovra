import SwiftUI

/// Placeholder for the restore sheet (S19), handed to T54. T54 replaces this file and keeps
/// `RestoreSheet(session:)`, so the router (App/Destinations.swift) never changes.
struct RestoreSheet: View {
    var session: SessionID?

    var body: some View {
        RoutePlaceholder(.sheet(.restore(session)))
    }
}
