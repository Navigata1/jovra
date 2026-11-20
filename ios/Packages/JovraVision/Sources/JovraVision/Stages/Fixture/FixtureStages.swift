import Foundation
import JovraCore

/// The mean luma of one frame.
public struct FrameLuma: Codable, Equatable, Sendable {
    public var time: MediaTime
    public var luma: Int
    public init(time: MediaTime, luma: Int) { self.time = time; self.luma = luma }
}

/// A jump in mean luma between two consecutive frames.
public struct LumaShift: Codable, Equatable, Sendable {
    /// The time of the later frame.
    public var time: MediaTime
    public var from: Int
    public var to: Int
    public init(time: MediaTime, from: Int, to: Int) { self.time = time; self.from = from; self.to = to }
}

/// Fixture stage (V00): the mean luma of every frame. It exercises frame reading, windows, checkpoints and
/// coverage, and claims nothing about tennis. Registered only for tests (`-processingAnalyzer visionFixture`).
public struct FixtureLumaStage: AnalysisStage {
    public static let id: AnalysisStageID = "fixture.luma"
    public var id: AnalysisStageID { Self.id }
    public var version: String { "1.0.0" }
    public var inputs: [AnalysisStageID] { [] }
    public var windowMs: Int { 500 }
    /// Extra time per window, so UI tests can act while analysis is still running.
    public var pace: Duration

    public init(pace: Duration = .zero) { self.pace = pace }

    public func analyse(_ window: AnalysisWindow, media: any AnalysisWindowReader, prior: AnalysisPriorOutputs,
                        state: inout AnalysisNoState) async throws -> AnalysisWindowResult<FrameLuma> {
        if pace > .zero { try await Task.sleep(for: pace) }
        var found: [FrameLuma] = []
        for try await frame in media.frames(in: window) {
            found.append(FrameLuma(time: frame.time, luma: frame.meanLuma()))
        }
        return found.isEmpty ? .skipped(.noVideoFrames) : .analysed(found)
    }
}

/// Fixture stage (V00): luma jumps of at least `threshold` between consecutive frames, read from
/// `FixtureLumaStage`'s output. The previous frame's luma is carried across windows in its checkpointed state.
public struct FixtureLumaShiftStage: AnalysisStage {
    public struct State: Codable, Equatable, Sendable {
        public var previous: Int?
    }

    public static let id: AnalysisStageID = "fixture.lumaShift"
    public static let threshold = 64
    public var id: AnalysisStageID { Self.id }
    public var version: String { "1.0.0" }
    public var inputs: [AnalysisStageID] { [FixtureLumaStage.id] }
    public var windowMs: Int { 500 }
    public var pace: Duration

    public init(pace: Duration = .zero) { self.pace = pace }

    public func initialState() -> State { State(previous: nil) }

    public func analyse(_ window: AnalysisWindow, media: any AnalysisWindowReader, prior: AnalysisPriorOutputs,
                        state: inout State) async throws -> AnalysisWindowResult<LumaShift> {
        if pace > .zero { try await Task.sleep(for: pace) }
        let frames = try prior.output(of: FixtureLumaStage()).observations.filter { frame in
            let micros = frame.time.value * 1_000_000 / Int64(frame.time.timescale)
            return micros >= Int64(window.startMs) * 1000 && micros < Int64(window.endMs) * 1000
        }
        guard !frames.isEmpty else { return .skipped(.outsideStageScope) }
        var shifts: [LumaShift] = []
        for frame in frames {
            if let previous = state.previous, abs(frame.luma - previous) >= Self.threshold {
                shifts.append(LumaShift(time: frame.time, from: previous, to: frame.luma))
            }
            state.previous = frame.luma
        }
        return .analysed(shifts)
    }
}

public enum FixtureStages {
    /// The fixture pipeline: luma, then luma shifts.
    public static func pipeline(pace: Duration = .zero) -> [any AnalysisStage] {
        [FixtureLumaStage(pace: pace), FixtureLumaShiftStage(pace: pace)]
    }
}
