import Foundation
import JovraCore
import JovraVision
import Testing

/// V00: the runner checkpoints every window, so a run that dies mid-way resumes where it stopped and ends
/// with exactly the bytes an uninterrupted run writes.
@Suite struct AnalysisRunnerResumeTests {
    /// 3 s at 10 fps; frame n has luma (n * 37) mod 256, so the luma-shift stage sees jumps of 37 or -219.
    let recording = SyntheticReader(segments: [.init(startMs: 0, durationMs: 3000)], fps: 10, luma: { UInt8(($0 * 37) % 256) })

    @Test func aRunKilledMidStageResumesToByteIdenticalOutputs() async throws {
        let reference = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: recording, workspace: Workspace.make()).run()

        let workspace = Workspace.make()
        let dying = recording.killing(onRequest: 4)   // the fourth window of the first stage never finishes
        await #expect(throws: SimulatedKill.self) {
            try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: dying, workspace: workspace).run()
        }
        #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("fixture.luma/checkpoint.json").path))
        #expect(!FileManager.default.fileExists(atPath: workspace.appendingPathComponent("fixture.luma.output.json").path))

        let resumed = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: recording, workspace: workspace).run()
        #expect(resumed.outputs == reference.outputs)
        #expect(resumed.resumes == [AnalysisResume(stage: "fixture.luma", fromWindow: 3, windows: 6)])
        #expect(reference.resumes.isEmpty)
    }

    @Test func aStageKilledMidRunResumesWithTheStateItCarried() async throws {
        // The luma steps from 10 to 200 at frame 10, the first frame of window 2: only the state carried
        // over from window 1 (the luma of frame 9) can see that jump.
        let step = SyntheticReader(segments: [.init(startMs: 0, durationMs: 3000)], fps: 10, luma: { $0 < 10 ? 10 : 200 })
        let reference = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: step, workspace: Workspace.make()).run()
        let shifts = try JSONDecoder().decode(AnalysisStageOutput<LumaShift>.self, from: try #require(reference.outputs["fixture.lumaShift"]))
        #expect(shifts.observations == [LumaShift(time: try MediaTime(value: 1_000_000, timescale: 1_000_000), from: 10, to: 200)])

        let workspace = Workspace.make()
        await #expect(throws: SimulatedKill.self) {
            try await AnalysisRunner(stages: [FixtureLumaStage(), DyingStage(base: FixtureLumaShiftStage(), dieAt: 2)],
                                     reader: step, workspace: workspace).run()
        }
        let resumed = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: step, workspace: workspace).run()
        #expect(resumed.resumes == [AnalysisResume(stage: "fixture.lumaShift", fromWindow: 2, windows: 6)])
        #expect(resumed.outputs == reference.outputs)
    }

    @Test func theFixtureStagesWriteTheLumaOfEveryFrameAndTheJumpsBetweenThem() async throws {
        let report = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: recording, workspace: Workspace.make()).run()
        let luma = try JSONDecoder().decode(AnalysisStageOutput<FrameLuma>.self, from: try #require(report.outputs["fixture.luma"]))
        #expect(luma.source == "model:fixture.luma@1.0.0")
        #expect(luma.observations.count == 30)
        #expect(luma.observations.prefix(4).map(\.luma) == [0, 37, 74, 111])
        #expect(luma.observations[7].time == (try MediaTime(value: 700_000, timescale: 1_000_000)))
        #expect(luma.coverage.analysed == [AnalysisRange(startMs: 0, endMs: 3000)])
        #expect(luma.coverage.skipped.isEmpty)

        // 37 * 7 = 259: the luma wraps from 222 to 3 between frames 6 and 7, and again every seven frames.
        let shifts = try JSONDecoder().decode(AnalysisStageOutput<LumaShift>.self, from: try #require(report.outputs["fixture.lumaShift"]))
        #expect(shifts.observations.map(\.time.value) == [700_000, 1_400_000, 2_100_000, 2_800_000])
        #expect(shifts.observations.first.map { [$0.from, $0.to] } == [222, 3])
    }

    @Test func aCancelledRunKeepsItsCheckpointAndResumesToTheSameBytes() async throws {
        let reference = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: recording, workspace: Workspace.make()).run()
        let workspace = Workspace.make()
        let windows = Counter()
        let progressed = AsyncStream<Void>.makeStream()
        let task = Task {
            try await AnalysisRunner(stages: FixtureStages.pipeline(pace: .milliseconds(20)), reader: recording, workspace: workspace)
                .run { _ in if windows.increment() == 8 { progressed.continuation.yield() } }
        }
        for await _ in progressed.stream { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }

        let resumed = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: recording, workspace: workspace).run()
        #expect(resumed.outputs == reference.outputs)
        #expect(resumed.resumes.count == 1)
        #expect(resumed.resumes.first?.fromWindow ?? 0 >= 8 - 6, "resumes in the second stage, after the first finished")
    }

    @Test func progressRisesWindowByWindowAcrossEveryStageToOne() async throws {
        let values = Recorder<Double>()
        _ = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: recording, workspace: Workspace.make())
            .run { values.append($0) }
        let reported = values.all
        #expect(reported.count == 12, "six windows in each of the two stages")
        #expect(reported.first == 1.0 / 12)
        #expect(reported.last == 1)
        #expect(reported == reported.sorted())
    }

    @Test func aRestartDiscardsCheckpointsAndFinishedOutputs() async throws {
        let workspace = Workspace.make()
        let dying = recording.killing(onRequest: 2)
        _ = try? await AnalysisRunner(stages: FixtureStages.pipeline(), reader: dying, workspace: workspace).run()
        let report = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: recording, workspace: workspace).run(restart: true)
        #expect(report.resumes.isEmpty)
    }

    @Test func aCheckpointFromAnotherRecordingIsNotResumed() async throws {
        let workspace = Workspace.make()
        let dying = recording.killing(onRequest: 4)
        _ = try? await AnalysisRunner(stages: FixtureStages.pipeline(), reader: dying, workspace: workspace).run()
        let other = SyntheticReader(name: "other", segments: [.init(startMs: 0, durationMs: 3000)], fps: 10, luma: { _ in 9 })
        let report = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: other, workspace: workspace).run()
        #expect(report.resumes.isEmpty, "the media fingerprint differs, so the stage starts again")
        let luma = try JSONDecoder().decode(AnalysisStageOutput<FrameLuma>.self, from: try #require(report.outputs["fixture.luma"]))
        #expect(Set(luma.observations.map(\.luma)) == [9])
    }

    @Test func windowsNeverCrossSegmentsAndGapsAreNotAnalysed() async throws {
        let two = SyntheticReader(segments: [.init(startMs: 0, durationMs: 1200), .init(startMs: 2000, durationMs: 700)], fps: 10, luma: { _ in 50 })
        let report = try await AnalysisRunner(stages: [FixtureLumaStage()], reader: two, workspace: Workspace.make()).run()
        let luma = try JSONDecoder().decode(AnalysisStageOutput<FrameLuma>.self, from: try #require(report.outputs["fixture.luma"]))
        #expect(luma.coverage.analysed == [AnalysisRange(startMs: 0, endMs: 1200), AnalysisRange(startMs: 2000, endMs: 2700)])
        #expect(luma.observations.count == 12 + 7)
        #expect(luma.observations[12].time.value == 2_000_000)
    }

    @Test func aWindowWithNoFramesIsReportedAsSkippedWithItsReason() async throws {
        // 1 fps: the second half of every second has no frame.
        let sparse = SyntheticReader(segments: [.init(startMs: 0, durationMs: 2000)], fps: 1, luma: { _ in 80 })
        let report = try await AnalysisRunner(stages: [FixtureLumaStage()], reader: sparse, workspace: Workspace.make()).run()
        let luma = try JSONDecoder().decode(AnalysisStageOutput<FrameLuma>.self, from: try #require(report.outputs["fixture.luma"]))
        #expect(luma.coverage.analysed == [AnalysisRange(startMs: 0, endMs: 500), AnalysisRange(startMs: 1000, endMs: 1500)])
        #expect(luma.coverage.skipped == [AnalysisSkip(startMs: 500, endMs: 1000, reason: .noVideoFrames),
                                          AnalysisSkip(startMs: 1500, endMs: 2000, reason: .noVideoFrames)])
    }

    @Test func aStageMayReadOnlyTheStagesBeforeIt() async throws {
        await #expect(throws: AnalysisRunnerError.inputNotBefore(stage: "fixture.lumaShift", input: "fixture.luma")) {
            try await AnalysisRunner(stages: [FixtureLumaShiftStage(), FixtureLumaStage()], reader: recording, workspace: Workspace.make()).run()
        }
        await #expect(throws: AnalysisRunnerError.duplicateStage("fixture.luma")) {
            try await AnalysisRunner(stages: [FixtureLumaStage(), FixtureLumaStage()], reader: recording, workspace: Workspace.make()).run()
        }
    }
}

final class Recorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []
    func append(_ value: Value) { lock.withLock { values.append(value) } }
    var all: [Value] { lock.withLock { values } }
}

/// A stage that dies (like a killed process) when it reaches window `dieAt`.
struct DyingStage<Base: AnalysisStage>: AnalysisStage {
    var base: Base
    var dieAt: Int
    var id: AnalysisStageID { base.id }
    var version: String { base.version }
    var inputs: [AnalysisStageID] { base.inputs }
    var windowMs: Int { base.windowMs }
    func initialState() -> Base.State { base.initialState() }
    func analyse(_ window: AnalysisWindow, media: any AnalysisWindowReader, prior: AnalysisPriorOutputs,
                 state: inout Base.State) async throws -> AnalysisWindowResult<Base.Observation> {
        if window.index == dieAt { throw SimulatedKill() }
        return try await base.analyse(window, media: media, prior: prior, state: &state)
    }
}
