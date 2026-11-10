import AVFoundation
import JovraCore
import JovraMedia
import XCTest
@testable import Jovra

/// The library that refuses the final save, as a full disk or a missing session document would.
private struct RefusingSink: RecordingSink {
    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws {
        throw CocoaError(.fileWriteOutOfSpace)
    }
}

private struct UnreadableBudget: DeviceBudget {
    func snapshot() async throws -> DeviceBudgetSnapshot { throw CocoaError(.fileReadUnknown) }
}

/// A budget that reads once (framing) and then cannot be read.
private final class FailingAfterFirstBudget: DeviceBudget, @unchecked Sendable {
    private let lock = NSLock()
    private var first: DeviceBudgetSnapshot?
    init(_ first: DeviceBudgetSnapshot) { self.first = first }
    func snapshot() async throws -> DeviceBudgetSnapshot {
        let reading = lock.withLock { () -> DeviceBudgetSnapshot? in defer { first = nil }; return first }
        guard let reading else { throw CocoaError(.fileReadUnknown) }
        return reading
    }
}

/// T17 review round 1: a stop that does not end as a saved recording is a state with a way out, and the
/// battery, storage and heat reading is re-read while recording.
final class CaptureStopFailureAndBudgetTests: XCTestCase {
    private var root: URL!
    private let healthy = DeviceBudgetSnapshot(freeBytes: 8_000_000_000, batteryFraction: 0.78, lowPowerMode: false, thermalState: .nominal)

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    private func recording(sink: (any RecordingSink)? = nil, budget: any DeviceBudget,
                           seconds: Int64 = 2) async throws -> (NativeCaptureCoordinator, LocalCaptureLibrary) {
        let library = try LocalCaptureLibrary(root: root)
        let source = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let clock = VirtualCaptureClock()
        let camera = FixtureCamera(url: source, duration: CMTime(value: seconds, timescale: 1), clock: clock)
        let capture = NativeCaptureCoordinator(library: library, source: camera, clock: clock, sink: sink, budget: budget)
        try await capture.prepare(seed: CaptureSetupChoices.defaultSinglesDraft.seed, preset: .init(width: 1280, height: 720),
                                  microphone: .notRequested)
        try await capture.start()
        try await camera.waitUntilFinished()
        return (capture, library)
    }

    // MARK: Stopped without a saved recording

    @MainActor
    func testAStopWhoseSaveIsRefusedEndsStoppedWithASaveFailureAndIsRecoveredAtRelaunch() async throws {
        let (capture, _) = try await recording(sink: RefusingSink(), budget: FakeDeviceBudget(healthy))
        do { try await capture.stop(); XCTFail("the refused save must surface") } catch {}

        XCTAssertEqual(capture.status?.phase, .stopped)
        XCTAssertNil(capture.savedRecording, "a refused save is never shown as saved")
        XCTAssertEqual(capture.stopFailure, .saveFailed)
        XCTAssertFalse(capture.isWorking)
        let status = try XCTUnwrap(capture.status)
        let state = CaptureRecordingState(status)
        XCTAssertEqual(state.pill, .stopped, "no REC dot on a stopped engine")
        XCTAssertEqual(CaptureRecordingCopy.pillText(state), "Stopped 0:02")
        XCTAssertEqual(state.stopFailure(isWorking: capture.isWorking, recorded: capture.stopFailure), .saveFailed)
        XCTAssertEqual(CaptureRecordingCopy.stopFailureMessage(.saveFailed, savedThroughMs: state.savedThroughMs),
                       "Video up to 0:02 is on this iPhone. JOVRA will look for it the next time it opens.")

        // What the message promises: the next launch finds the journal and adopts the recording.
        let id = try XCTUnwrap(capture.sessionID)
        let relaunched = try LocalCaptureLibrary(root: root)
        let summary = await relaunched.reconcileAtStartup()
        XCTAssertEqual(summary.recovered, 1)
        let document = try await relaunched.load(id)
        XCTAssertEqual(document.original?.state, .saved)
        XCTAssertEqual(document.recording.segments.count, 1)
    }

