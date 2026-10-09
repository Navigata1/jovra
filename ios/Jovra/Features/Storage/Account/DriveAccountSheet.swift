import SwiftUI

/// Placeholder for the Google Drive manage sheet (S19), handed to T53. T53 replaces this file and keeps
/// `DriveAccountSheet()`, so the router (App/Destinations.swift) never changes.
struct DriveAccountSheet: View {
    var body: some View {
        RoutePlaceholder(.sheet(.driveAccount))
    }
}
