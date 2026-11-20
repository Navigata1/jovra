import CoreVideo
import Foundation
import JovraCore

/// One recorded segment on the session timeline (gaps between segments are not recording).
public struct AnalysisSegment: Codable, Equatable, Sendable {
    public var startMs: Int
    public var durationMs: Int
    public init(startMs: Int, durationMs: Int) { self.startMs = startMs; self.durationMs = durationMs }
}

/// What a reader can say about the recording before decoding anything.
public struct AnalysisMediaInfo: Codable, Equatable, Sendable {
    public var segments: [AnalysisSegment]
    /// Changes whenever the media changes; checkpoints and outputs carry it.
    public var fingerprint: String
    public init(segments: [AnalysisSegment], fingerprint: String) {
        self.segments = segments; self.fingerprint = fingerprint
    }
}

/// One decoded video frame at its session time (microseconds, so frame times stay exact enough for 240 fps
/// and identical between an interrupted and an uninterrupted run).
public struct AnalysisFrame: @unchecked Sendable {
    public let time: MediaTime
    /// Read-only. 8-bit luma in plane 0 (bi-planar 4:2:0 from the asset reader, one-component in fixtures).
    public let pixelBuffer: CVPixelBuffer

    public init(time: MediaTime, pixelBuffer: CVPixelBuffer) {
        self.time = time; self.pixelBuffer = pixelBuffer
    }

    public var width: Int { CVPixelBufferGetWidth(pixelBuffer) }
    public var height: Int { CVPixelBufferGetHeight(pixelBuffer) }

    /// Mean of the 8-bit luma plane, sampled every `step` pixels in both directions, rounded to an integer.
    public func meanLuma(step: Int = 4) -> Int {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let planar = CVPixelBufferIsPlanar(pixelBuffer)
        guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) : CVPixelBufferGetBaseAddress(pixelBuffer)
        else { return 0 }
        let rowBytes = planar ? CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) : CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = planar ? CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) : CVPixelBufferGetWidth(pixelBuffer)
        let height = planar ? CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) : CVPixelBufferGetHeight(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0, count = 0
        for y in stride(from: 0, to: height, by: max(1, step)) {
            for x in stride(from: 0, to: width, by: max(1, step)) {
                sum += Int(bytes[y * rowBytes + x]); count += 1
            }
        }
        return count == 0 ? 0 : (sum + count / 2) / count
    }
}

/// Mono audio for one window, as 32-bit float samples starting at `start`.
public struct AnalysisAudio: Equatable, Sendable {
    public let sampleRate: Double
    public let start: MediaTime
    public let samples: [Float]
    public init(sampleRate: Double, start: MediaTime, samples: [Float]) {
        self.sampleRate = sampleRate; self.start = start; self.samples = samples
    }
}

/// A stage's view of the recording: frames and audio for one window at a time. Frames are pulled one by one
/// (never buffered for a whole window), so a stage at 4K holds only the frames it keeps.
public protocol AnalysisWindowReader: Sendable {
    var info: AnalysisMediaInfo { get }
    /// The window's frames in presentation order.
    func frames(in window: AnalysisWindow) -> AsyncThrowingStream<AnalysisFrame, any Error>
    /// The window's audio, or nil when the recording has none.
    func audio(in window: AnalysisWindow) async throws -> AnalysisAudio?
}
