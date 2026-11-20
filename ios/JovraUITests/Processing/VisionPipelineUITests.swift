import Foundation
import JovraVision
import XCTest

#if targetEnvironment(simulator)
/// V00: the JovraVision pipeline as the processing queue's analyze stage, driven by its fixture stages
/// (`-processingAnalyzer visionFixture`) over a fixture-camera recording (the synthetic sample video).
///
/// The simulator shares one file system between the app and this runner, so the tests read the app's
/// analysis folder directly: checkpoints at the moment JOVRA is killed, the run log after the relaunch, and
/// the finished observations, which are compared byte for byte with an uninterrupted run made here.
/// Simulator only: on a device the runner cannot read the app's container.
final class VisionPipelineUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private static let stages = ["fixture.luma", "fixture.lumaShift"]

    @MainActor
    func testAnalysisKilledMidRunResumesAfterRelaunchToByteIdenticalObservations() async throws {
        var app = XCUIApplication.launchJovra {
            $0.appearance = .light
            $0.library = .relaunchable
            $0.processingAnalyzer = .visionFixture
        }
        recordAndOpenProcessing(app, title: "Vision resume " + UUID().uuidString.prefix(4), seconds: 4)
        let analyze = stage("analyze", in: app)
        XCTAssertTrue(waitFor(analyze, timeout: 30) { $0.hasPrefix("In progress") && (Self.percent(in: $0) ?? 0) >= 15 },
                      "analysis is under way: \(value(of: analyze))")
        attachScreenshot(app, name: "v00-processing-light-analysing")

        // Kill JOVRA mid-analysis, as the system would.
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        let library = try AppFiles.library(folder: "JOVRA-relaunchable")
        let session = try XCTUnwrap(try AppFiles.sessions(in: library).first)
        let analysis = library.appendingPathComponent("analysis/\(session.lastPathComponent)")
        let interrupted = try XCTUnwrap(Self.stages.compactMap { try? AppFiles.checkpoint(stage: $0, in: analysis) }.first,
                                        "a checkpoint is on disk when JOVRA dies")
        XCTAssertGreaterThan(interrupted.nextWindow, 0)
        XCTAssertLessThan(interrupted.nextWindow, interrupted.windows)
        XCTAssertFalse(FileManager.default.fileExists(atPath: analysis.appendingPathComponent("fixture.lumaShift.output.json").path),
                       "the analysis had not finished")

        // Relaunch: the queue re-queues the interrupted stage and the runner resumes from the checkpoint.
        app = XCUIApplication.launchJovra {
            $0.appearance = .light
            $0.library = .relaunch
            $0.processingAnalyzer = .visionFixture
        }
        defer { app.terminate() }
        let outputs = Self.stages.map { analysis.appendingPathComponent("\($0).output.json") }
        let finished = await AppFiles.wait(timeout: 120) { outputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) } }
        XCTAssertTrue(finished, "the resumed analysis finishes")
        let log = try JSONDecoder().decode(RunLog.self, from: Data(contentsOf: analysis.appendingPathComponent("run.json")))
        XCTAssertEqual(log.resumes.first?.stage, interrupted.stage)
        XCTAssertEqual(log.resumes.first?.fromWindow, interrupted.nextWindow, "it resumed exactly where the checkpoint stood")

        // An uninterrupted run of the same stages over the same original, made here.
        let reference = try await AnalysisRunner(stages: FixtureStages.pipeline(),
                                                 reader: try await RecordingWindowReader.open(try AppFiles.sources(of: session)),
                                                 workspace: FileManager.default.temporaryDirectory.appendingPathComponent("v00-\(UUID().uuidString)"))
            .run()
        for (stage, url) in zip(Self.stages, outputs) {
            let written = try Data(contentsOf: url)
            XCTAssertEqual(written, reference.outputs[AnalysisStageID(stringLiteral: stage)], "\(stage): byte-identical observations")
            let attachment = XCTAttachment(data: written, uniformTypeIdentifier: "public.json")
            attachment.name = "v00-\(stage)-output"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let luma = try JSONDecoder().decode(AnalysisStageOutput<FrameLuma>.self, from: Data(contentsOf: outputs[0]))
        XCTAssertGreaterThan(luma.observations.count, 60, "every frame of the recording was read")
        XCTAssertEqual(luma.coverage.skipped, [], "the whole recording was analysed")
    }

    @MainActor
    func testRecordingAndReplayStayUsableWhileAnalysisRuns() async throws {
        let app = XCUIApplication.launchJovra {
            $0.appearance = .light
            $0.library = .fresh
            $0.processingAnalyzer = .visionFixture
        }
        defer { app.terminate() }
        recordAndOpenProcessing(app, title: "Vision busy " + UUID().uuidString.prefix(4), seconds: 25)
        let analyze = stage("analyze", in: app)
        XCTAssertTrue(waitFor(analyze, timeout: 60) { $0.hasPrefix("In progress") && (Self.percent(in: $0) ?? 0) >= 3 },
                      "analysis is under way: \(value(of: analyze))")
        let library = try AppFiles.newestLibrary(prefix: "JOVRA-fresh-")
        let first = try XCTUnwrap(try AppFiles.sessions(in: library).first)
        let firstAnalysis = library.appendingPathComponent("analysis/\(first.lastPathComponent)")
        let firstOutput = firstAnalysis.appendingPathComponent("fixture.lumaShift.output.json")

        // Record a second session while the first one's analysis is unfinished. The queue holds analysis
        // while capture runs (it never competes with recording) and resumes it from its checkpoint after.
        app.buttons["processing.close"].tap()
        recordAndOpenProcessing(app, title: "Vision second " + UUID().uuidString.prefix(4), seconds: 3,
                                screenshot: "v00-capture-dark-during-analysis") {
            XCTAssertFalse(FileManager.default.fileExists(atPath: firstOutput.path),
                           "the first analysis is still unfinished when recording starts")
        }
        XCTAssertTrue(value(of: stage("saved", in: app)).hasPrefix("Done"), "the second recording is saved")
        XCTAssertTrue(app.buttons["processing.viewSession"].isEnabled, "the saved original can be watched at once")

        // Replay while analysis runs: the second session's original opens, decodes and steps frame by frame
        // while the first session's analysis keeps writing checkpoints.
        XCTAssertTrue(waitFor(analyze, timeout: 30) { _ in
            AppFiles.windowsDone(in: firstAnalysis, stages: Self.stages) > 0 && !FileManager.default.fileExists(atPath: firstOutput.path)
        })
        let before = AppFiles.windowsDone(in: firstAnalysis, stages: Self.stages)
        let view = app.buttons["processing.viewSession"]
        for _ in 0..<6 where !view.isHittable { app.swipeUp() }
        view.tap()
        let frame = app.staticTexts["replay.frame"]
        XCTAssertTrue(frame.waitForExistence(timeout: 20), "the original decodes during analysis")
        XCTAssertTrue(frame.label.hasPrefix("f 0 ·"), frame.label)
        let next = app.buttons["replay.frame.next"]
        for _ in 0..<6 where !next.isHittable { app.swipeUp() }
        next.tap()
        XCTAssertTrue(waitFor(frame, timeout: 10) { _ in frame.label.hasPrefix("f 1 ·") }, "steps to the next frame: \(frame.label)")
        app.buttons["replay.play"].tap()
        attachScreenshot(app, name: "v00-replay-dark-during-analysis")
        app.buttons["replay.pause"].tap()
        let during = AppFiles.windowsDone(in: firstAnalysis, stages: Self.stages)
        XCTAssertGreaterThan(during, before, "analysis kept checkpointing windows while the video played")

        // Both analyses finish; the first one says it resumed after the recording interrupted it.
        let secondAnalysis = library.appendingPathComponent("analysis/\(try XCTUnwrap(try AppFiles.sessions(in: library).last).lastPathComponent)")
        let bothDone = await AppFiles.wait(timeout: 240) {
            FileManager.default.fileExists(atPath: firstOutput.path)
                && FileManager.default.fileExists(atPath: secondAnalysis.appendingPathComponent("fixture.lumaShift.output.json").path)
        }
        XCTAssertTrue(bothDone, "both analyses finish")
        let log = try JSONDecoder().decode(RunLog.self, from: Data(contentsOf: firstAnalysis.appendingPathComponent("run.json")))
        XCTAssertFalse(log.resumes.isEmpty, "recording interrupted the first analysis, which resumed from its checkpoint")
    }

    // MARK: Helpers

    /// Records a fixture-camera singles session of at least `seconds`, stops it and opens its processing route.
    @MainActor private func recordAndOpenProcessing(_ app: XCUIApplication, title: String, seconds: Int, screenshot: String? = nil,
                                                    beforeStart: () -> Void = {}) {
        app.startSinglesCapture(sessionName: title, me: "Jon", opponent: "Alex")
        let start = app.buttons["capture.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        for _ in 0..<6 where !start.isHittable { app.swipeUp() }
        beforeStart()
        start.tap()
        let saved = app.staticTexts["capture.confirmedTime"]
        XCTAssertTrue(waitFor(saved, timeout: Double(seconds) + 20) { _ in saved.exists && Self.seconds(in: saved.label) >= seconds },
                      "recording runs: \(saved.exists ? saved.label : "no saved time")")
        if let screenshot { attachScreenshot(app, name: screenshot) }
        let stop = app.buttons["capture.stop"]
        for _ in 0..<6 where !stop.isHittable { app.swipeUp() }
        stop.tap()
        let confirm = app.buttons.matching(identifier: "capture.confirmStop").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let processing = app.buttons["capture.processing"]
        XCTAssertTrue(processing.waitForExistence(timeout: 20))
        for _ in 0..<6 where !processing.isHittable { app.swipeUp() }
        processing.tap()
        XCTAssertTrue(app.heading("Processing").waitForExistence(timeout: 10))
    }

    @MainActor private func stage(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["processing.stage.\(id)"]
    }

    @MainActor private func value(of element: XCUIElement) -> String { (element.value as? String) ?? "" }

    @MainActor private func waitFor(_ element: XCUIElement, timeout: TimeInterval, _ condition: @escaping (String) -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition(self.value(of: element)) }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed
    }

    private static func percent(in value: String) -> Int? {
        guard let range = value.range(of: #"\d+(?=\s?%)"#, options: .regularExpression) else { return nil }
        return Int(value[range])
    }

    /// "Saved through 0:04" → 4.
    private static func seconds(in label: String) -> Int {
        let parts = label.split(separator: " ").last?.split(separator: ":").compactMap { Int($0) } ?? []
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    private struct RunLog: Decodable {
        struct Resume: Decodable { var stage: String; var fromWindow: Int }
        var resumes: [Resume]
    }
}

/// The app's files, read from this simulator's other app containers (UI tests only run on the simulator).
enum AppFiles {
    struct Checkpoint: Decodable { var stage: String; var nextWindow: Int; var windows: Int }

    private static var applications: URL { URL(fileURLWithPath: NSHomeDirectory()).deletingLastPathComponent() }

    /// The test library in JOVRA's temporary folder.
    static func library(folder: String) throws -> URL {
        for container in try FileManager.default.contentsOfDirectory(at: applications, includingPropertiesForKeys: nil) {
            let root = container.appendingPathComponent("tmp/\(folder)")
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("sessions").path) { return root }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    /// The most recently changed library whose folder starts with `prefix`.
    static func newestLibrary(prefix: String) throws -> URL {
        var found: [(Date, URL)] = []
        for container in try FileManager.default.contentsOfDirectory(at: applications, includingPropertiesForKeys: nil) {
            let tmp = container.appendingPathComponent("tmp")
            for folder in (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            where folder.lastPathComponent.hasPrefix(prefix) {
                let sessions = folder.appendingPathComponent("sessions")
                let date = (try? sessions.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                found.append((date, folder))
            }
        }
        guard let newest = found.max(by: { $0.0 < $1.0 })?.1 else { throw CocoaError(.fileNoSuchFile) }
        return newest
    }

    /// Session folders, oldest first.
    static func sessions(in library: URL) throws -> [URL] {
        let folders = try FileManager.default.contentsOfDirectory(at: library.appendingPathComponent("sessions"), includingPropertiesForKeys: nil)
        let dated = folders.compactMap { folder -> (String, URL)? in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("session.json")),
                  let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let created = document["createdAt"] as? String else { return nil }
            return (created, folder)
        }
        return dated.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// The session's finalized segments, as the app hands them to JovraVision.
    static func sources(of session: URL) throws -> [RecordingWindowReader.Source] {
        let data = try Data(contentsOf: session.appendingPathComponent("session.json"))
        let document = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let segments = try XCTUnwrap((document["recording"] as? [String: Any])?["segments"] as? [[String: Any]])
        return try segments.filter { $0["finalized"] as? Bool == true }
            .sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
            .map { segment in
                let path = try XCTUnwrap((segment["file"] as? [String: Any])?["path"] as? String)
                return RecordingWindowReader.Source(url: session.appendingPathComponent(path),
                                                    startMs: try XCTUnwrap(segment["startMs"] as? Int),
                                                    durationMs: try XCTUnwrap(segment["durationMs"] as? Int))
            }
    }

    static func checkpoint(stage: String, in analysis: URL) throws -> Checkpoint {
        try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: analysis.appendingPathComponent("\(stage)/checkpoint.json")))
    }

    /// Windows checkpointed or finished so far, over all stages.
    static func windowsDone(in analysis: URL, stages: [String]) -> Int {
        stages.reduce(0) { total, stage in
            if let checkpoint = try? checkpoint(stage: stage, in: analysis) { return total + checkpoint.nextWindow }
            let output = analysis.appendingPathComponent("\(stage).output.json")
            guard let data = try? Data(contentsOf: output),
                  let document = try? JSONDecoder().decode(AnalysisStageOutput<AnyObservation>.self, from: data) else { return total }
            let windows = AnalysisRunner.plan(500, over: document.media.segments).count
            return total + windows
        }
    }

    struct AnyObservation: Codable, Equatable, Sendable {}

    static func wait(timeout: TimeInterval, _ condition: @Sendable () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return true
    }
}
#endif
