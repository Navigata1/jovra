import Foundation

/// The demo adapter of SD11: in-process and deterministic. It replays the committed Sample transcripts
/// (`DemoCloudScripts`) for one `DemoCloudScenario`, quotes the illustrative Sample quote with charging disabled, and
/// never reserves, uploads, shares or charges (story 17). It holds no credential and has no network code: this folder
/// is checked in CI and by `CloudNoNetworkTests` for any networking type, and on Linux it does not even import the
/// networking module.
///
/// Pause, resume and cancel act on the Sample job in memory, stepped through `RenderJobMachine`, so ST38's controls
/// work in demo and refuse what the contract refuses; nothing persists between launches.
public actor DemoCloudClient: CloudClient {
    public nonisolated let scenario: DemoCloudScenario

    private let quoteRecord: Quote
    private let film: DeliveredArtifact
    private let scripts: DemoCloudScripts
    private var jobs: [String: [JobSnapshot]]

    public init(scenario: DemoCloudScenario = .queue) throws(CloudError) {
        self.scenario = scenario
        do {
            quoteRecord = try StudioContractCodec.decode(Quote.self, from: Data(DemoCloudFixtureSource.sampleQuote.utf8))
            film = try StudioContractCodec.decode(DeliveredArtifact.self, from: Data(DemoCloudFixtureSource.filmArtifact.utf8))
            let queue = try StudioContractCodec.decode(RenderJob.self, from: Data(DemoCloudFixtureSource.queueSampleJob.utf8))
            let ready = try StudioContractCodec.decode(RenderJob.self, from: Data(DemoCloudFixtureSource.readyJob.utf8))
            scripts = DemoCloudScripts(queueJob: queue, readyJob: ready,
                                       machine: try RenderJobMachine(contract: .bundled(), mode: .cloud))
        } catch let rejection as LedgerRejection {
            throw CloudError(rejection)
        } catch {
            throw .refused(code: "badFixture", message: "a bundled Sample record does not decode: \(error)")
        }
        let snapshots: [JobSnapshot]
        do { snapshots = try scripts.snapshots(for: scenario) } catch { throw CloudError(error) }
        jobs = snapshots.first.map { [$0.jobId: snapshots] } ?? [:]
    }

    /// The Sample job this scenario shows on ST38, or nil (not signed in).
    public nonisolated var sampleJobId: String? {
        switch scenario {
        case .notSignedIn: nil
        case .expiredLink, .revokedAccess, .deletionRunning, .deletionFailed: "job-film-01"
        default: "job-queue-38"
        }
    }

    public func mode() async -> CloudMode { .demo }

    public func identity() async throws(CloudError) -> CloudIdentity {
        scenario == .notSignedIn ? .signedOut : .demoProfile
    }

    // MARK: Quote and accept

    /// The illustrative Sample quote ("Sample quote $4 – $8, spending limit $12") for the Studio sample project.
    public func quote(_ request: CloudQuoteRequest) async throws(CloudError) -> CloudQuote {
        if scenario == .notSignedIn { throw .notSignedIn }
        guard request.projectId == quoteRecord.projectId else { throw .demoDisabled }
        let condition: CloudQuote.Condition = switch scenario {
        case .quoteExpired: .expired
        case .aboveCap: .aboveCap(spendingLimitCredits: DemoCloudScripts.aboveCapLimitCredits)
        default: .open
        }
        return CloudQuote(quote: quoteRecord, condition: condition, chargingEnabled: false)
    }

    /// Never reserves: the quote state machine of S12 puts every demo quote in `demoDisabled`, and this returns that,
    /// naming the Sample job ST38 shows instead (story 189).
    public func accept(_ quote: Quote, consent: QuoteConsent, capCredits: Int,
                       idempotencyKey: Ledger.Key) async throws(CloudError) -> AcceptResult {
        do {
            var state = try QuoteReservation(environment: .demo, spendingLimitCredits: max(0, capCredits))
            try state.request()
            try state.present(quoteRecord, at: StudioTimestamp(quoteRecord.createdAt))
            guard case .demoDisabled = state.state, state.reservationId == nil else {
                throw CloudError.refused(code: LedgerRejectCode.demoNeverReserves.rawValue, message: "demo never reserves")
            }
        } catch let error as CloudError {
            throw error
        } catch let rejection as LedgerRejection {
            throw CloudError(rejection)
        } catch {
            throw .demoDisabled
        }
        return .demoDisabled(sampleJob: sampleJobId)
    }

    // MARK: Upload

    /// Partial upload: cameras 1 and 2 are confirmed and camera 3 resumes after part 40. Every other scenario has no
    /// upload to open (the demo does not upload).
    public func openUpload(sourceId: String) async throws(CloudError) -> UploadSession {
        guard scenario == .partialUpload else { throw .demoDisabled }
        guard let index = DemoCloudScripts.sourceIds.firstIndex(of: sourceId) else { throw .unknownSource(sourceId) }
        var session = UploadSession(uploadId: "upload-sample-\(sourceId)", sourceId: sourceId,
                                    byteCount: DemoCloudScripts.sourceBytes, confirmedParts: [], completed: false, sample: true)
        let parts = index < 2 ? session.partCount : DemoCloudScripts.partialCamera3Parts
        session.confirmedParts = Array(1...parts)
        session.completed = index < 2
        return session
    }

    public func uploadPart(_ session: UploadSession, partNumber: Int) async throws(CloudError) -> UploadSession {
        throw .demoDisabled
    }

    public func completeUpload(_ session: UploadSession) async throws(CloudError) -> UploadSession {
        throw .demoDisabled
    }

    // MARK: Job

    public func job(_ jobId: String) async -> AsyncStream<JobSnapshot> {
        let snapshots = jobs[jobId] ?? []
        return AsyncStream { continuation in
            for snapshot in snapshots { continuation.yield(snapshot) }
            continuation.finish()
        }
    }

    public func pause(_ jobId: String) async throws(CloudError) -> JobSnapshot {
        let last = try latest(jobId)
        return try append(jobId, to: .paused, reason: "owner-paused", notice: nil, from: last)
    }

    /// Returns a paused or retrying job to the stage it remembers (a retry uses up an attempt). A job stopped at its
    /// limit resumes only through a new quote, so that is refused here, as the contract refuses it.
    public func resume(_ jobId: String) async throws(CloudError) -> JobSnapshot {
        let last = try latest(jobId)
        guard last.state == .paused || last.state == .failedRetryable,
              let stage = last.job.resumeStage.value.flatMap({ RenderJobState(rawValue: $0.rawValue) }) else {
            throw .refused(code: LedgerRejectCode.illegalTransition.rawValue,
                           message: "\(last.state.rawValue) has no stage to resume")
        }
        return try append(jobId, to: stage, reason: last.state == .paused ? "owner-resumed" : "retry", notice: nil, from: last)
    }

    public func cancel(_ jobId: String) async throws(CloudError) -> JobSnapshot {
        let last = try latest(jobId)
        return try append(jobId, to: .canceled, reason: "owner-canceled", notice: .removingTemporaryCopies, from: last)
    }

    // MARK: Artifacts and links

    public func artifacts(_ jobId: String) async throws(CloudError) -> [CloudArtifact] {
        let last = try latest(jobId)
        guard last.job.deliveredArtifactIds.contains(film.artifactId) else { return [] }
        return [CloudArtifact(record: film, shareLink: linkStatus, accessible: scenario != .revokedAccess)]
    }

    /// The demo has nothing in the cloud to download; with access revoked, the download says so.
    public func download(artifactId: String, resumingFrom byteOffset: Int) async -> AsyncThrowingStream<DownloadEvent, any Error> {
        let error: CloudError = artifactId != film.artifactId ? .unknownArtifact(artifactId)
            : scenario == .revokedAccess ? .accessRevoked : .demoDisabled
        return AsyncThrowingStream { $0.finish(throwing: error) }
    }

    public func shareLink(_ action: ShareLinkAction, artifactId: String) async throws(CloudError) -> ShareLinkStatus {
        guard artifactId == film.artifactId else { throw .unknownArtifact(artifactId) }
        if scenario == .revokedAccess { throw .accessRevoked }
        throw .demoDisabled
    }

    private var linkStatus: ShareLinkStatus {
        guard let link = film.delivery.shareLink.value else { return .none }
        switch scenario {
        case .expiredLink: return .expired(grantId: link.grantId, expiredAt: link.expiresAt)
        case .revokedAccess: return .revoked(grantId: link.grantId)
        default: return .active(grantId: link.grantId, issuedAt: link.issuedAt, expiresAt: link.expiresAt)
        }
    }

    // MARK: Deletion and export

    /// Deletion running or failed for the Sample film's cloud copies (three uploaded sources and the film);
    /// otherwise nothing is in the cloud to delete.
    public func deleteCloudCopies(projectId: String) async throws(CloudError) -> DeletionRequest {
        let status: DeletionRequest.Status = switch scenario {
        case .deletionRunning: .running(removed: 1, total: 4)
        case .deletionFailed: .failed(removed: 3, total: 4)
        default: .nothingToDelete
        }
        return DeletionRequest(requestId: "deletion-sample-01", scope: "project:\(projectId)", status: status, sample: true)
    }

    public func exportMyData() async throws(CloudError) -> DataExportRequest {
        DataExportRequest(requestId: "export-sample-01", status: .nothingInCloud, sample: true)
    }

    /// The demo profile is not an account, so there is no account to delete.
    public func deleteAccount() async throws(CloudError) -> DeletionRequest {
        throw .demoDisabled
    }

    // MARK: Helpers

    private func latest(_ jobId: String) throws(CloudError) -> JobSnapshot {
        guard let last = jobs[jobId]?.last else { throw .unknownJob(jobId) }
        return last
    }

    private func append(_ jobId: String, to: RenderJobState, reason: String, notice: JobNotice?,
                        from last: JobSnapshot) throws(CloudError) -> JobSnapshot {
        let next: JobSnapshot
        do { next = try scripts.control(last, to: to, reason: reason, notice: notice, facts: last.facts) } catch { throw CloudError(error) }
        jobs[jobId, default: []].append(next)
        return next
    }
}
