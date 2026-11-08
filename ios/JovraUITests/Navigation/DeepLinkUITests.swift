import XCTest

/// T07: the `jovra://` deep links App Intents use, opened in the running app by the system.
final class DeepLinkUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testStartSinglesRecordingOpensCaptureForSingles() throws {
        let app = XCUIApplication.launchJovra { $0.appearance = .light }
        XCTAssertTrue(app.heading("Home").waitForExistence(timeout: 8))

        app.open(try XCTUnwrap(URL(string: "jovra://record/singles")))

        XCTAssertTrue(app.heading("Capture").waitForExistence(timeout: 8), "the capture route is presented")
        let payload = app.staticTexts["capture.kind"]
        XCTAssertEqual(payload.label, "Singles match", "the actual setup keeps the selected kind")
        XCTAssertFalse(app.otherElements["tabBar"].exists)
        attachScreenshot(app, name: "t07-light-deep-link-start-singles")

        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.buttons["tab.record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.record"].isSelected, "the link opened capture from the Record tab")
    }

    /// No session store exists yet (T08/T20), so there is no real match: the link opens the library.
    /// The newest-real-match rule is covered by AppRouterTests against a fixed library.
    @MainActor
    func testShowLastMatchWithAnEmptyLibraryOpensTheLibrary() throws {
        let app = XCUIApplication.launchJovra {
            $0.appearance = .light
            $0.startRoute = "replay"
        }
        XCTAssertTrue(app.heading("Smart replay").waitForExistence(timeout: 8))

        app.open(try XCTUnwrap(URL(string: "jovra://sessions/last-match")))

        XCTAssertTrue(app.heading("Your sessions").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["tab.sessions"].isSelected)
    }
}
