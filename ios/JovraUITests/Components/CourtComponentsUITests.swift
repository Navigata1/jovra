import XCTest

/// T13: the court components in the DEBUG gallery (`JOVRA_COURT_GALLERY=<scenario>`): accessibility audit and
/// screenshots in light, dark and AX5, placements read in words, the five marker shapes, and the framing guide's
/// corner brackets driving the reprojection check.
final class CourtComponentsUITests: XCTestCase {
    @MainActor
    private func launch(_ scenario: String, appearance: LaunchConfiguration.Appearance = .light,
                        size: ContentSize? = .large) -> XCUIApplication {
        let app = XCUIApplication.jovra(contentSize: size) { $0.appearance = appearance }
        app.launchEnvironment["JOVRA_COURT_GALLERY"] = scenario
        app.launch()
        let heading = app.heading("Court components")
        XCTAssertTrue(heading.waitForExistence(timeout: 8))
        waitForLayoutToSettle(heading)
        return app
    }

    /// At an accessibility text size the first frame can be laid out before the size arrives, and an audit taken
    /// then samples nodes that are gone a moment later ("Contrast failed" with no element, about one launch in
    /// eight). The page counts as laid out when its heading's frame holds across two reads, the same rule the
    /// shared audit applies after a scroll.
    @MainActor
    private func waitForLayoutToSettle(_ marker: XCUIElement) {
        var previous = marker.frame
        for _ in 0..<AccessibilityAudit.settleChecks {
            Thread.sleep(forTimeInterval: AccessibilityAudit.settleInterval)
            let current = marker.frame
            if current == previous { return }
            previous = current
        }
        XCTFail("The court gallery did not settle after launch")
    }

    @MainActor
    func testCourtComponentsInLightDarkAndAX5() throws {
        let appearances: [(String, LaunchConfiguration.Appearance, ContentSize?)] = [
            ("light", .light, .large), ("dark", .dark, .large), ("ax5", .light, .accessibility5),
        ]
        for (slug, appearance, size) in appearances {
            for scenario in ["diagrams", "markers", "guide"] {
                let app = launch(scenario, appearance: appearance, size: size)
                try auditScreen(app)
                attachScreenshot(app, name: "t13-\(slug)-\(scenario)")
                if scenario == "diagrams" {
                    // The legend, the service-box and half-court variants sit below the first screen.
                    for page in 2...3 {
                        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
                        attachScreenshot(app, name: "t13-\(slug)-\(scenario)-\(page)")
                    }
                }
                app.terminate()
            }
        }
    }

    @MainActor
    func testVoiceOverDescribesAPlacementInWords() {
        let app = launch("diagrams")
        let marker = app.descendants(matching: .any)["court.marker.p37"].firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        XCTAssertEqual(marker.label, "Point 37, Deep cross-court, in")
        let outlier = app.descendants(matching: .any)["court.marker.fh-out3"].firstMatch
        XCTAssertEqual(outlier.label, "Point 46, Long down the line, wide, out, outside the court area")
        let review = app.descendants(matching: .any)["court.marker.fh-review"].firstMatch
        XCTAssertEqual(review.label, "Point 49, Deep cross-court, needs review")
        let diagram = app.descendants(matching: .any)["court.diagram.full"].firstMatch
        XCTAssertEqual(diagram.label, "Forehand placements, sample, 15 placed: 9 deep, 2 short, 3 out, 1 needs review")
        let legend = app.descendants(matching: .any)["court.legend"].firstMatch
        XCTAssertEqual(legend.label, "Legend: filled circle, In, triangle, Out, and ring, Needs review")
        // The serve zones are words VoiceOver can reach, not pixels in a drawing.
        for (zone, word) in [("wide", "Wide"), ("body", "Body"), ("t", "T")] {
            XCTAssertEqual(app.staticTexts["court.zone.\(zone)"].firstMatch.label, word)
        }
    }

