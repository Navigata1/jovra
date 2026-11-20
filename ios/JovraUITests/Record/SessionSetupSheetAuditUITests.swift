import XCTest

/// T21 acceptance 9 for the sheets: `performAccessibilityAudit` (textClipped included) passes on every
/// setup sheet (players for singles and for doubles, match format, camera preset) at every scroll
/// position, in light, dark and AX5. One test per sheet and variant keeps each run bounded.
///
/// Position k puts the sheet's title k half-heights above where it rests, so consecutive positions
/// overlap by half the visible height and every element shorter than that is audited whole at least once.
/// The sheet is moved by drags that hold before lifting (no fling) and audited once scrolling settles;
/// because the audit can scroll the content itself, each position is reached again from wherever the last
/// audit left it. An element partly scrolled out of the sheet's scroll view is set aside at that position
/// (it is judged where it is whole). The test fails unless it reaches the end with Done wholly on screen,
/// and it attaches the list of audited positions (`audit-positions-<variant>-<sheet>`).
final class SessionSetupSheetAuditUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// More than any setup sheet needs at AX5 (the format sheet's ten presets take about twenty).
    static let maximumSteps = 40
    /// How close a position must land to its target; consecutive positions still overlap by about half
    /// the visible height.
    static let tolerance: CGFloat = 24

    enum Sheet: String {
        case players, playersDoubles = "players-doubles", format, camera
    }

    enum Variant: String {
        case light, dark, ax5
    }

    // MARK: Light

    @MainActor func testPlayersSheetPassesTheAuditAtEveryScrollPositionInLight() throws { try audit(.players, .light) }
    @MainActor func testDoublesPlayersSheetPassesTheAuditAtEveryScrollPositionInLight() throws { try audit(.playersDoubles, .light) }
    @MainActor func testFormatSheetPassesTheAuditAtEveryScrollPositionInLight() throws { try audit(.format, .light) }
    @MainActor func testCameraSheetPassesTheAuditAtEveryScrollPositionInLight() throws { try audit(.camera, .light) }

    // MARK: Dark

    @MainActor func testPlayersSheetPassesTheAuditAtEveryScrollPositionInDark() throws { try audit(.players, .dark) }
    @MainActor func testDoublesPlayersSheetPassesTheAuditAtEveryScrollPositionInDark() throws { try audit(.playersDoubles, .dark) }
    @MainActor func testFormatSheetPassesTheAuditAtEveryScrollPositionInDark() throws { try audit(.format, .dark) }
    @MainActor func testCameraSheetPassesTheAuditAtEveryScrollPositionInDark() throws { try audit(.camera, .dark) }

    // MARK: AX5

    @MainActor func testPlayersSheetPassesTheAuditAtEveryScrollPositionAtAX5() throws { try audit(.players, .ax5) }
    @MainActor func testDoublesPlayersSheetPassesTheAuditAtEveryScrollPositionAtAX5() throws { try audit(.playersDoubles, .ax5) }
    @MainActor func testFormatSheetPassesTheAuditAtEveryScrollPositionAtAX5() throws { try audit(.format, .ax5) }
    @MainActor func testCameraSheetPassesTheAuditAtEveryScrollPositionAtAX5() throws { try audit(.camera, .ax5) }

    // MARK: Driving

    @MainActor
    private func audit(_ sheet: Sheet, _ variant: Variant) throws {
        let app = XCUIApplication.jovra(contentSize: variant == .ax5 ? .accessibility5 : nil) {
            $0.appearance = variant == .dark ? .dark : .light
            $0.demo = .off
            $0.startRoute = "record"
        }
        app.launch()
        XCTAssertTrue(app.heading("Set up your session").waitForExistence(timeout: 8))
        open(sheet, app)
        let container = app.otherElements["sheet.container"]
        XCTAssertTrue(container.waitForExistence(timeout: 5))
        let scroll = container.scrollViews["setupSheet.scroll"]
        XCTAssertTrue(scroll.exists, "setup sheets scroll in setupSheet.scroll")
        let title = scroll.staticTexts["screen.title"]
        attachScreenshot(app, name: "t21-\(variant.rawValue)-sheet-\(sheet.rawValue)")
        assertHitTargets(in: app)

        // Position k puts the title k half-heights above its resting place. The audit may scroll the
        // content itself, so every position is reached from wherever the last audit left it. The end is
        // the first position the content cannot reach (or where Done, the last control, is whole).
        let done = scroll.buttons["sheet.done"]
        let top = title.frame.minY
        let stride = (scroll.frame.height / 2).rounded()
        var positions: [String] = []
        for step in 1...Self.maximumSteps {
            let target = top - CGFloat(step - 1) * stride
            let reached = scrollTitle(to: target, in: scroll, marker: title)
            let before = title.frame.minY
            let atEnd = isWhole(done, in: scroll) || !reached
            try auditPosition(app, sheet: container, scroll: scroll, marker: title)
            positions.append("position \(step): title y \(Int(target)) wanted, \(Int(before)) audited\(atEnd ? " (end)" : "")")
            guard atEnd else { continue }
            // The last position: Done scrolled wholly into view the way a player scrolls, and audited there.
            app.reveal(done, in: scroll)
            waitForScrollingToSettle(title)
            if Int(title.frame.minY) != Int(before) {
                let last = title.frame.minY
                try auditPosition(app, sheet: container, scroll: scroll, marker: title)
                positions.append("position \(step + 1): title y \(Int(last)) audited, Done wholly in view (end)")
            }
            attachScreenshot(app, name: "t21-\(variant.rawValue)-sheet-\(sheet.rawValue)-end")
            attachPositions(positions, sheet, variant, reachedEnd: true)
            XCTAssertTrue(isWhole(done, in: scroll), "at the end of the \(sheet.rawValue) sheet Done is wholly on screen: \(done.frame) in \(scroll.frame)")
            return
        }
        attachPositions(positions, sheet, variant, reachedEnd: false)
        XCTFail("the \(sheet.rawValue) sheet did not reach its end in \(Self.maximumSteps) positions")
    }

    @MainActor
    private func isWhole(_ element: XCUIElement, in scroll: XCUIElement) -> Bool {
        let visible = scroll.frame
        return element.exists && element.frame.minY >= visible.minY - 1 && element.frame.maxY <= visible.maxY + 1
    }

    private func attachPositions(_ positions: [String], _ sheet: Sheet, _ variant: Variant, reachedEnd: Bool) {
        let heading = "\(sheet.rawValue) sheet, \(variant.rawValue): audited at \(positions.count) scroll positions"
            + (reachedEnd ? ", top to end" : ", end not reached")
        let attachment = XCTAttachment(string: ([heading] + positions).joined(separator: "\n"))
        attachment.name = "audit-positions-\(variant.rawValue)-\(sheet.rawValue)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("audit: " + heading)
    }

    /// Presents the sheet at its top, with names filled in as a player would see it. The players sheet is
    /// filled, closed and opened again: swiping a sheet back to its top would pull it down and close it.
    @MainActor
    private func open(_ sheet: Sheet, _ app: XCUIApplication) {
        switch sheet {
        case .players, .playersDoubles:
            if sheet == .players {
                app.buttons["record.mode.singlesMatch"].tap()
                app.fillPlayers(["me": "Jon", "opponent": "Alex"])
            } else {
                app.buttons["record.mode.doublesMatch"].tap()
                app.fillPlayers(["me": "Jon", "partner": "Sam", "opponent": "Alex", "opponentPartner": "Lee"])
            }
            app.finishSheet()
            let row = app.buttons["record.players"]
            app.reveal(row)
            row.tap()
        case .format:
            let row = app.buttons["record.scoring"]
            app.reveal(row)
            row.tap()
        case .camera:
            let row = app.buttons["record.camera"]
            app.reveal(row)
            row.tap()
        }
        Thread.sleep(forTimeInterval: 1.2) // the presentation animation ends before pixels are sampled
    }

    /// Drags the content until the title's top is within `tolerance` of `target` (a drag shorter than the
    /// touch slop does not scroll, so positions land within about 10 pt), never more than half the
    /// visible height at a time and holding before lifting, so nothing flings. A drag starts in the right
    /// margin (no control sits there), then the left margin, then the middle. False when the content
    /// stops short of the target: the sheet's end.
    @discardableResult @MainActor
    private func scrollTitle(to target: CGFloat, in scroll: XCUIElement, marker: XCUIElement) -> Bool {
        let height = scroll.frame.height
        for _ in 0..<12 {
            let delta = marker.frame.minY - target // > 0: move the content up
            if abs(delta) <= Self.tolerance { return true }
            let distance = min(abs(delta), height / 2) / height
            var moved = false
            for x in [0.97, 0.03, 0.5] {
                let before = marker.frame.minY
                let from = delta > 0 ? 0.75 : 0.25
                let to = delta > 0 ? from - distance : from + distance
                scroll.coordinate(withNormalizedOffset: CGVector(dx: x, dy: from))
                    .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: x, dy: to)),
                           withVelocity: .slow, thenHoldForDuration: 0.4)
                waitForScrollingToSettle(marker)
                if abs(marker.frame.minY - before) > 1 { moved = true; break }
            }
            if !moved { return false }
        }
        return abs(marker.frame.minY - target) <= Self.tolerance
    }

    /// One audit at the settled position. Every issue on an element wholly inside the scroll view, or in
    /// the sheet's fixed header, fails. Set aside, and logged: elements behind the sheet (the setup
    /// screen has its own audit), elements the scroll view clips at this position (judged where they are
    /// whole), and a rendered issue (contrast, element detection) found after the audit itself scrolled
    /// the content, which is sampled again once scrolling has settled.
    @MainActor
    private func auditPosition(_ app: XCUIApplication, sheet: XCUIElement, scroll: XCUIElement, marker: XCUIElement,
                               isRepeat: Bool = false) throws {
        let sheetFrame = sheet.frame.insetBy(dx: -1, dy: -1)
        let visible = scroll.frame.insetBy(dx: -1, dy: -1)
        let markerY = marker.frame.minY
        var moved: [String] = []
        try performAuditAllowingTimeouts(app) { issue in
            guard let element = issue.element else { return false }
            let frame = element.frame
            let kind = AccessibilityAudit.name(of: issue.auditType)
            guard sheetFrame.contains(frame) else {
                print("audit: \(kind) on “\(element.label)” at \(frame) set aside: behind the sheet")
                return true
            }
            if visible.intersects(frame), !visible.contains(frame) {
                print("audit: \(kind) on “\(element.label)” at \(frame) set aside: clipped by the scroll view at this position")
                return true
            }
            let isRendered = issue.auditType == .contrast || issue.auditType == .elementDetection
            if isRendered, !isRepeat, abs(marker.frame.minY - markerY) > 1 {
                print("audit: \(kind) on “\(element.label)” at \(frame) set aside: the audit moved the sheet by \(marker.frame.minY - markerY) pt")
                moved.append(element.label)
                return true
            }
            return false
        }
        guard !moved.isEmpty else { return }
        waitForScrollingToSettle(marker)
        print("audit: repeating at the settled position for \(moved)")
        try auditPosition(app, sheet: sheet, scroll: scroll, marker: marker, isRepeat: true)
    }

    /// XCTest code -56 means the audit did not finish in its time limit on a loaded machine; it reported
    /// nothing either way. Only that error is retried, up to twice, after a pause; any issue still fails.
    static let auditAttempts = 3

    @MainActor
    private func performAuditAllowingTimeouts(_ app: XCUIApplication,
                                              _ handler: @escaping (XCUIAccessibilityAuditIssue) throws -> Bool) throws {
        for attempt in 1...Self.auditAttempts {
            do {
                try app.performAccessibilityAudit(for: .all, handler)
                return
            } catch let error as NSError where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56
                && attempt < Self.auditAttempts {
                print("audit: did not complete in time (-56), attempt \(attempt); auditing this position again")
                Thread.sleep(forTimeInterval: 10)
            }
        }
    }
}
