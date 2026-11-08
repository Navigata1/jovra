import XCTest

/// Xcode's automated accessibility audit, run over the whole of a scrolling screen, with the two
/// documented exceptions (docs/DEVELOPING.md, "What the UI smoke test checks").
///
/// The audit runs on the screen as first shown, then again one, two, … slow swipes further down
/// (each swipe shorter than the viewport) until the end of the screen, so anything first seen cut
/// off by the tab bar is audited fully visible at a later step.
///
/// The audit scrolls the page by itself (22 pt to over 2,000 pt on JOVRA-T06). A contrast or element-detection
/// issue found while it moved the page was sampled from pixels that no longer sit under the reported
/// frames (on JOVRA-T06, high-contrast headings such as Home's "This week" failed this way); when the
/// page moved during an audit, those issues are set aside, logged, and the audit is repeated once at the
/// settled position, where they count like any other.
///
/// Exceptions, each logged when used:
/// - *Dynamic Type on tab bar titles*: they cap at xxxLarge and the Large Content Viewer takes over
///   (JovraTabBar), like the system tab bar. The audit reports a capped title as "may be clipped at
///   larger Dynamic Type sizes". Only the dynamicType audit, and only inside the tab bar's frame, is
///   exempt: a tab title that is actually clipped or truncated still fails the textClipped audit.
/// - *Contrast and element detection on clipped content*: an element that is not a tab bar item, under
///   the status-bar backdrop, or reaching into the tab bar or within `edgeBand` of it. There the audit
///   samples the backdrop, the bar or the chartreuse Record circle instead of the element, and its text
///   recognition sees text it cannot match to an element ("Potentially inaccessible text"). Each slow
///   swipe moves the page by more than `edgeBand` and less than the visible height, and every screen
///   ends with 32 pt of padding, so every element is audited clear of both bars at some step. Every
///   other audit type fails wherever the element is.
enum AccessibilityAudit {
    /// A renderer cannot assess a scrolling node whose pixels are cropped by its own viewport.
    /// Membership must be established from the scroll subtree; geometry alone must not exempt a
    /// fixed header control. Text clipping and all semantic/interaction findings always fail.
    static func isOccludedScrollIssue(type: XCUIAccessibilityAuditType, frame: CGRect,
                                      viewport: CGRect, isScrollDescendant: Bool) -> Bool {
        guard type == .contrast || type == .elementDetection,
              isScrollDescendant, !viewport.isNull, !viewport.isEmpty,
              !frame.isNull, !frame.isEmpty,
              [frame.minY, frame.maxY, viewport.minY, viewport.maxY].allSatisfy({ $0.isFinite }) else { return false }
        return frame.minY < viewport.minY || frame.maxY > viewport.maxY
    }

    /// Height of the band above the tab bar in which contrast sampling is unreliable.
    static let edgeBand: CGFloat = 16
    static let maximumSteps = 6
    /// Scroll settling: the page counts as still when the screen title moves less than 0.5 pt between
    /// two reads `settleInterval` apart, checked at most `settleChecks` times.
    static let settleInterval: TimeInterval = 0.3
    static let settleChecks = 10

    /// A readable name for the log (the type prints as its raw value).
    static func name(of type: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "elementDetection"), (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "sufficientElementDescription"), (.dynamicType, "dynamicType"),
            (.textClipped, "textClipped"), (.trait, "trait"),
        ]
        return names.first { $0.0 == type }?.1 ?? "audit type \(type.rawValue)"
    }
}

extension XCTestCase {
    /// Audits every part of the current screen for `types` (all audits by default).
    @MainActor
    func auditScreen(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType = .all, scrollIdentifier: String? = nil) throws {
        // On a tab screen the lockup is the first row, Space.x1 (8 pt) below the status-bar backdrop.
        let lockup = app.descendants(matching: .any).matching(identifier: "brand.lockup").firstMatch
        let onTabScreen = scrollIdentifier == nil && app.otherElements["tabBar"].exists && lockup.exists
        let visibleTop = onTabScreen ? lockup.frame.minY - 8 : 0
        let scrollView = scrollIdentifier.map { app.scrollViews[$0] } ?? app.scrollViews.firstMatch
        if let scrollIdentifier, !scrollView.exists {
            XCTFail("Requested foreground scroll view is missing: " + scrollIdentifier); return
        }
        let title = scrollIdentifier == nil ? app.staticTexts.matching(identifier: "screen.title").firstMatch
            : scrollView.staticTexts.matching(identifier: "screen.title").firstMatch
        if scrollIdentifier != nil, !title.exists {
            XCTFail("Requested foreground scroll title is missing"); return
        }
        try auditVisibleScreen(app, for: types, visibleTop: visibleTop, marker: title, scrollView: scrollView, foregroundModal: scrollIdentifier != nil)
        guard scrollView.exists, title.exists else { return }
        // The audit itself may move the scroll position, so each step starts again from the top and
        // scrolls `step` slow swipes down; it stops once another swipe no longer moves the page.
        var previousTitleY = title.frame.minY
        for step in 1...AccessibilityAudit.maximumSteps {
            scrollToTop(scrollView, foregroundTitle: scrollIdentifier == nil ? nil : title)
            for _ in 0..<step { scrollView.swipeUp(velocity: .slow) }
            waitForScrollingToSettle(title)
            let titleY = title.frame.minY
            guard abs(titleY - previousTitleY) > 1 else { break }
            previousTitleY = titleY
            try auditVisibleScreen(app, for: types, visibleTop: visibleTop, marker: title, scrollView: scrollView, foregroundModal: scrollIdentifier != nil)
        }
        scrollToTop(scrollView, foregroundTitle: scrollIdentifier == nil ? nil : title)
    }

