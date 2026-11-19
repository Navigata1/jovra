import XCTest

/// Bounded Capture controls only. The complete persisted recording-to-export gate is separate.
final class CaptureFlowUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testChosenFixtureCapturePausesMarksAndSavesWithoutAccountOrMicrophone() throws {
        let app = XCUIApplication.launchJovra { $0.demo = .off }
        app.buttons["tab.record"].tap()
        for (identifier, value) in [("capture.setup.title", "Court session"), ("capture.setup.playerA", "Jon"), ("capture.setup.playerB", "Alex")] {
            let field = app.textFields[identifier]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(value + "\n")
        }
        app.swipeUp()
        app.buttons["record.previewCapture"].tap()
        XCTAssertTrue(app.staticTexts["Simulator fixture camera"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["capture.sample"].exists)
        app.buttons["capture.start"].tap()
        XCTAssertTrue(app.staticTexts["capture.confirmedTime"].waitForExistence(timeout: 12))
        app.buttons["capture.markPoint"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Point marked · '")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["capture.pause"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.pausedBanner"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any)["capture.pausedBanner"].label, "Paused · Not recording")
        app.buttons["capture.resume"].tap()
        XCTAssertTrue(app.buttons["capture.pause"].waitForExistence(timeout: 10))
        app.buttons["capture.stop"].tap()
        let stop = app.buttons.matching(identifier: "capture.confirmStop").firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        XCTAssertTrue(app.staticTexts["capture.saved"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.textFields["account.email"].exists)
        attachScreenshot(app, name: "capture-fixture-saved")
        try auditScreen(app)
        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.buttons["tab.record"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testUnsupportedDoublesDeepLinkDoesNotBecomeSingles() throws {
        let app = XCUIApplication.launchJovra { $0.demo = .off }
        app.open(try XCTUnwrap(URL(string: "jovra://record/doubles")))
        XCTAssertTrue(app.staticTexts["capture.kind"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["capture.kind"].label.contains("Doubles match"))
        XCTAssertFalse(app.buttons["capture.start"].exists)
        app.buttons["capture.close"].tap()
    }

    @MainActor
    func testSetupAndUnsupportedModeAreAccessibleAtAX5() throws {
        let app = XCUIApplication.launchJovra(contentSize: .accessibility5) {
            $0.demo = .off; $0.startRoute = "capture"
        }
        XCTAssertTrue(app.staticTexts["capture.kind"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "capture-setup-ax5")
        assertHitTargets(in: app)
        try auditScreen(app)
        // T17: without a setup the route opens with a default singles draft; its details are edited in a sheet.
        let edit = app.buttons["capture.editDetails"]
        for _ in 0..<6 where !(edit.exists && edit.isHittable) { app.swipeUp() }
        edit.tap()
        XCTAssertTrue(app.textFields["capture.setup.title"].waitForExistence(timeout: 5))
        let noAd = app.descendants(matching: .any).matching(identifier: "capture.setup.noAd").firstMatch
        for _ in 0..<5 {
            if noAd.exists && noAd.isHittable { break }
            app.swipeUp()
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "capture-no-ad-native-semantics"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTAssertTrue(noAd.exists && noAd.isHittable)
        assertNoAd(noAd, isOn: false)
        noAd.tap()
        assertNoAd(noAd, isOn: true)
        noAd.tap()
        assertNoAd(noAd, isOn: false)
        app.swipeUp()
        attachScreenshot(app, name: "capture-setup-ax5-lower")
        assertHitTargets(in: app)
        try auditScreen(app)
        app.buttons["capture.details.done"].tap()
        app.open(try XCTUnwrap(URL(string: "jovra://record/doubles")))
        XCTAssertTrue(app.staticTexts["capture.kind"].label.contains("Doubles match"))
        attachScreenshot(app, name: "capture-unsupported-ax5")
        try auditScreen(app)
    }

    @MainActor
    func testSetupIsAccessibleInLightPresentationAtDefaultSize() throws {
        let app = XCUIApplication.launchJovra {
            $0.appearance = .light; $0.demo = .off; $0.startRoute = "capture"
        }
        XCTAssertTrue(app.staticTexts["capture.kind"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["capture.start"].waitForExistence(timeout: 15))
        attachScreenshot(app, name: "capture-setup-light-presentation")
        XCTAssertEqual(app.staticTexts["capture.draft.title"].label, "Singles match", "T17: no setup opens the default singles draft")
        assertHitTargets(in: app)
        try auditScreen(app)
        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.otherElements["tabBar"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCaptureCloseIsHittableAtAX5AndReturnsToTabs() throws {
        let app = XCUIApplication.launchJovra(contentSize: .accessibility5) {
            $0.demo = .off; $0.startRoute = "capture"
        }
        XCTAssertTrue(app.staticTexts["capture.kind"].waitForExistence(timeout: 5))
        let close = app.buttons["capture.close"]
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "capture-ax5-close-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        attachScreenshot(app, name: "capture-ax5-close")
        XCTAssertTrue(close.exists)
        XCTAssertTrue(close.isHittable, "The fixed exit must remain reachable at AX5")
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        close.tap()
        XCTAssertTrue(app.otherElements["tabBar"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertNoAd(_ element: XCUIElement, isOn: Bool, file: StaticString = #filePath, line: UInt = #line) {
        if element.elementType == .switch {
            XCTAssertEqual(element.value as? String, isOn ? "1" : "0", file: file, line: line)
        } else {
            XCTAssertEqual(element.elementType, .button, "unexpected native Toggle accessibility role", file: file, line: line)
            XCTAssertEqual(element.isSelected, isOn, file: file, line: line)
        }
    }
}
