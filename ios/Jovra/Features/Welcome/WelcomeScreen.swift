import JovraCore
import OSLog
import SwiftUI

/// Welcome (S01, reference 01): the first impression and the three ways in — start your own profile, optionally
/// continue with Apple, or look around with sample data. Forest in both appearances, no tab bar. States the ownership
/// promise before anything is asked (P0-18).
struct WelcomeScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(PlayerProfileModel.self) private var model
    @Environment(\.appleSignInClient) private var appleSignIn
    @Environment(\.localCaptureLibrary) private var library
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.launchConfiguration) private var launch

    @State private var notice: WelcomeNotice?
    @State private var isWorking = false

    var body: some View {
        GeometryReader { geometry in
            if verticalSizeClass == .compact {
                // iPhone landscape: hero on the leading 45 %, the panel scrolls on the trailing 55 %.
                HStack(spacing: 0) {
                    hero(topInset: geometry.safeAreaInsets.top)
                        .frame(width: geometry.size.width * 0.45 + geometry.safeAreaInsets.leading)
                        .ignoresSafeArea()
                    ScrollView { panel.padding(.vertical, Space.x3) }
                        .scrollIndicators(.hidden)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(topInset: geometry.safeAreaInsets.top)
                            .frame(height: heroHeight(for: geometry.size.height + geometry.safeAreaInsets.top))
                        panel.padding(.bottom, Space.x3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .ignoresSafeArea(edges: .top)
            }
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        // Forest in both appearances, so the status bar is light too.
        .preferredColorScheme(.dark)
        .disabled(isWorking)
        .jovraAnimation(.reveal, value: notice)
    }

    /// The hero takes the upper 55 % and shrinks first as text grows (at least 120 pt at accessibility sizes).
    private func heroHeight(for height: CGFloat) -> CGFloat {
        dynamicTypeSize.isAccessibilitySize ? max(120, height * 0.22) : height * 0.55
    }

    private func hero(topInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            WelcomeHeroArt()
            JovraLockup(height: dynamicTypeSize.isAccessibilitySize ? 40 : 56, markColor: .jovra(.textOnEditorial), tennisColor: .jovra(.accent), ballColor: .jovra(.accent))
                .padding(.top, topInset + Space.x2)
        }
        .clipped()
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("See your game.", tableName: "Welcome")
                    .font(.system(size: headlineSize, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(.jovra(.textOnEditorial))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("screen.title")
                Text("Every point. Every detail. Your vision.", tableName: "Welcome")
                    .font(.jovraSubtitle)
                    .foregroundStyle(.jovra(.textOnEditorial))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your videos stay yours. No account needed, no hour limits, no ads.", tableName: "Welcome")
                    .font(.jovraCaption)
                    .foregroundStyle(.jovra(.textSecondaryOnEditorial))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.half)
                    .accessibilityIdentifier("welcome.promise")
            }
            if let notice {
                BannerView(tone: notice == .appleCancelled ? .info : .attention, title: notice.message,
                           message: nil, primaryAction: nil, secondaryAction: nil)
                    .accessibilityIdentifier("welcome.notice")
                    .transition(.opacity)
            }
            RestoreOfferSlot()
            VStack(spacing: Space.x1 + Space.half) {
                Button(String(localized: "Get started", table: "Welcome"), action: getStarted)
                    .buttonStyle(JovraButtonStyle(kind: .accent, fullWidth: true))
                    .accessibilityIdentifier("welcome.getStarted")
                if AppleSignInAvailability.isOffered() {
                    AppleSignInButton(action: continueWithApple)
                        .frame(height: 52)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Text("Continue with Apple", tableName: "Welcome"))
                }
                Button(action: exploreDemo) {
                    Label(String(localized: "Explore a demo", table: "Welcome"), systemImage: "arrow.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.jovraLabel)
                        .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.jovra(.textOnEditorial))
                .accessibilityLabel(Text("Explore a demo", tableName: "Welcome"))
                .accessibilityIdentifier("welcome.exploreDemo")
            }
        }
        .padding(.horizontal, Space.screenMargin + Space.x1)
        .padding(.top, Space.x3)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 46

    private var reduceMotion: Bool { systemReduceMotion || launch.reduceMotion }

    // MARK: Actions

    private func getStarted() {
        model.beginOnboarding()
        router.show(.preShell(.onboarding(step: 2)))
    }

    private func continueWithApple() {
        notice = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            switch await model.signInWithApple(using: appleSignIn) {
            case .stayOnWelcome(.cancelled): notice = .appleCancelled
            case .stayOnWelcome(.failed): notice = .appleFailed
            case .enterShell: router.show(.tab(.home))
            case .onboarding: router.show(.preShell(.onboarding(step: 2)))
            }
        }
    }

    private func exploreDemo() {
        notice = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await model.exploreDemo(library: library, content: BundledSampleLibrary.load())
                router.show(.tab(.home))
            } catch {
                Logger(subsystem: "com.islanddevcrew.jovra", category: "Welcome")
                    .error("The demo could not be installed: \(String(describing: error), privacy: .public)")
                notice = .demoFailed
            }
        }
    }
}

/// The plain messages Welcome can show above its buttons. None of them blocks "Get started".
enum WelcomeNotice: Equatable {
    case appleCancelled, appleFailed, demoFailed

    var message: String {
        switch self {
        case .appleCancelled: String(localized: "Sign in with Apple was cancelled. You can continue without an account.", table: "Welcome")
        case .appleFailed: String(localized: "Sign in with Apple didn't finish. You can continue without an account.", table: "Welcome")
        case .demoFailed: String(localized: "The demo couldn't be opened. Nothing was changed; you can try again or get started.", table: "Welcome")
        }
    }
}
