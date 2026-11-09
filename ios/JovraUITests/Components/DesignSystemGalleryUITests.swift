import XCTest

/// T12 design-system extensions, through the DEBUG component gallery: every component state is
/// audited (performAccessibilityAudit) in light, dark and AX5 with named screenshots; the fraction
/// popover, toasts, capability page, hero art and readable column are exercised as a player would.
final class DesignSystemGalleryUITests: XCTestCase {
    /// The scenarios this ticket adds (CoreComponentsUITests covers the state cards and badges).
    static let scenarios = ["tiles", "popover", "controls", "feedback", "chrome", "capability", "capability-injected", "art"]
    /// `TEST_RUNNER_JOVRA_GALLERY_SCENARIOS=tiles,feedback` narrows the audit loops while iterating.
    static var auditedScenarios: [String] {
        guard let only = ProcessInfo.processInfo.environment["JOVRA_GALLERY_SCENARIOS"], !only.isEmpty else { return scenarios }
        return only.split(separator: ",").map(String.init)
    }
    static let appearances: [(slug: String, appearance: LaunchConfiguration.Appearance, size: ContentSize)] = [
        ("light", .light, .large), ("dark", .dark, .large), ("ax5", .light, .accessibility5),
    ]

    /// The gallery's page starts `Space.screenMargin` (20 pt) above its title, right under the status bar.
    @MainActor
    static func pageTop(of app: XCUIApplication) -> CGFloat {
        app.screenTitle.frame.minY - 20
    }

    @MainActor
    private func launchGallery(_ scenario: String, appearance: LaunchConfiguration.Appearance = .light,
                               size: ContentSize = .large) -> XCUIApplication {
        let app = XCUIApplication.jovra(contentSize: size) { $0.appearance = appearance }
        app.launchEnvironment["JOVRA_CORE_COMPONENT_GALLERY"] = scenario
        app.launch()
        XCTAssertTrue(app.heading("Core components").waitForExistence(timeout: 8), "gallery \(scenario) launched")
        return app
    }

    @MainActor
    func testEveryNewComponentScenarioPassesTheAuditInLightDarkAndAX5() throws {
        for (slug, appearance, size) in Self.appearances {
            for scenario in Self.auditedScenarios {
                let app = launchGallery(scenario, appearance: appearance, size: size)
                // The capability page is read-only; at AX5 a page's first screen may hold only text.
                assertHitTargets(in: app, requiresControls: false)
                try auditScreen(app, pageTop: Self.pageTop(of: app))
                attachScreenshot(app, name: "t12-\(slug)-\(scenario)")
                app.terminate()
            }
        }
    }

