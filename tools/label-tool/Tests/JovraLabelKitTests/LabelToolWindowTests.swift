import AppKit
import JovraBenchmark
@testable import JovraLabelKit
import SwiftUI
import XCTest

/// The founder's flow, driven through the real window with real key and mouse events on the synthetic sample
/// video: open, step frames, mark a hit, a stroke type, a bounce and four court corners with one key each,
/// undo, redo and save. The events take the same route as in the running app (`LabelWindow.sendEvent` and
/// `performKeyEquivalent`); nothing calls the session's commands directly.
///
/// The out-of-process twin is `UITests/LabelToolUITests.swift` (XCUITest on the built app).
@MainActor
final class LabelToolWindowTests: LabelWindowTestCase {
    func testFounderFlowOnTheSyntheticSampleVideo() async throws {
        try await openSample()
        let truth = try SampleVideo.truth()
        let recording = try XCTUnwrap(session.labels?.recording)
        XCTAssertEqual(recording.sha256, try RecordingFingerprint.sha256(of: try SampleVideo.url()))
        XCTAssertEqual([recording.width, recording.height], [640, 360])
        XCTAssertEqual(recording.frameRate, .init(num: 60, den: 1))
        XCTAssertEqual(recording.duration, RationalTime(value: 20, timescale: 1))
        XCTAssertEqual(session.labelsURL?.lastPathComponent, "rec-\(recording.sha256.prefix(12)).labels.json")
        XCTAssertEqual(session.labels?.split, try LabelSplit(recordingSha256: recording.sha256, duration: recording.duration))
        XCTAssertEqual(session.displayedTime, SampleVideo.frame(0))
        XCTAssertEqual(controller.window.contentView?.frame.size, LabelWindowController.initialContentSize(),
                       "the window keeps its size: the key legend scrolls instead of growing it")
        XCTAssertEqual(LabelWindowController.initialContentSize(screen: NSSize(width: 2560, height: 1400)), NSSize(width: 1320, height: 820))
        XCTAssertEqual(LabelWindowController.initialContentSize(screen: NSSize(width: 1176, height: 860)), NSSize(width: 1136, height: 800))
        XCTAssertEqual(LabelWindowController.initialContentSize(screen: NSSize(width: 800, height: 600)), NSSize(width: 1040, height: 640))

        // Hit candidates were pre-filled from the sound: one on every hit click of the ground truth.
        let candidates = try XCTUnwrap(session.labels?.hitCandidates)
        XCTAssertEqual(candidates.method, "jovra.audioOnsets.v1")
        for hit in truth.events ?? [] {
            XCTAssertTrue(candidates.items.contains { abs($0.time.seconds - hit.time.seconds) <= 0.010 }, "candidate on the hit at \(hit.time.seconds) s")
        }
        XCTAssertTrue(candidates.items.allSatisfy { $0.decision == .pending })

        // N: the first candidate is the serve at frame 90. H confirms it as a hit by the near player; 1 tags a serve.
        press("n")
        try await wait("the first candidate's frame") { self.session.displayedTime == SampleVideo.frame(90) }
        press("h")
        XCTAssertEqual(session.labels?.hits, [.init(time: SampleVideo.frame(90), player: .near)])
        XCTAssertEqual(session.selection, .hit(time: SampleVideo.frame(90), player: .near))
        XCTAssertEqual(session.document?.candidateCounts().confirmed, 1)
        press("1")
        XCTAssertEqual(session.labels?.hits.first?.stroke, .serve)
        XCTAssertEqual(session.notice?.text, "Serve at 0:01.500.")

        // Frame by frame, both ways: each press lands on exactly the next frame.
        try await step(1, to: 91)
        try await step(1, to: 92)
        try await step(-1, to: 91)
        try await step(10, shift: true, to: 101)
        try await step(10, shift: true, to: 111)
        for frame in 112...115 { try await step(1, to: Int64(frame)) }

        // B, then a click on the picture: the bounce of frame 115 with its image point.
        press("b")
        XCTAssertEqual(session.placement, .bounce)
        try click(x: 0.5, y: 0.25)
        XCTAssertNil(session.placement)
        let bounce = try XCTUnwrap(session.labels?.bounces.first)
        XCTAssertEqual(bounce.time, SampleVideo.frame(115))
        XCTAssertEqual(bounce.imagePoint.x, 0.5, accuracy: 0.002)
        XCTAssertEqual(bounce.imagePoint.y, 0.25, accuracy: 0.002)
        XCTAssertTrue(bounce.inPlay)
        press("x")
        XCTAssertEqual(session.labels?.bounces.first?.inPlay, false)
        press("x")
        XCTAssertEqual(session.labels?.bounces.first?.inPlay, true)

        // With the pointer on the ball, B alone places the bounce: one key, no click.
        try await step(1, to: 116)
        try hover(x: 0.6, y: 0.4)
        XCTAssertEqual(try XCTUnwrap(session.pointer).x, 0.6, accuracy: 0.002)
        press("b")
        XCTAssertNil(session.placement)
        XCTAssertEqual(session.labels?.bounces.map(\.time), [SampleVideo.frame(115), SampleVideo.frame(116)])
        XCTAssertEqual(try XCTUnwrap(session.labels?.bounces.last).imagePoint.y, 0.4, accuracy: 0.002)
        try hover(x: 1.4, y: 0.4)
        XCTAssertNil(session.pointer, "off the picture there is no pointer position")
        press(.delete)                                              // the bounce just marked is selected
        XCTAssertEqual(session.labels?.bounces.map(\.time), [SampleVideo.frame(115)])
        try await step(-1, to: 115)

        // C and a click, four times: the doubles corners in order.
        let corners = [(0.3, 0.2), (0.7, 0.2), (0.95, 0.9), (0.05, 0.9)]
        for (x, y) in corners {
            press("c")
            XCTAssertEqual(session.placement, .corner)
            try click(x: x, y: y)
        }
        let position = try XCTUnwrap(session.labels?.cameraPositions.first)
        XCTAssertEqual(position.from, SampleVideo.frame(0))
        XCTAssertEqual(position.corners.order, "farLeft,farRight,nearRight,nearLeft")
        for (point, expected) in zip(position.corners.points, corners) {
            XCTAssertEqual(try XCTUnwrap(point).x, expected.0, accuracy: 0.002)
            XCTAssertEqual(try XCTUnwrap(point).y, expected.1, accuracy: 0.002)
        }

        // A second hit by the far player on the next candidate (frame 151), a rally around both, and undo / redo.
        press("n")
        try await wait("the second candidate's frame") { self.session.displayedTime == SampleVideo.frame(151) }
        press("j")
        press("3")
        XCTAssertEqual(session.labels?.hits.map(\.player), [.near, .far])
        XCTAssertEqual(session.labels?.hits.last?.stroke, .backhand)
        press("]")
        XCTAssertEqual(session.notice?.kind, .warning, "] without [ is refused with a reason")
        XCTAssertEqual(session.notice?.text, "No rally is open. Press [ on the frame where the rally starts.")
        press("[")
        XCTAssertEqual(session.document?.openRallyStart, SampleVideo.frame(151))
        try await step(10, shift: true, to: 161)
        press("]")
        XCTAssertEqual(session.labels?.rallies, [.init(start: SampleVideo.frame(151), end: SampleVideo.frame(161))])

        press(.character("z"), command: true)                       // undo: the rally is open again
        XCTAssertEqual(session.labels?.rallies, [])
        XCTAssertEqual(session.document?.openRallyStart, SampleVideo.frame(151))
        press(.character("z"), command: true)                       // undo: no rally at all
        XCTAssertNil(session.document?.openRallyStart)
        press(.character("z"), command: true)                       // undo: the backhand tag
        XCTAssertNil(session.labels?.hits.last?.stroke)
        press(.character("z"), shift: true, command: true)          // redo three times
        press(.character("z"), shift: true, command: true)
        press(.character("z"), shift: true, command: true)
        XCTAssertEqual(session.labels?.hits.last?.stroke, .backhand)
        XCTAssertEqual(session.labels?.rallies.count, 1)
        XCTAssertFalse(session.canRedo)

        // Delete removes the selected label; undo brings it back. Frame 151 carries two labels, the rally's start
        // and the hit: "," reaches the rally first, then the hit, and the status line names the one selected.
        press(",")
        try await wait("the previous label's frame") { self.session.displayedTime == SampleVideo.frame(151) }
        XCTAssertEqual(session.selection, .rally(start: SampleVideo.frame(151)))
        XCTAssertEqual(session.notice?.text, "Rally at 0:02.516.")
        press(",")
        XCTAssertEqual(session.selection, .hit(time: SampleVideo.frame(151), player: .far))
        XCTAssertEqual(session.notice?.text, "Hit by the far player at 0:02.516.")
        press(.delete)
        XCTAssertEqual(session.labels?.hits.count, 1)
        press(.character("z"), command: true)
        XCTAssertEqual(session.labels?.hits.count, 2)

        // Nothing is on disk until ⌘S (autosave is off in this test); then the file is exactly the session.
        let url = try XCTUnwrap(session.labelsURL)
        XCTAssertTrue(session.isDirty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        press(.character("s"), command: true)
        XCTAssertFalse(session.isDirty)
        XCTAssertNotNil(session.lastSaved)
        let saved = try savedLabels()
        XCTAssertEqual(saved, session.document?.stored)
        XCTAssertEqual(saved.problems(), [])
        XCTAssertEqual(saved.labelledBy, .init(method: .human, tool: "jovra-label@1.0.0"))
        XCTAssertEqual(saved.counts, .init(hits: 2, strokes: 2, bounces: 1, rallies: 1, cameraPositions: 1))
        XCTAssertEqual(saved.hitCandidates?.items.filter { $0.decision == .confirmed }.count, 2)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("sample-2026"), "a label file never names the video file")
        XCTAssertFalse(text.contains(NSUserName()), "a label file never names a person or a home folder")
    }

