import XCTest

/// T17: the capture route's recording phase through the visibly labelled simulator fixture camera.
/// Every state the ticket names is reached by the real engine (pause, the fixture's interruption control,
/// a killed process) and audited with performAccessibilityAudit in portrait and landscape.
final class CaptureRecordingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    override func tearDown() {
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    // MARK: The flow

    @MainActor
    func testRecordPauseInterruptResumeAndStopLandsASessionWithGapsInTheLibrary() throws {
        let title = "T17 " + UUID().uuidString.prefix(6)
        let app = XCUIApplication.launchJovra { $0.demo = .off; $0.startRoute = "capture" }
        try startRecording(app, title: title)
        XCTAssertTrue(app.staticTexts["Simulator fixture camera"].exists, "the fixture camera is visibly labelled")
        XCTAssertTrue(app.staticTexts["capture.sample"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["capture.recPill"].label.hasPrefix("Recording, "))
        waitForSavedThrough(app, seconds: 2)
        assertNoLiveAnalysisElements(app)

        app.buttons["capture.markPoint"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Point marked · '")).firstMatch.waitForExistence(timeout: 5))

        app.buttons["capture.pause"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.pausedBanner"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any)["capture.recPill"].label.hasPrefix("Paused, "))
        app.buttons["capture.resume"].tap()
        XCTAssertTrue(app.buttons["capture.pause"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any)["capture.gap.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["capture.gap.0"].label.hasSuffix("· paused"))

        waitForSavedThrough(app, seconds: 4)
        interrupt(app)
        let question = app.staticTexts["capture.interruptionSheet.title"]
        XCTAssertTrue(question.label.hasPrefix("Recording stopped at "), question.label)
        XCTAssertTrue(question.label.hasSuffix("\u{00A0}— Resume?"), question.label)
        XCTAssertTrue(app.descendants(matching: .any)["capture.segmentSaved"].label.hasPrefix("Segment saved · Saved through "),
                      "user story 97: the closed segment is confirmed as saved")
        app.buttons["capture.interruption.resume"].tap()
        XCTAssertTrue(app.buttons["capture.pause"].waitForExistence(timeout: 30), "Resume continues the same session")
        let interruptionGap = app.descendants(matching: .any)["capture.gap.1"]
        XCTAssertTrue(interruptionGap.waitForExistence(timeout: 5))
        XCTAssertTrue(interruptionGap.label.hasSuffix("· interruption"), interruptionGap.label)
        waitForSavedThrough(app, seconds: 6)

        app.buttons["capture.stop"].tap()
        let confirm = app.buttons["capture.confirmStop"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["capture.saved"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["capture.saved.state"].label.hasPrefix("Saved with gaps"),
                      "a paused and interrupted recording is savedWithGaps")
        attachScreenshot(app, name: "s06-dark-saved-phase")
        app.buttons["capture.openLibrary"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.session.' AND label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the session is in the store")
    }

    @MainActor
    func testCaptureControlsMeetArmsLengthSizes() throws {
        let app = XCUIApplication.launchJovra { $0.demo = .off; $0.startRoute = "capture" }
        try startRecording(app, title: nil)
        for id in ["capture.markPoint", "capture.pause"] {
            let control = app.buttons[id]
            XCTAssertGreaterThanOrEqual(control.frame.width, 64, id)
            XCTAssertGreaterThanOrEqual(control.frame.height, 64, id)
        }
        let stop = app.buttons["capture.stop"]
        XCTAssertGreaterThanOrEqual(stop.frame.width, 76)
        XCTAssertGreaterThanOrEqual(stop.frame.height, 76)
        XCTAssertEqual(stop.label, "Stop recording")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["capture.stop"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.buttons["capture.stop"].frame.height, 76)
        XCTAssertGreaterThanOrEqual(app.buttons["capture.markPoint"].frame.height, 64)
        stopAndSave(app)
    }

    @MainActor
    func testDeleteThisRecordingRemovesTheSessionAfterConfirmation() throws {
        let title = "T17 delete " + UUID().uuidString.prefix(6)
        let app = XCUIApplication.launchJovra { $0.demo = .off; $0.startRoute = "capture" }
        try startRecording(app, title: title)
        waitForSavedThrough(app, seconds: 2)
        app.buttons["capture.more"].tap()
        let delete = app.buttons["capture.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let keep = app.buttons["capture.keepRecording"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5), "deleting asks first")
        waitForSheetToSettle()
        attachScreenshot(app, name: "s06-dark-delete-confirmation")
        try auditScreen(app)
        app.buttons["capture.confirmDelete"].tap()
        XCTAssertTrue(app.otherElements["tabBar"].waitForExistence(timeout: 15), "the route closes after deleting")
        app.buttons["tab.sessions"].tap()
        XCTAssertTrue(app.heading("Your sessions").waitForExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.session.' AND label CONTAINS %@", title)).firstMatch
        XCTAssertFalse(row.waitForExistence(timeout: 3), "the deleted session is not in the library")
    }

    // MARK: Crash and relaunch

    @MainActor
    func testRelaunchAfterAKilledRecordingShowsTheRecoveredRecordingSheetOnce() throws {
        let title = "T17 crash " + UUID().uuidString.prefix(6)
        var app = XCUIApplication.launchJovra { $0.demo = .off; $0.startRoute = "capture" }
        try startRecording(app, title: title)
        waitForSavedThrough(app, seconds: 2)
        app.buttons["capture.pause"].tap()
        XCTAssertTrue(app.buttons["capture.resume"].waitForExistence(timeout: 30))
        app.buttons["capture.resume"].tap()
        XCTAssertTrue(app.buttons["capture.pause"].waitForExistence(timeout: 30))
        waitForSavedThrough(app, seconds: 5)
        app.terminate()   // The process dies mid-segment: no stop, no sink handoff, an unfinished journal.

        app = XCUIApplication.launchJovra { $0.demo = .off; $0.appearance = .dark }
        let sheet = app.staticTexts["recovery.title"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "the relaunch reconciles the journal and says so")
        XCTAssertEqual(sheet.label, "Recording recovered")
        XCTAssertTrue(app.staticTexts[title].exists)
        XCTAssertTrue(app.staticTexts["recovery.savedThrough"].label.hasPrefix("Saved through "))
        let gaps = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'recovery.gap.'"))
        XCTAssertGreaterThanOrEqual(gaps.count, 1)
        XCTAssertTrue(gaps.allElementsBoundByIndex.contains { $0.label.hasSuffix("· paused") }, "the paused gap is listed")
        XCTAssertFalse(app.staticTexts["recovery.partial"].exists, "every segment decoded, so no partial report is claimed")
        attachScreenshot(app, name: "s06-dark-recovered-sheet")
        try auditScreen(app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        waitForSheetToSettle()
        shot(app, "s06-dark-landscape-recovered-sheet")
        try auditScreen(app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["recovery.done"].waitForExistence(timeout: 5))
        waitForSheetToSettle()
        app.buttons["recovery.done"].tap()
        XCTAssertFalse(sheet.waitForExistence(timeout: 2))

        app.terminate()
        app = XCUIApplication.launchJovra { $0.demo = .off }
        XCTAssertTrue(app.buttons["tab.sessions"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["recovery.title"].waitForExistence(timeout: 5), "an adopted recovery is reported once")
        app.buttons["tab.sessions"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.session.' AND label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the recovered session is in the library")
    }

    @MainActor
    func testRelaunchAfterALostSegmentShowsThePartialRecoveryReport() throws {
        let title = "T17 partial " + UUID().uuidString.prefix(6)
        var app = XCUIApplication.launchJovra { $0.demo = .off; $0.startRoute = "capture" }
        try startRecording(app, title: title)
        waitForSavedThrough(app, seconds: 2)
        app.buttons["capture.pause"].tap()
        XCTAssertTrue(app.buttons["capture.resume"].waitForExistence(timeout: 30))
        let firstSegmentEnd = savedSeconds(app)
        app.buttons["capture.resume"].tap()
        XCTAssertTrue(app.buttons["capture.pause"].waitForExistence(timeout: 30))
        waitForSavedThrough(app, seconds: firstSegmentEnd + 3)
        app.buttons["capture.pause"].tap()   // The second segment closes, so only the damage decides what is lost.
        XCTAssertTrue(app.buttons["capture.resume"].waitForExistence(timeout: 30))
        app.terminate()
        try damageFirstSegment(ofSessionTitled: title)

        app = XCUIApplication.launchJovra { $0.demo = .off; $0.appearance = .light }
        let sheet = app.staticTexts["recovery.title"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 30))
        XCTAssertEqual(sheet.label, "Recording partially recovered", "a recording that lost a part is never announced as fully recovered")
        XCTAssertTrue(app.staticTexts[title].exists)
        let partial = app.descendants(matching: .any)["recovery.partial"]
        XCTAssertTrue(partial.exists, "user story 100: the report says what failed")
        XCTAssertEqual(partial.label, "Part of this recording could not be recovered")
        let lost = app.staticTexts["recovery.unrecoverable.0"]
        XCTAssertTrue(lost.exists)
        XCTAssertTrue(lost.label.hasPrefix("Part 1: "), lost.label)
        XCTAssertFalse(app.staticTexts["recovery.unrecoverable.1"].exists, "the playable second part is kept, not reported lost")
        let gaps = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'recovery.gap.'"))
            .allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(gaps.contains { $0.hasPrefix("Gap 0:00–") && $0.hasSuffix("· not saved") }, "the lost part is a gap: \(gaps)")
        XCTAssertTrue(gaps.contains { $0.hasSuffix("· paused") }, "the player's pause is still listed: \(gaps)")
        attachScreenshot(app, name: "s06-light-recovered-partial-report")
        try auditScreen(app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        waitForSheetToSettle()
        shot(app, "s06-light-landscape-recovered-partial-report")
        try auditScreen(app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["recovery.openLibrary"].waitForExistence(timeout: 5))
        waitForSheetToSettle()
        app.buttons["recovery.openLibrary"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.session.' AND label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "every playable segment is kept in the library")
        XCTAssertTrue(row.label.contains("Partially saved"), row.label)
    }

    @MainActor
    func testTheRecoveredSheetWaitsForAnOpenCaptureRouteToClose() throws {
        let title = "T17 waits " + UUID().uuidString.prefix(6)
        var app = XCUIApplication.launchJovra { $0.demo = .off; $0.startRoute = "capture" }
        try startRecording(app, title: title)
        waitForSavedThrough(app, seconds: 2)
        app.terminate()

        // The next launch opens straight into the capture route, as a restored scene would.
        app = XCUIApplication.launchJovra { $0.demo = .off; $0.appearance = .light; $0.startRoute = "capture" }
        XCTAssertTrue(app.buttons["capture.start"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["recovery.title"].waitForExistence(timeout: 5), "two presentations at once would drop one")
        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.staticTexts["recovery.title"].waitForExistence(timeout: 15), "the report is kept until the shell is clear")
        XCTAssertTrue(app.staticTexts[title].exists)
        waitForSheetToSettle()
        // The sheet follows a forest capture route and must still take the app's light appearance.
        attachScreenshot(app, name: "s06-light-recovered-sheet")
        try auditScreen(app)
        app.buttons["recovery.done"].tap()
        XCTAssertTrue(app.staticTexts["recovery.title"].waitForNonExistence(timeout: 5))
    }

    // MARK: Accessibility audits (light, dark, AX5 × portrait, landscape)

    @MainActor
    func testRecordingStatesPassTheAccessibilityAuditInLight() throws {
        try auditEveryState(name: "light") { $0.appearance = .light }
    }

    @MainActor
    func testRecordingStatesPassTheAccessibilityAuditInDark() throws {
        try auditEveryState(name: "dark") { $0.appearance = .dark }
    }

    @MainActor
    func testRecordingStatesPassTheAccessibilityAuditAtAX5() throws {
        try auditEveryState(name: "ax5", contentSize: .accessibility5) { $0.appearance = .dark }
    }

    @MainActor
    func testRecoveredSheetPassesTheAccessibilityAuditAtAX5InBothOrientations() throws {
        let title = "T17 ax5 crash " + UUID().uuidString.prefix(6)
        var app = XCUIApplication.launchJovra { $0.demo = .off; $0.startRoute = "capture" }
        try startRecording(app, title: title)
        waitForSavedThrough(app, seconds: 2)
        app.terminate()
        app = XCUIApplication.launchJovra(contentSize: .accessibility5) { $0.demo = .off; $0.appearance = .light }
        XCTAssertTrue(app.staticTexts["recovery.title"].waitForExistence(timeout: 30))
        attachScreenshot(app, name: "s06-ax5-recovered-sheet")
        try auditScreen(app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["recovery.title"].waitForExistence(timeout: 5))
        shot(app, "s06-ax5-landscape-recovered-sheet")
        try auditScreen(app)
        app.buttons["recovery.done"].tap()
    }

    @MainActor
    private func auditEveryState(name: String, contentSize: ContentSize? = nil,
                                 _ configure: (inout LaunchConfiguration) -> Void) throws {
        let app = XCUIApplication.launchJovra(contentSize: contentSize) {
            $0.demo = .off; $0.startRoute = "capture"; configure(&$0)
        }
        XCTAssertTrue(app.buttons["capture.start"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["capture.slot.framing"].exists, "T23's framing slot holds its placeholder")
        attachScreenshot(app, name: "s06-\(name)-slot-framing-empty")
        try startRecording(app, title: nil)
        waitForSavedThrough(app, seconds: 2)
        // T24's score overlay and T25's court mode slots are empty: no card, no made-up score, no cover.
        XCTAssertFalse(app.descendants(matching: .any)["capture.slot.courtMode"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Manual score'")).firstMatch.exists)
        attachScreenshot(app, name: "s06-\(name)-slot-score-and-court-mode-empty")
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let suffix = orientation == .portrait ? "" : "-landscape"
            XCTAssertTrue(app.buttons["capture.stop"].waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 1)
            shot(app, "s06-\(name)\(suffix)-recording")
            try auditScreen(app)

            app.buttons["capture.pause"].tap()
            XCTAssertTrue(app.buttons["capture.resume"].waitForExistence(timeout: 40))
            shot(app, "s06-\(name)\(suffix)-paused")
            try auditScreen(app)
            app.buttons["capture.resume"].tap()
            XCTAssertTrue(app.buttons["capture.pause"].waitForExistence(timeout: 30))

            interrupt(app)
            waitForSheetToSettle()
            shot(app, "s06-\(name)\(suffix)-interrupted")
            try auditScreen(app)
            app.buttons["capture.interruption.resume"].tap()
            XCTAssertTrue(app.buttons["capture.pause"].waitForExistence(timeout: 30))

            app.buttons["capture.stop"].tap()
            XCTAssertTrue(app.buttons["capture.keepRecording"].waitForExistence(timeout: 5))
            waitForSheetToSettle()
            shot(app, "s06-\(name)\(suffix)-stop-confirmation")
            try auditScreen(app)
            app.buttons["capture.keepRecording"].tap()
            XCTAssertTrue(app.buttons["capture.keepRecording"].waitForNonExistence(timeout: 5))
        }
        XCUIDevice.shared.orientation = .portrait
        stopAndSave(app)
    }

    // MARK: Helpers

    /// The whole screen as the device shows it: in landscape an app screenshot comes back in the portrait
    /// buffer's coordinates, so the screen's own capture is attached instead.
    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        guard XCUIDevice.shared.orientation.isLandscape else { attachScreenshot(app, name: name); return }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A sheet's presentation animation moves and scales its text; audits and screenshots wait for it to end.
    private func waitForSheetToSettle() { Thread.sleep(forTimeInterval: 1.2) }

    /// Opens the default singles draft, optionally renames it, and starts recording.
    @MainActor
    private func startRecording(_ app: XCUIApplication, title: String?) throws {
        let start = app.buttons["capture.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["capture.draft.title"].label, "Singles match", "no setup opens the default singles draft")
        if let title {
            app.buttons["capture.editDetails"].tap()
            let field = app.textFields["capture.setup.title"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + title)
            app.buttons["capture.details.done"].tap()
            XCTAssertTrue(app.staticTexts["capture.draft.title"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["capture.draft.title"].label, title)
        }
        let ready = NSPredicate(format: "enabled == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: start)], timeout: 15), .completed)
        start.tap()
        XCTAssertTrue(app.buttons["capture.stop"].waitForExistence(timeout: 15))
    }

    @MainActor
    private func waitForSavedThrough(_ app: XCUIApplication, seconds: Int) {
        let saved = app.staticTexts["capture.confirmedTime"]
        let enough = NSPredicate { _, _ in
            saved.exists && (saved.label.split(separator: ":").last.flatMap { Int($0) } ?? 0) >= seconds
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enough, object: nil)], timeout: 30), .completed,
                       "saved through \(seconds) s")
    }

    @MainActor
    private func savedSeconds(_ app: XCUIApplication) -> Int {
        app.staticTexts["capture.confirmedTime"].label.split(separator: ":").last.flatMap { Int($0) } ?? 0
    }

    /// The test runner shares the simulator's data volume with the app, so it can stand in for a segment
    /// that did not survive: it finds this test's own recording by its unique title and replaces the first
    /// segment with bytes no decoder accepts. Only synthetic fixture-camera media is ever touched.
    private func damageFirstSegment(ofSessionTitled title: String) throws {
        #if targetEnvironment(simulator)
        let files = FileManager.default
        let applications = URL(fileURLWithPath: NSHomeDirectory()).deletingLastPathComponent()
        for container in try files.contentsOfDirectory(at: applications, includingPropertiesForKeys: nil) {
            let sessions = container.appendingPathComponent("Library/Application Support/JOVRA/sessions")
            for folder in (try? files.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil)) ?? [] {
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("session.json")),
                      let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      document["title"] as? String == title,
                      (document["recording"] as? [String: Any])?["mode"] as? String == "simulatorFixture" else { continue }
                let originals = folder.appendingPathComponent("originals")
                XCTAssertEqual(try files.contentsOfDirectory(atPath: originals.path).sorted(), ["segment-0.mp4", "segment-1.mp4"])
                try Data("JOVRA synthetic damaged segment".utf8).write(to: originals.appendingPathComponent("segment-0.mp4"), options: .atomic)
                return
            }
        }
        XCTFail("no fixture recording titled \(title) in this simulator")
        #else
        throw XCTSkip("Damaging a segment from the test runner needs the simulator's shared data volume.")
        #endif
    }

    @MainActor
    private func interrupt(_ app: XCUIApplication) {
        let control = app.buttons["capture.debug.interrupt"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.tap()
        XCTAssertTrue(app.staticTexts["capture.interruptionSheet.title"].waitForExistence(timeout: 15))
    }

    @MainActor
    private func stopAndSave(_ app: XCUIApplication) {
        app.buttons["capture.stop"].tap()
        let confirm = app.buttons["capture.confirmStop"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["capture.saved"].waitForExistence(timeout: 20))
    }

    /// User story 88: the recording phase shows no live ball speed, body skeleton or line calls. Every
    /// label on screen is read, so a later overlay that adds one fails here.
    @MainActor
    private func assertNoLiveAnalysisElements(_ app: XCUIApplication) {
        let banned = ["speed", "km/h", "mph", "skeleton", "pose", "joint", "line call", "call: in", "call: out", "rpm", "spin"]
        let labels = app.descendants(matching: .any).allElementsBoundByIndex.map { $0.label.lowercased() }
            + app.descendants(matching: .any).allElementsBoundByIndex.map { $0.identifier.lowercased() }
        XCTAssertFalse(labels.isEmpty)
        for label in labels {
            for term in banned { XCTAssertFalse(label.contains(term), "“\(label)” shows \(term)") }
            XCTAssertFalse(["in", "out", "fault"].contains(label.trimmingCharacters(in: .whitespaces)), "“\(label)” looks like a line call")
        }
    }
}
