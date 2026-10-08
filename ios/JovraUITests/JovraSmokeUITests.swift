import XCTest

/// Smoke test for the app shell: every tab renders its heading, reports its selected state, passes
/// Xcode's automated accessibility audit (Support/AccessibilityAuditing.swift), and is captured as a
/// screenshot attachment, in light and dark appearance. Screenshots are exported to evidence/ios/ by
/// scripts/ios/ui-test.sh.
final class JovraSmokeUITests: XCTestCase {
    private let tabs: [(identifier: String, slug: String, label: String, heading: String)] = [
        ("tab.home", "home", "Home", "Home"),
        ("tab.sessions", "sessions", "Sessions", "Your sessions"),
        ("tab.record", "record", "Record", "Set up your session"),
        ("tab.insights", "insights", "Insights", "Insights"),
        ("tab.profile", "profile", "Profile", "Profile"),
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testEveryTabInLightAppearance() throws {
        try visitEveryTab(appearance: .light)
    }

    @MainActor
    func testEveryTabInDarkAppearance() throws {
        try visitEveryTab(appearance: .dark)
    }

    @MainActor
    func testFullScreenRouteHidesTabsAndReturns() throws {
        let app = launch(appearance: .light)
        app.buttons["tab.record"].tap()
        app.buttons["record.previewCapture"].tap()

        XCTAssertTrue(app.staticTexts["capture.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.home"].waitForNonExistence(timeout: 5), "tab bar should be hidden by a full-screen route")
        attachScreenshot(app, name: "light-6-capture-route")
        try auditScreen(app)

        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.buttons["tab.record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.record"].isSelected, "dismissing returns to the tab that opened the route")
        attachScreenshot(app, name: "light-7-after-route")
    }

    @MainActor
    func testHomeHeroOpensRecordTab() {
        let app = launch(appearance: .light)
        app.buttons["home.recordSession"].tap()
        XCTAssertTrue(app.buttons["tab.record"].isSelected)
        XCTAssertTrue(heading("Set up your session", in: app).waitForExistence(timeout: 5))
    }

    /// With the "System" preference the app follows the device appearance. scripts/ios/ui-test.sh
    /// runs this once with the simulator in light and once in dark.
    @MainActor
    func testSystemAppearanceIsFollowed() throws {
        let app = launch(appearance: .system)
        XCTAssertTrue(heading("Home", in: app).waitForExistence(timeout: 5))
        attachScreenshot(app, name: "system-home")
        try auditScreen(app)
    }

    /// The largest accessibility text size (AX5). The tab bar must stay one compact row, and every
    /// English title one line high (its labels cap at xxxLarge and hand over to the Large Content
    /// Viewer; only a long translation wraps, which PseudoLocaleUITests covers). The Sessions filter
    /// pills must stack instead of breaking words, and every tab must pass the audit.
    @MainActor
    func testEveryTabAtLargestAccessibilityTextSize() throws {
        let app = launch(appearance: .light, contentSize: .accessibility5)
        let tabBar = app.otherElements["tabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        for (index, tab) in tabs.enumerated() {
            let button = app.buttons[tab.identifier]
            button.tap()
            XCTAssertTrue(heading(tab.heading, in: app).waitForExistence(timeout: 5), "\(tab.slug) shows “\(tab.heading)”")
            XCTAssertTrue(button.isSelected, "\(tab.identifier) reports selected")

            XCTAssertLessThanOrEqual(tabBar.frame.height, app.frame.height * 0.15, "tab bar (overhang strip and home-indicator inset included) stays compact at AX5 (\(tabBar.frame))")
            let frames = tabs.map { app.buttons[$0.identifier].frame }
            print("ax5: tab item heights \(frames.map(\.height)) pt; one-line limit \(TabItem.maximumOneLineHeight) pt")
            for (other, frame) in zip(tabs, frames) {
                XCTAssertEqual(frame.minY, frames[0].minY, accuracy: 0.5, "\(other.identifier) sits on the same row")
                XCTAssertLessThan(frame.height, TabItem.maximumOneLineHeight,
                                  "\(other.identifier) title stays on one line at AX5 (\(frame.height) pt; a second line adds \(TabItem.titleLineHeight) pt)")
                XCTAssertGreaterThanOrEqual(frame.height, 44, "\(other.identifier) is at least 44 pt tall")
            }

            if tab.slug == "sessions" {
                let pills = ["All", "Matches", "Practice"].map { app.buttons[$0] }
                pills.forEach { XCTAssertTrue($0.exists, "filter pill \($0) exists") }
                XCTAssertLessThan(pills[0].frame.maxY, pills[1].frame.minY + 1, "filter pills stack vertically at AX5")
                XCTAssertLessThan(pills[1].frame.maxY, pills[2].frame.minY + 1, "filter pills stack vertically at AX5")
                XCTAssertGreaterThan(pills[1].frame.width, app.frame.width * 0.6, "a stacked pill spans the panel")
            }

            attachScreenshot(app, name: "ax5-\(index + 1)-\(tab.slug)")
            try auditScreen(app)
        }
    }

    // MARK: Helpers (the audit, screenshots and launch helpers live in Support/)

    /// A tab item's layout (JovraTabBar's TabLabel): a 28 pt icon slot, 3 pt, the title (caption,
    /// capped at xxxLarge), 3 pt, a 5 pt selection dot. One title line keeps the item below
    /// `maximumOneLineHeight`; a second line adds a whole `titleLineHeight`.
    private enum TabItem {
        static let titleLineHeight = UIFont.preferredFont(
            forTextStyle: .caption1, compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge)
        ).lineHeight
        static let maximumOneLineHeight = 28 + 3 + 3 + 5 + titleLineHeight * 1.5
    }

    @MainActor
    private func visitEveryTab(appearance: LaunchConfiguration.Appearance) throws {
        let app = launch(appearance: appearance)
        XCTAssertTrue(app.otherElements["brand.lockup"].exists || app.images["brand.lockup"].exists, "brand lockup is visible")
        for (index, tab) in tabs.enumerated() {
            let button = app.buttons[tab.identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(tab.identifier) exists")
            XCTAssertEqual(button.label, tab.label, "VoiceOver label for \(tab.identifier)")
            button.tap()
            XCTAssertTrue(heading(tab.heading, in: app).waitForExistence(timeout: 5), "\(tab.slug) shows “\(tab.heading)”")
            XCTAssertTrue(button.isSelected, "\(tab.identifier) reports selected")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "\(tab.identifier) is at least 44 pt tall")
            XCTAssertGreaterThanOrEqual(button.frame.width, 44, "\(tab.identifier) is at least 44 pt wide")
            attachScreenshot(app, name: "\(appearance.rawValue)-\(index + 1)-\(tab.slug)")
            try auditScreen(app)
        }
    }

    @MainActor
    private func launch(appearance: LaunchConfiguration.Appearance, contentSize: ContentSize? = nil) -> XCUIApplication {
        XCUIApplication.launchJovra(contentSize: contentSize) { $0.appearance = appearance }
    }

    @MainActor
    private func heading(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.heading(text)
    }
}
