/// The one integer rounding rule used on both platforms (ADR-0011).
public enum Percent {
    public static func pct(n: Int, d: Int) throws -> Int? {
        guard n >= 0, d >= 0, n <= d else { throw PercentError.invalidFraction }
        guard d != 0 else { return nil }
        // Full-width multiplication keeps even Int.max/Int.max exact without overflowing.
        let scaled = UInt(n).multipliedFullWidth(by: 100)
        let divided = UInt(d).dividingFullWidth(scaled)
        let halfUp = UInt(d / 2 + d % 2)
        return Int(divided.quotient + (divided.remainder >= halfUp ? 1 : 0))
    }
    public static func ratio(n: Int, d: Int) throws -> RateRatio {
        let value = try pct(n: n, d: d)
        return RateRatio(n: n, d: d, pct: ContractNullable(value), display: value.map { "\($0)%" } ?? "—")
    }
    public static func pool(_ parts: [(n: Int, d: Int)]) throws -> RateRatio {
        var n = 0, d = 0
        for part in parts {
            _ = try pct(n: part.n, d: part.d)
            let numerator = n.addingReportingOverflow(part.n), denominator = d.addingReportingOverflow(part.d)
            guard !numerator.overflow, !denominator.overflow else { throw PercentError.overflow }
            n = numerator.partialValue; d = denominator.partialValue
        }
        return try ratio(n: n, d: d)
    }
    public static func delta(current: RateRatio, prior: RateRatio) -> String {
        guard let now = current.pct.value, let before = prior.pct.value else { return "—" }
        let delta = now - before
        let unit = abs(delta) == 1 ? "percentage point" : "percentage points"
        return "\(delta > 0 ? "+" : "")\(delta) \(unit)"
    }
}
public enum PercentError: Error, Equatable, Sendable { case invalidFraction, overflow }
