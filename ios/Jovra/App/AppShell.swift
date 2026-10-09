import SwiftUI

/// The five-tab shell: each tab has its own `NavigationStack` with typed pushes, full-screen routes
/// remove the tab bar (removed, not covered), and sheets present over whatever shows.
struct AppShell: View {
    @Environment(AppRouter.self) private var router

    private var selection: Binding<AppTab> {
        Binding(get: { router.selectedTab }, set: { router.select($0) })
    }

    var body: some View {
        // A native TabView keeps each tab's navigation state and mounts only the selected tab, so
        // hidden tabs never reach VoiceOver; its system bar is hidden in favour of `JovraTabBar`.
        TabView(selection: selection) {
            ForEach(AppTab.allCases) { tab in
                TabStack(tab: tab, selection: selection)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(tab)
            }
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .sheet(item: sheetBinding(overFullScreen: false)) { SheetDestination(route: $0).presentedSheet(router) }
        .fullScreenCover(item: Binding(get: { router.fullScreenRoute }, set: { if $0 == nil { router.dismissFullScreen() } })) { route in
            FullScreenDestination(route: route)
                .environment(router)
                // A sheet over a full-screen route is presented by the cover itself.
                .sheet(item: sheetBinding(overFullScreen: true)) { SheetDestination(route: $0).presentedSheet(router) }
        }
    }

    /// The router's sheet, presented by the shell or, while a full-screen route is up, by the cover.
    private func sheetBinding(overFullScreen: Bool) -> Binding<SheetRoute?> {
        Binding(
            get: { (router.fullScreenRoute != nil) == overFullScreen ? router.sheet : nil },
            set: { if $0 == nil, (router.fullScreenRoute != nil) == overFullScreen { router.dismissSheet() } }
        )
    }
}

/// One tab's stack. The bar is inset into the root and into every pushed screen, inside the
/// NavigationStack: an inset applied outside the TabView or the stack does not reach the scroll view,
/// so the end of a screen could never scroll clear of the bar.
private struct TabStack: View {
    var tab: AppTab
    var selection: Binding<AppTab>
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        switch tab {
        case .sessions:
            NavigationStack(path: $router.state.sessionsPath) {
                root.navigationDestination(for: SessionsRoute.self) { SessionsDestination(route: $0).tabBarInset(selection) }
            }
        case .insights:
            NavigationStack(path: $router.state.insightsPath) {
                root.navigationDestination(for: InsightsRoute.self) { InsightsDestination(route: $0).tabBarInset(selection) }
            }
        case .profile:
            NavigationStack(path: $router.state.profilePath) {
                root.navigationDestination(for: ProfileRoute.self) { ProfileDestination(route: $0).tabBarInset(selection) }
            }
        case .home, .record:
            NavigationStack { root }
        }
    }

    private var root: some View {
        TabRoot(tab: tab).tabBarInset(selection)
    }
}

private extension View {
    func tabBarInset(_ selection: Binding<AppTab>) -> some View {
        modifier(TabBarInset(selection: selection))
    }

    func presentedSheet(_ router: AppRouter) -> some View {
        // Full height by default. A sheet that wants other detents sets `.presentationDetents` in its
        // own view (its owning ticket decides). On iOS 26 a medium-detent sheet is drawn scaled, which
        // made the 44 pt Close control measure 42 pt and tripped the text-clipping audit.
        // Every sheet has its own 44 pt Close control; the system grabber (72 × 24 pt) is not offered.
        presentationDragIndicator(.hidden)
            .environment(router)
    }
}

private struct TabBarInset: ViewModifier {
    var selection: Binding<AppTab>
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if router.isTabBarVisible {
                JovraTabBar(selection: selection)
            }
        }
    }
}

private struct TabRoot: View {
    var tab: AppTab

    var body: some View {
        switch tab {
        case .home: HomeView()
        case .sessions: SessionsView()
        case .record: RecordView()
        case .insights: InsightsView()
        case .profile: ProfileView()
        }
    }
}
