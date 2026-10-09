import Foundation
import Observation
import OSLog
import SwiftUI

/// The five main tabs, in display order.
enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home, sessions, record, insights, profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Home", table: "App")
        case .sessions: String(localized: "Sessions", table: "App")
        case .record: String(localized: "Record", table: "App")
        case .insights: String(localized: "Insights", table: "App")
        case .profile: String(localized: "Profile", table: "App")
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .sessions: "calendar"
        case .record: "plus"
        case .insights: "chart.bar"
        case .profile: "person"
        }
    }

    /// Filled variant for the selected tab (only where SF Symbols has one; `calendar` has no fill).
    var selectedSymbol: String {
        switch self {
        case .home: "house.fill"
        case .sessions: "calendar"
        case .record: "plus"
        case .insights: "chart.bar.fill"
        case .profile: "person.fill"
        }
    }

    /// Stable identifier for UI tests.
    var accessibilityIdentifier: String { "tab.\(rawValue)" }
}

/// Everything about where the player is, as one value: what state restoration saves and restores.
struct RouterState: Codable, Equatable, Sendable {
    /// The pre-shell route while welcome or onboarding is up; nil once the shell shows.
    var preShell: PreShellRoute?
    var selectedTab: AppTab = .home
    var sessionsPath: [SessionsRoute] = []
    var insightsPath: [InsightsRoute] = []
    var profilePath: [ProfileRoute] = []
    var fullScreen: FullScreenRoute?
    var sheet: SheetRoute?

    /// The bytes kept in scene storage.
    func restorationData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    init() {}

    /// Decodes saved state. Data from an older build that no longer decodes throws; the caller then
    /// starts fresh rather than restoring half a state.
    init(restorationData data: Data) throws {
        self = try JSONDecoder().decode(RouterState.self, from: data)
    }
}

/// App-wide navigation state, provided through the SwiftUI environment. Feature code calls
/// `show(_:)`, `present(_:)` and friends; it never builds views for another feature.
@MainActor
@Observable
final class AppRouter {
    var state: RouterState

    init(state: RouterState = RouterState()) {
        self.state = state
    }

    convenience init(selectedTab: AppTab) {
        var state = RouterState()
        state.selectedTab = selectedTab
        self.init(state: state)
    }

    // MARK: Reading

    var selectedTab: AppTab { state.selectedTab }
    var fullScreenRoute: FullScreenRoute? { state.fullScreen }
    var sheet: SheetRoute? { state.sheet }
    var preShell: PreShellRoute? { state.preShell }

    /// The tab bar shows only in the shell, with no full-screen route up.
    var isTabBarVisible: Bool { state.preShell == nil && state.fullScreen == nil }

    // MARK: Navigating

    func select(_ tab: AppTab) { state.selectedTab = tab }

    /// Presents a full-screen route over the current tab, which is kept for when it is dismissed.
    func present(_ route: FullScreenRoute) {
        state.sheet = nil
        state.fullScreen = route
    }

    /// Dismisses the full-screen route and any sheet presented over it.
    func dismissFullScreen() {
        state.sheet = nil
        state.fullScreen = nil
    }

    /// Presents a sheet over whatever is showing (a tab, a push or a full-screen route).
    func present(sheet: SheetRoute) { state.sheet = sheet }

    func dismissSheet() { state.sheet = nil }

    /// Pushes onto the stack of the route's tab, selecting that tab.
    func push(_ route: PushRoute) {
        state.selectedTab = route.tab
        switch route {
        case .sessions(let route): state.sessionsPath.append(route)
        case .insights(let route): state.insightsPath.append(route)
        case .profile(let route): state.profilePath.append(route)
        }
    }

    /// Leaves welcome and onboarding for the shell.
    func enterShell() { state.preShell = nil }

    /// Sends the app to `destination` from anywhere: what deep links and the launch harness use.
    /// A push replaces its tab's stack, so the destination is one Back away from the tab root.
    func show(_ destination: AppDestination) {
        switch destination {
        case .preShell(let route):
            state = RouterState()
            state.preShell = route
        case .tab(let tab):
            leaveFocusedFlows()
            state.selectedTab = tab
        case .push(let route):
            leaveFocusedFlows()
            switch route {
            case .sessions(let route): state.sessionsPath = [route]
            case .insights(let route): state.insightsPath = [route]
            case .profile(let route): state.profilePath = [route]
            }
            state.selectedTab = route.tab
        case .fullScreen(let route):
            state.preShell = nil
            present(route)
        case .sheet(let route):
            state.preShell = nil
            present(sheet: route)
        }
    }

    /// Applies several destinations in order (a deep link may select a tab, then present a route).
    func show(_ destinations: [AppDestination]) {
        destinations.forEach(show)
    }

    private func leaveFocusedFlows() {
        state.preShell = nil
        state.fullScreen = nil
        state.sheet = nil
    }

    // MARK: Deep links

    /// Opens a `jovra://` link. Returns false (and changes nothing) for a link JOVRA does not know,
    /// including the Google Drive OAuth redirect, which belongs to the Drive sign-in session.
    @discardableResult
    func open(_ url: URL, sessions: any SessionLookup) async -> Bool {
        guard let link = DeepLink(url: url) else {
            Logger(subsystem: "com.islanddevcrew.jovra", category: "DeepLink")
                .notice("Ignored link with scheme \(url.scheme ?? "none", privacy: .public)")
            return false
        }
        show(await link.destinations(sessions: sessions))
        return true
    }
}