    @MainActor
    func testFiveMarkerShapesEachNamedByShapeAndMeaning() {
        let app = launch("markers")
        let expected = ["in": "filled circle, In", "out": "triangle, Out", "needsReview": "ring, Needs review",
                        "bookmark": "diamond, Bookmark", "unscored": "square outline, Unscored"]
        for (kind, label) in expected {
            XCTAssertEqual(app.descendants(matching: .any)["court.markerKind.\(kind)"].firstMatch.label, label)
        }
        XCTAssertTrue(app.staticTexts["Deep cross-court, in"].exists)
        XCTAssertTrue(app.staticTexts["Deep cross-court, wide, out"].exists)
        attachScreenshot(app, name: "t13-light-markers-read-aloud")
    }

    @MainActor
    func testDraggingACornerOffTheCourtFailsTheReprojectionCheck() throws {
        let app = launch("guide")
        let check = app.staticTexts["court.check"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertTrue(check.label.hasPrefix("Untapped lines: 0.0 px RMSE"), check.label)
        XCTAssertTrue(app.staticTexts["All four corners visible"].exists)
        let corner = app.descendants(matching: .any)["court.corner.farRightDoubles"].firstMatch
        XCTAssertEqual(corner.label, "Far right corner bracket")
        let before = corner.value as? String
        let start = corner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 18, dy: -14)))
        XCTAssertNotEqual(corner.value as? String, before, "the bracket moves in video pixels")
        XCTAssertTrue(app.staticTexts["Check the corners"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["The court lines don't match. Drag the brackets onto the outer corners."].exists)
        attachScreenshot(app, name: "t13-light-guide-dragged-poor")
        corner.doubleTap()
        XCTAssertTrue(app.staticTexts["All four corners visible"].waitForExistence(timeout: 3), "double tap puts the bracket back")
    }

    /// Story 66: a bracket dragged right across the court twists the quad until the fit puts measured lines beyond
    /// its own horizon. The guide must say so; it once read "All four corners visible" and "0.0 px RMSE" here.
    @MainActor
    func testDraggingABracketAcrossTheCourtIsNeverTheGoodState() throws {
        let app = launch("guide")
        let check = app.staticTexts["court.check"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let farRight = app.descendants(matching: .any)["court.corner.farRightDoubles"].firstMatch
        let nearLeft = app.descendants(matching: .any)["court.corner.nearLeftDoubles"].firstMatch
        let start = farRight.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Most of the way to the opposite corner: inside the triangle of the other three brackets.
        let end = nearLeft.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let across = CGVector(dx: (end.screenPoint.x - start.screenPoint.x) * 0.7, dy: (end.screenPoint.y - start.screenPoint.y) * 0.7)
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(across))
        XCTAssertTrue(app.staticTexts["Check the corners"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["All four corners visible"].exists)
        XCTAssertEqual(check.label, "Untapped lines: beyond the horizon, limit 3 px")
        attachScreenshot(app, name: "t13-light-guide-dragged-across")
        farRight.doubleTap()
        XCTAssertTrue(app.staticTexts["All four corners visible"].waitForExistence(timeout: 3), "double tap puts the bracket back")
    }

    @MainActor
    func testPoorFitAndLoupeStates() throws {
        for (scenario, appearance) in [("guide-poor", LaunchConfiguration.Appearance.dark), ("guide-loupe", .light),
                                       ("guide-twisted", .dark)] {
            let app = launch(scenario, appearance: appearance)
            if scenario == "guide-poor" {
                XCTAssertTrue(app.staticTexts["Check the corners"].waitForExistence(timeout: 5))
            }
            if scenario == "guide-twisted" {
                XCTAssertTrue(app.staticTexts["Check the corners"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts["All four corners visible"].exists)
                XCTAssertEqual(app.staticTexts["court.check"].firstMatch.label, "Untapped lines: beyond the horizon, limit 3 px")
            }
            try auditScreen(app)
            attachScreenshot(app, name: "t13-\(appearance == .dark ? "dark" : "light")-\(scenario)")
            app.terminate()
        }
    }
}
