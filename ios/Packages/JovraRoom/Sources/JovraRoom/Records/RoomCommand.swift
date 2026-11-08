/// `jovra.room.command/1` (command.schema.json): one request to the host, with its issuer, claimed role, the
/// freshness it was issued on, its expiry and a payload of exactly one command type. The ledger that judges it is
/// W02's (#271); this is the record and its record rule.
public struct RoomCommand: Codable, Equatable, Sendable {
    public struct Issuer: Codable, Equatable, Sendable {
        public enum Surface: String, Codable, CaseIterable, Sendable { case phone, watch }
        public var memberId: String
        public var deviceId: String
        public var surface: Surface
        /// The paired phone for a watch, and null for a phone.
        public var bridgeDeviceId: String?

        enum CodingKeys: String, CodingKey, CaseIterable { case memberId, deviceId, surface, bridgeDeviceId }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            memberId = try c.text(.memberId, .id)
            deviceId = try c.text(.deviceId, .id)
            surface = try c.required(Surface.self, .surface)
            bridgeDeviceId = try c.nullableText(.bridgeDeviceId, .id)
            if (surface == .watch) != (bridgeDeviceId != nil) {
                throw c.schemaError(.bridgeDeviceId, "a watch names its bridge phone; a phone has none")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(memberId, forKey: .memberId)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode(surface, forKey: .surface)
            try c.encodeNullable(bridgeDeviceId, forKey: .bridgeDeviceId)
        }
    }

    public struct IssuedFreshness: Codable, Equatable, Sendable {
        public var basedOnSnapshotSeq: Int?
        public var basedOnFreshness: Freshness

