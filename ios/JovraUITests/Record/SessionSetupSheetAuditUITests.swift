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
    /// An audit issue fails the test with its element, frame and position (`XCTFail` from the audit's
    /// handler), and the audit carries on so every issue at that position is reported.
    override func setUp() { continueAfterFailure = true }

    /// A swipe that reaches the end bounces; the frames settle before the pixels do.
    static let bounceSettle: TimeInterval = 3

    /// Element-detection issues with no element set aside at positions where the edge cut an element.
    private var setAsideWithoutElement = 0

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
        // content itself, so every position is reached from wherever the last audit left it. Once the
        // next position would take Done, the last control, above the bottom edge, the last position is
        // instead the end itself: Done scrolled into view the way a player scrolls (a drag past the end
        // would leave the content overscrolled while it is audited).
        let done = scroll.buttons["sheet.done"]
        let top = title.frame.minY
        let stride = (scroll.frame.height / 2).rounded()
        var positions: [String] = []
        for step in 1...Self.maximumSteps {
            let target = top - CGFloat(step - 1) * stride
            let move = title.frame.minY - target
            let isLast = isWhole(done, in: scroll) || move >= done.frame.maxY - scroll.frame.maxY
            if isLast {
                // Done scrolled into view the way a player scrolls (a held drag past the end can leave the
                // content mid-bounce, and the audit then never sees it idle), then the bounce settles.
                app.reveal(done, in: scroll)
                waitForScrollingToSettle(title)
                Thread.sleep(forTimeInterval: Self.bounceSettle)
            } else {
                XCTAssertTrue(scrollTitle(to: target, in: scroll, marker: title), "the \(sheet.rawValue) sheet scrolls to position \(step)")
            }
            let audited = title.frame.minY
            let doneIsWhole = isWhole(done, in: scroll)
            let doneFrame = done.frame
            if isLast { attachScreenshot(app, name: "t21-\(variant.rawValue)-sheet-\(sheet.rawValue)-end") }
            positions.append(isLast ? "position \(step): title y \(Int(audited)), the end, Done \(doneFrame.integral)"
                                    : "position \(step): title y \(Int(target)) wanted, \(Int(audited)) audited")
            do {
                try auditPosition(app, sheet: container, scroll: scroll, marker: title)
            } catch let error as NSError where Self.isTimeout(error) && !isLast {
                // The audit did not finish here, so this position is audited a little further on instead;
                // it still overlaps both neighbours by more than a third of the visible height.
                let further = target - Self.timeoutNudge
                XCTAssertTrue(scrollTitle(to: further, in: scroll, marker: title), "the \(sheet.rawValue) sheet scrolls past position \(step)")
                positions[positions.count - 1] = "position \(step): title y \(Int(target)) wanted, the audit did not finish there in time; audited instead at \(Int(title.frame.minY))"
                do {
                    try auditPosition(app, sheet: container, scroll: scroll, marker: title)
                } catch {
                    attachPositions(positions, sheet, variant, reachedEnd: false)
                    throw error
                }
            } catch {
                attachPositions(positions, sheet, variant, reachedEnd: false)
                throw error
            }
            guard isLast else { continue }
            positions.append("element-detection issues with no element set aside where the edge cut an element: \(setAsideWithoutElement)")
            attachPositions(positions, sheet, variant, reachedEnd: true)
            XCTAssertTrue(doneIsWhole, "at the end of the \(sheet.rawValue) sheet Done is wholly on screen: \(doneFrame) in \(scroll.frame)")
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
        let heading = "\(sheet.rawValue) sheet, \(variant.rawValue): audited at \(positions.filter { $0.hasPrefix("position") }.count) scroll positions"
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
    /// margin (no control sits there), then just inside it, then the middle (never at the left edge,
    /// where a drag is a system edge gesture). False when the content
    /// stops short of the target: the sheet's end.
    @discardableResult @MainActor
    private func scrollTitle(to target: CGFloat, in scroll: XCUIElement, marker: XCUIElement) -> Bool {
        let height = scroll.frame.height
        for _ in 0..<12 {
            let delta = marker.frame.minY - target // > 0: move the content up
            if abs(delta) <= Self.tolerance { return true }
            let distance = min(abs(delta), height / 2) / height
            var moved = false
            for x in [0.97, 0.9, 0.5] {
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
    ///
    /// Element detection can also report text with no element at all, so with no frame to judge. Glyphs
    /// the scroll view's edge cuts in half look like that. Such an issue is set aside only while some
    /// text, field or button is cut by the scroll view's edge at this position; that element is audited
    /// whole at a neighbouring position. Anywhere else it fails.
    @MainActor
    private func auditPosition(_ app: XCUIApplication, sheet: XCUIElement, scroll: XCUIElement, marker: XCUIElement,
                               isRepeat: Bool = false) throws {
        let sheetFrame = sheet.frame.insetBy(dx: -1, dy: -1)
        let visible = scroll.frame.insetBy(dx: -1, dy: -1)
        let markerY = marker.frame.minY
        let cut = elementsCut(by: visible, in: scroll)
        var moved: [String] = []
        // One call per audit type (`auditPasses`); together they are `.all`.
        for types in Self.auditPasses {
            try performAuditAllowingTimeouts(app, types: types) { issue in
                let kind = AccessibilityAudit.name(of: issue.auditType)
                guard let element = issue.element else {
                    if issue.auditType == .elementDetection, !cut.isEmpty {
                        print("audit: element detection with no element at title y \(markerY) set aside: the edge cuts \(cut)")
                        self.setAsideWithoutElement += 1
                    } else {
                        XCTFail("\(kind) with no element, title y \(markerY), nothing cut by the edge: \(issue.compactDescription)")
                        let tree = XCTAttachment(string: sheet.debugDescription)
                        tree.name = "audit-tree-at-issue"
                        tree.lifetime = .keepAlways
                        self.add(tree)
                    }
                    return true
                }
                let frame = element.frame
                guard sheetFrame.contains(frame) else {
                    print("audit: \(kind) on “\(element.label)” at \(frame) set aside: behind the sheet")
                    return true
                }
                if visible.intersects(frame), !visible.contains(frame) {
                    print("audit: \(kind) on “\(element.label)” at \(frame) set aside: clipped by the scroll view at this position")
                    return true
                }
                if !visible.intersects(frame), element.identifier != "sheet.close" {
                    print("audit: \(kind) on “\(element.label)” at \(frame) set aside: scrolled out of view at this position")
                    return true
                }
                let isRendered = issue.auditType == .contrast || issue.auditType == .elementDetection
                if isRendered, !isRepeat, abs(marker.frame.minY - markerY) > 1 {
                    print("audit: \(kind) on “\(element.label)” at \(frame) set aside: the audit moved the sheet by \(marker.frame.minY - markerY) pt")
                    moved.append(element.label)
                    return true
                }
                XCTFail("\(kind) on “\(element.label)” (\(element.identifier)) at \(frame); title y \(markerY) when the audit began, \(marker.frame.minY) now; scroll view \(visible): \(issue.compactDescription)")
                return true
            }
        }
        guard !moved.isEmpty else { return }
        waitForScrollingToSettle(marker)
        print("audit: repeating at the settled position for \(moved)")
        try auditPosition(app, sheet: sheet, scroll: scroll, marker: marker, isRepeat: true)
    }

    /// Labels of the texts, fields and buttons the scroll view's edge cuts at this position.
    @MainActor
    private func elementsCut(by visible: CGRect, in scroll: XCUIElement) -> [String] {
        [scroll.staticTexts, scroll.textFields, scroll.buttons].flatMap { query in
            query.allElementsBoundByIndex.compactMap { element -> String? in
                let frame = element.frame
                return visible.intersects(frame) && !visible.contains(frame) ? element.label : nil
            }
        }
    }

    /// XCTest code -56 means the audit did not finish in its time limit; it reported nothing either way.
    /// Only that error is retried, once, after a pause; any issue still fails.
    static let auditAttempts = 2
    /// How much further on a position is audited when the audit cannot finish at it.
    static let timeoutNudge: CGFloat = 120

    static func isTimeout(_ error: NSError) -> Bool {
        error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56
    }

    /// The seven audit types iOS defines (XCUIAccessibilityAuditTypes.h: `.all` adds only reserved bits
    /// on iOS), one call each, with dynamic type last because it re-lays the sheet out at other text
    /// sizes while it runs. A single `.all` call, reserved bits included, does not finish within
    /// XCTest's time limit at the format sheet's last position.
    static let auditPasses: [XCUIAccessibilityAuditType] = [
        .contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .textClipped, .trait, .dynamicType,
    ]

    @MainActor
    private func performAuditAllowingTimeouts(_ app: XCUIApplication, types: XCUIAccessibilityAuditType,
                                              _ handler: @escaping (XCUIAccessibilityAuditIssue) throws -> Bool) throws {
        for attempt in 1...Self.auditAttempts {
            do {
                try XCTContext.runActivity(named: "Audit \(AccessibilityAudit.name(of: types)), attempt \(attempt)") { _ in
                    try app.performAccessibilityAudit(for: types, handler)
                }
                return
            } catch let error as NSError where Self.isTimeout(error) && attempt < Self.auditAttempts {
                print("audit: did not complete in time (-56), attempt \(attempt); auditing this position again")
                Thread.sleep(forTimeInterval: 10)
            }
        }
    }
}
