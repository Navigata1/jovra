import SwiftUI

/// Placeholder for the "String broke" sheet, handed to T50. T50 replaces this file and keeps
/// `StringBrokeSheet(session:time:)`, so the router (App/Destinations.swift) never changes.
struct StringBrokeSheet: View {
    var session: SessionID
    var time: MediaTime

    var body: some View {
        RoutePlaceholder(.sheet(.stringBroke(session, time)))
    }
}