    func testReopeningLoadsTheSavedLabelsAndTheScorerReadsThem() async throws {
        try await openSample(autosave: true, findCandidates: false)
        press(.right, option: true)                                 // one second in
        try await wait("frame 60") { self.session.displayedTime == SampleVideo.frame(60) }
        press("h")
        press("2")
        press("[")
        let url = try XCTUnwrap(session.labelsURL)
        let saved = try savedLabels()                               // autosave wrote every edit
        XCTAssertEqual(saved.hits, [.init(time: SampleVideo.frame(60), player: .near, stroke: .forehand)])
        XCTAssertEqual(saved.rallies, [.init(start: SampleVideo.frame(60), end: nil)], "the open rally is kept")
        XCTAssertFalse(session.isDirty)

        controller.window.orderOut(nil)
        try await openSample(autosave: true, findCandidates: false)
        XCTAssertEqual(session.labelsURL, url)
        XCTAssertEqual(session.labels?.hits, saved.hits)
        XCTAssertEqual(session.document?.openRallyStart, SampleVideo.frame(60))
        XCTAssertEqual(session.notice?.text, "Opened with 1 hits, 0 bounces and 0 rallies already labelled.")

        // The label file the tool wrote is what the scorer takes: a stage that saw the hit 20 ms late.
        press(.right, option: true)
        try await wait("frame 60") { self.session.displayedTime == SampleVideo.frame(60) }
        press(.right, option: true)
        try await wait("frame 120") { self.session.displayedTime == SampleVideo.frame(120) }
        press("]")
        let labels = try savedLabels()
        let observations = StageObservations(recordingSha256: labels.recording.sha256, producer: "rule:test@1.0.0",
                                             hits: [.init(time: RationalTime(value: 1020, timescale: 1000))])
        let report = try LabelScorer.score(labels: labels, observations: observations)
        let split = labels.split.split(of: SampleVideo.frame(60))
        XCTAssertEqual(report.row(split, group: "hits", name: "recall")?.value, "1.0000")
        XCTAssertEqual(report.row(split, group: "hits", name: "timing bias")?.value, "+20.000")
    }

