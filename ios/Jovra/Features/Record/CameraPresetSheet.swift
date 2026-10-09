import SwiftUI

/// Placeholder for the camera preset sheet (S04), handed to T21. T21 replaces this file and keeps
/// `CameraPresetSheet()`, so the router (App/Destinations.swift) never changes.
struct CameraPresetSheet: View {
    var body: some View {
        RoutePlaceholder(.sheet(.cameraPreset))
    }
}
