import AVFoundation
import JovraCore
import JovraMedia
import XCTest
@testable import Jovra

final class ReplayPlaybackModelTests: XCTestCase {
    @MainActor
    func testSavedCaptureOpensActualOriginalAndStepsDecodedFramesWithoutChangingIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let source = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let clock = VirtualCaptureClock()
        let camera = FixtureCamera(url: source, duration: CMTime(value: 4, timescale: 1), clock: clock)
        let capture = NativeCaptureCoordinator(library: library, source: camera, clock: clock)
        try await capture.prepare(seed: seed(), preset: .init(width: 1280, height: 720), microphone: .denied)
        try await capture.start(); try await camera.waitUntilFinished(); try await capture.stop()
        let id = try XCTUnwrap(capture.sessionID)
        let recording = try XCTUnwrap(capture.savedRecording)
        let original = try await library.fileURL(id, relativePath: recording.segments[0].file.path)
        let bytes = try Data(contentsOf: original)
        let model = ReplayPlaybackModel()
        await model.open(library: library, session: id)
        XCTAssertNil(model.error)
        XCTAssertNotNil(model.player)
        XCTAssertEqual(model.document?.sample?.synthetic, true)
        XCTAssertEqual(model.frameCount, 120, "Count comes from decoding all saved frames")
        XCTAssertEqual(model.frame?.index, 0)
        XCTAssertEqual(model.frame?.time.seconds ?? -1, 0, accuracy: 0.001)
        await model.step(1)
        XCTAssertEqual(model.frame?.index, 1)
        XCTAssertEqual(model.frame?.time.seconds ?? -1, 1.0 / 30, accuracy: 0.001)
        await model.step(-1)
        XCTAssertEqual(model.frame?.index, 0)
        await model.step(-1)
        XCTAssertEqual(model.frame?.index, 0, "Frame bounds do not invent a frame")
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        model.close()
        XCTAssertNil(model.player)
    }

    @MainActor
    func testNoPlayableOriginalIsAnExplicitStateAndNeverCreatesVideo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let id = try await library.createCapture(seed(), mode: .simulatorFixture)
        let model = ReplayPlaybackModel()
        await model.open(library: library, session: id)
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.player)
        XCTAssertNil(model.frame)
        XCTAssertEqual(model.frameCount, 0)
        XCTAssertEqual(model.document?.id, id.rawValue, "Scoring still has the loaded session")
    }

    private func seed() -> CaptureSessionSeed {
        .init(title: "Actual replay original", players: [
            .init(id: "a", displayName: "Jon", handedness: .unknown, backhand: .unknown, isSelf: true),
            .init(id: "b", displayName: "Alex", handedness: .unknown, backhand: .unknown, isSelf: false)
        ], format: .init(presetId: .bestOf1, setsToWin: .value1, gameScoring: .ad,
                        set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let),
            toss: .init(firstServer: "a", startingEnds: .init(A: .near, B: .far)))
    }
}
