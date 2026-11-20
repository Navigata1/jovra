import AVFoundation
import JovraCore
import Observation
import SwiftUI

/// Loads the session the processing screen shows and its poster frame, and makes sure a saved session
/// has a processing job. Stage state itself comes from `ProcessingScheduler`.
@MainActor @Observable
final class ProcessingScreenModel {
    enum Phase {
        case loading
        case missing
        case unavailable
        case ready(SessionDocument)
    }

    private(set) var phase = Phase.loading
    private(set) var thumbnail: CGImage?

    func open(_ session: SessionID, library availability: LocalCaptureAvailability) async {
        guard case .ready(let library) = availability else { phase = .unavailable; return }
        let document: SessionDocument
        do { document = try await library.load(session) } catch { phase = .missing; return }
        phase = .ready(document)
        let scheduler = ProcessingScheduler.shared
        await scheduler.activate()
        if scheduler.job(session) == nil, ProcessingStagePresentation.isViewable(document.original) {
            await scheduler.enqueue(session)
        }
        thumbnail = await Self.posterFrame(document, session: session, library: library)
    }

    private static func posterFrame(_ document: SessionDocument, session: SessionID, library: LocalCaptureLibrary) async -> CGImage? {
        guard let segment = document.recording.segments.filter(\.finalized).min(by: { $0.index < $1.index }),
              let url = try? await library.fileURL(session, relativePath: segment.file.path) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let time = CMTime(seconds: min(0.5, Double(segment.durationMs) / 2000), preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }
}
