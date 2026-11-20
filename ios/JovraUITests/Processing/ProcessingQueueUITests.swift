import XCTest

/// T27: the processing route after a real fixture-camera recording (the seeded session), driven by the
/// fixture analyzer (`-processingAnalyzer`), which moves progress only and writes no results.
final class ProcessingQueueUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testStageTimelineProgressesViewSessionIsReadyBeforeAnalysisEndsAndPauseHoldsUntilResume() throws {
        let app = XCUIApplication.launchJovra {
            $0.appearance = .light
            $0.library = .fresh
            $0.processingAnalyzer = .steady
        }
        recordAndOpenProcessing(app, title: "Processing " + UUID().uuidString.prefix(6))

        let saved = stage("saved", in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertTrue(value(of: saved).hasPrefix("Done"), "the original is saved before anything else: \(value(of: saved))")
        XCTAssertTrue(waitFor(stage("prepareReplay", in: app), toStartWith: "Done", timeout: 20), "prepare replay finishes")

        let analyze = stage("analyze", in: app)
        XCTAssertTrue(waitFor(analyze, toStartWith: "In progress", timeout: 15), "analysis starts: \(value(of: analyze))")
        let view = app.buttons["processing.viewSession"]
        XCTAssertTrue(view.isEnabled, "View session is available while analysis is still running")
        XCTAssertTrue(app.descendants(matching: .any)["processing.status.path"].exists,
                      "while analysis runs the screen says what happens if you leave JOVRA")
        XCTAssertTrue(app.staticTexts["Recording is safe."].exists || app.otherElements["processing.safe"].exists)
        attachScreenshot(app, name: "s07-processing-light-analyzing")

        let pause = app.buttons["processing.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        XCTAssertTrue(waitFor(analyze, toStartWith: "Paused", timeout: 10), "pause holds the stage: \(value(of: analyze))")
        let heldAt = percent(in: value(of: analyze))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(percent(in: value(of: analyze)), heldAt, "a paused analysis does not move")
        attachScreenshot(app, name: "s07-processing-light-paused")

        app.buttons["processing.resume"].tap()
        let moved = NSPredicate { _, _ in
            let current = self.value(of: analyze)
            return current.hasPrefix("In progress") && (self.percent(in: current) ?? -1) > (heldAt ?? 100)
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 15), .completed,
                       "resume continues from where it stopped: \(value(of: analyze))")
        XCTAssertTrue(value(of: stage("backup", in: app)).contains("Awaiting Google Drive setup"))

        // Watching does not wait for analysis: View session opens the original while it is still running.
        XCTAssertTrue(value(of: analyze).hasPrefix("In progress"))
        for _ in 0..<6 where !view.isHittable { app.swipeUp() }
        view.tap()
        XCTAssertTrue(app.buttons["replay.play"].waitForExistence(timeout: 15), "View session opens the video mid-analysis")
        XCTAssertTrue(app.staticTexts["replay.frame"].waitForExistence(timeout: 20), "and its frames decode")
    }

    @MainActor
    func testAnInjectedAnalysisFailureShowsRetryWhileTheVideoStillPlays() throws {
        let app = XCUIApplication.launchJovra {
            $0.appearance = .light
            $0.library = .fresh
            $0.processingAnalyzer = .failsOnce
        }
        recordAndOpenProcessing(app, title: "Failure " + UUID().uuidString.prefix(6))
        let analyze = stage("analyze", in: app)
        XCTAssertTrue(waitFor(analyze, toStartWith: "Failed", timeout: 30), "the injected failure is shown: \(value(of: analyze))")
        XCTAssertTrue(value(of: analyze).contains("Your video is safe and still plays"))
        let retry = app.buttons["processing.retry"]
        XCTAssertTrue(retry.exists, "a failed analysis offers Retry")
        XCTAssertTrue(app.buttons["processing.viewSession"].isEnabled, "the video stays viewable after the failure")
        XCTAssertTrue(value(of: stage("prepareReplay", in: app)).hasPrefix("Done"), "the failure leaves the other stages alone")
        attachScreenshot(app, name: "s07-processing-light-failed")
        // The full accessibility audit runs on the settled screens (unavailable and demo, in light, dark
        // and AX5); here the retry control's size is checked.
        assertHitTargets(in: app)

        retry.tap()
        XCTAssertTrue(waitFor(analyze, toStartWith: "In progress", timeout: 10), "Retry starts analysis again")
        XCTAssertTrue(waitFor(analyze, toStartWith: "Done", timeout: 40), "the retried analysis finishes: \(value(of: analyze))")

        // The video plays: View session opens the original in Replay and its frames decode.
        let view = app.buttons["processing.viewSession"]
        for _ in 0..<6 where !view.isHittable { app.swipeUp() }
        view.tap()
        XCTAssertTrue(app.buttons["replay.play"].waitForExistence(timeout: 15), "View session opens the video")
        XCTAssertTrue(app.staticTexts["replay.frame"].waitForExistence(timeout: 20), "and the original decodes and plays")
    }

