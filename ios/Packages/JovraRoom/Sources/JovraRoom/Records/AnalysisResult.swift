/// `jovra.room.analysis-result/1`: a phone-produced, post-capture result with its sources, provenance label and
/// either a value with units and uncertainty or an explicit unavailable reason. It never changes the score.
public struct AnalysisResult: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case serveSpeed, bounceHint }
    public enum Units: String, Codable, CaseIterable, Sendable { case mph, kmh = "km/h", ms = "m/s", cm }
    public enum UnavailableReason: String, Codable, CaseIterable, Sendable {
        case capabilityAbsent, capabilityUnsupported, calibrationMissing, clockAlignmentMissing, occluded
        case lowConfidence, notYetProduced
    }
    public enum ReviewState: String, Codable, CaseIterable, Sendable { case notRequired, reviewNeeded, reviewed }

    public struct Uncertainty: Codable, Equatable, Sendable {
        public enum Level: String, Codable, CaseIterable, Sendable { case p90, p95, range }
        /// Decimal strings (`decimalString`), never binary floating point on the wire.
        public var lower: String
        public var upper: String
        public var level: Level

        enum CodingKeys: String, CodingKey, CaseIterable { case lower, upper, level }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            lower = try c.text(.lower, .decimal)
            upper = try c.text(.upper, .decimal)
            level = try c.required(Level.self, .level)
        }
    }

    static let schemaVersionValue = "jovra.room.analysis-result/1"

    public var sample: Bool
    public var resultId: String
    public var sessionId: String
    public var capabilityId: String
    public var kind: Kind
    public var sourceRefs: [SourceRef]
    public var pointEventId: String?
    public var producedAt: String
    public var producedAtEventRevision: Int
    public var label: ProvenanceLabel
    public var modelVersion: String?
    public var calibrationId: String?
    /// A decimal string, or nil with an `unavailableReason`.
    public var value: String?
    public var units: Units?
    public var uncertainty: Uncertainty?
    public var unavailableReason: UnavailableReason?
    public var reviewState: ReviewState

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, sample, resultId, sessionId, capabilityId, kind, sourceRefs, pointEventId, producedAt
        case producedAtEventRevision, label, modelVersion, calibrationId, value, units, uncertainty, unavailableReason
        case reviewState, scoreEffect
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        try c.constant(.schemaVersion, Self.schemaVersionValue)
        sample = try c.required(Bool.self, .sample)
        resultId = try c.text(.resultId, .id)
        sessionId = try c.text(.sessionId, .id)
        capabilityId = try c.text(.capabilityId, .capabilityId)
        kind = try c.required(Kind.self, .kind)
        sourceRefs = try c.objects(SourceRef.self, .sourceRefs, count: 1...6)
        pointEventId = try c.nullableText(.pointEventId, .id)
        producedAt = try c.text(.producedAt, .dateTime)
        producedAtEventRevision = try c.int(.producedAtEventRevision, Bound.revision)
        label = try c.required(ProvenanceLabel.self, .label)
        modelVersion = try c.nullableText(.modelVersion, .modelVersion)
        calibrationId = try c.nullableText(.calibrationId, .id)
        value = try c.nullableText(.value, .decimal)
        units = try c.nullable(Units.self, .units)
        uncertainty = try c.nullable(Uncertainty.self, .uncertainty)
        unavailableReason = try c.nullable(UnavailableReason.self, .unavailableReason)
        reviewState = try c.required(ReviewState.self, .reviewState)
        try c.constant(.scoreEffect, "none")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersionValue, forKey: .schemaVersion)
        try c.encode(sample, forKey: .sample)
        try c.encode(resultId, forKey: .resultId)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(capabilityId, forKey: .capabilityId)
        try c.encode(kind, forKey: .kind)
        try c.encode(sourceRefs, forKey: .sourceRefs)
        try c.encodeNullable(pointEventId, forKey: .pointEventId)
        try c.encode(producedAt, forKey: .producedAt)
        try c.encode(producedAtEventRevision, forKey: .producedAtEventRevision)
        try c.encode(label, forKey: .label)
        try c.encodeNullable(modelVersion, forKey: .modelVersion)
        try c.encodeNullable(calibrationId, forKey: .calibrationId)
        try c.encodeNullable(value, forKey: .value)
        try c.encodeNullable(units, forKey: .units)
        try c.encodeNullable(uncertainty, forKey: .uncertainty)
        try c.encodeNullable(unavailableReason, forKey: .unavailableReason)
        try c.encode(reviewState, forKey: .reviewState)
        try c.encode("none", forKey: .scoreEffect)
    }
}
