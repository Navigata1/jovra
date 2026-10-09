import XCTest

/// T07: every destination of the navigation model, visited through the launch harness
/// (`-startRoute <launch name>`). Each placeholder must show its title and the ticket that builds it
/// and pass the accessibility audit; every full-screen route has a top-leading Close control of at
/// least 44 × 44 pt labelled "Close <screen>", hides the tab bar, and returns to the tabs when closed.
///
/// The expected names, tickets and labels are written out here by hand (the app's catalog must match
/// them, not the other way round).
final class NavigationRoutesUITests: XCTestCase {
    struct Expected {
        var launchName: String
        var title: String
        var ticket: String
        var closeLabel: String?
    }

    static let preShell: [Expected] = [
        .init(launchName: "welcome", title: "Welcome", ticket: "T18"),
        .init(launchName: "onboarding", title: "Player onboarding", ticket: "T18"),
    ]

    static let pushes: [Expected] = [
        .init(launchName: "sessions.import", title: "Import videos", ticket: "T26"),
        .init(launchName: "sessions.matchOverview", title: "Match overview", ticket: "T22"),
        .init(launchName: "sessions.practiceOverview", title: "Practice overview", ticket: "T22"),
        .init(launchName: "insights.shotMap", title: "Shot map", ticket: "T41"),
        .init(launchName: "insights.serveLab", title: "Serve Lab", ticket: "T43"),
        .init(launchName: "insights.strokeLab", title: "Stroke Lab", ticket: "T42"),
        .init(launchName: "insights.progress", title: "Progress", ticket: "T48"),
        .init(launchName: "insights.drillDetail", title: "Drill", ticket: "T47"),
        .init(launchName: "profile.racketVault", title: "Racket Vault", ticket: "T49"),
        .init(launchName: "profile.stringJournal", title: "String journal", ticket: "T49"),
        .init(launchName: "profile.storage", title: "Storage and backup", ticket: "T51"),
        .init(launchName: "profile.settings", title: "Settings", ticket: "T56"),
        .init(launchName: "profile.spaceSaver", title: "Space Saver", ticket: "T55"),
        .init(launchName: "profile.diagnostics", title: "Diagnostics", ticket: "T57"),
        .init(launchName: "profile.recordingRules", title: "Recording rules", ticket: "T58"),
    ]

    static let fullScreens: [Expected] = [
        .init(launchName: "capture", title: "Capture", ticket: "T17", closeLabel: "Close capture"),
        .init(launchName: "replay", title: "Smart replay", ticket: "T28", closeLabel: "Close replay"),
        .init(launchName: "compare", title: "Compare", ticket: "T45", closeLabel: "Close compare"),
        .init(launchName: "pointReview", title: "Point review", ticket: "T30", closeLabel: "Close point review"),
        .init(launchName: "highlightReel", title: "Highlight reel", ticket: "T37", closeLabel: "Close highlight reel"),
        .init(launchName: "drillSession", title: "Drill session", ticket: "T47", closeLabel: "Close drill session"),
        .init(launchName: "processing", title: "Processing", ticket: "T27", closeLabel: "Close processing"),
    ]

