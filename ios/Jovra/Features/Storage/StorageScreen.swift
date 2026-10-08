import SwiftUI

/// Placeholder for the storage and backup screen (S19), handed to T51. T51 replaces this file and keeps
/// `StorageScreen()`, so the router (App/Destinations.swift) never changes.
struct StorageScreen: View {
    var body: some View {
        RoutePlaceholder(.push(.profile(.storage)))
    }
}
