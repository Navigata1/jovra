@preconcurrency import AVFoundation
import XCTest

/// "Bring your game in" (S07, T26). The system pickers are replaced by `-importSelection` (the files a
/// player would have picked), so every run imports real fixture media through the real pipeline and store.
/// Picker presentation itself is covered by `FilesImportUITests`. Each run writes unique synthetic copies
/// (a passthrough rewrite with a run-specific camera tag), so earlier runs never make them duplicates.
final class ImportSourcesUITests: XCTestCase {
    private var run = ""
    private var scratch: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        run = String(UUID().uuidString.prefix(6)).lowercased()
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("t26-\(run)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    @MainActor
    func testFilesImportSavesTheSessionWithItsRealDateAndSourceThenPresentsProcessing() async throws {
        let video = try await syntheticCopy("hevc-720p60-landscape.mov", named: "Court 3 rally \(run).mov", dated: true)
        let app = launch(selection: [video.path])
        openImport(app, source: "files")
        app.buttons["import.choose"].tap()

        let close = app.buttons.matching(NSPredicate(format: "identifier == 'processing.close'")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 30), "A single clean import presents the processing route")
        close.tap()
        let summary = rowSummary(app, containing: "Court 3 rally \(run).mov")
        XCTAssertTrue(summary.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(summary.label.contains("Saved locally"), summary.label)
        XCTAssertTrue(summary.label.contains("Files"), summary.label)
        XCTAssertTrue(summary.label.contains("Oct 6, 2026"), "the date comes from the file's own metadata: \(summary.label)")
        XCTAssertTrue(summary.label.contains("720p"), summary.label)
        // Negative control for FilesImportUITests' cancelled-picker check: these identifiers are live on a result.
        XCTAssertGreaterThan(app.descendants(matching: .any).matching(identifier: "import.row").count, 0)
        XCTAssertTrue(app.descendants(matching: .any)["import.safe"].exists)
        app.buttons["import.row.rotate"].firstMatch.tap()
        XCTAssertTrue(rowSummary(app, containing: "Turn saved: 90°").waitForExistence(timeout: 5))
        scrollIntoViewport(app.staticTexts["Your imports"], in: app, at: 0.1)
        attachScreenshot(app, name: "s07-light-import-saved")

        app.buttons["import.back"].tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Court 3 rally \(run)")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "The session is in the library: \(app.debugDescription)")
    }

    @MainActor
    func testADuplicateOffersOpenExistingAndImportAnyway() async throws {
        let first = try await syntheticCopy("duplicate-a.mp4", named: "Baseline drill \(run).mov", dated: false)
        let again = scratch.appendingPathComponent("Baseline drill copy \(run).mov")
        try FileManager.default.copyItem(at: first, to: again)

        var app = launch(selection: [first.path, again.path])
        openImport(app, source: "files")
        app.buttons["import.choose"].tap()
        let duplicate = rowSummary(app, containing: "Baseline drill copy \(run).mov")
        XCTAssertTrue(waitForLabel(duplicate, containing: "Already in your library"), duplicate.label)
        XCTAssertTrue(duplicate.label.contains("“Baseline drill \(run)”"), duplicate.label)
        XCTAssertTrue(app.buttons["import.row.openExisting"].exists)
        let anyway = app.buttons["import.row.importAnyway"]
        reveal(anyway, in: app)
        anyway.tap()
        XCTAssertTrue(waitForLabel(rowSummary(app, containing: "Baseline drill copy \(run).mov"), containing: "Saved locally"))

        app.terminate()
        app = launch(selection: [again.path])
        openImport(app, source: "photos")
        app.buttons["import.choose"].tap()
        let third = rowSummary(app, containing: "Baseline drill copy \(run).mov")
        XCTAssertTrue(waitForLabel(third, containing: "Already in your library"), third.label)
        let open = app.buttons["import.row.openExisting"]
        reveal(open, in: app)
        open.tap()
        XCTAssertTrue(app.buttons["replay.close"].waitForExistence(timeout: 15), "Open existing opens the saved session")
    }

    @MainActor
    func testABatchReportsEachFileIncludingAnUnsupportedCodecAndAWaitingDownload() async throws {
        let good = try await syntheticCopy("h264-1080p30-landscape.mp4", named: "Serve practice \(run).mov", dated: false)
        let cloud = try await syntheticCopy("hevc-720p30-vfr.mp4", named: "Cloud rally \(run).mov", dated: false)
        let ffv1 = scratch.appendingPathComponent("Old camera \(run).mov")
        try FileManager.default.copyItem(at: try fixture("ffv1-unsupported.mov"), to: ffv1)
        let app = launch(selection: [good.path, "cloud:" + cloud.path, ffv1.path])
        openImport(app, source: "files")
        app.buttons["import.choose"].tap()

        XCTAssertTrue(waitForLabel(rowSummary(app, containing: "Cloud rally \(run).mov"), containing: "Waiting for download"),
                      "a cloud-only file says so while it downloads")
        XCTAssertTrue(waitForLabel(rowSummary(app, containing: "Cloud rally \(run).mov"), containing: "Saved locally", timeout: 30),
                      "and completes when it becomes available")
        let unsupported = rowSummary(app, containing: "Old camera \(run).mov")
        XCTAssertTrue(waitForLabel(unsupported, containing: "Can't import this video"), unsupported.label)
        XCTAssertTrue(unsupported.label.contains("FFV1"), "the reason names the codec: \(unsupported.label)")
        XCTAssertTrue(waitForLabel(rowSummary(app, containing: "Serve practice \(run).mov"), containing: "Saved locally"))
        XCTAssertFalse(app.buttons["processing.close"].exists, "a batch stays on its per-file results")
    }

    @MainActor
    func testEndingTheAppMidImportLeavesNoPartialFolderAfterRelaunch() async throws {
        let video = try await syntheticCopy("hevc-720p60-landscape.mov", named: "Interrupted \(run).mov", dated: false)
        var app = launch(selection: [video.path], stall: true)
        openImport(app, source: "files")
        app.buttons["import.choose"].tap()
        XCTAssertTrue(waitForLabel(rowSummary(app, containing: "Interrupted \(run).mov"), containing: "Saving a copy"))
        let staging = try appContainer().appendingPathComponent("Library/Application Support/JOVRA/.files-imports")
        XCTAssertTrue(waitUntil(timeout: 20) { ((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []).count == 1 },
                      "the stalled import has its partial folder on disk")
        app.terminate()

        app = launch(selection: [])
        app.buttons["tab.sessions"].tap()
        XCTAssertTrue(app.buttons["library.import"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 20) { ((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []).isEmpty },
                      "relaunch removed the partial folder")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Interrupted \(run)")).firstMatch.exists)
    }

    @MainActor
    func testImportScreenPassesTheAccessibilityAuditInLightDarkAndAX5() async throws {
        for (appearance, size, slug) in [("light", nil, "light"), ("dark", nil, "dark"), ("light", ContentSize.accessibility5, "ax5")] as [(String, ContentSize?, String)] {
            let good = try await syntheticCopy("hevc-hlg-720p30.mov", named: "HDR rally \(slug) \(run).mov", dated: true)
            let ffv1 = scratch.appendingPathComponent("Old camera \(slug) \(run).mov")
            try FileManager.default.copyItem(at: try fixture("ffv1-unsupported.mov"), to: ffv1)
            let again = scratch.appendingPathComponent("HDR rally copy \(slug) \(run).mov")
            try FileManager.default.copyItem(at: good, to: again)
            let app = launch(selection: [good.path, ffv1.path, again.path], appearance: appearance, contentSize: size)
            openImport(app, source: "photos")
            // The tiles at the top of the page (full-width rows at AX5), not the Choose button openImport scrolled to.
            scrollIntoViewport(app.buttons["import.source.photos"], in: app, at: 0.25)
            attachScreenshot(app, name: "s07-\(slug)-import-sources")
            try auditScreen(app)
            if slug == "light" {
                let drive = app.buttons["import.source.drive"]
                reveal(drive, in: app)
                drive.tap()
                XCTAssertTrue(app.descendants(matching: .any)["import.drive.archiveSlot"].waitForExistence(timeout: 5))
                attachScreenshot(app, name: "s07-light-import-drive")
                try auditScreen(app)
                let photos = app.buttons["import.source.photos"]
                reveal(photos, in: app)
                photos.tap()
                reveal(app.buttons["import.choose"], in: app)
            }
            app.buttons["import.choose"].tap()
            XCTAssertTrue(waitForLabel(rowSummary(app, containing: "HDR rally copy \(slug) \(run).mov"), containing: "Already in your library", timeout: 30))
            // Audit the finished state: while a batch runs, the sources and footage controls are disabled.
            let cancel = app.buttons["import.cancel"]
            XCTAssertTrue(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cancel)],
                                           timeout: 20) == .completed)
            // The results, not the sources: "Your imports" near the top of the viewport, then (at standard sizes,
            // where the three rows fit) the held duplicate's actions must be in view too.
            scrollIntoViewport(app.staticTexts["Your imports"], in: app, at: 0.05)
            if size == nil {
                XCTAssertTrue(isInViewport(app.buttons["import.row.importAnyway"], in: app), "the duplicate row is in the screenshot")
                XCTAssertTrue(isInViewport(rowSummary(app, containing: "Old camera \(slug) \(run).mov"), in: app),
                              "the unsupported row is in the screenshot")
            } else {
                XCTAssertTrue(isInViewport(rowSummary(app, containing: "HDR rally \(slug) \(run).mov"), in: app),
                              "the first result row is in the screenshot")
            }
            attachScreenshot(app, name: "s07-\(slug)-import-results")
            // Every audit type, contrast included. At AX5 only, the helper's one logged exception applies: a contrast
            // finding on a SwiftUI node it cannot place, while tile text runs under the tab bar (see the helper).
            try auditScreen(app, allowUnplacedContrastUnderTabBar: size == .accessibility5)
            app.terminate()
        }
    }

