import SwiftUI

/// The recording-consent row of session setup (S04, N4). T21 owns the slot and its empty state;
/// T58 (recording rules and consent) replaces the body with the consent choice and its sheet, keeping
/// the type name, so the setup screen never changes.
struct ConsentRowSlot: View {
    var body: some View {
        SetupRow(symbol: "person.badge.shield.checkmark",
                 label: String(localized: "Recording consent", table: "Record", comment: "Setup row label"),
                 value: String(localized: "Not set", table: "Record", comment: "Consent row: no consent choice yet"),
                 detail: String(localized: "Choosing who agreed to be filmed arrives with recording rules.", table: "Record", comment: "Consent row empty state"),
                 identifier: "record.slot.consent")
    }
}
