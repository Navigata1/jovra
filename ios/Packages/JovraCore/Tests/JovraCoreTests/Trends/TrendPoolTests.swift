import Foundation
import Testing
import JovraCore

@Test func calendarDaysRejectImpossibleDatesAndCrossYearAndLeapBoundaries() throws {
    for invalid in ["2026-02-29", "2026-13-01", "2026-1-01", "20261006", "2026-10-06T00:00", "２０２６-10-06"] {
        #expect(throws: CalendarDayError.invalid) { try CalendarDay(invalid) }
    }
    #expect(try CalendarDay("2028-02-28").adding(days: 1).description == "2028-02-29")
    #expect(try CalendarDay("2026-01-03").adding(days: -7).description == "2025-12-27")
    let bounds = TrendPool.bucketBounds(.year, asOf: try CalendarDay("2026-03-15"))
    #expect(bounds.count == 12)
    #expect(bounds[0].from.description == "2025-04-01")
    #expect(bounds[10].from.description == "2026-02-01" && bounds[10].to.description == "2026-02-28")
    #expect(bounds[11].to.description == "2026-03-15")
}

@Test func trendRefusesAnImpossibleFractionInsteadOfPoolingIt() throws {
    let bad = TrendSession(id: "x", date: try CalendarDay("2026-10-01"), comparableKind: "singlesMatch", sample: false, n: 5, d: 4)
    #expect(throws: PercentError.invalidFraction) {
        try TrendPool.bucketed([bad], range: .fourWeeks, asOf: try CalendarDay("2026-10-06"), comparableKind: "singlesMatch")
    }
}

@Test func zeroDenominatorSessionsNeverShowAFakeZeroPercent() throws {
    let day = try CalendarDay("2026-10-05")
    let empty = TrendSession(id: "e", date: day, comparableKind: "singlesMatch", sample: false, n: 0, d: 0)
    let series = try TrendPool.bucketed([empty], range: .fourWeeks, asOf: try CalendarDay("2026-10-06"), comparableKind: "singlesMatch")
    #expect(series.buckets[3].ratio.display == "—")
    #expect(series.buckets[3].ratio.pct == .null)
    #expect(series.buckets[3].hidden)
    #expect(series.state == .tooFewComparable)
}
