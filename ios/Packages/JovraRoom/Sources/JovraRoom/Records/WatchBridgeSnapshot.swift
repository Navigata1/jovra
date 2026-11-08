/// `jovra.room.watch-bridge/1` (watch-bridge-snapshot.schema.json): what a paired phone forwards to its own watch.
/// Ages are the bridge's measurements (`ageAtBridgeMs`); the watch adds its own `receiverObservation` on accept.
/// This is the single watch contract (ADR-0026, docs/spec/watch-v1-spec.md).
public struct WatchBridgeSnapshot: Codable, Equatable, Sendable {
    public struct Bridge: Codable, Equatable, Sendable {
        public enum Channel: String, Codable, CaseIterable, Sendable {
            case watchConnectivity = "watchconnectivity", wearableDataLayer = "wearable-data-layer"
        }
        public var bridgeDeviceId: String
        public var bridgeInstanceId: String
        public var channel: Channel
        public var bridgeSeq: Int
        public var snapshotAgeAtBridgeMs: Int

        enum CodingKeys: String, CodingKey, CaseIterable {
            case bridgeDeviceId, bridgeInstanceId, channel, bridgeSeq, snapshotAgeAtBridgeMs
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            bridgeDeviceId = try c.text(.bridgeDeviceId, .id)
            bridgeInstanceId = try c.text(.bridgeInstanceId, .id)
            channel = try c.required(Channel.self, .channel)
            bridgeSeq = try c.int(.bridgeSeq, Bound.seq)
            snapshotAgeAtBridgeMs = try c.int(.snapshotAgeAtBridgeMs, Bound.durationMs)
        }
    }

    /// The watch owner's membership: the roles the host granted and the command types left on for the watch.
    public struct Participant: Codable, Equatable, Sendable {
        public var memberId: String
        public var commandRoles: [CommandRole]
        public var watchCommandTypes: [CommandType]

