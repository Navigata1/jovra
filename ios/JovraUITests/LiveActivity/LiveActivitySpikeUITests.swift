import XCTest

/// T60 SPIKE (throwaway branch). Observes the recording Live Activity from SpringBoard on the simulator:
/// the Notification Centre banner over a foreground recording, the Lock Screen after locking, and the
/// stale state after the app dies mid-recording. Simulator observations only; hardware is separate.
final class LiveActivitySpikeUITests: XCTestCase {
    @MainActor private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }
    private var samples: [String] = []
    private var started = Date()

    @MainActor override func setUp() async throws {
        continueAfterFailure = true; samples = []; started = Date()
        unlockIfNeeded()
    }

    /// The previous test may leave the simulator locked.
    @MainActor private func unlockIfNeeded() {
        XCUIDevice.shared.press(.home)
        sleep(1)
        let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
        bottom.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        sleep(1)
    }

    /// Foreground recording: pull Notification Centre down over the recorder (the app goes inactive, not
    /// background, so recording continues) and sample the activity's accessible text once a second.
    @MainActor
    func testForegroundRecordingUpdatesTheActivity() throws {
        let app = startRecording()
        XCTAssertTrue(app.staticTexts["capture.confirmedTime"].waitForExistence(timeout: 12))
        // 20 s of plain foreground recording: the app log records the update cadence.
        sleep(20)
        snap("t60-01-app-recording")
        openNotificationCentre(app)
        let banner = activityElement()
        XCTAssertTrue(banner.waitForExistence(timeout: 8), "no Live Activity visible in Notification Centre")
        snap("t60-02-notification-centre-recording")
        let allow = springboard.buttons["Allow"]
        if allow.exists { allow.tap(); record("tapped Allow on the Live Activities prompt") }
        sample(for: 16, label: "nc-foreground")
        snap("t60-03-notification-centre-recording-later")
        closeNotificationCentre(app)
        XCTAssertTrue(app.staticTexts["capture.phase"].waitForExistence(timeout: 5))
        record("app phase after NC: \(app.staticTexts["capture.phase"].label); saved: \(app.staticTexts["capture.confirmedTime"].label)")
        // Lock the device: the app backgrounds, CaptureScreen pauses, and the Lock Screen shows the paused activity.
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        sleep(3)
        snap("t60-04-lock-screen-after-lock")
        sample(for: 4, label: "lock-screen")
        dump("t60-cadence-foreground")
    }

    /// The app dies mid-recording (stand-in for a crash or jetsam kill): with no heartbeat the activity's
    /// stale date passes and it renders "Status unknown" with no further update from the app.
    @MainActor
    func testMissingHeartbeatShowsStatusUnknown() throws {
        let app = startRecording()
        XCTAssertTrue(app.staticTexts["capture.confirmedTime"].waitForExistence(timeout: 12))
        sleep(3)
        app.terminate()
        record("app terminated")
        XCUIDevice.shared.press(.home)
        openNotificationCentre(springboard)
        let banner = activityElement()
        XCTAssertTrue(banner.waitForExistence(timeout: 8), "no Live Activity visible after the app died")
        snap("t60-05-after-kill-before-stale")
        sample(for: 50, label: "after-kill")
        let unknown = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Status unknown'")).firstMatch
        if !unknown.waitForExistence(timeout: 5) { record("OBSERVED: no 'Status unknown' rendered") }
        snap("t60-06-status-unknown")
        dump("t60-cadence-stale")
    }

    // MARK: - Helpers

    @MainActor private func startRecording() -> XCUIApplication {
        let app = XCUIApplication.launchJovra { $0.demo = .off }
        // Scene continuity may restore the capture screen from an earlier run: close it first.
        if app.buttons["capture.close"].waitForExistence(timeout: 3) { app.buttons["capture.close"].tap() }
        XCTAssertTrue(app.buttons["tab.record"].waitForExistence(timeout: 5))
        app.buttons["tab.record"].tap()
        for (identifier, value) in [("capture.setup.title", "Court session"), ("capture.setup.playerA", "Player A"), ("capture.setup.playerB", "Player B")] {
            let field = app.textFields[identifier]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText(value + "\n")
        }
        app.swipeUp()
        app.buttons["record.previewCapture"].tap()
        XCTAssertTrue(app.buttons["capture.start"].waitForExistence(timeout: 10))
        app.buttons["capture.start"].tap()
        record("start tapped")
        return app
    }

    @MainActor private func activityElement() -> XCUIElement {
        springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'REC' OR label CONTAINS 'Status unknown' OR label CONTAINS 'Paused' OR label CONTAINS 'Saved'"))
            .firstMatch
    }

    @MainActor private func openNotificationCentre(_ over: XCUIApplication) {
        let top = over.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.005))
        top.press(forDuration: 0.1, thenDragTo: over.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75)))
        sleep(1)
        record("notification centre opened")
    }

    @MainActor private func closeNotificationCentre(_ app: XCUIApplication) {
        let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        bottom.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        sleep(1)
        record("notification centre closed; app state \(app.state.rawValue)")
    }

    @MainActor private func sample(for seconds: Int, label: String) {
        for _ in 0..<seconds {
            let labels = springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS 'REC' OR label CONTAINS 'Status unknown' OR label CONTAINS 'Paused' OR label CONTAINS 'Saved'"))
                .allElementsBoundByIndex.prefix(3).map(\.label)
            record("\(label): \(labels.joined(separator: " | "))")
            sleep(1)
        }
    }

    private func record(_ line: String) {
        samples.append(String(format: "t+%6.2fs  %@", Date().timeIntervalSince(started), line))
    }

    @MainActor private func snap(_ name: String) {
        record("screenshot \(name)")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dump(_ name: String) {
        let attachment = XCTAttachment(string: samples.joined(separator: "\n"))
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
