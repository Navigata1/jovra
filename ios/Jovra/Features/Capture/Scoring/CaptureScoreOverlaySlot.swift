import JovraCore
import SwiftUI

/// Marks a point at the live edge of the recording. T24 adds ScorePad outcomes behind the same seam; the
/// recording phase only ever calls `markPoint()` and shows the returned session time.
@MainActor
protocol MarkPointAction {
    /// The mark's session time in milliseconds.
    func markPoint() throws -> Int
}

/// The capture engine's own bookmark, the action used until live scoring exists.
struct EngineMarkPointAction: MarkPointAction {
    let coordinator: NativeCaptureCoordinator

    func markPoint() throws -> Int {
        let time = try coordinator.markPoint()
        guard time.timescale > 0 else { return 0 }
        return Int(time.value * 1000 / Int64(time.timescale))
    }
}

/// The score overlay's slot over the live preview (top leading). T24 fills it with the manual-score
/// ScoreboardOverlay; until then there is no score to show, so it draws nothing rather than an empty
/// card or a made-up score.
struct CaptureScoreOverlaySlot: View {
    var competitionMode: Bool

    var body: some View {
        EmptyView()
    }
}