    @MainActor
    func testAFailedDeleteEndsStoppedSaysSoAndCanBeRetried() async throws {
        let (capture, library) = try await recording(budget: FakeDeviceBudget(healthy))
        let id = try XCTUnwrap(capture.sessionID)
        let folder = try await library.recordingFolder(id)
        let document = folder.appendingPathComponent("session.json")
        let parked = root.appendingPathComponent("parked-session.json")
        try FileManager.default.moveItem(at: document, to: parked)   // The store cannot trash what it cannot read.

        do { try await capture.deleteRecording(); XCTFail("the failed deletion must surface") } catch {}
        XCTAssertEqual(capture.status?.phase, .stopped, "the engine stopped before the deletion failed")
        XCTAssertEqual(capture.stopFailure, .deleteFailed)
        XCTAssertFalse(capture.isDeleted)
        XCTAssertNil(capture.savedRecording)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path), "the recording is still on this iPhone, as the screen says")

        try FileManager.default.moveItem(at: parked, to: document)
        try await capture.deleteRecording()
        XCTAssertTrue(capture.isDeleted)
        XCTAssertNil(capture.stopFailure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    // MARK: Budget

    @MainActor
    func testTheBudgetIsReReadWhileRecordingSoBatteryAndHeatAreNeverFromFraming() async throws {
        let budget = FakeDeviceBudget(healthy)
        let (capture, _) = try await recording(budget: budget)
        XCTAssertEqual(capture.batteryFraction, 0.78)
        XCTAssertEqual(capture.status?.previewMode, .normal)

        budget.set(.init(freeBytes: 8_000_000_000, batteryFraction: 0.41, lowPowerMode: false, thermalState: .serious))
        XCTAssertEqual(capture.batteryFraction, 0.78, "nothing changes until the budget is read again")
        await capture.refreshBudget()
        XCTAssertEqual(capture.batteryFraction, 0.41)
        XCTAssertEqual(capture.status?.previewMode, .courtMode, "the court-mode slot follows the live reading")
        XCTAssertEqual(capture.status?.phase, .recording)
        try await capture.stop()
    }

    @MainActor
    func testKeepBudgetCurrentPollsUntilItsTaskIsCancelled() async throws {
        let budget = FakeDeviceBudget(healthy)
        let (capture, _) = try await recording(budget: budget)
        let polling = Task { await capture.keepBudgetCurrent(every: .milliseconds(20)) }
        for level in [0.64, 0.33] {
            budget.set(.init(freeBytes: 8_000_000_000, batteryFraction: level, lowPowerMode: false, thermalState: .nominal))
            let deadline = ContinuousClock.now + .seconds(10)
            while capture.batteryFraction != level, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertEqual(capture.batteryFraction, level, "the pill follows the battery without anyone asking")
        }
        polling.cancel()
        await polling.value
        budget.set(.init(freeBytes: 8_000_000_000, batteryFraction: 0.05, lowPowerMode: false, thermalState: .nominal))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(capture.batteryFraction, 0.33, "a cancelled poll reads nothing more")
        try await capture.stop()
    }

    @MainActor
    func testABatteryLevelThatCanNoLongerBeReadIsNotShownAsCurrent() async throws {
        let (capture, _) = try await recording(budget: FailingAfterFirstBudget(healthy))
        XCTAssertEqual(capture.batteryFraction, 0.78)
        await capture.refreshBudget()
        XCTAssertNil(capture.batteryFraction, "an old reading is hidden rather than drawn as the level now")
        XCTAssertEqual(capture.status?.phase, .recording, "a failed reading never stops the recording")
        XCTAssertNil(capture.stopFailure)
        try await capture.stop()
    }

    @MainActor
    func testTheEnginesOwnLowStorageStopLandsOnTheSavedRecordingWithItsReason() async throws {
        let budget = FakeDeviceBudget(healthy)
        let (capture, _) = try await recording(budget: budget)
        budget.set(.init(freeBytes: 10 * 1024 * 1024, batteryFraction: 0.78, lowPowerMode: false, thermalState: .nominal))
        await capture.refreshBudget()

        let saved = try XCTUnwrap(capture.savedRecording, "the engine stopped and saved by itself")
        XCTAssertEqual(capture.status?.phase, .stopped)
        XCTAssertNil(capture.stopFailure)
        XCTAssertEqual(CaptureRoutePhase(enginePhase: capture.status?.phase, isSaved: true), .saved)
        XCTAssertEqual(saved.captureEvents?.map(\.kind), [.lowStorageStop])
        XCTAssertEqual(CaptureRecordingCopy.automaticStopReason(saved), "Storage full. Everything up to 0:02 is saved.")
    }

    @MainActor
    func testTheEnginesOwnStopWhoseSaveIsRefusedIsAFailedStopNotADeadEnd() async throws {
        let budget = FakeDeviceBudget(healthy)
        let (capture, _) = try await recording(sink: RefusingSink(), budget: budget)
        budget.set(.init(freeBytes: 8_000_000_000, batteryFraction: 0.01, lowPowerMode: false, thermalState: .nominal))
        await capture.refreshBudget()

        XCTAssertEqual(capture.status?.phase, .stopped)
        XCTAssertNil(capture.savedRecording)
        XCTAssertEqual(capture.stopFailure, .saveFailed)
        XCTAssertFalse(capture.isWorking)
    }
}
