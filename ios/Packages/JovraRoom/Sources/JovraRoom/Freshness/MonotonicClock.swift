import Foundation

/// A monotonic millisecond clock owned by the receiving device. It must keep counting while the device sleeps: a
/// clock that pauses in sleep (`mach_absolute_time`, `SuspendingClock`) would under-state every age measured across a
/// sleep and show a silent camera as Fresh.
public protocol MonotonicClock: Sendable {
    /// Milliseconds on this clock's own timeline. Only differences between two readings of the same clock mean
    /// anything; a reading is never compared with another device's clock or a wall clock.
    func nowMs() -> Int
}

/// Production clock: Swift's `ContinuousClock` (`mach_continuous_time` on Apple platforms, `CLOCK_BOOTTIME` on
/// Linux), which keeps counting during sleep. Readings are relative to one process-wide origin, so every instance in
/// a process shares a timeline and a restart starts a new one (paired with a new `ProcessBaseline`).
public struct ContinuousMonotonicClock: MonotonicClock {
    private static let origin = ContinuousClock.now

    public init() {}

    public func nowMs() -> Int {
        let elapsed = ContinuousClock.now - Self.origin
        let (seconds, attoseconds) = elapsed.components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}

/// The receiver's process baseline id: it changes on every process start, and therefore on every reboot, so an
/// acceptance observed by an earlier process (or before a reboot) never counts as a valid baseline.
public enum ProcessBaseline {
    /// A fresh random id for this process, valid as a room `id` (letters, digits and '-').
    public static let current: String = "pb-" + UUID().uuidString.lowercased()
}

/// Receiver-owned freshness on an injected monotonic clock: stamps each accepted payload with this process's
/// baseline and clock reading, and reads ages back against the same clock. Inject a fake clock in tests;
/// production uses `ContinuousMonotonicClock` and `ProcessBaseline.current`.
public struct FreshnessClock<Clock: MonotonicClock>: Sendable {
    public let clock: Clock
    public let baselineId: String
    public let policy: FreshnessPolicy

    public init(clock: Clock, baselineId: String, policy: FreshnessPolicy = .proposal) {
        self.clock = clock
        self.baselineId = baselineId
        self.policy = policy
    }

    /// The observation to store with a payload accepted now. `transitMs` is the transport-observed bound, or nil when
    /// the delivery was queued and transit cannot be bounded.
    public func accept(transitMs: Int?) -> ReceiverObservation {
        ReceiverObservation(transitBounded: transitMs != nil, transitMs: transitMs, processBaselineId: baselineId,
                            acceptedAtMonoMs: clock.nowMs())
    }

    /// A sender age read now against a stored observation.
    public func read(senderAgeMs: Int, _ observation: ReceiverObservation) throws(FreshnessInputError)
        -> (freshness: Freshness, ageMs: Int?) {
        try FreshnessRule.observe(senderAgeMs: senderAgeMs, observation, nowMonoMs: clock.nowMs(),
                                  currentBaselineId: baselineId, policy: policy)
    }
}

extension FreshnessClock where Clock == ContinuousMonotonicClock {
    /// The production receiver: the continuous clock and this process's baseline.
    public static var live: FreshnessClock {
        FreshnessClock(clock: ContinuousMonotonicClock(), baselineId: ProcessBaseline.current)
    }
}
