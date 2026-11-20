import Foundation

public enum AnalysisRunnerError: Error, Equatable, Sendable {
    /// Two stages share an id.
    case duplicateStage(AnalysisStageID)
    /// A stage reads a stage that is not listed before it.
    case inputNotBefore(stage: AnalysisStageID, input: AnalysisStageID)
    /// A stage asked for an output that is not available.
    case inputUnavailable(AnalysisStageID)
    /// A stage's window length is not positive.
    case invalidWindow(AnalysisStageID)
}

/// What a finished run produced.
public struct AnalysisRunReport: Sendable {
    /// Each stage's output as written to the workspace (canonical JSON bytes).
    public var outputs: [AnalysisStageID: Data]
    /// The stages this run continued from a checkpoint, in run order.
    public var resumes: [AnalysisResume]
    /// How often the device budget held the run.
    public var pauses: [AnalysisPause]
}

/// Runs analysis stages over one recording (V00). Stages run one after another in the given order, each over
/// every window of the recording; a stage reads the finished outputs of the stages before it.
///
/// After every window the runner writes the window's result and a checkpoint, then reports progress, so:
/// - an app kill or a cancellation loses at most the window in flight, and the next run resumes there;
/// - a finished stage is never run again for the same media and method version;
/// - the outputs are byte-identical whether or not the run was interrupted (stages are deterministic).
///
/// Before each window it asks the device budget, and holds while the budget says pause.
public struct AnalysisRunner: Sendable {
    public var stages: [any AnalysisStage]
    public var reader: any AnalysisWindowReader
    public var workspace: URL
    public var budget: any AnalysisBudget
    /// How often a held run asks the budget again.
    public var budgetPoll: Duration
    /// Told when the budget starts holding the run (each hold once).
    public var onPause: @Sendable (AnalysisPause) async -> Void

    public init(stages: [any AnalysisStage], reader: any AnalysisWindowReader, workspace: URL,
                budget: any AnalysisBudget = UnlimitedAnalysisBudget(), budgetPoll: Duration = .seconds(5),
                onPause: @escaping @Sendable (AnalysisPause) async -> Void = { _ in }) {
        self.stages = stages; self.reader = reader; self.workspace = workspace
        self.budget = budget; self.budgetPoll = budgetPoll; self.onPause = onPause
    }

    /// Runs every stage to the end. `restart` discards checkpoints and finished outputs first (a retry after
    /// a failure). `progress` (0…1, over all windows of all stages) is called after each window is saved.
    @discardableResult
    public func run(restart: Bool = false,
                    progress: @Sendable (Double) async throws -> Void = { _ in }) async throws -> AnalysisRunReport {
        try validate()
        let files = AnalysisWorkspace(root: workspace)
        if restart { try files.clear() }
        let info = reader.info
        let plans = stages.map { Self.plan($0.windowMs, over: info.segments) }
        let total = plans.reduce(0) { $0 + $1.count }
        var context = RunContext(files: files, info: info, total: total)
        for (stage, plan) in zip(stages, plans) {
            let data = try await run(stage, plan: plan, context: &context, progress: progress)
            context.outputs[stage.id] = data
        }
        if total == 0 { try await progress(1) }
        return AnalysisRunReport(outputs: context.outputs, resumes: context.resumes, pauses: context.pauses)
    }

    /// The windows of a stage: `windowMs` slices of each segment, the last one of a segment shorter.
    public static func plan(_ windowMs: Int, over segments: [AnalysisSegment]) -> [AnalysisWindow] {
        var windows: [AnalysisWindow] = []
        for (index, segment) in segments.enumerated() where segment.durationMs > 0 {
            var start = segment.startMs
            let end = segment.startMs + segment.durationMs
            while start < end {
                let stop = min(start + windowMs, end)
                windows.append(AnalysisWindow(index: windows.count, segment: index, startMs: start, endMs: stop))
                start = stop
            }
        }
        return windows
    }

    // MARK: One stage

    private struct RunContext {
        let files: AnalysisWorkspace
        let info: AnalysisMediaInfo
        let total: Int
        var done = 0
        var outputs: [AnalysisStageID: Data] = [:]
        var resumes: [AnalysisResume] = []
        var pauses: [AnalysisPause] = []
    }

