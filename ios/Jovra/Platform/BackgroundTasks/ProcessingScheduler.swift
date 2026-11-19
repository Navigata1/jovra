import Foundation
import JovraCore
import Observation
import os

/// The app adapter around `ProcessingQueueStore` (spec: ProcessingQueue). It runs one stage at a time,
/// only while capture is idle, at thermal state fair or better and (for analysis) not on Low Power Mode
/// without a charger. Every decision and transition is the pure queue's; this type only does the work,
/// reports progress and reacts to the device. Backups are left to the archive service.
@MainActor @Observable
final class ProcessingScheduler {
    static let shared = ProcessingScheduler(launch: .current, library: LocalCaptureLibraryKey.defaultValue)

    /// What the scheduler is waiting for.
    enum Availability: Equatable { case starting, ready, unavailable }

    private(set) var availability = Availability.starting
    private(set) var jobs: [String: ProcessingJob] = [:]
    private(set) var hold: ProcessingHold?
    /// False on the iOS 18 path (or when the system refuses a continued-processing task): work stops
    /// when JOVRA leaves the foreground, and the screen says so.
    private(set) var continuesInBackground = ProcessingBackgroundTasks.supportsContinuedProcessing
    var conditions: ProcessingConditions { monitor.conditions }

    private enum StopReason { case pause, interrupt }
    private struct Running {
        var session: String
        var stage: ProcessingStage
        var task: Task<Void, Never>
    }

    @ObservationIgnored private let library: LocalCaptureLibrary?
    @ObservationIgnored private let analyzers: [any SessionAnalyzer]
    @ObservationIgnored private let monitor: ProcessingConditionsMonitor
    @ObservationIgnored private var store: ProcessingQueueStore?
    @ObservationIgnored private var running: Running?
    @ObservationIgnored private var stopReason: StopReason?
    @ObservationIgnored private var pumping = false
    @ObservationIgnored private var activation: Task<Void, Never>?
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private let log = Logger(subsystem: "com.islanddevcrew.jovra", category: "processing")
    private static let scheduledStages: Set<ProcessingStage> = [.prepareReplay, .analyze]

    init(launch: LaunchConfiguration, library: LocalCaptureAvailability) {
        if case .ready(let library) = library { self.library = library } else { self.library = nil }
        analyzers = AnalyzerRegistry.registered(for: launch)
        monitor = ProcessingConditionsMonitor(launch: launch)
    }

    /// Opens the persisted queue and starts watching the device. Safe to call more than once.
    func activate() async {
        if let activation { return await activation.value }
        let task = Task { await open() }
        activation = task
        await task.value
    }

    private func open() async {
        guard let library else { availability = .unavailable; return }
        do {
            store = try await library.processing()
        } catch {
            log.error("processing queue unavailable: \(String(describing: error), privacy: .public)")
            availability = .unavailable
            return
        }
        monitor.onChange = { [weak self] conditions in self?.conditionsChanged(conditions) }
        monitor.onBackground = { [weak self] background in self?.backgroundChanged(background) }
        monitor.start()
        try? await store?.updateBackup(monitor.conditions.backup)
        await refreshAll()
        availability = .ready
        pump()
    }

    func job(_ session: SessionID) -> ProcessingJob? { jobs[session.rawValue] }

    // MARK: Player actions

    /// Queues a saved session (after capture or import). Idempotent.
    func enqueue(_ session: SessionID, originalSaved: Bool = true) async {
        await activate()
        guard let store else { return }
        do {
            try await store.enqueue(session.rawValue, originalSaved: originalSaved)
            try await store.updateBackup(monitor.conditions.backup)
        } catch { log.error("enqueue failed: \(String(describing: error), privacy: .public)") }
        await refresh(session.rawValue)
        pump()
    }

    func pauseAnalysis(_ session: SessionID) async {
        guard let store else { return }
        if let running, running.session == session.rawValue, running.stage == .analyze {
            stop(.pause)
            await running.task.value
        } else {
            try? await store.pauseAnalysis(for: session.rawValue)
        }
        await refresh(session.rawValue)
        pump()
    }

    func resumeAnalysis(_ session: SessionID) async {
        guard let store else { return }
        try? await store.resumeAnalysis(for: session.rawValue)
        await refresh(session.rawValue)
        pump()
    }

    func retryAnalysis(_ session: SessionID) async {
        guard let store else { return }
        try? await store.retry(.analyze, for: session.rawValue)
        await refresh(session.rawValue)
        pump()
    }

