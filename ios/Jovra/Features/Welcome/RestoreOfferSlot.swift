import SwiftUI

/// The named place on Welcome where the restore ticket (T54) offers to restore archived sessions from Google Drive
/// after a reinstall. T54 replaces this file and keeps `RestoreOfferSlot()`; until then it draws nothing, so Welcome
/// makes no claim about a restore it cannot do yet.
struct RestoreOfferSlot: View {
    var body: some View {
        EmptyView()
    }
}
