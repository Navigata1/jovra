import Foundation
import XCTest
@testable import JovraCore

/// T27: the processing queue's state machine (pure) and its persistence (ProcessingQueueStore).
final class ProcessingQueueTests: XCTestCase {
    private let idle = ProcessingConditions(captureActive: false, thermal: .nominal, externalPower: true,
                                            lowPowerMode: false, backup: .awaitingSetup)

    // MARK: Stages are independent

    func testAFailedAnalyzeLeavesPrepareReplayAndBackupToRunOnTheirOwn() throws {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: true)
        try queue.start(.analyze, for: "s1", under: idle)
        try queue.fail(.analyze, for: "s1", reason: .analyzerFailed)

        XCTAssertEqual(queue.job("s1")?.analyze.status, .failed)
        XCTAssertEqual(queue.job("s1")?.prepareReplay.status, .queued, "a failed analyze does not touch prepare replay")
        XCTAssertEqual(queue.next(under: idle), .run(.prepareReplay, "s1"), "prepare replay still runs after analysis failed")

        try queue.start(.prepareReplay, for: "s1", under: idle)
        try queue.complete(.prepareReplay, for: "s1")
        XCTAssertEqual(queue.job("s1")?.prepareReplay.status, .done)
        XCTAssertEqual(queue.job("s1")?.analyze.status, .failed, "completing one stage does not clear another's failure")
    }

    func testAnalyzeDoesNotWaitForPrepareReplay() throws {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: true)
        try queue.start(.prepareReplay, for: "s1", under: idle)
        try queue.fail(.prepareReplay, for: "s1", reason: .mediaUnreadable)
        XCTAssertEqual(queue.next(under: idle), .run(.analyze, "s1"))
    }

    func testNothingRunsBeforeTheOriginalIsSaved() throws {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: false)
        XCTAssertEqual(queue.next(under: idle), .idle)
        XCTAssertThrowsError(try queue.start(.prepareReplay, for: "s1", under: idle)) {
            XCTAssertEqual($0 as? ProcessingQueueError, .originalNotSaved)
        }
        queue.enqueue("s1", originalSaved: true)
        XCTAssertEqual(queue.next(under: idle), .run(.prepareReplay, "s1"), "enqueue again records the saved original")
    }

    // MARK: Capture activity, heat and power

    func testNoStageStartsWhileCaptureActivityIsTrue() throws {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: true)
        var recording = idle
        recording.captureActive = true
        XCTAssertEqual(queue.next(under: recording), .hold(.captureActive))
        for stage in ProcessingStage.allCases {
            XCTAssertThrowsError(try queue.start(stage, for: "s1", under: recording)) {
                XCTAssertEqual($0 as? ProcessingQueueError, .held(.captureActive))
            }
            XCTAssertEqual(queue.job("s1")?[stage].status, stage == .backup ? .blocked : .queued)
        }
    }

    func testStagesWaitForFairThermalStateOrBetter() throws {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: true)
        var conditions = idle
        conditions.thermal = .fair
        XCTAssertEqual(queue.next(under: conditions), .run(.prepareReplay, "s1"), "fair is allowed")
        conditions.thermal = .serious
        XCTAssertEqual(queue.next(under: conditions), .hold(.tooWarm))
        conditions.thermal = .critical
        XCTAssertEqual(queue.next(under: conditions), .hold(.tooWarm))
    }

    func testAnalysisPrefersPowerAndWaitsWhenLowPowerModeIsOnWithoutCharging() throws {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: true)
        try queue.start(.prepareReplay, for: "s1", under: idle)
        try queue.complete(.prepareReplay, for: "s1")
        var battery = idle
        battery.externalPower = false
        XCTAssertEqual(queue.next(under: battery), .run(.analyze, "s1"), "battery alone does not stop analysis")
        battery.lowPowerMode = true
        XCTAssertEqual(queue.next(under: battery), .hold(.lowPower))
        battery.externalPower = true
        XCTAssertEqual(queue.next(under: battery), .run(.analyze, "s1"), "charging lifts the Low Power Mode wait")
    }

    func testSessionsRunInTheOrderTheyWereSaved() throws {
        var queue = ProcessingQueue()
        queue.enqueue("older", originalSaved: true)
        queue.enqueue("newer", originalSaved: true)
        XCTAssertEqual(queue.next(under: idle), .run(.prepareReplay, "older"), "sessions run in the order they were saved")
    }

    // MARK: Pause, resume, retry, unavailable

    func testPauseHoldsAnalysisAtItsProgressAndResumeContinuesFromThere() throws {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: true)
        try queue.start(.prepareReplay, for: "s1", under: idle)
        try queue.complete(.prepareReplay, for: "s1")
        try queue.start(.analyze, for: "s1", under: idle)
        try queue.report(.analyze, for: "s1", progress: 0.4)
        try queue.pauseAnalysis(for: "s1")

        XCTAssertEqual(queue.job("s1")?.analyze.status, .paused)
        XCTAssertEqual(queue.job("s1")?.analyze.progress, 0.4)
        XCTAssertEqual(queue.next(under: idle), .idle, "a paused analysis is never picked up")

        try queue.resumeAnalysis(for: "s1")
        XCTAssertEqual(queue.job("s1")?.analyze.status, .queued)
        XCTAssertEqual(queue.next(under: idle), .run(.analyze, "s1"))
        try queue.start(.analyze, for: "s1", under: idle)
        XCTAssertEqual(queue.job("s1")?.analyze.progress, 0.4, "resume continues from the saved progress")
    }

    func testProgressNeverMovesBackwardsOrPastTheEnd() throws {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: true)
        try queue.start(.analyze, for: "s1", under: idle)
        try queue.report(.analyze, for: "s1", progress: 0.6)
        try queue.report(.analyze, for: "s1", progress: 0.3)
        XCTAssertEqual(queue.job("s1")?.analyze.progress, 0.6)
        try queue.report(.analyze, for: "s1", progress: 1.7)
        XCTAssertEqual(queue.job("s1")?.analyze.progress, 1)
    }

    func testRetryRestartsAFailedAnalysisFromTheBeginning() throws {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: true)
        try queue.start(.analyze, for: "s1", under: idle)
        try queue.report(.analyze, for: "s1", progress: 0.4)
        try queue.fail(.analyze, for: "s1", reason: .analyzerFailed)
        XCTAssertThrowsError(try queue.resumeAnalysis(for: "s1"), "a failure is retried, not resumed")
        try queue.retry(.analyze, for: "s1")
        let analyze = try XCTUnwrap(queue.job("s1")?.analyze)
        XCTAssertEqual(analyze.status, .queued)
        XCTAssertEqual(analyze.progress, 0)
        XCTAssertNil(analyze.reason)
        XCTAssertEqual(analyze.attempts, 2)
    }

    func testWithNoAnalyzerRegisteredTheAnalyzeStageIsUnavailableWithItsReason() throws {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: true)
        try queue.markUnavailable(.analyze, for: "s1", reason: .noAnalyzerRegistered)
        XCTAssertEqual(queue.job("s1")?.analyze.status, .unavailable)
        XCTAssertEqual(queue.job("s1")?.analyze.reason, .noAnalyzerRegistered)
        XCTAssertEqual(queue.next(under: idle), .run(.prepareReplay, "s1"))
        XCTAssertThrowsError(try queue.pauseAnalysis(for: "s1"))
    }

    func testBackupWaitsForTheArchiveWithAReasonAndNeverRunsWithoutOne() throws {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: true)
        try queue.start(.prepareReplay, for: "s1", under: idle)
        try queue.complete(.prepareReplay, for: "s1")
        try queue.markUnavailable(.analyze, for: "s1", reason: .noAnalyzerRegistered)
        queue.updateBackup(.awaitingSetup)
        XCTAssertEqual(queue.job("s1")?.backup.status, .blocked)
        XCTAssertEqual(queue.job("s1")?.backup.reason, .awaitingArchiveSetup)
        queue.updateBackup(.waitingForWiFi)
        XCTAssertEqual(queue.job("s1")?.backup.reason, .waitingForWiFi)
        XCTAssertEqual(queue.next(under: idle), .idle, "a blocked backup is not runnable")
        queue.updateBackup(.ready)
        XCTAssertEqual(queue.job("s1")?.backup.status, .queued)
        XCTAssertNil(queue.job("s1")?.backup.reason)
        XCTAssertEqual(queue.next(under: idle), .run(.backup, "s1"))
        XCTAssertEqual(queue.next(under: idle, stages: [.prepareReplay, .analyze]), .idle,
                       "a scheduler that does not upload never picks the backup up")
    }

    // MARK: Facets

    func testAnalysisFacetFollowsTheAnalyzeStage() throws {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: true)
        XCTAssertEqual(queue.job("s1")?.analysisFacet.state, .queued)
        try queue.start(.analyze, for: "s1", under: idle)
        XCTAssertEqual(queue.job("s1")?.analysisFacet.state, .running)
        try queue.pauseAnalysis(for: "s1")
        XCTAssertEqual(queue.job("s1")?.analysisFacet.state, .paused)
        try queue.resumeAnalysis(for: "s1")
        try queue.start(.analyze, for: "s1", under: idle)
        try queue.fail(.analyze, for: "s1", reason: .analyzerFailed)
        XCTAssertEqual(queue.job("s1")?.analysisFacet, SessionAnalysis(state: .failed, reason: "analyzerFailed", runs: []))
        try queue.retry(.analyze, for: "s1")
        try queue.markUnavailable(.analyze, for: "s1", reason: .noAnalyzerRegistered)
        XCTAssertEqual(queue.job("s1")?.analysisFacet, SessionAnalysis(state: .unavailable, reason: "noAnalyzerRegistered", runs: []))
    }

    func testAFailedAnalyzeNeverChangesTheOriginalFacet() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = try SessionStore(root: root)
        var document = try Self.sampleDocument()
        document.original = .init(state: .saved, updatedAt: "2026-10-06T10:00:00Z")
        try await sessions.create(document)
        let originalBefore = try await sessions.load(document.id).original
        let processing = try ProcessingQueueStore(root: root, sessions: sessions)

        try await processing.enqueue(document.id, originalSaved: true)
        try await processing.start(.analyze, for: document.id, under: idle)
        try await processing.report(.analyze, for: document.id, progress: 0.5)
        try await processing.fail(.analyze, for: document.id, reason: .analyzerFailed)

        let after = try await sessions.load(document.id)
        XCTAssertEqual(after.original, originalBefore, "the original facet is untouched by a failed analysis")
        XCTAssertNotNil(after.original)
        XCTAssertEqual(after.analysis?.state, .failed, "only the analysis facet records the failure")
    }

    // MARK: Persistence across an app kill

    func testStatePersistedBeforeAnAppKillResumesAfterRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = try SessionStore(root: root)
        let document = try Self.sampleDocument()
        try await sessions.create(document)

        do {
            let before = try ProcessingQueueStore(root: root, sessions: sessions)
            try await before.enqueue(document.id, originalSaved: true)
            try await before.start(.prepareReplay, for: document.id, under: idle)
            try await before.complete(.prepareReplay, for: document.id)
            try await before.start(.analyze, for: document.id, under: idle)
            try await before.report(.analyze, for: document.id, progress: 0.35)
            // The process is killed here: no pause, no completion, nothing else is written.
        }

        let relaunched = try await ProcessingQueueStore.open(root: root, sessions: sessions)
        let job = try await XCTUnwrapAsync(await relaunched.job(document.id))
        XCTAssertEqual(job.prepareReplay.status, .done, "finished work stays finished")
        XCTAssertEqual(job.analyze.status, .queued, "interrupted work is queued again, not left running")
        XCTAssertEqual(job.analyze.progress, 0.35, "and resumes from its last saved progress")
        let next = await relaunched.next(under: idle)
        XCTAssertEqual(next, .run(.analyze, document.id))
        let stored = try await sessions.load(document.id)
        XCTAssertEqual(stored.analysis?.state, .queued, "the analysis facet no longer claims it is running")
    }

    func testAnUnreadableQueueFileStartsEmptyAndIsKeptAside() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = try SessionStore(root: root)
        try Data("{not json".utf8).write(to: root.appendingPathComponent(ProcessingQueueStore.fileName))
        let store = try ProcessingQueueStore(root: root, sessions: sessions)
        let jobs = await store.queue.jobs
        XCTAssertTrue(jobs.isEmpty)
        let aside = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("processing-queue.unreadable") }
        XCTAssertEqual(aside.count, 1, "the unreadable file is kept for diagnostics, not deleted")
    }

    private static func sampleDocument() throws -> SessionDocument {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { url.deleteLastPathComponent() }
        return try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: url.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")))
    }
}

private func XCTUnwrapAsync<T>(_ value: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    let resolved = try await value()
    return try XCTUnwrap(resolved, file: file, line: line)
}
