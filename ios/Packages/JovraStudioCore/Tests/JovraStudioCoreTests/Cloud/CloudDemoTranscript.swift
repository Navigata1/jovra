import Foundation
import JovraCore
import JovraStudioCore

/// The committed record of what the demo client reports for one scenario (`Cloud/Transcripts/<scenario>.json`): the
/// job's history once, every JobSnapshot of its stream (without repeating the history), and the result of every other
/// call a Studio screen makes in that state. `CloudDemoTranscriptTests` regenerates it through the public
/// `CloudClient` interface and requires it to equal the committed file.
///
/// To rewrite the files after an intended change: `JOVRA_RECORD_CLOUD_TRANSCRIPTS=1 swift test --filter Cloud`, then
/// review the diff.
struct CloudDemoTranscript: Codable, Equatable {
    enum Outcome<Value: Codable & Equatable>: Codable, Equatable {
        case ok(Value)
        case error(CloudError)
    }

    struct HistoryLine: Codable, Equatable {
        var seq: Int
        var from: String?
        var to: String
        var at: String
        var reason: String
    }

    struct SnapshotLine: Codable, Equatable {
        /// The last history entry this snapshot includes.
        var seq: Int
        var state: String
        var resumeStage: String?
        var attempt: Int
        var maxAttempts: Int
        var reservationId: String?
        var stageProgress: String?
        var deliveredArtifactIds: [String]
        var stages: [JobStageSnapshot]
        var notice: JobNotice?
    }

    struct QuoteLine: Codable, Equatable {
        var quoteId: String
        var environment: String
        var sample: Bool
        var illustrative: Bool
        var title: String
        var range: String?
        var limit: String?
        var condition: CloudQuote.Condition
        var chargingEnabled: Bool
    }

    struct ArtifactLine: Codable, Equatable {
        var artifactId: String
        var verified: Bool
        var accessible: Bool
        var shareLink: ShareLinkStatus
    }

    var transcript = "jovra.demo-cloud-transcript/1 (test golden file, not a shared contract)"
    var scenario: DemoCloudScenario
    var launchArguments: [String]
    var mode: CloudMode
    var identity: Outcome<CloudIdentity>
    var quote: Outcome<QuoteLine>
    var accept: Outcome<AcceptResult>
    var jobId: String?
    var history: [HistoryLine]
    var snapshots: [SnapshotLine]
    var artifacts: Outcome<[ArtifactLine]>?
    var uploads: [Outcome<UploadSession>]
    var shareLink: Outcome<ShareLinkStatus>?
    var download: Outcome<[DownloadEvent]>?
    var deleteCloudCopies: Outcome<DeletionRequest>
    var exportMyData: Outcome<DataExportRequest>
    var deleteAccount: Outcome<DeletionRequest>

    static let projectId = "sample-court-day"

    /// Records `client` (a demo client built from `scenario`'s launch arguments) call by call.
    static func record(_ scenario: DemoCloudScenario) async throws -> CloudDemoTranscript {
        let client = try CloudClients.make(configuration: CloudConfiguration(info: [CloudConfiguration.Key.environment: "demo"]),
                                           launchArguments: ["-AppleLanguages", "(en)"] + scenario.launchArguments)
        let quote = await result { () throws(CloudError) in try await client.quote(CloudQuoteRequest(projectId: projectId, planRevision: 1)) }
        let sampleQuote = try CloudFixtures.sampleQuote()
        let accept = await outcome { () throws(CloudError) in
            try await client.accept(sampleQuote, consent: CloudFixtures.consent, capCredits: sampleQuote.capCredits,
                                    idempotencyKey: Ledger.Key(projectId: projectId, planRevision: 1,
                                                               outputSpecSha256: sampleQuote.outputSpecSha256))
        }
        var jobId: String?
        if case .ok(.demoDisabled(let sample)) = accept { jobId = sample }
        var snapshots: [JobSnapshot] = []
        if let jobId { for await snapshot in await client.job(jobId) { snapshots.append(snapshot) } }

        var artifacts: Outcome<[ArtifactLine]>?
        var shareLink: Outcome<ShareLinkStatus>?
        var download: Outcome<[DownloadEvent]>?
        if let jobId {
            let listed = await result { () throws(CloudError) in try await client.artifacts(jobId) }
            artifacts = map(listed) { (list: [CloudArtifact]) in list.map { ArtifactLine(artifactId: $0.artifactId, verified: $0.verified,
                                                            accessible: $0.accessible, shareLink: $0.shareLink) } }
            if case .success(let list) = listed, let film = list.first {
                shareLink = await outcome { () throws(CloudError) in try await client.shareLink(.refresh, artifactId: film.artifactId) }
                download = await collect(await client.download(artifactId: film.artifactId, resumingFrom: 0))
            }
        }
        var uploads: [Outcome<UploadSession>] = []
        for source in ["camera-1", "camera-2", "camera-3"] {
            uploads.append(await outcome { () throws(CloudError) in try await client.openUpload(sourceId: source) })
        }
        return CloudDemoTranscript(
            scenario: scenario, launchArguments: scenario.launchArguments, mode: await client.mode(),
            identity: await outcome { () throws(CloudError) in try await client.identity() },
            quote: map(quote) { (q: CloudQuote) in
                QuoteLine(quoteId: q.quote.quoteId, environment: q.quote.environment.rawValue, sample: q.quote.sample,
                          illustrative: q.quote.illustrative, title: q.title, range: q.rangeText, limit: q.limitText,
                          condition: q.condition, chargingEnabled: q.chargingEnabled)
            },
            accept: accept, jobId: jobId,
            history: snapshots.last.map(historyLines) ?? [],
            snapshots: snapshots.map(line),
            artifacts: artifacts, uploads: uploads, shareLink: shareLink, download: download,
            deleteCloudCopies: await outcome { () throws(CloudError) in try await client.deleteCloudCopies(projectId: projectId) },
            exportMyData: await outcome { () throws(CloudError) in try await client.exportMyData() },
            deleteAccount: await outcome { () throws(CloudError) in try await client.deleteAccount() })
    }

