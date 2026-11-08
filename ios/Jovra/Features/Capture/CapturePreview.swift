import AVFoundation
import SwiftUI

/// Actual camera framing; the caller labels the synthetic preview separately from its recorder.
/// Letterboxing preserves the video frame, and the player is never another capture pipeline.
struct CapturePreview: UIViewRepresentable {
    var session: AVCaptureSession?
    var fixture: URL?
    func makeUIView(context: Context) -> CapturePreviewSurface {
        let surface = CapturePreviewSurface()
        if let session {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspect; surface.videoLayer = layer
        } else if let fixture {
            let player = AVQueuePlayer(); player.isMuted = true
            surface.player = player
            surface.loop = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: fixture))
            let layer = AVPlayerLayer(player: player); layer.videoGravity = .resizeAspect
            surface.videoLayer = layer; player.play()
        }
        if let layer = surface.videoLayer { surface.layer.addSublayer(layer) }
        return surface
    }
    func updateUIView(_ surface: CapturePreviewSurface, context: Context) {
        if let layer = surface.videoLayer as? AVCaptureVideoPreviewLayer, layer.session !== session { layer.session = session }
    }
    static func dismantleUIView(_ surface: CapturePreviewSurface, coordinator: ()) { surface.player?.pause() }
}

final class CapturePreviewSurface: UIView {
    var videoLayer: CALayer?
    var player: AVQueuePlayer?
    var loop: AVPlayerLooper?
    override func layoutSubviews() { super.layoutSubviews(); videoLayer?.frame = bounds }
}
