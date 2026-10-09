import Foundation
import JovraCore
import JovraMedia
import XCTest
@testable import Jovra

final class LocalCaptureLibraryTests: XCTestCase {
    func testNewFixtureCaptureStartsFreshAndRemainsSampleAfterReopening() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let players = [
            SessionPlayer(id: "a", displayName: "Player A", handedness: .unknown, backhand: .unknown, isSelf: true),
            SessionPlayer(id: "b", displayName: "Player B", handedness: .unknown, backhand: .unknown, isSelf: false),
        ]
        let format = SessionMatchFormat(presetId: .clubBo3, setsToWin: .value2, gameScoring: .ad,
                                       set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let)
        let toss = SessionToss(firstServer: "a", startingEnds: .init(A: .near, B: .far))
        let seed = CaptureSessionSeed(title: "First recording", players: players, format: format, toss: toss)
        let id = try await library.createCapture(seed, mode: .simulatorFixture)
        let reopened = try LocalCaptureLibrary(root: root)
        let session = try await reopened.load(id)
        XCTAssertEqual(session.title, "First recording")
        XCTAssertEqual(session.schemaVersion, .current)
        XCTAssertEqual(session.players, players)
        XCTAssertEqual(session.match?.log.count, 0, "A new capture must not inherit the 124 sample match points")
        XCTAssertEqual(session.marks?.count, 0)
        XCTAssertEqual(session.annotations?.count, 0)
        XCTAssertEqual(session.exports?.count, 0)
        XCTAssertEqual(session.recording.segments.count, 0)
        XCTAssertFalse(session.recording.mediaAvailable)
        XCTAssertEqual(session.sample?.synthetic, true)
        XCTAssertEqual(session.analysis?.state, .notRequested)
        XCTAssertEqual(session.review?.state, .notStarted)
        XCTAssertEqual(session.archive.state, .localOnly)
    }

    func testCapturePreservesTheChosenMatchFormatAndToss() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let players = [
            SessionPlayer(id: "a", displayName: "Player A", handedness: .unknown, backhand: .unknown, isSelf: true),
            SessionPlayer(id: "b", displayName: "Player B", handedness: .unknown, backhand: .unknown, isSelf: false),
        ]
        let format = SessionMatchFormat(presetId: .bestOf1, setsToWin: .value1, gameScoring: .noAd,
                                       set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let)
        let toss = SessionToss(firstServer: "b", startingEnds: .init(A: .far, B: .near))
        let seed = CaptureSessionSeed(title: "Chosen setup", players: players, format: format, toss: toss)
        let id = try await library.createCapture(seed, mode: .camera)
        let saved = try await library.load(id)
        XCTAssertEqual(saved.match?.format, format)
        XCTAssertEqual(saved.match?.toss, toss)
        XCTAssertNil(saved.sample, "Real camera origin is not sample content")
    }

    func testRecordingSinkHandoffPersistsRecordingAndMarksAfterReopening() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let seed = CaptureSessionSeed(title: "Interrupted capture", players: [
            .init(id: "a", displayName: "Player A", handedness: .unknown, backhand: .unknown, isSelf: true),
            .init(id: "b", displayName: "Player B", handedness: .unknown, backhand: .unknown, isSelf: false),
        ], format: .init(presetId: .bestOf1, setsToWin: .value1, gameScoring: .ad,
                         set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let),
            toss: .init(firstServer: "a", startingEnds: .init(A: .near, B: .far)))
        let id = try await library.createCapture(seed, mode: .simulatorFixture)
        let recording = SessionRecording(mode: .simulatorFixture, segments: [], gaps: [], microphone: .denied, mediaAvailable: false)
        let marks = [SessionMark(id: "first-mark", tMs: 500, kind: .highlight,
                                 provenance: .init(status: .manual, source: "player", sample: true))]
        let sink: any RecordingSink = library
        try await sink.saveRecording(sessionID: id.rawValue, recording: recording, marks: marks)
        let reopened = try LocalCaptureLibrary(root: root)
        let saved = try await reopened.load(id)
        XCTAssertEqual(saved.recording, recording)
        XCTAssertEqual(saved.marks, marks)
        XCTAssertEqual(saved.original?.state, .partial)
        XCTAssertEqual(saved.sample?.synthetic, true)
        XCTAssertEqual(saved.match?.log.count, 0)
        XCTAssertEqual(saved.analysis?.state, .notRequested)
    }
}
