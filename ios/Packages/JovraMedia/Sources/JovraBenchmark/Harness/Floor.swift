import Foundation

/// The minimum a gating run must reach. Analysis tickets define their floors from the research gates in
/// `spec/contracts/capability-registry.v1.json`; a run below its floor fails and keeps the capability
/// `disabled` (ADR-0004).
public struct Floor: Codable, Hashable, Sendable {
    public enum Comparator: String, Codable, Hashable, Sendable {
        case atLeast = ">="
        case atMost = "<="
    }

    public struct Metric: Codable, Hashable, Sendable {
        public let name: String
        public let comparator: Comparator
        /// An exact decimal, e.g. "0.95".
        public let threshold: String
        public let unit: String?

        public init(name: String, comparator: Comparator, threshold: String, unit: String? = nil) {
            precondition(Rational(decimal: threshold) != nil, "threshold must be a decimal string")
            self.name = name
            self.comparator = comparator
            self.threshold = threshold
            self.unit = unit
        }
    }

    public let source: String
    public let metrics: [Metric]

    public init(source: String, metrics: [Metric]) {
        self.source = source
        self.metrics = metrics
    }

    /// The harness self-test floor. It uses the values of the audio.hitDetection research gate so the oracle
    /// and null runs exercise a realistic floor; it is not that capability's gate and promotes nothing.
    public static let harnessSelfTest = Floor(
        source: "harness self-test (values of the audio.hitDetection gate; promotes nothing)",
        metrics: [
            Metric(name: "precision", comparator: .atLeast, threshold: "0.95"),
            Metric(name: "recall", comparator: .atLeast, threshold: "0.90"),
            Metric(name: "onset MAE", comparator: .atMost, threshold: "10", unit: "ms"),
        ]
    )

    public static let builtIn: [String: Floor] = ["harnessSelfTest": harnessSelfTest]

    /// Applies the floor to exact metric values. An undefined or missing metric fails.
    public func verdict(for metrics: [MetricResult]) -> Verdict {
        let checks = self.metrics.map { floorMetric -> Verdict.Check in
            let metric = metrics.first { $0.name == floorMetric.name }
            let threshold = Rational(decimal: floorMetric.threshold)!
            let passed: Bool
            if let exact = metric?.exact {
                passed = floorMetric.comparator == .atLeast ? exact >= threshold : exact <= threshold
            } else {
                passed = false
            }
            return Verdict.Check(name: floorMetric.name, comparator: floorMetric.comparator,
                                 threshold: floorMetric.threshold, unit: floorMetric.unit,
                                 value: metric?.value, passed: passed)
        }
        return Verdict(passed: checks.allSatisfy(\.passed), checks: checks)
    }
}

public struct Verdict: Codable, Hashable, Sendable {
    public struct Check: Codable, Hashable, Sendable {
        public let name: String
        public let comparator: Floor.Comparator
        public let threshold: String
        public let unit: String?
        public let value: String?
        public let passed: Bool

        enum CodingKeys: String, CodingKey { case name, comparator, threshold, unit, value, passed }

        public init(name: String, comparator: Floor.Comparator, threshold: String, unit: String?, value: String?, passed: Bool) {
            self.name = name
            self.comparator = comparator
            self.threshold = threshold
            self.unit = unit
            self.value = value
            self.passed = passed
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(comparator, forKey: .comparator)
            try c.encode(threshold, forKey: .threshold)
            try c.encodeIfPresent(unit, forKey: .unit)
            try c.encode(value, forKey: .value)   // explicit null when undefined
            try c.encode(passed, forKey: .passed)
        }
    }

    public let passed: Bool
    public let checks: [Check]
}
