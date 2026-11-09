import Foundation
import JovraCore

/// The one RenderJob state machine for local and cloud jobs (STU-04), driven by the transition contract
/// `spec/studio/contracts/render-job-transitions.v1.json` exactly as `spec/reference/studio/jobstate.py` reads it.
///
/// `checkTransition` decides one step; `replay` re-runs a stored job's whole history and requires the stored state,
/// resume stage and attempt to equal the result. A stored resume stage is checked, never trusted: it must be a stage
/// the current state can return to (`pausableFrom`, `retryableFrom`, `budgetExceededFrom`) and is absent in every other
/// state, so `ready`, `deleted` or a terminal state can never be resumed into. A retry uses up an attempt; terminal
/// states accept only deletion; paid stages need a reservation; `ready` needs a verified delivered artifact.
///
/// Local jobs (`Mode.local`) run the same contract with its cloud-only states removed: no quote, consent, upload,
/// queue or budget states, so a local `draft` goes straight to the first stage that follows them (`normalizing`), and
/// nothing a local job does spends a reservation. `ready` still needs a verified artifact.
public struct RenderJobMachine: Sendable {
    public enum Mode: String, Sendable, CaseIterable {
        case cloud
        case local
    }

    /// The fields a transition reads and writes. `resumeStage` is any state, so a stored `ready` or `deleted` resume
    /// stage can be represented and refused (`badResumeStage`) rather than lost in decoding.
    public struct Fields: Equatable, Sendable {
        public var state: RenderJobState
        public var resumeStage: RenderJobState?
        public var attempt: Int
        public var maxAttempts: Int

        public init(state: RenderJobState, resumeStage: RenderJobState? = nil, attempt: Int = 1, maxAttempts: Int = 3) {
            self.state = state
            self.resumeStage = resumeStage
            self.attempt = attempt
            self.maxAttempts = maxAttempts
        }
    }

    /// States that exist only because a cloud job is quoted, consented, uploaded, queued on a worker or budgeted.
    public static let cloudOnlyStates: Set<RenderJobState> = [
        .quoted, .consented, .uploadPending, .uploading, .queued, .quoteExpired, .budgetExceeded,
    ]

    public let contract: RenderJobTransitions
    public let mode: Mode

    private let states: Set<RenderJobState>
    private let terminal: Set<RenderJobState>
    private let forward: [RenderJobState: [RenderJobState]]
    private let pausableFrom: Set<RenderJobState>
    private let retryableFrom: Set<RenderJobState>
    private let terminalFailureFrom: Set<RenderJobState>
    private let budgetExceededFrom: Set<RenderJobState>
    private let reservationRequiredFrom: Set<RenderJobState>

    public init(contract: RenderJobTransitions, mode: Mode = .cloud) throws(LedgerRejection) {
        var forward: [RenderJobState: [RenderJobState]] = [:]
        for (from, targets) in contract.forward {
            guard let state = RenderJobState(rawValue: from) else {
                throw LedgerRejection(.unknownState, "the transition contract's forward map names \(from.debugDescription)")
            }
            forward[state] = targets
        }
        let removed = mode == .local ? Self.cloudOnlyStates : []
        func keep(_ list: [RenderJobState]) -> Set<RenderJobState> { Set(list).subtracting(removed) }
        self.contract = contract
        self.mode = mode
        self.states = keep(contract.states)
        self.terminal = Set(contract.terminal)
        self.forward = mode == .local ? Self.skipping(removed, in: forward) : forward
        self.pausableFrom = keep(contract.pausableFrom)
        self.retryableFrom = keep(contract.retryableFrom)
        self.terminalFailureFrom = keep(contract.terminalFailureFrom)
        self.budgetExceededFrom = keep(contract.budgetExceededFrom)
        self.reservationRequiredFrom = mode == .local ? [] : Set(contract.reservationRequiredFrom)
    }

    /// The contract's state named `name`, or `unknownState` (the boundary for a stored or received state string).
    public static func state(named name: String) throws(LedgerRejection) -> RenderJobState {
        guard let state = RenderJobState(rawValue: name) else {
            throw LedgerRejection(.unknownState, "unknown state \(name.debugDescription)")
        }
        return state
    }

