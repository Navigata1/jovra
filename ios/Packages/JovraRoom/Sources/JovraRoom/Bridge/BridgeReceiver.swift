/// The outcome of offering a bridge payload to the watch (spec/room/reference/jovra_room/bridge.py). Every refusal
/// leaves the receiver exactly as it was.
public enum BridgeVerdict: String, Equatable, Sendable, CaseIterable {
    case accepted
    /// Not the watch's own paired phone.
    case notPairedBridge
    /// A bridge instance (phone app process) the watch has already left.
    case bridgeInstanceRetired
    /// `bridgeSeq` did not strictly increase within the instance: a re-delivery is a replay, not a refresh.
    case replayOrOutOfOrder
    /// An older host epoch within one session.
    case staleEpoch
    /// Within one session and epoch, a lower `snapshotSeq` or `eventRevision`.
    case snapshotSeqRegressed, eventRevisionRegressed
}

/// Watch-side acceptance of `jovra.room.watch-bridge/1`. The watch is bound at pairing to one bridge, its own phone;
/// the companion channel (WatchConnectivity) authenticates the pairing, so the threats are an OS queue redelivering an
/// old payload, a late resend, or a payload from a previous bridge process. A new bridge instance or a new session
/// starts new marks, and neither lets an old payload back in.
///
/// Persist `state` on every accept and restore it at launch: replay marks survive a watch restart. Freshness never
/// does (a new process baseline makes every cached age Unknown; see `HealthSummary`).
public struct BridgeReceiver: Equatable, Sendable {
    /// The high-water marks of one session.
    public struct SessionMark: Codable, Equatable, Sendable {
        public var hostEpoch: Int
        public var snapshotSeq: Int
        public var eventRevision: Int
    }

    /// The persisted form.
    public struct State: Codable, Equatable, Sendable {
        public var pairedPhoneId: String
        public var instance: String?
        public var bridgeSeq: Int?
        public var retired: [String]
        public var sessions: [String: SessionMark]

        enum CodingKeys: String, CodingKey { case pairedPhoneId, instance, bridgeSeq, retired, sessions }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pairedPhoneId, forKey: .pairedPhoneId)
            try c.encodeNullable(instance, forKey: .instance)
            try c.encodeNullable(bridgeSeq, forKey: .bridgeSeq)
            try c.encode(retired, forKey: .retired)
            try c.encode(sessions, forKey: .sessions)
        }
    }

    public let pairedPhoneId: String
    private var instance: String?
    private var bridgeSeq: Int?
    private var retired: Set<String> = []
    private var sessions: [String: SessionMark] = [:]
    /// The last accepted payload (not persisted: after a restart the cached rows are Unknown until a new one arrives).
    public private(set) var applied: WatchBridgeSnapshot?

    public init(pairedPhoneId: String) { self.pairedPhoneId = pairedPhoneId }

    /// Accepts the payload or names why not, in the reference's order. Nothing changes unless `.accepted`.
    public mutating func accept(_ env: WatchBridgeSnapshot) -> BridgeVerdict {
        let b = env.bridge
        if b.bridgeDeviceId != pairedPhoneId { return .notPairedBridge }
        if retired.contains(b.bridgeInstanceId) { return .bridgeInstanceRetired }
        if b.bridgeInstanceId == instance, let bridgeSeq, b.bridgeSeq <= bridgeSeq { return .replayOrOutOfOrder }
        if let mark = sessions[env.sessionId] {
            if env.hostEpoch < mark.hostEpoch { return .staleEpoch }
            if env.hostEpoch == mark.hostEpoch {
                if env.snapshotSeq < mark.snapshotSeq { return .snapshotSeqRegressed }
                if env.eventRevision < mark.eventRevision { return .eventRevisionRegressed }
            }
        }
        if let instance, b.bridgeInstanceId != instance { retired.insert(instance) }
        instance = b.bridgeInstanceId
        bridgeSeq = b.bridgeSeq
        sessions[env.sessionId] = SessionMark(hostEpoch: env.hostEpoch, snapshotSeq: env.snapshotSeq,
                                              eventRevision: env.eventRevision)
        applied = env
        return .accepted
    }

    public var state: State {
        State(pairedPhoneId: pairedPhoneId, instance: instance, bridgeSeq: bridgeSeq, retired: retired.sorted(),
              sessions: sessions)
    }

    /// Restores the replay marks after a watch restart.
    public init(restoring state: State) {
        self.init(pairedPhoneId: state.pairedPhoneId)
        instance = state.instance
        bridgeSeq = state.bridgeSeq
        retired = Set(state.retired)
        sessions = state.sessions
    }
}
