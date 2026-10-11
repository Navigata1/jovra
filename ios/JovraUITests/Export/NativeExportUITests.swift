import XCTest

final class NativeExportUITests: XCTestCase {
    @MainActor
    func testExistingExportRouteShowsRealRangeControlsAndRefusesMissingSession() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launchJovra { $0.startRoute = "sheet.clipExport" }
        XCTAssertTrue(app.textFields["export.from"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["export.to"].exists)
        let export = app.buttons["export.create"]
        XCTAssertTrue(export.exists)
        XCTAssertFalse(export.isEnabled)
        XCTAssertFalse(app.buttons["export.share"].exists)
        XCTAssertFalse(app.staticTexts["export.done"].exists)
        attachScreenshot(app, name: "export-missing-session")
        assertHitTargets(in: app)
        try auditScreen(app)
    }
}
