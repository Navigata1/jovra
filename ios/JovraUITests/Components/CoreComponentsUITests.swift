import XCTest

final class CoreComponentsUITests: XCTestCase {
    @MainActor
    func testStatesAndBadgesInLightDarkAndAX5() throws {
        let appearances: [(String, LaunchConfiguration.Appearance, ContentSize?)] = [
            ("light", .light, .large), ("dark", .dark, .large), ("ax5", .light, .accessibility5),
        ]
        for (slug, appearance, size) in appearances {
            for state in ["empty", "denied", "error", "unsupported", "badges"] {
                let app = XCUIApplication.jovra(contentSize: size) { $0.appearance = appearance }
                app.launchEnvironment["JOVRA_CORE_COMPONENT_GALLERY"] = state
                app.launch()
                XCTAssertTrue(app.heading("Core components").waitForExistence(timeout: 8))
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
