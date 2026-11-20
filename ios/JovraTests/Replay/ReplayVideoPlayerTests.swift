import AVKit
import XCTest
@testable import Jovra

final class ReplayVideoPlayerTests: XCTestCase {
    /// With the analysis on, a paused frame inside the replay scroll view crashed the app.
    @MainActor
    func testReplayPlayerTurnsOffVideoFrameAnalysisAndKeepsThePlayer() {
        let player = AVPlayer()

        let controller = ReplayVideoPlayer.makeController(player: player)

        XCTAssertFalse(controller.allowsVideoFrameAnalysis)
        XCTAssertTrue(controller.player === player)
        XCTAssertTrue(AVPlayerViewController().allowsVideoFrameAnalysis, "The system default is on, so the setting above is what turns it off")
    }
}
