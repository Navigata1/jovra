import JovraCore
import SwiftUI

/// The Profile tab's root, the Profile hub (N11): who the player is, and the way to gear, storage, settings,
/// diagnostics and recording rules. The rows open screens other tickets build; until then those screens say so.
struct ProfileView: View {
    /// The only public contact address (CLAUDE.md rule 7), shown as plain text.
    private static let contactAddress = "hello@islanddevcrew.com"

    @Environment(AppRouter.self) private var router
    @Environment(PlayerProfileModel.self) private var model
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system
    @State private var isEditing = false

    var body: some View {
        JovraScreen(title: title, subtitle: subtitle) {
            AvatarInitial(initial: model.profile?.initial, size: 52)
                .accessibilityHidden(true)
        } content: {
            if model.isDemo {
                DemoBanner {
                    model.beginOnboarding()
                    router.show(.preShell(.onboarding(step: 2)))
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("profile.demoBanner")
            }
            profileState
            VStack(alignment: .leading, spacing: Space.x1) {
                SectionHeader(title: String(localized: "Your game and gear", table: "Profile"))
                VStack(spacing: 0) {
                    hubRow(symbol: "person.crop.circle", title: String(localized: "Player profile", table: "Profile"),
                           subtitle: String(localized: "Name, playing hand, backhand, level and goals", table: "Profile"),
                           identifier: "profile.row.player") { isEditing = true }
                        .disabled(model.profile == nil)
                    divider
                    hubRow(symbol: "tennis.racket", title: String(localized: "Racket Vault", table: "Profile"),
                           subtitle: String(localized: "Your rackets and setups", table: "Profile"),
                           identifier: "profile.row.racketVault") { router.push(.profile(.racketVault)) }
                    divider
                    hubRow(symbol: "book.closed", title: String(localized: "String journal", table: "Profile"),
                           subtitle: String(localized: "String jobs and court time since restring", table: "Profile"),
                           identifier: "profile.row.stringJournal") { router.push(.profile(.stringJournal)) }
                }
                .jovraCard(padding: Space.x1)
            }
            VStack(alignment: .leading, spacing: Space.x1) {
                SectionHeader(title: String(localized: "Your videos and this iPhone", table: "Profile"))
                VStack(spacing: 0) {
                    hubRow(symbol: "externaldrive", title: String(localized: "Storage and backup", table: "Profile"),
                           subtitle: String(localized: "Where your originals live", table: "Profile"),
                           identifier: "profile.row.storage") { router.push(.profile(.storage)) }
                    divider
                    hubRow(symbol: "hand.raised", title: String(localized: "Recording rules", table: "Profile"),
                           subtitle: String(localized: "Consent and who is on camera", table: "Profile"),
                           identifier: "profile.row.recordingRules") { router.push(.profile(.recordingRules)) }
                    divider
                    hubRow(symbol: "gearshape", title: String(localized: "Settings", table: "Profile"),
                           subtitle: String(localized: "Units, recording, backup and privacy", table: "Profile"),
                           identifier: "profile.row.settings") { router.push(.profile(.settings)) }
                    divider
                    hubRow(symbol: "doc.text.magnifyingglass", title: String(localized: "Diagnostics", table: "Profile"),
                           subtitle: String(localized: "A report you choose to share", table: "Profile"),
                           identifier: "profile.row.diagnostics") { router.push(.profile(.diagnostics)) }
                }
                .jovraCard(padding: Space.x1)
            }
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
            // IDC Rule 07: plain text only, never a link or selectable data-detector target. The
            // sentence is translated; the address is not, and verbatim text is never parsed as Markdown.
            Text(verbatim: String(localized: "Questions: \(Self.contactAddress)", table: "Profile", comment: "Footer: the public contact address follows the colon"))
                .font(.footnote)
                .foregroundStyle(.jovra(.textPrimary))
        }
        .navigationDestination(isPresented: $isEditing) {
            ProfileEditScreen()
        }
    }

    private var title: String {
        guard let name = model.profile?.trimmedName, !name.isEmpty else { return String(localized: "Profile", table: "Profile") }
        return name
    }

    private var subtitle: String {
        model.profile?.summary ?? String(localized: "Your privacy. Your game.", table: "Profile")
    }

    @ViewBuilder private var profileState: some View {
        switch model.state {
        case .unreadable:
            StateCard(symbol: "person.crop.circle.badge.exclamationmark",
                      title: String(localized: "Your profile couldn't be read", table: "Profile"),
                      message: String(localized: "It is still on this iPhone and nothing was changed. Your sessions are not affected.", table: "Profile"))
        case .unavailable:
            StateCard(symbol: "externaldrive.badge.exclamationmark",
                      title: String(localized: "Your profile isn't available", table: "Profile"),
                      message: String(localized: "Close JOVRA and open it again. Your sessions are not affected.", table: "Profile"))
        case .loaded:
            // The demo's sample profile is labelled by the DemoBanner above (its Sample badge), not twice.
            EmptyView()
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.jovra(.separator)).frame(height: 0.5).padding(.leading, Space.x5 + Space.x1)
    }

    private func hubRow(symbol: String, title: String, subtitle: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsRow(symbol: symbol, title: title, subtitle: subtitle)
                .padding(.horizontal, Space.x1)
                .frame(minHeight: HitTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}
