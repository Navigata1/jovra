import SwiftUI

/// The gear row of session setup (S04). T21 owns the slot and its empty state ("Add your racket ·
/// Optional", neutral, never attention); T50 replaces the body with the active racket and string job,
/// keeping the type name, so the setup screen never changes.
struct GearRowSlot: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        SetupRow(symbol: "tennis.racket",
                 label: String(localized: "Gear", table: "Record", comment: "Setup row label"),
                 value: String(localized: "Add your racket", table: "Record", comment: "Gear row when no racket is saved"),
                 detail: String(localized: "Optional", table: "Record", comment: "Gear row: a racket is not required"),
                 identifier: "record.slot.gear",
                 action: { router.show(.push(.profile(.racketVault))) })
    }
}
