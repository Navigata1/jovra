import XCTest

/// T14: the shared player, video surface, jog strip and transport, driven through the DEBUG video lab on the
/// bundled frame-counter fixtures and the synthetic sample match.
final class PlaybackCoreUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func launchLab(_ source: String = "fc-060", contentSize: ContentSize? = .large,
                           appearance: LaunchConfiguration.Appearance = .light) -> XCUIApplication {
        let app = XCUIApplication.jovra(contentSize: contentSize) { $0.appearance = appearance }
        app.launchEnvironment["JOVRA_VIDEO_LAB"] = source
        app.launch()
        XCTAssertTrue(app.staticTexts["screen.title"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor private func waitForValue(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.value as? String == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.value as? String == expected
    }

    @MainActor private func readout(_ app: XCUIApplication) -> String {
        let readout = element(app, "playback.readout")
        return (readout.value as? String) ?? readout.label
    }

    /// The frame number the readout shows ("f 12 · 0:00.20 · 60 fps" → 12).
    @MainActor private func readoutFrame(_ app: XCUIApplication) -> Int? {
        let text = readout(app)
        guard let range = text.range(of: #"f [0-9,]+"#, options: .regularExpression) else { return nil }
        return Int(text[range].dropFirst(2).replacingOccurrences(of: ",", with: ""))
    }

    @MainActor private func waitForReadout(_ app: XCUIApplication, frame: Int, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if readoutFrame(app) == frame { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return readoutFrame(app) == frame
    }

    // MARK: Layout and the adjustable jog strip

    @MainActor
    func testJogStripIsTallClearOfTheTimelineAboveTransportAndScrubsByFrame() throws {
        let app = launchLab()
        let jog = element(app, "playback.jog")
        XCTAssertTrue(jog.waitForExistence(timeout: 10))
        let timeline = element(app, "playback.timeline")
        let play = element(app, "transport.playPause")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(jog.frame.height, 48, "the jog strip is at least 48 pt tall")
        XCTAssertGreaterThanOrEqual(jog.frame.minY - timeline.frame.maxY, 16, "at least 16 pt below the timeline")
        XCTAssertGreaterThan(play.frame.minY, jog.frame.maxY, "the jog strip sits above the transport row")
        XCTAssertLessThan(jog.frame.maxY, window.maxY - 60, "never at the bottom edge")
        attachScreenshot(app, name: "s10-light-lab-layout")

        XCTAssertTrue(waitForReadout(app, frame: 0))
        XCTAssertEqual(jog.label, "Jog strip")
        XCTAssertTrue((jog.value as? String)?.hasPrefix("Frame 0,") == true, String(describing: jog.value))
        // A finger drag of 40 pt to the left is five frames forward at 8 pt per frame (chase seek, exact on release).
        let start = jog.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -40, dy: 0)))
        let landed = try XCTUnwrap(readoutFrame(app))
        XCTAssertTrue((3...6).contains(landed), "drag scrubbed about five frames forward: \(readout(app))")
        XCTAssertTrue((jog.value as? String)?.hasPrefix("Frame \(landed),") == true, "VoiceOver hears the frame: \(String(describing: jog.value))")
        // The VoiceOver increment itself (one frame per adjust) is proven in the hosted JogStripAccessibilityTests:
        // XCUITest on iOS has no API to send an accessibility increment to an adjustable element.
    }

    // MARK: Keyboard

    @MainActor
    func testSpaceTogglesPlaybackAndRightArrowStepsOneFrame() throws {
        let app = launchLab("fc-240")
        let play = element(app, "transport.playPause")
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForReadout(app, frame: 0))
        XCTAssertEqual(play.label, "Play")
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(play.wait(for: \.label, toEqual: "Pause", timeout: 3), "space started playback")
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(play.wait(for: \.label, toEqual: "Play", timeout: 3))
        let paused = try XCTUnwrap(readoutFrame(app))
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitForReadout(app, frame: min(paused + 1, 479)), "→ stepped one frame from \(paused): \(readout(app))")
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(waitForReadout(app, frame: paused), "← stepped back to \(paused): \(readout(app))")
    }

    // MARK: Rate, loop and hold-to-repeat

    @MainActor
    func testRateChangesShowInTheReadout() throws {
        let app = launchLab()
        let rate = element(app, "transport.rate")
        XCTAssertTrue(rate.waitForExistence(timeout: 10))
        XCTAssertFalse(readout(app).contains("×"), "1× is not repeated in the readout")
        rate.tap()
        element(app, "transport.rate.0.5").tap()
        XCTAssertTrue(readout(app).contains("0.5×"), readout(app))
        attachScreenshot(app, name: "s10-light-lab-half-rate")
        rate.tap()
        element(app, "transport.rate.2.0").tap()
        XCTAssertTrue(readout(app).contains("2×"), readout(app))
    }

    @MainActor
    func testABLoopKeepsPlaybackBetweenAAndB() throws {
        let app = launchLab()
        let next = element(app, "transport.nextFrame")
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        for _ in 0..<20 { next.tap() }
        XCTAssertTrue(waitForReadout(app, frame: 20))
        let loop = element(app, "transport.loop")
        loop.tap()                                   // A = 20
        for _ in 0..<15 { next.tap() }
        XCTAssertTrue(waitForReadout(app, frame: 35))
        loop.tap()                                   // B = 35
        XCTAssertEqual(loop.label, "Clear loop")
        element(app, "transport.playPause").tap()
        var seen: [Int] = []
        let end = Date().addingTimeInterval(1.6)
        while Date() < end {
            if let frame = readoutFrame(app) { seen.append(frame) }
        }
        element(app, "transport.playPause").tap()
        XCTAssertFalse(seen.isEmpty)
        XCTAssertTrue(seen.allSatisfy { (19...36).contains($0) }, "playback stayed inside A–B ± 1 frame: \(seen)")
        XCTAssertGreaterThan(Set(seen).count, 3, "the loop actually played: \(Set(seen).sorted())")
    }

    @MainActor
    func testHoldingNextFrameRepeats() throws {
        let app = launchLab()
        let next = element(app, "transport.nextFrame")
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.press(forDuration: 1.5)
        let frame = try XCTUnwrap(readoutFrame(app))
        XCTAssertGreaterThan(frame, 3, "holding repeated the step (frame \(frame))")
    }

    // MARK: Zoom

    @MainActor
    func testPinchZoomPersistsWhileSteppingResetsAndMatchesTheAccessibleControl() throws {
        let app = launchLab()
        let surface = element(app, "video.surface")
        let zoom = element(app, "video.zoom")
        XCTAssertTrue(zoom.waitForExistence(timeout: 10))
        XCTAssertEqual(zoom.value as? String, "100%")
        surface.pinch(withScale: 8, velocity: 4)
        XCTAssertTrue(waitForValue(zoom, "400%"), "a pinch tops out at 400%: \(String(describing: zoom.value))")
        let pinched = zoom.value as? String
        element(app, "transport.nextFrame").tap()
        element(app, "transport.nextFrame").tap()
        XCTAssertTrue(waitForReadout(app, frame: 2))
        element(app, "transport.previousFrame").tap()
        XCTAssertTrue(waitForReadout(app, frame: 1))
        XCTAssertEqual(zoom.value as? String, pinched, "zoom persists while stepping")
        attachScreenshot(app, name: "s10-light-lab-zoomed")
        element(app, "video.zoom.reset").tap()
        XCTAssertTrue(waitForValue(zoom, "100%"))
        XCTAssertFalse(element(app, "video.zoom.reset").exists, "reset is offered only while zoomed")

        // The accessible control reaches the same range: every level up to the pinch maximum and back.
        var levels: [String] = []
        let zoomIn = element(app, "video.zoom.in"), zoomOut = element(app, "video.zoom.out")
        for _ in 0..<4 {
            zoomIn.tap()
            levels.append(zoom.value as? String ?? "")
        }
        XCTAssertEqual(levels, ["150%", "200%", "300%", "400%"], "the control steps to the pinch maximum")
        XCTAssertFalse(zoomIn.isEnabled, "no level beyond what a pinch reaches")
        zoomOut.tap()
        XCTAssertEqual(zoom.value as? String, "300%")
        while zoomOut.isEnabled { zoomOut.tap() }
        XCTAssertEqual(zoom.value as? String, "100%")
    }

    // MARK: States and badges

    @MainActor
    func testAMissingFileShowsAStateCardInsteadOfCrashing() throws {
        let app = launchLab("missing")
        XCTAssertTrue(app.staticTexts["Video missing"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["The original isn't on this iPhone."].exists)
        XCTAssertFalse(element(app, "playback.jog").exists)
        XCTAssertEqual(app.state, .runningForeground)
        try auditScreen(app)
        attachScreenshot(app, name: "s10-light-lab-missing")
    }

    @MainActor
    func testSampleMediaCarriesTheSyntheticSampleBadge() throws {
        let app = launchLab("sample")
        let badge = element(app, "video.sample")
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
        XCTAssertEqual(badge.label, "Sample video (synthetic)")
        XCTAssertTrue(element(app, "playback.jog").waitForExistence(timeout: 15), "the 54:00 sample match opened")
        XCTAssertTrue(readout(app).contains("60 fps"), readout(app))
        attachScreenshot(app, name: "s10-light-lab-sample")
    }

    // MARK: Accessibility audit

    @MainActor
    func testAccessibilityAuditInLightDarkAndAX5PortraitAndLandscape() throws {
        let cases: [(String, LaunchConfiguration.Appearance, ContentSize)] = [
            ("light", .light, .large), ("dark", .dark, .large), ("ax5", .light, .accessibility5),
        ]
        for (slug, appearance, size) in cases {
            for landscape in [false, true] {
                XCUIDevice.shared.orientation = .portrait
                let app = launchLab("fc-060", contentSize: size, appearance: appearance)
                XCTAssertTrue(element(app, "playback.jog").waitForExistence(timeout: 10))
                if landscape {
                    XCUIDevice.shared.orientation = .landscapeLeft
                    let window = app.windows.firstMatch
                    let jog = element(app, "playback.jog"), video = element(app, "video.surface")
                    // Landscape layout: the video leads, the timeline/jog/transport panel trails.
                    let laidOut = NSPredicate { _, _ in
                        window.frame.width > window.frame.height && jog.frame.minX > video.frame.maxX
                    }
                    _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: laidOut, object: nil)], timeout: 8)
                    XCTAssertGreaterThan(window.frame.width, window.frame.height, "the app rotated")
                    XCTAssertGreaterThan(jog.frame.minX, video.frame.maxX, "video leading, controls trailing: jog \(jog.frame), video \(video.frame), window \(window.frame)")
                }
                assertNothingSpillsSideways(app)
                try auditScreen(app)
                let name = "s10-\(slug)-lab-\(landscape ? "landscape" : "portrait")"
                if landscape { attachLandscapeScreenshot(name: name) } else { attachScreenshot(app, name: name) }
                app.terminate()
            }
        }
        XCUIDevice.shared.orientation = .portrait
        let sample = launchLab("sample", contentSize: .accessibility5, appearance: .dark)
        XCTAssertTrue(element(sample, "playback.jog").waitForExistence(timeout: 15))
        try auditScreen(sample)
        attachScreenshot(sample, name: "s10-ax5-dark-lab-sample")
    }

    /// Nothing scrolls horizontally: every control lies within the window's width.
    @MainActor
    private func assertNothingSpillsSideways(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        for id in ["screen.title", "video.surface", "video.sample", "playback.timeline", "playback.jog", "playback.readout",
                   "transport.rate", "transport.previousFrame", "transport.playPause", "transport.nextFrame",
                   "transport.loop", "transport.back10", "transport.forward10", "video.zoom.in", "video.zoom.out"] {
            let frame = element(app, id).frame
            XCTAssertTrue(frame.minX >= window.minX - 0.5 && frame.maxX <= window.maxX + 0.5,
                          "\(id) at \(frame) leaves the \(window.width) pt window", file: file, line: line)
        }
    }

    /// `app.screenshot()` crops a rotated app wrongly on this simulator runtime. The screen capture is right but
    /// carries its rotation as image orientation, which the attachment's PNG drops; drawing it bakes it in.
    @MainActor
    private func attachLandscapeScreenshot(name: String) {
        let image = XCUIScreen.main.screenshot().image
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        let attachment = XCTAttachment(image: upright)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
