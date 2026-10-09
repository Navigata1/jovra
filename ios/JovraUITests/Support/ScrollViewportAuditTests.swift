import XCTest

/// Captured renderer issue: a scrolling label at y102 was sampled under a fixed header;
/// visible labels and fixed controls must keep failing actual reported audit findings.
final class ScrollViewportAuditTests: XCTestCase {
    private let viewport = CGRect(x: 0, y: 138, width: 402, height: 736)
    private let occludedLabel = CGRect(x: 36, y: 102, width: 81, height: 20)

    func testRenderingOnlyOnConfirmedOccludedScrollingContentIsDeferred() {
        for type in [XCUIAccessibilityAuditType.contrast, .elementDetection] {
            XCTAssertTrue(AccessibilityAudit.isOccludedScrollIssue(type: type, frame: occludedLabel, viewport: viewport, isScrollDescendant: true))
            XCTAssertTrue(AccessibilityAudit.isOccludedScrollIssue(type: type, frame: CGRect(x: 36, y: 130, width: 81, height: 20), viewport: viewport, isScrollDescendant: true))
        }
    }

    func testVisibleScrollingAndFixedHeaderFindingsAreNeverDeferred() {
        for type in [XCUIAccessibilityAuditType.contrast, .elementDetection] {
            XCTAssertFalse(AccessibilityAudit.isOccludedScrollIssue(type: type, frame: CGRect(x: 36, y: 150, width: 81, height: 20), viewport: viewport, isScrollDescendant: true))
            XCTAssertFalse(AccessibilityAudit.isOccludedScrollIssue(type: type, frame: CGRect(x: 16, y: 78, width: 44, height: 44), viewport: viewport, isScrollDescendant: false))
        }
    }

    func testTextClippingAndEveryNonRenderingIssueStillFailEvenWhenOccluded() {
        for type in [XCUIAccessibilityAuditType.textClipped, .dynamicType, .hitRegion, .sufficientElementDescription, .trait] {
            XCTAssertFalse(AccessibilityAudit.isOccludedScrollIssue(type: type, frame: occludedLabel, viewport: viewport, isScrollDescendant: true))
        }
        XCTAssertFalse(AccessibilityAudit.isOccludedScrollIssue(type: .contrast, frame: occludedLabel, viewport: .null, isScrollDescendant: true))
        XCTAssertFalse(AccessibilityAudit.isOccludedScrollIssue(type: .contrast, frame: occludedLabel, viewport: .zero, isScrollDescendant: true))
        XCTAssertFalse(AccessibilityAudit.isOccludedScrollIssue(type: .contrast, frame: .null, viewport: viewport, isScrollDescendant: true))
        XCTAssertFalse(AccessibilityAudit.isOccludedScrollIssue(type: .all, frame: occludedLabel, viewport: viewport, isScrollDescendant: true))
    }
}
