import Foundation

public enum RunMode: String, Codable, Hashable, Sendable {
    /// Held-out seeds only; the record carries a verdict against its floor.
    case gate
    /// Tuning seeds only; the record has metrics but no verdict and gates nothing.
    case tuning
}

/// `spec/schemas/benchmark-record.schema.json`. Optional fields the schema requires are written as explicit
/// nulls.
public struct BenchmarkRecord: Codable, Hashable, Sendable {
    public static let schemaVersion = "1.0.0"
    public static let kind = "jovra.benchmarkRecord"

    public struct Harness: Codable, Hashable, Sendable {
        public let version: String
    }

    public struct Clip: Codable, Hashable, Sendable {
        public let truthId: String
        public let seed: Int
        public let split: GroundTruth.Split
        /// The ground truth's `renderer.sourceHash`: the renderer version that made the clip.
        public let rendererSourceHash: String
        /// The ground truth's `signature.decodedFramesSha256`. For a candidate, the harness decoded the rendered
        /// clip and checked this hash before estimating; oracle and null estimators read no media.
        public let decodedFramesSha256: String
        public let truthEventsSha256: String
        public let outputs: JSONValue

        public init(truthId: String, seed: Int, split: GroundTruth.Split, rendererSourceHash: String,
                    decodedFramesSha256: String, truthEventsSha256: String, outputs: JSONValue) {
            self.truthId = truthId
            self.seed = seed
            self.split = split
            self.rendererSourceHash = rendererSourceHash
            self.decodedFramesSha256 = decodedFramesSha256
            self.truthEventsSha256 = truthEventsSha256
            self.outputs = outputs
        }
    }

    public let schemaVersion: String
    public let kind: String
    public let runId: String
    public let at: String
    public let harness: Harness
    public let task: TaskDescriptor
    public let estimator: EstimatorIdentity
    public let capabilityId: String?
    public let mode: RunMode
    public let band: String
    public let clips: [Clip]
    public let metrics: [MetricResult]
    public let floor: Floor?
    public let verdict: Verdict?

    enum CodingKeys: String, CodingKey {
        case schemaVersion, kind, runId, at, harness, task, estimator, capabilityId, mode, band, clips, metrics, floor, verdict
    }

    public init(runId: String, at: String, harness: Harness, task: TaskDescriptor, estimator: EstimatorIdentity,
                capabilityId: String?, mode: RunMode, band: String, clips: [Clip], metrics: [MetricResult],
                floor: Floor?, verdict: Verdict?) {
        self.schemaVersion = Self.schemaVersion
        self.kind = Self.kind
        self.runId = runId
        self.at = at
        self.harness = harness
        self.task = task
        self.estimator = estimator
        self.capabilityId = capabilityId
        self.mode = mode
        self.band = band
        self.clips = clips
        self.metrics = metrics
        self.floor = floor
        self.verdict = verdict
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(kind, forKey: .kind)
        try c.encode(runId, forKey: .runId)
        try c.encode(at, forKey: .at)
        try c.encode(harness, forKey: .harness)
        try c.encode(task, forKey: .task)
        try c.encode(estimator, forKey: .estimator)
        try c.encode(capabilityId, forKey: .capabilityId)
        try c.encode(mode, forKey: .mode)
        try c.encode(band, forKey: .band)
        try c.encode(clips, forKey: .clips)
        try c.encode(metrics, forKey: .metrics)
        try c.encode(floor, forKey: .floor)
        try c.encode(verdict, forKey: .verdict)
    }

    /// Pretty, key-sorted JSON with a trailing newline: the committed form.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    /// The same record with the run's identity and time cleared, for comparing two runs' content.
    public var content: BenchmarkRecord {
        BenchmarkRecord(runId: "-", at: "-", harness: harness, task: task, estimator: estimator,
                        capabilityId: capabilityId, mode: mode, band: band, clips: clips, metrics: metrics,
                        floor: floor, verdict: verdict)
    }
}
