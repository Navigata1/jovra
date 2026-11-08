/// The watch's camera health (docs/spec/watch-v1-spec.md "HealthSummary"; freshness.py `observe_bridge` + `counts`).
///
/// - `enrolled` comes from the roster, never from the rows present: an enrolled camera with no row is Unknown.
/// - `fresh` counts Fresh rows; `freshRecording` counts Fresh rows whose own last report is Recording. The headline is
///   `freshRecording / enrolled`, and "all recording" is claimed only when every enrolled camera is in it.
/// - Each row shows `lastReportedElapsedMs` exactly as last reported (`StatusRow.elapsedText`, floored), never
///   advanced by the watch clock, plus "may still be recording" when stale.
///
/// Ages are chained: `ageAtBridgeMs` + bridge-to-watch transit + the watch's monotonic time since accepting the
/// payload. A queued delivery, a payload accepted under another process baseline (restart) or a clock that runs
/// backwards is Unknown.
public struct HealthSummary: Equatable, Sendable {
    public let rows: [StatusRow]
    public let counts: RoomCounts

    public var enrolled: Int { counts.enrolled }
    public var fresh: Int { counts.fresh }
    public var freshRecording: Int { counts.freshRecording }
    public var canClaimAllRecording: Bool { counts.canClaimAllRecording }

    /// Rows already classified by the receiver: each camera's report, its freshness and its age (nil if unknown).
    public init(rows classified: [(report: CameraReport, freshness: Freshness, ageMs: Int?)],
                enrolled: [String]) throws {
        rows = classified.map { StatusRow.remote($0.report, freshness: $0.freshness, ageMs: $0.ageMs) }
        counts = try RoomCounts(rows: classified.map { ($0.report, RowFreshness($0.freshness)) }, enrolled: enrolled)
    }

    /// The watch path: a cached bridge payload read at the watch's `nowMonoMs` under `currentBaselineId`. A payload
    /// the watch never stamped with its own `receiverObservation` has no bounded age: every row is Unknown.
    public static func watch(_ bridge: WatchBridgeSnapshot, nowMonoMs: Int,
                             currentBaselineId: String) throws -> HealthSummary {
        let policy = bridge.freshnessPolicy.policy
        let rows = try bridge.devices.map { device -> (report: CameraReport, freshness: Freshness, ageMs: Int?) in
            guard let observation = bridge.receiverObservation?.observation else { return (device.report, .unknown, nil) }
            let (freshness, age) = try FreshnessRule.observe(senderAgeMs: device.ageAtBridgeMs, observation,
                                                             nowMonoMs: nowMonoMs,
                                                             currentBaselineId: currentBaselineId, policy: policy)
            return (device.report, freshness, age)
        }
        return try HealthSummary(rows: rows, enrolled: bridge.roster.cameraDeviceIds)
    }

    /// The watch path on a live `FreshnessClock` (production: `.live`, the continuous clock and this process's
    /// baseline).
    public static func watch<Clock: MonotonicClock>(_ bridge: WatchBridgeSnapshot,
                                                    clock: FreshnessClock<Clock>) throws -> HealthSummary {
        try watch(bridge, nowMonoMs: clock.clock.nowMs(), currentBaselineId: clock.baselineId)
    }
}
