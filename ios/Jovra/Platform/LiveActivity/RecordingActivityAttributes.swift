import ActivityKit
import Foundation

/// T60 SPIKE (throwaway branch, never merged). Compiled into both the app and the widget extension.
/// Static plus dynamic data stays far below ActivityKit's 4 KB limit.
struct RecordingActivityAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable, Sendable { case recording, paused, saved }

    struct ContentState: Codable, Hashable, Sendable {
        var phase: Phase
        /// Wall-clock origin of the session time, so the widget counts REC time without updates.
        var recordingStartedAt: Date
        var recordingSeconds: Int
        /// The REC timer freezes here (the stale date) if no further heartbeat arrives.
        var timerEnd: Date?
        /// When the journal last confirmed media durable on disk (the heartbeat).
        var savedAt: Date?
        var batteryPercent: Int?
    }

    /// Simulator fixture captures are always shown as Sample.
    var isSample: Bool
}
