import XCTest

/// T07, stories 17, 333 and 346: JOVRA never asks for a permission at launch; it explains in its own
/// sheet first, then shows Apple's own prompt; a denied permission states the consequence and links to
/// iOS Settings. The states come from the launch harness (`-permissions camera=denied`), except where
/// the test needs Apple's real prompt.
final class PermissionsCenterUITests: XCTestCase {
    @MainActor private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testColdStartAndATourOfTheTabsShowNoSystemPrompt() {
        let app = XCUIApplication.jovra { $0.appearance = .light }
        for resource in [XCUIProtectedResource.camera, .microphone, .photos] {
            app.resetAuthorizationStatus(for: resource)
        }
        app.launch()
        XCTAssertTrue(app.heading("Home").waitForExistence(timeout: 8))
        XCTAssertFalse(springboard.alerts.firstMatch.waitForExistence(timeout: 3), "no system prompt on a cold start")
        for tab in ShellTab.allCases {
            app.buttons[tab.identifier].tap()
            XCTAssertTrue(app.heading(tab.heading).waitForExistence(timeout: 5))
            XCTAssertFalse(springboard.alerts.firstMatch.waitForExistence(timeout: 1), "no system prompt on \(tab.slug)")
        }
    }

    @MainActor
    func testTheExplanationComesFirstThenApplesOwnPrompt() {
        let app = XCUIApplication.jovra {
            $0.appearance = .light
            $0.startRoute = "sheet.permission.microphone"
        }
        app.resetAuthorizationStatus(for: .microphone)
        app.launch()

        XCTAssertTrue(app.heading("Microphone").waitForExistence(timeout: 8))
        XCTAssertEqual(element("permission.status", in: app).label, "Status: Not asked yet")
        XCTAssertTrue(element("permission.explanation", in: app).exists, "JOVRA's explanation is shown first")
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "no system prompt before the player continues")
        attachScreenshot(app, name: "t07-light-permission-explanation")

        app.buttons["permission.continue"].tap()
        let prompt = springboard.alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "Apple's own prompt follows the explanation")
        let dontAllow = prompt.buttons.element(boundBy: 0)
        dontAllow.tap()

        let status = element("permission.status", in: app)
        XCTAssertTrue(status.waitForLabel("Status: Off", timeout: 5), "the answer is reflected (\(status.label))")
        XCTAssertEqual(element("permission.consequence", in: app).label,
                       "Recordings have no sound, so rallies won't be found automatically. Recording and scoring still work.")
        XCTAssertTrue(app.buttons["permission.openSettings"].exists, "a denied permission links to iOS Settings")
    }

    @MainActor
    func testADeniedPermissionStatesTheConsequenceAndOpensIOSSettings() throws {
        let app = XCUIApplication.launchJovra {
            $0.appearance = .light
            $0.permissions = [.camera: .denied]
            $0.startRoute = "sheet.permission.camera"
        }
        XCTAssertTrue(app.heading("Camera").waitForExistence(timeout: 8))
        XCTAssertEqual(element("permission.status", in: app).label, "Status: Off")
        XCTAssertEqual(element("permission.consequence", in: app).label,
                       "Recording is off because camera access is off. You can still import videos and review your sessions.")
        let openSettings = app.buttons["permission.openSettings"]
        XCTAssertEqual(openSettings.label, "Open iOS Settings")
        assertHitTargets(in: app)
        try auditSheet(app)

        openSettings.tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10), "iOS Settings opens")
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "no prompt: iOS Settings is where it changes")
        app.activate()
    }

    @MainActor
    func testRestrictedAndAuthorizedOfferNoPrompt() {
        for (state, label) in [(LaunchConfiguration.PermissionState.restricted, "Status: Restricted"), (.authorized, "Status: Allowed")] {
            let app = XCUIApplication.launchJovra {
                $0.appearance = .light
                $0.permissions = [.photosAdd: state]
                $0.startRoute = "sheet.permission.photosAdd"
            }
            XCTAssertTrue(app.heading("Photos").waitForExistence(timeout: 8))
            XCTAssertEqual(element("permission.status", in: app).label, label)
            XCTAssertFalse(app.buttons["permission.continue"].exists, "\(state): nothing to ask")
            XCTAssertFalse(app.buttons["permission.openSettings"].exists, "\(state): nothing to change")
            XCTAssertTrue(app.buttons["permission.done"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testDeniedPermissionSheetInLightDarkAndAX5() throws {
        let variants: [(LaunchConfiguration.Appearance, ContentSize?, String)] = [
            (.light, nil, "light"), (.dark, nil, "dark"), (.light, .accessibility5, "ax5"),
        ]
        for (appearance, size, name) in variants {
            let app = XCUIApplication.launchJovra(contentSize: size) {
                $0.appearance = appearance
                $0.permissions = [.camera: .denied]
                $0.startRoute = "sheet.permission.camera"
            }
            XCTAssertTrue(app.heading("Camera").waitForExistence(timeout: 8))
            attachScreenshot(app, name: "t07-\(name)-permission-camera-denied")
            try auditSheet(app)
            app.terminate()
        }
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

extension XCUIElement {
    /// Waits until the element's label reads `label`.
    func waitForLabel(_ label: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
