import SwiftUI

/// Placeholder for the "Delete all JOVRA data" sheet (S20), handed to T57. T57 replaces this file and keeps
/// `DeleteAllDataSheet()`, so the router (App/Destinations.swift) never changes.
struct DeleteAllDataSheet: View {
    var body: some View {
        RoutePlaceholder(.sheet(.deleteAllData))
    }
}
