import XCTest

/// The founder's flow in the built app, from outside the process: open the synthetic sample video, step a
/// frame, mark a hit, a stroke type, a bounce and the four court corners with one key each, undo, redo and
/// save, then read the label file the app wrote.
///
/// Needs the rendered sample (`python3 scripts/media/render.py --set sample`) and a Mac that allows UI
/// automation. Run with scripts/benchmarks/label-tool-ui-test.sh. The in-process twin, which needs neither,
/// is Tests/JovraLabelKitTests/LabelToolWindowTests.swift.
final class LabelToolUITests: XCTestCase {
    private var labelsDirectory: URL!
    private var app: XCUIApplication!

    /// tools/label-tool/UITests/LabelToolUITests.swift -> the repository root.
    private static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private static func sampleVideo() throws -> URL {
        let truthURL = repository.appendingPathComponent("spec/fixtures/media/sample/2026-09-09-match.truth.json")
        let truth = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: truthURL)) as? [String: Any])
        let path = try XCTUnwrap((truth["media"] as? [String: Any])?["path"] as? String)
        let url = repository.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("The synthetic sample video is not rendered. Run: python3 scripts/media/render.py --set sample")
        }
        return url
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        labelsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("jovra-label-uitest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: labelsDirectory, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchArguments = ["--open", try Self.sampleVideo().path, "--labels-dir", labelsDirectory.path, "--mute", "--no-autosave"]
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let labelsDirectory { try? FileManager.default.removeItem(at: labelsDirectory) }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Everything an element says: its label and its value.
    private func text(_ identifier: String) -> String {
        let found = element(identifier)
        guard found.exists else { return "" }
        return [found.label, found.value as? String ?? ""].joined(separator: " ")
    }

    private func expect(_ identifier: String, says expected: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if text(identifier).contains(expected) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("\(identifier) says \"\(text(identifier))\", expected it to contain \"\(expected)\"", file: file, line: line)
    }

    /// Clicks the picture: `x` and `y` are fractions of the window, inside the picture area on its left.
    private func clickWindow(x: CGFloat, y: CGFloat) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).click()
    }

    func testFounderLabelsTheSyntheticSampleVideo() throws {
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "the window opens")
        expect("time", says: "0:00.000", timeout: 60)
        expect("candidate-status", says: "to review", timeout: 60)
        expect("count-hits", says: "0")

        // N: the first hit candidate (the serve click at 1.5 s). H: a hit by the near player. 1: a serve.
        app.typeKey("n", modifierFlags: [])
        expect("time", says: "0:01.500")
        app.typeKey("h", modifierFlags: [])
        expect("count-hits", says: "1")
        expect("status", says: "Hit, near player, at 0:01.500")
        app.typeKey("1", modifierFlags: [])
        expect("count-strokes", says: "1")
        expect("selection", says: "Stroke type: serve")

        // One frame forward and back (60 fps: 16.7 ms a frame).
        app.typeKey(.rightArrow, modifierFlags: [])
        expect("time", says: "0:01.516")
        app.typeKey(.leftArrow, modifierFlags: [])
        expect("time", says: "0:01.500")

        // B, then a click on the picture: a bounce with its image point.
        app.typeKey("b", modifierFlags: [])
        XCTAssertTrue(element("placement-prompt").waitForExistence(timeout: 10), "B asks for the point")
        clickWindow(x: 0.35, y: 0.45)
        expect("count-bounces", says: "1")

        // C and a click, four times: the court corners.
        for (x, y) in [(0.25, 0.36), (0.50, 0.36), (0.60, 0.62), (0.08, 0.62)] as [(CGFloat, CGFloat)] {
            app.typeKey("c", modifierFlags: [])
            XCTAssertTrue(element("placement-prompt").waitForExistence(timeout: 10), "C asks for the corner")
            clickWindow(x: x, y: y)
        }
        expect("count-corners", says: "4")

        // Undo takes the last corner back; redo restores it.
        app.typeKey("z", modifierFlags: .command)
        expect("count-corners", says: "3")
        app.typeKey("z", modifierFlags: [.command, .shift])
        expect("count-corners", says: "4")

        // ⌘S writes the label file; nothing was written before it (autosave is off for this run).
        expect("save-state", says: "Unsaved changes")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: labelsDirectory.path), [])
        app.typeKey("s", modifierFlags: .command)
        expect("save-state", says: "Saved")

        let files = try FileManager.default.contentsOfDirectory(atPath: labelsDirectory.path)
        XCTAssertEqual(files.count, 1)
        let name = try XCTUnwrap(files.first)
        XCTAssertTrue(name.hasPrefix("rec-") && name.hasSuffix(".labels.json"), name)
        let labels = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: labelsDirectory.appendingPathComponent(name))) as? [String: Any])
        XCTAssertEqual(labels["kind"] as? String, "jovra.benchmarkLabels")
        let hits = try XCTUnwrap(labels["hits"] as? [[String: Any]])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?["player"] as? String, "near")
        XCTAssertEqual(hits.first?["stroke"] as? String, "serve")
        let time = try XCTUnwrap(hits.first?["time"] as? [String: Any])
        XCTAssertEqual((time["value"] as? Double ?? 0) / (time["timescale"] as? Double ?? 1), 1.5, accuracy: 0.0001)
        let bounces = try XCTUnwrap(labels["bounces"] as? [[String: Any]])
        XCTAssertEqual(bounces.count, 1)
        XCTAssertEqual(bounces.first?["inPlay"] as? Bool, true)
        let point = try XCTUnwrap(bounces.first?["imagePoint"] as? [String: Any])
        XCTAssertTrue((0.0...1.0).contains(point["x"] as? Double ?? -1) && (0.0...1.0).contains(point["y"] as? Double ?? -1))
        let positions = try XCTUnwrap(labels["cameraPositions"] as? [[String: Any]])
        let corners = try XCTUnwrap((positions.first?["corners"] as? [String: Any])?["points"] as? [Any])
        XCTAssertEqual(corners.filter { !($0 is NSNull) }.count, 4)
        XCTAssertEqual((labels["labelledBy"] as? [String: Any])?["method"] as? String, "human")
    }

    func testEveryControlHasADescription() throws {
        app.launch()
        expect("time", says: "0:00.000", timeout: 60)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription]) { issue in
            // The window's own close, minimise and zoom buttons belong to AppKit.
            issue.element?.elementType == .window || issue.element == nil
        }
    }
}