    /// Waits until nothing is running and nothing can start (the overnight task's completion point).
    func drain() async {
        await activate()
        pump()
        guard running != nil || pumping else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    /// Stops the running stage at its saved progress (background time ran out, or the app left the
    /// foreground on the iOS 18 path).
    func interruptRunning() {
        stop(.interrupt)
    }

    // MARK: Scheduling

    private func pump() {
        guard availability != .unavailable, running == nil, !pumping, let store else { return }
        pumping = true
        Task {
            while running == nil {
                let decision = await store.next(under: monitor.conditions, stages: Self.scheduledStages)
                guard case .run(let stage, let session) = decision else {
                    if case .hold(let reason) = decision { hold = reason } else { hold = nil }
                    break
                }
                hold = nil
                guard await begin(stage, session, store: store) else { break }
            }
            pumping = false
            notifyIdleIfSettled()
        }
    }

    /// Starts `stage`; returns false when nothing more should be tried now.
    private func begin(_ stage: ProcessingStage, _ session: String, store: ProcessingQueueStore) async -> Bool {
        if stage == .analyze, analyzers.isEmpty {
            // Honest by default: with nothing registered the stage says so instead of pretending.
            do { try await store.markUnavailable(.analyze, for: session, reason: .noAnalyzerRegistered) } catch { return false }
            await refresh(session)
            return true
        }
        do {
            try await store.start(stage, for: session, under: monitor.conditions)
        } catch ProcessingQueueError.held(let reason) {
            hold = reason
            return false
        } catch {
            log.error("start failed: \(String(describing: error), privacy: .public)")
            return false
        }
        await refresh(session)
        let saved = jobs[session]?[stage].progress ?? 0
        let attempt = jobs[session]?[stage].attempts ?? 1
        let task = Task<Void, Never> { [weak self] in
            await self?.perform(stage, session, from: saved, attempt: attempt, store: store)
        }
        running = Running(session: session, stage: stage, task: task)
        if stage == .analyze { ProcessingBackgroundTasks.beginContinuedProcessing(for: SessionID(rawValue: session), scheduler: self) }
        return true
    }

    private func perform(_ stage: ProcessingStage, _ session: String, from saved: Double, attempt: Int,
                         store: ProcessingQueueStore) async {
        let report: @Sendable (Double) async throws -> Void = { [weak self] progress in
            try Task.checkCancellation()
            try await store.report(stage, for: session, progress: progress)
            await self?.progressed(session, stage)
        }
        do {
            switch stage {
            case .prepareReplay:
                guard let library else { throw PrepareReplayStage.Failure(reason: .originalMissing) }
                try await PrepareReplayStage.run(SessionID(rawValue: session), library: library, from: saved, report: report)
            case .analyze:
                try await runAnalyzers(session, from: saved, attempt: attempt, report: report)
            case .backup:
                break
            }
            try Task.checkCancellation()
            try await store.complete(stage, for: session)
        } catch {
            await settle(stage, session, after: error, store: store)
        }
        await finish(session)
    }

    /// Analyzers run in order; the stage's progress spans them evenly, so a saved resume point maps back
    /// to an analyzer and its own progress.
    private func runAnalyzers(_ session: String, from saved: Double, attempt: Int,
                              report: @escaping @Sendable (Double) async throws -> Void) async throws {
        let count = Double(analyzers.count)
        let start = min(analyzers.count - 1, Int((saved * count).rounded(.down)))
        for index in start..<analyzers.count {
            let local = index == start ? saved * count - Double(index) : 0
            try await analyzers[index].analyze(SessionID(rawValue: session), attempt: attempt, from: local) { progress in
                try await report((Double(index) + progress) / count)
            }
        }
    }

    private func settle(_ stage: ProcessingStage, _ session: String, after error: any Error, store: ProcessingQueueStore) async {
        let cancelled = error is CancellationError || Task.isCancelled
        switch (cancelled, stopReason) {
        case (true, .pause):
            try? await store.pauseAnalysis(for: session)
        case (true, _):
            try? await store.interrupt(stage, for: session)
        default:
            let reason = (error as? PrepareReplayStage.Failure)?.reason ?? .analyzerFailed
            log.error("\(stage.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            try? await store.fail(stage, for: session, reason: reason)
        }
    }

    private func finish(_ session: String) async {
        await refresh(session)
        let stage = running?.stage
        running = nil
        stopReason = nil
        if stage == .analyze { ProcessingBackgroundTasks.endContinuedProcessing(success: jobs[session]?.analyze.status == .done) }
        pump()
    }

    private func stop(_ reason: StopReason) {
        guard let running else { return }
        stopReason = reason
        running.task.cancel()
    }

    private func progressed(_ session: String, _ stage: ProcessingStage) async {
        await refresh(session)
        if stage == .analyze, let progress = jobs[session]?.analyze.progress {
            ProcessingBackgroundTasks.updateContinuedProcessing(progress: progress)
        }
    }

    private func conditionsChanged(_ conditions: ProcessingConditions) {
        Task {
            try? await store?.updateBackup(conditions.backup)
            await refreshAll()
            if let running, ProcessingQueue.hold(for: running.stage, under: conditions) != nil { stop(.interrupt) }
            pump()
        }
    }

    private func backgroundChanged(_ background: Bool) {
        if background {
            if !continuesInBackground { stop(.interrupt) }
            if jobs.values.contains(where: { $0.analyze.status == .queued || $0.prepareReplay.status == .queued }) {
                ProcessingBackgroundTasks.scheduleOvernight()
            }
        } else {
            pump()
        }
    }

    /// The system declined a continued-processing task: this run behaves like the iOS 18 path.
    func continuedProcessingRefused() { continuesInBackground = false }

    private func refresh(_ session: String) async {
        jobs[session] = await store?.job(session)
    }

    private func refreshAll() async {
        if let store { jobs = await store.queue.jobs }
    }

    private func notifyIdleIfSettled() {
        guard running == nil, !pumping else { return }
        let waiters = idleWaiters
        idleWaiters = []
        waiters.forEach { $0.resume() }
    }
}
