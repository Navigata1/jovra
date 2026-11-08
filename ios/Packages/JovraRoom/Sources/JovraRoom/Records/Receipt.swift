/// A host's answer to a command (receipt.schema.json). Inside a snapshot or bridge payload `schemaVersion` may be
/// omitted; the standalone `jovra.room.receipt/1` record requires it.
public struct RoomReceipt: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, CaseIterable, Sendable {
        case offlineDraft, unauthenticatedChannel, issuerNotAuthenticated, surfaceNotPermitted, noTargets
        case wrongSession, staleEpoch, unknownEpoch, notMember, roleNotGranted, roleNotPermitted, commandIdReuse
        case ttlTooLong, expired, unboundedTransit, unknownTarget, baseRevisionStale, undoTargetInvalid
        case hostEpochChanged, requiresResubmit
    }

    public struct Conflict: Codable, Equatable, Sendable {
        public var baseEventRevision: Int
        public var currentEventRevision: Int

        enum CodingKeys: String, CodingKey, CaseIterable { case baseEventRevision, currentEventRevision }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            baseEventRevision = try c.int(.baseEventRevision, Bound.revision)
            currentEventRevision = try c.int(.currentEventRevision, Bound.revision)
        }
    }

    public struct DeviceResult: Codable, Equatable, Sendable {
        public enum Reason: String, Codable, CaseIterable, Sendable {
            case startRequested, alreadyRecording, finalizing, stopRequested, notRecording, cameraPermissionDenied
            case foregroundRequired, finalizeFailed, unreachable, noAcknowledgement
        }
        public var deviceId: String
        public var status: DeviceResultStatus
        public var reason: Reason?

        enum CodingKeys: String, CodingKey, CaseIterable { case deviceId, status, reason }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            deviceId = try c.text(.deviceId, .id)
            status = try c.required(DeviceResultStatus.self, .status)
            reason = try c.nullable(Reason.self, .reason)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode(status, forKey: .status)
            try c.encodeNullable(reason, forKey: .reason)
        }
    }

    static let schemaVersionValue = "jovra.room.receipt/1"

    public var hasSchemaVersion: Bool
    public var commandId: String
    public var sessionId: String
    public var hostEpoch: Int
    public var type: CommandType
    public var status: ReceiptStatus
    public var reason: Reason?
    public var canonicalEventRevision: Int?
    public var appliedRecordId: String?
    public var conflict: Conflict?
    public var deviceResults: [DeviceResult]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, commandId, sessionId, hostEpoch, type, status, reason, canonicalEventRevision
        case appliedRecordId, conflict, deviceResults
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        hasSchemaVersion = try c.optionalConstant(.schemaVersion, Self.schemaVersionValue)
        commandId = try c.text(.commandId, .id)
        sessionId = try c.text(.sessionId, .id)
        hostEpoch = try c.int(.hostEpoch, Bound.hostEpoch)
        type = try c.required(CommandType.self, .type)
        status = try c.required(ReceiptStatus.self, .status)
        reason = try c.nullable(Reason.self, .reason)
        canonicalEventRevision = try c.nullableInt(.canonicalEventRevision, Bound.revision)
        appliedRecordId = try c.nullableText(.appliedRecordId, .id)
        conflict = try c.nullable(Conflict.self, .conflict)
        deviceResults = try c.objects(DeviceResult.self, .deviceResults, count: 0...6)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if hasSchemaVersion { try c.encode(Self.schemaVersionValue, forKey: .schemaVersion) }
        try c.encode(commandId, forKey: .commandId)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(hostEpoch, forKey: .hostEpoch)
        try c.encode(type, forKey: .type)
        try c.encode(status, forKey: .status)
        try c.encodeNullable(reason, forKey: .reason)
        try c.encodeNullable(canonicalEventRevision, forKey: .canonicalEventRevision)
        try c.encodeNullable(appliedRecordId, forKey: .appliedRecordId)
        try c.encodeNullable(conflict, forKey: .conflict)
        try c.encode(deviceResults, forKey: .deviceResults)
    }
}

/// The standalone `jovra.room.receipt/1` record.
public struct ReceiptRecord: Codable, Equatable, Sendable {
    public var receipt: RoomReceipt

    public init(from decoder: Decoder) throws {
        receipt = try RoomReceipt(from: decoder)
        guard receipt.hasSchemaVersion else { throw decoder.schemaError("schemaVersion required") }
    }

    public func encode(to encoder: Encoder) throws { try receipt.encode(to: encoder) }
}
