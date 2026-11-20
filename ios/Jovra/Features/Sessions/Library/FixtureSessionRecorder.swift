import Foundation
import JovraCore
import JovraMedia

/// The walking skeleton (T20, after T15): `-recordFixtureSession <seconds>` records a session through the real
/// capture engine with the fixture camera and no recording screen, so the library can be shown listing a
/// session the engine itself saved. It runs once per launch, in its own task, so leaving the Sessions tab
/// mid-recording never leaves the engine running unstopped.
@MainActor
enum FixtureSessionRecorder {
    private static var recording: Task<SessionID?, any Error>?

    /// The recording the launch asked for, started on first call and awaited by every later one; nil when
    /// the launch asked for none.
    static func recordIfRequested(_ configuration: LaunchConfiguration, library: LocalCaptureLibrary) async throws -> SessionID? {
        guard let seconds = configuration.recordFixtureSessionSeconds else { return nil }
        if let recording { return try await recording.value }
        let task = Task { try await record(seconds: seconds, library: library) }
        recording = task
        return try await task.value
    }

    private static func record(seconds: Int, library: LocalCaptureLibrary) async throws -> SessionID? {
        guard let url = Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4") else {
            throw CaptureError.noVideo
        }
        let clock = RealtimeCaptureClock()
        let coordinator = NativeCaptureCoordinator(library: library, source: FixtureCamera(url: url, clock: clock), clock: clock)
        try await coordinator.prepare(seed: seed, preset: .init(width: 1280, height: 720, bitRate: 4_000_000),
                                      microphone: .notRequested)
        try await coordinator.start()
        try await Task.sleep(for: .seconds(seconds))
        try await coordinator.stop()
        try await coordinator.leaveScreen()
        return coordinator.sessionID
    }

    private static var seed: CaptureSessionSeed {
        let players = [
            SessionPlayer(id: "jon", displayName: "Jon", handedness: .unknown, backhand: .unknown, isSelf: true),
            SessionPlayer(id: "alex", displayName: "Alex", handedness: .unknown, backhand: .unknown, isSelf: false),
        ]
        let format = SessionMatchFormat(presetId: .clubBo3, setsToWin: .value2, gameScoring: .ad,
                                        set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let)
        return CaptureSessionSeed(title: String(localized: "Fixture recording", table: "Sessions.Library"), players: players, format: format,
                                  toss: SessionToss(firstServer: "jon", startingEnds: .init(A: .near, B: .far)))
    }
}
