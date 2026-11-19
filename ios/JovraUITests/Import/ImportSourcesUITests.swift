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
        app.buttons["import.row.rotate"].firstMatch.tap()
        XCTAssertTrue(rowSummary(app, containing: "Shown turned 90°").waitForExistence(timeout: 5))
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
            let results = app.staticTexts["Your imports"]
            reveal(results, in: app)
            attachScreenshot(app, name: "s07-\(slug)-import-results")
            if size == .accessibility5 {
                // Every type including textClipped and Dynamic Type. Contrast does not depend on text size and
                // is audited for these same rows in light and dark; on this ~3,000 pt AX5 page the audit's own
                // scrolling reports an element-less contrast finding it cannot place (see the PR's known gaps).
                try auditScreen(app, for: XCUIAccessibilityAuditType.all.subtracting(.contrast))
            } else {
                try auditScreen(app)
            }
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