    @MainActor
    func testWithNoAnalyzerRegisteredAnalysisIsUnavailableInLightDarkAndAX5() throws {
        let variants: [(LaunchConfiguration.Appearance, ContentSize?, String)] = [
            (.light, nil, "light"), (.dark, nil, "dark"), (.light, .accessibility5, "ax5"),
        ]
        for (appearance, size, variant) in variants {
            let app = XCUIApplication.launchJovra(contentSize: size) {
                $0.appearance = appearance
                $0.library = .fresh
            }
            recordAndOpenProcessing(app, title: "Unavailable \(variant) " + UUID().uuidString.prefix(4))
            let analyze = stage("analyze", in: app)
            XCTAssertTrue(waitFor(analyze, toStartWith: "Unavailable", timeout: 20), "\(variant): \(value(of: analyze))")
            XCTAssertTrue(value(of: analyze).contains("no automatic analysis is installed"), "the reason is stated")
            XCTAssertTrue(waitFor(stage("prepareReplay", in: app), toStartWith: "Done", timeout: 20))
            XCTAssertTrue(app.buttons["processing.viewSession"].isEnabled)
            XCTAssertFalse(app.buttons["processing.pause"].exists, "nothing to pause when nothing can run")
            XCTAssertFalse(app.descendants(matching: .any)["processing.status.path"].exists, "no background promise when nothing runs")
            XCTAssertTrue(app.descendants(matching: .any)["processing.sample"].exists, "fixture footage stays labelled Sample")
            attachScreenshot(app, name: "s07-processing-\(variant)-unavailable")
            let view = app.buttons["processing.viewSession"]
            for _ in 0..<8 where !app.descendants(matching: .any)["processing.status.wifi"].isHittable { app.swipeUp() }
            XCTAssertLessThanOrEqual(view.frame.maxX, app.frame.maxX + 1, "\(variant): nothing runs off the right edge")
            XCTAssertGreaterThanOrEqual(view.frame.minX, app.frame.minX - 1, "\(variant): nothing runs off the left edge")
            attachScreenshot(app, name: "s07-processing-\(variant)-unavailable-actions")
            assertHitTargets(in: app)
            try auditScreen(app, scrollIdentifier: "processing.scroll")
            app.terminate()
        }
    }

    /// The simulator can set neither Low Power Mode nor the thermal state, so the device state is
    /// injected (`-processingDevice`). With no analyzer registered the hold must not turn an analysis
    /// this build cannot run into one that only seems to wait.
    @MainActor
    func testWithNoAnalyzerAnalysisIsUnavailableEvenWhileLowPowerModeOrHeatHoldsTheQueue() throws {
        let variants: [(LaunchConfiguration.ProcessingDevice, String, String)] = [
            (.lowPowerOnBattery, "low-power", "Waiting for a charger while Low Power Mode is on"),
            (.tooWarm, "too-warm", "Waiting for your iPhone to cool down"),
        ]
        for (device, variant, holdCopy) in variants {
            let app = XCUIApplication.launchJovra {
                $0.appearance = .light
                $0.library = .fresh
                $0.processingDevice = device
            }
            recordAndOpenProcessing(app, title: "Held \(variant) " + UUID().uuidString.prefix(4))
            let analyze = stage("analyze", in: app)
            XCTAssertTrue(waitFor(analyze, toStartWith: "Unavailable", timeout: 20), "\(variant): \(value(of: analyze))")
            XCTAssertTrue(value(of: analyze).contains("no automatic analysis is installed"), "\(variant): the reason is stated")
            XCTAssertFalse(value(of: analyze).contains(holdCopy), "\(variant): no waiting copy for analysis that cannot run")
            if device == .tooWarm {
                XCTAssertTrue(value(of: stage("prepareReplay", in: app)).contains(holdCopy),
                              "the hold still shows where it applies: \(value(of: stage("prepareReplay", in: app)))")
            } else {
                XCTAssertTrue(waitFor(stage("prepareReplay", in: app), toStartWith: "Done", timeout: 20),
                              "Low Power Mode holds analysis only")
            }
            XCTAssertFalse(app.buttons["processing.pause"].exists, "\(variant): no Pause analysis")
            XCTAssertFalse(app.descendants(matching: .any)["processing.status.path"].exists,
                           "\(variant): no 'Runs on this iPhone' line")
            XCTAssertTrue(app.buttons["processing.viewSession"].isEnabled, "\(variant): the video stays viewable")
            attachScreenshot(app, name: "s07-processing-light-unavailable-\(variant)")
            app.terminate()
        }
    }

