import CoreVideo
import Foundation
import JovraCore
import JovraVision

/// A synthetic recording held in memory: `fps` frames a second whose every pixel has the luma `luma(frame)`.
/// It stands in for a decoded video where a test needs exact, hand-checkable pixel values.
struct SyntheticReader: AnalysisWindowReader {
    struct Segment: Sendable { var startMs: Int; var durationMs: Int }

    var segments: [Segment]
    var fps: Int
    var luma: @Sendable (Int) -> UInt8
    /// Distinguishes recordings with the same timing (part of the fingerprint, like a file's bytes).
    var name: String
    /// Counts `frames(in:)` calls; the reader throws `SimulatedKill` on the call with this number (1-based).
    private(set) var killOnRequest: Int?
    private(set) var requests = Counter()

    init(name: String = "synthetic", segments: [Segment], fps: Int, luma: @escaping @Sendable (Int) -> UInt8) {
        self.name = name; self.segments = segments; self.fps = fps; self.luma = luma
    }

    /// A copy with its own request count that dies on request `number`.
    func killing(onRequest number: Int) -> SyntheticReader {
        var copy = SyntheticReader(name: name, segments: segments, fps: fps, luma: luma)
        copy.killOnRequest = number
        return copy
    }

    var info: AnalysisMediaInfo {
        AnalysisMediaInfo(segments: segments.map { AnalysisSegment(startMs: $0.startMs, durationMs: $0.durationMs) },
                          fingerprint: "\(name)-\(fps)fps-" + segments.map { "\($0.startMs)+\($0.durationMs)" }.joined(separator: ","))
    }

    func frames(in window: AnalysisWindow) -> AsyncThrowingStream<AnalysisFrame, any Error> {
        let request = requests.increment()
        let segment = segments[window.segment]
        let killed = killOnRequest == request
        let fps = fps, luma = luma
        return AsyncThrowingStream { continuation in
            if killed { continuation.finish(throwing: SimulatedKill()); return }
            // Frame n of the segment is at n / fps seconds after its start.
            let first = (window.startMs - segment.startMs) * fps / 1000
            var frame = first
            while true {
                let localMicros = Int64(frame) * 1_000_000 / Int64(fps)
                let sessionMicros = Int64(segment.startMs) * 1000 + localMicros
                if sessionMicros >= Int64(window.endMs) * 1000 { break }
                if sessionMicros >= Int64(window.startMs) * 1000 {
                    let value = luma(frame)
                    continuation.yield(AnalysisFrame(time: try! MediaTime(value: sessionMicros, timescale: 1_000_000),
                                                     pixelBuffer: Self.buffer(filledWith: value)))
                }
                frame += 1
            }
            continuation.finish()
        }
    }

    func audio(in window: AnalysisWindow) async throws -> AnalysisAudio? { nil }

    static func buffer(filledWith value: UInt8, width: Int = 8, height: Int = 4) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8, nil, &buffer)
        let pixels = buffer!
        CVPixelBufferLockBaseAddress(pixels, [])
        let base = CVPixelBufferGetBaseAddress(pixels)!
        memset(base, Int32(value), CVPixelBufferGetBytesPerRow(pixels) * height)
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return pixels
    }
}

struct SimulatedKill: Error {}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int { lock.withLock { value += 1; return value } }
    var current: Int { lock.withLock { value } }
}

enum Workspace {
    static func make(_ name: String = #function) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jovra-vision-tests", isDirectory: true)
            .appendingPathComponent("\(name.filter(\.isLetter))-\(UUID().uuidString)", isDirectory: true)
    }
}