    // MARK: Helpers

    @MainActor
    private func launch(selection: [String], stall: Bool = false, appearance: String = "light",
                        contentSize: ContentSize? = nil) -> XCUIApplication {
        XCUIApplication.launchJovra(contentSize: contentSize) {
            $0.demo = .off
            $0.appearance = LaunchConfiguration.Appearance(rawValue: appearance)
            $0.importSelection = selection
            $0.importStall = stall
        }
    }

    @MainActor
    private func openImport(_ app: XCUIApplication, source: String) {
        app.buttons["tab.sessions"].tap()
        let entry = app.buttons["library.import"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.heading("Bring your game in").waitForExistence(timeout: 10))
        app.buttons["import.source.\(source)"].tap()
        let name = app.textFields["import.player"]
        reveal(name, in: app)
        name.tap()
        name.typeText("Sample Player\n")
        let choose = app.buttons["import.choose"]
        reveal(choose, in: app)
        XCTAssertTrue(choose.isEnabled)
    }

    @MainActor
    private func rowSummary(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "import.row.summary")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 20) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.25))
        }
        return condition()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 where !(element.exists && element.isHittable) { scroll.swipeUp() }
        for _ in 0..<8 where !(element.exists && element.isHittable) { scroll.swipeDown() }
    }

    /// The page area not covered by the status bar, the screen's back control or the tab bar.
    @MainActor
    private func viewport(_ app: XCUIApplication) -> (top: CGFloat, bottom: CGFloat) {
        let window = app.windows.firstMatch.frame
        let back = app.buttons["import.back"]
        let top = back.exists && back.frame.maxY > window.minY ? max(back.frame.maxY, window.minY + 60) : window.minY + 60
        let tabBar = app.otherElements["tabBar"]
        return (top, tabBar.exists ? tabBar.frame.minY - 8 : window.maxY - 34)
    }

    @MainActor
    private func isInViewport(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let (top, bottom) = viewport(app)
        let frame = element.frame
        return !frame.isEmpty && frame.minY >= top && frame.maxY <= bottom
    }

    /// Drags the page (slowly, so it does not fling) until `element`'s top sits at `fraction` of the visible area,
    /// or the page cannot move further. `reveal` only needs hittability, which an element behind the tab bar can have.
    @MainActor
    private func scrollIntoViewport(_ element: XCUIElement, in app: XCUIApplication, at fraction: CGFloat) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element)")
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<12 {
            let (top, bottom) = viewport(app)
            let height = bottom - top
            let target = top + height * fraction
            let delta = target - element.frame.minY
            if abs(delta) < 12 { return }
            let move = max(-height * 0.7, min(height * 0.7, delta))
            let startY = move > 0 ? top + 16 : bottom - 16
            let before = element.frame.minY
            let start = origin.withOffset(CGVector(dx: 8, dy: startY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: move)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            waitForScrollingToSettle(element)
            if abs(element.frame.minY - before) < 1 { return }
        }
    }

    /// The app's data container on this simulator (UI-test runner and app share the simulated device).
    private func appContainer() throws -> URL {
        let applications = URL(fileURLWithPath: NSHomeDirectory()).deletingLastPathComponent()
        for candidate in try FileManager.default.contentsOfDirectory(at: applications, includingPropertiesForKeys: nil) {
            let metadata = candidate.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard let plist = NSDictionary(contentsOf: metadata),
                  plist["MCMMetadataIdentifier"] as? String == "com.islanddevcrew.jovra" else { continue }
            return candidate
        }
        throw XCTSkip("The app container is not readable from the UI-test runner on this destination")
    }

    private func fixture(_ name: String) throws -> URL {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let media = repository.appendingPathComponent(".cache/media")
        let folder = try FileManager.default.contentsOfDirectory(atPath: media.path).first { $0.hasPrefix("import-") }
        guard let folder else { throw XCTSkip("Render the import fixtures first: python3 scripts/media/render.py --set import") }
        return media.appendingPathComponent(folder).appendingPathComponent(name)
    }

    /// A passthrough rewrite (never re-encoded) tagged with this run, optionally dated Oct 6, 2026 (Sample data).
    @MainActor
    private func syntheticCopy(_ fixtureName: String, named name: String, dated: Bool) async throws -> URL {
        let destination = scratch.appendingPathComponent(name)
        try await Self.exportCopy(from: try fixture(fixtureName), to: destination, tag: "Sample Camera \(run)", dated: dated)
        return destination
    }

    private nonisolated static func exportCopy(from source: URL, to destination: URL, tag: String, dated: Bool) async throws {
        let session = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough))
        var metadata: [AVMetadataItem] = []
        let camera = AVMutableMetadataItem()
        camera.identifier = .quickTimeMetadataModel
        camera.value = tag as NSString
        metadata.append(camera)
        if dated {
            let creation = AVMutableMetadataItem()
            creation.identifier = .quickTimeMetadataCreationDate
            creation.value = "2026-10-06T15:00:00Z" as NSString
            metadata.append(creation)
        }
        session.metadata = metadata
        session.outputURL = destination
        session.outputFileType = .mov
        await session.export()
        XCTAssertEqual(session.status, .completed, String(describing: session.error))
    }
}
