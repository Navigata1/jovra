import AVFoundation
import JovraCore
import JovraMedia
import Observation

/// ARC releases this subscription with its owning coordinator. Cancellation is thread-safe and
/// avoids reading a main-actor property from the coordinator's nonisolated deinitializer.
private final class CaptureStatusSubscription {
    var task: Task<Void, Never>?
    deinit { task?.cancel() }
}

/// Why the engine is stopped with no recording acknowledged as saved. The screen says which, and what is
/// still on this iPhone, instead of leaving a recording screen that no longer records.
enum CaptureStopFailure: Equatable, Sendable {
    /// Stop (the player's, or the engine's own at low storage or battery) could not finish its final save.
    case saveFailed
    /// "Delete this recording" stopped the engine but the session folder could not be removed.
    case deleteFailed
}

/// The native screen controls the accepted capture engine, never its writer or journal. Only
/// confirmed engine status is displayed; a saved result appears after the shared sink commits.
@MainActor @Observable
final class NativeCaptureCoordinator {
    /// How often storage, battery and heat are re-read while the recording phase is up. At the route's
    /// 4 Mbit/s the engine's 32 MB floor is about a minute of video, so a low-storage stop is never late.
    static let budgetRefreshInterval = Duration.seconds(10)

    private let library: LocalCaptureLibrary
    private let source: any CaptureSource
    private let clock: any CaptureClock
    private let sink: any RecordingSink
    private let budget: any DeviceBudget
    private var engine: CaptureEngine?
    private let subscription = CaptureStatusSubscription()
    private var folder: URL?
    /// The singles draft the session document is minted from when recording starts, not before, so
    /// framing and closing without recording leave nothing in the library.
    private(set) var seed: CaptureSessionSeed?
    private(set) var sessionID: SessionID?
    private(set) var status: CaptureStatus?
    private(set) var preflight: PreflightReport?
    private(set) var savedRecording: SessionRecording?
    private(set) var isWorking = false
    /// The player confirmed Delete this recording and the session folder is gone.
    private(set) var isDeleted = false
    /// Set when the engine stopped without a saved recording; cleared when a retried deletion succeeds.
    private(set) var stopFailure: CaptureStopFailure?
    /// False after a budget read failed: the last reading is then old, and is not shown as current.
    private(set) var isBudgetCurrent = true
    private var isRefreshingBudget = false

    var isFixture: Bool { source.mode == .simulatorFixture }
    var previewSession: AVCaptureSession? { (source as? CameraSource)?.previewSession }

    /// A transition or the engine's own reaction to a budget reading is in flight, so a stopped engine
    /// may still be saving.
    var isSettling: Bool { isWorking || isRefreshingBudget }
    /// The battery level to draw: the engine's latest reading, or nothing once a re-read has failed.
    var batteryFraction: Double? { isBudgetCurrent ? status?.budget?.batteryFraction : nil }

    /// `sink` and `budget` are system-boundary injections for tests; the app saves through the library
    /// and reads the device's own storage, battery and heat.
    init(library: LocalCaptureLibrary, source: any CaptureSource, clock: any CaptureClock = RealtimeCaptureClock(),
         sink: (any RecordingSink)? = nil, budget: any DeviceBudget = LiveDeviceBudget()) {
        self.library = library; self.source = source; self.clock = clock
        self.sink = sink ?? library; self.budget = budget
    }

    func prepare(seed: CaptureSessionSeed, preset: CapturePreset, microphone: SessionRecordingMicrophone) async throws {
        guard !isWorking, engine == nil else { throw CaptureError.invalidState }
        isWorking = true
        defer { isWorking = false }
        let candidate = CaptureEngine(source: source, clock: clock, sink: sink, budget: budget)
        do {
            let report = try await candidate.prepare(preset, microphone: microphone)
            self.seed = seed; engine = candidate; preflight = report
            status = candidate.status
            subscription.task = Task { [weak self, candidate] in
                for await status in candidate.statuses {
                    guard !Task.isCancelled, let self else { break }
                    self.status = status
                }
            }
        } catch {
            await source.stop()
            throw error
        }
    }

