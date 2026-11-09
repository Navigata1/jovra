import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// STU-04: one RenderJobMachine for local and cloud jobs (stories 193, 194, 197, 198), beyond the shared vectors.
@Suite("Ledger: RenderJobMachine for local and cloud jobs")
struct LedgerJobMachineTests {
    static let cloud = LedgerVectors.machine
    static let local = try! RenderJobMachine(contract: LedgerVectors.transitions, mode: .local)

    static func code(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let r as LedgerRejection { return r.code.rawValue } catch { return "\(error)" }
    }

    /// Walks `path` from draft; returns the fields after the last step.
    static func walk(_ machine: RenderJobMachine, _ path: [RenderJobState], reservation: Bool = true,
                     verified: Bool = true) throws -> RenderJobMachine.Fields {
        var job = RenderJobMachine.Fields(state: .draft)
        for to in path { job = try machine.checkTransition(job, to: to, hasReservation: reservation, verifiedArtifact: verified) }
        return job
    }

    @Test("a local job runs draft -> normalizing -> ... -> ready with no quote, upload or reservation")
    func localJobSkipsCloudOnlyStates() throws {
        let path: [RenderJobState] = [.normalizing, .syncing, .analyzing, .planning, .previewRendering, .finalRendering, .verifying, .ready]
        #expect(try Self.walk(Self.local, path, reservation: false).state == .ready)
        #expect(Self.local.forwardTargets(of: .draft) == [.normalizing])
        // the same path is refused for a cloud job: it must be quoted, consented and reserved first
        #expect(Self.code { _ = try Self.walk(Self.cloud, path, reservation: false) } == "illegalTransition")
        #expect(Self.code { _ = try Self.walk(Self.local, [.normalizing, .planning, .previewRendering, .finalRendering, .verifying, .ready],
                                              reservation: false, verified: false) } == "unverifiedReady")
    }

    @Test("a local job never enters a cloud-only state", arguments: RenderJobMachine.cloudOnlyStates.sorted { $0.rawValue < $1.rawValue })
    func localRefusesCloudOnly(state: RenderJobState) throws {
        let from: RenderJobMachine.Fields = state == .budgetExceeded ? .init(state: .normalizing) : .init(state: .draft)
        #expect(Self.code { _ = try Self.local.checkTransition(from, to: state, hasReservation: true, verifiedArtifact: false) }
                == "cloudOnlyState")
        #expect(Self.code { _ = try Self.local.checkTransition(.init(state: state), to: .canceled, hasReservation: true,
                                                               verifiedArtifact: false) } == "cloudOnlyState")
    }

    @Test("pause, retry and cancel work the same for local jobs; a retry counts an attempt")
    func localPauseRetryCancel() throws {
        var job = try Self.walk(Self.local, [.normalizing, .planning, .previewRendering, .finalRendering], reservation: false)
        job = try Self.local.checkTransition(job, to: .failedRetryable, hasReservation: false, verifiedArtifact: false)
        #expect(job.resumeStage == .finalRendering)
        job = try Self.local.checkTransition(job, to: .finalRendering, hasReservation: false, verifiedArtifact: false)
        #expect(job.attempt == 2 && job.resumeStage == nil)
        job = try Self.local.checkTransition(job, to: .paused, hasReservation: false, verifiedArtifact: false)
        #expect(Self.code { _ = try Self.local.checkTransition(job, to: .verifying, hasReservation: false, verifiedArtifact: false) }
                == "illegalTransition", "a pause resumes only where it stopped")
        job = try Self.local.checkTransition(job, to: .canceled, hasReservation: false, verifiedArtifact: false)
        #expect(job.state == .canceled && job.resumeStage == nil)
        #expect(Self.code { _ = try Self.local.checkTransition(job, to: .finalRendering, hasReservation: false, verifiedArtifact: false) }
                == "terminalState")
    }

    @Test("a stored resume stage is checked, never trusted, whatever path the record took")
    func storedResumeStageChecked() throws {
        for stage in RenderJobState.allCases {
            let paused = RenderJobMachine.Fields(state: .paused, resumeStage: stage)
            let allowed = Self.cloud.resumeStages(for: .paused).contains(stage)
            let result = Self.code { _ = try Self.cloud.checkTransition(paused, to: stage, hasReservation: true, verifiedArtifact: true) }
            #expect((result == "badResumeStage") == !allowed, "paused -> \(stage.rawValue): \(result ?? "accepted")")
            #expect(!allowed || result == nil, "paused at \(stage.rawValue) must resume there: \(result ?? "")")
        }
        #expect(!Self.cloud.resumeStages(for: .paused).contains(.ready))
        #expect(Self.cloud.resumeStages(for: .ready).isEmpty)
    }

    @Test("replaying the stored jobs reaches their state, resume stage and attempt")
    func replayStoredJobs() throws {
        let artifacts = try LedgerRecordRuleTests.artifacts()
        let ready = try LedgerVectors.record(RenderJob.self, "render-job.ready.json")
        let fields = try Self.cloud.replay(ready, verifiedArtifact: RenderJobMachine.verifiedArtifact(for: ready, artifacts: artifacts))
        #expect(fields == .init(state: .ready, resumeStage: nil, attempt: 2, maxAttempts: 3))
        let queue = try LedgerVectors.record(RenderJob.self, "render-job.queue-sample.json")
        #expect(try Self.cloud.replay(queue, verifiedArtifact: false).state == .previewRendering)
        var backwards = queue
        backwards.history[5].at = "2026-10-07T22:50:59.999Z"
        #expect(Self.code { try Self.cloud.replay(backwards, verifiedArtifact: false) } == "badHistory")
    }

    @Test("every working state belongs to a named stage, and analyzing is shown as Build film, never as analysis")
    func displayStages() {
        #expect(RenderJobStage(state: .analyzing) == .buildFilm)
        #expect(RenderJobStage(state: .normalizing) == .alignAngles && RenderJobStage(state: .syncing) == .alignAngles)
        #expect(RenderJobStage(state: .planning) == .buildFilm && RenderJobStage(state: .finalRendering) == .buildFilm)
        #expect(RenderJobStage(state: .uploading) == .upload && RenderJobStage(state: .verifying) == .verifyExport)
        #expect(RenderJobStage.allCases.allSatisfy { !$0.rawValue.lowercased().contains("analy") })
        // stage progress is reported only for working states, so every one of them has a stage (story 194)
        for state in LedgerVectors.transitions.pausableFrom { #expect(RenderJobStage(state: state) != nil, "\(state.rawValue)") }
        for state: RenderJobState in [.draft, .quoted, .ready, .paused, .canceled, .failedTerminal, .deleted] {
            #expect(RenderJobStage(state: state) == nil)
        }
    }

    @Test("the bundled contract drives the same machine as the repository's file")
    func bundledMachine() throws {
        let bundled = try RenderJobMachine(contract: RenderJobTransitions.bundled())
        #expect(try Self.walk(bundled, [.quoted, .consented, .uploadPending, .queued]).state == .queued)
    }
}
