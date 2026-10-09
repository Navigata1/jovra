import SwiftUI

/// Placeholder for the string journal (S18), handed to T49. T49 replaces this file and keeps
/// `StringJournalScreen()`, so the router (App/Destinations.swift) never changes.
struct StringJournalScreen: View {
    var body: some View {
        RoutePlaceholder(.push(.profile(.stringJournal)))
    }
}
