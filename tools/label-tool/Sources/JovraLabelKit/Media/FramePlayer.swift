import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import QuartzCore
import VideoToolbox

/// Plays one local recording and reports the frame that is on screen, with that frame's own presentation
/// time. The time comes from the decoded frame, not from a clock, so a label lands on the exact frame even
/// when the recording's frame rate varies.
@MainActor
public final class FramePlayer {
    public struct Frame {
        public let time: CMTime
        public let image: CGImage
    }

    public var onFrame: ((Frame) -> Void)?
    public var onPlayingChanged: ((Bool) -> Void)?

    private let player = AVPlayer()
    private var output: AVPlayerItemVideoOutput?
    private var poll: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?
    private var rotationDegrees = 0
    private let context = CIContext()
    public private(set) var isPlaying = false
    public private(set) var rate: Float = 1
    public private(set) var duration: CMTime = .zero

    public init(muted: Bool = false) {
        player.isMuted = muted
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = false
    }

    public func load(_ url: URL, rotationDegrees: Int) async throws {
        stop()
        let asset = AVURLAsset(url: url)
        duration = try await asset.load(.duration)
        self.rotationDegrees = rotationDegrees
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .timeDomain
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        self.output = output
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setPlaying(false) }
        }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                self?.deliverNewFrame()
                try? await Task.sleep(nanoseconds: 8_000_000)
            }
        }
        await seek(to: .zero)
    }

    public func stop() {
        poll?.cancel()
        poll = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        output = nil
        setPlaying(false)
    }

    public func play() {
        guard player.currentItem != nil else { return }
        if let item = player.currentItem, duration.isNumeric, CMTimeCompare(item.currentTime(), duration) >= 0 { return }
        player.rate = rate
        setPlaying(true)
    }

    public func pause() {
        player.pause()
        setPlaying(false)
    }

    public func setRate(_ rate: Float) {
        self.rate = rate
        if isPlaying { player.rate = rate }
    }

    /// Moves by whole frames. Pauses first: stepping is always from a still frame.
    public func step(by frames: Int) {
        pause()
        player.currentItem?.step(byCount: frames)
    }

    /// Shows the frame on screen at `time` (the last frame that starts at or before it).
    public func seek(to time: CMTime) async {
        let target = CMTimeClampToRange(time, range: CMTimeRange(start: .zero, duration: duration.isNumeric ? duration : .positiveInfinity))
        await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func currentTime() -> CMTime {
        player.currentTime()
    }

    private func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        isPlaying = playing
        onPlayingChanged?(playing)
    }

    private func deliverNewFrame() {
        guard let output, player.currentItem != nil else { return }
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: itemTime) else { return }
        var shown = CMTime.invalid
        guard let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &shown), let image = image(from: buffer) else { return }
        onFrame?(Frame(time: shown.isNumeric ? shown : itemTime, image: image))
    }

    private func image(from buffer: CVPixelBuffer) -> CGImage? {
        if rotationDegrees == 0 {
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
            if let image { return image }
        }
        let orientation: CGImagePropertyOrientation
        switch rotationDegrees {
        case 90: orientation = .right
        case 180: orientation = .down
        case 270: orientation = .left
        default: orientation = .up
        }
        let upright = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        return context.createCGImage(upright, from: upright.extent)
    }
}
