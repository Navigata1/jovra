@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import JovraCore

public enum FramePlaybackError: Error, Equatable, Sendable {
    case invalidSource, outOfRange, noVideo, unavailableFrame(expected: Int, actual: Int)
}

public struct PlaybackFrame: Sendable {
    public let image: CGImage
    public let index: Int
    /// Presentation time on this video's normalized AVFoundation timeline.
    public let time: CMTime
}

/// Exact still-frame lookup for a known constant-rate source. The caller supplies the recording's
/// verified frame count/rate; imported variable-rate material needs a presentation-time index first.
/// A frame returned by this adapter has been decoded, rather than inferred from a player readout.
public actor FramePlayback {
    private let asset: AVURLAsset
    private let generator: AVAssetImageGenerator
    private let rate: FrameRate
    private let frameCount: Int
    private var videoStart: CMTime?

    public init(url: URL, rate: FrameRate, frameCount: Int) throws {
        guard url.isFileURL, frameCount > 0, rate.frames <= Int(Int32.max),
              !Int64(frameCount - 1).multipliedReportingOverflow(by: Int64(rate.perSeconds)).overflow,
              FileManager.default.fileExists(atPath: url.path) else {
            throw FramePlaybackError.invalidSource
        }
        self.rate = rate; self.frameCount = frameCount
        let asset = AVURLAsset(url: url)
        self.asset = asset
        generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
    }

    public func frame(at index: Int) async throws -> PlaybackFrame {
        try Task.checkCancellation()
        guard (0..<frameCount).contains(index) else { throw FramePlaybackError.outOfRange }
        let start: CMTime
        if let cached = videoStart { start = cached }
        else {
            guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw FramePlaybackError.noVideo }
            start = try await video.load(.timeRange).start
            videoStart = start
        }
        let requested = CMTimeAdd(start, CMTime(frame: index, at: rate))
        let (image, actual) = try await generator.image(at: requested)
        try Task.checkCancellation()
        let normalized = CMTimeSubtract(actual, start)
        let decodedIndex = normalized.frameIndex(at: rate)
        guard decodedIndex == index else { throw FramePlaybackError.unavailableFrame(expected: index, actual: decodedIndex) }
        return .init(image: image, index: decodedIndex, time: normalized)
    }
}
