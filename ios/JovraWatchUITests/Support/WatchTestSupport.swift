import Foundation
import JovraRoom
import XCTest

/// A receiver clock the test moves by hand.
final class ManualMonotonicClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var now: Int

    init(nowMs: Int = 0) { now = nowMs }

    func nowMs() -> Int { lock.withLock { now } }
    func advance(byMs delta: Int) { lock.withLock { now += delta } }
}

/// The spec/room records this test bundle carries (the same folder reference the app bundles).
enum WatchTestRecords {
    static func library(file: StaticString = #filePath, line: UInt = #line) throws -> WatchRecordLibrary {
        try XCTUnwrap(WatchRecordLibrary(bundle: Bundle(for: BundleToken.self)),
                      "the records folder is missing from the test bundle", file: file, line: line)
    }

    static func sample() throws -> WatchBridgeSnapshot {
        try library().watchBridgeSnapshot(WatchStateRegistry.sampleRecord)
    }

    /// The sample with a later bridge sequence (same bridge instance), as the phone's next push would carry.
    static func sample(bridgeSeq: Int) throws -> WatchBridgeSnapshot {
        var snapshot = try sample()
        snapshot.bridge.bridgeSeq = bridgeSeq
        return snapshot
    }

    private final class BundleToken {}
}

extension XCUIApplication {
    /// Launches the watch app on one harness state (or with any other launch configuration).
    @discardableResult
    static func launchWatch(_ configuration: WatchLaunchConfiguration) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = configuration.arguments
        app.launch()
        return app
    }

    static func launchWatch(state: WatchStateID) -> XCUIApplication {
        launchWatch(WatchLaunchConfiguration(watchState: state))
    }

    /// Swipes up (Digital Crown direction) until `surface` is on screen: a page scrolls its own content to the end
    /// before the vertical TabView moves to the next page. False when it never appears.
    func swipeUp(toPage surface: WatchSurface, maxSwipes: Int = 8) -> Bool {
        for _ in 0..<maxSwipes {
            if self.surface(surface).exists, self.surface(surface).isHittable { return true }
            swipeUp()
        }
        return self.surface(surface).waitForExistence(timeout: 2)
    }

    /// The root view of a surface, by its identifier.
    func surface(_ surface: WatchSurface) -> XCUIElement {
        descendants(matching: .any).matching(identifier: surface.identifier).firstMatch
    }
}

extension XCTestCase {
    /// The accessibility audit on everything JOVRA draws. The one exception is the system's own vertical page
    /// indicator (PUICMaterialPageIndicatorView), which the audit reports as a small hit region; it is watchOS chrome
    /// the app cannot size, and the pages are reachable by swipe and Digital Crown.
    func auditAccessibility(_ app: XCUIApplication,
                            for types: XCUIAccessibilityAuditType = .all) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            issue.auditType == .hitRegion && issue.detailedDescription.contains("PUICMaterialPageIndicatorView")
        }
    }

    /// Keeps a named screenshot of the current screen (scripts/ios/watch-ui-test.sh exports it to evidence/watch/<ticket>/).
    func keepScreenshot(_ name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
