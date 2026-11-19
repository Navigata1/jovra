import Foundation
import JovraCore
import XCTest
@testable import Jovra

/// T27: the scheduler adapter over a real library and queue file. The simulator never launches
/// background tasks and cannot set Low Power Mode or the thermal state, so the device state is injected
/// (`-processingDevice`), leaving the foreground is driven through `backgroundChanged`, and the overnight
/// request is counted instead of submitted.
@MainActor
final class ProcessingSchedulerTests: XCTestCase {
    private var root: URL!
    private var schedulers: [ProcessingScheduler] = []

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("JOVRA-scheduler-\(UUID().uuidString)")
    }

    /// Stops every scheduler a test opened (as if JOVRA left the foreground without continued
    /// processing) and lets its interrupt settle before the library folder is removed.
    override func tearDown() async throws {
        for scheduler in schedulers {
            scheduler.continuedProcessingRefused()
            scheduler.backgroundChanged(true)
        }
        try await waitUntil("every scheduler has stopped", timeout: .seconds(5)) {
            schedulers.allSatisfy { scheduler in
                ProcessingStage.allCases.allSatisfy { stage in
                    !scheduler.jobs.values.contains { $0[stage].status == .running }
                }
            }
        }
        schedulers = []
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: No analyzer registered

    func testWithNoAnalyzerAQueuedAnalysisIsUnavailableUnderALowPowerModeHold() async throws {
        let (scheduler, session) = try await scheduled(device: .lowPowerOnBattery, analyzer: nil)
        let analyze = try XCTUnwrap(scheduler.job(session)?.analyze)
        XCTAssertEqual(analyze.status, .unavailable, "not left queued behind the Low Power Mode hold")
        XCTAssertEqual(analyze.reason, .noAnalyzerRegistered)
        XCTAssertNil(ProcessingStagePresentation.analysisAction(for: analyze.status), "no Pause analysis")
        XCTAssertNil(ProcessingStagePresentation.backgroundNote(analysis: analyze.status,
                                                                continuesInBackground: scheduler.continuesInBackground))
        let row = ProcessingStagePresentation.rows(original: nil, recordingMode: .simulatorFixture, job: scheduler.job(session),
                                                   hold: scheduler.hold, locale: Locale(identifier: "en_US"))[2]
        XCTAssertEqual(row.status, "Unavailable")
        let stored = try await library().load(session)
        XCTAssertEqual(stored.analysis?.state, .unavailable, "the analysis facet agrees")
    }

    func testWithNoAnalyzerAQueuedAnalysisIsUnavailableWhileTheIPhoneIsTooWarm() async throws {
        let (scheduler, session) = try await scheduled(device: .tooWarm, analyzer: nil)
        try await waitUntil("the heat hold is reported") { scheduler.hold == .tooWarm }
        XCTAssertEqual(scheduler.job(session)?.analyze.status, .unavailable)
        XCTAssertEqual(scheduler.job(session)?.prepareReplay.status, .queued, "prepare replay still waits for the iPhone to cool")
        let row = ProcessingStagePresentation.rows(original: nil, recordingMode: .simulatorFixture, job: scheduler.job(session),
                                                   hold: scheduler.hold, locale: Locale(identifier: "en_US"))[2]
        XCTAssertEqual(row.status, "Unavailable")
        XCTAssertFalse(row.detail.contains("cool down"))
    }

    // MARK: Leaving JOVRA without continued processing

    func testLeavingJOVRAStopsAnalysisDoesNotRestartItInTheBackgroundAndAsksForTheOvernightTask() async throws {
        let overnight = Counter()
        let (scheduler, session) = try await scheduled(device: nil, analyzer: .steady, background: false, overnight: overnight)
        scheduler.continuedProcessingRefused() // the iOS 18 path (and the refused path on iOS 26)
        try await waitUntil("analysis runs") {
            scheduler.job(session)?.analyze.status == .running && (scheduler.job(session)?.analyze.progress ?? 0) > 0
        }

        scheduler.backgroundChanged(true)
        try await waitUntil("the interrupt settles at the saved progress") { scheduler.job(session)?.analyze.status == .queued }
        let saved = try XCTUnwrap(scheduler.job(session)?.analyze.progress)
        XCTAssertEqual(overnight.count, 1, "the overnight task is asked for once the interrupted stage is queued again")

        // Several fixture-analyzer steps (250 ms each) later, nothing has restarted.
        try await Task.sleep(for: .milliseconds(1500))
        let stored = try await library().processing().job(session.rawValue)
        XCTAssertEqual(stored?.analyze.status, .queued, "the queue file shows no restart in the background")
        XCTAssertEqual(stored?.analyze.progress, saved, "and no progress made in the background")
        XCTAssertEqual(overnight.count, 1, "asked for once per stay in the background")

        scheduler.backgroundChanged(false)
        try await waitUntil("analysis continues in the foreground from where it stopped") {
            (scheduler.job(session)?.analyze.progress ?? 0) > saved
        }
        XCTAssertEqual(overnight.count, 1, "no overnight request from the foreground")
    }

    func testANewStageDoesNotStartInTheBackgroundEvenWithContinuedProcessing() async throws {
        let overnight = Counter()
        let (scheduler, session) = try await scheduled(device: nil, analyzer: .steady, background: true, overnight: overnight)
        // Enqueued while JOVRA is already in the background (an import finishing, say).
        let library = try library()
        let other = try await library.createCapture(Self.seed, mode: .simulatorFixture)
        await scheduler.enqueue(other)
        try await Task.sleep(for: .milliseconds(500))
        for id in [session, other] {
            XCTAssertNotEqual(scheduler.job(id)?.prepareReplay.status, .running)
            XCTAssertNotEqual(scheduler.job(id)?.analyze.status, .running)
        }
        XCTAssertEqual(overnight.count, 1, "work left in the background asks for the overnight task, once")

        scheduler.backgroundChanged(false)
        try await waitUntil("returning to JOVRA starts the queue") { scheduler.job(session)?.analyze.status == .running }
    }

    // MARK: Helpers

    private static let seed = CaptureSessionSeed(title: "Scheduler fixture", players: [
        .init(id: "a", displayName: "Player A", handedness: .unknown, backhand: .unknown, isSelf: true),
        .init(id: "b", displayName: "Player B", handedness: .unknown, backhand: .unknown, isSelf: false),
    ], format: .init(presetId: .bestOf1, setsToWin: .value1, gameScoring: .ad,
                     set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let),
        toss: .init(firstServer: "a", startingEnds: .init(A: .near, B: .far)))

    /// Counts overnight requests instead of submitting them.
    final class Counter { var count = 0 }

    private var openedLibrary: LocalCaptureLibrary?

    private func library() throws -> LocalCaptureLibrary {
        if let openedLibrary { return openedLibrary }
        let library = try LocalCaptureLibrary(root: root)
        openedLibrary = library
        return library
    }

    /// A scheduler over a fresh library with one session queued. Its original has no media, so prepare
    /// replay fails on its own; analysis does not wait for it.
    private func scheduled(device: LaunchConfiguration.ProcessingDevice?, analyzer: LaunchConfiguration.ProcessingAnalyzer?,
                           background: Bool = false, overnight: Counter = Counter()) async throws -> (ProcessingScheduler, SessionID) {
        var launch = LaunchConfiguration()
        launch.processingDevice = device
        launch.processingAnalyzer = analyzer
        let library = try library()
        let scheduler = ProcessingScheduler(launch: launch, library: .ready(library))
        schedulers.append(scheduler)
        scheduler.submitOvernightRequest = { overnight.count += 1 }
        await scheduler.activate()
        scheduler.backgroundChanged(background)
        let session = try await library.createCapture(Self.seed, mode: .simulatorFixture)
        await scheduler.enqueue(session)
        return (scheduler, session)
    }

    private func waitUntil(_ what: String, timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return XCTFail("timed out waiting until \(what)") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
