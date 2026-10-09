import SwiftUI

/// Placeholder for the players sheet (S04), handed to T21. T21 replaces this file and keeps
/// `PlayersSheet()`, so the router (App/Destinations.swift) never changes.
struct PlayersSheet: View {
    var body: some View {
        RoutePlaceholder(.sheet(.players))
    }
}
