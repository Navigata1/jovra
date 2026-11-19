import CryptoKit
import Foundation

/// A point in normalized image space: 0..1 from the top-left of the displayed picture (GLOSSARY, Court model).
public struct ImagePoint: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Clamped to the picture and rounded to six places, so a label file's bytes do not depend on how a
    /// pointer position was computed.
    public var normalized: ImagePoint {
        func tidy(_ value: Double) -> Double { (min(max(value, 0), 1) * 1_000_000).rounded() / 1_000_000 }
        return ImagePoint(x: tidy(x), y: tidy(y))
    }
}

/// `spec/schemas/benchmark-labels.schema.json`: what a person marked on one real recording. Times and points
/// only; no frame, no audio, no file name and no person's name (docs/fixtures/real-footage.md).
public struct BenchmarkLabels: Codable, Hashable, Sendable {
    public static let schemaVersion = "1.0.0"
    public static let kind = "jovra.benchmarkLabels"

    public struct FrameRate: Codable, Hashable, Sendable {
        public let num: Int
        public let den: Int

        public init(num: Int, den: Int) {
            self.num = num
            self.den = den
        }
    }

    /// The file the labels were made on, identified by its bytes.
    public struct Recording: Codable, Hashable, Sendable {
        public let sha256: String
        public let byteSize: Int64
        public let duration: RationalTime
        /// Displayed picture size in pixels (after the track rotation).
        public let width: Int
        public let height: Int
        public let frameRate: FrameRate
        public let variableFrameRate: Bool

        public init(sha256: String, byteSize: Int64, duration: RationalTime, width: Int, height: Int,
                    frameRate: FrameRate, variableFrameRate: Bool) {
            self.sha256 = sha256
            self.byteSize = byteSize
            self.duration = duration
            self.width = width
            self.height = height
            self.frameRate = frameRate
            self.variableFrameRate = variableFrameRate
        }
    }

    public struct LabelledBy: Codable, Hashable, Sendable {
        public enum Method: String, Codable, Hashable, Sendable {
            case human
            case synthetic
        }

        public let method: Method
        public let tool: String

        public init(method: Method, tool: String) {
            self.method = method
            self.tool = tool
        }
    }

    public enum Player: String, Codable, Hashable, Sendable, CaseIterable {
        case near
        case far
    }

    /// The stroke types of the GLOSSARY.
    public enum Stroke: String, Codable, Hashable, Sendable, CaseIterable {
        case serve
        case forehand
        case backhand
        case volley
        case overhead
        case other
    }

    public struct Hit: Codable, Hashable, Sendable {
        public let time: RationalTime
        public let player: Player
        public let stroke: Stroke?

        public init(time: RationalTime, player: Player, stroke: Stroke? = nil) {
            self.time = time
            self.player = player
            self.stroke = stroke
        }