    private func run<S: AnalysisStage>(_ stage: S, plan: [AnalysisWindow], context: inout RunContext,
                                       progress: @Sendable (Double) async throws -> Void) async throws -> Data {
        let files = context.files
        let media = AnalysisMediaIdentity(context.info)
        let outputURL = files.outputURL(stage.id)
        if let data = try? Data(contentsOf: outputURL),
           let output = try? JSONDecoder().decode(AnalysisStageOutput<S.Observation>.self, from: data),
           output.version == stage.version, output.media == media {
            context.done += plan.count
            return data
        }
        try files.remove(outputURL)

        var state = stage.initialState()
        var next = 0
        if let checkpoint = files.read(AnalysisCheckpoint<S.State>.self, at: files.checkpointURL(stage.id)),
           checkpoint.version == stage.version, checkpoint.media == media, checkpoint.windowMs == stage.windowMs,
           checkpoint.windows == plan.count, (0...plan.count).contains(checkpoint.nextWindow) {
            state = checkpoint.state
            next = checkpoint.nextWindow
        } else {
            try files.remove(files.stageFolder(stage.id))
        }
        if next > 0 {
            let resume = AnalysisResume(stage: stage.id, fromWindow: next, windows: plan.count)
            context.resumes.append(resume)
            var log = files.read(AnalysisRunLog.self, at: files.runLogURL) ?? AnalysisRunLog()
            log.resumes.append(resume)
            try files.write(AnalysisWorkspace.encode(log), to: files.runLogURL)
        }
        context.done += next

        let prior = AnalysisPriorOutputs(context.outputs)
        for window in plan[next...] {
            try Task.checkCancellation()
            if let pause = try await holdWhileBudgetPauses() { context.pauses.append(pause) }
            let result = try await stage.analyse(window, media: reader, prior: prior, state: &state)
            try files.write(AnalysisWorkspace.encode(AnalysisWindowPart(window: window, result: result)),
                            to: files.partURL(stage.id, window: window.index))
            let checkpoint = AnalysisCheckpoint(stage: stage.id, version: stage.version, media: media, windowMs: stage.windowMs,
                                                windows: plan.count, nextWindow: window.index + 1, state: state)
            try files.write(AnalysisWorkspace.encode(checkpoint), to: files.checkpointURL(stage.id))
            context.done += 1
            try await progress(Double(context.done) / Double(context.total))
        }
        return try finish(stage, plan: plan, media: media, files: files)
    }

    /// Assembles the stage output from its window parts, writes it and removes the parts and checkpoint.
    private func finish<S: AnalysisStage>(_ stage: S, plan: [AnalysisWindow], media: AnalysisMediaIdentity,
                                          files: AnalysisWorkspace) throws -> Data {
        var coverage = AnalysisCoverage()
        var observations: [S.Observation] = []
        for window in plan {
            let url = files.partURL(stage.id, window: window.index)
            let part = try JSONDecoder().decode(AnalysisWindowPart<S.Observation>.self, from: Data(contentsOf: url))
            switch part.result {
            case .analysed(let found):
                coverage.add(window, skipped: nil)
                observations += found
            case .skipped(let reason):
                coverage.add(window, skipped: reason)
            }
        }
        let output = AnalysisStageOutput(stage: stage.id, version: stage.version, source: stage.source, media: media,
                                         coverage: coverage, observations: observations)
        let data = try AnalysisWorkspace.encode(output)
        try files.write(data, to: files.outputURL(stage.id))
        try files.remove(files.stageFolder(stage.id))
        return data
    }

    /// Holds (cancellably) while the budget answers a pause; returns the first pause, if any.
    private func holdWhileBudgetPauses() async throws -> AnalysisPause? {
        guard let first = await budget.pause() else { return nil }
        await onPause(first)
        repeat {
            try await Task.sleep(for: budgetPoll)
        } while await budget.pause() != nil
        return first
    }

    private func validate() throws {
        var seen = Set<AnalysisStageID>()
        for stage in stages {
            guard seen.insert(stage.id).inserted else { throw AnalysisRunnerError.duplicateStage(stage.id) }
            guard stage.windowMs > 0 else { throw AnalysisRunnerError.invalidWindow(stage.id) }
        }
        var before = Set<AnalysisStageID>()
        for stage in stages {
            for input in stage.inputs where !before.contains(input) {
                throw AnalysisRunnerError.inputNotBefore(stage: stage.id, input: input)
            }
            before.insert(stage.id)
        }
    }
}
