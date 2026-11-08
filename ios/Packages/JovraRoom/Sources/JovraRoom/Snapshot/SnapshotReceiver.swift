import Foundation
import JovraCore

/// The outcome of offering a snapshot to a receiver (spec/room/reference/jovra_room/snapshot.py). Every refusal
/// leaves the receiver's state exactly as it was.
public enum SnapshotVerdict: String, Equatable, Sendable, CaseIterable {
    case accepted
    case wrongSession, staleEpoch
    /// A newer epoch is informational and never adopted on sight; only `reconcile` adopts one.
    case epochChangeRequiresReconciliation
    case hostKeyMismatch, hostDeviceChanged, replayOrOutOfOrder, eventRevisionRegressed
    case rosterRegressed, rosterChangedWithoutRevision, unauthenticatedDevice, duplicateDevice
    case captureInstanceRetired, deviceSeqRegressed, deviceSeqReused
}

public enum ReconcileVerdict: String, Equatable, Sendable, CaseIterable {
    case reconciled, epochNotNewer, hostNotAuthenticated
}

/// Snapshot acceptance on a participant phone (or a watch bridge phone). Bound at join to the session, host epoch,
/// host TLS key, host device and the roster it was admitted under, it accepts only a strictly increasing
/// `snapshotSeq`, a non-decreasing `eventRevision` and a roster that changes only with a higher `rosterRevision`.
/// Per-device sequences never go back within a capture instance, a sequence is never reused for different content
/// and a device never returns to a capture instance it has left. Its `State` is what must persist across restarts
/// (replay protection); the monotonic freshness baseline deliberately does not.
public struct SnapshotReceiver: Equatable, Sendable {
    /// The last accepted report of one device: its capture instance, sequence and canonical content without the
    /// host's `ageAtHostMs` (which changes between snapshots of one report).
    public struct DeviceMark: Codable, Equatable, Sendable {
        public var captureInstanceId: String
        public var deviceSeq: Int
        public var fingerprint: String
    }

    /// The persisted form. Keys follow the reference's `persisted()`.
    public struct State: Codable, Equatable, Sendable {
        public var sessionId: String
        public var hostEpoch: Int
        public var hostKey: String
        public var hostDeviceId: String
        public var members: [String]
        public var rosterRevision: Int
        public var lastSeq: Int?
        public var eventRevision: Int?
        public var deviceSeq: [String: DeviceMark]
        public var retired: [String: [String]]

        enum CodingKeys: String, CodingKey {
            case sessionId, hostEpoch, hostKey, hostDeviceId, members, rosterRevision, lastSeq, eventRevision
            case deviceSeq, retired
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(hostEpoch, forKey: .hostEpoch)
            try c.encode(hostKey, forKey: .hostKey)
            try c.encode(hostDeviceId, forKey: .hostDeviceId)
            try c.encode(members, forKey: .members)
            try c.encode(rosterRevision, forKey: .rosterRevision)
            try c.encodeNullable(lastSeq, forKey: .lastSeq)
            try c.encodeNullable(eventRevision, forKey: .eventRevision)
            try c.encode(deviceSeq, forKey: .deviceSeq)
            try c.encode(retired, forKey: .retired)
        }
    }

    public private(set) var sessionId: String
    public private(set) var hostEpoch: Int
    public private(set) var hostKey: String
    public private(set) var hostDeviceId: String
    public private(set) var members: Set<String>
    public private(set) var rosterRevision: Int
    public private(set) var lastSeq: Int?
    public private(set) var eventRevision: Int?
    private var deviceMarks: [String: DeviceMark] = [:]
    private var retired: [String: Set<String>] = [:]
    /// The last accepted envelope.
    public private(set) var applied: RoomSnapshotRecord?

    public init(sessionId: String, hostEpoch: Int, hostKey: String, hostDeviceId: String, members: [String],
                rosterRevision: Int = 0) {
        self.sessionId = sessionId
        self.hostEpoch = hostEpoch
        self.hostKey = hostKey
        self.hostDeviceId = hostDeviceId
        self.members = Set(members)
        self.rosterRevision = rosterRevision
    }

