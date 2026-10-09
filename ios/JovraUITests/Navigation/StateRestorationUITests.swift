import XCTest

/// Independently exercises scene storage across a backgrounded process restart. The test never
/// discards the scene through the app switcher: iOS intentionally removes that scene's saved state.
final class StateRestorationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBackgroundedSceneRestoresCapturePayloadAndPresentingTab() throws {
        let app = XCUIApplication()
        app.launchArguments = [] // A real launch, because harness launches intentionally skip restore.
        app.launch()
        // Reset the route through a known system deep link regardless of any earlier scene state.
        app.open(try XCTUnwrap(URL(string: "jovra://record/doubles")))
        XCTAssertTrue(app.heading("Capture").waitForExistence(timeout: 8))
        let payload = app.descendants(matching: .any).matching(identifier: "placeholder.payload").firstMatch
        XCTAssertTrue(payload.label.contains("Session kind: Doubles match"))
        attachScreenshot(app, name: "t07-restoration-before-background")

        XCUIDevice.shared.press(.home)
        let backgrounded = app.wait(for: .runningBackground, timeout: 3) || app.state == .runningBackgroundSuspended
        XCTAssertTrue(backgrounded)
        // Allow the scene's asynchronous preservation to finish before ending the process.
        Thread.sleep(forTimeInterval: 3)
        app.terminate()
        app.launch()

        XCTAssertTrue(app.heading("Capture").waitForExistence(timeout: 8), "the full-screen route restores")
        XCTAssertTrue(payload.label.contains("Session kind: Doubles match"), "the typed payload restores")
        XCTAssertFalse(app.otherElements["tabBar"].exists)
        attachScreenshot(app, name: "t07-restoration-after-relaunch")
        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.buttons["tab.record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.record"].isSelected, "closing returns to the restored presenting tab")
    }
}