    static func historyLines(_ snapshot: JobSnapshot) -> [HistoryLine] {
        snapshot.job.history.map { HistoryLine(seq: $0.seq, from: $0.from.value?.rawValue, to: $0.to.rawValue, at: $0.at, reason: $0.reason) }
    }

    static func line(_ snapshot: JobSnapshot) -> SnapshotLine {
        let job = snapshot.job
        return SnapshotLine(seq: job.history.count - 1, state: job.state.rawValue, resumeStage: job.resumeStage.value?.rawValue,
                            attempt: job.attempt, maxAttempts: job.maxAttempts, reservationId: job.reservationId.value,
                            stageProgress: job.stageProgress.value.map { "\($0.stage.rawValue) \($0.percent)%\($0.sample ? " Sample" : "")" },
                            deliveredArtifactIds: job.deliveredArtifactIds, stages: snapshot.stages, notice: snapshot.notice)
    }

    static func result<T>(_ body: () async throws(CloudError) -> T) async -> Result<T, CloudError> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }

    static func outcome<T: Codable & Equatable>(_ body: () async throws(CloudError) -> T) async -> Outcome<T> {
        map(await result(body)) { $0 }
    }

    static func map<T, U>(_ result: Result<T, CloudError>, _ transform: (T) -> U) -> Outcome<U> {
        switch result {
        case .success(let value): .ok(transform(value))
        case .failure(let error): .error(error)
        }
    }

    static func collect(_ stream: AsyncThrowingStream<DownloadEvent, any Error>) async -> Outcome<[DownloadEvent]> {
        var events: [DownloadEvent] = []
        do {
            for try await event in stream { events.append(event) }
            return .ok(events)
        } catch let error as CloudError {
            return .error(error)
        } catch {
            return .error(.refused(code: "unexpected", message: "\(error)"))
        }
    }

    // MARK: Files

    static var folder: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Transcripts", isDirectory: true)
    }

    static func url(_ scenario: DemoCloudScenario) -> URL { folder.appendingPathComponent("\(scenario.rawValue).json") }

    static var recording: Bool { ProcessInfo.processInfo.environment["JOVRA_RECORD_CLOUD_TRANSCRIPTS"] == "1" }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    static func committed(_ scenario: DemoCloudScenario) throws -> CloudDemoTranscript {
        try JSONDecoder().decode(CloudDemoTranscript.self, from: Data(contentsOf: url(scenario)))
    }
}

/// The shared fixtures the Cloud tests compare against (read from the repository, never from the demo's own copy).
enum CloudFixtures {
    static func record<T: StudioContract>(_ type: T.Type, _ name: String) throws -> T {
        try StudioContractCodec.decode(type, from: StudioFixtures.data("records/\(name)"))
    }

    static func sampleQuote() throws -> Quote { try record(Quote.self, "quote.sample-illustrative.json") }
    static func queueJob() throws -> RenderJob { try record(RenderJob.self, "render-job.queue-sample.json") }
    static func readyJob() throws -> RenderJob { try record(RenderJob.self, "render-job.ready.json") }
    static func film() throws -> DeliveredArtifact { try record(DeliveredArtifact.self, "delivered-artifact.film.json") }

    static let consent = QuoteConsent(consentRecordId: "consent-sample-01", uploadSelectedSources: true, modelProvider: true,
                                      textClasses: [.ownerNotes], retentionDays: 7, consentTextVersion: "studio-consent/1",
                                      at: "2026-10-07T22:50:00Z")
}
