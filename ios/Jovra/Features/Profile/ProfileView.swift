import SwiftUI

struct ProfileView: View {
    /// The only public contact address (CLAUDE.md rule 7), shown as plain text.
    private static let contactAddress = "hello@islanddevcrew.com"

    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    var body: some View {
        JovraScreen(title: String(localized: "Profile", table: "Profile"), subtitle: String(localized: "Your privacy. Your game.", table: "Profile")) {
            VStack(alignment: .leading, spacing: Space.x1) {
                SectionHeader(title: String(localized: "Preferences", table: "Profile"))
                VStack(alignment: .leading, spacing: Space.x1) {
                    SettingsRow(
                        symbol: "circle.lefthalf.filled",
                        title: String(localized: "Appearance", table: "Profile"),
                        subtitle: String(localized: "Follow the system, or always light or dark.", table: "Profile")
                    ) {
                        EmptyView()
                    }
                    .accessibilityElement(children: .combine)
                    FilterPills(options: AppearancePreference.allCases, selection: $appearance) { $0.title }
                        .accessibilityIdentifier("profile.appearance")
                }
                .jovraCard(padding: Space.x2)
            }
            ComingLaterCard(
                symbol: "person",
                message: String(localized: "Your player profile, Racket Vault, string journal, storage and backup, and camera, microphone and photo permissions.", table: "Profile")
            )
            // IDC Rule 07: plain text only, never a link or selectable data-detector target. The
            // sentence is translated; the address is not, and verbatim text is never parsed as Markdown.
            Text(verbatim: String(localized: "Questions: \(Self.contactAddress)", table: "Profile", comment: "Footer: the public contact address follows the colon"))
                .font(.footnote)
                .foregroundStyle(.jovra(.textPrimary))
        }
    }
}
