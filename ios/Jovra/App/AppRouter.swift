import Observation
import SwiftUI

/// The five main tabs, in display order.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
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

/// Focused flows that take over the whole screen and hide the tab bar
/// (capture, replay and compare arrive in later tickets).
enum FullScreenRoute: String, Identifiable, Hashable {
    case capturePreview

    var id: String { rawValue }
}

/// App-wide navigation state, provided through the SwiftUI environment.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab
    var fullScreenRoute: FullScreenRoute?

    init(selectedTab: AppTab = .home) {
        self.selectedTab = selectedTab
    }

    var isTabBarVisible: Bool { fullScreenRoute == nil }

    func select(_ tab: AppTab) { selectedTab = tab }

    func present(_ route: FullScreenRoute) { fullScreenRoute = route }

    func dismissFullScreen() { fullScreenRoute = nil }
}
