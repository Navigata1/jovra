import Foundation
import JovraCore

/// A half-open range of session time.
public struct AnalysisRange: Codable, Equatable, Hashable, Sendable {
    public var startMs: Int
    public var endMs: Int
    public init(startMs: Int, endMs: Int) { self.startMs = startMs; self.endMs = endMs }
    public var durationMs: Int { endMs - startMs }
}

/// A range a stage did not analyse, with its reason.
public struct AnalysisSkip: Codable, Equatable, Hashable, Sendable {
    public var startMs: Int
    public var endMs: Int
    public var reason: AnalysisSkipReason
    public init(startMs: Int, endMs: Int, reason: AnalysisSkipReason) {
        self.startMs = startMs; self.endMs = endMs; self.reason = reason
    }
}

/// What share of the recording a stage analysed and why not the rest (V-track rule 4). Touching ranges with
/// the same meaning are merged, so the lists stay short for long recordings.
public struct AnalysisCoverage: Codable, Equatable, Sendable {
    public var analysed: [AnalysisRange]
    public var skipped: [AnalysisSkip]

    public init(analysed: [AnalysisRange] = [], skipped: [AnalysisSkip] = []) {
        self.analysed = analysed; self.skipped = skipped
    }

    public var analysedMs: Int { analysed.reduce(0) { $0 + $1.durationMs } }
    public var skippedMs: Int { skipped.reduce(0) { $0 + $1.endMs - $1.startMs } }
    /// Analysed share of the recorded time (0…1); 0 when nothing was recorded.
    public var share: Double {
        let total = analysedMs + skippedMs
        return total == 0 ? 0 : Double(analysedMs) / Double(total)
    }

    mutating func add(_ window: AnalysisWindow, skipped reason: AnalysisSkipReason?) {
        if let reason {
            if let last = skipped.last, last.endMs == window.startMs, last.reason == reason {
                skipped[skipped.count - 1].endMs = window.endMs
            } else {
                skipped.append(AnalysisSkip(startMs: window.startMs, endMs: window.endMs, reason: reason))
            }
        } else if let last = analysed.last, last.endMs == window.startMs {
            analysed[analysed.count - 1].endMs = window.endMs
        } else {
            analysed.append(AnalysisRange(startMs: window.startMs, endMs: window.endMs))
        }
    }
}

/// The recording a stage output belongs to. A checkpoint or output for other media is never reused.
public struct AnalysisMediaIdentity: Codable, Equatable, Sendable {
    public var fingerprint: String
    public var segments: [AnalysisSegment]
    public init(_ info: AnalysisMediaInfo) { fingerprint = info.fingerprint; segments = info.segments }
}

/// One stage's finished result for one recording: its observations in window order and its coverage.
/// Written as canonical JSON (sorted keys), so equal results are equal bytes.
public struct AnalysisStageOutput<Observation: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public static var kind: String { "jovra.analysisStageOutput" }
    public var schemaVersion: String
    public var kind: String
    public var stage: AnalysisStageID
    public var version: String
    public var source: String
    public var media: AnalysisMediaIdentity
    public var coverage: AnalysisCoverage
    public var observations: [Observation]

    public init(stage: AnalysisStageID, version: String, source: String, media: AnalysisMediaIdentity,
                coverage: AnalysisCoverage, observations: [Observation]) {
        schemaVersion = "1.0.0"; kind = Self.kind
        self.stage = stage; self.version = version; self.source = source
        self.media = media; self.coverage = coverage; self.observations = observations
    }
}

/// The finished outputs of earlier stages, decoded at most once per stage and run.
public final class AnalysisPriorOutputs: @unchecked Sendable {
    private let encoded: [AnalysisStageID: Data]
    private let lock = NSLock()
    private var decoded: [AnalysisStageID: any Sendable] = [:]

    init(_ encoded: [AnalysisStageID: Data]) { self.encoded = encoded }

    /// The output `stage` wrote earlier in this run (or a run before it). Throws when it is not available,
    /// which means the stage was not listed before the reader.
    public func output<S: AnalysisStage>(of stage: S) throws -> AnalysisStageOutput<S.Observation> {
        try lock.withLock {
            if let cached = decoded[stage.id] as? AnalysisStageOutput<S.Observation> { return cached }
            guard let data = encoded[stage.id] else { throw AnalysisRunnerError.inputUnavailable(stage.id) }
            let output = try JSONDecoder().decode(AnalysisStageOutput<S.Observation>.self, from: data)
            decoded[stage.id] = output
            return output
        }
    }
}
