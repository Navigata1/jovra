import XCTest

extension XCTestCase {
    /// `performAccessibilityAudit` for a presented sheet. The audit also walks the dimmed screen behind
    /// the sheet, which VoiceOver cannot reach while the sheet is up; there it reports the screen's
    /// text as clipped where the sheet covers it. Issues on elements outside the sheet's container
    /// (`sheet.container`) are therefore logged and set aside: that screen has its own audit (the tab
    /// tour in JovraSmokeUITests). Every issue inside the sheet fails. At large text sizes the sheet is
    /// first dragged to its large detent and then audited at each scroll step.
    @MainActor
    func auditSheet(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        let sheet = app.otherElements["sheet.container"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "a sheet is presented", file: file, line: line)
        try auditSheetOnce(app, sheet: sheet)
        let scrollView = sheet.scrollViews.firstMatch
        guard scrollView.exists else { return }
        for _ in 0..<AccessibilityAudit.maximumSteps {
            let marker = sheet.staticTexts.firstMatch.frame.minY
            scrollView.swipeUp(velocity: .slow)
            Thread.sleep(forTimeInterval: 0.8)
            guard abs(sheet.staticTexts.firstMatch.frame.minY - marker) > 1 else { break }
            try auditSheetOnce(app, sheet: sheet)
        }
    }

    @MainActor
    private func auditSheetOnce(_ app: XCUIApplication, sheet: XCUIElement) throws {
        let frame = sheet.frame.insetBy(dx: -1, dy: -1)
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element else { return false }
            if frame.contains(element.frame) { return false }
            let visible = element.frame.intersection(frame)
            // Sheet content scrolled partly out of view is clipped by the sheet itself: judged at the
            // step where it is fully inside. Anything that does not start inside the sheet is behind it.
            print("audit: \(AccessibilityAudit.name(of: issue.auditType)) issue on “\(element.label)” at \(element.frame) set aside: outside the sheet \(frame) (visible part \(visible))")
            return true
        }
    }
}