    func testPlaybackRunsAndPausesAndTheKeysStillWorkWhileItPlays() async throws {
        try await openSample(findCandidates: false)
        press(.space)
        XCTAssertTrue(session.isPlaying)
        try await wait("playback to pass half a second") { self.session.displayedTime.seconds > 0.5 }
        press("h")                                                  // marking never needs a pause
        XCTAssertEqual(session.labels?.hits.count, 1)
        press(.space)
        XCTAssertFalse(session.isPlaying)
        let stopped = session.displayedTime
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertLessThanOrEqual(abs(session.displayedTime.seconds - stopped.seconds), 0.05, "paused means the frame stays")
        press("=")
        XCTAssertEqual(session.rate, 2)
        press("-")
        press("-")
        XCTAssertEqual(session.rate, 0.5)
    }

    func testKeysDoNothingBeforeARecordingIsOpenAndAMissingFileSaysWhy() async throws {
        controller = LabelWindowController(session: LabelSession(configuration: .init(labelsDirectory: scratch)))
        press("h")
        press(.character("s"), command: true)
        XCTAssertEqual(session.phase, .empty)
        XCTAssertNil(session.labels)
        var asked = 0
        session.onOpenRequested = { asked += 1 }
        press(.character("o"), command: true)
        XCTAssertEqual(asked, 1, "⌘O asks for a recording in every state")
        await session.open(video: scratch.appendingPathComponent("missing.mp4"))
        guard case .failed(let reason) = session.phase else { return XCTFail("a missing file fails to open") }
        XCTAssertFalse(reason.isEmpty)
        try Data("not a video".utf8).write(to: scratch.appendingPathComponent("notes.mp4"))
        await session.open(video: scratch.appendingPathComponent("notes.mp4"))
        guard case .failed = session.phase else { return XCTFail("a file that is not a video fails to open") }
    }

