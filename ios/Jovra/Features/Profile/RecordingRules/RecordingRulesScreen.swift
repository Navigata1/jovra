import SwiftUI

/// Placeholder for the recording rules (N4), handed to T58. T58 replaces this file and keeps
/// `RecordingRulesScreen()`, so the router (App/Destinations.swift) never changes.
struct RecordingRulesScreen: View {
    var body: some View {
        RoutePlaceholder(.push(.profile(.recordingRules)))
    }
}