    static let sheets: [Expected] = [
        .init(launchName: "sheet.pointEditor", title: "Point editor", ticket: "T29", closeLabel: "Close point editor"),
        .init(launchName: "sheet.clipExport", title: "Clip export", ticket: "T36", closeLabel: "Close clip export"),
        .init(launchName: "sheet.sharePack", title: "Share Pack", ticket: "T38", closeLabel: "Close Share Pack"),
        .init(launchName: "sheet.capabilityDetail", title: "How this was measured", ticket: "T12", closeLabel: "Close how this was measured"),
        .init(launchName: "sheet.matchFormat", title: "Match format", ticket: "T21", closeLabel: "Close match format"),
        .init(launchName: "sheet.players", title: "Players", ticket: "T21", closeLabel: "Close players"),
        .init(launchName: "sheet.cameraPreset", title: "Camera preset", ticket: "T21", closeLabel: "Close camera preset"),
        .init(launchName: "sheet.trash", title: "Trash", ticket: "T20", closeLabel: "Close trash"),
        .init(launchName: "sheet.goal", title: "Goal", ticket: "T48", closeLabel: "Close goal"),
        .init(launchName: "sheet.consentAttach", title: "Consent", ticket: "T58", closeLabel: "Close consent"),
        .init(launchName: "sheet.calibration", title: "Calibration", ticket: "T23", closeLabel: "Close calibration"),
        .init(launchName: "sheet.stringBroke", title: "String broke", ticket: "T50", closeLabel: "Close string broke"),
        .init(launchName: "sheet.restore", title: "Restore a session", ticket: "T54", closeLabel: "Close restore a session"),
        .init(launchName: "sheet.comparisonPicker", title: "Choose two recordings", ticket: "T45", closeLabel: "Close choose two recordings"),
        .init(launchName: "sheet.driveAccount", title: "Google Drive account", ticket: "T53", closeLabel: "Close Google Drive account"),
        .init(launchName: "sheet.account", title: "Account", ticket: "T56", closeLabel: "Close account"),
        .init(launchName: "sheet.deleteAllData", title: "Delete all JOVRA data", ticket: "T57", closeLabel: "Close delete all JOVRA data"),
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Every placeholder

    @MainActor
    func testEveryFullScreenRouteHasACloseControlAndHidesTheTabs() throws {
        for expected in Self.fullScreens {
            let app = launch(expected)
            assertPlaceholder(expected, in: app)
            XCTAssertFalse(app.otherElements["tabBar"].exists, "\(expected.launchName) hides the tab bar")
            let close = app.buttons["\(expected.launchName).close"]
            XCTAssertTrue(close.exists, "\(expected.launchName) has a Close control")
            XCTAssertEqual(close.label, expected.closeLabel)
            XCTAssertGreaterThanOrEqual(close.frame.width, 44, "\(expected.launchName) Close is at least 44 pt wide")
            XCTAssertGreaterThanOrEqual(close.frame.height, 44, "\(expected.launchName) Close is at least 44 pt tall")
            XCTAssertLessThan(close.frame.midX, app.frame.midX, "\(expected.launchName) Close sits at top leading")
            XCTAssertLessThan(close.frame.midY, app.frame.height * 0.2, "\(expected.launchName) Close sits at the top")
            assertHitTargets(in: app)
            try auditScreen(app)

            close.tap()
            XCTAssertTrue(app.otherElements["tabBar"].waitForExistence(timeout: 5), "closing \(expected.launchName) returns to the tabs")
            app.terminate()
        }
    }

    @MainActor
    func testEverySheetHasACloseControlAndNamesItsTicket() throws {
        for expected in Self.sheets {
            let app = launch(expected)
            assertPlaceholder(expected, in: app)
            let close = app.buttons["sheet.close"]
            XCTAssertTrue(close.exists, "\(expected.launchName) has a Close control")
            XCTAssertEqual(close.label, expected.closeLabel)
            XCTAssertGreaterThanOrEqual(close.frame.width, 44)
            XCTAssertGreaterThanOrEqual(close.frame.height, 44)
            try auditSheet(app)

            close.tap()
            XCTAssertTrue(app.heading(expected.title).waitForNonExistence(timeout: 5), "closing \(expected.launchName) dismisses it")
            app.terminate()
        }
    }

    @MainActor
    func testEveryPushKeepsTheTabsAndGoesBack() throws {
        for expected in Self.pushes {
            let app = launch(expected)
            assertPlaceholder(expected, in: app)
            XCTAssertTrue(app.otherElements["tabBar"].exists, "\(expected.launchName) keeps the tab bar")
            let tab = "tab.\(expected.launchName.split(separator: ".")[0])"
            XCTAssertTrue(app.buttons[tab].isSelected, "\(expected.launchName) is on its tab")
            try auditScreen(app)

            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.exists, "\(expected.launchName) has a Back button")
            back.tap()
            XCTAssertTrue(app.heading(expected.title).waitForNonExistence(timeout: 5), "Back leaves \(expected.launchName)")
            app.terminate()
        }
    }

