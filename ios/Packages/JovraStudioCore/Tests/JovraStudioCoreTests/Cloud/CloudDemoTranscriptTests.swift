import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// SD11 acceptance 1: every injectable failure state is reached by its launch argument, and its JobSnapshot sequence
/// matches the committed transcript (one test case per state, plus the normal queue).
@Suite("Cloud: demo transcripts by launch argument")
struct CloudDemoTranscriptTests {
    @Test("the scenario's snapshots and call results equal its committed transcript", arguments: DemoCloudScenario.allCases)
    func matchesCommittedTranscript(scenario: DemoCloudScenario) async throws {
        let recorded = try await CloudDemoTranscript.record(scenario)
        if CloudDemoTranscript.recording {
            try FileManager.default.createDirectory(at: CloudDemoTranscript.folder, withIntermediateDirectories: true)
            try recorded.encoded().write(to: CloudDemoTranscript.url(scenario))
        }
        let committed = try CloudDemoTranscript.committed(scenario)
        #expect(recorded.snapshots == committed.snapshots, "snapshot sequence of \(scenario.rawValue)")
        #expect(recorded.history == committed.history)
        #expect(recorded == committed)
    }

    @Test("every committed transcript names a scenario, and every scenario has one")
    func oneTranscriptPerScenario() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: CloudDemoTranscript.folder.path)
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
        #expect(names == DemoCloudScenario.allCases.map(\.rawValue).sorted())
        #expect(DemoCloudScenario.failureStates.count == 13)
    }

    /// What ST38, ST37, ST39 and ST40 say each state looks like, written from the screen spec, not from the code.
    struct Expected: Sendable, CustomTestStringConvertible {
        var scenario: DemoCloudScenario
        var finalState: RenderJobState?
        var stage: RenderJobStage?
        var status: JobStageStatus?
        var testDescription: String { scenario.rawValue }
    }

    static let expected: [Expected] = [
        .init(scenario: .queue, finalState: .previewRendering, stage: .buildFilm, status: .inProgress),
        .init(scenario: .paused, finalState: .paused, stage: .upload, status: .paused),
        .init(scenario: .retryable, finalState: .previewRendering, stage: .buildFilm, status: .inProgress),
        .init(scenario: .terminal, finalState: .failedTerminal, stage: .buildFilm, status: .failed),
        .init(scenario: .canceled, finalState: .canceled, stage: .buildFilm, status: .canceled),
        .init(scenario: .budgetExhausted, finalState: .budgetExceeded, stage: .buildFilm, status: .stopped),
        .init(scenario: .quoteExpired, finalState: .quoteExpired, stage: nil, status: nil),
        .init(scenario: .notSignedIn, finalState: nil, stage: nil, status: nil),
        .init(scenario: .aboveCap, finalState: .quoted, stage: nil, status: nil),
        .init(scenario: .partialUpload, finalState: .failedRetryable, stage: .upload, status: .retrying),
        .init(scenario: .expiredLink, finalState: .ready, stage: nil, status: nil),
        .init(scenario: .revokedAccess, finalState: .ready, stage: nil, status: nil),
        .init(scenario: .deletionRunning, finalState: .ready, stage: nil, status: nil),
        .init(scenario: .deletionFailed, finalState: .ready, stage: nil, status: nil),
    ]

    @Test("each launch argument lands on the state its screen describes", arguments: expected)
    func landsOnState(expected: Expected) async throws {
        let client = try DemoCloudClient(scenario: DemoCloudScenario(launchArguments: expected.scenario.launchArguments))
        #expect(client.scenario == expected.scenario)
        var last: JobSnapshot?
        if let jobId = client.sampleJobId { for await snapshot in await client.job(jobId) { last = snapshot } }
        #expect(last?.state == expected.finalState)
        #expect(last?.currentStage?.stage == expected.stage)
        #expect(last?.currentStage?.status == expected.status)
    }

    @Test("paused: the upload stage is paused at 2.1 of 10.8 GB, and Resume upload returns it to In progress")
    func paused() async throws {
        let client = try DemoCloudClient(scenario: .paused)
        let upload = try #require(await Self.last(client)?.stages.first)
        #expect(upload.stage == .upload && upload.status == .paused)
        #expect(upload.bytesDone == 2_100_000_000 && upload.bytesTotal == 10_800_000_000)
        let resumed = try await client.resume("job-queue-38")
        #expect(resumed.state == .uploading && resumed.stages[0].status == .inProgress && resumed.job.resumeStage == .null)
        #expect(resumed.job.history.last?.reason == "owner-resumed")
    }

    @Test("retryable: Trying again, then the retry runs as attempt 2 of 3")
    func retryable() async throws {
        let snapshots = try await Self.all(DemoCloudClient(scenario: .retryable))
        let failing = try #require(snapshots.dropLast().last)
        #expect(failing.state == .failedRetryable && failing.currentStage?.status == .retrying && failing.job.attempt == 1)
        let retry = try #require(snapshots.last)
        #expect(retry.job.attempt == 2 && retry.job.maxAttempts == 3 && retry.currentStage?.stage == .buildFilm)
    }

    @Test("terminal: the job cannot be resumed, paused or retried; nothing was charged beyond the Sample reservation")
    func terminal() async throws {
        let client = try DemoCloudClient(scenario: .terminal)
        #expect(await Self.last(client)?.state == .failedTerminal)
        await #expect(throws: CloudError.self) { _ = try await client.resume("job-queue-38") }
        await #expect(throws: CloudError.refused(code: "terminalState", message: "failed_terminal is terminal")) {
            _ = try await client.pause("job-queue-38")
        }
    }

    @Test("canceled: Film canceled, then Removing temporary copies, then Temporary copies removed")
    func canceled() async throws {
        let snapshots = try await Self.all(DemoCloudClient(scenario: .canceled))
        #expect(snapshots.suffix(2).map(\.notice) == [.removingTemporaryCopies, .temporaryCopiesRemoved])
        #expect(snapshots.suffix(2).allSatisfy { $0.state == .canceled })
    }

    @Test("budget exhausted: stopped at the Sample reservation's 4-credit cap; it resumes only through a new quote")
    func budgetExhausted() async throws {
        let client = try DemoCloudClient(scenario: .budgetExhausted)
        let last = try #require(await Self.last(client))
        #expect(last.notice == .stoppedAtLimit(capCredits: 4))
        let reservation = try JSONSerialization.jsonObject(with: StudioFixtures.data("records/usage-reservation.held.json")) as? [String: Any]
        #expect((reservation?["capCredits"] as? NSNumber)?.intValue == 4)
        #expect(last.job.resumeStage == .value(.previewRendering))
        await #expect(throws: CloudError.self) { _ = try await client.resume("job-queue-38") }
    }

    @Test("quote expired, not signed in and above cap are quote states; local options never depend on them")
    func quoteStates() async throws {
        let expired = try await DemoCloudClient(scenario: .quoteExpired).quote(CloudQuoteRequest(projectId: "sample-court-day", planRevision: 1))
        #expect(expired.condition == .expired)
        let above = try await DemoCloudClient(scenario: .aboveCap).quote(CloudQuoteRequest(projectId: "sample-court-day", planRevision: 1))
        #expect(above.condition == .aboveCap(spendingLimitCredits: 3) && above.quote.capCredits == 4)
        let signedOut = try DemoCloudClient(scenario: .notSignedIn)
        #expect(try await signedOut.identity() == .signedOut)
        await #expect(throws: CloudError.notSignedIn) {
            _ = try await signedOut.quote(CloudQuoteRequest(projectId: "sample-court-day", planRevision: 1))
        }
        #expect(CloudError.notSignedIn.message == "Sign in to make films in the cloud.")
    }

    @Test("partial upload: two of three sources confirmed; camera 3 resumes after part 40 and never re-sends one")
    func partialUpload() async throws {
        let client = try DemoCloudClient(scenario: .partialUpload)
        let upload = try #require(await Self.last(client)?.stages.first)
        #expect(upload.status == .retrying && upload.sourcesDone == 2 && upload.sourceCount == 3)
        let camera3 = try await client.openUpload(sourceId: "camera-3")
        #expect(camera3.partCount == 108)                // 3,600,000,000 bytes in 32 MiB parts
        #expect(camera3.remainingParts.first == 41 && camera3.remainingParts.count == 68)
        #expect(Set(camera3.remainingParts).isDisjoint(with: camera3.confirmedParts))
        #expect(try await client.openUpload(sourceId: "camera-1").remainingParts.isEmpty)
        #expect(upload.bytesDone == 7_200_000_000 + camera3.confirmedBytes)
    }

    @Test("expired link and revoked access are states of the delivered film's link; revoked access refuses the download")
    func links() async throws {
        let expired = try await DemoCloudClient(scenario: .expiredLink).artifacts("job-film-01")
        #expect(expired.map(\.shareLink) == [.expired(grantId: "grant-01", expiredAt: "2026-10-08T23:50:00Z")])
        let revokedClient = try DemoCloudClient(scenario: .revokedAccess)
        let revoked = try await revokedClient.artifacts("job-film-01")
        #expect(revoked.map(\.shareLink) == [.revoked(grantId: "grant-01")] && revoked.map(\.accessible) == [false])
        var thrown: (any Error)?
        do { for try await _ in await revokedClient.download(artifactId: "film-court-memories", resumingFrom: 0) {} } catch { thrown = error }
        #expect(thrown as? CloudError == .accessRevoked)
    }

    @Test("deletion running and failed report progress over the four cloud copies; the demo otherwise has none")
    func deletion() async throws {
        #expect(try await DemoCloudClient(scenario: .deletionRunning).deleteCloudCopies(projectId: "sample-court-day").status
                == .running(removed: 1, total: 4))
        #expect(try await DemoCloudClient(scenario: .deletionFailed).deleteCloudCopies(projectId: "sample-court-day").status
                == .failed(removed: 3, total: 4))
        #expect(try await DemoCloudClient(scenario: .queue).deleteCloudCopies(projectId: "sample-court-day").status == .nothingToDelete)
    }

    @Test("demo deletion progress belongs only to the Sample project",
          arguments: [DemoCloudScenario.deletionRunning, .deletionFailed])
    func deletionDoesNotClaimCopiesForOtherProjects(scenario: DemoCloudScenario) async throws {
        let client = try DemoCloudClient(scenario: scenario)
        let result = try await client.deleteCloudCopies(projectId: "other-project")
        #expect(result.scope == "project:other-project")
        #expect(result.sample)
        #expect(result.status == .nothingToDelete)
    }

    @Test("an unknown scenario name or a missing value is refused; no argument is the queue")
    func launchArgumentParsing() throws {
        #expect(try DemoCloudScenario(launchArguments: []) == .queue)
        #expect(try DemoCloudScenario(launchArguments: ["-studioCloudScenario", "budgetExhausted"]) == .budgetExhausted)
        #expect(throws: CloudError.self) { try DemoCloudScenario(launchArguments: ["-studioCloudScenario", "explode"]) }
        #expect(throws: CloudError.self) { try DemoCloudScenario(launchArguments: ["-studioCloudScenario"]) }
    }

    static func all(_ client: DemoCloudClient) async -> [JobSnapshot] {
        var out: [JobSnapshot] = []
        if let jobId = client.sampleJobId { for await snapshot in await client.job(jobId) { out.append(snapshot) } }
        return out
    }

    static func last(_ client: DemoCloudClient) async -> JobSnapshot? { await all(client).last }
}
