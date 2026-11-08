/// The host's latest-state envelope, `jovra.room.snapshot/1` (room-snapshot.schema.json). Every device row carries the
/// host-measured `ageAtHostMs`; no field lets anyone assert freshness.
public struct RoomSnapshotRecord: Codable, Equatable, Sendable {
    static let schemaVersionValue = "jovra.room.snapshot/1"

    public var sample: Bool
    public var sessionId: String
    public var hostDeviceId: String
    public var hostEpoch: Int
    public var hostKeySha256: String
    public var snapshotSeq: Int
    public var eventRevision: Int
    public var freshnessPolicy: RoomFreshnessPolicy
    public var capabilities: RoomCapabilities
    public var score: ScoreSummary?
    public var roster: RoomRoster
    public var devices: [RoomDeviceStatus]
    public var receipts: [RoomReceipt]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, sample, sessionId, hostDeviceId, hostEpoch, hostKeySha256, snapshotSeq, eventRevision
        case freshnessPolicy, capabilities, score, roster, devices, receipts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        try c.constant(.schemaVersion, Self.schemaVersionValue)
        sample = try c.required(Bool.self, .sample)
        sessionId = try c.text(.sessionId, .id)
        hostDeviceId = try c.text(.hostDeviceId, .id)
        hostEpoch = try c.int(.hostEpoch, Bound.hostEpoch)
        hostKeySha256 = try c.text(.hostKeySha256, .sha256)
        snapshotSeq = try c.int(.snapshotSeq, Bound.seq)
        eventRevision = try c.int(.eventRevision, Bound.revision)
        freshnessPolicy = try c.required(RoomFreshnessPolicy.self, .freshnessPolicy)
        capabilities = try c.required(RoomCapabilities.self, .capabilities)
        score = try c.optional(ScoreSummary.self, .score)
        roster = try c.required(RoomRoster.self, .roster)
        devices = try c.objects(RoomDeviceStatus.self, .devices, count: 0...6)
        if let index = devices.firstIndex(where: { $0.ageAtHostMs == nil }) {
            throw RoomDecodingError.schema(path: jsonPointer(c.codingPath, CodingKeys.devices) + "/\(index)/ageAtHostMs",
                                           reason: "required property missing")
        }
        receipts = try c.objects(RoomReceipt.self, .receipts, count: 0...64)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersionValue, forKey: .schemaVersion)
        try c.encode(sample, forKey: .sample)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(hostDeviceId, forKey: .hostDeviceId)
        try c.encode(hostEpoch, forKey: .hostEpoch)
        try c.encode(hostKeySha256, forKey: .hostKeySha256)
        try c.encode(snapshotSeq, forKey: .snapshotSeq)
        try c.encode(eventRevision, forKey: .eventRevision)
        try c.encode(freshnessPolicy, forKey: .freshnessPolicy)
        try c.encode(capabilities, forKey: .capabilities)
        try c.encodeIfPresent(score, forKey: .score)
        try c.encode(roster, forKey: .roster)
        try c.encode(devices, forKey: .devices)
        try c.encode(receipts, forKey: .receipts)
    }
}
