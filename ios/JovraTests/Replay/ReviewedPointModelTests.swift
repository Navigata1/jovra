import AVFoundation
import JovraCore
import JovraMedia
import XCTest
@testable import Jovra

final class ReviewedPointModelTests: XCTestCase {
    @MainActor
    func testReviewedCorrectionRefoldsLaterScoreStatsAndPersistsWithoutInventingObservations() async throws {
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
        let model = ReviewedPointModel()
        await model.open(library: library, session: id)
        for (index, winner) in [Side.a, .a, .a, .b].enumerated() {
            await model.append(winner: winner, startMs: index * 500, endMs: (index + 1) * 500)
            XCTAssertNil(model.error)
        }
        XCTAssertEqual(model.points.count, 4)
        XCTAssertEqual(model.pointsWonAFraction, "3/4")
        let first = try XCTUnwrap(model.points.first).id
        let second = model.points[1].id
        model.select(first)
        await model.correct(winner: .b)
        XCTAssertNil(model.error)
        XCTAssertNotEqual(model.selectedID, first, "Selection follows the correction's active replacement")
        model.select(second)
        XCTAssertEqual(model.scoreBefore, "0–15")
        XCTAssertEqual(model.pointsWonAFraction, "2/4")
        XCTAssertEqual(model.pointsWonA?.evidence.provenance, .reviewed)
        XCTAssertEqual(model.pointsWonA?.evidence.sample, true)
        XCTAssertNil(model.firstServeInA?.value)
        XCTAssertNil(model.shots?.value)
        XCTAssertEqual(model.document?.match?.log.count, 5, "Original decisions remain in history")
        let reopened = try LocalCaptureLibrary(root: root)
        let restored = ReviewedPointModel()
        await restored.open(library: reopened, session: id)
        restored.select(second)
        XCTAssertEqual(restored.scoreBefore, "0–15")
        XCTAssertEqual(restored.pointsWonAFraction, "2/4")
        await restored.append(winner: .a, startMs: -1, endMs: 100)
        XCTAssertNotNil(restored.error)
        XCTAssertEqual(restored.points.count, 4)
        XCTAssertEqual(restored.document?.match?.log.count, 5)
    }

    private func seed() -> CaptureSessionSeed {
        .init(title: "Reviewed native points", players: [
            .init(id: "a", displayName: "Jon", handedness: .unknown, backhand: .unknown, isSelf: true),
            .init(id: "b", displayName: "Alex", handedness: .unknown, backhand: .unknown, isSelf: false)
        ], format: .init(presetId: .bestOf1, setsToWin: .value1, gameScoring: .ad,
                        set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let),
            toss: .init(firstServer: "a", startingEnds: .init(A: .near, B: .far)))
    }
}
