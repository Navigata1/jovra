/// A camera's own report (device-status.schema.json `deviceStatus`). It has no freshness, "connected" or Unknown
/// field: freshness is always derived by the receiver. As a standalone `jovra.room.device-status/1` record it carries
/// schemaVersion, sessionId and hostEpoch; inside a snapshot the host adds its own measurement `ageAtHostMs`.
public struct RoomDeviceStatus: Codable, Equatable, Sendable {
    public enum FailureReason: String, Codable, CaseIterable, Sendable {
        case cameraPermissionDenied, microphonePermissionDenied, storageFull, thermalShutdown, interrupted
        case writerFailed, other
    }

    public struct Observations: Codable, Equatable, Sendable {
        public var storageFreeBytes: Int?
        public var estimatedMinutesLeft: Int?
        public var batteryPercent: Int?
        public var charging: Bool?
        public var lowPowerMode: Bool?
        public var thermal: ThermalState

        enum CodingKeys: String, CodingKey, CaseIterable {
            case storageFreeBytes, estimatedMinutesLeft, batteryPercent, charging, lowPowerMode, thermal
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            storageFreeBytes = try c.nullableInt(.storageFreeBytes, 0...Int.max)
            estimatedMinutesLeft = try c.nullableInt(.estimatedMinutesLeft, 0...Int.max)
            batteryPercent = try c.nullableInt(.batteryPercent, 0...100)
            charging = try c.nullable(Bool.self, .charging)
            lowPowerMode = try c.nullable(Bool.self, .lowPowerMode)
            thermal = try c.required(ThermalState.self, .thermal)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeNullable(storageFreeBytes, forKey: .storageFreeBytes)
            try c.encodeNullable(estimatedMinutesLeft, forKey: .estimatedMinutesLeft)
            try c.encodeNullable(batteryPercent, forKey: .batteryPercent)
            try c.encodeNullable(charging, forKey: .charging)
            try c.encodeNullable(lowPowerMode, forKey: .lowPowerMode)
            try c.encode(thermal, forKey: .thermal)
        }
    }

    static let schemaVersionValue = "jovra.room.device-status/1"

    /// Present on the standalone record; optional inside a snapshot.
    public var hasSchemaVersion: Bool
    public var sessionId: String?
    public var hostEpoch: Int?
    public var deviceId: String
    public var captureInstanceId: String
    public var segmentId: String
    public var deviceSeq: Int
    public var captureState: CaptureState
    /// `primary` or `camera` when present.
    public var captureRole: CaptureRole?
    public var lastReportedElapsedMs: Int
    /// Present exactly when `captureState` is Failed.
    public var failureReason: FailureReason?
    /// The host's measurement of this report's age; required inside a snapshot, refused on a sender's own record.
    public var ageAtHostMs: Int?
    public var observations: Observations

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, sessionId, hostEpoch, deviceId, captureInstanceId, segmentId, deviceSeq, captureState
        case captureRole, lastReportedElapsedMs, failureReason, ageAtHostMs, observations
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        hasSchemaVersion = try c.optionalConstant(.schemaVersion, Self.schemaVersionValue)
        sessionId = try c.optionalText(.sessionId, .id)
        hostEpoch = try c.optionalInt(.hostEpoch, Bound.hostEpoch)
        deviceId = try c.text(.deviceId, .id)
        captureInstanceId = try c.text(.captureInstanceId, .id)
        segmentId = try c.text(.segmentId, .id)
        deviceSeq = try c.int(.deviceSeq, Bound.seq)
        captureState = try c.required(CaptureState.self, .captureState)
        captureRole = try c.optional(CaptureRole.self, .captureRole)
        if captureRole == CaptureRole.none { throw c.schemaError(.captureRole, "a reporting device is primary or camera") }
        lastReportedElapsedMs = try c.int(.lastReportedElapsedMs, Bound.durationMs)
        failureReason = try c.optional(FailureReason.self, .failureReason)
        if (captureState == .failed) != (failureReason != nil) {
            throw c.schemaError(.failureReason, "required exactly when captureState is Failed")
        }
        ageAtHostMs = try c.optionalInt(.ageAtHostMs, Bound.durationMs)
        observations = try c.required(Observations.self, .observations)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if hasSchemaVersion { try c.encode(Self.schemaVersionValue, forKey: .schemaVersion) }
        try c.encodeIfPresent(sessionId, forKey: .sessionId)
        try c.encodeIfPresent(hostEpoch, forKey: .hostEpoch)
        try c.encode(deviceId, forKey: .deviceId)
        try c.encode(captureInstanceId, forKey: .captureInstanceId)
        try c.encode(segmentId, forKey: .segmentId)
        try c.encode(deviceSeq, forKey: .deviceSeq)
        try c.encode(captureState, forKey: .captureState)
        try c.encodeIfPresent(captureRole, forKey: .captureRole)
        try c.encode(lastReportedElapsedMs, forKey: .lastReportedElapsedMs)
        try c.encodeIfPresent(failureReason, forKey: .failureReason)
        try c.encodeIfPresent(ageAtHostMs, forKey: .ageAtHostMs)
        try c.encode(observations, forKey: .observations)
    }
}

/// The standalone `jovra.room.device-status/1` record: schemaVersion, sessionId and hostEpoch are required.
public struct DeviceStatusRecord: Codable, Equatable, Sendable {
    public var status: RoomDeviceStatus

    public init(from decoder: Decoder) throws {
        status = try RoomDeviceStatus(from: decoder)
        guard status.hasSchemaVersion else { throw decoder.schemaError("schemaVersion required") }
        guard status.sessionId != nil, status.hostEpoch != nil else {
            throw decoder.schemaError("sessionId and hostEpoch required")
        }
    }

    public func encode(to encoder: Encoder) throws { try status.encode(to: encoder) }
}