    @MainActor
    func testThePreShellHasNoTabsAndOpensTheApp() throws {
        for expected in Self.preShell {
            let app = launch(expected)
            assertPlaceholder(expected, in: app)
            XCTAssertFalse(app.otherElements["tabBar"].exists, "\(expected.launchName) is before the shell")
            try auditScreen(app)

            app.buttons["preShell.continue"].tap()
            XCTAssertTrue(app.heading("Home").waitForExistence(timeout: 5), "the pre-shell opens on Home")
            XCTAssertTrue(app.otherElements["tabBar"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testRecordPresentsCaptureAndClosingReturnsToRecord() {
        let app = XCUIApplication.launchJovra { $0.appearance = .light }
        app.buttons["tab.record"].tap()
        for (id, value) in [("capture.setup.title", "Navigation test"), ("capture.setup.playerA", "Jon"), ("capture.setup.playerB", "Alex")] {
            let field = app.textFields[id]
            field.tap(); field.typeText(value + "\n")
        }
        app.swipeUp()
        app.buttons["record.previewCapture"].tap()
        XCTAssertTrue(app.heading("Capture").waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["tabBar"].exists)
        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.buttons["tab.record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.record"].isSelected, "closing returns to the tab that presented the route")
    }

    // MARK: Evidence: one of each kind in light, dark and AX5

    @MainActor
    func testRepresentativePlaceholdersInLightDarkAndAX5() throws {
        let samples: [(Expected, String)] = [
            (Self.preShell[0], "welcome"),
            (Self.pushes[1], "push-match-overview"),
            (Self.fullScreens[1], "full-screen-replay"),
            (Self.sheets[0], "sheet-point-editor"),
        ]
        let variants: [(LaunchConfiguration.Appearance, ContentSize?, String)] = [
            (.light, nil, "light"), (.dark, nil, "dark"), (.light, .accessibility5, "ax5"),
        ]
        for (appearance, size, variant) in variants {
            for (expected, slug) in samples {
                let app = XCUIApplication.launchJovra(contentSize: size) {
                    $0.appearance = appearance
                    $0.startRoute = expected.launchName
                }
                assertPlaceholder(expected, in: app)
                attachScreenshot(app, name: "t07-\(variant)-\(slug)")
                if expected.launchName.hasPrefix("sheet.") { try auditSheet(app) } else { try auditScreen(app) }
                app.terminate()
            }
        }
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ expected: Expected) -> XCUIApplication {
        XCUIApplication.launchJovra {
            $0.appearance = .light
            $0.startRoute = expected.launchName
        }
    }

    @MainActor
    private func assertPlaceholder(_ expected: Expected, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.heading(expected.title).waitForExistence(timeout: 8), "\(expected.launchName) shows “\(expected.title)”", file: file, line: line)
        if expected.launchName == "capture" {
            XCTAssertTrue(app.staticTexts["capture.kind"].exists, "Capture now renders its actual setup", file: file, line: line)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "placeholder.ticket").firstMatch.exists)
            return
        }
        if expected.launchName == "sheet.clipExport" {
            XCTAssertTrue(app.textFields["export.from"].waitForExistence(timeout: 5), "Export renders actual range controls", file: file, line: line)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "placeholder.ticket").firstMatch.exists)
            return
        }
        let ticket = app.descendants(matching: .any).matching(identifier: "placeholder.ticket").firstMatch
        XCTAssertTrue(ticket.exists, "\(expected.launchName) shows the ticket that builds it", file: file, line: line)
        XCTAssertEqual(ticket.label, "Built in ticket \(expected.ticket)", file: file, line: line)
    }
}
