import JovraCore
import OSLog
import SwiftUI

/// Player onboarding (S02, reference 02): three steps on a StepRail. Step 1 "Account" is always done (no account is
/// needed, or Apple filled it in), so onboarding opens on step 2 "Profile" and ends with step 3 "Play". It never asks
/// for the camera, the microphone or Photos (story 17): each is asked for only when it is first needed.
///
/// The router owns the step (`onboarding(step:)`); the answers live in `PlayerProfileModel.draft` so they survive
/// moving between steps.
struct OnboardingScreen: View {
    var step: Int

    @Environment(AppRouter.self) private var router
    @Environment(PlayerProfileModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.launchConfiguration) private var launch

    /// Step 1 is never shown on its own; anything outside 2…3 opens the nearest real step.
    private var shownStep: Int { min(3, max(2, step)) }

    var body: some View {
        Group {
            if shownStep == 2 {
                ProfileStep(next: { go(to: 3) }, back: leaveOnboarding)
            } else {
                PlayStep(back: { go(to: 2) })
            }
        }
        .id(shownStep)
        .transition(OnboardingMotion.stepChange(forward: true, reduceMotion: reduceMotion).transition)
    }

    private var reduceMotion: Bool { systemReduceMotion || launch.reduceMotion }

    private func go(to step: Int) {
        withAnimation(Motion.standard.animation(reduceMotion: reduceMotion)) {
            router.show(.preShell(.onboarding(step: step)))
        }
    }

    /// Back from the first step: Welcome for a new player; the shell for one who came from the demo's "Make it yours".
    private func leaveOnboarding() {
        withAnimation(Motion.standard.animation(reduceMotion: reduceMotion)) {
            if model.needsWelcome { router.show(.preShell(.welcome)) } else { router.enterShell() }
        }
    }
}

/// How onboarding moves (screens.md §0.4): steps slide in from the trailing edge; with Reduce Motion every change,
/// including the swap of the app's root, is a cross-fade only.
enum OnboardingMotion: Equatable {
    case slide(Edge)
    case crossFade

    static func stepChange(forward: Bool, reduceMotion: Bool) -> OnboardingMotion {
        reduceMotion ? .crossFade : .slide(forward ? .trailing : .leading)
    }

    /// The pre-shell ⇄ shell swap is a cross-fade with or without Reduce Motion.
    static let rootSwap = OnboardingMotion.crossFade

    var transition: AnyTransition {
        switch self {
        case .slide(let edge): .asymmetric(insertion: .move(edge: edge).combined(with: .opacity), removal: .opacity)
        case .crossFade: .opacity
        }
    }
}

// MARK: - Shared chrome

/// The onboarding page: Back, the small lockup, the StepRail, the title, the content, and a bottom action that stays
/// reachable (a safe-area inset). One readable column, 560 pt at most.
struct OnboardingPage<Content: View, Actions: View>: View {
    var step: Int
    var title: String
    var subtitle: String
    var back: () -> Void
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility text sizes a pinned bar would cover most of the screen, so the actions end the page instead.
    private var pinsActions: Bool { !dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                ZStack {
                    JovraLockup(height: 40)
                    HStack {
                        Button(action: back) {
                            Image(systemName: "chevron.backward")
                                .font(.body.weight(.semibold))
                                .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.jovra(.textPrimary))
                        .accessibilityLabel(Text("Back", tableName: "Onboarding"))
                        .accessibilityIdentifier("onboarding.back")
                        Spacer()
                    }
                }
                StepRail(current: step, labels: [
                    String(localized: "Account", table: "Onboarding", comment: "Step rail: step 1"),
                    String(localized: "Profile", table: "Onboarding", comment: "Step rail: step 2"),
                    String(localized: "Play", table: "Onboarding", comment: "Step rail: step 3"),
                ])
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(title)
                        .jovraDisplayTitle()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("screen.title")
                    Text(subtitle)
                        .font(.jovraSubtitle)
                        .foregroundStyle(.jovra(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
                if !pinsActions {
                    VStack(spacing: Space.x1) { actions }
                        .padding(.top, Space.x1)
                }
                #if DEBUG
                PermissionRequestProbe()
                #endif
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.top, Space.x1)
            .padding(.bottom, Space.x4)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // An opaque page-coloured backdrop under the status bar, as JovraScreen has, so scrolled content never sits
        // behind the clock.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0).background(Color.jovra(.background))
        }
        .clipped()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if pinsActions { pinnedActions }
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
            // Back swipes to the previous step (S02 Route); the swipe starts near the leading edge.
            if value.startLocation.x < 32, value.translation.width > 80 { back() }
        })
    }

    private var pinnedActions: some View {
            VStack(spacing: Space.x1) { actions }
                .padding(.horizontal, Space.screenMargin)
                .padding(.top, Space.x1 + Space.half)
                .padding(.bottom, Space.x1)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .background(Color.jovra(.background).ignoresSafeArea())
                .overlay(alignment: .top) { Rectangle().fill(Color.jovra(.separator)).frame(height: 0.5) }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("screen.bottomBar")
    }
}

// MARK: - Step 2 "Profile"

private struct ProfileStep: View {
    var next: () -> Void
    var back: () -> Void
    @Environment(PlayerProfileModel.self) private var model

