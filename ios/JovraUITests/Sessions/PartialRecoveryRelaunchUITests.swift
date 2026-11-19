import XCTest

#if targetEnvironment(simulator)
/// Opt-in phases. The host checks custody before inducing damage between the first two.
final class PartialRecoveryRelaunchUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testRecordTwoSegmentsAndTerminateBeforeSave() throws {
        let app = try launchIsolated(startRoute: "record")
        defer { terminate(app) }
        for (id, text) in [("capture.setup.title", "Partial recovery fixture"),
                           ("capture.setup.playerA", "Fixture A"), ("capture.setup.playerB", "Fixture B")] {
            let field = app.textFields[id]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(text + "\n")
        }
        app.swipeUp()
        app.buttons["record.previewCapture"].tap()
        XCTAssertTrue(app.staticTexts["capture.sample"].waitForExistence(timeout: 10))
        app.buttons["capture.start"].tap()
        let saved = app.staticTexts["capture.confirmedTime"]
        waitForSavedSeconds(saved, atLeast: 2)
        let pause = app.buttons["capture.pause"]
        let resume = app.buttons["capture.resume"]
        pause.tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        let firstEnd = savedSeconds(saved)
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        waitForSavedSeconds(saved, atLeast: firstEnd + 2)
        app.buttons["capture.markPoint"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Point marked · '")).firstMatch.waitForExistence(timeout: 5))
        pause.tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["capture.saved"].exists)
    }

    @MainActor
    func testFirstColdLaunchRecoversAndOpensPartialRecording() throws {
        try verifyRecovery(announced: true, screenshot: "partial-recovery-first-launch")
    }

    @MainActor
    func testNextColdLaunchKeepsPartialRecordingWithoutAnnouncingAgain() throws {
        try verifyRecovery(announced: false, screenshot: "partial-recovery-next-launch")
    }

    @MainActor
    private func verifyRecovery(announced: Bool, screenshot: String) throws {
        let app = try launchIsolated(startRoute: "sessions")
        defer { terminate(app) }
        let id = try XCTUnwrap(ProcessInfo.processInfo.environment["JOVRA_PARTIAL_RECOVERY_SESSION_ID"])
        XCTAssertEqual(UUID(uuidString: id)?.uuidString, id)
        // T17: the launch that adopts the recovery says so in the recovered-recording sheet, once.
        let sheet = app.staticTexts["recovery.title"]
        XCTAssertEqual(sheet.waitForExistence(timeout: announced ? 20 : 3), announced)
        if announced {
            XCTAssertEqual(sheet.label, "Recording partially recovered")
            XCTAssertTrue(app.staticTexts["recovery.unrecoverable.0"].label.hasPrefix("Part 1: "))
            app.buttons["recovery.done"].tap()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        }
        let row = app.buttons["library.session.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertTrue(row.label.contains("Partial recovery fixture"))
        XCTAssertTrue(row.label.contains("Sample"))
        XCTAssertTrue(row.label.contains("Partially saved"))
        let notice = app.staticTexts["Recording partially recovered"]
        XCTAssertEqual(notice.exists, announced)
        XCTAssertFalse(app.staticTexts["Recovery needs attention"].exists)
        attachScreenshot(app, name: screenshot)
        for _ in 0..<4 {
            if row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(app.heading("Smart replay").waitForExistence(timeout: 10))
        let frame = app.staticTexts["replay.frame"]
        XCTAssertTrue(frame.waitForExistence(timeout: 20))
        XCTAssertTrue(frame.label.hasPrefix("f 0 ·"))
        app.buttons["replay.frame.next"].tap()
        let nextFrame = NSPredicate { _, _ in frame.label.hasPrefix("f 1 ·") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: nextFrame, object: nil)], timeout: 10), .completed)
        XCTAssertFalse(app.staticTexts["replay.error"].exists)
    }

    @MainActor
    private func launchIsolated(startRoute: String) throws -> XCUIApplication {
        let token = ProcessInfo.processInfo.environment["JOVRA_PARTIAL_RECOVERY_TOKEN"]
        try XCTSkipUnless(token != nil, "This phase requires a dedicated simulator and isolated app bundle.")
        let value = try XCTUnwrap(token)
        XCTAssertNotNil(value.range(of: "^[a-f0-9]{12}$", options: .regularExpression))
        let app = XCUIApplication(bundleIdentifier: "com.islanddevcrew.jovra.partial-recovery-\(value)")
        app.launchArguments = ["-demo", "off", "-startRoute", startRoute]
        XCTAssertEqual(app.state, .notRunning)
        app.launch()
        return app
    }

    @MainActor
    private func terminate(_ app: XCUIApplication) {
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    @MainActor
    private func savedSeconds(_ element: XCUIElement) -> Int {
        guard element.exists else { return 0 }
        return Self.savedSeconds(in: element.label)
    }

    private nonisolated static func savedSeconds(in label: String) -> Int {
        let time = label.split(separator: " ").last?.split(separator: ":").compactMap { Int($0) }
        return time?.reduce(0) { $0 * 60 + $1 } ?? 0
    }

    @MainActor
    private func waitForSavedSeconds(_ element: XCUIElement, atLeast seconds: Int) {
        let predicate = NSPredicate { _, _ in
            element.exists && Self.savedSeconds(in: element.label) >= seconds
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 15), .completed)
    }
}
#endif
