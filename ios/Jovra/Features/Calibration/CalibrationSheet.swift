import SwiftUI

/// Placeholder for the calibration sheet (S05), handed to T23. T23 replaces this file and keeps
/// `CalibrationSheet(session:time:)`, so the router (App/Destinations.swift) never changes.
struct CalibrationSheet: View {
    var session: SessionID
    var time: MediaTime

    var body: some View {
        RoutePlaceholder(.sheet(.calibration(session, time)))
    }
}
