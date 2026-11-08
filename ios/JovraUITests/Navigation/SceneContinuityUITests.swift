import XCTest

/// Checks scene continuity through background/foreground. Process-death restoration is checked
/// outside XCTest: launches by this harness do not preserve SceneStorage on the tested simulator.
final class SceneContinuityUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBackgroundedSceneRetainsCapturePayloadAndPresentingTab() throws {
        let app = XCUIApplication()
        app.launchArguments = [] // No JOVRA launch overrides; the route is opened explicitly below.
        app.launch()
        // Reset the route through a known system deep link regardless of any earlier scene state.
        app.open(try XCTUnwrap(URL(string: "jovra://record/doubles")))
        XCTAssertTrue(app.heading("Capture").waitForExistence(timeout: 8))
        let payload = app.staticTexts["capture.kind"]
        XCTAssertEqual(payload.label, "Doubles match")
        attachScreenshot(app, name: "t07-scene-continuity-before-background")

        XCUIDevice.shared.press(.home)
        let backgrounded = app.wait(for: .runningBackground, timeout: 3) || app.state == .runningBackgroundSuspended
        XCTAssertTrue(backgrounded)
        // Let the scene background fully before activating the same running app.
        Thread.sleep(forTimeInterval: 3)
        app.activate()

        XCTAssertTrue(app.heading("Capture").waitForExistence(timeout: 8), "the full-screen route survives backgrounding")
        XCTAssertEqual(payload.label, "Doubles match", "the actual mode survives backgrounding")
        XCTAssertFalse(app.otherElements["tabBar"].exists)
        attachScreenshot(app, name: "t07-scene-continuity-after-foreground")
        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.buttons["tab.record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.record"].isSelected, "closing returns to the presenting tab")
    }
}
