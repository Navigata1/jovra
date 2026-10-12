import AVFoundation
import JovraCore
import JovraMedia
import XCTest
@testable import Jovra

final class NativeExportModelTests: XCTestCase {
    @MainActor
    func testActualSavedCaptureExportsFourFilesOnlyAfterDurableAcknowledgment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let source = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let clock = VirtualCaptureClock()
        let camera = FixtureCamera(url: source, duration: CMTime(value: 2, timescale: 1), clock: clock)
        let capture = NativeCaptureCoordinator(library: library, source: camera, clock: clock)
        try await capture.prepare(seed: seed(), preset: .init(width: 1280, height: 720), microphone: .denied)
        try await capture.start(); try await camera.waitUntilFinished(); try await capture.stop()
        let id = try XCTUnwrap(capture.sessionID)
        let segment = try XCTUnwrap(capture.savedRecording?.segments.first)
        let original = try await library.fileURL(id, relativePath: segment.file.path)
        let bytes = try Data(contentsOf: original)
        let model = NativeExportModel()
        await model.open(library: library, session: id)
        XCTAssertFalse(model.includeAudio)
        XCTAssertNil(model.package)
        model.includeAudio = true // Requested audio cannot create a track in the silent original.
        model.fromText = "0"; model.toText = "1000"
        await model.export()
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.error)
        let package = try XCTUnwrap(model.package)
        XCTAssertEqual(package.eventLogVersion, 0)
        XCTAssertFalse(package.includesAudio)
        XCTAssertEqual(package.videoFrames, 30)
        for url in [package.clip, package.sessionJSON, package.pointsCSV, package.statsCSV] {
            XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)
        }
        let decoded = try await decodeCaptureToEnd(package.clip)
        XCTAssertEqual(decoded.videoFrames, 30)
        let current = try await library.load(id)
        XCTAssertEqual(current.exports?.filter { $0.status == .done }.count, 2)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        XCTAssertEqual(model.currentVersion, package.eventLogVersion)
        XCTAssertEqual(model.isStale, false)
        model.toText = "3000"
        await model.export()
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.package, "A failed new request must not present the prior files as newly done")
        let after = try await library.load(id)
        XCTAssertEqual(after.exports?.count, 2)
        await model.open(library: library, session: id)
        XCTAssertFalse(model.includeAudio, "A reopened session starts with audio off again")
    }

    private func seed() -> CaptureSessionSeed {
        .init(title: "Native export original", players: [
            .init(id: "a", displayName: "Jon", handedness: .unknown, backhand: .unknown, isSelf: true),
            .init(id: "b", displayName: "Alex", handedness: .unknown, backhand: .unknown, isSelf: false)
        ], format: .init(presetId: .bestOf1, setsToWin: .value1, gameScoring: .ad,
            set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let),
            toss: .init(firstServer: "a", startingEnds: .init(A: .near, B: .far)))
    }
}
