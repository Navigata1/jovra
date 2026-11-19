import Foundation

/// Matching tolerances of the `labelScoring` task. A person labels to the frame, so the defaults are wider
/// than the 50 ms of synthetic onsets: 100 ms (three frames at 30 fps) for hits and bounces, 1 s for rally
/// boundaries (the V05 gate).
public struct LabelScoringTolerances: Codable, Hashable, Sendable {
    public let hit: RationalTime
    public let bounce: RationalTime
    public let rallyBoundary: RationalTime

    public init(hit: RationalTime, bounce: RationalTime, rallyBoundary: RationalTime) {
        self.hit = hit
        self.bounce = bounce
        self.rallyBoundary = rallyBoundary
    }

    public static let standard = LabelScoringTolerances(hit: RationalTime(value: 100, timescale: 1000),
                                                        bounce: RationalTime(value: 100, timescale: 1000),
                                                        rallyBoundary: RationalTime(value: 1, timescale: 1))
}

/// One printed metric. `value` is the text shown (nil when undefined, 0/0). `exact` is `.some` for exact
/// rational metrics (its payload nil when undefined) and absent for counts and pixel distances.
public struct LabelScoreRow: Codable, Hashable, Sendable {
    public let group: String
    public let name: String
    public let unit: String?
    public let value: String?
    public let exact: Rational??

    init(group: String, name: String, unit: String? = nil, value: String?, exact: Rational?? = .none) {
        self.group = group
        self.name = name
        self.unit = unit
        self.value = value
        self.exact = exact
    }

    enum CodingKeys: String, CodingKey { case group, name, unit, value, exact }
    enum FractionKeys: String, CodingKey { case n, d }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        group = try c.decode(String.self, forKey: .group)
        name = try c.decode(String.self, forKey: .name)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        value = try c.decodeIfPresent(String.self, forKey: .value)
        if !c.contains(.exact) {
            exact = .none
        } else if try c.decodeNil(forKey: .exact) {
            exact = .some(nil)
        } else {
            let f = try c.nestedContainer(keyedBy: FractionKeys.self, forKey: .exact)
            let d = try f.decode(Int64.self, forKey: .d)
            guard d > 0 else {
                throw DecodingError.dataCorruptedError(forKey: .d, in: f, debugDescription: "fraction denominator must be positive, got \(d)")
            }
            exact = .some(Rational(try f.decode(Int64.self, forKey: .n), d))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(group, forKey: .group)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encode(value, forKey: .value)
        guard let exact else { return }
        if let exact {
            var f = c.nestedContainer(keyedBy: FractionKeys.self, forKey: .exact)
            try f.encode(exact.numerator, forKey: .n)
            try f.encode(exact.denominator, forKey: .d)
        } else {
            try c.encodeNil(forKey: .exact)
        }
    }
}

/// The scorer's result: the tuning windows and the held-out windows, each with its own rows. There is no
/// combined number: a gate reads held-out rows only (ADR-0004).
public struct LabelScoreReport: Codable, Hashable, Sendable {
    public struct SplitResult: Codable, Hashable, Sendable {
        public let windows: Int
        public let durationMs: Int
        public let rows: [LabelScoreRow]
    }

    public let tuning: SplitResult
    public let heldOut: SplitResult

    public func row(_ split: GroundTruth.Split, group: String, name: String) -> LabelScoreRow? {
        (split == .tuning ? tuning : heldOut).rows.first { $0.group == group && $0.name == name }
    }

    /// The printed table: one line per metric, tuning beside held-out.
    public func text() -> String {
        func seconds(_ ms: Int) -> String { ms % 1000 == 0 ? "\(ms / 1000) s" : "\(Double(ms) / 1000) s" }
        func pad(_ text: String, _ width: Int) -> String { text + String(repeating: " ", count: max(width - text.count, 1)) }
        func shown(_ row: LabelScoreRow?) -> String {
            guard let row else { return "" }
            guard let value = row.value else { return "undefined" }
            return row.unit.map { "\(value) \($0)" } ?? value
        }
        var lines = [pad("", 18) + pad("", 52) + pad("tuning", 16) + "held-out",
                     pad("windows", 18) + pad("", 52) + pad("\(tuning.windows) (\(seconds(tuning.durationMs)))", 16)
                        + "\(heldOut.windows) (\(seconds(heldOut.durationMs)))"]
        var previousGroup = ""
        for row in tuning.rows {
            let other = heldOut.rows.first { $0.group == row.group && $0.name == row.name }
            lines.append(pad(row.group == previousGroup ? "" : row.group, 18) + pad(row.name, 52) + pad(shown(row), 16) + shown(other))
            previousGroup = row.group
        }
        if heldOut.windows == 0 {
            lines.append("No held-out window: this recording is one window long and cannot gate a capability.")
        }
        return lines.joined(separator: "\n")
    }
}
