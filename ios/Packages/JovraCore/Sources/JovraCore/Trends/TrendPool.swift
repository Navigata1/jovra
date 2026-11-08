import Foundation

/// The progress window a trend covers (glossary: Progress window). Weeks for 4 weeks, months for 3 months and Year.
public enum TrendRange: String, Codable, CaseIterable, Sendable {
    case fourWeeks = "4W", threeMonths = "3M", year = "Year"
}

/// Real trends never include sample sessions, and a sample (demo) trend uses only sample sessions.
public enum TrendScope: String, Codable, CaseIterable, Sendable { case real, sample }

/// The minimum samples below which a bucket is hidden and a comparison is not drawn (screens S16).
/// One constants type so tuning on hardware is a one-line change; it must equal the reference `trend.MINIMUMS`.
public struct TrendMinimums: Codable, Equatable, Sendable {
    public var bucketDenominator: Int
    public var pooledDenominator: Int
    public var bucketsWithData: Int
    public init(bucketDenominator: Int, pooledDenominator: Int, bucketsWithData: Int) {
        self.bucketDenominator = bucketDenominator; self.pooledDenominator = pooledDenominator
        self.bucketsWithData = bucketsWithData
    }
    public static let standard = TrendMinimums(bucketDenominator: 20, pooledDenominator: 100, bucketsWithData: 2)
}

/// One session's contribution to a trend: the stat's numerator and denominator in that session.
public struct TrendSession: Codable, Equatable, Sendable {
    public var id: String
    public var date: CalendarDay
    /// Opaque key for comparable sessions, such as "singlesMatch". Only equal keys are pooled together.
    public var comparableKind: String
    public var sample: Bool
    public var n: Int
    public var d: Int
    public init(id: String, date: CalendarDay, comparableKind: String, sample: Bool, n: Int, d: Int) {
        self.id = id; self.date = date; self.comparableKind = comparableKind; self.sample = sample; self.n = n; self.d = d
    }
}

public struct TrendBucket: Codable, Equatable, Sendable {
    public var index: Int
    public var from: CalendarDay
    public var to: CalendarDay
    public var sessionIds: [String]
    /// The pooled fraction. A hidden bucket keeps it for the table fallback but never feeds the headline.
    public var ratio: RateRatio
    public var hidden: Bool
}

public struct TrendHeadline: Codable, Equatable, Sendable {
    public var currentIndex: Int
    public var priorIndex: Int
    public var current: RateRatio
    public var prior: RateRatio
    /// Percentage points, from the two displayed integers.
    public var deltaPoints: Int
    /// en-US canonical text ("+4 percentage points"); the UI localizes from `deltaPoints`.
    public var deltaText: String
}

public struct TrendExclusions: Codable, Equatable, Sendable {
    public var otherScope: Int
    public var otherKind: Int
    public var outsideWindow: Int
}

public enum TrendState: String, Codable, Sendable { case ok, tooFewComparable, noData }

public struct TrendSeries: Codable, Equatable, Sendable {
    public var state: TrendState
    public var buckets: [TrendBucket]
    public var pooled: RateRatio
    public var sessionCount: Int
    public var excluded: TrendExclusions
    public var headline: ContractNullable<TrendHeadline>
}

/// Pooled cross-session aggregation (rules §6.10). Percentages are never averaged: each bucket sums the numerators
/// and denominators of its comparable sessions, and deltas are taken from displayed integers (rules §7 rule 4).
public enum TrendPool {
    public static func bucketed(_ sessions: [TrendSession], range: TrendRange, asOf: CalendarDay,
                                comparableKind: String, scope: TrendScope = .real,
                                minimums: TrendMinimums = .standard) throws -> TrendSeries {
        let bounds = bucketBounds(range, asOf: asOf)
        let windowStart = bounds[0].from
        var excluded = TrendExclusions(otherScope: 0, otherKind: 0, outsideWindow: 0)
        var used: [TrendSession] = []
        for session in sessions.sorted(by: { ($0.date, $0.id) < ($1.date, $1.id) }) {
            _ = try Percent.ratio(n: session.n, d: session.d) // domain check: 0 <= n <= d
            if session.sample != (scope == .sample) { excluded.otherScope += 1 }
            else if session.comparableKind != comparableKind { excluded.otherKind += 1 }
            else if session.date < windowStart || asOf < session.date { excluded.outsideWindow += 1 }
            else { used.append(session) }
        }
        let buckets = try bounds.enumerated().map { index, bound in
            let inside = used.filter { bound.from <= $0.date && $0.date <= bound.to }
            let ratio = try Percent.pool(inside.map { (n: $0.n, d: $0.d) })
            return TrendBucket(index: index, from: bound.from, to: bound.to, sessionIds: inside.map(\.id),
                               ratio: ratio, hidden: ratio.d < minimums.bucketDenominator)
        }
        let pooled = try Percent.pool(buckets.map { (n: $0.ratio.n, d: $0.ratio.d) })
        let shown = buckets.filter { !$0.hidden }
        let comparable = shown.count >= max(2, minimums.bucketsWithData) && pooled.d >= minimums.pooledDenominator
        var headline: TrendHeadline?
        if comparable, let current = shown.last, let now = current.ratio.pct.value {
            let prior = shown[shown.count - 2]
            // A shown bucket has a positive denominator, so both displayed integers exist.
            let before = prior.ratio.pct.value ?? now
            headline = TrendHeadline(currentIndex: current.index, priorIndex: prior.index, current: current.ratio,
                                     prior: prior.ratio, deltaPoints: now - before,
                                     deltaText: Percent.delta(current: current.ratio, prior: prior.ratio))
        }
        let state: TrendState = used.isEmpty ? .noData : (comparable ? .ok : .tooFewComparable)
        return TrendSeries(state: state, buckets: buckets, pooled: pooled, sessionCount: used.count,
                           excluded: excluded, headline: .init(headline))
    }

    /// Inclusive bucket bounds, oldest first; the last bucket ends on `asOf`.
    public static func bucketBounds(_ range: TrendRange, asOf: CalendarDay) -> [(from: CalendarDay, to: CalendarDay)] {
        switch range {
        case .fourWeeks:
            return (0..<4).map { i in (asOf.adding(days: -(7 * (4 - i) - 1)), asOf.adding(days: -7 * (3 - i))) }
        case .threeMonths, .year:
            let count = range == .year ? 12 : 3
            return (0..<count).reversed().map { back in
                (asOf.monthStart(back: back), back == 0 ? asOf : asOf.monthStart(back: back - 1).adding(days: -1))
            }
        }
    }
}
