import SwiftUI

/// Placeholder for the Racket Vault (S17), handed to T49. T49 replaces this file and keeps
/// `RacketVaultScreen()`, so the router (App/Destinations.swift) never changes.
struct RacketVaultScreen: View {
    var body: some View {
        RoutePlaceholder(.push(.profile(.racketVault)))
    }
}
