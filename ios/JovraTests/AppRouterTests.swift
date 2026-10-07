import Testing
@testable import Jovra

@MainActor
@Suite("App router")
struct AppRouterTests {
    @Test("tabs are Home, Sessions, Record, Insights, Profile in that order")
    func tabOrder() {
        #expect(AppTab.allCases.map(\.title) == ["Home", "Sessions", "Record", "Insights", "Profile"])
    }

    @Test("starts on Home with no full-screen route")
    func initialState() {
        let router = AppRouter()
        #expect(router.selectedTab == .home)
        #expect(router.fullScreenRoute == nil)
    }

    @Test("presenting a full-screen route hides the tabs until it is dismissed")
    func presentAndDismiss() {
        let router = AppRouter()
        router.select(.record)
        router.present(.capturePreview)
        #expect(router.fullScreenRoute == .capturePreview)
        #expect(!router.isTabBarVisible)
        router.dismissFullScreen()
        #expect(router.fullScreenRoute == nil)
        #expect(router.isTabBarVisible)
        #expect(router.selectedTab == .record)
    }
}
