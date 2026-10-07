import SwiftUI

/// The five-tab shell. Focused flows are presented as full-screen routes (via `AppRouter`); while one
/// is up the tab bar is removed, not just covered.
struct AppShell: View {
    @State private var router = AppRouter()

    var body: some View {
        // A native TabView keeps each tab's navigation state and mounts only the selected tab, so
        // hidden tabs never reach VoiceOver; its system bar is hidden in favour of `JovraTabBar`.
        TabView(selection: Binding(get: { router.selectedTab }, set: { router.select($0) })) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack { TabRoot(tab: tab) }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(tab)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if router.isTabBarVisible {
                JovraTabBar(selection: Binding(get: { router.selectedTab }, set: { router.select($0) }))
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