        enum CodingKeys: String, CodingKey, CaseIterable { case basedOnSnapshotSeq, basedOnFreshness }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            basedOnSnapshotSeq = try c.nullableInt(.basedOnSnapshotSeq, Bound.seq)
            basedOnFreshness = try c.required(Freshness.self, .basedOnFreshness)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeNullable(basedOnSnapshotSeq, forKey: .basedOnSnapshotSeq)
            try c.encode(basedOnFreshness, forKey: .basedOnFreshness)
        }
    }

    public struct Expiry: Codable, Equatable, Sendable {
        public var ttlMs: Int
        /// Volatile: recomputed on every send and excluded from the idempotency fingerprint.
        public var ageAtSendMs: Int

        enum CodingKeys: String, CodingKey, CaseIterable { case ttlMs, ageAtSendMs }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            ttlMs = try c.int(.ttlMs, 1000...86_400_000)
            ageAtSendMs = try c.int(.ageAtSendMs, Bound.durationMs)
        }
    }

    public struct Target: Codable, Equatable, Sendable {
        public enum Scope: String, Codable, CaseIterable, Sendable { case session, device, allCameras }
        public var scope: Scope
        public var deviceIds: [String]

        enum CodingKeys: String, CodingKey, CaseIterable { case scope, deviceIds }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            scope = try c.required(Scope.self, .scope)
            deviceIds = try c.ids(.deviceIds, count: 0...6, unique: true)
        }
    }

    public enum ReviewReason: String, Codable, CaseIterable, Sendable { case point, serve, uncertainBounce, other }

    public enum Payload: Codable, Equatable, Sendable {
        case pointWon(winnerPlayerId: String)
        case undo(targetEventId: String)
        case markForReview(reason: ReviewReason, pointEventId: String?, sourceRefs: [SourceRef], note: String?)
        case startRequest
        case stopOne(targetLabel: String)
        /// Always confirmed on the wire (`confirmed: true`).
        case stopAllRequest(targetLabel: String)

        public var type: CommandType {
            switch self {
            case .pointWon: .pointWon
            case .undo: .undo
            case .markForReview: .markForReview
            case .startRequest: .startRequest
            case .stopOne: .stopOne
            case .stopAllRequest: .stopAllRequest
            }
        }

        private enum TypeKey: String, CodingKey, CaseIterable { case type }
        private enum PointKeys: String, CodingKey, CaseIterable { case type, winnerPlayerId }
        private enum UndoKeys: String, CodingKey, CaseIterable { case type, targetEventId }
        private enum MarkKeys: String, CodingKey, CaseIterable { case type, reason, pointEventId, sourceRefs, note }
        private enum StartKeys: String, CodingKey, CaseIterable { case type }
        private enum StopOneKeys: String, CodingKey, CaseIterable { case type, targetLabel }
        private enum StopAllKeys: String, CodingKey, CaseIterable { case type, targetLabel, confirmed }

        public init(from decoder: Decoder) throws {
            let probe = try decoder.container(keyedBy: TypeKey.self)
            switch try probe.required(CommandType.self, .type) {
            case .pointWon:
                self = .pointWon(winnerPlayerId: try decoder.strictContainer(PointKeys.self).text(.winnerPlayerId, .id))
            case .undo:
                self = .undo(targetEventId: try decoder.strictContainer(UndoKeys.self).text(.targetEventId, .id))
            case .markForReview:
                let c = try decoder.strictContainer(MarkKeys.self)
                self = .markForReview(reason: try c.required(ReviewReason.self, .reason),
                                      pointEventId: try c.nullableText(.pointEventId, .id),
                                      sourceRefs: try c.objects(SourceRef.self, .sourceRefs, count: 0...6),
                                      note: try c.nullableText(.note, .userText))
            case .startRequest:
                _ = try decoder.strictContainer(StartKeys.self)
                self = .startRequest
            case .stopOne:
                self = .stopOne(targetLabel: try decoder.strictContainer(StopOneKeys.self).text(.targetLabel, .userText))
            case .stopAllRequest:
                let c = try decoder.strictContainer(StopAllKeys.self)
                let label = try c.text(.targetLabel, .userText)
                try c.constant(.confirmed, true)
                self = .stopAllRequest(targetLabel: label)
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .pointWon(let winner):
                var c = encoder.container(keyedBy: PointKeys.self)
                try c.encode(type, forKey: .type)
                try c.encode(winner, forKey: .winnerPlayerId)
            case .undo(let target):
                var c = encoder.container(keyedBy: UndoKeys.self)
                try c.encode(type, forKey: .type)
                try c.encode(target, forKey: .targetEventId)
            case .markForReview(let reason, let pointEventId, let sourceRefs, let note):
                var c = encoder.container(keyedBy: MarkKeys.self)
                try c.encode(type, forKey: .type)
                try c.encode(reason, forKey: .reason)
                try c.encodeNullable(pointEventId, forKey: .pointEventId)
                try c.encode(sourceRefs, forKey: .sourceRefs)
                try c.encodeNullable(note, forKey: .note)
            case .startRequest:
                var c = encoder.container(keyedBy: StartKeys.self)
                try c.encode(type, forKey: .type)
            case .stopOne(let label):
                var c = encoder.container(keyedBy: StopOneKeys.self)
                try c.encode(type, forKey: .type)
                try c.encode(label, forKey: .targetLabel)
            case .stopAllRequest(let label):
                var c = encoder.container(keyedBy: StopAllKeys.self)
                try c.encode(type, forKey: .type)
                try c.encode(label, forKey: .targetLabel)
                try c.encode(true, forKey: .confirmed)
            }
        }
    }

    static let schemaVersionValue = "jovra.room.command/1"

    public var commandId: String
    public var sessionId: String
    public var hostEpoch: Int
    public var issuer: Issuer
    public var role: CommandRole
    public var issuedAt: String
    public var issuedFreshness: IssuedFreshness
    public var expiry: Expiry
    public var target: Target
    /// Required for score commands; null for capture requests.
    public var baseEventRevision: Int?
    public var payload: Payload

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, commandId, sessionId, hostEpoch, issuer, role, issuedAt, issuedFreshness, expiry, target
        case baseEventRevision, payload
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        try c.constant(.schemaVersion, Self.schemaVersionValue)
        commandId = try c.text(.commandId, .id)
        sessionId = try c.text(.sessionId, .id)
        hostEpoch = try c.int(.hostEpoch, Bound.hostEpoch)
        issuer = try c.required(Issuer.self, .issuer)
        role = try c.required(CommandRole.self, .role)
        issuedAt = try c.text(.issuedAt, .dateTime)
        issuedFreshness = try c.required(IssuedFreshness.self, .issuedFreshness)
        expiry = try c.required(Expiry.self, .expiry)
        target = try c.required(Target.self, .target)
        baseEventRevision = try c.nullableInt(.baseEventRevision, Bound.revision)
        payload = try c.required(Payload.self, .payload)
        try Self.checkShape(payload.type, target, baseEventRevision, c)
    }

    /// The schema's allOf: each command type fixes its target scope, target count and base revision.
    private static func checkShape(_ type: CommandType, _ target: Target, _ base: Int?,
                                   _ c: KeyedDecodingContainer<CodingKeys>) throws {
        let ids = target.deviceIds.count
        let (scope, count, needsBase): (Target.Scope, ClosedRange<Int>, Bool?) = switch type {
        case .pointWon, .undo: (.session, 0...0, true)
        case .markForReview: (.session, 0...0, nil)
        case .startRequest: (.device, 1...6, false)
        case .stopOne: (.device, 1...1, false)
        case .stopAllRequest: (.allCameras, 0...0, false)
        }
        guard target.scope == scope, count.contains(ids) else {
            throw c.schemaError(.target, "\(type.rawValue) targets \(scope.rawValue) with \(count) device ids")
        }
        if let needsBase, needsBase != (base != nil) {
            throw c.schemaError(.baseEventRevision, needsBase ? "a score command needs its base" : "must be null")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersionValue, forKey: .schemaVersion)
        try c.encode(commandId, forKey: .commandId)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(hostEpoch, forKey: .hostEpoch)
        try c.encode(issuer, forKey: .issuer)
        try c.encode(role, forKey: .role)
        try c.encode(issuedAt, forKey: .issuedAt)
        try c.encode(issuedFreshness, forKey: .issuedFreshness)
        try c.encode(expiry, forKey: .expiry)
        try c.encode(target, forKey: .target)
        try c.encodeNullable(baseEventRevision, forKey: .baseEventRevision)
        try c.encode(payload, forKey: .payload)
    }
}
