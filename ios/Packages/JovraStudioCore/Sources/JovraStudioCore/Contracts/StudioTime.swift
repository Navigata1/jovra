import Foundation

/// Studio time (spec SD7): session (match) time is integer microseconds; source time is an exact rational; the one
/// time-to-frame rule rounds half up, `frame = floor(t * fps + 1/2)`, in exact integer arithmetic. No binary floating
/// point reaches a time or frame decision (`spec/reference/studio/core.py`, section "time").
public enum StudioTime {
    public static let microsecondsPerSecond = 1_000_000

    public enum TimeError: Error, Equatable {
        case zeroDenominator
        case overflow
    }

    /// `floor(num / den + 1/2)` exactly, for any sign of `num` and `den != 0`. The one half-up rule; the core
    /// percentage (`Percent.pct`) is this rule applied to `100 n / d`.
    public static func roundHalfUp(_ num: Int, over den: Int) throws -> Int {
        guard den != 0 else { throw TimeError.zeroDenominator }
        // floor((2 num + den) / (2 den)), with the sign moved into the numerator first.
        let (n, d) = den < 0 ? (try negate(num), try negate(den)) : (num, den)
        let twice = n.multipliedReportingOverflow(by: 2), twiceDen = d.multipliedReportingOverflow(by: 2)
        guard !twice.overflow, !twiceDen.overflow else { throw TimeError.overflow }
        let top = twice.partialValue.addingReportingOverflow(d)
        guard !top.overflow else { throw TimeError.overflow }
        return floorDivide(top.partialValue, twiceDen.partialValue)
    }

    /// The frame shown at session-relative time `timeUs` (microseconds, an exact rational) on a constant-rate clock.
    public static func frame(atMicroseconds timeUs: StudioExactRational, fps: StudioFrameRate) throws -> Int {
        // t[µs] * num / (den * 1e6)
        let scaled = try timeUs.multiplied(by: StudioExactRational(fps.num, fps.den * microsecondsPerSecond))
        return try roundHalfUp(scaled.numerator, over: scaled.denominator)
    }

    /// The exact start time of frame `frame`, in microseconds.
    public static func frameStartMicroseconds(_ frame: Int, fps: StudioFrameRate) throws -> StudioExactRational {
        try StudioExactRational(frame, 1).multiplied(by: frameDurationMicroseconds(fps))
    }

    /// The exact duration of one frame, in microseconds: 1e6 * den / num.
    public static func frameDurationMicroseconds(_ fps: StudioFrameRate) throws -> StudioExactRational {
        try StudioExactRational(microsecondsPerSecond * fps.den, fps.num)
    }

    /// A rational media time (`value / timescale` seconds) in exact microseconds.
    public static func microseconds(_ time: StudioRationalTime) throws -> StudioExactRational {
        try StudioExactRational(time.value, time.timescale).multiplied(by: StudioExactRational(microsecondsPerSecond, 1))
    }

    private static func negate(_ x: Int) throws -> Int {
        guard x != .min else { throw TimeError.overflow }
        return -x
    }

    private static func floorDivide(_ a: Int, _ b: Int) -> Int {
        let q = a / b, r = a % b
        return (r != 0 && (r < 0) != (b < 0)) ? q - 1 : q
    }
}

/// An exact rational in lowest terms with a positive denominator.
public struct StudioExactRational: Hashable, Sendable, CustomStringConvertible {
    public let numerator: Int
    public let denominator: Int

    public init(_ numerator: Int, _ denominator: Int) throws {
        guard denominator != 0 else { throw StudioTime.TimeError.zeroDenominator }
        guard numerator != .min, denominator != .min else { throw StudioTime.TimeError.overflow }
        let sign = denominator < 0 ? -1 : 1
        let g = Self.gcd(abs(numerator), abs(denominator))
        self.numerator = sign * numerator / g
        self.denominator = sign * denominator / g
    }

    public func multiplied(by other: StudioExactRational) throws -> StudioExactRational {
        // Cross-reduce first so exact products of real clock values stay inside Int.
        let g1 = Self.gcd(abs(numerator), other.denominator), g2 = Self.gcd(abs(other.numerator), denominator)
        let n = (numerator / g1).multipliedReportingOverflow(by: other.numerator / g2)
        let d = (denominator / g2).multipliedReportingOverflow(by: other.denominator / g1)
        guard !n.overflow, !d.overflow else { throw StudioTime.TimeError.overflow }
        return try StudioExactRational(n.partialValue, d.partialValue)
    }

    public var description: String { denominator == 1 ? "\(numerator)" : "\(numerator)/\(denominator)" }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var (a, b) = (a, b)
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }
}
