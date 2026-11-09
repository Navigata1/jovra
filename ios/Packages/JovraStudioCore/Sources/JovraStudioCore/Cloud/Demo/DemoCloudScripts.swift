import Foundation
import JovraCore

/// The demo's job transcripts, built from the committed Sample records and stepped through `RenderJobMachine`, so a
/// transcript the job contract would refuse cannot be built at all.
///
/// The demo itself never creates a job, a reservation or an upload: its transcripts replay the Sample records of
/// `spec/studio/fixtures/records` (`render-job.queue-sample.json`, `render-job.ready.json`), which are Sample
/// test-environment jobs held by Sample reservations. Failure scenarios branch from those histories at the point the
/// failure happens. Times continue the fixtures' own clock; nothing reads the device clock.
struct DemoCloudScripts {
    /// One recorded change: a transition (with the stage progress it reported), or only a new notice.
    struct Step {
        var to: RenderJobState?
        var at: String
        var reason: String
        var percent: Int?
        var facts: JobStageFacts
        var notice: JobNotice?

        static func move(_ to: RenderJobState, _ at: String, _ reason: String, percent: Int? = nil,
                         facts: JobStageFacts, notice: JobNotice? = nil) -> Step {
            Step(to: to, at: at, reason: reason, percent: percent, facts: facts, notice: notice)
        }

        static func notice(_ notice: JobNotice, facts: JobStageFacts) -> Step {
            Step(to: nil, at: "", reason: "", percent: nil, facts: facts, notice: notice)
        }
    }

    /// The ST38 sources: three 60-minute angles of 3.6 GB each, 10.8 GB in all (`quote.sample-illustrative.json`
    /// line items; illustrative metadata, no bytes bundled).
    static let sourceIds = ["camera-1", "camera-2", "camera-3"]
    static let sourceBytes = 3_600_000_000
    static let uploadBytes = 10_800_000_000
    /// `usage-reservation.held.json` capCredits: the Sample cap the budget scenario stops at.
    static let queueReservationCapCredits = 4
    /// ST37 above-cap: a spending limit one credit under the Sample quote's 4-credit cap.
    static let aboveCapLimitCredits = 3
    /// ST38 paused: "Paused · 2.1 of 10.8 GB".
    static let pausedBytes = 2_100_000_000
    /// Partial upload: cameras 1 and 2 confirmed, camera 3 confirmed through part 40.
    static let partialCamera3Parts = 40

    static let notUploaded = facts(sources: 0, bytes: 0, reviewed: false)
    static let uploaded = facts(sources: 3, bytes: uploadBytes, reviewed: false)
    static let aligned = facts(sources: 3, bytes: uploadBytes, reviewed: true)
    static let paused = facts(sources: 0, bytes: pausedBytes, reviewed: false)
    static let partial = facts(sources: 2, bytes: 2 * sourceBytes + partialCamera3Parts * UploadSession.partSizeBytes,
                               reviewed: false)

    static func facts(sources: Int, bytes: Int, reviewed: Bool) -> JobStageFacts {
        JobStageFacts(sourceCount: 3, sourcesUploaded: sources, uploadBytes: uploadBytes, bytesUploaded: bytes,
                      alignmentReviewed: reviewed)
    }

    let queueJob: RenderJob
    let readyJob: RenderJob
    let machine: RenderJobMachine

    init(queueJob: RenderJob, readyJob: RenderJob, machine: RenderJobMachine) {
        self.queueJob = queueJob
        self.readyJob = readyJob
        self.machine = machine
    }

    /// The Sample job a scenario shows, or nil when it has none (not signed in).
    func snapshots(for scenario: DemoCloudScenario) throws(LedgerRejection) -> [JobSnapshot] {
        let queue = recordedSteps(of: queueJob)
        let accepted = 3   // the stream starts once the job is accepted: upload_pending
        let late = "2026-10-07T23:16:00Z"
        switch scenario {
        case .queue:
            return try build(queueJob, queue, from: accepted)
        case .paused:
            return try build(queueJob, Array(queue[...4]) + [.move(.paused, "2026-10-07T22:55:00Z", "owner-paused", facts: Self.paused)],
                             from: accepted)
        case .retryable:
            return try build(queueJob, queue + [
                .move(.failedRetryable, late, "lease-lost", facts: Self.aligned),
                .move(.previewRendering, "2026-10-07T23:17:00Z", "retry", facts: Self.aligned),
            ], from: accepted)
        case .terminal:
            return try build(queueJob, queue + [.move(.failedTerminal, late, "render-failed", facts: Self.aligned)], from: accepted)
        case .canceled:
            return try build(queueJob, queue + [
                .move(.canceled, late, "owner-canceled", facts: Self.aligned, notice: .removingTemporaryCopies),
                .notice(.temporaryCopiesRemoved, facts: Self.aligned),
            ], from: accepted)
        case .budgetExhausted:
            return try build(queueJob, queue + [
                .move(.budgetExceeded, late, "cap-reached", facts: Self.aligned,
                      notice: .stoppedAtLimit(capCredits: Self.queueReservationCapCredits)),
            ], from: accepted)
        case .quoteExpired:
            return try build(unreserved(queueJob), Array(queue[...1]) + [
                .move(.quoteExpired, "2026-10-07T23:15:00Z", "quote-expired", facts: Self.notUploaded),
            ], from: 0)
        case .aboveCap:
            return try build(unreserved(queueJob), Array(queue[...1]), from: 0)
        case .notSignedIn:
            return []
        case .partialUpload:
            return try build(queueJob, Array(queue[...4]) + [
                .move(.failedRetryable, "2026-10-07T23:01:00Z", "upload-interrupted", facts: Self.partial),
            ], from: accepted)
        case .expiredLink, .revokedAccess, .deletionRunning, .deletionFailed:
            let ready = recordedSteps(of: readyJob)
            return try build(readyJob, ready, from: ready.count - 1)
        }
    }