    @MainActor
    private func scrollToTop(_ scrollView: XCUIElement, foregroundTitle: XCUIElement? = nil) {
        guard let foregroundTitle else {
            for _ in 0..<3 { scrollView.swipeDown(velocity: .fast) }
            return
        }
        for _ in 0..<12 {
            // A short allowance starts the pan recognizer; stop before a second pull at the top.
            let remaining = scrollView.frame.minY - foregroundTitle.frame.minY
            if remaining <= 1 { return }
            let distance = min(remaining + 16, scrollView.frame.height * 0.45)
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.1)
            waitForScrollingToSettle(foregroundTitle)
        }
        XCTFail("Foreground scroll did not reach its top boundary")
    }

    /// A swipe returns while the page may still be decelerating; an audit taken then samples pixels
    /// that no longer sit under the elements' reported frames. Waits until `marker` holds still.
    @MainActor
    private func waitForScrollingToSettle(_ marker: XCUIElement) {
        var previous = marker.frame.minY
        for _ in 0..<AccessibilityAudit.settleChecks {
            Thread.sleep(forTimeInterval: AccessibilityAudit.settleInterval)
            let current = marker.frame.minY
            if abs(current - previous) < 0.5 { return }
            previous = current
        }
        print("audit: scrolling did not settle after \(AccessibilityAudit.settleChecks) checks")
    }

    /// Audits the screen as it is. The audit scrolls a partly hidden element into view by itself, and
    /// a rendering-dependent issue (contrast, element detection) found while it moved the page was
    /// sampled from pixels that no longer sit under the reported frames. If the page moved during the
    /// audit, such issues are set aside and the audit is repeated once at the settled position; the
    /// repeat's result is the one that counts.
    @MainActor
    private func auditVisibleScreen(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType, visibleTop: CGFloat,
                                    marker: XCUIElement, scrollView: XCUIElement, foregroundModal: Bool, isRepeat: Bool = false) throws {
        let tabBar = app.otherElements["tabBar"]
        let hasForegroundTabBar = !foregroundModal && tabBar.exists
        let visibleBottom = hasForegroundTabBar ? tabBar.frame.minY : app.frame.maxY
        let tabBarFrame = hasForegroundTabBar ? tabBar.frame : .null
        let markerY = marker.exists ? marker.frame.minY : nil
        var setAside: [String] = []
        try app.performAccessibilityAudit(for: types) { issue in
            guard let element = issue.element else { return false }
            // Tab bar titles stop growing at xxxLarge, like the system tab bar; the Large Content
            // Viewer shows them enlarged. The audit reports the cap as a Dynamic Type issue: exempt
            // inside the bar only. Text clipping is never exempt.
            if issue.auditType == .dynamicType, tabBarFrame.contains(element.frame) {
                print("audit: ignored dynamic type on tab bar “\(element.label)” (capped titles, Large Content Viewer)")
                return true
            }
            let frame = element.frame
            let isRendered = issue.auditType == .contrast || issue.auditType == .elementDetection
            if isRendered, !isRepeat, let markerY, abs(marker.frame.minY - markerY) > 1 {
                print("audit: \(AccessibilityAudit.name(of: issue.auditType)) issue on “\(element.label)” at \(frame) set aside: the audit moved the page by \(marker.frame.minY - markerY) pt")
                setAside.append(element.label)
                return true
            }
            if isRendered, scrollView.exists {
                let viewport = scrollView.frame.intersection(app.frame)
                let matches = scrollView.descendants(matching: element.elementType).matching(
                    NSPredicate(format: "identifier == %@ AND label == %@", element.identifier, element.label)
                ).allElementsBoundByIndex
                let belongsToScroll = matches.contains { $0.frame == frame }
                if AccessibilityAudit.isOccludedScrollIssue(type: issue.auditType, frame: frame,
                                                           viewport: viewport, isScrollDescendant: belongsToScroll) {
                    print("audit: \(AccessibilityAudit.name(of: issue.auditType)) on scrolling “\(element.label)” at \(frame) cropped by actual viewport \(viewport); assessed when visible")
                    return true
                }
            }
            let isTabBarItem = element.identifier.hasPrefix("tab.")
            let isClipped = !isTabBarItem && (frame.maxY > visibleBottom - AccessibilityAudit.edgeBand || frame.minY < visibleTop)
            guard isRendered, isClipped else {
                print("audit: \(AccessibilityAudit.name(of: issue.auditType)) issue on “\(element.label)” at \(frame), visible \(visibleTop)–\(visibleBottom): FAILS (\(issue.compactDescription))")
                return false
            }
            print("audit: \(AccessibilityAudit.name(of: issue.auditType)) issue on “\(element.label)” at \(frame), visible \(visibleTop)–\(visibleBottom): ignored (clipped or in the edge band)")
            return true
        }
        guard !setAside.isEmpty else { return }
        waitForScrollingToSettle(marker)
        print("audit: repeating the audit at the settled position for \(setAside)")
        try auditVisibleScreen(app, for: types, visibleTop: visibleTop, marker: marker, scrollView: scrollView, foregroundModal: foregroundModal, isRepeat: true)
    }
}