    @MainActor
    func testTheDemoShowsDemoProcessingStateInLightDarkAndAX5() throws {
        let variants: [(LaunchConfiguration.Appearance, ContentSize?, String)] = [
            (.light, nil, "light"), (.dark, nil, "dark"), (.light, .accessibility5, "ax5"),
        ]
        for (appearance, size, variant) in variants {
            let app = XCUIApplication.launchJovra(contentSize: size) {
                $0.appearance = appearance
                $0.demo = .sample
                $0.startRoute = "processing"
            }
            XCTAssertTrue(app.heading("Processing").waitForExistence(timeout: 8))
            XCTAssertTrue(app.descendants(matching: .any)["processing.demo"].exists, "\(variant): the demo is labelled")
            XCTAssertTrue(app.staticTexts["Demo processing state"].exists)
            XCTAssertTrue(value(of: stage("analyze", in: app)).contains("62"), "the brief's sample value, labelled as demo")
            attachScreenshot(app, name: "s07-processing-\(variant)-demo")
            let title = app.heading("Processing")
            XCTAssertGreaterThanOrEqual(title.frame.minX, app.frame.minX - 1, "\(variant): the title stays on screen")
            try auditScreen(app, scrollIdentifier: "processing.scroll")
            app.terminate()
        }
    }

    // MARK: Helpers

    /// Records a short fixture-camera singles session, stops it and opens its processing route.
    @MainActor private func recordAndOpenProcessing(_ app: XCUIApplication, title: String) {
        app.buttons["tab.record"].tap()
        for (id, text) in [("capture.setup.title", title), ("capture.setup.playerA", "Jon"), ("capture.setup.playerB", "Alex")] {
            let field = app.textFields[id]
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(text + "\n")
        }
        let preview = app.buttons["record.previewCapture"]
        // At large text sizes the button can sit under the floating tab bar while still "hittable".
        let tabBar = app.otherElements["tabBar"]
        for _ in 0..<8 where !preview.isHittable || (tabBar.exists && preview.frame.maxY > tabBar.frame.minY - 8) {
            app.swipeUp()
        }
        preview.tap()
        let start = app.buttons["capture.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        for _ in 0..<6 where !start.isHittable { app.swipeUp() }
        start.tap()
        let savedThrough = app.staticTexts["capture.confirmedTime"]
        XCTAssertTrue(savedThrough.waitForExistence(timeout: 15))
        let stop = app.buttons["capture.stop"]
        for _ in 0..<6 where !stop.isHittable { app.swipeUp() }
        stop.tap()
        let confirm = app.buttons.matching(identifier: "capture.confirmStop").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let processing = app.buttons["capture.processing"]
        XCTAssertTrue(processing.waitForExistence(timeout: 20))
        for _ in 0..<6 where !processing.isHittable { app.swipeUp() }
        processing.tap()
        XCTAssertTrue(app.heading("Processing").waitForExistence(timeout: 10))
    }

    @MainActor private func stage(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["processing.stage.\(id)"]
    }

    @MainActor private func value(of element: XCUIElement) -> String {
        (element.value as? String) ?? ""
    }

    @MainActor private func waitFor(_ element: XCUIElement, toStartWith prefix: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { _, _ in self.value(of: element).hasPrefix(prefix) }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed
    }

    /// The whole percentage in a stage's value ("In progress, 42%, …"), if any.
    private func percent(in value: String) -> Int? {
        guard let range = value.range(of: #"\d+(?=\s?%)"#, options: .regularExpression) else { return nil }
        return Int(value[range])
    }
}
