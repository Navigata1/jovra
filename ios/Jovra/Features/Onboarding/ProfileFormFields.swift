import JovraCore
import SwiftUI

/// The player fields of onboarding step 2, reused by the Profile hub's "Your player profile" edit screen (screens.md
/// S02): avatar and name, playing hand, backhand style, skill level and up to three goals. Nothing is preselected.
struct ProfileFormFields: View {
    @Binding var profile: PlayerProfile
    /// The handedness the player had before this edit; changing it shows that filters will update (edit mode only).
    var savedHandedness: SessionPlayerHandedness?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            nameRow
            ProfileFieldGroup(title: String(localized: "Playing hand", table: "Onboarding")) {
                ChoiceSegment(options: SessionPlayerHandedness.choices, selection: optional(\.handedness),
                              title: \.title, symbol: { _ in "hand.raised" }, identifier: "onboarding.hand")
                if let savedHandedness, savedHandedness != .unknown, profile.handedness != savedHandedness {
                    Label {
                        Text("Forehand and backhand filters will update for all sessions.", tableName: "Onboarding")
                    } icon: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .font(.jovraLabel)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile.edit.handednessNote")
                }
            }
            ProfileFieldGroup(title: String(localized: "Backhand style", table: "Onboarding")) {
                // Stroke silhouettes mirror for a left-hander.
                ChoiceSegment(options: SessionPlayerBackhand.choices, selection: optional(\.backhand),
                              title: \.title, symbol: { _ in "figure.tennis" },
                              mirrorsSymbols: profile.handedness == .left, identifier: "onboarding.backhand")
            }
            ProfileFieldGroup(title: String(localized: "Skill level", table: "Onboarding")) {
                ChoiceSegment(options: SkillLevel.allCases, selection: $profile.level, title: \.title, identifier: "onboarding.level")
            }
            ProfileFieldGroup(title: String(localized: "Your goals (select up to 3)", table: "Onboarding")) {
                GoalChips(profile: $profile)
            }
        }
    }

    private var nameRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Space.x3))
        return layout {
            AvatarInitial(initial: profile.initial, size: dynamicTypeSize.isAccessibilitySize ? 64 : 96)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("Name", tableName: "Onboarding")
                    .font(.jovraLabel)
                    .foregroundStyle(.jovra(.textSecondary))
                    .accessibilityHidden(true)
                TextField(String(localized: "First name", table: "Onboarding"), text: $profile.name)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .font(.jovraHeadline.weight(.regular))
                    .foregroundStyle(.jovra(.textPrimary))
                    .padding(.horizontal, Space.x2)
                    .frame(minHeight: 56)
                    .background(Color.jovra(.surfaceSunken), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Color.jovra(nameFocused ? .textPrimary : .separator), lineWidth: nameFocused ? 1.5 : 1)
                    }
                    .accessibilityLabel(Text("Name", tableName: "Onboarding"))
                    .accessibilityIdentifier("onboarding.name")
            }
        }
    }

    /// A handedness or backhand binding where `.unknown` reads as "nothing selected".
    private func optional<Value: Equatable>(_ keyPath: WritableKeyPath<PlayerProfile, Value>) -> Binding<Value?>
        where Value: RawRepresentable, Value.RawValue == String {
        Binding(
            get: { profile[keyPath: keyPath].rawValue == "unknown" ? nil : profile[keyPath: keyPath] },
            set: { if let value = $0 { profile[keyPath: keyPath] = value } }
        )
    }
}
