import Foundation

/// `spec/schemas/benchmark-observations.schema.json`: what one analysis stage found on one recording, in the
/// form the label scorer reads. A stage lists only the kinds it produces: nil is "not scored", an empty array
/// is "found nothing". `analysed` is the stage's coverage (V-track rule 4).
public struct StageObservations: Codable, Hashable, Sendable {
    public static let schemaVersion = "1.0.0"
    public static let kind = "jovra.benchmarkObservations"

    public struct Range: Codable, Hashable, Sendable {
        public let start: RationalTime
        public let end: RationalTime

        public init(start: RationalTime, end: RationalTime) {
            self.start = start
            self.end = end
        }
    }

    public struct Hit: Codable, Hashable, Sendable {
        public let time: RationalTime
        public let player: BenchmarkLabels.Player?
        public let stroke: BenchmarkLabels.Stroke?

        public init(time: RationalTime, player: BenchmarkLabels.Player? = nil, stroke: BenchmarkLabels.Stroke? = nil) {
            self.time = time
            self.player = player
            self.stroke = stroke
        }
    }

    public struct Bounce: Codable, Hashable, Sendable {
        public let time: RationalTime
        public let imagePoint: ImagePoint?

        public init(time: RationalTime, imagePoint: ImagePoint? = nil) {
            self.time = time
            self.imagePoint = imagePoint
        }
    }

    public struct CourtCorners: Codable, Hashable, Sendable {
        public let time: RationalTime
        /// Four entries in the label order (far left, far right, near right, near left); nil where unknown.
        public let points: [ImagePoint?]

        public init(time: RationalTime, points: [ImagePoint?]) {
            self.time = time
            self.points = points
        }
    }

    public let schemaVersion: String
    public let kind: String
    public let recordingSha256: String
    /// The stage and its method version, e.g. `model:shots@0.1.0`.
    public let producer: String
    public let analysed: [Range]?
    public let hits: [Hit]?
    public let bounces: [Bounce]?
    public let rallies: [Range]?
    public let courtCorners: [CourtCorners]?

    public init(recordingSha256: String, producer: String, analysed: [Range]? = nil, hits: [Hit]? = nil,
                bounces: [Bounce]? = nil, rallies: [Range]? = nil, courtCorners: [CourtCorners]? = nil) {
        self.schemaVersion = Self.schemaVersion
        self.kind = Self.kind
        self.recordingSha256 = recordingSha256
        self.producer = producer
        self.analysed = analysed
        self.hits = hits
        self.bounces = bounces
        self.rallies = rallies
        self.courtCorners = courtCorners
    }

    /// Why these observations cannot be scored against `labels`; empty when they can.
    public func problems(against labels: BenchmarkLabels) -> [String] {
        var problems: [String] = []
        if kind != Self.kind { problems.append("kind is \(kind), not \(Self.kind)") }
        if recordingSha256 != labels.recording.sha256 {
            problems.append("observations are for a different recording than the labels")
        }
        var previous: RationalTime?
        for range in analysed ?? [] {
            if range.end <= range.start || (previous.map { range.start < $0 } ?? false) {
                problems.append("analysed ranges must run forwards, in order and without overlap")
            }
            previous = range.end
        }
        if (rallies ?? []).contains(where: { $0.end <= $0.start }) {
            problems.append("an observed rally does not run forwards")
        }
        if (courtCorners ?? []).contains(where: { $0.points.count != 4 }) {
            problems.append("a court corner observation needs four entries")
        }
        return problems
    }
}
