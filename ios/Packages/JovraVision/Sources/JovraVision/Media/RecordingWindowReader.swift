import AVFoundation
import CryptoKit
import Foundation
import JovraCore

public enum RecordingWindowReaderError: Error, Equatable, Sendable {
    /// The segment's file has no video track.
    case noVideoTrack(segment: Int)
    /// AVFoundation could not read the segment.
    case unreadable(segment: Int, detail: String)
}

/// Reads a saved recording (its segment files on the session timeline) window by window with AVFoundation.
///
/// Video is decoded sequentially: consecutive windows continue one `AVAssetReader`, and a window that lies
/// behind what was read (a resume, or a stage reading out of order) starts a new reader at that window,
/// which decodes from the preceding key frame. Either way a frame decodes to the same pixels. Frame times
/// are the segment start plus the frame's presentation time, in microseconds.
public actor RecordingWindowReader: AnalysisWindowReader {
    public struct Source: Sendable {
        public var url: URL
        public var startMs: Int
        public var durationMs: Int
        public init(url: URL, startMs: Int, durationMs: Int) { self.url = url; self.startMs = startMs; self.durationMs = durationMs }
    }

    public nonisolated let info: AnalysisMediaInfo
    private let sources: [Source]
    private let assets: [AVURLAsset]
    private let videoTracks: [AVAssetTrack]
    private var cursor: Cursor?

    /// The open sequential video reader.
    private struct Cursor {
        var segment: Int
        var stream: Int
        var reader: AVAssetReader
        var output: AVAssetReaderTrackOutput
        /// A decoded frame that belongs to a later window.
        var pending: CMSampleBuffer?
        /// The session time of the last frame handed out (µs), -1 before the first.
        var lastReturned: Int64
    }

    private init(sources: [Source], assets: [AVURLAsset], videoTracks: [AVAssetTrack], info: AnalysisMediaInfo) {
        self.sources = sources; self.assets = assets; self.videoTracks = videoTracks; self.info = info
    }

    /// Opens every segment and checks it has video. The fingerprint covers each file's size, duration and
    /// picture size, so a replaced or re-encoded file never resumes an old checkpoint.
    public static func open(_ sources: [Source]) async throws -> RecordingWindowReader {
        var assets: [AVURLAsset] = []
        var videoTracks: [AVAssetTrack] = []
        var identity: [String] = []
        for (index, source) in sources.enumerated() {
            let asset = AVURLAsset(url: source.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            do {
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw RecordingWindowReaderError.noVideoTrack(segment: index)
                }
                let duration = try await asset.load(.duration)
                let size = try await track.load(.naturalSize)
                let bytes = try source.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
                videoTracks.append(track)
                identity.append("\(source.startMs)+\(source.durationMs)|\(bytes)|\(duration.value)/\(duration.timescale)|\(Int(size.width))x\(Int(size.height))")
            } catch let error as RecordingWindowReaderError {
                throw error
            } catch {
                throw RecordingWindowReaderError.unreadable(segment: index, detail: String(describing: error))
            }
            assets.append(asset)
        }
        let digest = SHA256.hash(data: Data(identity.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        let info = AnalysisMediaInfo(segments: sources.map { AnalysisSegment(startMs: $0.startMs, durationMs: $0.durationMs) },
                                     fingerprint: "sha256:" + digest)
        return RecordingWindowReader(sources: sources, assets: assets, videoTracks: videoTracks, info: info)
    }

    // MARK: Video

    public nonisolated func frames(in window: AnalysisWindow) -> AsyncThrowingStream<AnalysisFrame, any Error> {
        let token = Self.nextStreamToken()
        return AsyncThrowingStream(unfolding: { try await self.nextFrame(in: window, stream: token) })
    }

    /// Identifies one `frames(in:)` sequence, so a second sequence over the same window starts again.
    private static let streamCounter = StreamCounter()
    private static func nextStreamToken() -> Int { streamCounter.next() }

    private func nextFrame(in window: AnalysisWindow, stream token: Int) throws -> AnalysisFrame? {
        try Task.checkCancellation()
        let startMicros = Int64(window.startMs) * 1000, endMicros = Int64(window.endMs) * 1000
        if cursor?.stream != token {
            // A new sequence continues the open reader only when it lies ahead of what was handed out.
            if let open = cursor, open.segment == window.segment, open.lastReturned < startMicros {
                cursor?.stream = token
            } else {
                cursor = try makeCursor(for: window, stream: token)
            }
        }
        guard var open = cursor else { return nil }
        defer { cursor = open }
        let segmentStart = Int64(sources[window.segment].startMs) * 1000
        while true {
            let next = open.pending ?? open.output.copyNextSampleBuffer()
            open.pending = nil
            guard let sample = next else {
                if open.reader.status == .failed {
                    throw RecordingWindowReaderError.unreadable(segment: window.segment,
                                                                detail: String(describing: open.reader.error))
                }
                return nil
            }
            guard let image = CMSampleBufferGetImageBuffer(sample) else { continue }
            let local = CMTimeConvertScale(sample.presentationTimeStamp, timescale: 1_000_000, method: .roundHalfAwayFromZero)
            let micros = segmentStart + local.value
            if micros < startMicros { continue }
            if micros >= endMicros {
                open.pending = sample
                return nil
            }
            open.lastReturned = micros
            return AnalysisFrame(time: try MediaTime(value: micros, timescale: 1_000_000), pixelBuffer: image)
        }
    }

    private func makeCursor(for window: AnalysisWindow, stream: Int) throws -> Cursor {
        cursor?.reader.cancelReading()
        let asset = assets[window.segment]
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch {
            throw RecordingWindowReaderError.unreadable(segment: window.segment, detail: String(describing: error))
        }
        let track = videoTracks[window.segment]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        let localStart = window.startMs - sources[window.segment].startMs
        reader.timeRange = CMTimeRange(start: CMTime(value: CMTimeValue(localStart), timescale: 1000), duration: .positiveInfinity)
        guard reader.startReading() else {
            throw RecordingWindowReaderError.unreadable(segment: window.segment, detail: String(describing: reader.error))
        }
        return Cursor(segment: window.segment, stream: stream, reader: reader, output: output, pending: nil, lastReturned: -1)
    }

    // MARK: Audio

    public func audio(in window: AnalysisWindow) async throws -> AnalysisAudio? {
        try Task.checkCancellation()
        let asset = assets[window.segment]
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let descriptions = try await track.load(.formatDescriptions)
        guard let stream = descriptions.first.flatMap({ CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }),
              stream.mSampleRate > 0 else { return nil }
        let rate = stream.mSampleRate
        let localStartMs = window.startMs - sources[window.segment].startMs
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch {
            throw RecordingWindowReaderError.unreadable(segment: window.segment, detail: String(describing: error))
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1, AVSampleRateKey: rate,
        ])
        reader.add(output)
        reader.timeRange = CMTimeRange(start: CMTime(value: CMTimeValue(localStartMs), timescale: 1000),
                                       end: CMTime(value: CMTimeValue(localStartMs + window.endMs - window.startMs), timescale: 1000))
        guard reader.startReading() else {
            throw RecordingWindowReaderError.unreadable(segment: window.segment, detail: String(describing: reader.error))
        }
        let first = Int64((Double(localStartMs) / 1000 * rate).rounded())
        let count = Int((Double(window.endMs - window.startMs) / 1000 * rate).rounded())
        var samples = [Float]()
        samples.reserveCapacity(count)
        var nextIndex = first
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = chunk.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            guard status == kCMBlockBufferNoErr else { continue }
            let bufferStart = Int64((buffer.presentationTimeStamp.seconds * rate).rounded())
            // Keep only the samples inside the window, never repeating one.
            for (offset, value) in chunk.enumerated() {
                let index = bufferStart + Int64(offset)
                guard index >= nextIndex, index < first + Int64(count) else { continue }
                samples.append(value)
                nextIndex = index + 1
            }
        }
        if reader.status == .failed {
            throw RecordingWindowReaderError.unreadable(segment: window.segment, detail: String(describing: reader.error))
        }
        return AnalysisAudio(sampleRate: rate, start: try MediaTime(value: Int64(window.startMs) * 1000, timescale: 1_000_000),
                             samples: samples)
    }
}

/// Numbers `frames(in:)` sequences across all readers.
private final class StreamCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
}
