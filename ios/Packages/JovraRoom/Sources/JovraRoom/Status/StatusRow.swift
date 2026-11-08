/// A row's freshness as displayed: the receiver-derived Fresh / Delayed / Unknown, or Local for the device's own
/// capture (known now, counted as fresh).
public enum RowFreshness: String, Codable, CaseIterable, Hashable, Sendable {
    case fresh = "Fresh", delayed = "Delayed", unknown = "Unknown", local = "Local"

    public init(_ freshness: Freshness) {
        switch freshness {
        case .fresh: self = .fresh
        case .delayed: self = .delayed
        case .unknown: self = .unknown
        }
    }

    /// Fresh or Local: counts toward `fresh` and, when recording, `freshRecording`.
    public var isFreshLike: Bool { self == .fresh || self == .local }
}

/// The three fields of a camera's report a status row needs; both a snapshot device and a bridge device provide
/// them.
public struct CameraReport: Equatable, Hashable, Sendable {
    public var deviceId: String
    public var captureState: CaptureState
    public var lastReportedElapsedMs: Int

    public init(deviceId: String, captureState: CaptureState, lastReportedElapsedMs: Int) {
        self.deviceId = deviceId
        self.captureState = captureState
        self.lastReportedElapsedMs = lastReportedElapsedMs
    }
}

extension RoomDeviceStatus {
    public var report: CameraReport {
        CameraReport(deviceId: deviceId, captureState: captureState, lastReportedElapsedMs: lastReportedElapsedMs)
    }
}

extension WatchBridgeSnapshot.Device {
    public var report: CameraReport {
        CameraReport(deviceId: deviceId, captureState: captureState, lastReportedElapsedMs: lastReportedElapsedMs)
    }
}

/// What a status row may say (freshness.py `display_row`). A remote duration is always the last reported value: it is
/// never extended with the receiver's clock, even while Fresh. Only the device's own UI runs its local capture timer.
public struct StatusRow: Equatable, Hashable, Sendable {
    public enum ElapsedSource: String, Codable, CaseIterable, Hashable, Sendable {
        case lastReported = "last-reported", localTimer = "local-timer"
    }

    public let deviceId: String
    public let freshness: RowFreshness
    public let elapsedMs: Int
    public let elapsedSource: ElapsedSource
    /// Always false: no row ever advances a remote value.
    public let extrapolated: Bool
    /// Delayed or Unknown.
    public let stale: Bool
    /// How long ago the receiver last heard this camera, or nil when that is not known (after a restart).
    public let lastHeardAgeMs: Int?
    /// A stale row whose last state was Starting, Recording, Paused or Finalizing.
    public let mayStillBeRecording: Bool
    public let captureState: CaptureState

    /// A remote camera's row.
    public static func remote(_ report: CameraReport, freshness: Freshness, ageMs: Int?) -> StatusRow {
        let stale = freshness != .fresh
        return StatusRow(deviceId: report.deviceId, freshness: RowFreshness(freshness),
                         elapsedMs: report.lastReportedElapsedMs, elapsedSource: .lastReported, extrapolated: false,
                         stale: stale, lastHeardAgeMs: ageMs,
                         mayStillBeRecording: stale && report.captureState.isActiveCapture,
                         captureState: report.captureState)
    }

    /// The device's own capture, timed by its own local timer.
    public static func local(_ report: CameraReport, localElapsedMs: Int) throws(FreshnessInputError) -> StatusRow {
        guard localElapsedMs >= 0 else { throw .negativeAge("localElapsedMs = \(localElapsedMs)") }
        return StatusRow(deviceId: report.deviceId, freshness: .local, elapsedMs: localElapsedMs,
                         elapsedSource: .localTimer, extrapolated: false, stale: false, lastHeardAgeMs: 0,
                         mayStillBeRecording: false, captureState: report.captureState)
    }

    /// The frozen elapsed value as a clock string, floored to seconds: "12:26", or "1:02:03" from an hour.
    public var elapsedText: String { RoomDurationText.clock(milliseconds: elapsedMs) }

    /// Whole seconds since last heard, floored ("heard 18 s ago"), or nil when not known.
    public var lastHeardSeconds: Int? { lastHeardAgeMs.map { $0 / 1000 } }
}

/// Language-neutral duration text for status rows. Sentences ("May still be recording", "Last heard 18 s ago") are
/// the app's String Catalog copy; this package supplies only the numbers they are built from.
public enum RoomDurationText {
    /// `m:ss` below an hour, `h:mm:ss` from an hour. Floors to the second, so a value is never overstated; negative
    /// input reads as 0:00.
    public static func clock(milliseconds: Int) -> String {
        let total = max(0, milliseconds) / 1000
        let (hours, minutes, seconds) = (total / 3600, total / 60 % 60, total % 60)
        let ss = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        guard hours > 0 else { return "\(minutes):\(ss)" }
        return "\(hours):\(minutes < 10 ? "0\(minutes)" : "\(minutes)"):\(ss)"
    }
}
