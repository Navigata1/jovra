import XCTest

/// The UI-test harness itself: launch arguments reach the app, the 44 pt and copy helpers check what
/// they claim to check.
final class HarnessUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Launch configuration, end to end

    @MainActor
    func testStartRouteOpensTheNamedTab() {
        let app = XCUIApplication.launchJovra {
            $0.appearance = .dark
            $0.startRoute = "insights"
        }
        XCTAssertTrue(app.heading("Insights").waitForExistence(timeout: 5), "launched on Insights")
        XCTAssertTrue(app.buttons["tab.insights"].isSelected)
        attachScreenshot(app, name: "harness-start-route-insights")
    }

    @MainActor
    func testStartRouteOpensAFullScreenRouteWithoutTheTabBar() {
        let app = XCUIApplication.launchJovra { $0.startRoute = "capturePreview" }
        XCTAssertTrue(app.staticTexts["capture.title"].waitForExistence(timeout: 5), "launched on the capture route")
        XCTAssertFalse(app.buttons["tab.home"].exists, "the tab bar is hidden")
    }

    // MARK: 44 pt targets

    func testUndersizedControlsAreReported() {
        let controls: [HitTarget.Control] = [
            .init(description: "ok", frame: CGRect(x: 0, y: 0, width: 44, height: 44)),
            .init(description: "short", frame: CGRect(x: 0, y: 0, width: 120, height: 30)),
            .init(description: "narrow", frame: CGRect(x: 0, y: 0, width: 43, height: 60)),
        ]
        XCTAssertEqual(HitTarget.undersized(controls).map(\.description), ["short", "narrow"])
    }

    @MainActor
    func testEveryControlOnEveryTabIsAtLeast44Points() {
        let app = XCUIApplication.launchJovra { $0.appearance = .light }
        for tab in ShellTab.allCases {
            app.buttons[tab.identifier].tap()
            XCTAssertTrue(app.heading(tab.heading).waitForExistence(timeout: 5), "\(tab.slug) is showing")
            assertHitTargets(in: app)
        }
    }

    // MARK: Copy from the brief, with the honesty corrections

    func testBriefCopyIsTheQuotedCopyOfEachScreen() throws {
        XCTAssertEqual(try BriefCopy.briefStrings(screen: 1),
                       ["See your game.", "Every point. Every detail. Your vision.", "Get started", "Continue with Apple", "Explore a demo"])
        XCTAssertEqual(try BriefCopy.screens().count, 20)
    }

    func testHonestyCorrectionsReplaceOrDropTheBriefsClaims() throws {
        let setup = try BriefCopy.expected(screen: 4)
        XCTAssertTrue(setup.contains("Best of 3 · Ad · Tie-break at 6–6"))
        XCTAssertFalse(setup.contains("Best of 3 · Advantage"))
        XCTAssertFalse(setup.contains { $0.contains("3.2 GB") })

        let settings = try BriefCopy.expected(screen: 20)
        XCTAssertTrue(settings.contains("Not needed for import"))
        XCTAssertTrue(settings.contains("Add-only"))
        XCTAssertFalse(settings.contains("Selected photos"))
        XCTAssertFalse(settings.contains { $0.contains("Reference concept") })

        XCTAssertTrue(try BriefCopy.expected(screen: 12).contains("Fastest marked serve"))
        XCTAssertTrue(try BriefCopy.expected(screen: 3).contains("+4 percentage points"))
        XCTAssertFalse(try BriefCopy.expected(screen: 11).contains("Estimated from calibrated video"))
        XCTAssertTrue(try BriefCopy.expected(screen: 19).contains("Demo"))
        XCTAssertFalse(try BriefCopy.expected(screen: 19).contains("Connected · Demo"))
    }

    func testAScreensOwnCorrectionWinsOverTheDefault() throws {
        let expected = try BriefCopy.expected(screen: 4, corrections: ["Best of 3 · Advantage": .replace(with: ["Best of 5 · No-Ad"])])
        XCTAssertTrue(expected.contains("Best of 5 · No-Ad"))
        XCTAssertFalse(expected.contains("Best of 3 · Ad · Tie-break at 6–6"))
    }

    @MainActor
    func testCopyAssertionFindsTheShellsBriefCopyOnHome() throws {
        // The foundation Home shows a subset of screen 3; the rest arrives with the Home ticket (T19).
        let app = XCUIApplication.launchJovra { $0.appearance = .light }
        XCTAssertTrue(app.heading("Home").waitForExistence(timeout: 5))
        let shownByShell: Set<String> = ["Your game, in focus.", "Ready for your next session?", "Record a session", "This week", "Sample data"]
        let notYetBuilt = Set(try BriefCopy.expected(screen: 3)).subtracting(shownByShell)
        try assertBriefCopy(screen: 3, in: app, excluding: notYetBuilt)
    }
}
