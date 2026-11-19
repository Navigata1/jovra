import Foundation

/// The independent stages a saved session goes through after capture or import (spec: ProcessingQueue).
/// No stage waits for another: each needs only the saved original, and a failure in one never blocks
/// or changes the others.
public enum ProcessingStage: String, Codable, CaseIterable, Sendable {
    case prepareReplay, analyze, backup
}

/// Why a stage is failed, unavailable or blocked. Stored as a code; the screen owns the words.
public enum ProcessingReason: String, Codable, Sendable {
    /// No analyzer is registered in this build (the analyze stage reports unavailable).
    case noAnalyzerRegistered
    /// A registered analyzer threw.
    case analyzerFailed
    /// The original could not be opened for replay.
    case mediaUnreadable
    /// The session's original is no longer on this device.
    case originalMissing
    /// No Google Drive archive is set up yet.
    case awaitingArchiveSetup
    /// The archive is connected but backups wait for Wi-Fi.
    case waitingForWiFi
}

/// One stage of one session. `progress` (0…1) is also the resume point: it is persisted with every
/// report, so work interrupted by an app kill continues from it.
public struct ProcessingStageState: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// Waiting its turn (or interrupted and waiting to resume).
        case queued
        case running
        /// Held by the player (analysis only).
        case paused
        case done
        case failed
        /// Cannot run in this build, with its reason.
        case unavailable
        /// Waiting on something outside JOVRA (the archive or Wi-Fi), with its reason.
        case blocked
    }

    public var status: Status
    public var progress: Double
    public var reason: ProcessingReason?
    /// How many times the stage has been started from the beginning (1 before any retry).
    public var attempts: Int

    public init(status: Status, progress: Double = 0, reason: ProcessingReason? = nil, attempts: Int = 1) {
        self.status = status; self.progress = progress; self.reason = reason; self.attempts = attempts
    }
}

/// The processing record for one session.
public struct ProcessingJob: Codable, Equatable, Sendable {
    public let sessionID: String
    /// Order of arrival, so sessions run in the order they were saved.
    public let sequence: Int
    public var originalSaved: Bool
    public var prepareReplay: ProcessingStageState
    public var analyze: ProcessingStageState
    public var backup: ProcessingStageState

    public subscript(stage: ProcessingStage) -> ProcessingStageState {
        get {
            switch stage {
            case .prepareReplay: prepareReplay
            case .analyze: analyze
            case .backup: backup
            }
        }
        set {
            switch stage {
            case .prepareReplay: prepareReplay = newValue
            case .analyze: analyze = newValue
            case .backup: backup = newValue
            }
        }
    }

    /// The session's analysis facet as this job describes it. The original facet is never derived
    /// from processing: a failed stage cannot change it.
    public var analysisFacet: SessionAnalysis {
        let state: SessionAnalysisState = switch analyze.status {
        case .queued, .blocked: .queued
        case .running: .running
        case .paused: .paused
        case .done: .done
        case .failed: .failed
        case .unavailable: .unavailable
        }
        return SessionAnalysis(state: state, reason: analyze.reason?.rawValue, runs: [])
    }
}

/// What the device allows right now. The app adapter reads it from the capture activity signal,
/// `ProcessInfo` and the archive service.
public struct ProcessingConditions: Equatable, Sendable {
    /// `ProcessInfo.ThermalState`, mirrored so this module stays Foundation-portable.
    public enum Thermal: Int, Comparable, Sendable {
        case nominal, fair, serious, critical
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Where a backup stands before any upload can start.
    public enum BackupReadiness: Equatable, Sendable {
        case awaitingSetup, waitingForWiFi, ready
    }

    public var captureActive: Bool
    public var thermal: Thermal
    public var externalPower: Bool
    public var lowPowerMode: Bool
    public var backup: BackupReadiness

    public init(captureActive: Bool, thermal: Thermal, externalPower: Bool, lowPowerMode: Bool, backup: BackupReadiness) {
        self.captureActive = captureActive; self.thermal = thermal; self.externalPower = externalPower
        self.lowPowerMode = lowPowerMode; self.backup = backup
    }
}

/// Why the queue is not starting anything although work is waiting.
public enum ProcessingHold: String, Equatable, Sendable {
    /// A recording is in progress: processing never competes with capture.
    case captureActive
    /// Thermal state is worse than fair.
    case tooWarm
    /// Low Power Mode is on and the phone is not charging (analysis only).
    case lowPower
}

public enum ProcessingDecision: Equatable, Sendable {
    case run(ProcessingStage, String)
    case hold(ProcessingHold)
    case idle
}

public enum ProcessingQueueError: Error, Equatable, Sendable {
    case unknownSession
    case originalNotSaved
    case held(ProcessingHold)
    case invalidTransition(ProcessingStage, ProcessingStageState.Status)
}

/// The pure, persistent state machine of the processing queue. It decides and records; it never does
/// the work (the scheduler adapter in the app does) and never touches the original.
public struct ProcessingQueue: Codable, Equatable, Sendable {
    public private(set) var jobs: [String: ProcessingJob] = [:]
    private var nextSequence = 0

    public init() {}

    public func job(_ sessionID: String) -> ProcessingJob? { jobs[sessionID] }

    /// Adds a session (idempotent). Calling it again with `originalSaved: true` records the save.
    public mutating func enqueue(_ sessionID: String, originalSaved: Bool) {
        if var existing = jobs[sessionID] {
            existing.originalSaved = existing.originalSaved || originalSaved
            jobs[sessionID] = existing
            return
        }
        jobs[sessionID] = ProcessingJob(
            sessionID: sessionID, sequence: nextSequence, originalSaved: originalSaved,
            prepareReplay: .init(status: .queued), analyze: .init(status: .queued),
            backup: .init(status: .blocked, reason: .awaitingArchiveSetup)
        )
        nextSequence += 1
    }