    @MainActor
    func testFractionPopoverReadsValueFractionAndProvenance() throws {
        for (slug, appearance, size) in Self.appearances {
            let app = launchGallery("tiles", appearance: appearance, size: size)
            let tile = app.buttons["tile.firstServes"]
            XCTAssertTrue(tile.waitForExistence(timeout: 5))
            XCTAssertEqual(tile.value as? String, "67 percent, 40 of 60, manual", "the tile itself reads its fraction")
            tile.tap()
            let value = app.descendants(matching: .any)["fraction.value"]
            XCTAssertTrue(value.waitForExistence(timeout: 5), "tapping the tile opens the fraction popover")
            XCTAssertEqual(value.label, "First serves in")
            XCTAssertEqual(value.value as? String, "67 percent, 40 of 60, manual")
            XCTAssertTrue(app.staticTexts["First serves that landed in, out of every first serve you hit."].exists, "definition")
            XCTAssertTrue(app.staticTexts["Manual value"].exists || app.descendants(matching: .any)["Manual value"].exists,
                          "provenance badge")
            attachScreenshot(app, name: "t12-\(slug)-fraction-popover")
            // XCUITest reports a presented popover with an empty visible frame, so its audit cannot attribute
            // the popover's text; the same content is audited inline in the "popover" gallery scenario.
            // At accessibility sizes the popover's content scrolls; bring its action into view as a
            // player would, by scrolling the popover.
            let showPoints = app.buttons["Show points"]
            // XCUITest reports the popover itself with an empty frame, so the drag starts on its content.
            for _ in 0..<6 where !showPoints.isHittable {
                let start = value.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -240)))
            }
            XCTAssertTrue(showPoints.isHittable, "Show points is reachable at \(slug)")
            showPoints.tap()
            XCTAssertTrue(app.staticTexts["Show points requested"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testZeroDenominatorShowsAnEmDashAndReadsNoData() throws {
        let app = launchGallery("tiles")
        let tile = app.buttons["tile.secondServes"]
        if !tile.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertEqual(tile.value as? String, "no data")
        tile.tap()
        let value = app.descendants(matching: .any)["fraction.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.value as? String, "no data")
        attachScreenshot(app, name: "t12-light-fraction-zero")
    }

    @MainActor
    func testToastAndUndoBarAppearAndUndoWorks() throws {
        let app = launchGallery("feedback")
        let show = app.buttons["Show toast"]
        while !show.isHittable { app.swipeUp(velocity: .slow) }
        show.tap()
        let toast = app.otherElements["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.staticTexts["Score updated for points 43–124"].exists)
        attachScreenshot(app, name: "t12-light-toast")
        XCTAssertTrue(toast.waitForNonExistence(timeout: 8), "a toast dismisses itself after 4 s")

        app.buttons["Move to Recently deleted"].tap()
        let undoBar = app.otherElements["undoBar"]
        XCTAssertTrue(undoBar.waitForExistence(timeout: 3))
        attachScreenshot(app, name: "t12-light-undobar")
        let undo = undoBar.buttons["toast.undo"]
        XCTAssertGreaterThanOrEqual(undo.frame.width, 44)
        XCTAssertGreaterThanOrEqual(undo.frame.height, 44)
        undo.tap()
        XCTAssertTrue(app.staticTexts["Restored"].waitForExistence(timeout: 3))
        XCTAssertFalse(undoBar.exists)
    }

    @MainActor
    func testCapabilityDetailRendersTheRegistryAndAnInjectedOne() {
        let shipped = launchGallery("capability")
        XCTAssertEqual(shipped.descendants(matching: .any)["capability.status"].value as? String, "Estimated")
        XCTAssertEqual(shipped.descendants(matching: .any)["capability.benchmark"].value as? String, "Not benchmarked")
        XCTAssertEqual(shipped.descendants(matching: .any)["capability.testedOn"].value as? String, "Not tested yet")
        XCTAssertEqual(shipped.descendants(matching: .any)["capability.methodVersion"].value as? String,
                       "serveSpeed.manualAssisted@1.0.0")
        shipped.terminate()

        let injected = launchGallery("capability-injected")
        XCTAssertEqual(injected.descendants(matching: .any)["capability.status"].value as? String, "Validated")
        XCTAssertEqual(injected.descendants(matching: .any)["capability.benchmark"].value as? String, "Passed on Mar 2, 2027")
        XCTAssertEqual(injected.descendants(matching: .any)["capability.testedOn"].value as? String, "Test dataset: radar-paired serves")
    }

    /// The real route (N12): "How this was measured" opens as a sheet, reads the bundled registry, passes
    /// the audit in light, dark and AX5, and closes with its 44 pt Close control.
    @MainActor
    func testCapabilitySheetRouteRendersTheRegistryAndCloses() throws {
        for (slug, appearance, size) in Self.appearances {
            let app = XCUIApplication.launchJovra(contentSize: size) {
                $0.appearance = appearance
                $0.startRoute = "sheet.capabilityDetail"
            }
            XCTAssertTrue(app.heading("How this was measured").waitForExistence(timeout: 8))
            let status = app.descendants(matching: .any)["capability.status"]
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            XCTAssertEqual(status.value as? String, "Estimated")
            XCTAssertEqual(app.descendants(matching: .any)["capability.methodVersion"].value as? String,
                           "serveSpeed.manualAssisted@1.0.0")
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "placeholder.ticket").firstMatch.exists)
            let close = app.buttons["sheet.close"]
            XCTAssertEqual(close.label, "Close how this was measured")
            XCTAssertGreaterThanOrEqual(close.frame.width, 44)
            XCTAssertGreaterThanOrEqual(close.frame.height, 44)
            // A long sheet that scrolls: audited as a foreground modal, step by step down its scroll view.
            try auditScreen(app, scrollIdentifier: "capability.scroll")
            attachScreenshot(app, name: "t12-\(slug)-capability-sheet")
            close.tap()
            XCTAssertTrue(app.heading("How this was measured").waitForNonExistence(timeout: 5), "Close dismisses the sheet")
            app.terminate()
        }
    }

    @MainActor
    func testHeroArtIsHiddenFromVoiceOver() {
        let app = launchGallery("art")
        XCTAssertTrue(app.buttons["Record a session"].exists, "the editorial card's content is there")
        // Two pieces of vector art are on screen (the editorial backdrop and a feature panel); the
        // only things VoiceOver can reach are the page's words and its one button.
        let labels = Set(app.descendants(matching: .any).allElementsBoundByIndex.map(\.label)
            .filter { !$0.isEmpty && !$0.hasPrefix("Vertical scroll bar") })
        XCTAssertEqual(labels, ["Core components", "Ready for your next session?", "Record a session"])
        XCTAssertEqual(app.images.count, 0, "no illustration is announced as an image")
        attachScreenshot(app, name: "t12-light-hero-art")
    }

    /// ReadableColumn: full width on iPhone, capped at 720 pt on a regular-width iPad. The gallery
    /// reports the column's measured width.
    @MainActor
    func testReadableColumnIsFullWidthOnIPhoneAndCappedAt720OnIPad() throws {
        let app = launchGallery("chrome")
        let readout = app.staticTexts["gallery.columnWidth"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        let width = try XCTUnwrap(Double(readout.label.filter(\.isNumber)))
        let window = app.windows.firstMatch.frame
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertGreaterThan(window.width, 760, "a regular-width window")
            XCTAssertEqual(width, 720, accuracy: 1, "capped at 720 pt")
        } else {
            XCTAssertEqual(width, Double(window.width), accuracy: 1, "full width on iPhone")
        }
        attachScreenshot(app, name: "t12-\(UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone")-readable-column")
    }

    /// Run with the simulator in Increase Contrast (`xcrun simctl ui <udid> increase_contrast enabled`)
    /// and TEST_RUNNER_JOVRA_EXPECT_INCREASED_CONTRAST=1; skipped otherwise.
    @MainActor
    func testEveryScenarioInIncreasedContrast() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JOVRA_EXPECT_INCREASED_CONTRAST"] == "1",
                          "needs the simulator in Increase Contrast")
        for appearance in [("light", LaunchConfiguration.Appearance.light), ("dark", .dark)] {
            for scenario in ["empty", "error", "badges"] + Self.auditedScenarios {
                let app = launchGallery(scenario, appearance: appearance.1)
                XCTAssertEqual(app.screenTitle.value as? String, "Increased contrast", "the app sees Increase Contrast")
                try auditScreen(app, pageTop: Self.pageTop(of: app))
                attachScreenshot(app, name: "t12-hc-\(appearance.0)-\(scenario)")
                app.terminate()
            }
        }
    }
}
