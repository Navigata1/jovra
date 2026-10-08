import SwiftUI

/// The five-tab shell. Focused flows are presented as full-screen routes (via `AppRouter`); while one
/// is up the tab bar is removed, not just covered.
struct AppShell: View {
    /// Starts on the tab or full-screen route named by the `-startRoute` launch argument, if any.
    @State private var router: AppRouter = {
        let launch = LaunchConfiguration.current
        let router = AppRouter(selectedTab: launch.startTab ?? .home)
        if let route = launch.startFullScreenRoute { router.present(route) }
        return router
    }()

    private var selection: Binding<AppTab> {
        Binding(get: { router.selectedTab }, set: { router.select($0) })
    }

    var body: some View {
        // A native TabView keeps each tab's navigation state and mounts only the selected tab, so
        // hidden tabs never reach VoiceOver; its system bar is hidden in favour of `JovraTabBar`.
        // The bar is inset into each tab's root screen, inside its NavigationStack: an inset applied
        // outside the TabView or the NavigationStack does not reach the scroll view, so the end of a
        // screen could never scroll clear of the bar.
        TabView(selection: selection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    TabRoot(tab: tab)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if router.isTabBarVisible {
                                JovraTabBar(selection: selection)
                            }
                        }
                }
                .toolbar(.hidden, for: .tabBar)
                    .tag(tab)
            }
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .environment(router)
        .fullScreenCover(item: Binding(get: { router.fullScreenRoute }, set: { router.fullScreenRoute = $0 })) { route in
            FullScreenDestination(route: route)
                .environment(router)
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

private struct FullScreenDestination: View {
    var route: FullScreenRoute

    var body: some View {
        switch route {
        case .capturePreview: CapturePlaceholderView()
        }
    }
}
