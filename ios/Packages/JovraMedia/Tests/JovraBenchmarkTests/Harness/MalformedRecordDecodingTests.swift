import Foundation
import JovraBenchmark
import Testing

/// Malformed committed JSON is reported as a decoding error, never a trap: a zero timescale, a zero frame
/// rate, a zero fraction denominator or a threshold that is not a plain decimal must not reach the
/// preconditions behind `RationalTime`, `Rational`, `FrameRate` or `Floor.verdict`.
@Suite("Malformed benchmark JSON throws instead of trapping")
struct MalformedRecordDecodingTests {
    static let catalog = MediaFixtureCatalog.repository()

    static func committed(_ name: String) throws -> [String: Any] {
        let url = catalog.truthDirectory.appendingPathComponent("benchmark").appendingPathComponent(name)
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    static func decode(_ object: [String: Any]) throws -> BenchmarkRecord {
        try JSONDecoder().decode(BenchmarkRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test("the committed record decodes (the cases below change one field each)")
    func committedDecodes() throws {
        _ = try Self.decode(try Self.committed("oracle.gate.json"))
    }

    @Test("a zero or negative timescale is a decoding error", arguments: [0, -1000])
    func badTimescale(timescale: Int) throws {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RationalTime.self, from: Data(#"{"value": 50, "timescale": \#(timescale)}"#.utf8))
        }
        var record = try Self.committed("oracle.gate.json")
        var task = try #require(record["task"] as? [String: Any])
        task["tolerance"] = ["value": 50, "timescale": timescale]
        record["task"] = task
        #expect(throws: DecodingError.self) { try Self.decode(record) }
    }

    @Test("a floor threshold that is not a plain decimal is a decoding error", arguments: ["1e-3", "", "0.9.1", "-1", "abc"])
    func badThreshold(threshold: String) throws {
        var record = try Self.committed("oracle.gate.json")
        var floor = try #require(record["floor"] as? [String: Any])
        var metrics = try #require(floor["metrics"] as? [[String: Any]])
        metrics[0]["threshold"] = threshold
        floor["metrics"] = metrics
        record["floor"] = floor
        #expect(throws: DecodingError.self) { try Self.decode(record) }
    }

    @Test("a metric fraction with a zero denominator is a decoding error")
    func badFraction() throws {
        var record = try Self.committed("oracle.gate.json")
        var metrics = try #require(record["metrics"] as? [[String: Any]])
        metrics[0]["exact"] = ["n": 1, "d": 0]
        record["metrics"] = metrics
        #expect(throws: DecodingError.self) { try Self.decode(record) }
    }

    @Test("a ground-truth frame rate of zero is a decoding error")
    func badFrameRate() throws {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GroundTruth.Rate.self, from: Data(#"{"num": 0, "den": 1}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GroundTruth.Rate.self, from: Data(#"{"num": 30, "den": 0}"#.utf8))
        }
    }
}
