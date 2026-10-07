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

    /// The largest accessibility text size (AX5). The tab bar must stay one compact row with every
    /// title on one line (its labels cap at xxxLarge and hand over to the Large Content Viewer), the
    /// Sessions filter pills must stack instead of breaking words, and every tab must pass the audit.
    @MainActor
    func testEveryTabAtLargestAccessibilityTextSize() throws {
        let app = launch(appearance: "light", contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        let tabBar = app.otherElements["tabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        for (index, tab) in tabs.enumerated() {
            let button = app.buttons[tab.identifier]
            button.tap()
            XCTAssertTrue(heading(tab.heading, in: app).waitForExistence(timeout: 5), "\(tab.slug) shows “\(tab.heading)”")
            XCTAssertTrue(button.isSelected, "\(tab.identifier) reports selected")

            XCTAssertLessThanOrEqual(tabBar.frame.height, app.frame.height * 0.15, "tab bar (overhang strip and home-indicator inset included) stays compact at AX5 (\(tabBar.frame))")
            let frames = tabs.map { app.buttons[$0.identifier].frame }
            for (other, frame) in zip(tabs, frames) {
                XCTAssertEqual(frame.minY, frames[0].minY, accuracy: 0.5, "\(other.identifier) sits on the same row")
                XCTAssertEqual(frame.height, frames[0].height, accuracy: 0.5, "\(other.identifier) title stays on one line")
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
            try audit(app)
        }
    }

    // MARK: Helpers

    /// Runs Xcode's full accessibility audit on what is on screen, then audits again one, two, …
    /// slow swipes further down (each swipe shorter than the viewport) until the end of the screen,
    /// so anything first seen cut off by the tab bar is audited fully visible at a later step.
    ///
    /// Two narrow exceptions. A *dynamic type* issue on tab bar text is ignored: its titles cap at
    /// xxxLarge and the Large Content Viewer takes over (JovraTabBar). A *contrast* issue on an element
    /// that is not a tab bar item is ignored in one audit pass when the element is clipped (under the
    /// status-bar backdrop, or reaching into the tab bar and the strip reserved for the Record circle)
    /// or ends within `edgeBand` of the bar, where the audit's sampling takes in the bar and the
    /// chartreuse circle. SwiftUI keeps off-screen scroll content in the tree, so such elements are
    /// sampled against pixels that are not theirs. Every ignored issue is logged.
    ///
    /// Nothing escapes the audit this way. Each slow swipe moves the page by more than `edgeBand` and
    /// less than the visible height, so an element in the band at one step is fully visible and clear
    /// of the band at the next; and the last step (the end of the screen, always audited) leaves the
    /// final element Space.x4 (32 pt, twice `edgeBand`) above the bar, as JovraScreen pads its end.
    @MainActor
    private func audit(_ app: XCUIApplication) throws {
        // On a tab screen the lockup is the first row, Space.x1 (8 pt) below the status-bar backdrop.
        let lockup = app.descendants(matching: .any).matching(identifier: "brand.lockup").firstMatch
        let onTabScreen = app.otherElements["tabBar"].exists && lockup.exists
        let visibleTop = onTabScreen ? lockup.frame.minY - 8 : 0
        let title = app.staticTexts.matching(identifier: "screen.title").firstMatch
        let scrollView = app.scrollViews.firstMatch
        try auditVisibleScreen(app, visibleTop: visibleTop)
        guard scrollView.exists, title.exists else { return }
        // The audit itself may move the scroll position, so each step starts again from the top
        // and scrolls `step` slow swipes down; it stops once another swipe no longer moves the page.
        var previousTitleY = title.frame.minY
        for step in 1...6 {
            scrollToTop(scrollView)
            for _ in 0..<step { scrollView.swipeUp(velocity: .slow) }
            let titleY = title.frame.minY
            guard abs(titleY - previousTitleY) > 1 else { break }
            previousTitleY = titleY
            try auditVisibleScreen(app, visibleTop: visibleTop)
        }
        scrollToTop(scrollView)
    }

    @MainActor
    private func scrollToTop(_ scrollView: XCUIElement) {
        for _ in 0..<3 { scrollView.swipeDown(velocity: .fast) }
    }

    /// Height of the band above the tab bar in which contrast sampling is unreliable (see `audit`).
    private static let edgeBand: CGFloat = 16

    @MainActor
    private func auditVisibleScreen(_ app: XCUIApplication, visibleTop: CGFloat) throws {
        let tabBar = app.otherElements["tabBar"]
        let visibleBottom = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
        let tabBarFrame = tabBar.exists ? tabBar.frame : .null
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element else { return false }
            if issue.auditType == .dynamicType, tabBarFrame.contains(element.frame) {
                print("audit: ignored dynamic type on tab bar “\(element.label)” (Large Content Viewer)")
                return true
            }
            guard issue.auditType == .contrast else { return false }
            let frame = element.frame
            let isTabBarItem = element.identifier.hasPrefix("tab.")
            let isClipped = !isTabBarItem && (frame.maxY > visibleBottom - Self.edgeBand || frame.minY < visibleTop)
            print("audit: contrast issue on “\(element.label)” at \(frame), visible \(visibleTop)–\(visibleBottom): \(isClipped ? "ignored (clipped or in the edge band)" : "FAILS")")
            return isClipped
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
    private func launch(appearance: String, contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-\(appearanceKey)", appearance]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
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
