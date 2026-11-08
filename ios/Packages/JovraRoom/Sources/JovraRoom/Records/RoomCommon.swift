// Shared objects of room-common.schema.json: the freshness policy as carried on the wire, capabilities, the score
// summary, the roster and source references.

/// The `freshnessPolicy` object a host or bridge sends. v1 pins the proposal defaults (`const` 5,000 / 15,000 ms).
public struct RoomFreshnessPolicy: Codable, Equatable, Sendable {
    public let policy: FreshnessPolicy
    /// `proposalOnly: true` when present: the thresholds are product defaults to benchmark.
    public let proposalOnly: Bool

    public init(proposalOnly: Bool = true) {
        policy = FreshnessPolicy(freshMaxMs: 5000, delayedMaxMs: 15000)
        self.proposalOnly = proposalOnly
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case freshMaxMs, delayedMaxMs, proposalOnly }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        try c.constant(.freshMaxMs, 5000)
        try c.constant(.delayedMaxMs, 15000)
        proposalOnly = try c.optionalConstant(.proposalOnly, true)
        policy = FreshnessPolicy(freshMaxMs: 5000, delayedMaxMs: 15000)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(policy.freshMaxMs, forKey: .freshMaxMs)
        try c.encode(policy.delayedMaxMs, forKey: .delayedMaxMs)
        if proposalOnly { try c.encode(true, forKey: .proposalOnly) }
    }
}

/// What the room can deliver in this session. v1 never delivers live serve speed or automated line calls: both are
/// `const false`, so they are not stored.
public struct RoomCapabilities: Codable, Equatable, Sendable {
    public var recordingHealth: Bool
    public var manualScore: Bool
    public var markForReview: Bool
    /// Phone-produced, post-capture serve-speed results may be forwarded (never live). Absent is not the same as false
    /// on the wire, so it is kept as sent.
    public var serveSpeedResults: Bool?

    public init(recordingHealth: Bool, manualScore: Bool, markForReview: Bool, serveSpeedResults: Bool? = nil) {
        self.recordingHealth = recordingHealth
        self.manualScore = manualScore
        self.markForReview = markForReview
        self.serveSpeedResults = serveSpeedResults
    }

    public var deliversServeSpeedResults: Bool { serveSpeedResults == true }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case recordingHealth, manualScore, markForReview, serveSpeedResults, liveServeSpeed, automatedLineCalls
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        recordingHealth = try c.required(Bool.self, .recordingHealth)
        manualScore = try c.required(Bool.self, .manualScore)
        markForReview = try c.required(Bool.self, .markForReview)
        serveSpeedResults = try c.optional(Bool.self, .serveSpeedResults)
        try c.constant(.liveServeSpeed, false)
        try c.constant(.automatedLineCalls, false)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(recordingHealth, forKey: .recordingHealth)
        try c.encode(manualScore, forKey: .manualScore)
        try c.encode(markForReview, forKey: .markForReview)
        try c.encodeIfPresent(serveSpeedResults, forKey: .serveSpeedResults)
        try c.encode(false, forKey: .liveServeSpeed)
        try c.encode(false, forKey: .automatedLineCalls)
    }
}

/// Derived from the authoritative point-event log at `eventRevision` (ADR-0003). Display only; label is `manual`.
public struct ScoreSummary: Codable, Equatable, Sendable {
    public struct Player: Codable, Equatable, Sendable {
        public enum Point: String, Codable, CaseIterable, Sendable {
            case love = "0", fifteen = "15", thirty = "30", forty = "40", advantage = "AD", none = "-"
        }
        public var playerId: String
        public var games: Int
        public var point: Point

        enum CodingKeys: String, CodingKey, CaseIterable { case playerId, games, point }

        public init(from decoder: Decoder) throws {
            let c = try decoder.strictContainer(CodingKeys.self)
            playerId = try c.text(.playerId, .id)
            games = try c.int(.games, 0...99)
            point = try c.required(Point.self, .point)
        }
    }

    public var eventRevision: Int
    public var players: [Player]

    enum CodingKeys: String, CodingKey, CaseIterable { case eventRevision, label, players }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        eventRevision = try c.int(.eventRevision, Bound.revision)
        try c.constant(.label, "manual")
        players = try c.objects(Player.self, .players, count: 2...4)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(eventRevision, forKey: .eventRevision)
        try c.encode("manual", forKey: .label)
        try c.encode(players, forKey: .players)
    }
}

/// The host's enrolled camera ids at a roster revision. Receivers count enrolment from the roster, never from the
/// rows that happen to be present.
public struct RoomRoster: Codable, Equatable, Sendable {
    public var rosterRevision: Int
    public var cameraDeviceIds: [String]

    public init(rosterRevision: Int, cameraDeviceIds: [String]) {
        self.rosterRevision = rosterRevision
        self.cameraDeviceIds = cameraDeviceIds
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case rosterRevision, cameraDeviceIds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        rosterRevision = try c.int(.rosterRevision, Bound.seq)
        cameraDeviceIds = try c.ids(.cameraDeviceIds, count: 1...6, unique: true)
    }
}

public struct FrameRange: Codable, Equatable, Sendable {
    public var startFrame: Int
    public var endFrame: Int

    enum CodingKeys: String, CodingKey, CaseIterable { case startFrame, endFrame }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        startFrame = try c.int(.startFrame, 0...Int.max)
        endFrame = try c.int(.endFrame, 0...Int.max)
    }
}

/// Where evidence lives: a device's capture instance and segment, optionally a frame range on that segment.
public struct SourceRef: Codable, Equatable, Sendable {
    public var deviceId: String
    public var captureInstanceId: String
    public var segmentId: String
    public var frameRange: FrameRange?

    enum CodingKeys: String, CodingKey, CaseIterable { case deviceId, captureInstanceId, segmentId, frameRange }

    public init(from decoder: Decoder) throws {
        let c = try decoder.strictContainer(CodingKeys.self)
        deviceId = try c.text(.deviceId, .id)
        captureInstanceId = try c.text(.captureInstanceId, .id)
        segmentId = try c.text(.segmentId, .id)
        frameRange = try c.nullable(FrameRange.self, .frameRange)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(deviceId, forKey: .deviceId)
        try c.encode(captureInstanceId, forKey: .captureInstanceId)
        try c.encode(segmentId, forKey: .segmentId)
        try c.encodeNullable(frameRange, forKey: .frameRange)
    }
}
