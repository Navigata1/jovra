import XCTest
@testable import Jovra

/// T60 spike (throwaway branch): the journal heartbeat -> Live Activity content mapping.
/// Expected values are worked examples from the issue copy ("REC 32:10 · Saved 4 s ago · Battery 64%").
final class RecordingLiveActivityPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testAdvancingSavedThroughProducesARecordingUpdateThatGoesStaleAfterTenSeconds() throws {
        var policy = RecordingLiveActivityPolicy()
        let update = try XCTUnwrap(policy.update(for: .init(phase: .recording, recordingSeconds: 1930,
                                                            savedThroughSeconds: 1926, batteryFraction: 0.64), at: t0))
        XCTAssertEqual(update.state.phase, .recording)
        XCTAssertEqual(update.state.recordingStartedAt, Date(timeIntervalSinceReferenceDate: 799_998_070))
        XCTAssertEqual(update.state.recordingSeconds, 1930)
        XCTAssertEqual(update.state.savedAt, t0)
        XCTAssertEqual(update.state.batteryPercent, 64)
        XCTAssertEqual(update.staleDate, Date(timeIntervalSinceReferenceDate: 800_000_010))
        // The REC timer stops counting at the deadline, so a dead recorder is never shown as still recording.
        XCTAssertEqual(update.state.timerEnd, Date(timeIntervalSinceReferenceDate: 800_000_010))
    }

    func testAHeartbeatThatDoesNotAdvanceSavedThroughSendsNoUpdateSoTheStaleClockKeepsRunning() {
        var policy = RecordingLiveActivityPolicy()
        _ = policy.update(for: .init(phase: .recording, recordingSeconds: 10, savedThroughSeconds: 8, batteryFraction: 0.5), at: t0)
        XCTAssertNil(policy.update(for: .init(phase: .recording, recordingSeconds: 11, savedThroughSeconds: 8, batteryFraction: 0.5),
                                   at: t0.addingTimeInterval(1)))
        XCTAssertNotNil(policy.update(for: .init(phase: .recording, recordingSeconds: 12, savedThroughSeconds: 10, batteryFraction: 0.5),
                                      at: t0.addingTimeInterval(2)))
    }

    func testRecordingWithNothingSavedYetSendsNoHeartbeat() {
        var policy = RecordingLiveActivityPolicy()
        XCTAssertNil(policy.update(for: .init(phase: .recording, recordingSeconds: 0, savedThroughSeconds: nil, batteryFraction: 0.5), at: t0))
        XCTAssertNil(policy.update(for: .init(phase: .recording, recordingSeconds: 1, savedThroughSeconds: 0, batteryFraction: 0.5), at: t0))
    }

    func testPausingFreezesTheTimeAndNeverGoesStale() throws {
        var policy = RecordingLiveActivityPolicy()
        _ = policy.update(for: .init(phase: .recording, recordingSeconds: 30, savedThroughSeconds: 28, batteryFraction: 0.9), at: t0)
        let paused = try XCTUnwrap(policy.update(for: .init(phase: .paused, recordingSeconds: 32, savedThroughSeconds: 32, batteryFraction: 0.9),
                                                 at: t0.addingTimeInterval(3)))
        XCTAssertEqual(paused.state.phase, .paused)
        XCTAssertEqual(paused.state.recordingSeconds, 32)
        XCTAssertEqual(paused.state.savedAt, t0.addingTimeInterval(3))
        XCTAssertNil(paused.staleDate)
        XCTAssertNil(policy.update(for: .init(phase: .paused, recordingSeconds: 32, savedThroughSeconds: 32, batteryFraction: 0.9),
                                   at: t0.addingTimeInterval(4)))
    }

    func testStoppedBecomesSavedAndTransitionalPhasesAreIgnored() throws {
        var policy = RecordingLiveActivityPolicy()
        XCTAssertNil(policy.update(for: .init(phase: .stopping, recordingSeconds: 40, savedThroughSeconds: 40, batteryFraction: 0.9), at: t0))
        let saved = try XCTUnwrap(policy.update(for: .init(phase: .stopped, recordingSeconds: 40, savedThroughSeconds: 40, batteryFraction: 0.9), at: t0))
        XCTAssertEqual(saved.state.phase, .saved)
        XCTAssertNil(saved.staleDate)
    }

    func testUnknownBatteryIsNeverInvented() throws {
        var policy = RecordingLiveActivityPolicy()
        let update = try XCTUnwrap(policy.update(for: .init(phase: .recording, recordingSeconds: 5, savedThroughSeconds: 4, batteryFraction: -1), at: t0))
        XCTAssertNil(update.state.batteryPercent)
        var other = RecordingLiveActivityPolicy()
        XCTAssertNil(other.update(for: .init(phase: .recording, recordingSeconds: 5, savedThroughSeconds: 4, batteryFraction: nil), at: t0)?.state.batteryPercent)
    }
}
