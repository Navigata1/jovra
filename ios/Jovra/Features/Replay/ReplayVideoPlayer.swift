import AVKit
import SwiftUI

/// The system player with video-frame analysis (Live Text on a paused frame) turned off.
///
/// SwiftUI's `VideoPlayer` leaves the analysis on. Inside a `ScrollView`, the analysis view asks the
/// hosting scroll view for its gesture container when a paused frame's result arrives, and SwiftUI
/// aborts in AttributeGraph: the app crashed on the replay screen. Tennis footage has no text worth
/// selecting, so nothing is lost by turning it off.
struct ReplayVideoPlayer: UIViewControllerRepresentable {
    var player: AVPlayer

    /// Builds the controller. Separate from `makeUIViewController` so a test can check its settings.
    @MainActor static func makeController(player: AVPlayer) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.allowsVideoFrameAnalysis = false
        controller.player = player
        return controller
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        Self.makeController(player: player)
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
