import AVFoundation
import JovraCore
import JovraMedia
import XCTest
@testable import Jovra

final class NativeCaptureCoordinatorTests: XCTestCase {
    @MainActor
    func testFixtureCaptureSavesFreshDecodableOriginalThroughTheSharedLibrary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let sourceURL = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let clock = VirtualCaptureClock()
        let camera = FixtureCamera(url: sourceURL, duration: CMTime(value: 4, timescale: 1), clock: clock)
        let capture = NativeCaptureCoordinator(library: library, source: camera, clock: clock)
        let seed = CaptureSessionSeed(title: "Native fixture capture", players: [
            .init(id: "a", displayName: "Player A", handedness: .unknown, backhand: .unknown, isSelf: true),
            .init(id: "b", displayName: "Player B", handedness: .unknown, backhand: .unknown, isSelf: false),
        ], format: .init(presetId: .bestOf1, setsToWin: .value1, gameScoring: .ad,
                         set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let),
            toss: .init(firstServer: "a", startingEnds: .init(A: .near, B: .far)))
        try await capture.prepare(seed: seed, preset: .init(width: 1280, height: 720), microphone: .denied)
        try await capture.start()
        try await camera.waitUntilFinished()
        try await capture.stop()
        let id = try XCTUnwrap(capture.sessionID)
        let saved = try XCTUnwrap(capture.savedRecording)
        XCTAssertTrue(saved.mediaAvailable)
        XCTAssertEqual(saved.microphone, .denied)
        XCTAssertEqual(saved.segments.count, 1)
        XCTAssertTrue(saved.segments[0].finalized)
        let reopened = try LocalCaptureLibrary(root: root)
        let session = try await reopened.load(id)
        XCTAssertEqual(session.recording, saved)
        XCTAssertEqual(session.original?.state, .saved)
        XCTAssertEqual(session.sample?.synthetic, true)
        XCTAssertEqual(session.match?.log.count, 0)
        let original = try await reopened.fileURL(id, relativePath: saved.segments[0].file.path)
        let info = try await MediaProbe.probe(original)
        XCTAssertEqual(info.video?.isDecodable, true)
        XCTAssertNil(info.audio, "Denied microphone cannot block video or silently add sound")
        XCTAssertEqual(info.duration.seconds, 4, accuracy: 1.0 / 30)
        XCTAssertNotEqual(try Data(contentsOf: original), try Data(contentsOf: sourceURL), "Capture re-encodes; it never copies the bundled source")
        let frames = try await Self.decodedFrames(original)
        XCTAssertEqual(frames, 120)
    }

    private static func decodedFrames(_ url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var count = 0
        while output.copyNextSampleBuffer() != nil { count += 1 }
        XCTAssertEqual(reader.status, .completed)
        return count
    }
}