    func testALabelFileThatCannotBeTrustedIsLeftUntouched() async throws {
        let hash = try RecordingFingerprint.sha256(of: try SampleVideo.url())
        let target = scratch.appendingPathComponent(BenchmarkLabels.fileName(recordingSha256: hash))
        try Data("{\"kind\": \"something else\"}".utf8).write(to: target)
        controller = LabelWindowController(session: LabelSession(configuration: .init(labelsDirectory: scratch)))
        await session.open(video: try SampleVideo.url())
        guard case .failed(let reason) = session.phase else { return XCTFail("an unreadable label file stops the open") }
        XCTAssertTrue(reason.contains("left untouched"), reason)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "{\"kind\": \"something else\"}")
    }

    /// Renders the window for the pull request's evidence when JOVRA_LABEL_SNAPSHOT_DIR is set.
    func testSnapshotsForEvidence() async throws {
        guard let folder = ProcessInfo.processInfo.environment["JOVRA_LABEL_SNAPSHOT_DIR"] else {
            throw XCTSkip("set JOVRA_LABEL_SNAPSHOT_DIR to write the evidence images")
        }
        let output = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            controller = LabelWindowController(session: LabelSession(configuration: .init(labelsDirectory: scratch)))
            controller.window.appearance = NSAppearance(named: appearance)
            try snapshot(to: output.appendingPathComponent("label-tool-\(name)-1-empty.png"))
            try? FileManager.default.removeItem(at: scratch)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            try await openSample()
            controller.window.appearance = NSAppearance(named: appearance)
            press("n")
            try await wait("frame 90") { self.session.displayedTime == SampleVideo.frame(90) }
            press("h")
            press("1")
            for (x, y) in [(0.33, 0.30), (0.67, 0.30), (0.93, 0.93), (0.07, 0.93)] {
                press("c")
                try click(x: x, y: y)
            }
            press("[")
            try await step(10, shift: true, to: 100)
            try await step(10, shift: true, to: 110)
            for frame in 111...115 { try await step(1, to: Int64(frame)) }
            press("b")
            try snapshot(to: output.appendingPathComponent("label-tool-\(name)-2-placing-bounce.png"))
            try click(x: 0.42, y: 0.34)
            try snapshot(to: output.appendingPathComponent("label-tool-\(name)-3-labelled.png"))
            press("]")
            press("]")
            try snapshot(to: output.appendingPathComponent("label-tool-\(name)-4-refusal.png"))
            controller.window.orderOut(nil)
        }
    }

    private func snapshot(to url: URL) throws {
        let view = try XCTUnwrap(controller.window.contentView)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
