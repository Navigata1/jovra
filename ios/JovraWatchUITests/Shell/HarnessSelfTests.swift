import JovraRoom
import XCTest

/// The `-watchState` harness self-test (W03 acceptance): every registered state opens its surface, and an unknown
/// value fails with the listed error. The parsing and registry checks run without launching the app.
@MainActor
final class HarnessSelfTests: XCTestCase {
    private let registry = WatchStateRegistry.shared

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: Contract (no launch)

    func testEveryRegisteredValueRoundTripsThroughTheLaunchArguments() {
        XCTAssertFalse(registry.states.isEmpty)
        XCTAssertEqual(Set(registry.registeredValues).count, registry.states.count, "registered values are unique")
        for state in registry.states {
            let configuration = WatchLaunchConfiguration(watchState: state.id)
            XCTAssertEqual(WatchLaunchConfiguration(arguments: configuration.arguments), configuration,
                           "\(state.id) does not round-trip")
        }
        XCTAssertEqual(Set(registry.states.map(\.id.surface)), Set(WatchSurface.allCases),
                       "every surface has at least one registered state")
    }

    func testUnregisteredValuesAreProblemsNeverIgnored() {
        for value in ["health.nope", "nonsense", "health.", ".fresh", "court.fresh", "HEALTH.fresh"] {
            let parsed = WatchLaunchConfiguration(arguments: ["-watchState", value])
            XCTAssertNil(parsed.watchState, value)
            XCTAssertEqual(parsed.problems, [.unknownWatchState(value)], value)
        }
        XCTAssertEqual(WatchLaunchConfiguration(arguments: ["-watchState"]).problems, [.missingValue("-watchState")])
        XCTAssertEqual(WatchLaunchConfiguration(arguments: ["-reduceMotion", "maybe"]).problems,
                       [.invalidBoolean(key: "-reduceMotion", value: "maybe")])
        // The system's own arguments are not ours to judge.
        XCTAssertEqual(WatchLaunchConfiguration(arguments: ["-AppleLanguages", "(en)"]).problems, [])
    }

    func testEveryRecordAStateNamesDecodesStrictly() throws {
        let library = try WatchTestRecords.library()
        for state in registry.states {
            for step in state.steps {
                switch step {
                case .deliverNow(let record, _), .queue(let record):
                    let snapshot = try library.watchBridgeSnapshot(record)
                    XCTAssertTrue(snapshot.sample, "\(record) is sample data and must render the Sample label")
                case .flushQueue, .restartWatchProcess, .acknowledgeAlerts:
                    break
                }
            }
        }
    }

    func testCopyClipsToEighteenCharactersAndKeepsShortText() {
        XCTAssertEqual(WatchCopy.clip("Camera 3"), "Camera 3")
        XCTAssertEqual(WatchCopy.clip("Far baseline left corner"), "Far baseline left…")
        XCTAssertEqual(WatchCopy.clip("Far baseline left corner").count, WatchCopy.lineLimit)
    }

    // MARK: Launches

    func testEveryRegisteredStateOpensItsSurface() throws {
        for state in registry.states {
            let app = XCUIApplication.launchWatch(state: state.id)
            let surface = app.surface(state.id.surface)
            XCTAssertTrue(surface.waitForExistence(timeout: 10), "\(state.id) did not open \(state.id.surface)")
            XCTAssertFalse(app.descendants(matching: .any)["watch.harness.problems"].exists, "\(state.id)")
            if state.steps.isEmpty {
                XCTAssertTrue(app.descendants(matching: .any)["watch.waiting"].exists, "\(state.id) waits")
            } else {
                XCTAssertTrue(app.descendants(matching: .any)["watch.sample"].firstMatch.exists,
                              "\(state.id) is fed from a sample record and must say Sample")
            }
            keepScreenshot("w03-\(state.id.surface.rawValue)-\(state.id.state.lowercased())", of: app)
            try auditAccessibility(app)
            app.terminate()
        }
    }

    func testUnknownStateFailsWithTheListedError() {
        let app = XCUIApplication()
        app.launchArguments = ["-watchState", "health.doesNotExist"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["watch.harness.problems"].waitForExistence(timeout: 10))
        let problem = app.descendants(matching: .any)["watch.harness.problem"]
        XCTAssertTrue(problem.label.contains("unknown -watchState health.doesNotExist"), problem.label)
        for value in registry.registeredValues {
            XCTAssertTrue(app.descendants(matching: .any)["watch.harness.registered.\(value)"].exists,
                          "\(value) is not listed")
        }
        for surface in WatchSurface.allCases {
            XCTAssertFalse(app.surface(surface).exists, "no surface opens on an unknown state")
        }
        keepScreenshot("w03-harness-unknown-state", of: app)
    }

    func testPagesRunHealthScoreServeMarkTopToBottom() {
        let app = XCUIApplication.launchWatch(state: .init(surface: .health, state: "fresh"))
        XCTAssertTrue(app.surface(.health).waitForExistence(timeout: 10))
        for next in WatchSurface.pages.dropFirst() {
            XCTAssertTrue(app.swipeUp(toPage: next), "swiping up does not reach \(next)")
            keepScreenshot("w03-page-\(next.rawValue)", of: app)
        }
    }

    func testViewAllPushesEveryCamera() {
        let app = XCUIApplication.launchWatch(state: .init(surface: .health, state: "fresh"))
        let viewAll = app.buttons["watch.health.viewAll"]
        XCTAssertTrue(viewAll.waitForExistence(timeout: 10))
        viewAll.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watch.cameras"].waitForExistence(timeout: 5))
        for camera in ["c1", "c2", "c3", "c4", "c5", "c6"] {
            let row = app.descendants(matching: .any)["watch.camera.\(camera)"]
            XCTAssertTrue(row.waitForExistence(timeout: 2), camera)
        }
        let unknown = app.descendants(matching: .any)["watch.camera.c3"].label
        XCTAssertTrue(unknown.contains("status unknown") && unknown.contains("may still be recording"), unknown)
        keepScreenshot("w03-health-view-all", of: app)
    }

    func testAcknowledgeClosesTheAlertSheet() {
        let app = XCUIApplication.launchWatch(state: .init(surface: .alert, state: "cameraUnknown"))
        XCTAssertTrue(app.surface(.alert).waitForExistence(timeout: 10))
        app.buttons["watch.alert.acknowledge"].tap()
        XCTAssertTrue(app.surface(.alert).waitForNonExistence(timeout: 5), "the sheet stays after Acknowledge")
        XCTAssertTrue(app.surface(.health).waitForExistence(timeout: 5))
    }

    func testLargestTextSizeKeepsTheHealthShellReadable() throws {
        let app = XCUIApplication()
        app.launchArguments = WatchLaunchConfiguration(watchState: .init(surface: .health, state: "fresh")).arguments
            + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.surface(.health).waitForExistence(timeout: 10))
        keepScreenshot("w03-health-fresh-ax5", of: app)
        try auditAccessibility(app)
    }
}
