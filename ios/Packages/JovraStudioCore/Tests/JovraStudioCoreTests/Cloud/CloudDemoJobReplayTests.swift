import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// SD11 acceptance 2: a demo job's stages replay through RenderJobMachine without a refused transition, and the 42% is
/// the stage progress of Build film, never an overall percentage (stories 193, 194).
@Suite("Cloud: demo jobs replay through RenderJobMachine")
struct CloudDemoJobReplayTests {
    static let machine = try! RenderJobMachine(contract: .bundled(), mode: .cloud)

    @Test("every snapshot of every scenario is a record the job machine replays to its stored state",
          arguments: DemoCloudScenario.allCases)
    func everySnapshotReplays(scenario: DemoCloudScenario) async throws {
        let film = try CloudFixtures.film()
        for snapshot in await CloudDemoTranscriptTests.all(try DemoCloudClient(scenario: scenario)) {
            let verified = RenderJobMachine.verifiedArtifact(for: snapshot.job, artifacts: [film])
            #expect(throws: Never.self, "\(scenario.rawValue) at \(snapshot.state.rawValue)") {
                try Self.machine.replay(snapshot.job, verifiedArtifact: verified)
            }
            #expect(snapshot.isSample)
            // the record round-trips through the strict jovra.render-job/1 codec, so it is a valid stored job
            #expect(try StudioContractCodec.decode(RenderJob.self, from: StudioContractCodec.encode(snapshot.job)) == snapshot.job)
        }
    }

    @Test("the queue sample ends exactly at the committed render-job.queue-sample.json")
    func queueEndsAtFixture() async throws {
        let last = try #require(await CloudDemoTranscriptTests.last(try DemoCloudClient(scenario: .queue)))
        #expect(last.job == (try CloudFixtures.queueJob()))
    }

    @Test("the delivered scenarios show the committed render-job.ready.json")
    func readyIsFixture() async throws {
        for scenario in [DemoCloudScenario.expiredLink, .revokedAccess, .deletionRunning, .deletionFailed] {
            let snapshots = await CloudDemoTranscriptTests.all(try DemoCloudClient(scenario: scenario))
            #expect(snapshots.map(\.job) == [try CloudFixtures.readyJob()])
            #expect(snapshots.first?.stages.allSatisfy { $0.status == .complete && $0.percent == nil } == true)
        }
    }

    @Test("ST38: Upload complete (3 sources), Align angles complete and reviewed, Build film 42% of its stage, Verify export queued")
    func queueStages() async throws {
        let last = try #require(await CloudDemoTranscriptTests.last(try DemoCloudClient(scenario: .queue)))
        let stages = last.stages
        #expect(stages.map(\.title) == ["Upload", "Align angles", "Build film", "Verify export"])
        #expect(stages.map(\.status) == [.complete, .complete, .inProgress, .queued])
        #expect(stages[0].sourcesDone == 3 && stages[0].sourceCount == 3)
        #expect(stages[1].reviewed == true)
        #expect(stages[2].percent == 42)
        #expect(last.job.stageProgress.value?.stage == .previewRendering)
        #expect(RenderJobStage(state: .previewRendering) == .buildFilm)
    }

    @Test("a percentage only ever sits on the one stage in progress, in every snapshot of every scenario",
          arguments: DemoCloudScenario.allCases)
    func percentBelongsToOneStage(scenario: DemoCloudScenario) async throws {
        for snapshot in await CloudDemoTranscriptTests.all(try DemoCloudClient(scenario: scenario)) {
            let withPercent = snapshot.stages.filter { $0.percent != nil }
            #expect(withPercent.count <= 1)
            #expect(withPercent.allSatisfy { $0.status == .inProgress && (0...100).contains($0.percent!) })
            if let progress = snapshot.job.stageProgress.value {
                #expect(withPercent.map(\.stage) == [RenderJobStage(state: progress.stage)].compactMap { $0 })
            }
        }
    }

    @Test("a JobSnapshot has no whole-job percentage to show")
    func noOverallPercentage() throws {
        let labels = Mirror(reflecting: JobSnapshot(job: try CloudFixtures.queueJob(), facts: JobStageFacts(
            sourceCount: 3, sourcesUploaded: 3, uploadBytes: 1, bytesUploaded: 1, alignmentReviewed: true))).children.compactMap(\.label)
        #expect(labels.sorted() == ["facts", "job", "notice", "stages"])
    }

    @Test("pause, resume and cancel on the demo job go through the machine and stay replayable")
    func controlsReplay() async throws {
        let client = try DemoCloudClient(scenario: .queue)
        let paused = try await client.pause("job-queue-38")
        #expect(paused.state == .paused && paused.job.resumeStage == .value(.previewRendering))
        #expect(paused.stages[2].status == .paused && paused.stages[2].percent == nil)
        let resumed = try await client.resume("job-queue-38")
        #expect(resumed.state == .previewRendering && resumed.job.attempt == 1)
        let canceled = try await client.cancel("job-queue-38")
        #expect(canceled.state == .canceled && canceled.notice == .removingTemporaryCopies)
        for snapshot in [paused, resumed, canceled] {
            #expect(throws: Never.self) { try Self.machine.replay(snapshot.job, verifiedArtifact: false) }
        }
        #expect(canceled.job.history.suffix(3).map(\.at) == ["2026-10-07T23:14:00Z", "2026-10-07T23:15:00Z", "2026-10-07T23:16:00Z"])
        // the stream now ends with the controlled state
        #expect(await CloudDemoTranscriptTests.last(client)?.state == .canceled)
        await #expect(throws: CloudError.refused(code: "illegalTransition", message: "canceled has no stage to resume")) {
            _ = try await client.resume("job-queue-38")
        }
        await #expect(throws: CloudError.unknownJob("job-other")) { _ = try await client.pause("job-other") }
    }
}
