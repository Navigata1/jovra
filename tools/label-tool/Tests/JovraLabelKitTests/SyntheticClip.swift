import AVFoundation
import CoreVideo
import Foundation
import JovraBenchmark

/// Small synthetic recordings written by the tests themselves, for the timing shapes the rendered sample
/// video (60 fps, every frame time a whole 1/90000 s tick) does not have: a container time base that is not
/// a divisor of 90 kHz, and 30 fps with sharp sounds that start late in their frame.
///
/// Flat grey frames with a moving bar and, optionally, short 4 kHz bursts. Nothing here comes from a real
/// recording, and nothing is kept: each clip goes to the test's scratch folder.
enum SyntheticClip {
    struct Shape {
        /// The video track's time base: frame `k` is shown at `k * ticksPerFrame / timescale` seconds.
        var timescale: Int32
        var ticksPerFrame: Int64
        var frames: Int
        /// Where 5 ms bursts start, in seconds. Empty means no audio track.
        var clicks: [Double] = []

        func frame(_ index: Int64) -> RationalTime {
            RationalTime(value: index * ticksPerFrame, timescale: Int64(timescale))
        }

        /// The index of the frame on screen at `seconds`.
        func frameIndex(at seconds: Double) -> Int64 {
            Int64((seconds * Double(timescale) / Double(ticksPerFrame)).rounded(.down))
        }
    }

    /// The founder's match recording has this time base: 1/29589 s, a frame every 1000 ticks. Its frame times
    /// are not whole 1/90000 s ticks (frame 2 is 6083.3 of them).
    static let oddTimeBase = Shape(timescale: 29_589, ticksPerFrame: 1000, frames: 45)

    /// 30 fps, with three bursts that start 26 to 28 ms into their frame and one on a frame boundary.
    static let thirtyFramesPerSecond = Shape(timescale: 600, ticksPerFrame: 20, frames: 135, clicks: [1.026, 2.027, 3.028, 3.5])

    enum WriteError: Error {
        case notStarted(String)
        case pixelBuffer
        case audioBuffer(OSStatus)
        case failed(String)
    }

    static let width = 320, height = 180
    static let sampleRate = 48_000

    static func write(_ shape: Shape, to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieTimeScale = shape.timescale
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            // No reordering: a frame's presentation time is its position in the file.
            AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false, AVVideoMaxKeyFrameIntervalKey: 15],
        ])
        video.mediaTimeScale = shape.timescale
        video.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(video)
        let end = CMTime(value: Int64(shape.frames) * shape.ticksPerFrame, timescale: shape.timescale)
        let sound = shape.clicks.isEmpty ? nil : try audioBuffer(clicks: shape.clicks, seconds: end.seconds)
        var audio: AVAssetWriterInput?
        if let sound {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: CMSampleBufferGetFormatDescription(sound))
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audio = input
        }
        guard writer.startWriting() else { throw WriteError.notStarted(writer.error?.localizedDescription ?? "unknown") }
        writer.startSession(atSourceTime: .zero)
        // The sound goes in first, whole: with it finished the writer never holds the picture back to interleave.
        if let audio, let sound {
            try await ready(audio, writer)
            guard audio.append(sound) else { throw WriteError.failed(writer.error?.localizedDescription ?? "the sound was refused") }
            audio.markAsFinished()
        }
        for index in 0..<shape.frames {
            try await ready(video, writer)
            let time = CMTime(value: Int64(index) * shape.ticksPerFrame, timescale: shape.timescale)
            guard adaptor.append(try picture(index: index, of: shape.frames), withPresentationTime: time) else {
                throw WriteError.failed(writer.error?.localizedDescription ?? "a frame was refused")
            }
        }
        video.markAsFinished()
        writer.endSession(atSourceTime: end)
        // The completion-handler form, resumed by hand: see `AssetLoading` for why this package emits no
        // compiler-made async bridge for an AVFoundation call that JovraMedia also makes.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw WriteError.failed(writer.error?.localizedDescription ?? "not completed") }
    }

    private static func ready(_ input: AVAssetWriterInput, _ writer: AVAssetWriter) async throws {
        let deadline = Date().addingTimeInterval(30)
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing else { throw WriteError.failed(writer.error?.localizedDescription ?? "the writer stopped") }
            guard Date() < deadline else { throw WriteError.failed("the writer took no more data for 30 s") }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// Grey that brightens through the clip, with a white bar that moves a little every frame.
    private static func picture(index: Int, of count: Int) throws -> CVPixelBuffer {
        var made: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &made)
        guard let buffer = made else { throw WriteError.pixelBuffer }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw WriteError.pixelBuffer }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let grey = UInt8(48 + 120 * index / max(count, 1))
        let barStart = (index * 6) % (width - 16)
        for row in 0..<height {
            let line = base.advanced(by: row * rowBytes).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width {
                let value: UInt8 = (barStart..<(barStart + 16)).contains(column) ? 235 : grey
                line[column * 4] = value
                line[column * 4 + 1] = value
                line[column * 4 + 2] = value
                line[column * 4 + 3] = 255
            }
        }
        return buffer
    }

    /// Mono 16-bit sound: silence with a decaying 4 kHz burst of 5 ms at each click.
    private static func audioBuffer(clicks: [Double], seconds: Double) throws -> CMSampleBuffer {
        let count = Int((seconds * Double(sampleRate)).rounded())
        var samples = [Int16](repeating: 0, count: count)
        let burst = sampleRate / 200
        for click in clicks {
            let start = Int((click * Double(sampleRate)).rounded())
            for offset in 0..<burst where start + offset < count {
                let phase = 2 * Double.pi * 4000 * Double(offset) / Double(sampleRate)
                samples[start + offset] = Int16(0.6 * 32_767 * cos(phase) * Double(burst - offset) / Double(burst))
            }
        }
        var description = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        var status = CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                                    magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard status == noErr, let format else { throw WriteError.audioBuffer(status) }
        let bytes = count * MemoryLayout<Int16>.size
        var block: CMBlockBuffer?
        status = CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                                    customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
        guard status == kCMBlockBufferNoErr, let block else { throw WriteError.audioBuffer(status) }
        status = samples.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) }
        guard status == kCMBlockBufferNoErr else { throw WriteError.audioBuffer(status) }
        var sample: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
            presentationTimeStamp: .zero, packetDescriptions: nil, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw WriteError.audioBuffer(status) }
        return sample
    }
}
