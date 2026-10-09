import XCTest

final class CoreComponentsUITests: XCTestCase {
    @MainActor
    func testStatesInLightDarkAndAX5() throws {
        try auditGallery(states: ["empty", "denied", "error", "unsupported"])
    }

    @MainActor
    func testBadgesInLightDarkAndAX5() throws {
        try auditGallery(states: ["badges"])
    }

    @MainActor
    private func auditGallery(states: [String]) throws {
        let expectedTitles = ["empty": "No sessions yet", "denied": "Camera access is off",
                              "error": "Export didn't finish", "unsupported": "Speed is not available"]
        let appearances: [(String, LaunchConfiguration.Appearance, ContentSize?)] = [
            ("light", .light, .large), ("dark", .dark, .large), ("ax5", .light, .accessibility5),
        ]
        for (slug, appearance, size) in appearances {
            for state in states {
                let app = XCUIApplication.jovra(contentSize: size) { $0.appearance = appearance }
                app.launchEnvironment["JOVRA_CORE_COMPONENT_GALLERY"] = state
                app.launch()
                XCTAssertTrue(app.heading("Core components").waitForExistence(timeout: 8))
                if let expected = expectedTitles[state] {
                    XCTAssertTrue(app.staticTexts[expected].exists)
                } else {
                    XCTAssertEqual(app.staticTexts["gallery.fixture"].label, "Simulator fixture camera")
                }
                try auditScreen(app)
                attachScreenshot(app, name: "t12-\(slug)-\(state)")
                app.terminate()
            }
        }
    }

    @MainActor
    func testSampleAndFixtureAreExplicitAndSampleActionWorks() {
        let app = XCUIApplication.jovra { $0.appearance = .light }
        app.launchEnvironment["JOVRA_CORE_COMPONENT_GALLERY"] = "badges"
        app.launch()
        XCTAssertTrue(app.heading("Core components").waitForExistence(timeout: 8))
        attachScreenshot(app, name: "t12-light-badges")
        let sample = app.descendants(matching: .any)["gallery.sample"]
        XCTAssertTrue(sample.exists)
        guard sample.exists else { return }
        XCTAssertEqual(sample.label, "Sample data")
        XCTAssertTrue(app.staticTexts["gallery.sample"].exists, "A badge describes data; it is not an unlabeled interactive container")
        XCTAssertEqual(app.descendants(matching: .any)["gallery.fixture"].label, "Simulator fixture camera")
        app.buttons["Leave sample"].tap()
        XCTAssertTrue(app.staticTexts["Sample closed"].exists)
    }

    @MainActor
    func testEmptyStateOffersWorkingRecordAndImportActions() {
        let app = XCUIApplication.jovra { $0.appearance = .light }
        app.launchEnvironment["JOVRA_CORE_COMPONENT_GALLERY"] = "empty"
        app.launch()
        XCTAssertTrue(app.heading("Core components").waitForExistence(timeout: 8))
        attachScreenshot(app, name: "t12-light-empty-actions")
        let record = app.buttons["Record a session"]
        XCTAssertTrue(record.waitForExistence(timeout: 8))
        guard record.exists else { return }
        record.tap()
        XCTAssertTrue(app.staticTexts["Record requested"].exists)
        app.buttons["Import a video"].tap()
        XCTAssertTrue(app.staticTexts["Import requested"].exists)
    }
}
