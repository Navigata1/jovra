import JovraCore
import OSLog
import SwiftUI

/// "Your player profile" (S02 edit mode, pushed from the Profile hub, story 16): the onboarding fields without the
/// StepRail, saved with "Save". Changing handedness says the forehand and backhand filters will update. The demo's
/// sample profile shows a Sample badge; saving it makes it the player's own.
struct ProfileEditScreen: View {
    @Environment(PlayerProfileModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = PlayerProfile()
    @State private var saved: PlayerProfile?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                ZStack {
                    JovraLockup(height: 40)
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.backward")
                                .font(.body.weight(.semibold))
                                .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.jovra(.textPrimary))
                        .accessibilityLabel(Text("Back to Profile", tableName: "Profile"))
                        .accessibilityIdentifier("profile.edit.back")
                        Spacer()
                    }
                }
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text("Your player profile", tableName: "Profile")
                        .jovraDisplayTitle()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("screen.title")
                    if saved?.isSample == true {
                        HStack(spacing: Space.x1) {
                            SampleBadge()
                            Text("Saving makes this profile yours.", tableName: "Profile")
                                .font(.jovraLabel)
                                .foregroundStyle(.jovra(.textSecondary))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("profile.edit.sample")
                    }
                }
                ProfileFormFields(profile: $draft, savedHandedness: saved?.handedness)
                Text("Change these anytime.", tableName: "Profile")
                    .font(.jovraCaption)
                    .foregroundStyle(.jovra(.textSecondary))
                if let problem {
                    BannerView(tone: .attention, title: problem, message: nil, primaryAction: nil, secondaryAction: nil)
                }
                // Save ends the form: nothing is ever hidden under a pinned bar.
                saveButton
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.top, Space.x1)
            .padding(.bottom, Space.x4)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0).background(Color.jovra(.background))
        }
        .clipped()
        .background(Color.jovra(.background).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard saved == nil, let profile = model.profile else { return }
            saved = profile
            draft = profile
        }
    }

    private var saveButton: some View {
        Button(String(localized: "Save", table: "Profile"), action: save)
            .buttonStyle(.jovraPrimary)
            .accessibilityIdentifier("profile.edit.save")
    }

    private func save() {
        var profile = draft
        profile.isSample = false
        do {
            try model.save(profile)
            dismiss()
        } catch {
            Logger(subsystem: "com.islanddevcrew.jovra", category: "Profile")
                .error("The profile could not be saved: \(String(describing: error), privacy: .public)")
            problem = String(localized: "Your changes couldn't be saved. They are still here; try again.", table: "Profile")
        }
    }
}
