// fixture-kind: jovra.fixture.units
import Foundation
import Testing
@testable import JovraCore
struct UnitsRunner: FixtureRunner {
    let kind = "jovra.fixture.units"
    private struct Fixture: Decodable { var cases: [Case] }
    private struct Case: Decodable {
        var op: String, value: String?, from: String?, to: String?, places: Int?
        var unit: String?, preferredUnit: String?, label: String?
        var expected: Expectation
    }
    private struct Expectation: Codable {
        var value: String?, unit: String?, converted: Bool?, label: String?, known: Bool?, ranges: [GaugeRange]?
    }
    func run(_ data: Data, path: URL) throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        for c in fixture.cases {
            switch c.op {
            case "convert":
                #expect(try Units.convert(#require(c.value), from: #require(c.from), to: #require(c.to), places: #require(c.places)) == c.expected.value)
            case "display":
                let result = try Units.display(#require(c.value), unit: #require(c.unit), preferredUnit: #require(c.preferredUnit))
                #expect(result.value == c.expected.value && result.unit == c.expected.unit && result.converted == c.expected.converted)
            case "gaugeHint":
                let result = Units.gaugeHint(try #require(c.label))
                #expect(result.label == c.expected.label && result.known == c.expected.known && result.ranges == c.expected.ranges)
            default: Issue.record("Unknown units operation \(c.op)")
            }
        }
        print("units vectors: \(fixture.cases.count)")
    }
}
