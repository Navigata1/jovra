import SwiftUI

/// The named place on every SessionCard for the session's archive action (back up now, retry, reconnect,
/// download from Google Drive). The restore ticket (T54) fills it; until then it draws nothing, so no card
/// offers an archive action the app cannot perform yet.
struct ArchiveActionSlot: View {
    var entry: LibraryEntry

    var body: some View {
        EmptyView()
    }
}
