@preconcurrency import AVFoundation
import Foundation
import JovraCore

public enum ShortGOPProxyError: Error, Equatable, Sendable {
    case noVideo, readFailed, writeFailed, frameCountMismatch(expected: Int, written: Int)
}

/// An intra-only (every frame a sync frame) H.264 copy of a recording's video, used only for backward frame
/// steps. Each frame keeps the original's presentation time, so frame N of the proxy is frame N of the
/// original. The original is never modified; the proxy lives in the caller's proxy folder and can be deleted.
public struct ShortGOPProxy: Sendable {
    public let url: URL
    public let frameCount: Int

    /// Longest side of the proxy; smaller sources keep their size.
    public static let maximumDimension = 1280

    /// Builds a distinct proxy beside `directory`'s other files and publishes it without replacing a file.
    /// The caller supplies an existing private local directory and owns its cache lifecycle.
    public static func build(from source: URL, into directory: URL, frameRate: FrameRate) async throws -> ShortGOPProxy {
        let staged = try await encode(from: source, into: directory, frameRate: frameRate)
        defer { staged.discard() }
        return try staged.publish()
    }

    /// A complete encode with its unique temporary name still in place.
    struct Staged: Sendable {
        let leaf: ProxyLeaf
        let finalName: String
        let frameCount: Int
        var partial: URL { leaf.url }
        var final: URL { leaf.directory.url.appendingPathComponent(finalName) }

        func discard() { leaf.discard() }

        func publish(expectedFrameCount: Int? = nil) throws -> ShortGOPProxy {
            if let expectedFrameCount, frameCount != expectedFrameCount {
                throw ShortGOPProxyError.frameCountMismatch(expected: expectedFrameCount, written: frameCount)
            }
            try Task.checkCancellation()
            return ShortGOPProxy(url: try leaf.publish(as: finalName), frameCount: frameCount)
        }
    }

    static func encode(from source: URL, into directory: URL, frameRate: FrameRate) async throws -> Staged {
        try Task.checkCancellation()
        let receiver = try ProxyDirectory(directory)
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ShortGOPProxyError.noVideo }
        let (naturalSize, transform, timeScale) = try await track.load(.naturalSize, .preferredTransform, .naturalTimeScale)
        let longest = max(naturalSize.width, naturalSize.height)
        let scale = longest > CGFloat(maximumDimension) ? CGFloat(maximumDimension) / longest : 1
        // Even dimensions for 4:2:0.
        let width = Int((naturalSize.width * scale / 2).rounded()) * 2
        let height = Int((naturalSize.height * scale / 2).rounded()) * 2

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ShortGOPProxyError.readFailed }
        reader.add(output)

        let job = "JOVRA-Proxy-" + UUID().uuidString
        let partial = try ProxyLeaf(receiver, name: "\(job).proxy.partial.mov", create: true)
        var keepPartial = false
        defer { if !keepPartial { partial.discard() } }

        // The writer needs a URL. Its pathname stays in process-owned system scratch, never in the receiver.
        let temporary = try ProxyDirectory(FileManager.default.temporaryDirectory)
        let scratch = try temporary.privateChild(job)
        let movie = "encoded.mov"
        defer {
            if let output = try? ProxyLeaf(scratch, name: movie, create: false) { output.discard() }
            temporary.discardPrivateChild(scratch)
        }
        try scratch.verify()
        let writer = try AVAssetWriter(outputURL: scratch.url.appendingPathComponent(movie), fileType: .mov)
        let fps = max(1, Int(frameRate.framesPerSecond.rounded()))
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: [
                AVVideoMaxKeyFrameIntervalKey: 1,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoAverageBitRateKey: width * height * 6,
            ] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        // Keep the original's clock: a coarser movie timescale (AVFoundation's default is 600) rounds 240 fps
        // frame times onto the previous frame, so the proxy's frame N would decode as N-1.
        let clock = timeScale > 0 ? timeScale : CMTimeScale(frameRate.frames)
        input.mediaTimeScale = clock
        writer.movieTimeScale = clock
        guard writer.canAdd(input) else { throw ShortGOPProxyError.writeFailed }
        writer.add(input)

        try Task.checkCancellation()
        try scratch.verify()
        guard reader.startReading(), writer.startWriting() else {
            if reader.status == .reading { reader.cancelReading() }
            throw reader.status == .failed ? ShortGOPProxyError.readFailed : ShortGOPProxyError.writeFailed
        }
        var written = 0
        var started = false
        do {
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard CMSampleBufferGetImageBuffer(sample) != nil else { continue }
                if !started {
                    writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample))
                    started = true
                }
                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    guard writer.status == .writing else { throw ShortGOPProxyError.writeFailed }
                    try await Task.sleep(for: .milliseconds(1))
                }
                guard input.append(sample) else { throw ShortGOPProxyError.writeFailed }
                written += 1
            }
            guard reader.status == .completed else { throw ShortGOPProxyError.readFailed }
            input.markAsFinished()
            await writer.finishWriting()
            try Task.checkCancellation()
            guard writer.status == .completed else { throw ShortGOPProxyError.writeFailed }
        } catch {
            if reader.status == .reading { reader.cancelReading() }
            if writer.status == .writing { writer.cancelWriting() }
            throw error
        }
        let output = try ProxyLeaf(scratch, name: movie, create: false)
        try output.copy(to: partial)
        keepPartial = true
        return Staged(leaf: partial, finalName: "\(job).proxy.mov", frameCount: written)
    }
}

/// Decodes exact frames from a short-GOP proxy. Backward steps on a long-GOP original decode every frame
/// since the previous sync frame; on the proxy each frame decodes alone.
public actor ProxyBackwardStepper {
    public let proxy: ShortGOPProxy
    private let playback: FramePlayback

    public init(proxy: ShortGOPProxy, frameRate: FrameRate) throws {
        self.proxy = proxy
        playback = try FramePlayback(url: proxy.url, rate: frameRate, frameCount: proxy.frameCount)
    }

    /// Builds the proxy for `original` and checks it holds `expectedFrameCount` frames when one is given.
    public static func prepare(original: URL, frameRate: FrameRate, proxyDirectory: URL,
                               expectedFrameCount: Int? = nil) async throws -> ProxyBackwardStepper {
        let staged = try await ShortGOPProxy.encode(from: original, into: proxyDirectory, frameRate: frameRate)
        defer { staged.discard() }
        let proxy = try staged.publish(expectedFrameCount: expectedFrameCount)
        return try ProxyBackwardStepper(proxy: proxy, frameRate: frameRate)
    }

    /// The decoded proxy frame at `index`, verified to be that frame (FramePlayback refuses a mismatch).
    public func frame(at index: Int) async throws -> PlaybackFrame {
        try await playback.frame(at: index)
    }
}
