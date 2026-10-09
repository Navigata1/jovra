import Testing
@testable import JovraCore

@Test func percentagesUseHalfUpAndPoolCounts() throws {
    #expect(try Percent.pct(n: 1, d: 8) == 13)
    #expect(try Percent.pct(n: 5, d: 8) == 63)
    #expect(try Percent.ratio(n: 0, d: 0).display == "—")
    let pooled = try Percent.pool([(n: 1, d: 2), (n: 30, d: 40)])
    #expect(pooled.n == 31 && pooled.d == 42 && pooled.pct.value == 74)
    #expect(try Percent.delta(current: Percent.ratio(n: 7, d: 10), prior: Percent.ratio(n: 2, d: 3)) == "+3 percentage points")
}
