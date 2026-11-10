import AVFoundation
import JovraCore
import JovraMedia
import XCTest
@testable import Jovra

private struct RefusingHandoff: RecordingSink {
    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws {
        throw CocoaError(.fileWriteOutOfSpace)
    }
}

final class StartupRecoveryTests: XCTestCase {
    @MainActor
    func testReopenedLibraryRecoversFinishedJournalOnceWithoutChangingOriginalOrEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let seed = CaptureSessionSeed(title: "Pending capture", players: [
            .init(id: "a", displayName: "Player A", handedness: .unknown, backhand: .unknown, isSelf: true),
            .init(id: "b", displayName: "Player B", handedness: .unknown, backhand: .unknown, isSelf: false)
        ], format: .init(presetId: .bestOf1, setsToWin: .value1, gameScoring: .ad,
            set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let),
            toss: .init(firstServer: "a", startingEnds: .init(A: .near, B: .far)))
        let id = try await library.createCapture(seed, mode: .simulatorFixture)
        let folder = try await library.recordingFolder(id)
        let source = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let clock = VirtualCaptureClock()
        let camera = FixtureCamera(url: source, duration: CMTime(value: 2, timescale: 1), clock: clock)
        // The synthetic failed-handoff fixture tests recovery, independently of live capture admission.
        let budget = FakeDeviceBudget(.init(freeBytes: 64 * 1024 * 1024, batteryFraction: nil,
                                             lowPowerMode: false, thermalState: .nominal))
        let engine = CaptureEngine(source: camera, clock: clock, sink: RefusingHandoff(), budget: budget)
        _ = try await engine.prepare(.init(width: 1280, height: 720), microphone: .denied)
        try await engine.start(sessionID: id.rawValue, folder: folder)
        try await camera.waitUntilFinished()
        _ = try engine.markPoint(note: "Captured mark")
        do { _ = try await engine.stop(); XCTFail("Expected handoff failure") }
        catch let error as CocoaError { XCTAssertEqual(error.code, .fileWriteOutOfSpace) }

        let journalURL = folder.appendingPathComponent("capture-journal.json")
        let journal = try CaptureJournal.open(url: journalURL).snapshot()
        XCTAssertTrue(journal.finished)
        let movieURL = folder.appendingPathComponent(try XCTUnwrap(journal.segments.first).file.path)
        let movie = try Data(contentsOf: movieURL)
        let journalBytes = try Data(contentsOf: journalURL)
        let store = try SessionStore(root: root)
        try await store.update(id.rawValue, facet: .review(.init(state: .inProgress)))
        let before = try await library.load(id)
        XCTAssertFalse(before.recording.mediaAvailable, "The original process did not acknowledge a save")

        let scanner = RecoveryScanner(root: root)
        let scanned = try await scanner.scan()
        let candidate = try XCTUnwrap(scanned.first)
        let sourceWitness = await scanner.adoptionWitness(for: id.rawValue)
        let witness = try XCTUnwrap(sourceWitness)
        try movie.write(to: movieURL, options: .atomic) // Same bytes, different file after verification.
        do {
            _ = try await store.reconcileCaptureRecovery(candidate.recording, marks: candidate.marks,
                                                         original: candidate.original, for: id.rawValue,
                                                         verifyOriginals: witness.verify)
            XCTFail("Replacement after the scan must not be acknowledged")
        } catch {
            let after = try await store.load(id.rawValue)
            XCTAssertEqual(after, before)
        }

        let unfinishedID = try await library.createCapture(seed, mode: .camera)
        let unfinishedFolder = try await library.recordingFolder(unfinishedID)
        let unfinishedJournal = unfinishedFolder.appendingPathComponent("capture-journal.json")
        _ = try CaptureJournal(url: unfinishedJournal, sessionID: unfinishedID.rawValue, mode: .camera, microphone: .notRequested)
        let unfinishedBytes = try Data(contentsOf: unfinishedJournal)
        let liveResult = await library.reconcileAtStartup()
        XCTAssertEqual(liveResult, .init(), "Recovery never scans a session started by the same process")

