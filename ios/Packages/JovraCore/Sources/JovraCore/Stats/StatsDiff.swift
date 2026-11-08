import Foundation

/// One stat whose fraction or count a correction changed: the stats half of the "Recalculated" indicator
/// (`ScoringEngine.diff(before:after:)` lists the points, games, sets and result).
public struct StatChange: Equatable, Sendable {
    public let key: StatKey
    /// Nil when the line does not exist on that side of the edit (a doubles server who no longer serves).
    public let before: StatValue?
    public let after: StatValue?
}

extension StatsEngine {
    /// Lists, in stats.csv order, only the stats whose numerator, denominator or count differs between two folds.
    /// Evidence alone (a corrected point's new id, a provenance change) is not a changed number and is not listed.
    public static func diff(before: MatchTimeline, after: MatchTimeline) throws -> [StatChange] {
        let old = try compute(before), new = try compute(after)
        var keys = try catalogue(old)
        for key in try catalogue(new) where !keys.contains(key) { keys.append(key) }
        return try keys.compactMap { key in
            let a = try value(key, old), b = try value(key, new)
            return same(a, b) ? nil : StatChange(key: key, before: a, after: b)
        }
    }

    private static func same(_ lhs: StatValue?, _ rhs: StatValue?) -> Bool {
        switch (lhs, rhs) {
        case (.ratio(let a)?, .ratio(let b)?): return a.n == b.n && a.d == b.d
        default: return lhs == rhs
        }
    }
}
