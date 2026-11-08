import Foundation

/// Composition rows (Deep / Short / Out and similar shares of one whole). Each row is rounded on its own with the
/// shared half-up rule, so the rounded rows may sum to 99 or 101; `sumsTo100` tells the UI to say so (story 229)
/// rather than nudging a row to force 100.
public struct Composition: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let label: String
        public let ratio: RateRatio
    }
    public let rows: [Row]
    /// The shared denominator: the number of observations the rows split.
    public let total: Int
    /// Sum of the displayed integers; nil when there is nothing to split.
    public let roundedSum: Int?
    public var sumsTo100: Bool { roundedSum == 100 }

    public init(_ counts: [(label: String, count: Int)]) throws {
        var total = 0
        for part in counts {
            guard part.count >= 0 else { throw PercentError.invalidFraction }
            let next = total.addingReportingOverflow(part.count)
            guard !next.overflow else { throw PercentError.overflow }
            total = next.partialValue
        }
        let rows = try counts.map { Row(label: $0.label, ratio: try Percent.ratio(n: $0.count, d: total)) }
        self.rows = rows; self.total = total
        roundedSum = total == 0 ? nil : rows.reduce(0) { $0 + ($1.ratio.pct.value ?? 0) }
    }
}
