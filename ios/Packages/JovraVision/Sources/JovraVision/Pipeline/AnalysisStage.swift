import Foundation
import JovraCore

/// A stage's stable name. It is part of the stage's `source` (`model:<id>@<version>`) and names its files in
/// the workspace, so it uses the source grammar's letters only.
public struct AnalysisStageID: RawRepresentable, Hashable, Comparable, Codable, Sendable,
                               ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty, rawValue.count <= 48, !rawValue.hasPrefix("."),
              rawValue.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)) })
        else { return nil }
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        guard let id = AnalysisStageID(rawValue: value) else { preconditionFailure("invalid analysis stage id \(value)") }
        self = id
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let id = AnalysisStageID(rawValue: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "invalid analysis stage id \(text)"))
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }
}

/// One slice of the recording a stage analyses at a time: a half-open range of session time inside one
/// segment. Windows never cross a segment boundary, so a gap between segments is never analysed.
public struct AnalysisWindow: Codable, Hashable, Sendable {
    /// Position in the stage's plan, counted across all segments.
    public let index: Int
    /// The segment the window lies in (index into `AnalysisMediaInfo.segments`).
    public let segment: Int
    public let startMs: Int
    public let endMs: Int

    public init(index: Int, segment: Int, startMs: Int, endMs: Int) {
        self.index = index; self.segment = segment; self.startMs = startMs; self.endMs = endMs
    }
}

/// Why a stage could not analyse a window (V-track rule 4: coverage says why, and nothing is guessed).
public enum AnalysisSkipReason: String, Codable, CaseIterable, Sendable {
    /// The window holds no decodable video frame.
    case noVideoFrames
    /// The window holds no audio the stage needs.
    case noAudio
    /// The recording does not meet the capture guidance the stage needs (resolution, frame rate, mount).
    case belowCaptureGuidance
    /// The stage looks only where an earlier stage found something, and found nothing here.
    case outsideStageScope
}

/// What a stage made of one window.
public enum AnalysisWindowResult<Observation: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    case analysed([Observation])
    case skipped(AnalysisSkipReason)
}

/// A stage with nothing to carry from one window to the next.
public struct AnalysisNoState: Codable, Equatable, Sendable {
    public init() {}
}

/// One step of the analysis pipeline (V00). It reads windows of the recording through `media` and the
/// finished outputs of the stages it names in `inputs`, and returns typed observations per window.
///
/// The runner checkpoints `state` after every window, so a stage must keep everything it carries between
/// windows there and be deterministic: the same media and inputs give the same observations whether the run
/// was interrupted or not. A stage throws on a real failure and lets cancellation propagate.
public protocol AnalysisStage: Sendable {
    associatedtype Observation: Codable & Equatable & Sendable
    associatedtype State: Codable & Equatable & Sendable = AnalysisNoState

    var id: AnalysisStageID { get }
    /// The method version. A new version never resumes an older checkpoint or reuses an older output.
    var version: String { get }
    /// Stages whose finished outputs this stage reads. Each must come earlier in the runner's list.
    var inputs: [AnalysisStageID] { get }
    /// Window length; the last window of a segment is shorter.
    var windowMs: Int { get }

    func initialState() -> State
    func analyse(_ window: AnalysisWindow, media: any AnalysisWindowReader, prior: AnalysisPriorOutputs,
                 state: inout State) async throws -> AnalysisWindowResult<Observation>
}

extension AnalysisStage {
    /// Who produced the observations, in the contract's source grammar (`common.schema.json#/$defs/source`).
    public var source: String { "model:\(id.rawValue)@\(version)" }
}

extension AnalysisStage where State == AnalysisNoState {
    public func initialState() -> AnalysisNoState { AnalysisNoState() }
}