    var body: some View {
        @Bindable var model = model
        OnboardingPage(step: 2,
                       title: String(localized: "Make it your game", table: "Onboarding"),
                       subtitle: String(localized: "Tell us a bit about your tennis game.", table: "Onboarding"),
                       back: back) {
            ProfileFormFields(profile: $model.draft, savedHandedness: nil)
            Text("Change these anytime.", tableName: "Onboarding")
                .font(.jovraCaption)
                .foregroundStyle(.jovra(.textSecondary))
                .accessibilityIdentifier("onboarding.changeAnytime")
        } actions: {
            Button(action: next) {
                Label(String(localized: "Continue", table: "Onboarding"), systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(.jovraPrimary)
            .accessibilityIdentifier("onboarding.continue")
        }
    }
}

// MARK: - Step 3 "Play"

private struct PlayStep: View {
    var back: () -> Void

    @Environment(AppRouter.self) private var router
    @Environment(PlayerProfileModel.self) private var model
    @Environment(\.appPreferences) private var preferences
    @Environment(\.localCaptureLibrary) private var library
    @State private var units: UnitSystem? = nil
    @State private var problem: String?
    @State private var isWorking = false

    var body: some View {
        @Bindable var model = model
        OnboardingPage(step: 3,
                       title: String(localized: "How you play", table: "Onboarding"),
                       subtitle: String(localized: "Two quick choices, then you're on court.", table: "Onboarding"),
                       back: back) {
            ProfileFieldGroup(title: String(localized: "Usually play", table: "Onboarding")) {
                ChoiceSegment(options: UsualFormat.allCases, selection: $model.draft.usualFormat,
                              title: \.title, identifier: "onboarding.format")
            }
            ProfileFieldGroup(title: String(localized: "Units", table: "Onboarding")) {
                ChoiceSegment(options: UnitSystem.allCases, selection: $units, title: \.shortTitle, identifier: "onboarding.units")
            }
            FootageCards()
            if let problem {
                BannerView(tone: .attention, title: problem, message: nil, primaryAction: nil, secondaryAction: nil)
                    .accessibilityIdentifier("onboarding.problem")
            }
        } actions: {
            Button { finish(then: .record) } label: {
                Label(String(localized: "Record your first session", table: "Onboarding"), systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(JovraButtonStyle(kind: .accent, fullWidth: true))
            .accessibilityIdentifier("onboarding.recordFirst")
            Button(String(localized: "Look around first", table: "Onboarding")) { finish(then: .home) }
                .buttonStyle(.jovraSecondary)
                .accessibilityIdentifier("onboarding.lookAround")
            if !model.hasSampleContent {
                Button { finish(then: .sample) } label: {
                    Text("Explore the sample", tableName: "Onboarding")
                        .font(.jovraLabel.weight(.semibold))
                        .underline()
                        .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.jovra(.textPrimary))
                .accessibilityIdentifier("onboarding.exploreSample")
            }
        }
        .disabled(isWorking)
        .onAppear { units = units ?? preferences.units }
    }

    private enum Destination { case record, home, sample }

    private func finish(then destination: Destination) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                if let units { preferences.units = units }
                try model.completeOnboarding()
                if destination == .sample {
                    try await model.installSample(library: library, content: BundledSampleLibrary.load())
                }
                router.show(.tab(destination == .record ? .record : .home))
            } catch {
                Logger(subsystem: "com.islanddevcrew.jovra", category: "Onboarding")
                    .error("Onboarding could not finish: \(String(describing: error), privacy: .public)")
                problem = model.profile == nil
                    ? String(localized: "Your profile could not be saved. Your choices are still here; try again.", table: "Onboarding")
                    : String(localized: "Your profile is saved, but the sample could not be added. You can add it later from Home.", table: "Onboarding")
                if model.profile != nil, destination == .sample { router.show(.tab(.home)) }
            }
        }
    }
}

/// The own-your-footage promise, where originals live and the iCloud device-backup default (stories 14, 15), and how
/// recording asks for permissions. Statements only: nothing here asks for anything.
private struct FootageCards: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1 + Space.half) {
            InfoCard(symbol: "lock.shield",
                     title: String(localized: "Your videos stay yours: no hour limits, no ads", table: "Onboarding"),
                     message: String(localized: "Originals are saved on this iPhone first, in JOVRA's own storage. Nothing is uploaded unless you back up to your own Google Drive.", table: "Onboarding"),
                     tone: .positive)
                .accessibilityIdentifier("onboarding.promise")
            InfoCard(symbol: "icloud.slash",
                     title: String(localized: "Left out of iCloud device backup", table: "Onboarding"),
                     message: String(localized: "Originals are excluded from your iCloud device backup by default, so a long match never fills it. You can change this in Settings.", table: "Onboarding"))
                .accessibilityIdentifier("onboarding.icloud")
            InfoCard(symbol: "video",
                     title: String(localized: "How JOVRA records", table: "Onboarding"),
                     message: String(localized: "We ask for the camera when you first record. The microphone is optional; we'll explain before asking.", table: "Onboarding"))
                .accessibilityIdentifier("onboarding.howRecording")
        }
    }
}

private extension UnitSystem {
    /// S02 step 3 "Units": "mph · lb" / "km/h · kg".
    var shortTitle: String {
        switch self {
        case .imperial: String(localized: "mph · lb", table: "Onboarding", comment: "Units choice")
        case .metric: String(localized: "km/h · kg", table: "Onboarding", comment: "Units choice")
        }
    }
}
