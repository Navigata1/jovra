import SwiftUI

/// Placeholder for the import from Photos and Files (S07), handed to T26. T26 replaces this file and keeps
/// `ImportScreen()`, so the router (App/Destinations.swift) never changes.
struct ImportScreen: View {
    var body: some View {
        RoutePlaceholder(.push(.sessions(.importVideos)))
    }
}