    /// Accepts the envelope or names why not. Nothing changes unless the verdict is `.accepted`.
    public mutating func accept(_ envelope: RoomSnapshotRecord) -> SnapshotVerdict {
        if let refusal = refusal(of: envelope) { return refusal }
        lastSeq = envelope.snapshotSeq
        eventRevision = envelope.eventRevision
        members = Set(envelope.roster.cameraDeviceIds)
        rosterRevision = envelope.roster.rosterRevision
        for device in envelope.devices {
            if let previous = deviceMarks[device.deviceId], previous.captureInstanceId != device.captureInstanceId {
                retired[device.deviceId, default: []].insert(previous.captureInstanceId)
            }
            deviceMarks[device.deviceId] = DeviceMark(captureInstanceId: device.captureInstanceId,
                                                      deviceSeq: device.deviceSeq,
                                                      fingerprint: Self.fingerprint(of: device))
        }
        applied = envelope
        return .accepted
    }

    private func refusal(of env: RoomSnapshotRecord) -> SnapshotVerdict? {
        if env.sessionId != sessionId { return .wrongSession }
        if env.hostEpoch < hostEpoch { return .staleEpoch }
        if env.hostEpoch > hostEpoch { return .epochChangeRequiresReconciliation }
        if env.hostKeySha256 != hostKey { return .hostKeyMismatch }
        if env.hostDeviceId != hostDeviceId { return .hostDeviceChanged }
        if let lastSeq, env.snapshotSeq <= lastSeq { return .replayOrOutOfOrder }
        if let eventRevision, env.eventRevision < eventRevision { return .eventRevisionRegressed }
        let rosterIds = Set(env.roster.cameraDeviceIds)
        if env.roster.rosterRevision < rosterRevision { return .rosterRegressed }
        if env.roster.rosterRevision == rosterRevision, rosterIds != members { return .rosterChangedWithoutRevision }
        var seen = Set<String>()
        for device in env.devices {
            if !rosterIds.contains(device.deviceId) { return .unauthenticatedDevice }
            if !seen.insert(device.deviceId).inserted { return .duplicateDevice }
            if retired[device.deviceId]?.contains(device.captureInstanceId) == true { return .captureInstanceRetired }
            if let previous = deviceMarks[device.deviceId], previous.captureInstanceId == device.captureInstanceId {
                if device.deviceSeq < previous.deviceSeq { return .deviceSeqRegressed }
                if device.deviceSeq == previous.deviceSeq, Self.fingerprint(of: device) != previous.fingerprint {
                    return .deviceSeqReused
                }
            }
        }
        return nil
    }

    /// Adopts a newer host epoch only for an approved host key the transport has authenticated. Snapshot sequence
    /// and event revision restart with the new epoch; device sequences, retired instances and the roster keep
    /// protecting against replay.
    public mutating func reconcile(newEpoch: Int, hostKey newKey: String, hostDeviceId newHost: String,
                                   approvedHostKeys: Set<String>) -> ReconcileVerdict {
        guard newEpoch > hostEpoch else { return .epochNotNewer }
        guard approvedHostKeys.contains(newKey) else { return .hostNotAuthenticated }
        hostEpoch = newEpoch
        hostKey = newKey
        hostDeviceId = newHost
        lastSeq = nil
        eventRevision = nil
        return .reconciled
    }

    public var state: State {
        State(sessionId: sessionId, hostEpoch: hostEpoch, hostKey: hostKey, hostDeviceId: hostDeviceId,
              members: members.sorted(), rosterRevision: rosterRevision, lastSeq: lastSeq,
              eventRevision: eventRevision, deviceSeq: deviceMarks,
              retired: retired.mapValues { $0.sorted() })
    }

    /// Restores replay protection after a process restart. The applied envelope and any freshness baseline are not
    /// restored: freshness after a restart is Unknown until a bounded exchange renews it.
    public init(restoring state: State) {
        self.init(sessionId: state.sessionId, hostEpoch: state.hostEpoch, hostKey: state.hostKey,
                  hostDeviceId: state.hostDeviceId, members: state.members, rosterRevision: state.rosterRevision)
        lastSeq = state.lastSeq
        eventRevision = state.eventRevision
        deviceMarks = state.deviceSeq
        retired = state.retired.mapValues(Set.init)
    }

    /// Canonical JSON (JovraCore, ADR-0029) of the device's own report without `ageAtHostMs`. Equality of these bytes
    /// is what the reference compares through a SHA-256 of the same canonical text.
    static func fingerprint(of device: RoomDeviceStatus) -> String {
        var report = device
        report.ageAtHostMs = nil
        // Fail closed: a report that cannot be encoded never matches anything, so a reused sequence is refused.
        guard let data = try? CanonicalJSON.encode(report) else { return "unencodable-\(UUID().uuidString)" }
        return String(decoding: data, as: UTF8.self)
    }
}
