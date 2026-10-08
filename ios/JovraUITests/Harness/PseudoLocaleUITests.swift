import XCTest

/// The pseudo-locale run (story 382): every tab with the accented, bracketed pseudolanguage, which
/// lengthens every string that comes from a String Catalog. The assertion is the textClipped audit
/// (tab bar titles excepted, as documented in Support/AccessibilityAuditing.swift: they shrink to fit
/// their column by design); the screenshots are evidence only.
final class PseudoLocaleUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testEveryTabPassesTheTextClippedAuditInThePseudoLocale() throws {
        let app = XCUIApplication.launchJovra {
            $0.appearance = .light
            $0.pseudoLocale = .accented
        }
        for (index, tab) in ShellTab.allCases.enumerated() {
            let button = app.buttons[tab.identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(tab.identifier) exists")
            button.tap()
            XCTAssertTrue(button.isSelected, "\(tab.identifier) reports selected")
            let title = app.screenTitle
            XCTAssertTrue(title.waitForExistence(timeout: 5), "\(tab.slug) shows its title")
            // Proves the pseudolanguage is on: catalog strings come back bracketed.
            XCTAssertTrue(title.label.hasPrefix("[#"), "\(tab.slug) title is pseudo-localized: “\(title.label)”")
            XCTAssertTrue(button.label.hasPrefix("[#") && button.label.hasSuffix("#]"),
                          "\(tab.identifier) label is the whole pseudo-localized title: “\(button.label)”")
            attachScreenshot(app, name: "pseudo-\(index + 1)-\(tab.slug)")
            try auditScreen(app, for: .textClipped)
        }
    }
}
