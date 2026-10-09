import SwiftUI

/// Placeholder for the Fast Point Review deck (N1), handed to T30. T30 replaces this file and keeps
/// `PointReviewScreen(session:filter:)`, so the router (App/Destinations.swift) never changes.
struct PointReviewScreen: View {
    var session: SessionID
    var filter: PointFilter

    var body: some View {
        RoutePlaceholder(.fullScreen(.pointReview(session, filter)))
    }
}