        enum CodingKeys: String, CodingKey, CaseIterable { case memberId, commandRoles, watchCommandTypes }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            memberId = try c.text(.memberId, .id)
            commandRoles = try c.values(CommandRole.self, .commandRoles, count: 1...4)
            watchCommandTypes = try c.values(CommandType.self, .watchCommandTypes, count: 0...6)
        }
    }

    public struct Alert: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable {
            case ownRecordingFailed, ownStorageCritical, cameraUnknown, storageLow, batteryLow, thermalWarning
            case reviewNeeded

            /// Only the watch owner's own recording failure or storage may be critical (records.py OWN_ALERTS).
            public var isOwnCapture: Bool { self == .ownRecordingFailed || self == .ownStorageCritical }
        }
        public enum Severity: String, Codable, CaseIterable, Sendable { case critical, deferred }

        public var alertId: String
        public var kind: Kind
        public var deviceId: String?
        public var severity: Severity
        public var ageAtBridgeMs: Int

        enum CodingKeys: String, CodingKey, CaseIterable { case alertId, kind, deviceId, severity, ageAtBridgeMs }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            alertId = try c.text(.alertId, .id)
            kind = try c.required(Kind.self, .kind)
            deviceId = try c.nullableText(.deviceId, .id)
            severity = try c.required(Severity.self, .severity)
            ageAtBridgeMs = try c.int(.ageAtBridgeMs, Bound.durationMs)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(alertId, forKey: .alertId)
            try c.encode(kind, forKey: .kind)
            try c.encodeNullable(deviceId, forKey: .deviceId)
            try c.encode(severity, forKey: .severity)
            try c.encode(ageAtBridgeMs, forKey: .ageAtBridgeMs)
        }
    }

    /// A camera row as the bridge forwards it: the camera's own report plus the bridge's age measurement.
    public struct Device: Codable, Equatable, Sendable {
        public struct Flags: Codable, Equatable, Sendable {
            public var storageLow: Bool?
            public var batteryLow: Bool?
            public var thermalWarning: Bool?

            enum CodingKeys: String, CodingKey, CaseIterable { case storageLow, batteryLow, thermalWarning }

            public init(from decoder: Decoder) throws {
                let c = try decoder.strictContainer(CodingKeys.self)
                storageLow = try c.optional(Bool.self, .storageLow)
                batteryLow = try c.optional(Bool.self, .batteryLow)
                thermalWarning = try c.optional(Bool.self, .thermalWarning)
            }
        }

        public var deviceId: String
        public var captureInstanceId: String
        public var segmentId: String
        public var deviceSeq: Int
        public var captureState: CaptureState
        public var ageAtBridgeMs: Int
        public var lastReportedElapsedMs: Int
        public var flags: Flags?

        enum CodingKeys: String, CodingKey, CaseIterable {
            case deviceId, captureInstanceId, segmentId, deviceSeq, captureState, ageAtBridgeMs, lastReportedElapsedMs
            case flags
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            deviceId = try c.text(.deviceId, .id)
            captureInstanceId = try c.text(.captureInstanceId, .id)
            segmentId = try c.text(.segmentId, .id)
            deviceSeq = try c.int(.deviceSeq, Bound.seq)
            captureState = try c.required(CaptureState.self, .captureState)
            ageAtBridgeMs = try c.int(.ageAtBridgeMs, Bound.durationMs)
            lastReportedElapsedMs = try c.int(.lastReportedElapsedMs, Bound.durationMs)
            flags = try c.optional(Flags.self, .flags)
        }
    }

    /// What the watch writes on accept. A queued delivery is always unbounded; an interactive one always bounded.
    public struct ReceiverObservationRecord: Codable, Equatable, Sendable {
        public enum Delivery: String, Codable, CaseIterable, Sendable { case interactive, queued, fixture }
        public var delivery: Delivery
        public var observation: ReceiverObservation

        enum CodingKeys: String, CodingKey, CaseIterable {
            case delivery, transitBounded, transitMs, processBaselineId, acceptedAtMonoMs
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            delivery = try c.required(Delivery.self, .delivery)
            let bounded = try c.required(Bool.self, .transitBounded)
            let transitMs = try c.nullableInt(.transitMs, Bound.durationMs)
            if bounded != (transitMs != nil) {
                throw c.schemaError(.transitMs, "a bounded transit states its bound; an unbounded one is null")
            }
            if (delivery == .queued && bounded) || (delivery == .interactive && !bounded) {
                throw c.schemaError(.transitBounded, "queued is always unbounded and interactive always bounded")
            }
            observation = ReceiverObservation(transitBounded: bounded, transitMs: transitMs,
                                              processBaselineId: try c.text(.processBaselineId, .id),
                                              acceptedAtMonoMs: try c.int(.acceptedAtMonoMs, Bound.seq))
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(delivery, forKey: .delivery)
            try c.encode(observation.transitBounded, forKey: .transitBounded)
            try c.encodeNullable(observation.transitMs, forKey: .transitMs)
            try c.encode(observation.processBaselineId, forKey: .processBaselineId)
            try c.encode(observation.acceptedAtMonoMs, forKey: .acceptedAtMonoMs)
        }
    }

    static let schemaVersionValue = "jovra.room.watch-bridge/1"

    public var sample: Bool
    public var sessionId: String
    public var hostEpoch: Int
    public var snapshotSeq: Int
    public var eventRevision: Int
    public var bridge: Bridge
    public var participant: Participant
    public var freshnessPolicy: RoomFreshnessPolicy
    public var capabilities: RoomCapabilities
    public var score: ScoreSummary?
    public var roster: RoomRoster
    /// `latestServe` may be absent or null on the wire; both mean no forwarded result, and each re-encodes as sent.
    public var latestServe: AnalysisResult?
    public var latestServeIsExplicitNull: Bool
    public var alerts: [Alert]
    public var devices: [Device]
    public var receipts: [RoomReceipt]
    public var receiverObservation: ReceiverObservationRecord?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, sample, sessionId, hostEpoch, snapshotSeq, eventRevision, bridge, participant
        case freshnessPolicy, capabilities, score, roster, latestServe, alerts, devices, receipts, receiverObservation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        try c.constant(.schemaVersion, Self.schemaVersionValue)
        sample = try c.required(Bool.self, .sample)
        sessionId = try c.text(.sessionId, .id)
        hostEpoch = try c.int(.hostEpoch, Bound.hostEpoch)
        snapshotSeq = try c.int(.snapshotSeq, Bound.seq)
        eventRevision = try c.int(.eventRevision, Bound.revision)
        bridge = try c.required(Bridge.self, .bridge)
        participant = try c.required(Participant.self, .participant)
        freshnessPolicy = try c.required(RoomFreshnessPolicy.self, .freshnessPolicy)
        capabilities = try c.required(RoomCapabilities.self, .capabilities)
        score = try c.optional(ScoreSummary.self, .score)
        roster = try c.required(RoomRoster.self, .roster)
        latestServeIsExplicitNull = c.contains(.latestServe) ? try c.decodeNil(forKey: .latestServe) : false
        latestServe = latestServeIsExplicitNull ? nil : try c.optional(AnalysisResult.self, .latestServe)
        alerts = try c.objects(Alert.self, .alerts, count: 0...8)
        devices = try c.objects(Device.self, .devices, count: 0...6)
        receipts = try c.objects(RoomReceipt.self, .receipts, count: 0...16)
        receiverObservation = try c.optional(ReceiverObservationRecord.self, .receiverObservation)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersionValue, forKey: .schemaVersion)
        try c.encode(sample, forKey: .sample)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(hostEpoch, forKey: .hostEpoch)
        try c.encode(snapshotSeq, forKey: .snapshotSeq)
        try c.encode(eventRevision, forKey: .eventRevision)
        try c.encode(bridge, forKey: .bridge)
        try c.encode(participant, forKey: .participant)
        try c.encode(freshnessPolicy, forKey: .freshnessPolicy)
        try c.encode(capabilities, forKey: .capabilities)
        try c.encodeIfPresent(score, forKey: .score)
        try c.encode(roster, forKey: .roster)
        if latestServeIsExplicitNull { try c.encodeNil(forKey: .latestServe) }
        else { try c.encodeIfPresent(latestServe, forKey: .latestServe) }
        try c.encode(alerts, forKey: .alerts)
        try c.encode(devices, forKey: .devices)
        try c.encode(receipts, forKey: .receipts)
        try c.encodeIfPresent(receiverObservation, forKey: .receiverObservation)
    }
}

