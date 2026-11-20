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
        let app = XCUIApplication.launchJovra { $0.startRoute = "capture" }
        XCTAssertTrue(app.heading("Capture").waitForExistence(timeout: 5), "launched on the capture route")
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

    // MARK: Screenshot names

    func testScreenshotNamesAreLowerCaseWordsJoinedByHyphens() {
        XCTAssertTrue(Screenshots.isValidName("s04-dark-setup"))
        XCTAssertTrue(Screenshots.isValidName("ax5-1-home"))
        XCTAssertFalse(Screenshots.isValidName("Home Screen"))
        XCTAssertFalse(Screenshots.isValidName("home--screen"))
        XCTAssertFalse(Screenshots.isValidName(""))
    }

    /// A bad name records a test failure; it must not crash the runner (which would lose the other
    /// tests and every attachment of the run).
    @MainActor
    func testABadScreenshotNameFailsTheTestInsteadOfCrashing() {
        continueAfterFailure = true
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { $0.compactDescription.contains("lower-case words joined by hyphens") }
        XCTExpectFailure("a bad screenshot name is a recorded failure", options: options) {
            attachScreenshot(XCUIApplication(), name: "Bad Name")
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
        // Home (T19) in the demo shows screen 3's copy computed from the sample library. The reference's "This week"
        // daily chart and "+4 pts" are deliberate differences of the written spec (S03): a "Last 4 weeks" weekly
        // chart and "+4 percentage points vs last week".
        let app = XCUIApplication.jovra {
            $0.appearance = .light
            $0.demo = .sample
            $0.library = .fresh
        }
        let morning = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 8, minute: 30))!
        app.launchEnvironment["JOVRA_HOME_NOW"] = ISO8601DateFormatter().string(from: morning)
        app.launch()
        XCTAssertTrue(app.heading("Good morning, Jon.").waitForExistence(timeout: 10))
        // Tiles and the latest-session card are single VoiceOver elements, so their numbers are values, not labels:
        // HomeDashboardUITests asserts each one ("8, sample data", "6 hours, 42 minutes, sample data", "67 percent,
        // 40 of 60, sample data", "Jon vs Alex, Jon won 6–4, 6–3, 54 minutes, Singles").
        let spokenInItsCard = BriefCopy.Correction.drop(reason: "read as part of its tile or card (HomeDashboardUITests)")
        try assertBriefCopy(screen: 3, in: app, corrections: [
            "8": spokenInItsCard, "6h 42m": spokenInItsCard, "67%": spokenInItsCard,
            "Jon vs Alex": spokenInItsCard, "6–4 6–3": spokenInItsCard, "54 min · Singles": spokenInItsCard,
            "This week": .replace(with: ["Last 4 weeks"]),
            "+4 pts": .drop(reason: "spoken with the trend value: “+4 percentage points vs last week”"),
        ])
    }
}
