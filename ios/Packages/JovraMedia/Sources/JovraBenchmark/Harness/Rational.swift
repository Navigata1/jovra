import Foundation

public struct RationalOverflow: Error, Equatable {}

/// An exact fraction in lowest terms with a positive denominator. Metrics and verdicts are computed with it
/// so Swift and the Python reference (`fractions.Fraction`) agree exactly; arithmetic throws rather than
/// wrapping when a result does not fit in 64 bits, and comparisons use full-width products so they never
/// overflow.
public struct Rational: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let numerator: Int64
    public let denominator: Int64

    public init(_ numerator: Int64, _ denominator: Int64 = 1) {
        precondition(denominator != 0, "Rational needs a non-zero denominator")
        let sign: Int64 = denominator < 0 ? -1 : 1
        let divisor = Swift.max(Rational.gcd(numerator, denominator), 1)
        self.numerator = sign * numerator / divisor
        self.denominator = sign * denominator / divisor
    }

    public init(_ time: RationalTime) {
        self.init(time.value, time.timescale)
    }

    /// An exact decimal such as "0.95" or "10".
    public init?(decimal text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              parts.last!.count <= 18 else { return nil }
        let places = parts.count == 2 ? parts[1].count : 0
        guard let digits = Int64(parts.joined()) else { return nil }
        var scale: Int64 = 1
        for _ in 0..<places { scale *= 10 }
        self.init(digits, scale)
    }

    static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var (x, y) = (a.magnitude, b.magnitude)
        while y != 0 { (x, y) = (y, x % y) }
        return Int64(x)
    }

    public static let zero = Rational(0)

    public var magnitude: Rational { Rational(Swift.abs(numerator), denominator) }

    public func adding(_ other: Rational) throws -> Rational {
        let g = Rational.gcd(denominator, other.denominator)
        let (a, o1) = numerator.multipliedReportingOverflow(by: other.denominator / g)
        let (b, o2) = other.numerator.multipliedReportingOverflow(by: denominator / g)
        let (n, o3) = a.addingReportingOverflow(b)
        let (d, o4) = denominator.multipliedReportingOverflow(by: other.denominator / g)
        guard !(o1 || o2 || o3 || o4) else { throw RationalOverflow() }
        return Rational(n, d)
    }

    public func subtracting(_ other: Rational) throws -> Rational {
        try adding(Rational(-other.numerator, other.denominator))
    }

    public func multiplied(by other: Rational) throws -> Rational {
        let g1 = Rational.gcd(numerator, other.denominator), g2 = Rational.gcd(other.numerator, denominator)
        let (n, o1) = (numerator / Swift.max(g1, 1)).multipliedReportingOverflow(by: other.numerator / Swift.max(g2, 1))
        let (d, o2) = (denominator / Swift.max(g2, 1)).multipliedReportingOverflow(by: other.denominator / Swift.max(g1, 1))
        guard !(o1 || o2) else { throw RationalOverflow() }
        return Rational(n, d)
    }

    public func divided(by other: Rational) throws -> Rational {
        precondition(other.numerator != 0, "division by zero")
        return try multiplied(by: Rational(other.denominator, other.numerator))
    }

    public static func < (lhs: Rational, rhs: Rational) -> Bool {
        let left = lhs.numerator.multipliedFullWidth(by: rhs.denominator)
        let right = rhs.numerator.multipliedFullWidth(by: lhs.denominator)
        return (left.high, left.low) < (right.high, right.low)
    }

    /// Rounded half-up to `places` decimals (non-negative values), e.g. 2/3 at 4 places is "0.6667".
    public func decimalString(places: Int) throws -> String {
        precondition(numerator >= 0, "decimalString is defined for non-negative values")
        var scale: Int64 = 1
        for _ in 0..<places { scale *= 10 }
        let (scaled, o1) = numerator.multipliedReportingOverflow(by: scale * 2)
        let (twice, o2) = denominator.multipliedReportingOverflow(by: 2)
        guard !(o1 || o2) else { throw RationalOverflow() }
        let rounded = (scaled + denominator) / twice
        let whole = rounded / scale, fraction = rounded % scale
        guard places > 0 else { return "\(whole)" }
        let digits = String(fraction)
        return "\(whole)." + String(repeating: "0", count: places - digits.count) + digits
    }

    public var description: String { denominator == 1 ? "\(numerator)" : "\(numerator)/\(denominator)" }
}
