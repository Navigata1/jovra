import Foundation
import JovraVision
import Testing

/// V00: the device budget hook. Analysis holds between windows on critical heat or a low battery on battery
/// power, keeps its checkpoint while held, and can still be cancelled.
@Suite struct AnalysisBudgetTests {
    let recording = SyntheticReader(segments: [.init(startMs: 0, durationMs: 2000)], fps: 10, luma: { UInt8($0 * 9) })

    @Test(arguments: [
        (ProcessInfo.ThermalState.critical, 0.80, true, AnalysisPause.criticalHeat),
        (.critical, 0.05, false, .criticalHeat),
        (.nominal, 0.10, false, .lowBattery),
        (.serious, 0.03, false, .lowBattery),
    ] as [(ProcessInfo.ThermalState, Double, Bool, AnalysisPause)])
    func theBudgetPausesForCriticalHeatOrALowBatteryOnBattery(thermal: ProcessInfo.ThermalState, battery: Double,
                                                               charging: Bool, expected: AnalysisPause) {
        #expect(AnalysisBudgetPolicy.pause(thermal: thermal, battery: battery, charging: charging) == expected)
    }

    @Test(arguments: [
        (ProcessInfo.ThermalState.serious, 0.80 as Double?, false),
        (.fair, 0.11, false),
        (.nominal, 0.04, true),
        (.nominal, nil, false),
    ] as [(ProcessInfo.ThermalState, Double?, Bool)])
    func theBudgetLetsAnalysisRunOtherwise(thermal: ProcessInfo.ThermalState, battery: Double?, charging: Bool) {
        #expect(AnalysisBudgetPolicy.pause(thermal: thermal, battery: battery, charging: charging) == nil)
    }

    @Test func aHeldRunWaitsAndThenFinishesWithTheSameOutputs() async throws {
        let reference = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: recording, workspace: Workspace.make()).run()
        let budget = ScriptedBudget([nil, nil, .lowBattery, .lowBattery, .lowBattery, nil])
        let told = Recorder<AnalysisPause>()
        let report = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: recording, workspace: Workspace.make(),
                                              budget: budget, budgetPoll: .milliseconds(1), onPause: { told.append($0) }).run()
        #expect(report.outputs == reference.outputs)
        #expect(report.pauses == [.lowBattery])
        #expect(told.all == [.lowBattery])
        #expect(budget.asked >= 6, "it asks again until the budget lets it go")
    }

    @Test func aHeldRunCanBeCancelledAndResumesFromItsCheckpoint() async throws {
        let reference = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: recording, workspace: Workspace.make()).run()
        let workspace = Workspace.make()
        // Two windows run, then the phone overheats and stays hot.
        let budget = ScriptedBudget([nil, nil], then: .criticalHeat)
        let held = AsyncStream<Void>.makeStream()
        let task = Task {
            try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: recording, workspace: workspace,
                                     budget: budget, budgetPoll: .milliseconds(5), onPause: { _ in held.continuation.yield() }).run()
        }
        for await _ in held.stream { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }

        let resumed = try await AnalysisRunner(stages: FixtureStages.pipeline(), reader: recording, workspace: workspace).run()
        #expect(resumed.outputs == reference.outputs)
        #expect(resumed.resumes == [AnalysisResume(stage: "fixture.luma", fromWindow: 2, windows: 4)])
    }
}

/// Answers from a script, then `then` for every later question.
final class ScriptedBudget: AnalysisBudget, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [AnalysisPause?]
    private let then: AnalysisPause?
    private var count = 0

    init(_ script: [AnalysisPause?], then: AnalysisPause? = nil) { self.script = script; self.then = then }

    var asked: Int { lock.withLock { count } }

    func pause() async -> AnalysisPause? {
        lock.withLock {
            count += 1
            return script.isEmpty ? then : script.removeFirst()
        }
    }
}
