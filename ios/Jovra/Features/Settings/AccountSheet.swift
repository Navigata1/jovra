import SwiftUI

/// Placeholder for the account sheet (S20), handed to T56. T56 replaces this file and keeps
/// `AccountSheet()`, so the router (App/Destinations.swift) never changes.
struct AccountSheet: View {
    var body: some View {
        RoutePlaceholder(.sheet(.account))
    }
}
