// fixture-kind: jovra.fixture.trend
import Foundation
import Testing
import JovraCore

struct TrendFixture: Decodable {
    let id: String
    let defaultMinimums: TrendMinimums
    let cases: [Case]
    struct Case: Decodable {
        let name: String
        let input: Input
        let assertions: [Assertion]
        let expected: TrendSeries
    }
    struct Input: Decodable {
        let range: TrendRange
        let asOf: CalendarDay
        let comparableKind: String
        let scope: TrendScope
        let minimums: TrendMinimums?
        let sessions: [TrendSession]
    }
    struct Assertion: Decodable { let path: String }
}

struct TrendRunner: FixtureRunner {
    let kind = "jovra.fixture.trend"
    func run(_ data: Data, path: URL) throws {
        let fixture = try JSONDecoder().decode(TrendFixture.self, from: data)
        #expect(fixture.defaultMinimums == .standard, "Swift TrendMinimums.standard must equal the reference minimums")
        for c in fixture.cases {
            let i = c.input
            let actual = try TrendPool.bucketed(i.sessions, range: i.range, asOf: i.asOf, comparableKind: i.comparableKind,
                                                scope: i.scope, minimums: i.minimums ?? .standard)
            #expect(actual == c.expected, "\(fixture.id) \(c.name)")
        }
        print("trend cases: \(fixture.cases.count) (\(fixture.cases.reduce(0) { $0 + $1.assertions.count }) hand assertions)")
    }
}
