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

    func testAnUnattributedFindingIsDeferredOnlyWhileScrollContentIsCut() {
        XCTAssertTrue(AccessibilityAudit.isUnattributedCropIssue(type: .contrast, hasElement: false, scrollContentIsCropped: true))
        XCTAssertTrue(AccessibilityAudit.isUnattributedCropIssue(type: .elementDetection, hasElement: false, scrollContentIsCropped: true))
        // Nothing cut, or a finding with its element: the usual rules decide, so this exception never applies.
        XCTAssertFalse(AccessibilityAudit.isUnattributedCropIssue(type: .contrast, hasElement: false, scrollContentIsCropped: false))
        XCTAssertFalse(AccessibilityAudit.isUnattributedCropIssue(type: .contrast, hasElement: true, scrollContentIsCropped: true))
        for type in [XCUIAccessibilityAuditType.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription, .trait] {
            XCTAssertFalse(AccessibilityAudit.isUnattributedCropIssue(type: type, hasElement: false, scrollContentIsCropped: true))
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

    func testUnplacedContrastIsExemptOnlyWithNoElementOnASwiftUINodeAndTextUnderTheTabBar() {
        let node = AccessibilityAudit.unplacedSwiftUINodeContrast
        XCTAssertTrue(AccessibilityAudit.isUnplacedContrastUnderTabBar(type: .contrast, hasElement: false, detail: node,
                                                                       textUnderTabBar: ["“From your device”"]))
        // No text under the bar, a placed element, another description or another audit type: it still fails.
        XCTAssertFalse(AccessibilityAudit.isUnplacedContrastUnderTabBar(type: .contrast, hasElement: false, detail: node, textUnderTabBar: []))
        XCTAssertFalse(AccessibilityAudit.isUnplacedContrastUnderTabBar(type: .contrast, hasElement: true, detail: node, textUnderTabBar: ["x"]))
        XCTAssertFalse(AccessibilityAudit.isUnplacedContrastUnderTabBar(type: .contrast, hasElement: false, detail: "Contrast failed",
                                                                        textUnderTabBar: ["x"]))
        XCTAssertFalse(AccessibilityAudit.isUnplacedContrastUnderTabBar(type: .elementDetection, hasElement: false, detail: node,
                                                                        textUnderTabBar: ["x"]))
        // "Under the tab bar": reaching into the 16 pt band above it or below its top, and on screen.
        XCTAssertTrue(AccessibilityAudit.isUnderTabBar(frame: CGRect(x: 0, y: 700, width: 100, height: 50), tabBarTop: 759, screenBottom: 874))
        XCTAssertTrue(AccessibilityAudit.isUnderTabBar(frame: CGRect(x: 0, y: 810, width: 100, height: 100), tabBarTop: 759, screenBottom: 874))
        XCTAssertFalse(AccessibilityAudit.isUnderTabBar(frame: CGRect(x: 0, y: 600, width: 100, height: 100), tabBarTop: 759, screenBottom: 874))
        XCTAssertFalse(AccessibilityAudit.isUnderTabBar(frame: CGRect(x: 0, y: 900, width: 100, height: 40), tabBarTop: 759, screenBottom: 874))
    }
}
