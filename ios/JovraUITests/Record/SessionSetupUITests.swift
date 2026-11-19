import XCTest

/// T21: session setup (S04) end to end on the simulator: the chosen setup reaches the capture route, an
/// invalid doubles order is blocked, only fixture presets are offered, the microphone consequence, low
/// space, the slots' empty states, the remembered setup after relaunch, and the accessibility audit of
/// the screen and every sheet in light, dark and AX5.
final class SessionSetupUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func launch(appearance: LaunchConfiguration.Appearance = .light, contentSize: ContentSize? = nil,
                        environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication.jovra(contentSize: contentSize) {
            $0.appearance = appearance
            $0.demo = .off
            $0.startRoute = "record"
        }
        for (key, value) in environment { app.launchEnvironment[key] = value }
        app.launch()
        XCTAssertTrue(app.heading("Set up your session").waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func tap(_ option: String, in field: String, _ app: XCUIApplication) {
        let group = app.descendants(matching: .any).matching(identifier: field).firstMatch
        let sheet = app.otherElements["sheet.container"]
        app.reveal(group.buttons[option], in: sheet.exists ? sheet.scrollViews.firstMatch : nil)
        group.buttons[option].tap()
    }

    /// One audit of a presented sheet as it first appears (no scroll steps): issues on the screen
    /// behind the sheet are set aside, as `auditSheet` does. A full scroll-step audit of every sheet
    /// in three variants kept the simulator's test daemon busy for most of an hour on this machine.
    @MainActor
    private func auditSheetViewport(_ app: XCUIApplication) throws {
        let sheet = app.otherElements["sheet.container"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let frame = sheet.frame.insetBy(dx: -1, dy: -1)
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element else { return false }
            return !frame.contains(element.frame)
        }
    }

    /// Taps the switch itself (trailing), not the row's words.
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        let before = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let changed = NSPredicate(format: "value != %@", before ?? "")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: changed, evaluatedWith: toggle)], timeout: 3), .completed)
    }

    @MainActor
    private func routePayload(_ app: XCUIApplication) throws -> [String: Any] {
        let probe = app.descendants(matching: .any).matching(identifier: "route.payload").firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 8), "the capture route is presented")
        let json = try XCTUnwrap(probe.value as? String)
        let route = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let capture = try XCTUnwrap(route["capture"] as? [String: Any], "the presented route is capture: \(json)")
        return try XCTUnwrap(capture["_0"] as? [String: Any], "capture carries a setup: \(json)")
    }

    // MARK: Acceptance

    @MainActor
    func testCheckCameraPositionPresentsCaptureWhosePayloadIsTheChosenSetup() throws {
        let app = launch(environment: ["JOVRA_ROUTE_PROBE": "1"])
        app.buttons["record.mode.singlesMatch"].tap()
        app.fillPlayers(["me": "Jon", "opponent": "Alex"], sessionName: "Probe match")
        tap("Left", in: "players.opponent.hand", app)
        tap("One-handed", in: "players.opponent.backhand", app)
        tap("Alex", in: "players.firstServer", app)
        tap("Far end", in: "players.startingEnd", app)
        app.finishSheet()

        app.reveal(app.buttons["record.scoring"]); app.buttons["record.scoring"].tap()
        let preset = app.buttons["format.preset.noAdMatchTiebreak"]
        app.reveal(preset, in: app.otherElements["sheet.container"].scrollViews.firstMatch)
        preset.tap()
        tap("No lets", in: "format.lets", app)
        tap("Deuce court", in: "format.decidingSide", app)
        app.finishSheet()
        XCTAssertEqual(app.buttons["record.scoring"].value as? String, "Best of 3 · No-Ad · 10-point match tie-break for the third set · No lets")

        app.reveal(app.buttons["record.camera"]); app.buttons["record.camera"].tap()
        let fixture = app.buttons["camera.format.720p30.fixture"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 5))
        fixture.tap()
        app.finishSheet()

        let microphone = app.switches["record.microphone"]
        app.reveal(microphone)
        if (microphone.value as? String) == "1" { flip(microphone) }

        let check = app.buttons["record.checkCameraPosition"]
        app.reveal(check)
        check.tap()
        let draft = try routePayload(app)
        XCTAssertEqual(draft["kind"] as? String, "singlesMatch")
        let setup = try XCTUnwrap(draft["sessionSetup"] as? [String: Any])
        XCTAssertEqual(setup["mode"] as? String, "singlesMatch")
        XCTAssertEqual(setup["sessionName"] as? String, "Probe match")
        XCTAssertEqual((setup["me"] as? [String: Any])?["name"] as? String, "Jon")
        let opponent = try XCTUnwrap(setup["opponent"] as? [String: Any])
        XCTAssertEqual(opponent["name"] as? String, "Alex")
        XCTAssertEqual(opponent["handedness"] as? String, "left")
        XCTAssertEqual(opponent["backhand"] as? String, "oneHanded")
        XCTAssertEqual(setup["firstServer"] as? String, "opponent")
        XCTAssertEqual(setup["myTeamStartsNear"] as? Bool, false)
        XCTAssertEqual(setup["noAdDecidingSide"] as? String, "deuce")
        let format = try XCTUnwrap(setup["format"] as? [String: Any])
        XCTAssertEqual(format["preset"] as? String, "noAdMatchTiebreak")
        XCTAssertEqual(format["lets"] as? String, "noLet")
        XCTAssertEqual(setup["cameraFormatID"] as? String, "720p30.fixture")
        XCTAssertEqual(setup["microphoneOn"] as? Bool, false)
        XCTAssertNil(draft["captureChoices"], "today's capture screen cannot record this format, so it is not offered a substitute")
    }

    @MainActor
    func testAnInvalidDoublesOrderIsBlockedWithAnExplanationAndAValidOneIsPresented() throws {
        let app = launch(environment: ["JOVRA_ROUTE_PROBE": "1"])
        app.buttons["record.mode.doublesMatch"].tap()
        app.fillPlayers(["me": "Jon", "partner": "Sam", "opponent": "Alex", "opponentPartner": "Lee"])
        tap("Sam", in: "players.order.1.second", app)
        let problem = app.descendants(matching: .any).matching(identifier: "players.order.1.problem").firstMatch
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        XCTAssertTrue(problem.label.contains("the second server must come from the other team"), problem.label)
        attachScreenshot(app, name: "t21-light-doubles-invalid-order")
        XCTAssertFalse(app.buttons["sheet.done"].isEnabled, "Done waits for a valid order")
        app.buttons["sheet.close"].tap()
        let problems = app.descendants(matching: .any).matching(identifier: "record.problems").firstMatch
        app.reveal(problems)
        XCTAssertTrue(problems.label.contains("must come from the other team"))
        let check = app.buttons["record.checkCameraPosition"]
        app.reveal(check)
        XCTAssertFalse(check.isEnabled, "an invalid order blocks recording")

        app.reveal(app.buttons["record.players"]); app.buttons["record.players"].tap()
        tap("Alex", in: "players.order.1.second", app)
        tap("Lee", in: "players.order.1.receiverB", app)
        XCTAssertFalse(problem.exists)
        let add = app.buttons["players.order.add"]
        app.reveal(add, in: app.otherElements["sheet.container"].scrollViews.firstMatch)
        add.tap()
        tap("Lee", in: "players.order.2.first", app)
        tap("Sam", in: "players.order.2.second", app)
        app.finishSheet()
        app.reveal(check)
        XCTAssertTrue(check.isEnabled)
        check.tap()
        let draft = try routePayload(app)
        XCTAssertEqual(draft["kind"] as? String, "doublesMatch")
        let setup = try XCTUnwrap(draft["sessionSetup"] as? [String: Any])
        let orders = try XCTUnwrap(setup["doublesOrders"] as? [[String: Any]])
        XCTAssertEqual(orders.count, 2, "one order per set")
        XCTAssertEqual(orders[0]["firstServer"] as? String, "me")
        XCTAssertEqual(orders[0]["secondServer"] as? String, "opponent")
        XCTAssertEqual(orders[0]["deuceReceiverB"] as? String, "opponentPartner")
        XCTAssertEqual(orders[1]["firstServer"] as? String, "opponentPartner")
        XCTAssertEqual(orders[1]["secondServer"] as? String, "partner")
    }

    @MainActor
    func testTheSimulatorOffersOnlyTheFixturePresetAndMicrophoneOffStatesItsConsequence() throws {
        let app = launch()
        let camera = app.buttons["record.camera"]
        app.reveal(camera)
        XCTAssertTrue((camera.value as? String)?.hasPrefix("720p · 30 fps, Simulator fixture camera") == true, "\(camera.value ?? "")")
        camera.tap()
        let sheet = app.otherElements["sheet.container"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let formats = sheet.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'camera.format.'"))
        XCTAssertEqual(formats.count, 1, "only the fixture clip's own format is listed")
        XCTAssertEqual(formats.firstMatch.identifier, "camera.format.720p30.fixture")
        XCTAssertEqual(formats.firstMatch.label, "720p · 30 fps")
        app.finishSheet()

        let microphone = app.switches["record.microphone"]
        app.reveal(microphone)
        flip(microphone)
        XCTAssertEqual(microphone.value as? String, "0")
        XCTAssertEqual(app.staticTexts["record.microphone.detail"].label, "Off: rally detection unavailable; video still records")
        attachScreenshot(app, name: "t21-light-microphone-off")
    }

    @MainActor
    func testInjectedLowFreeSpaceShowsAWarningChip() throws {
        let app = launch(environment: ["JOVRA_DEVICE_BUDGET": "lowStorage"])
        let storage = app.descendants(matching: .any).matching(identifier: "record.preflight.storage").firstMatch
        app.reveal(storage)
        let value = try XCTUnwrap(storage.value as? String)
        XCTAssertTrue(value.hasPrefix("Room for about 22m"), value)
        XCTAssertTrue(value.hasSuffix("warning"), value)
        XCTAssertTrue((app.buttons["record.camera"].value as? String)?.contains("Not enough space for 1h. About 22m fits.") == true)
        attachScreenshot(app, name: "t21-light-low-space")
        let roomy = launch(environment: ["JOVRA_DEVICE_BUDGET": "roomy"])
        let chip = roomy.descendants(matching: .any).matching(identifier: "record.preflight.storage").firstMatch
        roomy.reveal(chip)
        XCTAssertTrue((chip.value as? String)?.hasPrefix("Storage ready") == true)
    }

    @MainActor
    func testTheConsentAndGearSlotsRenderTheirEmptyStates() {
        let app = launch()
        let gear = app.buttons["record.slot.gear"]
        app.reveal(gear)
        XCTAssertEqual(gear.label, "Gear")
        XCTAssertEqual(gear.value as? String, "Add your racket, Optional")
        let consent = app.descendants(matching: .any).matching(identifier: "record.slot.consent").firstMatch
        app.reveal(consent)
        XCTAssertEqual(consent.label, "Recording consent")
        XCTAssertTrue((consent.value as? String)?.hasPrefix("Not set") == true)
    }

    @MainActor
    func testTheLastSetupIsRestoredAfterRelaunch() {
        let app = launch()
        app.buttons["record.mode.servePractice"].tap()
        app.fillPlayers(["me": "Jon"])
        app.finishSheet()
        let microphone = app.switches["record.microphone"]
        app.reveal(microphone)
        flip(microphone)
        app.terminate()

        app.launchEnvironment["JOVRA_SETUP_RESET"] = "0"
        app.launch()
        XCTAssertTrue(app.heading("Set up your session").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["record.mode.servePractice"].isSelected, "the remembered mode is selected")
        XCTAssertFalse(app.buttons["record.mode.singlesMatch"].isSelected)
        app.reveal(app.buttons["record.players"])
        XCTAssertEqual(app.buttons["record.players"].value as? String, "Jon")
        app.reveal(app.switches["record.microphone"])
        XCTAssertEqual(app.switches["record.microphone"].value as? String, "0")
    }

    // MARK: Accessibility and evidence (light, dark, AX5)

    @MainActor
    func testSetupAndEverySheetPassTheAuditInLight() throws { try auditEverything(.light, nil, "light") }

    @MainActor
    func testSetupAndEverySheetPassTheAuditInDark() throws { try auditEverything(.dark, nil, "dark") }

    @MainActor
    func testSetupAndEverySheetPassTheAuditAtAX5() throws { try auditEverything(.light, .accessibility5, "ax5") }

    @MainActor
    private func auditEverything(_ appearance: LaunchConfiguration.Appearance, _ size: ContentSize?, _ variant: String) throws {
        let app = launch(appearance: appearance, contentSize: size)
        app.fillPlayers(["me": "Jon", "opponent": "Alex"])
        tap("Right", in: "players.me.hand", app)
        tap("Left", in: "players.opponent.hand", app)
        app.finishSheet()
        for _ in 0..<6 { app.scrollViews.firstMatch.swipeDown(velocity: .fast) }
        attachScreenshot(app, name: "s04-\(variant)-setup")
        assertHitTargets(in: app)
        try auditScreen(app)
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        attachScreenshot(app, name: "t21-\(variant)-setup-lower")

        for (row, slug) in [("record.players", "players"), ("record.scoring", "format"), ("record.camera", "camera")] {
            let button = app.buttons[row]
            app.reveal(button)
            button.tap()
            XCTAssertTrue(app.otherElements["sheet.container"].waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 1.2) // the presentation animation ends before pixels are sampled
            attachScreenshot(app, name: "t21-\(variant)-sheet-\(slug)")
            assertHitTargets(in: app)
            try auditSheetViewport(app)
            app.buttons["sheet.close"].tap()
            XCTAssertTrue(app.otherElements["sheet.container"].waitForNonExistence(timeout: 5))
        }

        // Doubles: the players sheet with the serving-order editor.
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        app.buttons["record.mode.doublesMatch"].tap()
        app.fillPlayers(["partner": "Sam", "opponentPartner": "Lee"])
        let order = app.descendants(matching: .any).matching(identifier: "players.order.1.second").firstMatch
        app.reveal(order, in: app.otherElements["sheet.container"].scrollViews.firstMatch)
        attachScreenshot(app, name: "t21-\(variant)-sheet-players-doubles")
        app.buttons["sheet.close"].tap()

        // Practice: no scoring row; the camera angle row instead.
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        app.buttons["record.mode.strokePractice"].tap()
        XCTAssertFalse(app.buttons["record.scoring"].exists, "practice has no scoring row")
        let angle = app.descendants(matching: .any).matching(identifier: "record.cameraAngle").firstMatch
        app.reveal(angle)
        attachScreenshot(app, name: "t21-\(variant)-stroke-practice")
    }
}