    /// The stages a job in `state` may remember as its resume stage (empty: it must remember none).
    public func resumeStages(for state: RenderJobState) -> Set<RenderJobState> {
        switch state {
        case .paused: pausableFrom
        case .failedRetryable: retryableFrom
        case .budgetExceeded: budgetExceededFrom
        default: []
        }
    }

    /// The forward targets of `state` in this mode (local: the cloud-only states skipped).
    public func forwardTargets(of state: RenderJobState) -> [RenderJobState] { forward[state] ?? [] }

    /// One step, or the rejection `jobstate.Machine.check_transition` gives, in the same order of checks.
    public func checkTransition(_ job: Fields, to: RenderJobState, hasReservation: Bool,
                                verifiedArtifact: Bool) throws(LedgerRejection) -> Fields {
        let state = job.state
        try require(states.contains(to), stateCode(to), "\(to.rawValue) is not a state of a \(mode.rawValue) job")
        try require(states.contains(state), stateCode(state), "\(state.rawValue) is not a state of a \(mode.rawValue) job")
        let allowed = resumeStages(for: state)
        if !allowed.isEmpty {
            try require(job.resumeStage.map(allowed.contains) == true, .badResumeStage,
                        "\(state.rawValue) cannot resume to \(job.resumeStage?.rawValue ?? "null")")
        } else {
            try require(job.resumeStage == nil, .badResumeStage, "\(state.rawValue) remembers no resume stage")
        }
        var next = Fields(state: to, resumeStage: job.resumeStage, attempt: job.attempt, maxAttempts: job.maxAttempts)
        if to == .deleted {
            try require(state != .deleted, .terminalState, "a deleted job accepts no transition")
            next.resumeStage = nil
            return next
        }
        try require(!terminal.contains(state), .terminalState, "\(state.rawValue) is terminal")
        switch to {
        case .canceled:
            next.resumeStage = nil
            return next
        case .paused:
            try require(pausableFrom.contains(state), .illegalTransition, "cannot pause from \(state.rawValue)")
            next.resumeStage = state
            return next
        case .failedRetryable:
            try require(retryableFrom.contains(state), .illegalTransition, "cannot fail retryably from \(state.rawValue)")
            next.resumeStage = state
            return next
        case .failedTerminal:
            try require(terminalFailureFrom.contains(state), .illegalTransition, "cannot fail from \(state.rawValue)")
            next.resumeStage = nil
            return next
        case .budgetExceeded:
            try require(budgetExceededFrom.contains(state), .illegalTransition, "no budget check at \(state.rawValue)")
            next.resumeStage = state
            return next
        default:
            break
        }
        if (state == .paused || state == .failedRetryable) && to == job.resumeStage {
            if state == .failedRetryable {
                try require(job.attempt < job.maxAttempts, .retriesExhausted, "no attempts left; fail terminally")
                next.attempt = job.attempt + 1
            }
            next.resumeStage = nil
            try guards(to, hasReservation: hasReservation, verifiedArtifact: verifiedArtifact)
            return next
        }
        try require(forwardTargets(of: state).contains(to), .illegalTransition, "\(state.rawValue) -> \(to.rawValue) is not allowed")
        if state == .quoteExpired || state == .budgetExceeded {
            next.resumeStage = nil   // a re-quote starts a new consent; nothing is resumed automatically
        }
        try guards(to, hasReservation: hasReservation, verifiedArtifact: verifiedArtifact)
        return next
    }

    /// Re-runs a RenderJob record's history (`jobstate.Machine.replay`). `verifiedArtifact` must be resolved from the
    /// delivered artifacts (`verifiedArtifact(for:artifacts:)`), never from the id list alone.
    @discardableResult
    public func replay(_ job: RenderJob, verifiedArtifact: Bool) throws(LedgerRejection) -> Fields {
        let history = job.history
        try require(history.first.map { $0.from.value == nil && $0.to == .draft } == true, .badHistory,
                    "history starts with null -> draft")
        var current = Fields(state: .draft, resumeStage: nil, attempt: 1, maxAttempts: job.maxAttempts)
        let hasReservation = job.reservationId.value != nil
        var previous = try StudioTimestamp(history[0].at)
        for (index, step) in history.enumerated().dropFirst() {
            try require(step.seq == index && step.from.value == current.state, .badHistory,
                        "history step \(index) does not continue from \(current.state.rawValue)")
            let at = try StudioTimestamp(step.at)
            try require(at >= previous, .badHistory, "history timestamps go backwards")
            previous = at
            current = try checkTransition(current, to: step.to, hasReservation: hasReservation, verifiedArtifact: verifiedArtifact)
        }
        try require(job.state == current.state, .stateMismatch, "stored state \(job.state.rawValue) but history gives \(current.state.rawValue)")
        try require(job.resumeStage.value?.rawValue == current.resumeStage?.rawValue, .stateMismatch,
                    "stored resumeStage \(job.resumeStage.value?.rawValue ?? "null") but history gives \(current.resumeStage?.rawValue ?? "null")")
        try require(job.attempt == current.attempt, .stateMismatch, "stored attempt \(job.attempt) but history gives \(current.attempt)")
        if let progress = job.stageProgress.value {
            try require(progress.stage == job.state, .stateMismatch, "stage progress is reported for the active stage only")
        }
        return current
    }

