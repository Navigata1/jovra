import XCTest

/// Persisted native Library handoff only; scoring and exports use the separate CoreFlow gate.
final class NativeLibraryUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testSavedFixtureRemainsInLibraryAfterRelaunchAndOpensReplay() throws {
        let title = "Library " + String(UUID().uuidString.prefix(8))
        let app = XCUIApplication.launchJovra { $0.demo = .off }
        app.buttons["tab.record"].tap()
        for (id, value) in [("capture.setup.title", String(title)), ("capture.setup.playerA", "Jon"), ("capture.setup.playerB", "Alex")] {
            let field = app.textFields[id]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(value + "\n")
        }
        app.swipeUp(); app.buttons["record.previewCapture"].tap()
        XCTAssertTrue(app.staticTexts["capture.sample"].waitForExistence(timeout: 10))
        app.buttons["capture.start"].tap()
        XCTAssertTrue(app.staticTexts["capture.confirmedTime"].waitForExistence(timeout: 12))
        app.buttons["capture.stop"].tap()
        app.buttons.matching(identifier: "capture.confirmStop").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["capture.saved"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["capture.openLibrary"].waitForExistence(timeout: 5))
        app.buttons["capture.openLibrary"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.session.' AND label CONTAINS %@", title)).firstMatch.waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        app.buttons["tab.sessions"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.session.' AND label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Sample"))
        app.buttons["Practice"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), "A saved match must not remain in the Practice filter")
        app.buttons["Matches"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        app.buttons["All"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "library-persisted-fixture")
        assertHitTargets(in: app)
        try auditScreen(app)
        row.tap()
        XCTAssertTrue(app.heading("Smart replay").waitForExistence(timeout: 5))
    }

    @MainActor
    func testRealStoredLibraryIsAccessibleAtAX5() throws {
        let app = XCUIApplication.launchJovra(contentSize: .accessibility5) {
            $0.demo = .off; $0.startRoute = "sessions"
        }
        XCTAssertTrue(app.heading("Your sessions").waitForExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.session.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Use a real fixture session retained by the recording flow")
        attachScreenshot(app, name: "library-stored-ax5")
        assertHitTargets(in: app)
        try auditScreen(app)
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<4 {
            if row.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(app.heading("Smart replay").waitForExistence(timeout: 5))
    }
}
