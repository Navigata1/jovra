import Foundation
import JovraMedia

/// T60 SPIKE (throwaway branch). One journal heartbeat as the capture engine reports it.
struct RecordingHeartbeat: Equatable, Sendable {
    var phase: CapturePhase
    var recordingSeconds: Double?
    var savedThroughSeconds: Double?
    var batteryFraction: Double?
}

struct RecordingLiveActivityUpdate: Equatable, Sendable {
    var state: RecordingActivityAttributes.ContentState
    /// After this date the activity renders "Status unknown" without any further update from the app.
    var staleDate: Date?
}

/// Maps heartbeats to Live Activity content. A recording update is sent only when the journal's saved-through
/// time advances, so a stalled writer (or a killed app) stops the updates and the stale date takes over.
struct RecordingLiveActivityPolicy: Sendable {
    static let staleAfter: TimeInterval = 10

    private var lastSavedThrough: Double?
    private var lastPhase: RecordingActivityAttributes.Phase?
    private var lastSavedAt: Date?

    mutating func update(for heartbeat: RecordingHeartbeat, at now: Date) -> RecordingLiveActivityUpdate? {
        let seconds = Int((heartbeat.recordingSeconds ?? 0).rounded(.down))
        switch heartbeat.phase {
        case .recording:
            guard let saved = heartbeat.savedThroughSeconds, saved > 0, saved > (lastSavedThrough ?? 0) else { return nil }
            lastSavedThrough = saved; lastPhase = .recording; lastSavedAt = now
            let deadline = now.addingTimeInterval(Self.staleAfter)
            var content = state(.recording, seconds: seconds, savedAt: now, heartbeat: heartbeat, now: now)
            content.timerEnd = deadline
            return .init(state: content, staleDate: deadline)
        case .paused, .stopped:
            let phase: RecordingActivityAttributes.Phase = heartbeat.phase == .paused ? .paused : .saved
            guard phase != lastPhase else { return nil }
            if let saved = heartbeat.savedThroughSeconds, saved > (lastSavedThrough ?? 0) {
                lastSavedThrough = saved; lastSavedAt = now
            }
            lastPhase = phase
            return .init(state: state(phase, seconds: seconds, savedAt: lastSavedAt, heartbeat: heartbeat, now: now), staleDate: nil)
        case .idle, .ready, .pausing, .stopping:
            return nil
        }
    }

    private func state(_ phase: RecordingActivityAttributes.Phase, seconds: Int, savedAt: Date?,
                       heartbeat: RecordingHeartbeat, now: Date) -> RecordingActivityAttributes.ContentState {
        .init(phase: phase, recordingStartedAt: now.addingTimeInterval(-TimeInterval(seconds)), recordingSeconds: seconds, timerEnd: nil,
              savedAt: savedAt, batteryPercent: Self.percent(heartbeat.batteryFraction))
    }

    private static func percent(_ fraction: Double?) -> Int? {
        guard let fraction, fraction >= 0, fraction <= 1 else { return nil }
        return Int((fraction * 100).rounded())
    }
}
