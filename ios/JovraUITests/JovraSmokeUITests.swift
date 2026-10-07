import XCTest

/// Smoke test for the app shell: every tab renders its heading, reports its selected state, passes
/// Xcode's automated accessibility audit, and is captured as a screenshot attachment, in light and
/// dark appearance. Screenshots are exported to evidence/ios/ by scripts/ios/ui-test.sh.
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
        try visitEveryTab(appearance: "light")
    }

    @MainActor
    func testEveryTabInDarkAppearance() throws {
        try visitEveryTab(appearance: "dark")
    }

    @MainActor
    func testFullScreenRouteHidesTabsAndReturns() throws {
        let app = launch(appearance: "light")
        app.buttons["tab.record"].tap()
        app.buttons["record.previewCapture"].tap()

        XCTAssertTrue(app.staticTexts["capture.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.home"].waitForNonExistence(timeout: 5), "tab bar should be hidden by a full-screen route")
        attachScreenshot(app, name: "light-6-capture-route")
        try audit(app)

        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.buttons["tab.record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.record"].isSelected, "dismissing returns to the tab that opened the route")
        attachScreenshot(app, name: "light-7-after-route")
    }

    @MainActor
    func testHomeHeroOpensRecordTab() {
        let app = launch(appearance: "light")
        app.buttons["home.recordSession"].tap()
        XCTAssertTrue(app.buttons["tab.record"].isSelected)
        XCTAssertTrue(heading("Set up your session", in: app).waitForExistence(timeout: 5))
    }

    /// With the "System" preference the app follows the device appearance. scripts/ios/ui-test.sh
    /// runs this once with the simulator in light and once in dark.
    @MainActor
    func testSystemAppearanceIsFollowed() throws {
        let app = launch(appearance: "system")
        XCTAssertTrue(heading("Home", in: app).waitForExistence(timeout: 5))
        attachScreenshot(app, name: "system-home")
        try audit(app)
    }

    // MARK: Helpers

    /// Runs Xcode's full accessibility audit. One narrow exception: a *contrast* issue on an element
    /// that reaches into the opaque tab bar (or touches its top edge, where the audit's sampling
    /// window takes in bar pixels) is ignored. Such an element is scrolled out of sight or cut by the
    /// bar; SwiftUI keeps off-screen scroll content in the tree, and the audit measures the bar, not
    /// the element. Text contrast itself is enforced for every colour role by ColorRoleContrastTests.
    /// Every other issue, of every audit type, fails the test.
    @MainActor
    private func audit(_ app: XCUIApplication) throws {
        let tabBar = app.otherElements["tabBar"]
        let visibleBottom = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
        let edgeSamplingMargin: CGFloat = 6
        try app.performAccessibilityAudit { issue in
            guard issue.auditType == .contrast, let element = issue.element else { return false }
            let atOrBehindTabBar = element.frame.maxY > visibleBottom - edgeSamplingMargin
            if atOrBehindTabBar {
                print("audit: ignored contrast on “\(element.label)” at \(element.frame) (tab bar top \(visibleBottom))")
            }
            return atOrBehindTabBar
        }
    }

    @MainActor
    private func visitEveryTab(appearance: String) throws {
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
            attachScreenshot(app, name: "\(appearance)-\(index + 1)-\(tab.slug)")
            try audit(app)
        }
    }

    @MainActor
    private func launch(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-\(appearanceKey)", appearance]
        app.launch()
        return app
    }

    private var appearanceKey: String { "appearance" }

    @MainActor
    private func heading(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(identifier: "screen.title").matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