    public mutating func remove(_ sessionID: String) { jobs[sessionID] = nil }

    /// The next stage to start under `conditions`, oldest session first and stage order within it.
    /// `stages` limits the choice to the stages the caller runs (the archive service runs backups).
    public func next(under conditions: ProcessingConditions,
                     stages: Set<ProcessingStage> = Set(ProcessingStage.allCases)) -> ProcessingDecision {
        let waiting = jobs.values.sorted { $0.sequence < $1.sequence }.filter(\.originalSaved).flatMap { job in
            ProcessingStage.allCases.filter { stages.contains($0) && job[$0].status == .queued }.map { (job.sessionID, $0) }
        }
        guard !waiting.isEmpty else { return .idle }
        var firstHold: ProcessingHold?
        for (session, stage) in waiting {
            if let hold = Self.hold(for: stage, under: conditions) {
                firstHold = firstHold ?? hold
                continue
            }
            return .run(stage, session)
        }
        return firstHold.map(ProcessingDecision.hold) ?? .idle
    }

    /// Why `stage` may not start (or keep running) under `conditions`; nil when it may.
    public static func hold(for stage: ProcessingStage, under conditions: ProcessingConditions) -> ProcessingHold? {
        if conditions.captureActive { return .captureActive }
        if conditions.thermal > .fair { return .tooWarm }
        if stage == .analyze, conditions.lowPowerMode, !conditions.externalPower { return .lowPower }
        return nil
    }

    // MARK: Transitions

    public mutating func start(_ stage: ProcessingStage, for sessionID: String, under conditions: ProcessingConditions) throws {
        var job = try existing(sessionID)
        guard job.originalSaved else { throw ProcessingQueueError.originalNotSaved }
        if let hold = Self.hold(for: stage, under: conditions) { throw ProcessingQueueError.held(hold) }
        try expect(job[stage], in: [.queued], stage)
        job[stage].status = .running
        jobs[sessionID] = job
    }

    /// Records progress (the resume point). Progress never moves backwards and stops at 1.
    public mutating func report(_ stage: ProcessingStage, for sessionID: String, progress: Double) throws {
        var job = try existing(sessionID)
        try expect(job[stage], in: [.running], stage)
        job[stage].progress = min(1, max(job[stage].progress, progress))
        jobs[sessionID] = job
    }

    public mutating func complete(_ stage: ProcessingStage, for sessionID: String) throws {
        var job = try existing(sessionID)
        try expect(job[stage], in: [.running], stage)
        job[stage] = .init(status: .done, progress: 1, attempts: job[stage].attempts)
        jobs[sessionID] = job
    }

    public mutating func fail(_ stage: ProcessingStage, for sessionID: String, reason: ProcessingReason) throws {
        var job = try existing(sessionID)
        try expect(job[stage], in: [.running, .queued], stage)
        job[stage].status = .failed
        job[stage].reason = reason
        jobs[sessionID] = job
    }

    public mutating func markUnavailable(_ stage: ProcessingStage, for sessionID: String, reason: ProcessingReason) throws {
        var job = try existing(sessionID)
        try expect(job[stage], in: [.queued, .running, .unavailable], stage)
        job[stage].status = .unavailable
        job[stage].reason = reason
        jobs[sessionID] = job
    }

    /// The player holds analysis; its progress is kept.
    public mutating func pauseAnalysis(for sessionID: String) throws {
        var job = try existing(sessionID)
        try expect(job.analyze, in: [.queued, .running], .analyze)
        job.analyze.status = .paused
        jobs[sessionID] = job
    }

    /// Continues a paused analysis from its saved progress.
    public mutating func resumeAnalysis(for sessionID: String) throws {
        var job = try existing(sessionID)
        try expect(job.analyze, in: [.paused], .analyze)
        job.analyze.status = .queued
        jobs[sessionID] = job
    }

    /// Starts a failed (or unavailable) stage again from the beginning.
    public mutating func retry(_ stage: ProcessingStage, for sessionID: String) throws {
        var job = try existing(sessionID)
        try expect(job[stage], in: [.failed, .unavailable], stage)
        job[stage] = .init(status: .queued, attempts: job[stage].attempts + 1)
        jobs[sessionID] = job
    }

    /// Applies the archive's readiness to every backup stage that has not started.
    public mutating func updateBackup(_ readiness: ProcessingConditions.BackupReadiness) {
        for (id, var job) in jobs where [.queued, .blocked].contains(job.backup.status) {
            switch readiness {
            case .awaitingSetup: job.backup = .init(status: .blocked, reason: .awaitingArchiveSetup, attempts: job.backup.attempts)
            case .waitingForWiFi: job.backup = .init(status: .blocked, reason: .waitingForWiFi, attempts: job.backup.attempts)
            case .ready: job.backup = .init(status: .queued, attempts: job.backup.attempts)
            }
            jobs[id] = job
        }
    }

    /// After a relaunch nothing is running: interrupted stages are queued again at their saved progress.
    public mutating func recoverAfterRelaunch() {
        for (id, var job) in jobs {
            for stage in ProcessingStage.allCases where job[stage].status == .running {
                job[stage].status = .queued
            }
            jobs[id] = job
        }
    }

    private func existing(_ sessionID: String) throws -> ProcessingJob {
        guard let job = jobs[sessionID] else { throw ProcessingQueueError.unknownSession }
        return job
    }

    private func expect(_ state: ProcessingStageState, in allowed: [ProcessingStageState.Status], _ stage: ProcessingStage) throws {
        guard allowed.contains(state.status) else { throw ProcessingQueueError.invalidTransition(stage, state.status) }
    }
}
