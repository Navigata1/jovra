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

/// The native screen controls the accepted capture engine, never its writer or journal. Only
/// confirmed engine status is displayed; a saved result appears after the shared sink commits.
@MainActor @Observable
final class NativeCaptureCoordinator {
    private let library: LocalCaptureLibrary
    private let source: any CaptureSource
    private let clock: any CaptureClock
    private var engine: CaptureEngine?
    private let subscription = CaptureStatusSubscription()
    private var folder: URL?
    private(set) var sessionID: SessionID?
    private(set) var status: CaptureStatus?
    private(set) var preflight: PreflightReport?
    private(set) var savedRecording: SessionRecording?
    private(set) var isWorking = false

    var isFixture: Bool { source.mode == .simulatorFixture }
    var previewSession: AVCaptureSession? { (source as? CameraSource)?.previewSession }

    init(library: LocalCaptureLibrary, source: any CaptureSource, clock: any CaptureClock = RealtimeCaptureClock()) {
        self.library = library; self.source = source; self.clock = clock
    }

    func prepare(seed: CaptureSessionSeed, preset: CapturePreset, microphone: SessionRecordingMicrophone) async throws {
        guard !isWorking, engine == nil else { throw CaptureError.invalidState }
        isWorking = true
        defer { isWorking = false }
        let candidate = CaptureEngine(source: source, clock: clock, sink: library)
        do {
            let report = try await candidate.prepare(preset, microphone: microphone)
            let id = try await library.createCapture(seed, mode: source.mode)
            let location = try await library.recordingFolder(id)
            sessionID = id; folder = location; engine = candidate; preflight = report
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

    func start() async throws {
        guard let sessionID, let folder else { throw CaptureError.invalidState }
        try await transition { try await $0.start(sessionID: sessionID.rawValue, folder: folder) }
    }

    func pause() async throws { try await transition { try await $0.pause() } }
    func resume() async throws { try await transition { try await $0.resume() } }

    func stop() async throws {
        try await transition { self.savedRecording = try await $0.stop() }
    }

    func markPoint() throws {
        guard !isWorking, let engine else { throw CaptureError.invalidState }
        _ = try engine.markPoint()
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
