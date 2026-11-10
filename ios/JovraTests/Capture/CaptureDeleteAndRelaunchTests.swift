import AVFoundation
import JovraCore
import JovraMedia
import XCTest
@testable import Jovra

private struct RefusingSink: RecordingSink {
    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws {
        throw CocoaError(.fileWriteOutOfSpace)
    }
}

/// T17's library seams: deleting a recording on disk, and the report the relaunch sheet shows.
final class CaptureDeleteAndRelaunchTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testFramingCreatesNoSessionAndDeleteRemovesTheRecordingFolderFromDisk() async throws {
        let library = try LocalCaptureLibrary(root: root)
        let source = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let clock = VirtualCaptureClock()
        let camera = FixtureCamera(url: source, duration: CMTime(value: 2, timescale: 1), clock: clock)
        let capture = NativeCaptureCoordinator(library: library, source: camera, clock: clock)
        try await capture.prepare(seed: CaptureSetupChoices.defaultSinglesDraft.seed, preset: .init(width: 1280, height: 720),
                                  microphone: .notRequested)
        let whileFraming = try await library.sessions()
        XCTAssertTrue(whileFraming.isEmpty, "framing and closing leave nothing in the library")

        try await capture.start()
        try await camera.waitUntilFinished()
        let id = try XCTUnwrap(capture.sessionID)
        let folder = try await library.recordingFolder(id)
        let originals = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("originals").path)
        XCTAssertFalse(originals.isEmpty, "the recording wrote media before it was deleted")

        try await capture.deleteRecording()
        XCTAssertTrue(capture.isDeleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "the session folder is gone from disk")
        let reopened = try LocalCaptureLibrary(root: root)
        let after = try await reopened.sessions()
        XCTAssertFalse(after.contains { $0.id == id.rawValue })
    }

    @MainActor
    func testTheRelaunchReportCarriesGapsAndThePartialRecoveryReport() async throws {
        let library = try LocalCaptureLibrary(root: root)
        let id = try await library.createCapture(CaptureSetupChoices.defaultSinglesDraft.seed, mode: .simulatorFixture)
        let folder = try await library.recordingFolder(id)
        let source = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let clock = VirtualCaptureClock()
        let camera = FixtureCamera(url: source, duration: CMTime(value: 1, timescale: 1), clock: clock)
        let budget = FakeDeviceBudget(.init(freeBytes: 64 * 1024 * 1024, batteryFraction: nil, lowPowerMode: false, thermalState: .nominal))
        let engine = CaptureEngine(source: camera, clock: clock, sink: RefusingSink(), budget: budget)
        _ = try await engine.prepare(.init(width: 1280, height: 720), microphone: .notRequested)
        try await engine.start(sessionID: id.rawValue, folder: folder)
        try await camera.waitUntilFinished()
        try await engine.pause()
        clock.advance(by: CMTimeSubtract(CMTime(value: 5, timescale: 1), clock.now()))
        try await engine.resume()
        try await camera.waitUntilFinished()
        _ = try? await engine.stop()   // The handoff fails, as if the app died before acknowledging it.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("originals/segment-0.mp4"))

        let relaunched = try LocalCaptureLibrary(root: root)
        let summary = await relaunched.reconcileAtStartup()
        XCTAssertEqual(summary.partiallyRecovered, 1)
        XCTAssertEqual(summary.recovered, 0)
        let report = try XCTUnwrap(summary.reports.first)
        XCTAssertEqual(report.id, id.rawValue)
        XCTAssertEqual(report.title, "Singles match")
        XCTAssertEqual(report.outcome, .partial)
        XCTAssertEqual(report.unrecoverable.map(\.path), ["originals/segment-0.mp4"])
        XCTAssertEqual(report.unrecoverable.map(\.reason), ["The segment file was never saved to this iPhone."])
        XCTAssertEqual(report.gaps, [SessionGap(startMs: 0, endMs: 1000, reason: .other),
                                     SessionGap(startMs: 1000, endMs: 5000, reason: .userPaused)])
        XCTAssertEqual(report.savedThroughMs, 6000)
        let document = try await relaunched.load(id)
        XCTAssertEqual(document.original?.state, .partial)
        XCTAssertEqual(document.recording.segments.map(\.id), ["segment-1"], "every playable segment is kept")

        let again = try LocalCaptureLibrary(root: root)
        let second = await again.reconcileAtStartup()
        XCTAssertTrue(second.reports.isEmpty, "the sheet is shown once, at the launch that recovered it")
    }
}
