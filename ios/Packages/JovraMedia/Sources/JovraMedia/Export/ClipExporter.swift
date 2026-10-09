@preconcurrency import AVFoundation
import Foundation
import Darwin

public enum ClipExportError: Error, Equatable, Sendable {
    case invalidRange, noVideo, destinationExists, unsupportedExport, failed(String), filesystem(Int32)
}

public struct ClipExportResult: Sendable {
    public let videoFrames: Int
    public let duration: CMTime
    public let includesAudio: Bool
}

/// A local, re-encoded clip from one source segment. The half-open range is relative to the first
/// video presentation timestamp, not the container's mux offset. Audio is excluded by default.
public enum ClipExporter {
    public static func exportClip(source: URL, range: CMTimeRange, destination: URL,
                                  includeAudio: Bool = false) async throws -> ClipExportResult {
        try Task.checkCancellation()
        guard range.isValid, range.start.isNumeric, range.duration.isNumeric,
              CMTimeCompare(range.start, .zero) >= 0, CMTimeCompare(range.duration, .zero) > 0 else {
            throw ClipExportError.invalidRange
        }
        // attributesOfItem detects dangling links as well as existing files; never replace either.
        guard (try? FileManager.default.attributesOfItem(atPath: destination.path)) == nil else {
            throw ClipExportError.destinationExists
        }
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw ClipExportError.noVideo }
        let bounds = try await video.load(.timeRange)
        guard CMTimeCompare(range.end, bounds.duration) <= 0 else { throw ClipExportError.invalidRange }
        let chosen = CMTimeRange(start: CMTimeAdd(bounds.start, range.start), duration: range.duration)
        let composition = AVMutableComposition()
        guard let outputVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ClipExportError.unsupportedExport
        }
        try outputVideo.insertTimeRange(chosen, of: video, at: .zero)
        outputVideo.preferredTransform = try await video.load(.preferredTransform)
        if includeAudio, let audio = try await asset.loadTracks(withMediaType: .audio).first {
            let overlap = CMTimeRangeGetIntersection(chosen, otherRange: try await audio.load(.timeRange))
            if overlap.isValid, CMTimeCompare(overlap.duration, .zero) > 0 {
                guard let outputAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw ClipExportError.unsupportedExport
                }
                try outputAudio.insertTimeRange(overlap, of: audio, at: CMTimeSubtract(overlap.start, chosen.start))
            }
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ClipExportError.unsupportedExport
        }
        session.metadata = []
        session.shouldOptimizeForNetworkUse = true
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".clip-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let job = ClipExportJob(session: session, destination: temporary)
        try await withTaskCancellationHandler(operation: { try await job.run() }, onCancel: { job.cancel() })
        try Task.checkCancellation()
        // Completion means every frame decoded, not merely that a file or AVAsset duration exists.
        let decoded = try await decodeCaptureToEnd(temporary)
        let audio = try await AVURLAsset(url: temporary).loadTracks(withMediaType: .audio)
        try synchronize(temporary, directory: false)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporary, to: destination)
        // A failed post-publication flush refuses acknowledgment but preserves the completed file.
        try synchronize(destination.deletingLastPathComponent(), directory: true)
        return .init(videoFrames: decoded.videoFrames, duration: decoded.duration, includesAudio: !audio.isEmpty)
    }

    private static func synchronize(_ url: URL, directory: Bool) throws {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | (directory ? O_DIRECTORY : 0))
        guard descriptor >= 0 else { throw ClipExportError.filesystem(errno) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw ClipExportError.filesystem(errno) }
    }
}

/// AVFoundation permits cancellation from another thread; all other session configuration is
/// complete before this wrapper is shared. One export completion owns the continuation.
private final class ClipExportJob: @unchecked Sendable {
    let session: AVAssetExportSession
    let destination: URL
    init(session: AVAssetExportSession, destination: URL) { self.session = session; self.destination = destination }
    func cancel() { session.cancelExport() }
    func run() async throws {
        try Task.checkCancellation()
        if #available(iOS 18, macOS 15, *) {
            try await session.export(to: destination, as: .mp4)
        } else {
            session.outputURL = destination
            session.outputFileType = .mp4
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                session.exportAsynchronously { [self] in
                    switch session.status {
                    case .completed: continuation.resume()
                    case .cancelled: continuation.resume(throwing: CancellationError())
                    default: continuation.resume(throwing: ClipExportError.failed(session.error?.localizedDescription ?? "Incomplete export"))
                    }
                }
            }
        }
    }
}
