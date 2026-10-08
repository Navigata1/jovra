import XCTest

/// Xcode's automated accessibility audit, run over the whole of a scrolling screen, with the two
/// documented exceptions (docs/DEVELOPING.md, "What the UI tests check").
///
/// The audit runs on the screen as first shown, then again one, two, … slow swipes further down
/// (each swipe shorter than the viewport) until the end of the screen, so anything first seen cut
/// off by the tab bar is audited fully visible at a later step.
///
/// Exceptions, each logged when used:
/// - *Dynamic Type on tab bar titles*: they cap at xxxLarge and the Large Content Viewer takes over
///   (JovraTabBar), like the system tab bar. The audit reports a capped title as "may be clipped at
///   larger Dynamic Type sizes". Only the dynamicType audit, and only inside the tab bar's frame, is
///   exempt: a tab title that is actually clipped or truncated still fails the textClipped audit.
/// - *Contrast on clipped content*: an element that is not a tab bar item, under the status-bar
///   backdrop, or reaching into the tab bar or within `edgeBand` of it, where the audit samples the
///   bar and the chartreuse Record circle instead of the element. Each slow swipe moves the page by
///   more than `edgeBand` and less than the visible height, and every screen ends with 32 pt of
///   padding, so every element is audited clear of the bar at some step.
enum AccessibilityAudit {
    /// Height of the band above the tab bar in which contrast sampling is unreliable.
    static let edgeBand: CGFloat = 16
    static let maximumSteps = 6
}

extension XCTestCase {
    /// Audits every part of the current screen for `types` (all audits by default).
    @MainActor
    func auditScreen(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType = .all) throws {
        // On a tab screen the lockup is the first row, Space.x1 (8 pt) below the status-bar backdrop.
        let lockup = app.descendants(matching: .any).matching(identifier: "brand.lockup").firstMatch
        let onTabScreen = app.otherElements["tabBar"].exists && lockup.exists
        let visibleTop = onTabScreen ? lockup.frame.minY - 8 : 0
        let title = app.staticTexts.matching(identifier: "screen.title").firstMatch
        let scrollView = app.scrollViews.firstMatch
        try auditVisibleScreen(app, for: types, visibleTop: visibleTop)
        guard scrollView.exists, title.exists else { return }
        // The audit itself may move the scroll position, so each step starts again from the top and
        // scrolls `step` slow swipes down; it stops once another swipe no longer moves the page.
        var previousTitleY = title.frame.minY
        for step in 1...AccessibilityAudit.maximumSteps {
            scrollToTop(scrollView)
            for _ in 0..<step { scrollView.swipeUp(velocity: .slow) }
            let titleY = title.frame.minY
            guard abs(titleY - previousTitleY) > 1 else { break }
            previousTitleY = titleY
            try auditVisibleScreen(app, for: types, visibleTop: visibleTop)
        }
        scrollToTop(scrollView)
    }

    @MainActor
    private func scrollToTop(_ scrollView: XCUIElement) {
        for _ in 0..<3 { scrollView.swipeDown(velocity: .fast) }
    }

    @MainActor
    private func auditVisibleScreen(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType, visibleTop: CGFloat) throws {
        let tabBar = app.otherElements["tabBar"]
        let visibleBottom = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
        let tabBarFrame = tabBar.exists ? tabBar.frame : .null
        try app.performAccessibilityAudit(for: types) { issue in
            guard let element = issue.element else { return false }
            // Tab bar titles stop growing at xxxLarge, like the system tab bar; the Large Content
            // Viewer shows them enlarged. The audit reports the cap as a Dynamic Type issue: exempt
            // inside the bar only. Text clipping is never exempt.
            if issue.auditType == .dynamicType, tabBarFrame.contains(element.frame) {
                print("audit: ignored dynamic type on tab bar “\(element.label)” (capped titles, Large Content Viewer)")
                return true
            }
            guard issue.auditType == .contrast else {
                print("audit: \(issue.auditType) issue on “\(element.label)” at \(element.frame): FAILS (\(issue.compactDescription))")
                return false
            }
            let frame = element.frame
            let isTabBarItem = element.identifier.hasPrefix("tab.")
            let isClipped = !isTabBarItem && (frame.maxY > visibleBottom - AccessibilityAudit.edgeBand || frame.minY < visibleTop)
            print("audit: contrast issue on “\(element.label)” at \(frame), visible \(visibleTop)–\(visibleBottom): \(isClipped ? "ignored (clipped or in the edge band)" : "FAILS")")
            return isClipped
        }
    }
}
