import XCTest

/// Home (S03, T19) in the running app: the demo numbers with their Sample badges, the sample-scope rule, the empty
/// state, the em dash, the next-step rows and their routes, the fraction popover, and the accessibility audit
/// (textClipped included) in light, dark and AX5. Scenarios come from the DEBUG seam `JOVRA_HOME_SCENARIO`
/// (Features/Home/HomeScenario.swift); the clock is fixed at 08:30 on Oct 6, the sample library's last day.
final class HomeDashboardUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Demo

    @MainActor
    func testDemoInLightShowsTheSampleNumbersWithBadges() throws {
        let app = launch(appearance: .light, demo: true)
        try assertDemoNumbers(app)
        attachScreenshot(app, name: "s03-light-demo")
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        attachScreenshot(app, name: "s03-light-demo-lower")
        try auditScreen(app)
    }

    @MainActor
    func testDemoInDarkPassesTheAudit() throws {
        let app = launch(appearance: .dark, demo: true)
        try assertDemoNumbers(app)
        attachScreenshot(app, name: "s03-dark-demo")
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        attachScreenshot(app, name: "s03-dark-demo-lower")
        try auditScreen(app)
    }

    @MainActor
    func testDemoAtAX5PassesTheAudit() throws {
        let app = launch(appearance: .light, demo: true, contentSize: .accessibility5)
        XCTAssertTrue(element(app, "home.tile.sessions").waitForExistence(timeout: 10))
        attachScreenshot(app, name: "s03-ax5-demo")
        for part in ["tiles", "latest", "steps", "trend"] {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            attachScreenshot(app, name: "s03-ax5-demo-\(part)")
        }
        try auditScreen(app)
    }

    @MainActor
    func testFirstServesFractionIsOneTapAway() {
        let app = launch(appearance: .light, demo: true)
        let tile = app.buttons["home.tile.firstServes"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        let value = element(app, "fraction.value")
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertTrue(value.value as? String == "67 percent, 40 of 60, manual, sample data", "popover reads \(String(describing: value.value))")
        XCTAssertTrue(app.staticTexts["40 of 60"].exists)
        attachScreenshot(app, name: "home-light-fraction-popover")
    }

    @MainActor
    func testTheTrendChartIsAnAudioGraph() {
        let app = launch(appearance: .light, demo: true)
        let chart = element(app, "home.trend.chart")
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        XCTAssertEqual(chart.label, "First serves in by week")
        // The descriptor itself (series, axes, values) is verified in HomeDashboardTests; XCUITest exposes only that
        // the element is the chart VoiceOver offers "Chart details" and the Audio Graph on.
        let value = element(app, "home.trend.value")
        XCTAssertTrue((value.value as? String)?.contains("+4 percentage points vs last week") == true,
                      "trend value: \(String(describing: value.value))")
    }

    // MARK: Sample-scope rule

    @MainActor
    func testOneRealSessionBesideTheSamplesCountsOnlyItselfWithoutSampleBadges() throws {
        let app = launch(appearance: .light, scenario: "realPlusSample")
        let sessions = element(app, "home.tile.sessions")
        XCTAssertTrue(sessions.waitForExistence(timeout: 10))
        XCTAssertEqual(sessions.value as? String, "1")
        XCTAssertEqual(element(app, "home.tile.onCourt").value as? String, "54 minutes")
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Sample data")).count, 0,
                       "no Sample badge anywhere once a session of your own exists")
        XCTAssertFalse(element(app, "home.trend.sample").exists)
        attachScreenshot(app, name: "home-light-real-plus-sample")
        try auditScreen(app)
    }

    // MARK: Empty and no data

    @MainActor
    func testFreshInstallShowsTheEmptyStateInLight() throws {
        let app = launch(appearance: .light, scenario: "empty")
        try assertEmptyState(app)
        attachScreenshot(app, name: "s03-light-empty")
        try auditScreen(app)
    }

    @MainActor
    func testFreshInstallShowsTheEmptyStateInDark() throws {
        let app = launch(appearance: .dark, scenario: "empty")
        try assertEmptyState(app)
        attachScreenshot(app, name: "s03-dark-empty")
        try auditScreen(app)
    }

    @MainActor
    func testFreshInstallShowsTheEmptyStateAtAX5() throws {
        let app = launch(appearance: .light, scenario: "empty", contentSize: .accessibility5)
        XCTAssertTrue(element(app, "home.empty").waitForExistence(timeout: 10))
        attachScreenshot(app, name: "s03-ax5-empty")
        try auditScreen(app)
    }

    @MainActor
    func testEmptyStateActionsOpenRecordAndImport() {
        let app = launch(appearance: .light, scenario: "empty")
        let importVideo = app.buttons["home.empty.import"]
        XCTAssertTrue(scrollTo(importVideo, in: app))
        importVideo.tap()
        XCTAssertTrue(app.heading("Bring your game in").waitForExistence(timeout: 5), "Import opens on the Sessions tab")
        app.buttons["tab.home"].tap()
        let record = app.buttons["home.empty.record"]
        XCTAssertTrue(scrollTo(record, in: app))
        record.tap()
        XCTAssertTrue(app.buttons["tab.record"].waitForSelection())
    }

    @MainActor
    func testNoMatchYetShowsAnEmDashNeverZeroPercent() {
        let app = launch(appearance: .light, scenario: "practiceOnly")
        let tile = element(app, "home.tile.firstServes")
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        XCTAssertEqual(tile.value as? String, "no data")
        XCTAssertTrue(tile.label.contains("No match yet"))
        XCTAssertFalse((tile.value as? String)?.contains("0") == true, "never a fake 0%")
        attachScreenshot(app, name: "home-light-no-match-yet")
    }

    // MARK: Next steps

    @MainActor
    func testNeedsReviewOpensPointReviewOnNeedsReview() {
        let app = launch(appearance: .light, scenario: "needsReview")
        let row = app.buttons["home.nextStep.review"]
        XCTAssertTrue(scrollTo(row, in: app))
        XCTAssertEqual(row.label, "Finish reviewing")
        XCTAssertEqual(row.value as? String, "Review 8 flagged points in Jon vs Alex")
        attachScreenshot(app, name: "home-light-next-step-review")
        row.tap()
        XCTAssertTrue(app.heading("Point review").waitForExistence(timeout: 5))
        let payload = element(app, "placeholder.payload")
        XCTAssertTrue(payload.waitForExistence(timeout: 5))
        XCTAssertTrue(payload.label.contains("home-review-1") && payload.label.contains("Needs review"),
                      "the route carries the session and the Needs review filter: \(payload.label)")
    }

    @MainActor
    func testLocalOnlyOpensStorage() {
        let app = launch(appearance: .light, scenario: "localOnly")
        let row = app.buttons["home.nextStep.backUp"]
        XCTAssertTrue(scrollTo(row, in: app))
        XCTAssertEqual(row.label, "Back up Jon vs Alex")
        attachScreenshot(app, name: "home-light-next-step-backup")
        row.tap()
        XCTAssertTrue(app.heading("Storage and backup").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.profile"].isSelected)
    }

    @MainActor
    func testSavedWithGapsOpensThatSession() {
        assertResumeRow(scenario: "savedWithGaps", session: "home-gaps-1", screenshot: "home-light-next-step-resume")
    }

    @MainActor
    func testInterruptedOpensThatSession() {
        assertResumeRow(scenario: "interrupted", session: "home-partial-1", screenshot: nil)
    }

    // MARK: Helpers

    @MainActor
    private func assertResumeRow(scenario: String, session: String, screenshot: String?) {
        let app = launch(appearance: .light, scenario: scenario)
        let row = app.buttons["home.nextStep.resume"]
        XCTAssertTrue(scrollTo(row, in: app))
        XCTAssertEqual(row.label, "Pick up your interrupted session")
        XCTAssertTrue((row.value as? String)?.hasPrefix("Jon vs Alex stopped early.") == true)
        if let screenshot { attachScreenshot(app, name: screenshot) }
        row.tap()
        XCTAssertTrue(app.buttons["tab.home"].waitForNonExistence(timeout: 5), "replay covers the tabs")
        XCTAssertTrue(element(app, "replay.scroll").waitForExistence(timeout: 5), "the replay route opened for \(session)")
    }

    @MainActor
    private func assertDemoNumbers(_ app: XCUIApplication) throws {
        XCTAssertTrue(app.heading("Good morning, Jon.").waitForExistence(timeout: 10))
        let sessions = element(app, "home.tile.sessions")
        XCTAssertTrue(sessions.waitForExistence(timeout: 10))
        XCTAssertEqual(sessions.label, "Sessions, Last 4 weeks")
        XCTAssertEqual(sessions.value as? String, "8, sample data")
        XCTAssertEqual(element(app, "home.tile.onCourt").value as? String, "6 hours, 42 minutes, sample data")
        let firstServes = app.buttons["home.tile.firstServes"]
        XCTAssertEqual(firstServes.label, "First serves in, Latest match")
        XCTAssertEqual(firstServes.value as? String, "67 percent, 40 of 60, manual, sample data")
        let latest = element(app, "home.latestSession")
        XCTAssertTrue(latest.label.hasPrefix("Jon vs Alex, Jon won 6–4, 6–3, 54 minutes, Singles"), "latest: \(latest.label)")
        // The tiles' badge, the latest session's and the trend section's; every tile also says "sample data".
        XCTAssertTrue(element(app, "home.tiles.sample").exists)
        XCTAssertTrue(element(app, "home.trend.sample").exists)
        XCTAssertGreaterThanOrEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Sample data")).count, 3)
    }

    @MainActor
    private func assertEmptyState(_ app: XCUIApplication) throws {
        XCTAssertTrue(element(app, "home.empty").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Your first session shows up here."].exists)
        XCTAssertTrue(app.buttons["home.empty.record"].exists)
        XCTAssertTrue(app.buttons["home.empty.import"].exists)
        XCTAssertFalse(element(app, "home.tiles").exists, "no zero-filled tiles")
        XCTAssertFalse(app.staticTexts["0"].exists)
        XCTAssertTrue(app.heading("Good morning.").exists, "no name without a session or profile")
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.waitForExistence(timeout: 10) else { return false }
        // Clear of the tab bar, not merely on screen: a tap under the bar lands on the bar.
        let tabBarTop = app.otherElements["tabBar"].frame.minY
        func isClear() -> Bool { element.isHittable && element.frame.maxY < tabBarTop - 8 }
        for _ in 0..<6 where !isClear() { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
        return isClear()
    }

    @MainActor
    private func launch(appearance: LaunchConfiguration.Appearance, demo: Bool = false, scenario: String? = nil,
                        contentSize: ContentSize? = nil) -> XCUIApplication {
        let app = XCUIApplication.jovra(contentSize: contentSize) {
            $0.appearance = appearance
            $0.library = .fresh
            if demo { $0.demo = .sample }
        }
        if let scenario { app.launchEnvironment["JOVRA_HOME_SCENARIO"] = scenario }
        app.launchEnvironment["JOVRA_HOME_NOW"] = Self.morningOfOctober6
        app.launch()
        return app
    }

    /// 08:30 on Oct 6, 2026 on this simulator's clock: morning, and the day the sample library's window ends.
    private static var morningOfOctober6: String {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 8, minute: 30))!
        return ISO8601DateFormatter().string(from: date)
    }
}

private extension XCUIElement {
    @MainActor
    func waitForSelection(timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isSelected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return isSelected
    }
}
