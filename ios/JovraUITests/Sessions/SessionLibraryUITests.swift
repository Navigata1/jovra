import XCTest

/// T20 session library (S08): the walking skeleton, independent facet labels, search, Trash with Undo, the purge
/// dialog, quarantine, and the accessibility audit over the demo, empty, no-results and Trash states.
final class SessionLibraryUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func cards(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.session.'"))
    }

    @MainActor
    private func card(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.session.' AND label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func searchField(_ app: XCUIApplication) -> XCUIElement { app.textFields["library.search"] }

    /// Scrolls the library until `element` sits fully clear of the tab bar (the bar floats over the page, so
    /// `isHittable` alone would let a tap land on a tab).
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let bar = app.otherElements["tabBar"]
        func isClear() -> Bool {
            guard element.exists, element.isHittable else { return false }
            let limit = bar.exists ? bar.frame.minY : app.frame.maxY
            return element.frame.maxY < limit - 8 && element.frame.minY > 100
        }
        for _ in 0..<12 where !isClear() {
            let below = element.exists && element.frame.minY > 100
            below ? app.scrollViews.firstMatch.swipeUp(velocity: .slow) : app.scrollViews.firstMatch.swipeDown(velocity: .slow)
        }
    }

    // MARK: Walking skeleton

    @MainActor
    func testRecordFixtureSessionArgumentRecordsThroughTheEngineAndOpensReplay() throws {
        let app = XCUIApplication.launchJovra {
            $0.appearance = .light; $0.library = .fresh; $0.recordFixtureSessionSeconds = 10; $0.startRoute = "sessions"
        }
        XCTAssertTrue(app.heading("Your sessions").waitForExistence(timeout: 10))
        let recorded = card(app, containing: "Fixture recording")
        XCTAssertTrue(recorded.waitForExistence(timeout: 60), "the 10 s engine recording is listed")
        XCTAssertTrue(recorded.label.contains("Video: On device"), recorded.label)
        XCTAssertTrue(recorded.label.contains(" sec · "), "a short recording states its seconds: \(recorded.label)")
        XCTAssertTrue(recorded.label.contains("Only on this iPhone"), recorded.label)
        XCTAssertTrue(recorded.label.contains("Sample"), "fixture-camera recordings are Sample: \(recorded.label)")
        XCTAssertNotNil(recorded.label.range(of: "[0-9.,]+ (kB|KB|MB|GB) on this iPhone", options: .regularExpression),
                        "the card states the bytes the recording uses: \(recorded.label)")
        attachScreenshot(app, name: "s08-light-walking-skeleton")
        recorded.tap()
        XCTAssertTrue(app.heading("Smart replay").waitForExistence(timeout: 10), "opening the session presents replay")
        attachScreenshot(app, name: "walking-skeleton-replay")
    }

    /// A session with video on this iPhone shows its poster frame (the fixture camera records 16:9). At AX5 the
    /// thumbnail spans the card, and the poster must be cropped to 16:10 rather than widen the whole page.
    @MainActor
    func testRecordedSessionWithAPosterFitsTheScreenAtAX5() throws {
        let app = XCUIApplication.launchJovra(contentSize: .accessibility5) {
            $0.appearance = .light; $0.library = .fresh; $0.recordFixtureSessionSeconds = 3; $0.startRoute = "sessions"
        }
        let recorded = card(app, containing: "Fixture recording")
        XCTAssertTrue(recorded.waitForExistence(timeout: 60), "the 3 s engine recording is listed")
        XCTAssertTrue(recorded.label.contains("Video: On device"), "the card has a poster to load: \(recorded.label)")
        // The poster loads after the card appears. Wait for the page to widen; it must not.
        let screenWidth = app.windows.firstMatch.frame.width
        let page = app.scrollViews.firstMatch
        let widened = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in page.exists && page.frame.width > screenWidth + 0.5 }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [widened], timeout: 5), .timedOut,
                       "the library is laid out wider than the screen: \(page.frame) vs width \(screenWidth)")
        assertFitsTheScreenWidth(app, identifierPrefixes: ["library.session.", "library.delete.", "library.import"])
        attachScreenshot(app, name: "s08-ax5-recorded-poster")
        assertHitTargets(in: app)
        try auditScreen(app)
        reveal(recorded, in: app)
        assertFitsTheScreenWidth(app, identifierPrefixes: ["library.session.", "library.delete."])
        attachScreenshot(app, name: "s08-ax5-recorded-poster-card")
    }

    // MARK: Facets and quarantine

    @MainActor
    func testFacetFixturesShowFourIndependentLabelsAndQuarantineReason() throws {
        let app = XCUIApplication.launchJovra { $0.appearance = .light; $0.library = .facets; $0.startRoute = "sessions" }
        XCTAssertTrue(app.heading("Your sessions").waitForExistence(timeout: 10))
        let quarantine = app.descendants(matching: .any)["library.quarantined.fixture-unreadable"]
        XCTAssertTrue(quarantine.waitForExistence(timeout: 15), "the unreadable document is reported")
        XCTAssertTrue(quarantine.label.contains("Reason:"), quarantine.label)
        attachScreenshot(app, name: "s08-light-facets-1")

        // Every scroll position is attached, down to the one showing the Trash row, so each card whose label is
        // read here (it must be hittable) also appears in a named screenshot: the facet grid covers all eleven.
        var labels: [String: String] = [:]
        var page = 2
        var reachedTrash = false
        for _ in 0..<16 {
            for element in cards(app).allElementsBoundByIndex where element.exists && element.isHittable {
                labels[element.identifier] = element.label
            }
            if app.buttons["library.trash"].isHittable { reachedTrash = true; break }
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            attachScreenshot(app, name: "s08-light-facets-\(page)")
            page += 1
        }
        XCTAssertTrue(reachedTrash, "the last screenshot shows the Trash row below the last card")
        XCTAssertEqual(labels.count, 11, "every facet fixture lists while one document is quarantined: \(labels.keys.sorted())")
        XCTAssertTrue(labels.values.contains { $0.hasPrefix("Lesson with coach") && $0.contains("Backup: Google Drive is full") },
                      "the eleventh card, the only quota-blocked one, was on screen in an attached page")
        for label in labels.values {
            for axis in ["Video:", "Analysis:", "Review:", "Backup:"] {
                XCTAssertTrue(label.contains(axis), "each card states its \(axis) facet: \(label)")
            }
        }
        let all = labels.values.joined(separator: "\n")
        let expected = [
            "Video: Not finalized", "Video: Recovery in progress", "Video: On device", "Video: Saved with gaps",
            "Video: Partially saved", "Video: Importing", "Video: In Google Drive only", "Video: Video missing",
            "Analysis: Not analyzed", "Analysis: Analysis queued", "Analysis: Analyzing", "Analysis: Analysis paused",
            "Analysis: Analysis ready", "Analysis: Partly analyzed", "Analysis: Analysis failed", "Analysis: Analysis unavailable",
            "Review: Not reviewed", "Review: Needs review", "Review: Reviewed",
            "Backup: Not backed up", "Backup: Backup not set up", "Backup: Queued for backup", "Backup: Waiting for Wi-Fi",
            "Backup: Preparing backup", "Backup: Backing up", "Backup: Checking backup", "Backup: Backed up",
            "Backup: Retry backup", "Backup: Needs reconnect", "Backup: Google Drive is full",
            "Only on this iPhone",
        ]
        for text in expected { XCTAssertTrue(all.contains(text), "a card shows “\(text)”") }
        XCTAssertTrue(app.buttons["library.trash"].label.contains("Trash · 1"))
    }

    // MARK: Search

    @MainActor
    func testSearchFiltersAndNoResultsOffersClearSearch() throws {
        let app = XCUIApplication.launchJovra { $0.appearance = .light; $0.demo = .sample; $0.startRoute = "sessions" }
        XCTAssertTrue(card(app, containing: "Serve practice").waitForExistence(timeout: 15))
        let search = searchField(app)
        search.tap(); search.typeText("Alex")
        XCTAssertTrue(card(app, containing: "Jon vs Alex").waitForExistence(timeout: 5))
        XCTAssertTrue(card(app, containing: "Serve practice").waitForNonExistence(timeout: 5), "Alex filters the list")
        XCTAssertFalse(card(app, containing: "Jon vs Sam").exists)
        attachScreenshot(app, name: "s08-light-search-alex")

        app.buttons["library.search.clear"].tap()
        search.tap(); search.typeText("zzz")
        let noResults = app.descendants(matching: .any)["library.noResults"]
        XCTAssertTrue(noResults.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No sessions match “zzz”"].exists)
        XCTAssertEqual(cards(app).count, 0)
        attachScreenshot(app, name: "s08-light-no-results")
        app.buttons["Clear search"].firstMatch.tap()
        XCTAssertTrue(card(app, containing: "Serve practice").waitForExistence(timeout: 5), "clearing the search lists every session again")
    }

    // MARK: Trash

    @MainActor
    func testDeleteThenUndoRestoresAndThePurgeDialogStatesItsScope() throws {
        let app = XCUIApplication.launchJovra {
            $0.appearance = .light; $0.library = .facets; $0.recordFixtureSessionSeconds = 3; $0.startRoute = "sessions"
        }
        let recorded = card(app, containing: "Fixture recording")
        XCTAssertTrue(recorded.waitForExistence(timeout: 45))
        let id = recorded.identifier.replacingOccurrences(of: "library.session.", with: "")

        try moveToTrash(id, in: app)
        XCTAssertTrue(recorded.waitForNonExistence(timeout: 10), "Delete moves the session out of the list")
        let undo = app.buttons["toast.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "an UndoBar offers Undo")
        attachScreenshot(app, name: "s08-light-undo-bar")
        undo.tap()
        XCTAssertTrue(app.buttons["library.session.\(id)"].waitForExistence(timeout: 10), "Undo restores the session")
        XCTAssertTrue(app.buttons["library.session.\(id)"].label.contains("Video: On device"), "with its original state")

        try moveToTrash(id, in: app)
        XCTAssertTrue(app.buttons["library.session.\(id)"].waitForNonExistence(timeout: 10))
        let trash = app.buttons["library.trash"]
        reveal(trash, in: app)
        XCTAssertTrue(trash.label.contains("Trash · 2"), trash.label)
        trash.tap()
        XCTAssertTrue(app.heading("Trash").waitForExistence(timeout: 5))
        let purge = app.buttons["trash.purge.\(id)"]
        XCTAssertTrue(purge.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "s08-light-trash")
        purge.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n")
        XCTAssertTrue(text.contains("permanently"), text)
        XCTAssertTrue(text.contains("The original video ("), "names the original and its size: \(text)")
        XCTAssertTrue(text.contains("analysis"), text)
        XCTAssertTrue(text.contains("local copies"), text)
        XCTAssertTrue(text.contains("Google Drive: no verified copy. This is the only copy of the original video."), text)
        attachScreenshot(app, name: "s08-light-purge-dialog")
        alert.buttons["Delete permanently"].firstMatch.tap()
        XCTAssertTrue(purge.waitForNonExistence(timeout: 10), "the confirmed purge removes it")
        XCTAssertTrue(app.descendants(matching: .any)["trash.session.\(LibraryFixtureIDs.trashed)"].exists,
                      "other trashed sessions stay: Trash is never emptied for you")

        // The Sample "Old warm-up" has no original stored here and no backup: the dialog must not call anything
        // "the only copy of the original video".
        let purgeSample = app.buttons["trash.purge.\(LibraryFixtureIDs.trashed)"]
        XCTAssertTrue(purgeSample.waitForExistence(timeout: 5))
        purgeSample.tap()
        let sampleAlert = app.alerts.firstMatch
        XCTAssertTrue(sampleAlert.waitForExistence(timeout: 5))
        let sampleText = sampleAlert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n")
        XCTAssertTrue(sampleText.contains("No original video is on this iPhone"), sampleText)
        XCTAssertTrue(sampleText.contains("No copy of the original video exists on this iPhone or in Google Drive."), sampleText)
        XCTAssertFalse(sampleText.contains("This is the only copy"), sampleText)
        attachScreenshot(app, name: "s08-light-purge-dialog-no-original")
        sampleAlert.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(sampleAlert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(purgeSample.exists, "Cancel keeps the session in Trash")
    }

    @MainActor
    private func moveToTrash(_ id: String, in app: XCUIApplication) throws {
        let delete = app.buttons["library.delete.\(id)"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        reveal(delete, in: app)
        delete.tap()
        let confirm = app.alerts.firstMatch.buttons["Move to Trash"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
    }

    // MARK: Accessibility audit: demo, empty, no results and Trash in light, dark and AX5

    private enum Variant: CaseIterable {
        case light, dark, ax5
        var slug: String { String(describing: self) }
    }

    @MainActor
    private func launch(_ variant: Variant, _ configure: (inout LaunchConfiguration) -> Void) -> XCUIApplication {
        XCUIApplication.launchJovra(contentSize: variant == .ax5 ? .accessibility5 : nil) {
            $0.appearance = variant == .dark ? .dark : .light
            configure(&$0)
        }
    }

    /// The demo library is the longest audited page (eight cards of four status pills each). XCTest's own
    /// time limit for one audit is sometimes exceeded there even after `auditScreen` splits the audit by type;
    /// the whole audit then runs once more from the top. Every finding still fails; only XCTest's
    /// "Audit failed to complete in time" is retried, once.
    @MainActor
    private func auditLongScreen(_ app: XCUIApplication) throws {
        do {
            try auditScreen(app)
        } catch let error as NSError where AccessibilityAudit.isTimeout(error) {
            app.scrollViews.firstMatch.swipeDown(velocity: .fast)
            app.scrollViews.firstMatch.swipeDown(velocity: .fast)
            try auditScreen(app)
        }
    }

    @MainActor
    func testDemoLibraryPassesTheAuditInLightDarkAndAX5() throws {
        for variant in Variant.allCases {
            let app = launch(variant) { $0.demo = .sample; $0.startRoute = "sessions" }
            XCTAssertTrue(card(app, containing: "Jon vs Alex").waitForExistence(timeout: 15))
            attachScreenshot(app, name: "s08-\(variant.slug)-demo")
            assertHitTargets(in: app)
            try auditLongScreen(app)
            app.terminate()
        }
    }

    @MainActor
    func testEmptyLibraryPassesTheAuditInLightDarkAndAX5() throws {
        for variant in Variant.allCases {
            let app = launch(variant) { $0.library = .fresh; $0.startRoute = "sessions" }
            XCTAssertTrue(app.descendants(matching: .any)["library.empty"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["Record a session"].exists && app.buttons["Import a video"].exists)
            attachScreenshot(app, name: "s08-\(variant.slug)-empty")
            assertHitTargets(in: app)
            try auditScreen(app)
            app.terminate()
        }
    }

    @MainActor
    func testNoResultsPassesTheAuditInLightDarkAndAX5() throws {
        for variant in Variant.allCases {
            let app = launch(variant) { $0.demo = .sample; $0.startRoute = "sessions" }
            let search = searchField(app)
            XCTAssertTrue(search.waitForExistence(timeout: 15))
            XCTAssertTrue(card(app, containing: "Jon vs Alex").waitForExistence(timeout: 15))
            search.tap(); search.typeText("zzz\n")
            XCTAssertTrue(app.descendants(matching: .any)["library.noResults"].waitForExistence(timeout: 5))
            attachScreenshot(app, name: "s08-\(variant.slug)-no-results")
            assertHitTargets(in: app)
            try auditScreen(app)
            app.terminate()
        }
    }

    @MainActor
    func testTrashPassesTheAuditInLightDarkAndAX5() throws {
        for variant in Variant.allCases {
            let app = launch(variant) { $0.library = .facets; $0.startRoute = "sheet.trash" }
            XCTAssertTrue(app.heading("Trash").waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any)["trash.session.\(LibraryFixtureIDs.trashed)"].waitForExistence(timeout: 15))
            attachScreenshot(app, name: "s08-\(variant.slug)-trash")
            try auditSheet(app)
            app.terminate()
        }
    }
}

/// Ids of the `-library facets` fixtures (LibraryFixtures in the app).
private enum LibraryFixtureIDs {
    static let trashed = "fixture-trashed"
}
