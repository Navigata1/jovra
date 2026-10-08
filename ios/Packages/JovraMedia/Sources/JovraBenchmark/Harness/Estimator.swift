import Foundation

/// Who produced a benchmark record's outputs. Oracle and null are harness self-test estimators: they prove
/// that the floor can be passed and can be failed. Only a `candidate` record can back a capability.
public enum EstimatorRole: String, Codable, Hashable, Sendable {
    case candidate
    case oracle
    case null
}

public struct EstimatorIdentity: Codable, Hashable, Sendable {
    public let id: String
    public let methodVersion: String
    public let role: EstimatorRole

    public init(id: String, methodVersion: String, role: EstimatorRole) {
        self.id = id
        self.methodVersion = methodVersion
        self.role = role
    }
}

/// One clip handed to an estimator: its ground truth and, when rendered, its media file. Only the oracle may
/// read the truth's answers; a real estimator reads `mediaURL`.
public struct BenchmarkClip: Sendable {
    public let truth: GroundTruth
    public let mediaURL: URL?

    public init(truth: GroundTruth, mediaURL: URL?) {
        self.truth = truth
        self.mediaURL = mediaURL
    }
}

/// Anything the harness can run: analysis tickets add their estimators (hit detection, rally segmentation,
/// camera-moved detection, ...) behind this protocol and register them in `EstimatorRegistry`.
public protocol BenchmarkEstimator: Sendable {
    associatedtype Output: Codable & Sendable
    var identity: EstimatorIdentity { get }
    func estimate(_ clip: BenchmarkClip) async throws -> Output
}

/// What a record says about its task (`task` in benchmark-record.schema.json).
public struct TaskDescriptor: Codable, Hashable, Sendable {
    public let id: String
    public let version: String
    public let tolerance: RationalTime?

    public init(id: String, version: String, tolerance: RationalTime?) {
        self.id = id
        self.version = version
        self.tolerance = tolerance
    }
}

/// A scored task. The reference validator (scripts/spec/validate.py) re-scores each record with the Python
/// scorer of the same `id` and `version`, so both implementations must agree exactly.
public protocol BenchmarkTask: Sendable {
    associatedtype Output: Codable & Sendable
    var descriptor: TaskDescriptor { get }
    func truthDigest(of truth: GroundTruth) -> String
    func score(truths: [GroundTruth], outputs: [Output]) throws -> [MetricResult]
}

/// One metric of a run: the exact value (nil when undefined, e.g. 0/0) and its rounded display text.
public struct MetricResult: Codable, Hashable, Sendable {
    public let name: String
    public let unit: String?
    public let exact: Rational?
    public let value: String?

    public init(name: String, unit: String? = nil, exact: Rational?, places: Int) throws {
        self.name = name
        self.unit = unit
        self.exact = exact
        self.value = try RationalOverflow.naming("metric \(name)") { try exact?.decimalString(places: places) }
    }

    private init(name: String, unit: String?, exact: Rational?, value: String?) {
        self.name = name
        self.unit = unit
        self.exact = exact
        self.value = value
    }

    /// The same result under another name (a capability's gate name for a task metric).
    public func named(_ name: String) -> MetricResult {
        MetricResult(name: name, unit: unit, exact: exact, value: value)
    }

    enum CodingKeys: String, CodingKey { case name, unit, exact, value }
    enum FractionKeys: String, CodingKey { case n, d }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        value = try c.decodeIfPresent(String.self, forKey: .value)
        if try c.decodeNil(forKey: .exact) {
            exact = nil
        } else {
            let f = try c.nestedContainer(keyedBy: FractionKeys.self, forKey: .exact)
            let d = try f.decode(Int64.self, forKey: .d)
            guard d > 0 else {
                throw DecodingError.dataCorruptedError(forKey: .d, in: f, debugDescription: "fraction denominator must be positive, got \(d)")
            }
            exact = Rational(try f.decode(Int64.self, forKey: .n), d)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encode(value, forKey: .value)
        if let exact {
            var f = c.nestedContainer(keyedBy: FractionKeys.self, forKey: .exact)
            try f.encode(exact.numerator, forKey: .n)
            try f.encode(exact.denominator, forKey: .d)
        } else {
            try c.encodeNil(forKey: .exact)
        }
    }
}
