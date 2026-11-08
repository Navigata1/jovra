/// Separate counts over the roster's enrolled cameras (freshness.py `counts`), never over the rows that happen to be
/// present: an enrolled camera with no row is Unknown and not recording-fresh.
public struct RoomCounts: Codable, Equatable, Hashable, Sendable {
    public let enrolled: Int
    public let fresh: Int
    public let delayed: Int
    public let unknown: Int
    public let reportedRecording: Int
    public let freshRecording: Int
    /// Only when every enrolled camera is freshly heard (or local) and Recording.
    public let canClaimAllRecording: Bool

    public init(enrolled: Int, fresh: Int, delayed: Int, unknown: Int, reportedRecording: Int, freshRecording: Int,
                canClaimAllRecording: Bool) {
        self.enrolled = enrolled
        self.fresh = fresh
        self.delayed = delayed
        self.unknown = unknown
        self.reportedRecording = reportedRecording
        self.freshRecording = freshRecording
        self.canClaimAllRecording = canClaimAllRecording
    }

    public struct RowNotEnrolled: Error, Equatable, Sendable { public let deviceId: String }

    /// `rows` are (report, freshness); a later row for the same device replaces an earlier one. A row for a camera
    /// that is not enrolled is a caller error.
    public init(rows: [(CameraReport, RowFreshness)], enrolled enrolledIds: [String]) throws(RowNotEnrolled) {
        let enrolled = Set(enrolledIds)
        var byId: [String: (CameraReport, RowFreshness)] = [:]
        for (report, freshness) in rows {
            guard enrolled.contains(report.deviceId) else { throw RowNotEnrolled(deviceId: report.deviceId) }
            byId[report.deviceId] = (report, freshness)
        }
        let present = byId.values
        let freshRecording = present.filter { $0.1.isFreshLike && $0.0.captureState == .recording }.count
        self.init(enrolled: enrolled.count,
                  fresh: present.filter { $0.1.isFreshLike }.count,
                  delayed: present.filter { $0.1 == .delayed }.count,
                  unknown: present.filter { $0.1 == .unknown }.count + (enrolled.count - byId.count),
                  reportedRecording: present.filter { $0.0.captureState == .recording }.count,
                  freshRecording: freshRecording,
                  canClaimAllRecording: !enrolled.isEmpty && freshRecording == enrolled.count)
    }
}

/// A receiver's whole status panel: one row per present camera plus the roster counts.
public struct RoomStatusBoard: Equatable, Sendable {
    public let rows: [StatusRow]
    public let counts: RoomCounts

    /// The phone path (freshness.py `observe_snapshot`): age = ageAtHostMs + host-to-phone transit + this phone's
    /// monotonic time since accepting the snapshot. `localDeviceId` is this phone's own camera, shown as Local with
    /// its own timer (`localElapsedMs`, defaulting to its last report until the capture timer is wired).
    public static func phone(_ snapshot: RoomSnapshotRecord, observation: ReceiverObservation, nowMonoMs: Int,
                             currentBaselineId: String, localDeviceId: String? = nil,
                             localElapsedMs: Int? = nil) throws -> RoomStatusBoard {
        let policy = snapshot.freshnessPolicy.policy
        var rows: [StatusRow] = []
        for device in snapshot.devices {
            let report = device.report
            if report.deviceId == localDeviceId {
                rows.append(try StatusRow.local(report, localElapsedMs: localElapsedMs ?? report.lastReportedElapsedMs))
                continue
            }
            // Decoding guarantees the host's age on every snapshot row; without one the row is Unknown, never fresh.
            guard let hostAge = device.ageAtHostMs else {
                rows.append(.remote(report, freshness: .unknown, ageMs: nil))
                continue
            }
            let (freshness, age) = try FreshnessRule.observe(senderAgeMs: hostAge, observation,
                                                             nowMonoMs: nowMonoMs,
                                                             currentBaselineId: currentBaselineId, policy: policy)
            rows.append(.remote(report, freshness: freshness, ageMs: age))
        }
        return try board(rows, reports: snapshot.devices.map(\.report), enrolled: snapshot.roster.cameraDeviceIds)
    }

    /// The room link (host or network) is lost (freshness.py `on_room_disconnect`). Local capture continues
    /// untouched and no command of any kind is generated (no stop-all); every cached remote row becomes Unknown and
    /// keeps its last reported elapsed value. Counts are over the remote cameras that were known.
    public static func disconnected(remote: [CameraReport]) throws -> RoomStatusBoard {
        let rows = remote.map { StatusRow.remote($0, freshness: .unknown, ageMs: nil) }
        return try board(rows, reports: remote, enrolled: remote.map(\.deviceId))
    }

    private static func board(_ rows: [StatusRow], reports: [CameraReport], enrolled: [String]) throws -> RoomStatusBoard {
        let counted = zip(reports, rows).map { ($0, $1.freshness) }
        return RoomStatusBoard(rows: rows, counts: try RoomCounts(rows: counted, enrolled: enrolled))
    }
}

/// The outcome of losing the room link: what the device keeps doing and what it shows. `commandsIssued` is always
/// empty; it exists so the rule is asserted, not assumed.
public struct RoomDisconnectOutcome: Equatable, Sendable {
    public let localCaptureState: CaptureState
    public let commandsIssued: [RoomCommand]
    public let board: RoomStatusBoard

    public static func onRoomDisconnect(local: CameraReport, remote: [CameraReport]) throws -> RoomDisconnectOutcome {
        RoomDisconnectOutcome(localCaptureState: local.captureState, commandsIssued: [],
                              board: try .disconnected(remote: remote))
    }
}