    /// The `verifiedArtifact` flag for `replay`: every listed artifact exists, belongs to this job and passed
    /// verification, and there is at least one (`bundle.verified_artifact_for`). An id is not an artifact.
    public static func verifiedArtifact(for job: RenderJob, artifacts: [DeliveredArtifact]) -> Bool {
        let byId = Dictionary(artifacts.map { ($0.artifactId, $0) }, uniquingKeysWith: { first, _ in first })
        return !job.deliveredArtifactIds.isEmpty && job.deliveredArtifactIds.allSatisfy { id in
            guard let artifact = byId[id] else { return false }
            return artifact.jobId.value == job.jobId && artifact.verification.status == .passed
        }
    }

    private func guards(_ to: RenderJobState, hasReservation: Bool, verifiedArtifact: Bool) throws(LedgerRejection) {
        if reservationRequiredFrom.contains(to) {
            try require(hasReservation, .reservationRequired, "\(to.rawValue) spends and needs an accepted reservation")
        }
        if to == .ready {
            try require(verifiedArtifact, .unverifiedReady, "ready needs a verified delivered artifact")
        }
    }

    /// A state outside this machine: a cloud-only state on a local job, otherwise not a contract state.
    private func stateCode(_ state: RenderJobState) -> LedgerRejectCode {
        mode == .local && Self.cloudOnlyStates.contains(state) ? .cloudOnlyState : .unknownState
    }

    private func require(_ condition: Bool, _ code: LedgerRejectCode, _ message: @autoclosure () -> String) throws(LedgerRejection) {
        try LedgerRejection.require(condition, code, message())
    }

    /// The forward map with `removed` states bypassed: an edge into a removed state is replaced by that state's own
    /// targets, transitively; removed states lose their own edges.
    private static func skipping(_ removed: Set<RenderJobState>,
                                 in forward: [RenderJobState: [RenderJobState]]) -> [RenderJobState: [RenderJobState]] {
        func expand(_ state: RenderJobState, _ seen: Set<RenderJobState>) -> [RenderJobState] {
            guard removed.contains(state) else { return [state] }
            guard !seen.contains(state) else { return [] }
            return (forward[state] ?? []).flatMap { expand($0, seen.union([state])) }
        }
        var out: [RenderJobState: [RenderJobState]] = [:]
        for (from, targets) in forward where !removed.contains(from) {
            var list: [RenderJobState] = []
            for target in targets.flatMap({ expand($0, []) }) where !list.contains(target) { list.append(target) }
            out[from] = list
        }
        return out
    }
}

/// The stage a player sees on the render queue (ST38, stories 193 and 194). Every percentage belongs to one of these;
/// there is deliberately no analysis stage: `analyzing` gathers the bound points, keepers and notes for the plan
/// (v1 runs no vision analysis), so it folds into "Build film" with planning and rendering.
public enum RenderJobStage: String, CaseIterable, Sendable {
    case upload
    case alignAngles
    case buildFilm
    case verifyExport

    /// The visible stage a working state belongs to; nil for states that are not a stage at work (draft, quoted,
    /// consented, ready, paused, failures, canceled, deleted).
    public init?(state: RenderJobState) {
        switch state {
        case .uploadPending, .uploading: self = .upload
        case .queued, .normalizing, .syncing: self = .alignAngles
        case .analyzing, .planning, .previewRendering, .awaitingReview, .finalRendering: self = .buildFilm
        case .verifying: self = .verifyExport
        default: return nil
        }
    }
}
