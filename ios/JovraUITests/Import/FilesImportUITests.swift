import XCTest

final class FilesImportUITests: XCTestCase {
    @MainActor
    func testLibraryOpensNativeFilesPickerAndCancellationDoesNotReportSuccess() throws {
        continueAfterFailure = false
        let app = XCUIApplication.launchJovra { $0.demo = .off }
        app.buttons["tab.sessions"].tap()
        app.buttons["library.import"].tap()
        let name = app.textFields["import.player"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let choose = app.buttons["import.choose"]
        XCTAssertFalse(choose.isEnabled)
        name.tap()
        name.typeText("Practice Player\n")
        XCTAssertTrue(choose.isEnabled)
        choose.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
        cancel.tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["import.saved"].exists)
        XCTAssertFalse(app.staticTexts["import.issue"].exists)
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.exists)
        back.tap()
        XCTAssertTrue(app.buttons["library.import"].waitForExistence(timeout: 5))
    }
}
