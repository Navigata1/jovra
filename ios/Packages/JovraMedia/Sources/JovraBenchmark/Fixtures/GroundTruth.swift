import Foundation
import JovraCore

/// A media time as an exact rational, `value / timescale` seconds (the shared contracts store media times
/// this way so frame accuracy survives serialization).
public struct RationalTime: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let value: Int64
    public let timescale: Int64

    public init(value: Int64, timescale: Int64) {
        precondition(timescale > 0, "RationalTime needs a positive timescale")
        self.value = value
        self.timescale = timescale
    }

    enum CodingKeys: String, CodingKey { case value, timescale }

    /// Decoded JSON is checked, not trusted: a non-positive timescale is a decoding error, not a trap.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let timescale = try c.decode(Int64.self, forKey: .timescale)
        guard timescale > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .timescale, in: c, debugDescription: "timescale must be positive, got \(timescale)")
        }
        self.init(value: try c.decode(Int64.self, forKey: .value), timescale: timescale)
    }

    public static func < (lhs: RationalTime, rhs: RationalTime) -> Bool {
        Rational(lhs) < Rational(rhs)
    }

    public static func == (lhs: RationalTime, rhs: RationalTime) -> Bool {
        Rational(lhs) == Rational(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Rational(self))
    }

    public var description: String { "\(value)/\(timescale)" }
}

/// Ground truth for one rendered media fixture (`spec/schemas/ground-truth.schema.json`), written by
/// `scripts/media/render.py`. Tests compare what JovraMedia decodes or probes against these values.
public struct GroundTruth: Codable, Hashable, Sendable {
    public enum Split: String, Codable, Hashable, Sendable {
        case tuning
        case heldOut
    }

    public struct Renderer: Codable, Hashable, Sendable {
        public let script: String
        public let sourceHash: String
    }

    public struct Media: Codable, Hashable, Sendable {
        /// Repository-relative path inside the git-ignored render cache.
        public let path: String
        public let container: String
    }

    public struct Rate: Codable, Hashable, Sendable {
        public let num: Int
        public let den: Int
        public var frameRate: FrameRate { FrameRate(frames: num, perSeconds: den) }

        enum CodingKeys: String, CodingKey { case num, den }

        /// A non-positive rate is a decoding error, so `frameRate` can never trap.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            num = try c.decode(Int.self, forKey: .num)
            den = try c.decode(Int.self, forKey: .den)
            guard num > 0, den > 0 else {
                throw DecodingError.dataCorruptedError(forKey: .num, in: c, debugDescription: "frame rate \(num)/\(den) must be positive")
            }
        }
    }

    public struct HDR: Codable, Hashable, Sendable {
        public let transfer: String
        public let primaries: String
        public let matrix: String
    }

    public struct Video: Codable, Hashable, Sendable {
        public let codec: String
        public let fourCC: String
        public let bitDepth: Int
        public let codedWidth: Int
        public let codedHeight: Int
        public let rotationDegrees: Int
        public let displayWidth: Int
        public let displayHeight: Int
        public let orientation: String
        /// Nominal rate; for a variable-frame-rate clip, the median frame duration's rate.
        public let frameRate: Rate
        /// Frame durations vary (a phone-style VFR clip); frameCount / frameRate is still the duration.
        public let variableFrameRate: Bool
        public let frameCount: Int
        public let duration: RationalTime
        public let hdr: HDR?
        public let supported: Bool
    }

    public struct Audio: Codable, Hashable, Sendable {
        public let codec: String
        public let sampleRate: Int
        public let channels: Int
        public let sampleCount: Int
    }

    public struct FrameCodeSpec: Codable, Hashable, Sendable {
        public let cells: Int
        public let encodes: String
    }

    public struct Signature: Codable, Hashable, Sendable {
        public let method: String
        public let columns: Int
        public let rows: Int
        public let minimumMargin: Int
        public let frameCount: Int
        public let decodedFramesSha256: String
    }

    public struct Event: Codable, Hashable, Sendable {
        public let type: String
        public let time: RationalTime
        public let sample: Int
        public let frame: Int
    }

    public struct Point: Codable, Hashable, Sendable {
        public let x: Int
        public let y: Int
    }

    public struct Court: Codable, Hashable, Sendable {
        public let space: String
        public let order: String
        public let points: [Point]
    }

    public struct Cell: Codable, Hashable, Sendable {
        public let column: Int
        public let row: Int
    }

    public let id: String
    public let set: String
    public let description: String
    public let band: String
    public let renderer: Renderer
    public let media: Media
    public let seed: Int?
    public let split: Split?
    public let duplicateOf: String?
    public let video: Video
    public let audio: Audio?
    public let frameCode: FrameCodeSpec
    public let signature: Signature
    public let events: [Event]?
    public let court: Court?
    public let flashCell: Cell?
}
