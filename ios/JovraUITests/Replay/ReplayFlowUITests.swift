import XCTest

/// Public recording, saved library, decoded replay and durable score-correction seam.
final class ReplayFlowUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testActualSavedRecordingOpensDecodedReplayAndDurableReviewedCorrection() throws {
        let title = "Replay " + UUID().uuidString.prefix(8)
        let app = XCUIApplication.launchJovra { $0.demo = .off }
        app.buttons["tab.record"].tap()
        for (id, text) in [("capture.setup.title", title), ("capture.setup.playerA", "Jon"), ("capture.setup.playerB", "Alex")] {
            let field = app.textFields[id]
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(text + "\n")
        }
        app.swipeUp(); app.buttons["record.previewCapture"].tap()
        XCTAssertTrue(app.buttons["capture.start"].waitForExistence(timeout: 10))
        app.buttons["capture.start"].tap()
        let saved = app.staticTexts["capture.confirmedTime"]
        XCTAssertTrue(saved.waitForExistence(timeout: 15))
        let enough = NSPredicate { _, _ in
            let seconds = saved.label.split(separator: ":").last.flatMap { Int($0) } ?? 0
            return seconds >= 4
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enough, object: nil)], timeout: 12), .completed)
        app.buttons["capture.stop"].tap()
        let stop = app.buttons.matching(identifier: "capture.confirmStop").firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5)); stop.tap()
        XCTAssertTrue(app.staticTexts["capture.saved"].waitForExistence(timeout: 20))
        app.buttons["capture.openLibrary"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.session.' AND label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.buttons["replay.play"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["replay.sample"].exists)
        XCTAssertTrue(app.staticTexts["replay.frame"].waitForExistence(timeout: 20))
        app.buttons["replay.frame.next"].tap()
        let nextFrame = NSPredicate { _, _ in app.staticTexts["replay.frame"].label.hasPrefix("f 1 ·") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: nextFrame, object: nil)], timeout: 10), .completed)
        for (index, winner) in ["A", "A", "A", "B"].enumerated() {
            replace(app.textFields["review.startMs"], with: String(index * 500))
            replace(app.textFields["review.endMs"], with: String((index + 1) * 500))
            reveal(app.buttons["review.add." + winner], in: app)
            app.buttons["review.add." + winner].tap()
            XCTAssertTrue(app.buttons["review.point.\(index + 1)"].waitForExistence(timeout: 10))
        }
        reveal(app.buttons["review.point.1"], in: app); app.buttons["review.point.1"].tap()
        reveal(app.buttons["review.correct.B"], in: app); app.buttons["review.correct.B"].tap()
        reveal(app.buttons["review.point.2"], in: app); app.buttons["review.point.2"].tap()
        XCTAssertTrue(app.staticTexts["review.scoreBefore"].label.contains("0–15"))
        XCTAssertTrue(app.staticTexts["review.pointsWon.A"].label.contains("2/4"))
        XCTAssertTrue(app.staticTexts["review.score.sample"].waitForExistence(timeout: 5), "Synthetic selected score stays labelled beside its value")
        XCTAssertTrue(app.staticTexts["review.pointsWon.sample"].exists, "Synthetic stat stays labelled after the header scrolls away")
        XCTAssertTrue(app.staticTexts["review.firstServes.A"].label.hasSuffix("—"))
        XCTAssertTrue(app.staticTexts["review.shots"].label.hasSuffix("—"))
        attachScreenshot(app, name: "replay-reviewed-correction")
        try auditScreen(app, scrollIdentifier: "replay.scroll")
        app.buttons["replay.close"].tap(); app.terminate(); app.launch()
        app.buttons["tab.sessions"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        reveal(app.buttons["review.point.2"], in: app); app.buttons["review.point.2"].tap()
        XCTAssertTrue(app.staticTexts["review.scoreBefore"].label.contains("0–15"))
    }

    @MainActor private func replace(_ field: XCUIElement, with text: String) {
        reveal(field, in: XCUIApplication()); field.tap()
        let count = (field.value as? String)?.count ?? 0
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + text + "\n")
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 { if element.isHittable { return }; app.swipeUp() }
        for _ in 0..<6 { if element.isHittable { return }; app.swipeDown() }
        XCTAssertTrue(element.isHittable)
    }
}