    /// Match details edited while framing; refused once the session exists.
    func updateSeed(_ seed: CaptureSessionSeed) throws {
        guard sessionID == nil, engine != nil else { throw CaptureError.invalidState }
        self.seed = seed
    }

    func start() async throws {
        guard let seed, sessionID == nil else { throw CaptureError.invalidState }
        try await transition { engine in
            let id = try await self.library.createCapture(seed, mode: self.source.mode)
            let location = try await self.library.recordingFolder(id)
            self.sessionID = id; self.folder = location
            try await engine.start(sessionID: id.rawValue, folder: location)
        }
    }

    func pause() async throws { try await transition { try await $0.pause() } }
    /// The same path a camera interruption takes (the fixture's debug control and the backgrounded scene).
    func interrupt(reason: SessionGapReason) async throws { try await transition { try await $0.interrupt(reason: reason) } }
    func resume() async throws { try await transition { try await $0.resume() } }

    /// A stop whose final save fails leaves the engine stopped: `stopFailure` says so, and the journal and
    /// every closed segment stay on disk for the next launch's recovery scan.
    func stop() async throws {
        try await transition { engine in
            do { self.savedRecording = try await engine.stop() }
            catch {
                if engine.status.phase == .stopped, self.savedRecording == nil { self.stopFailure = .saveFailed }
                throw error
            }
        }
    }

    /// Re-reads storage, battery and heat, so the screen never shows the reading taken when framing began.
    /// The engine reacts to the reading itself: court mode when the phone is hot, and its own stop-and-save
    /// when storage or battery is nearly gone, which lands exactly where the player's Stop does.
    func refreshBudget() async {
        guard !isWorking, !isRefreshingBudget, let engine,
              engine.status.phase == .recording || engine.status.phase == .paused else { return }
        isRefreshingBudget = true
        defer { isRefreshingBudget = false; status = engine.status }
        do {
            if let stopped = try await engine.refreshBudget() { savedRecording = stopped; stopFailure = nil }
            isBudgetCurrent = true
        } catch {
            if engine.status.phase == .stopped, savedRecording == nil { stopFailure = .saveFailed }
            else if engine.status.phase != .stopped { isBudgetCurrent = false }
        }
    }

    /// Runs for as long as the recording phase is on screen: cancelling the task ends it, and so does a
    /// stopped engine, which has nothing left to protect.
    func keepBudgetCurrent(every interval: Duration = NativeCaptureCoordinator.budgetRefreshInterval) async {
        while !Task.isCancelled, status?.phase != .stopped {
            await refreshBudget()
            do { try await Task.sleep(for: interval) } catch { return }
        }
    }

    @discardableResult func markPoint() throws -> JovraCore.MediaTime {
        guard !isWorking, let engine else { throw CaptureError.invalidState }
        return try engine.markPoint()
    }

    /// Ends the recording and removes its session folder, originals included, after the player confirmed.
    /// A failed final save does not keep the footage: the player asked for it to be gone. If the folder
    /// cannot be removed the engine is already stopped; `stopFailure` says so and this can be called again.
    func deleteRecording() async throws {
        guard !isWorking, let engine, let sessionID else { throw CaptureError.invalidState }
        isWorking = true
        defer { isWorking = false; status = engine.status }
        if engine.status.phase == .recording || engine.status.phase == .paused { _ = try? await engine.stop() }
        do { try await library.deleteCapture(sessionID) }
        catch { stopFailure = .deleteFailed; throw error }
        savedRecording = nil; isDeleted = true; stopFailure = nil
    }

    /// Leaving framing releases the camera. An interrupted active recording is retained by the
    /// engine's journal; this is not a substitute for the full recovery/hardware acceptance gate.
    func leaveScreen() async throws {
        if status?.phase == .recording { try await pause() }
        await source.stop()
        subscription.task?.cancel()
    }

    private func transition(_ action: (CaptureEngine) async throws -> Void) async throws {
        guard !isWorking, let engine else { throw CaptureError.invalidState }
        isWorking = true
        defer { isWorking = false; status = engine.status }
        try await action(engine)
    }
}
