import AVFoundation
import Foundation
import JovraCore

/// The prepare-replay stage: opens every finalized segment of the saved original and confirms it is
/// playable with its tracks and duration loaded, one segment at a time (each one is a resume point).
/// It reads the original and never writes it.
enum PrepareReplayStage {
    struct Failure: Error { var reason: ProcessingReason }

    static func run(_ session: SessionID, library: LocalCaptureLibrary, from progress: Double,
                    report: @Sendable (Double) async throws -> Void) async throws {
        let document: SessionDocument
        do { document = try await library.load(session) } catch { throw Failure(reason: .originalMissing) }
        let segments = document.recording.segments.filter(\.finalized).sorted { $0.index < $1.index }
        guard document.recording.mediaAvailable, !segments.isEmpty else { throw Failure(reason: .originalMissing) }
        let first = Int((progress * Double(segments.count)).rounded(.down))
        for (offset, segment) in segments.enumerated() where offset >= first {
            try Task.checkCancellation()
            let url: URL
            do { url = try await library.fileURL(session, relativePath: segment.file.path) } catch {
                throw Failure(reason: .originalMissing)
            }
            guard FileManager.default.fileExists(atPath: url.path) else { throw Failure(reason: .originalMissing) }
            let asset = AVURLAsset(url: url)
            do {
                let (playable, duration, tracks) = try await asset.load(.isPlayable, .duration, .tracks)
                guard playable, duration.seconds > 0, tracks.contains(where: { $0.mediaType == .video }) else {
                    throw Failure(reason: .mediaUnreadable)
                }
            } catch let failure as Failure {
                throw failure
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw Failure(reason: .mediaUnreadable)
            }
            try await report(Double(offset + 1) / Double(segments.count))
        }
    }
}
