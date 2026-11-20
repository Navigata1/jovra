import Foundation
import JovraCore
import JovraVision
import XCTest
@testable import Jovra

/// V00: the app side of the JovraVision pipeline: registration as the analyze stage, where a session's
/// analysis lives, and what happens when there is nothing saved to analyse.
final class VisionAnalyzerTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("JOVRA-vision-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testTheVisionFixtureRegistersTheVisionPipelineAsTheAnalyzeStage() throws {
        var launch = LaunchConfiguration()
        launch.processingAnalyzer = .visionFixture
        let analyzers = AnalyzerRegistry.registered(for: launch, library: .ready(try LocalCaptureLibrary(root: root)))
        XCTAssertEqual(analyzers.count, 1)
        XCTAssertTrue(analyzers.first is VisionAnalyzer)
        XCTAssertTrue(AnalyzerRegistry.registered(for: launch, library: .unavailable).isEmpty,
                      "without a library there is nothing to read, so nothing is registered")
        XCTAssertTrue(AnalyzerRegistry.registered(for: LaunchConfiguration(), library: .unavailable).isEmpty,
                      "production registers no analyzer until a V ticket passes its gate")
    }

    func testASessionWithNoSavedRecordingFailsInsteadOfAnalysingNothing() async throws {
        let library = try LocalCaptureLibrary(root: root)
        let session = try await library.createCapture(Self.seed, mode: .simulatorFixture)
        let analyzer = VisionAnalyzer(capabilityID: "fixture.vision", library: library, stages: { FixtureStages.pipeline() })
        do {
            try await analyzer.analyze(session, attempt: 1, from: 0) { _ in XCTFail("no progress without a recording") }
            XCTFail("expected a failure")
        } catch is VisionAnalyzer.NoRecording {}
        let analysis = await library.analysisFolder(session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: analysis.path), "nothing is written for it")
    }

    func testASessionsAnalysisLivesBesideItAndGoesWhenItIsDeleted() async throws {
        let library = try LocalCaptureLibrary(root: root)
        let session = try await library.createCapture(Self.seed, mode: .simulatorFixture)
        let analysis = await library.analysisFolder(session)
        XCTAssertEqual(analysis.deletingLastPathComponent().lastPathComponent, "analysis")
        XCTAssertFalse(analysis.path.contains("/sessions/"), "never inside the session folder the store owns")
        try FileManager.default.createDirectory(at: analysis, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: analysis.appendingPathComponent("fixture.luma.output.json"))

        try await library.deleteCapture(session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: analysis.path))
    }

    private static let seed = CaptureSessionSeed(title: "Vision fixture", players: [
        .init(id: "a", displayName: "Player A", handedness: .unknown, backhand: .unknown, isSelf: true),
        .init(id: "b", displayName: "Player B", handedness: .unknown, backhand: .unknown, isSelf: false),
    ], format: .init(presetId: .bestOf1, setsToWin: .value1, gameScoring: .ad,
                     set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let),
        toss: .init(firstServer: "a", startingEnds: .init(A: .near, B: .far)))
}
