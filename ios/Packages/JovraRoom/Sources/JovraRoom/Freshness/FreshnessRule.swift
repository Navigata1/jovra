/// The freshness thresholds (spec/room room-common `freshnessPolicy`). v1 pins the proposal defaults: product
/// defaults to benchmark, not OS scheduling guarantees.
public struct FreshnessPolicy: Equatable, Hashable, Sendable {
    public let freshMaxMs: Int
    public let delayedMaxMs: Int

    public init(freshMaxMs: Int, delayedMaxMs: Int) {
        self.freshMaxMs = freshMaxMs
        self.delayedMaxMs = delayedMaxMs
    }

    /// Fresh at 5,000 ms or less; Delayed above that up to 15,000 ms; Unknown above that.
    public static let proposal = FreshnessPolicy(freshMaxMs: 5000, delayedMaxMs: 15000)

    /// `nil` (an age that cannot be established) is Unknown.
    public func classify(ageMs: Int?) -> Freshness {
        guard let ageMs else { return .unknown }
        if ageMs <= freshMaxMs { return .fresh }
        if ageMs <= delayedMaxMs { return .delayed }
        return .unknown
    }
}

/// Invalid freshness input (freshness.py `_duration` and the bounded-transit check). Codes are the fixture's.
public enum FreshnessInputError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A negative duration; the associated value names the input.
    case negativeAge(String)
    /// A transit marked bounded without its bound.
    case transitBoundMissing

    public var code: String {
        switch self {
        case .negativeAge: "negativeAge"
        case .transitBoundMissing: "transitBoundMissing"
        }
    }

    public var description: String {
        switch self {
        case .negativeAge(let name): "negativeAge: \(name)"
        case .transitBoundMissing: "transitBoundMissing: a bounded transit must state its bound"
        }
    }
}

/// What a receiver records when it accepts a payload: whether transit was bounded (and by how much), the process
/// baseline it measured under and its own monotonic time of acceptance. Mirrors the watch-bridge
/// `receiverObservation` (without the delivery kind) and the phone path's observation.
public struct ReceiverObservation: Codable, Equatable, Hashable, Sendable {
    public var transitBounded: Bool
    public var transitMs: Int?
    public var processBaselineId: String
    public var acceptedAtMonoMs: Int

    public init(transitBounded: Bool, transitMs: Int?, processBaselineId: String, acceptedAtMonoMs: Int) {
        self.transitBounded = transitBounded
        self.transitMs = transitMs
        self.processBaselineId = processBaselineId
        self.acceptedAtMonoMs = acceptedAtMonoMs
    }

    enum CodingKeys: String, CodingKey { case transitBounded, transitMs, processBaselineId, acceptedAtMonoMs }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(transitBounded, forKey: .transitBounded)
        try c.encodeNullable(transitMs, forKey: .transitMs)
        try c.encode(processBaselineId, forKey: .processBaselineId)
        try c.encode(acceptedAtMonoMs, forKey: .acceptedAtMonoMs)
    }
}

/// Receiver-owned freshness (spec/room/reference/jovra_room/freshness.py). Ages are chained monotonic durations,
/// each measured on one device:
///
///     age = sender-side age (ageAtHostMs or ageAtBridgeMs) + known transit + receiver time since accept
///
/// Wall clocks from different devices are never subtracted. An unbounded transit (a queued or background delivery,
/// even one that arrived this instant) or a lost process baseline (restart) is Unknown until a bounded exchange renews
/// it; arrival alone never resets freshness.
public enum FreshnessRule {
    /// The receiver's conservative age in ms, or `nil` when it cannot be established (Unknown).
    public static func chainedAgeMs(senderAgeMs: Int, sinceAcceptMs: Int, transitBounded: Bool, transitMs: Int?,
                                    baselineValid: Bool) throws(FreshnessInputError) -> Int? {
        let sender = try duration("senderAgeMs", senderAgeMs)
        let since = try duration("sinceAcceptMs", sinceAcceptMs)
        var transit = 0
        if transitBounded {
            guard let transitMs else { throw .transitBoundMissing }
            transit = try duration("transitMs", transitMs)
        }
        guard transitBounded, baselineValid else { return nil }
        let (partial, overflow1) = sender.addingReportingOverflow(transit)
        let (total, overflow2) = partial.addingReportingOverflow(since)
        return overflow1 || overflow2 ? nil : total
    }

    public static func classify(senderAgeMs: Int, sinceAcceptMs: Int, transitBounded: Bool, transitMs: Int?,
                                baselineValid: Bool,
                                policy: FreshnessPolicy = .proposal) throws(FreshnessInputError) -> Freshness {
        policy.classify(ageMs: try chainedAgeMs(senderAgeMs: senderAgeMs, sinceAcceptMs: sinceAcceptMs,
                                                transitBounded: transitBounded, transitMs: transitMs,
                                                baselineValid: baselineValid))
    }

    /// One sender age read against an acceptance observation at the receiver's `nowMonoMs` (freshness.py `_observe`).
    /// The baseline is valid only when the observation was taken under `currentBaselineId`; a clock that appears to
    /// run backwards (a reused baseline id after a reboot, a contract violation) is Unknown, never a crash.
    public static func observe(senderAgeMs: Int, _ observation: ReceiverObservation, nowMonoMs: Int,
                               currentBaselineId: String,
                               policy: FreshnessPolicy = .proposal) throws(FreshnessInputError)
        -> (freshness: Freshness, ageMs: Int?) {
        var baselineValid = observation.processBaselineId == currentBaselineId
        var since = nowMonoMs - observation.acceptedAtMonoMs
        if since < 0 { (baselineValid, since) = (false, 0) }
        let age = try chainedAgeMs(senderAgeMs: senderAgeMs, sinceAcceptMs: baselineValid ? since : 0,
                                   transitBounded: observation.transitBounded, transitMs: observation.transitMs,
                                   baselineValid: baselineValid)
        return (policy.classify(ageMs: age), age)
    }

    private static func duration(_ name: String, _ value: Int) throws(FreshnessInputError) -> Int {
        guard value >= 0 else { throw .negativeAge("\(name) = \(value)") }
        return value
    }
}
