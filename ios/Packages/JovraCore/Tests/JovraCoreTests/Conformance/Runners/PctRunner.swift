// fixture-kind: jovra.fixture.pct
import Foundation
import Testing
@testable import JovraCore
struct PctRunner: FixtureRunner {
    let kind = "jovra.fixture.pct"
    private struct Fixture: Decodable { var cases: [Case] }
    private struct Case: Decodable {
        var op: String
        var n: Int?, d: Int?, current: [Int]?, prior: [Int]?, parts: [[Int]]?
        var expected: Expectation
    }
    private struct Expectation: Decodable { var n: Int?, d: Int?, pct: Int?, display: String?, text: String? }
    func run(_ data: Data, path: URL) throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        for c in fixture.cases {
            switch c.op {
            case "ratio":
                let ratio = try Percent.ratio(n: #require(c.n), d: #require(c.d))
                #expect(ratio.n == c.expected.n && ratio.d == c.expected.d && ratio.pct.value == c.expected.pct && ratio.display == c.expected.display)
            case "delta":
                let a = try #require(c.current), b = try #require(c.prior)
                #expect(try Percent.delta(current: Percent.ratio(n: a[0], d: a[1]), prior: Percent.ratio(n: b[0], d: b[1])) == c.expected.text)
            case "pool":
                let ratio = try Percent.pool(#require(c.parts).map { (n: $0[0], d: $0[1]) })
                #expect(ratio.n == c.expected.n && ratio.d == c.expected.d && ratio.pct.value == c.expected.pct && ratio.display == c.expected.display)
            default: Issue.record("Unknown pct operation \(c.op)")
            }
        }
        print("pct vectors: \(fixture.cases.count)")
    }
}
