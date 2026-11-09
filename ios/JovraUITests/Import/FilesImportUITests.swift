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
        try auditScreen(app)
        choose.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
        cancel.tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["import.saved"].exists)
        XCTAssertFalse(app.staticTexts["import.issue"].exists)
        let back = app.buttons["import.back"]
        XCTAssertTrue(back.exists)
        back.tap()
        XCTAssertTrue(app.buttons["library.import"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSinglesMatchRequiresExplicitSetupAndFullFootageConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication.launchJovra { $0.demo = .off }
        app.buttons["tab.sessions"].tap()
        app.buttons["library.import"].tap()
        let practice = app.textFields["import.player"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5))
        app.buttons["Singles match"].tap()
        let choose = app.buttons["import.choose"]
        XCTAssertFalse(practice.exists)
        XCTAssertFalse(choose.isEnabled)
        for (id, name) in [("import.match.playerA", "Player A"), ("import.match.playerB", "Player B")] {
            let field = app.textFields[id]
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(name + "\n")
        }
        for (id, option) in [("import.match.format", "Best of one set"), ("import.match.scoring", "No-ad"),
                             ("import.match.firstServer", "Player B"), ("import.match.nearPlayer", "Player A")] {
            let picker = app.buttons[id]
            for _ in 0..<4 where !picker.isHittable { app.swipeUp() }
            XCTAssertTrue(picker.isHittable)
            picker.tap(); app.buttons[option].tap()
        }
        let complete = app.switches["import.match.complete"]
        for _ in 0..<4 where !complete.isHittable { app.swipeUp() }
        XCTAssertTrue(complete.isHittable)
        XCTAssertFalse(choose.isEnabled, "A scored match requires confirmation of complete footage")
        complete.tap()
        XCTAssertTrue(choose.isEnabled)
    }
}
