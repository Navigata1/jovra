import XCTest

/// The audit's narrow exceptions are pure functions, so their negative controls run without the app.
final class AuditExceptionTests: XCTestCase {
    func testOnlyContrastOnALoneDashIsExempt() {
        XCTAssertTrue(AccessibilityAudit.isGlyphOnlyContrastIssue(type: .contrast, label: "—"))
        XCTAssertTrue(AccessibilityAudit.isGlyphOnlyContrastIssue(type: .contrast, label: "–"))
        // Words, numbers and a dash beside them still fail; so does every other audit type on a dash.
        XCTAssertFalse(AccessibilityAudit.isGlyphOnlyContrastIssue(type: .contrast, label: "67%"))
        XCTAssertFalse(AccessibilityAudit.isGlyphOnlyContrastIssue(type: .contrast, label: "— no data"))
        XCTAssertFalse(AccessibilityAudit.isGlyphOnlyContrastIssue(type: .contrast, label: ""))
        for type in [XCUIAccessibilityAuditType.dynamicType, .textClipped, .elementDetection, .hitRegion,
                     .sufficientElementDescription, .trait] {
            XCTAssertFalse(AccessibilityAudit.isGlyphOnlyContrastIssue(type: type, label: "—"))
        }
    }

    func testATimedOutAuditIsRepeatedOneTypeAtATime() {
        XCTAssertTrue(AccessibilityAudit.isTimeout(NSError(domain: "com.apple.xcode.xctest.accessibilityAudit", code: -56)))
        XCTAssertFalse(AccessibilityAudit.isTimeout(NSError(domain: "com.apple.xcode.xctest.accessibilityAudit", code: -1)))
        XCTAssertFalse(AccessibilityAudit.isTimeout(NSError(domain: NSCocoaErrorDomain, code: -56)))
        XCTAssertEqual(XCUIAccessibilityAuditType(AccessibilityAudit.singleTypes(in: .all)), .all, "every audit type still runs")
        XCTAssertGreaterThanOrEqual(AccessibilityAudit.singleTypes(in: .all).count, 7)
        XCTAssertEqual(AccessibilityAudit.singleTypes(in: [.contrast, .textClipped]), [.contrast, .textClipped])
    }
}
