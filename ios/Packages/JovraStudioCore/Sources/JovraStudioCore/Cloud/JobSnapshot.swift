import Foundation

/// One report of a job (`CloudClient.job`): the durable RenderJob record as it is now, and the four player-facing
/// stages derived from it (ST38, stories 193 and 194).
public struct JobSnapshot: Equatable, Sendable {
    public let job: RenderJob
    public let stages: [JobStageSnapshot]
    public let notice: JobNotice?
    /// What the upload and alignment reported, which the stages are derived from.
    public let facts: JobStageFacts

    public init(job: RenderJob, facts: JobStageFacts, notice: JobNotice? = nil) {
        self.job = job
        self.facts = facts
        self.stages = JobStageSnapshot.stages(for: job, facts: facts)
        self.notice = notice
    }

    public var jobId: String { job.jobId }
    public var state: RenderJobState { job.state }
    public var isSample: Bool { job.sample }

    /// The stage at work, paused, retrying, stopped or where the job ended; nil before upload and after delivery.
    public var currentStage: JobStageSnapshot? { stages.first { $0.status != .complete && $0.status != .queued } }
}

/// What the stage list needs beyond the record: what the upload and alignment reported.
public struct JobStageFacts: Codable, Equatable, Sendable {
    public var sourceCount: Int
    public var sourcesUploaded: Int
    public var uploadBytes: Int
    public var bytesUploaded: Int
    public var alignmentReviewed: Bool

    public init(sourceCount: Int, sourcesUploaded: Int, uploadBytes: Int, bytesUploaded: Int, alignmentReviewed: Bool) {
        self.sourceCount = sourceCount
        self.sourcesUploaded = sourcesUploaded
        self.uploadBytes = uploadBytes
        self.bytesUploaded = bytesUploaded
        self.alignmentReviewed = alignmentReviewed
    }
}

/// A job-level message that is not a stage state (ST38 Canceled, Budget exhausted).
public enum JobNotice: Codable, Equatable, Sendable {
    case removingTemporaryCopies
    case temporaryCopiesRemoved
    /// The job stopped at the player's cap; only the player raises it.
    case stoppedAtLimit(capCredits: Int)
}

public enum JobStageStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case inProgress
    case paused
    /// A retryable failure: the stage will try again (ST38 "Trying again · attempt 2 of 3").
    case retrying
    /// Stopped at the spending limit.
    case stopped
    case failed
    case canceled
    case complete
}

/// One of the four stages with its own state. `percent` is this stage's own progress ("42% of this step") and only
/// ever appears on the stage at work; no total-job percentage exists anywhere.
public struct JobStageSnapshot: Codable, Equatable, Sendable {
    public var stage: RenderJobStage
    public var status: JobStageStatus
    public var percent: Int?
    /// Upload only: sources and bytes the server confirmed.
    public var sourcesDone: Int?
    public var sourceCount: Int?
    public var bytesDone: Int?
    public var bytesTotal: Int?
    /// Align angles only, once complete: whether the alignment was reviewed.
    public var reviewed: Bool?

    public var title: String { stage.title }

    /// The four stages of a cloud job, derived from the record alone plus the upload and alignment facts.
    public static func stages(for job: RenderJob, facts: JobStageFacts) -> [JobStageSnapshot] {
        let (current, status) = position(of: job)
        let all = RenderJobStage.allCases
        let currentIndex = current.flatMap { all.firstIndex(of: $0) }
        return all.enumerated().map { index, stage in
            let stageStatus: JobStageStatus = switch (job.state, currentIndex) {
            case (.ready, _), (.deleted, _): .complete
            case (_, nil): .queued
            case (_, let i?): index < i ? .complete : index == i ? status : .queued
            }
            var snapshot = JobStageSnapshot(stage: stage, status: stageStatus)
            if stageStatus == .inProgress, let progress = job.stageProgress.value,
               RenderJobStage(state: progress.stage) == stage {
                snapshot.percent = progress.percent
            }
            switch stage {
            case .upload:
                let done = stageStatus == .complete
                snapshot.sourcesDone = done ? facts.sourceCount : facts.sourcesUploaded
                snapshot.sourceCount = facts.sourceCount
                snapshot.bytesDone = done ? facts.uploadBytes : facts.bytesUploaded
                snapshot.bytesTotal = facts.uploadBytes
            case .alignAngles where stageStatus == .complete:
                snapshot.reviewed = facts.alignmentReviewed
            default:
                break
            }
            return snapshot
        }
    }

    /// The stage the job is in (or stopped in) and that stage's status.
    private static func position(of job: RenderJob) -> (RenderJobStage?, JobStageStatus) {
        if let stage = RenderJobStage(state: job.state) { return (stage, .inProgress) }
        let resumed = job.resumeStage.value.flatMap { RenderJobState(rawValue: $0.rawValue) }.flatMap(RenderJobStage.init(state:))
        switch job.state {
        case .paused: return (resumed, .paused)
        case .failedRetryable: return (resumed, .retrying)
        case .budgetExceeded: return (resumed, .stopped)
        case .failedTerminal: return (lastStage(in: job), .failed)
        case .canceled: return (lastStage(in: job), .canceled)
        default: return (nil, .queued)
        }
    }

    /// The last stage the history entered (where a failed or canceled job stopped).
    private static func lastStage(in job: RenderJob) -> RenderJobStage? {
        job.history.reversed().lazy.compactMap { RenderJobStage(state: $0.to) }.first
    }

    init(stage: RenderJobStage, status: JobStageStatus) {
        self.stage = stage
        self.status = status
    }
}

extension RenderJobStage: Codable {
    /// The stage's name on ST38.
    public var title: String {
        switch self {
        case .upload: "Upload"
        case .alignAngles: "Align angles"
        case .buildFilm: "Build film"
        case .verifyExport: "Verify export"
        }
    }
}
