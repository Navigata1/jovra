import XCTest

/// Drives session setup (S04, T21) the way a player does: the Record tab, the players sheet, and
/// "Check camera position". Flows that only need a recording to start use `startSinglesCapture`.
extension XCUIApplication {
    /// Scrolls `scrollView` (the screen's own by default) until `element` can be tapped.
    @MainActor
    func reveal(_ element: XCUIElement, in scrollView: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let scroller = scrollView ?? scrollViews.firstMatch
        // On a tab screen the content stops at the tab bar: an element under it is "hittable" but a tap
        // lands on the bar, so it counts as reachable only once it is wholly above the bar.
        let tabBar = otherElements["tabBar"]
        func reachable() -> Bool {
            guard element.exists, element.isHittable else { return false }
            let bottom = scrollView == nil && tabBar.exists ? tabBar.frame.minY : frame.maxY
            return element.frame.maxY <= bottom
        }
        for _ in 0..<12 where !reachable() {
            // Above the visible part (the page was scrolled past it): scroll back up instead.
            if element.exists, element.frame.maxY < scroller.frame.minY + 60 {
                scroller.swipeDown(velocity: .slow)
            } else {
                scroller.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(reachable(), "\(element) can be reached", file: file, line: line)
    }

    /// Replaces a text field's contents (the remembered setup may already hold a name).
    @MainActor
    func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        let placeholder = field.placeholderValue ?? ""
        let deletes = current == placeholder ? 0 : current.count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: deletes) + text + "\n")
    }

    /// Opens the players sheet from the Record tab and fills the names in play; returns with the sheet open.
    @MainActor
    func fillPlayers(_ names: [String: String], sessionName: String? = nil) {
        let row = buttons["record.players"]
        reveal(row)
        row.tap()
        let sheet = otherElements["sheet.container"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        for seat in ["me", "partner", "opponent", "opponentPartner"] {
            guard let name = names[seat] else { continue }
            let field = textFields["players.\(seat).name"]
            reveal(field, in: sheet.scrollViews.firstMatch)
            replaceText(in: field, with: name)
        }
        if let sessionName {
            let field = textFields["players.sessionName"]
            reveal(field, in: sheet.scrollViews.firstMatch)
            replaceText(in: field, with: sessionName)
        }
    }

    /// Closes the open setup sheet with Done.
    @MainActor
    func finishSheet() {
        let sheet = otherElements["sheet.container"]
        let done = buttons["sheet.done"]
        reveal(done, in: sheet.scrollViews.firstMatch)
        done.tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
    }

    /// Record tab → Singles match → names → "Check camera position": the capture route opens with that setup.
    @MainActor
    func startSinglesCapture(sessionName: String, me: String = "Jon", opponent: String = "Alex") {
        buttons["tab.record"].tap()
        let singles = buttons["record.mode.singlesMatch"]
        XCTAssertTrue(singles.waitForExistence(timeout: 5))
        singles.tap()
        fillPlayers(["me": me, "opponent": opponent], sessionName: sessionName)
        finishSheet()
        let check = buttons["record.checkCameraPosition"]
        reveal(check)
        check.tap()
    }
}
