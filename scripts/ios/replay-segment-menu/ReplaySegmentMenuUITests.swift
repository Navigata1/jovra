import XCTest

/// Runs only in the generated alternate simulator test target. The app seeds its own fixture.
final class ReplaySegmentMenuUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testActualMenuOpensLaterSegmentAfterTheFirstIsUnavailable() throws {
        let sessionID = "03268C75-58B5-4495-8C78-38929FBA1C63"
        #if !targetEnvironment(simulator)
        throw XCTSkip("the owned-container segment menu probe runs on the simulator only")
        #endif
        let token = try XCTUnwrap(ProcessInfo.processInfo.environment["JOVRA_SEGMENT_MENU_PROBE_TOKEN"])
        let runID = try XCTUnwrap(UUID(uuidString: token))
        XCTAssertEqual(runID.uuidString.lowercased(), token)
        let bundle = "com.islanddevcrew.jovra.menuprobe" + token.replacingOccurrences(of: "-", with: "")
        let app = XCUIApplication(bundleIdentifier: bundle)
        var launch = LaunchConfiguration()
        launch.startRoute = "sessions"
        app.launchArguments = launch.arguments + ["-UIPreferredContentSizeCategoryName", ContentSize.large.rawValue]
        app.launchEnvironment = ["JOVRA_SEGMENT_MENU_APP_TOKEN": token]
        app.launch()
        let row = app.buttons.matching(identifier: "library.session.\(sessionID)")
        try tapUnique(row, in: app, named: "the exclusively seeded session")
        XCTAssertFalse(app.staticTexts["segment-menu.seed.refused"].exists)

        let replay = app.scrollViews["replay.scroll"]
        XCTAssertTrue(replay.waitForExistence(timeout: 10))
        let unavailable = replay.staticTexts["replay.error"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10))
        XCTAssertFalse(replay.buttons["replay.play"].exists)

        let laterOption = app.buttons.matching(NSPredicate(format: "label == %@", "Segment 2"))
        XCTAssertEqual(laterOption.count, 0, "the second menu item is absent before opening the picker")
        let picker = replay.buttons.matching(NSPredicate(format: "label == %@", "Recording segment, Segment 1"))
        try tapUnique(picker, in: app, named: "the segment picker in Replay")
        try tapUnique(laterOption, in: app, named: "Segment 2 in the newly opened system menu")

        let frame = replay.staticTexts["replay.frame"]
        XCTAssertTrue(frame.waitForExistence(timeout: 15))
        XCTAssertTrue(frame.label.hasPrefix("f 0 ·"), "the later original starts at its own frame zero")
        XCTAssertFalse(unavailable.exists)
        XCTAssertTrue(replay.buttons["replay.play"].exists)
        let selection = replay.buttons.matching(NSPredicate(format: "label == %@", "Recording segment, Segment 2"))
        XCTAssertTrue(selection.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(selection.count, 1)
        let next = replay.buttons.matching(identifier: "replay.frame.next")
        XCTAssertTrue(next.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(next.count, 1)
        let viewport = replay.frame.intersection(app.windows.firstMatch.frame)
        XCTAssertFalse(viewport.isEmpty)
        XCTAssertGreaterThanOrEqual(next.firstMatch.frame.minY, viewport.maxY,
                                    "the retained run placed Next frame below the Replay scroll viewport")
        XCTAssertFalse(next.firstMatch.isHittable)
        replay.swipeUp()
        let revealedViewport = replay.frame.intersection(app.windows.firstMatch.frame)
        XCTAssertEqual(next.count, 1)
        XCTAssertTrue(revealedViewport.contains(next.firstMatch.frame), "one scroll reveals the same Next frame control")
        try tapUnique(next, in: app, named: "Next frame")
        let decodedNext = NSPredicate { _, _ in frame.label.hasPrefix("f 1 ·") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: decodedNext, object: nil)], timeout: 8), .completed)
    }

    @MainActor
    private func tapUnique(_ query: XCUIElementQuery, in app: XCUIApplication, named name: String) throws {
        let first = query.firstMatch
        guard first.waitForExistence(timeout: 10), query.count == 1, first.isHittable else {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Replay menu scope at refusal"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Replay menu screen at refusal"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            return XCTFail("Expected exactly one hittable \(name).")
        }
        first.tap()
    }
}