        let reopened = try LocalCaptureLibrary(root: root)
        let result = await reopened.reconcileAtStartup()
        XCTAssertEqual(result.recovered, 1)
        XCTAssertEqual(result.refused, 1)
        XCTAssertEqual(result.reports.map(\.id), [id.rawValue], "T17: the relaunch sheet names the recovered recording")
        XCTAssertEqual(result.reports.first?.outcome, .complete)
        XCTAssertEqual(result.reports.first?.savedThroughMs, 2000)
        XCTAssertEqual(try Data(contentsOf: unfinishedJournal), unfinishedBytes)
        let sessions = try await reopened.sessions()
        XCTAssertEqual(sessions.first(where: { $0.id == id.rawValue })?.original?.state, .saved)
        let recovered = try await reopened.load(id)
        XCTAssertEqual(recovered.recording.recovery?.outcome, .complete)
        XCTAssertEqual(recovered.marks?.first?.note, "Captured mark")
        XCTAssertEqual(recovered.review, before.review)
        XCTAssertEqual(try Data(contentsOf: movieURL), movie)
        XCTAssertEqual(try Data(contentsOf: journalURL), journalBytes)
        let receipt = folder.appendingPathComponent("capture-recovery.json")
        let receiptBytes = try Data(contentsOf: receipt)
        let third = try LocalCaptureLibrary(root: root)
        let again = await third.reconcileAtStartup()
        XCTAssertEqual(again, .init(refused: 1), "Already saved journals are not decoded again")
        let repeated = try await third.load(id)
        XCTAssertEqual(repeated, recovered)
        XCTAssertEqual(try Data(contentsOf: receipt), receiptBytes)
    }

    @MainActor
    func testPartialStartupRecoveryMakesPlayableFootageAvailableAndDoesNotAnnounceItAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let setup = CaptureSetupChoices(title: "Partial capture", playerA: "Player A", playerB: "Player B")
        let id = try await library.createCapture(setup.seed, mode: .simulatorFixture)
        let folder = try await library.recordingFolder(id)
        let source = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let clock = VirtualCaptureClock()
        let camera = FixtureCamera(url: source, duration: CMTime(value: 2, timescale: 1), clock: clock)
        let budget = FakeDeviceBudget(.init(freeBytes: 64 * 1024 * 1024, batteryFraction: nil,
                                             lowPowerMode: false, thermalState: .nominal))
        let engine = CaptureEngine(source: camera, clock: clock, sink: RefusingHandoff(), budget: budget)
        _ = try await engine.prepare(.init(width: 1280, height: 720), microphone: .denied)
        try await engine.start(sessionID: id.rawValue, folder: folder)
        try await camera.waitUntilFinished()
        try await engine.pause()
        clock.advance(by: CMTime(value: 1, timescale: 1))
        try await engine.resume()
        try await camera.waitUntilFinished()
        do { _ = try await engine.stop(); XCTFail("Expected handoff failure") }
        catch let error as CocoaError { XCTAssertEqual(error.code, .fileWriteOutOfSpace) }

        let journalURL = folder.appendingPathComponent("capture-journal.json")
        let journal = try CaptureJournal.open(url: journalURL).snapshot()
        XCTAssertTrue(journal.finished)
        guard journal.segments.count == 2 else { return XCTFail("Expected two recorded segments") }
        let damagedSegment = journal.segments[0], playableSegment = journal.segments[1]
        let damaged = folder.appendingPathComponent(damagedSegment.file.path)
        let playable = folder.appendingPathComponent(playableSegment.file.path)
        let damage = Data("Synthetic damaged segment".utf8)
        try damage.write(to: damaged)
        let journalBytes = try Data(contentsOf: journalURL)
        let playableBytes = try Data(contentsOf: playable)

        let reopened = try LocalCaptureLibrary(root: root)
        let summary = await reopened.reconcileAtStartup()
        XCTAssertEqual(summary.partiallyRecovered, 1)
        XCTAssertEqual([summary.recovered, summary.refused], [0, 0])
        XCTAssertFalse(summary.scanFailed)
        XCTAssertEqual(summary.reports.map(\.id), [id.rawValue], "T17: the relaunch sheet names the partial recovery")
        XCTAssertEqual(summary.reports.first?.outcome, .partial)
        XCTAssertEqual(summary.reports.first?.unrecoverable.map(\.path), [damagedSegment.file.path])
        let rows = try await reopened.sessions()
        XCTAssertEqual(rows.map(\.id), [id.rawValue])
        XCTAssertEqual(rows.first?.original?.state, .partial)
        let recovered = try await reopened.load(id)
        XCTAssertTrue(recovered.recording.mediaAvailable)
        XCTAssertEqual(recovered.recording.segments.map(\.id), [playableSegment.id])
        XCTAssertEqual(recovered.recording.recovery?.outcome, .partial)
        XCTAssertEqual(recovered.recording.recovery?.unrecoverable?.map(\.path), [damagedSegment.file.path])
        let mediaURL = try await reopened.fileURL(id, relativePath: playableSegment.file.path)
        XCTAssertEqual(try Data(contentsOf: mediaURL), playableBytes)
        XCTAssertEqual(try Data(contentsOf: damaged), damage)
        XCTAssertEqual(try Data(contentsOf: journalURL), journalBytes)

        let urls = [folder.appendingPathComponent("session.json"), folder.appendingPathComponent("capture-recovery.json"),
                    journalURL, playable, damaged]
        let bytes = try urls.map { try Data(contentsOf: $0) }
        let modificationDates = try urls.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        let third = try LocalCaptureLibrary(root: root)
        let repeatSummary = await third.reconcileAtStartup()
        XCTAssertEqual(repeatSummary, .init(), "An unchanged partial recovery must not announce again")
        let repeated = try await third.load(id)
        XCTAssertEqual(repeated, recovered)
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, bytes)
        XCTAssertEqual(try urls.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }, modificationDates)
    }
}
