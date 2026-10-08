import Vision
import XCTest

/// The pseudo-locale run (story 382). Every tab is shown in the accented, bracketed pseudolanguage,
/// which lengthens every string that comes from a String Catalog. The assertions are the textClipped
/// audit (tab bar titles included: only their Dynamic Type cap is exempt, see
/// Support/AccessibilityAuditing.swift) and a check that no visible text bypassed the catalogs. The
/// tab titles are also checked in the double-length pseudolanguage and at AX5, where a tab column is
/// narrowest for its text, by the audit and by reading the rendered title back from the screen. The
/// screenshots are evidence only.
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
        var bypassed: [String] = []
        for (index, tab) in ShellTab.allCases.enumerated() {
            let button = app.buttons[tab.identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(tab.identifier) exists")
            button.tap()
            XCTAssertTrue(button.isSelected, "\(tab.identifier) reports selected")
            let title = app.screenTitle
            XCTAssertTrue(title.waitForExistence(timeout: 5), "\(tab.slug) shows its title")
            // Proves the pseudolanguage is on: catalog strings come back bracketed.
            XCTAssertTrue(title.label.hasPrefix("[#"), "\(tab.slug) title is pseudo-localized: “\(title.label)”")
            bypassed += unlocalizedText(in: app).map { "\(tab.slug): “\($0)”" }
            attachScreenshot(app, name: "pseudo-\(index + 1)-\(tab.slug)")
            try auditScreen(app, for: .textClipped)
        }
        XCTAssertEqual(bypassed, [], "visible text that bypassed the String Catalogs")
    }

    /// Double-length titles at the default size: the audit, and each title read back from the screen
    /// in full (a truncated title reads back with "…" or a missing word).
    @MainActor
    func testTabTitlesFitInTheDoubleLengthPseudoLocale() throws {
        let app = XCUIApplication.launchJovra {
            $0.appearance = .light
            $0.pseudoLocale = .doubleLength
        }
        try assertTabTitlesFit(in: app, screenshotPrefix: "pseudo-double", readBack: true)
    }

    /// Accented, bracketed titles at AX5: the titles are capped at xxxLarge, the longest size they reach.
    @MainActor
    func testTabTitlesFitInThePseudoLocaleAtLargestAccessibilityTextSize() throws {
        let app = XCUIApplication.launchJovra(contentSize: .accessibility5) {
            $0.appearance = .light
            $0.pseudoLocale = .accented
        }
        try assertTabTitlesFit(in: app, screenshotPrefix: "pseudo-ax5", readBack: false)
    }

    /// Double-length titles at AX5.
    @MainActor
    func testTabTitlesFitInTheDoubleLengthPseudoLocaleAtLargestAccessibilityTextSize() throws {
        let app = XCUIApplication.launchJovra(contentSize: .accessibility5) {
            $0.appearance = .light
            $0.pseudoLocale = .doubleLength
        }
        try assertTabTitlesFit(in: app, screenshotPrefix: nil, readBack: true)
    }

    // MARK: Helpers

    /// Selects each tab in turn (a selected title is semibold, so wider) and checks every title.
    @MainActor
    private func assertTabTitlesFit(in app: XCUIApplication, screenshotPrefix: String?, readBack: Bool) throws {
        let tabBar = app.otherElements["tabBar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "tab bar exists")
        for (index, tab) in ShellTab.allCases.enumerated() {
            let button = app.buttons[tab.identifier]
            button.tap()
            XCTAssertTrue(button.isSelected, "\(tab.identifier) reports selected")
            XCTAssertTrue(app.screenTitle.waitForExistence(timeout: 5), "\(tab.slug) shows its title")
            for other in ShellTab.allCases {
                let item = app.buttons[other.identifier]
                XCTAssertTrue(item.label.hasPrefix("[#") || item.label.contains(" "),
                              "\(other.identifier) is pseudo-localized: “\(item.label)”")
                XCTAssertGreaterThanOrEqual(item.frame.minX, tabBar.frame.minX - 0.5, "\(other.identifier) stays in the bar")
                XCTAssertLessThanOrEqual(item.frame.maxX, tabBar.frame.maxX + 0.5, "\(other.identifier) stays in the bar")
                if readBack {
                    try assertRendersInFull(item, selectedTab: tab)
                }
            }
            if let screenshotPrefix {
                attachScreenshot(app, name: "\(screenshotPrefix)-\(index + 1)-\(tab.slug)")
            }
            try auditTabBar(app)
        }
    }

    /// The textClipped audit, failing on any tab bar title. Clipping elsewhere on these screens is
    /// logged and left to the accented run above, which audits every screen in full.
    @MainActor
    private func auditTabBar(_ app: XCUIApplication) throws {
        let tabBarFrame = app.otherElements["tabBar"].frame
        try app.performAccessibilityAudit(for: .textClipped) { issue in
            guard let element = issue.element else { return false }
            guard tabBarFrame.contains(element.frame) else {
                print("audit: text clipped on “\(element.label)” outside the tab bar: not part of this check")
                return true
            }
            print("audit: text clipped on tab bar “\(element.label)”: FAILS (\(issue.compactDescription))")
            return false
        }
    }

    /// Reads the title back from a screenshot of the tab item with on-device text recognition and
    /// compares it with the item's full accessibility label. Only used for the double-length
    /// pseudolanguage, which is plain English letters the recognizer reads reliably.
    @MainActor
    private func assertRendersInFull(_ item: XCUIElement, selectedTab: ShellTab) throws {
        let image = try XCTUnwrap(item.screenshot().image.cgImage, "\(item.identifier) screenshot")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        let rendered = lines.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        // Letters only, and "contains": the recognizer also reads the icon above the title (the
        // Record circle's "+" or the Insights bars as "ll"), and may split a wrapped title anywhere.
        let squash = { (text: String) in text.lowercased().filter(\.isLetter) }
        XCTAssertFalse(rendered.contains("…") || rendered.contains("..."),
                       "\(item.identifier) title is truncated on screen (\(selectedTab.slug) selected): “\(rendered)”")
        XCTAssertTrue(squash(rendered).contains(squash(item.label)),
                      "\(item.identifier) shows its whole title (\(selectedTab.slug) selected): read “\(rendered)”, label “\(item.label)”")
    }

    /// Visible static text with words in it that did not come from a String Catalog (it is not
    /// bracketed). FormatStyle output (JovraFormat) is localized by
    /// Foundation, not a catalog: a number, or a number with its unit attached such as "6h 42m".
    @MainActor
    private func unlocalizedText(in app: XCUIApplication) -> [String] {
        let screenFrame = app.frame
        let isFormattedValue = { (label: String) in
            label.split(whereSeparator: \.isWhitespace).allSatisfy { $0.first?.isNumber == true || !$0.contains(where: \.isLetter) }
        }
        return app.staticTexts.allElementsBoundByIndex
            .filter { $0.exists && screenFrame.intersects($0.frame) }
            .map(\.label)
            .filter { !$0.contains("[#") && !isFormattedValue($0) }
    }
}