        enum CodingKeys: String, CodingKey { case time, player, stroke }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(time, forKey: .time)
            try c.encode(player, forKey: .player)
            try c.encode(stroke, forKey: .stroke)
        }
    }

    public struct Bounce: Codable, Hashable, Sendable {
        public let time: RationalTime
        public let imagePoint: ImagePoint
        /// True during a live rally; false for a dead ball. Never a line call.
        public let inPlay: Bool

        public init(time: RationalTime, imagePoint: ImagePoint, inPlay: Bool = true) {
            self.time = time
            self.imagePoint = imagePoint
            self.inPlay = inPlay
        }
    }

    public struct Rally: Codable, Hashable, Sendable {
        public let start: RationalTime
        /// Nil while the rally is still open in the labelling tool.
        public let end: RationalTime?

        public init(start: RationalTime, end: RationalTime?) {
            self.start = start
            self.end = end
        }

        enum CodingKeys: String, CodingKey { case start, end }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(start, forKey: .start)
            try c.encode(end, forKey: .end)
        }
    }

    public struct Corners: Codable, Hashable, Sendable {
        public static let court = "doubles"
        public static let order = "farLeft,farRight,nearRight,nearLeft"
        /// The corner names in label order, for screens and reports.
        public static let names = ["Far left", "Far right", "Near right", "Near left"]

        public let court: String
        public let order: String
        /// Four entries in `order`; nil where a corner is hidden or outside the picture.
        public let points: [ImagePoint?]

        public init(points: [ImagePoint?]) {
            precondition(points.count == 4, "a court has four corners")
            self.court = Self.court
            self.order = Self.order
            self.points = points
        }
    }

    public struct CameraPosition: Codable, Hashable, Sendable {
        public let from: RationalTime
        public let corners: Corners

        public init(from: RationalTime, corners: Corners) {
            self.from = from
            self.corners = corners
        }
    }

    /// Audio onsets the labelling tool offered. Never ground truth: only `hits` are.
    public struct HitCandidates: Codable, Hashable, Sendable {
        public enum Decision: String, Codable, Hashable, Sendable {
            case pending
            case confirmed
            case rejected
        }

        public struct Candidate: Codable, Hashable, Sendable {
            public let time: RationalTime
            public let decision: Decision

            public init(time: RationalTime, decision: Decision = .pending) {
                self.time = time
                self.decision = decision
            }
        }

        public let method: String
        public let items: [Candidate]

        public init(method: String, items: [Candidate]) {
            self.method = method
            self.items = items
        }
    }

    public struct Counts: Codable, Hashable, Sendable {
        public let hits: Int
        /// Hits that carry a stroke type.
        public let strokes: Int
        public let bounces: Int
        /// Closed rallies.
        public let rallies: Int
        public let cameraPositions: Int

        public init(hits: Int, strokes: Int, bounces: Int, rallies: Int, cameraPositions: Int) {
            self.hits = hits
            self.strokes = strokes
            self.bounces = bounces
            self.rallies = rallies
            self.cameraPositions = cameraPositions
        }

        public subscript(key: String) -> Int? {
            ["hits": hits, "strokes": strokes, "bounces": bounces, "rallies": rallies, "cameraPositions": cameraPositions][key]
        }
    }

    public let schemaVersion: String
    public let kind: String
    public let recording: Recording
    public let labelledBy: LabelledBy
    public let split: LabelSplit
    public let hits: [Hit]
    public let bounces: [Bounce]
    public let rallies: [Rally]
    public let cameraPositions: [CameraPosition]
    public let hitCandidates: HitCandidates?

    public init(recording: Recording, labelledBy: LabelledBy, split: LabelSplit, hits: [Hit] = [], bounces: [Bounce] = [],
                rallies: [Rally] = [], cameraPositions: [CameraPosition] = [], hitCandidates: HitCandidates? = nil) {
        self.schemaVersion = Self.schemaVersion
        self.kind = Self.kind
        self.recording = recording
        self.labelledBy = labelledBy
        self.split = split
        self.hits = hits
        self.bounces = bounces
        self.rallies = rallies
        self.cameraPositions = cameraPositions
        self.hitCandidates = hitCandidates
    }

    /// An empty label document for a recording, with its hash-fixed split already in place.
    public init(recording: Recording, labelledBy: LabelledBy) throws {
        self.init(recording: recording, labelledBy: labelledBy,
                  split: try LabelSplit(recordingSha256: recording.sha256, duration: recording.duration))
    }

    /// The same document with some parts replaced (labels are values; an edit makes a new one).
    public func replacing(hits: [Hit]? = nil, bounces: [Bounce]? = nil, rallies: [Rally]? = nil,
                          cameraPositions: [CameraPosition]? = nil, hitCandidates: HitCandidates?? = nil) -> BenchmarkLabels {
        BenchmarkLabels(recording: recording, labelledBy: labelledBy, split: split, hits: hits ?? self.hits,
                        bounces: bounces ?? self.bounces, rallies: rallies ?? self.rallies,
                        cameraPositions: cameraPositions ?? self.cameraPositions,
                        hitCandidates: hitCandidates ?? self.hitCandidates)
    }

    public var counts: Counts {
        Counts(hits: hits.count, strokes: hits.filter { $0.stroke != nil }.count, bounces: bounces.count,
               rallies: rallies.filter { $0.end != nil }.count, cameraPositions: cameraPositions.count)
    }

    /// The name a label file takes from its recording: `rec-<first 12 hex of the hash>.labels.json`.
    public var fileName: String { Self.fileName(recordingSha256: recording.sha256) }

    public static func fileName(recordingSha256: String) -> String {
        "rec-\(recordingSha256.prefix(12)).labels.json"
    }

    /// Pretty, key-sorted JSON with a trailing newline: the committed form. The label set records the SHA-256
    /// of exactly these bytes.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    public static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// What the schema cannot say (the same rules as `label_problems` in the Python reference).
    public func problems() -> [String] {
        var problems: [String] = []
        guard kind == Self.kind else { return ["kind is \(kind), not \(Self.kind)"] }
        let expected = try? LabelSplit(recordingSha256: recording.sha256, duration: recording.duration,
                                       windowMs: split.windowMs, heldOutPermille: split.heldOutPermille)
        if expected != split {
            problems.append("split is not the hash-fixed split of this recording")
        }
        let end = recording.duration
        func check(_ name: String, _ times: [RationalTime]) {
            if zip(times, times.dropFirst()).contains(where: { $1 < $0 }) { problems.append("\(name) are not in time order") }
            if times.contains(where: { $0 > end }) { problems.append("\(name) hold a time after the recording ends") }
        }
        check("hits", hits.map(\.time))
        var seen = Set<String>()
        for hit in hits where !seen.insert("\(Rational(hit.time))|\(hit.player.rawValue)").inserted {
            problems.append("two hits by the \(hit.player.rawValue) player at \(Rational(hit.time)) s")
        }
        check("bounces", bounces.map(\.time))
        check("rally starts", rallies.map(\.start))
        var previousEnd: RationalTime?
        for (index, rally) in rallies.enumerated() {
            if let previousEnd, rally.start < previousEnd { problems.append("rally \(index + 1) starts before the previous rally ends") }
            guard let finish = rally.end else {
                if index != rallies.count - 1 { problems.append("rally \(index + 1) is open but is not the last rally") }
                continue
            }
            if finish <= rally.start { problems.append("rally \(index + 1) does not run forwards") }
            if finish > end { problems.append("rally \(index + 1) ends after the recording") }
            previousEnd = finish
        }
        check("camera positions", cameraPositions.map(\.from))
        if Set(cameraPositions.map { Rational($0.from) }).count != cameraPositions.count {
            problems.append("two camera positions start at the same time")
        }
        if let hitCandidates {
            check("hit candidates", hitCandidates.items.map(\.time))
            if Set(hitCandidates.items.map { Rational($0.time) }).count != hitCandidates.items.count {
                problems.append("two hit candidates share a time")
            }
        }
        let points = bounces.map(\.imagePoint) + cameraPositions.flatMap { $0.corners.points.compactMap { $0 } }
        if points.contains(where: { !(0...1).contains($0.x) || !(0...1).contains($0.y) }) {
            problems.append("an image point lies outside the picture")
        }
        return problems
    }
}
