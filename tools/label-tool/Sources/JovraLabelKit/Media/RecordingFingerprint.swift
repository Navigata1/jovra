import AVFoundation
import CryptoKit
import Foundation
import JovraBenchmark
import JovraMedia

public enum RecordingError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    case noVideo
    case notDecodable(String)

    public var description: String {
        switch self {
        case .unreadable(let reason): "The file could not be read: \(reason)"
        case .noVideo: "This file has no video track."
        case .notDecodable(let codec): "This Mac cannot decode the video (\(codec))."
        }
    }
}

/// Identifies a recording by its bytes and reads the facts a label file records about it. The file is read
/// locally and nothing about it is stored except the hash, the size and the picture's shape.
public enum RecordingFingerprint {
    /// SHA-256 of the file, streamed so a two-hour recording never sits in memory.
    public static func sha256(of url: URL, chunkSize: Int = 4 << 20) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw RecordingError.unreadable(error.localizedDescription)
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public struct Result: Sendable {
        public let recording: BenchmarkLabels.Recording
        /// Clockwise rotation the track asks for on display (0, 90, 180 or 270).
        public let rotationDegrees: Int
        public let hasAudio: Bool
    }

    public static func read(_ url: URL) async throws -> Result {
        let info: MediaInfo
        do {
            info = try await MediaProbe.probe(url)
        } catch {
            throw RecordingError.unreadable(error.localizedDescription)
        }
        guard let video = info.video else { throw RecordingError.noVideo }
        guard video.isDecodable else { throw RecordingError.notDecodable(video.fourCC) }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let hash = try await Task.detached(priority: .userInitiated) { try sha256(of: url) }.value
        let duration = info.duration.isNumeric && info.duration.value > 0
            ? RationalTime(value: info.duration.value, timescale: Int64(info.duration.timescale))
            : RationalTime(value: 0, timescale: 1)
        let rate = video.frameRate.map { BenchmarkLabels.FrameRate(num: $0.frames, den: $0.perSeconds) } ?? .init(num: 30, den: 1)
        let recording = BenchmarkLabels.Recording(sha256: hash, byteSize: size, duration: duration, width: video.displayWidth,
                                                  height: video.displayHeight, frameRate: rate,
                                                  variableFrameRate: video.isVariableFrameRate)
        return Result(recording: recording, rotationDegrees: video.rotationDegrees, hasAudio: info.audio != nil)
    }
}