/// `jovra.room.watch-local/1`: phone and its own watch only, never room commands. Each kind carries exactly its own
/// fields (the schema's allOf); `stopOwnPhone` has no target, so a watch can only stop its own phone.
public struct WatchLocalMessage: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case echoRequest, echoReply, ackAlert, stopOwnPhone, stopOwnPhoneResult

        /// Required fields; every other optional field is forbidden for the kind.
        var required: Set<CodingKeys> {
            switch self {
            case .echoRequest: [.echoMonoMs]
            case .echoReply: [.echoMonoMs, .bridgeSeq, .inReplyTo]
            case .ackAlert: [.alertId]
            case .stopOwnPhone: [.confirmed]
            case .stopOwnPhoneResult: [.result, .inReplyTo]
            }
        }
    }

    public enum StopResult: String, Codable, CaseIterable, Sendable { case stopRequested, notRecording, finalizeFailed }

    static let schemaVersionValue = "jovra.room.watch-local/1"

    public var messageId: String
    public var sessionId: String
    public var kind: Kind
    public var echoMonoMs: Int?
    public var bridgeSeq: Int?
    public var alertId: String?
    public var result: StopResult?
    public var inReplyTo: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, messageId, sessionId, kind, echoMonoMs, bridgeSeq, alertId, confirmed, result, inReplyTo
        static let perKind: Set<CodingKeys> = [.echoMonoMs, .bridgeSeq, .alertId, .confirmed, .result, .inReplyTo]
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        try c.constant(.schemaVersion, Self.schemaVersionValue)
        messageId = try c.text(.messageId, .id)
        sessionId = try c.text(.sessionId, .id)
        kind = try c.required(Kind.self, .kind)
        for key in CodingKeys.perKind.sorted(by: { $0.stringValue < $1.stringValue }) {
            if kind.required.contains(key) != c.contains(key) {
                throw c.schemaError(key, kind.required.contains(key) ? "required property missing"
                                                                     : "not allowed for \(kind.rawValue)")
            }
        }
        echoMonoMs = try c.optionalInt(.echoMonoMs, Bound.seq)
        bridgeSeq = try c.optionalInt(.bridgeSeq, Bound.seq)
        alertId = try c.optionalText(.alertId, .id)
        _ = try c.optionalConstant(.confirmed, true)
        result = try c.optional(StopResult.self, .result)
        inReplyTo = try c.optionalText(.inReplyTo, .id)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersionValue, forKey: .schemaVersion)
        try c.encode(messageId, forKey: .messageId)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(echoMonoMs, forKey: .echoMonoMs)
        try c.encodeIfPresent(bridgeSeq, forKey: .bridgeSeq)
        try c.encodeIfPresent(alertId, forKey: .alertId)
        if kind == .stopOwnPhone { try c.encode(true, forKey: .confirmed) }
        try c.encodeIfPresent(result, forKey: .result)
        try c.encodeIfPresent(inReplyTo, forKey: .inReplyTo)
    }
}
