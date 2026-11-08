import Foundation
import JovraRoom

/// Words and spoken labels for camera status. Screens show short forms (≤ 18 characters per line); VoiceOver reads
/// full words with ages (watch spec "Accessibility"). Copy comes from the "Watch" table.
enum WatchStatusText {
    /// "C3": the short on-screen name for a camera id; the spoken form is `spokenName`.
    static func shortName(_ deviceId: String) -> String { WatchCopy.clip(deviceId.uppercased(), limit: 6) }

    static func spokenName(_ deviceId: String) -> String {
        String(localized: "Camera \(deviceId.uppercased())", table: "Watch")
    }

    static func word(_ freshness: RowFreshness) -> String {
        switch freshness {
        case .fresh: String(localized: "Fresh", table: "Watch")
        case .local: String(localized: "This phone", table: "Watch")
        case .delayed: String(localized: "Delayed", table: "Watch")
        case .unknown: String(localized: "Unknown", table: "Watch")
        }
    }

    static func word(_ state: CaptureState) -> String {
        switch state {
        case .ready: String(localized: "Ready", table: "Watch")
        case .starting: String(localized: "Starting", table: "Watch")
        case .recording: String(localized: "Recording", table: "Watch")
        case .paused: String(localized: "Paused", table: "Watch")
        case .finalizing: String(localized: "Finalizing", table: "Watch")
        case .saved: String(localized: "Saved", table: "Watch")
        case .failed: String(localized: "Failed", table: "Watch")
        }
    }

    /// "2s", "1m 5s"; nil when the last-heard age is not known (after a restart).
    static func shortAge(_ row: StatusRow) -> String? {
        row.lastHeardSeconds.map {
            Duration.seconds($0).formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
        }
    }

    static func spokenDuration(milliseconds: Int) -> String {
        Duration.seconds(max(0, milliseconds) / 1000)
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// What the value slot of a row shows: the frozen elapsed time while fresh and recording, otherwise a word.
    static func value(_ row: StatusRow) -> String {
        if row.stale { return word(row.freshness) }
        return row.captureState == .recording ? row.elapsedText : word(row.captureState)
    }

    /// "Camera C3, status unknown, last heard 18 seconds ago, may still be recording."
    static func spokenRow(_ row: StatusRow) -> String {
        var parts = [spokenName(row.deviceId)]
        if row.stale {
            parts.append(String(localized: "status \(word(row.freshness).lowercased())", table: "Watch"))
        } else {
            parts.append(word(row.captureState).lowercased())
            if row.captureState == .recording {
                parts.append(String(localized: "\(spokenDuration(milliseconds: row.elapsedMs)), last known",
                                    table: "Watch"))
            }
        }
        if let age = row.lastHeardAgeMs {
            parts.append(String(localized: "last heard \(spokenDuration(milliseconds: age)) ago", table: "Watch"))
        } else {
            parts.append(String(localized: "last heard time not known", table: "Watch"))
        }
        if row.mayStillBeRecording { parts.append(String(localized: "may still be recording", table: "Watch")) }
        return parts.joined(separator: ", ") + "."
    }

    /// Worst first: Unknown, then Delayed, then the rest; ties by camera id.
    static func worstFirst(_ rows: [StatusRow]) -> [StatusRow] {
        func rank(_ row: StatusRow) -> Int {
            switch row.freshness {
            case .unknown: 0
            case .delayed: 1
            case .fresh, .local: row.captureState == .recording ? 3 : 2
            }
        }
        return rows.sorted { (rank($0), $0.deviceId) < (rank($1), $1.deviceId) }
    }
}
