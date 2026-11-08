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
        let engine = CaptureEngine(source: camera, clock: clock, sink: RefusingHandoff())
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

        let unfinishedID = try await library.createCapture(seed, mode: .camera)
        let unfinishedFolder = try await library.recordingFolder(unfinishedID)
        let unfinishedJournal = unfinishedFolder.appendingPathComponent("capture-journal.json")
        _ = try CaptureJournal(url: unfinishedJournal, sessionID: unfinishedID.rawValue, mode: .camera, microphone: .notRequested)
        let unfinishedBytes = try Data(contentsOf: unfinishedJournal)
        let liveResult = await library.reconcileAtStartup()
        XCTAssertEqual(liveResult, .init(), "Recovery never scans a session started by the same process")

        let reopened = try LocalCaptureLibrary(root: root)
        let result = await reopened.reconcileAtStartup()
        XCTAssertEqual(result, .init(recovered: 1, refused: 1))
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
}