    /// A record's own history as steps, with the stage facts each state implies and its stored stage progress on the
    /// last step.
    private func recordedSteps(of job: RenderJob) -> [Step] {
        job.history.enumerated().map { index, item in
            let percent = index == job.history.count - 1 ? job.stageProgress.value?.percent : nil
            return .move(item.to, item.at, item.reason, percent: percent, facts: Self.facts(after: item.to, in: job))
        }
    }

    /// Before the upload finishes nothing is uploaded; after it, everything is; after alignment, it is reviewed
    /// (the Sample sync map is the reviewed record, `records/sync-map.json`).
    private static func facts(after state: RenderJobState, in job: RenderJob) -> JobStageFacts {
        let order = job.history.map(\.to)
        let reached = { (target: RenderJobState) in order.firstIndex(of: target).map { i in
            order.firstIndex(of: state).map { $0 >= i } ?? false } ?? false }
        if state == .ready || reached(.planning) || reached(.analyzing) { return aligned }
        if reached(.queued) { return uploaded }
        return notUploaded
    }

    /// The same Sample job before any reservation existed (it never got past its quote).
    private func unreserved(_ job: RenderJob) -> RenderJob {
        var copy = job
        copy.reservationId = .null
        return copy
    }

    /// Steps `steps` from `null -> draft` through the machine and returns the snapshots from step `from` on.
    func build(_ base: RenderJob, _ steps: [Step], from: Int) throws(LedgerRejection) -> [JobSnapshot] {
        guard let first = steps.first, first.to == .draft else {
            throw LedgerRejection(.badHistory, "a transcript starts with null -> draft")
        }
        var fields = RenderJobMachine.Fields(state: .draft, maxAttempts: base.maxAttempts)
        var history = [RenderJobHistoryItem(seq: 0, from: .null, to: .draft, at: first.at, reason: first.reason)]
        var snapshots: [JobSnapshot] = []
        var percent = first.percent
        for (index, step) in steps.enumerated() {
            if index > 0, let to = step.to {
                fields = try machine.checkTransition(fields, to: to, hasReservation: base.reservationId.value != nil,
                                                     verifiedArtifact: to == .ready && !base.deliveredArtifactIds.isEmpty)
                history.append(RenderJobHistoryItem(seq: history.count, from: .value(history[history.count - 1].to),
                                                    to: to, at: step.at, reason: step.reason))
                percent = step.percent
            }
            if index >= from {
                snapshots.append(JobSnapshot(job: record(base, fields, history, percent: percent), facts: step.facts,
                                             notice: step.notice))
            }
        }
        return snapshots
    }

    /// The RenderJob record after `history`.
    func record(_ base: RenderJob, _ fields: RenderJobMachine.Fields, _ history: [RenderJobHistoryItem],
                percent: Int?) -> RenderJob {
        var job = base
        job.state = fields.state
        job.resumeStage = ContractNullable(fields.resumeStage.flatMap { RenderJobResumeStage(rawValue: $0.rawValue) })
        job.attempt = fields.attempt
        job.stageProgress = ContractNullable(percent.map { RenderJobStageProgress(stage: fields.state, percent: $0, sample: true) })
        job.deliveredArtifactIds = fields.state == .ready ? base.deliveredArtifactIds : []
        job.history = history
        return job
    }

    /// One control step (pause, resume, cancel) on the latest snapshot, a minute after its last history entry.
    func control(_ last: JobSnapshot, to: RenderJobState, reason: String, notice: JobNotice?,
                 facts: JobStageFacts) throws(LedgerRejection) -> JobSnapshot {
        let job = last.job
        let current = RenderJobMachine.Fields(state: job.state,
                                              resumeStage: job.resumeStage.value.flatMap { RenderJobState(rawValue: $0.rawValue) },
                                              attempt: job.attempt, maxAttempts: job.maxAttempts)
        let next = try machine.checkTransition(current, to: to, hasReservation: job.reservationId.value != nil,
                                               verifiedArtifact: false)
        let previous = try StudioTimestamp(job.history[job.history.count - 1].at)
        var history = job.history
        history.append(RenderJobHistoryItem(seq: history.count, from: .value(job.state), to: to,
                                            at: Self.text(millis: previous.millisecondsSinceEpoch + 60_000), reason: reason))
        return JobSnapshot(job: record(job, next, history, percent: nil), facts: facts, notice: notice)
    }

    /// `yyyy-MM-ddTHH:mm:ssZ` for a whole-second instant.
    static func text(millis: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(millis / 1_000)))
    }
}
