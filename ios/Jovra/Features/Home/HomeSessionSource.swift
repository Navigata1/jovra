import AVFoundation
import Foundation
import JovraCore
import OSLog

/// Where Home's session documents come from: the local session store (every session that is not in Trash), plus,
/// in the demo (`-demo sample`), the sample library bundled with the app. A sample session already installed in the
/// store keeps its stored copy. Home never counts anything else (CLAUDE.md rule 1).
enum HomeSessionSource {
    enum LoadError: Error { case libraryUnavailable }

    static func documents(library: LocalCaptureAvailability, launch: LaunchConfiguration) async throws -> [SessionDocument] {
        #if DEBUG
        if let scenario = HomeScenario.current { return try scenario.documents() }
        #endif
        guard case .ready(let store) = library else { throw LoadError.libraryUnavailable }
        var documents: [SessionDocument] = []
        for summary in try await store.sessions() {
            do { documents.append(try await store.load(SessionID(rawValue: summary.id))) } catch {
                // A document that cannot be read is the library's to quarantine; Home counts what it can read.
                logger.notice("Home skipped a session it could not read: \(String(describing: error), privacy: .public)")
            }
        }
        if launch.demo == .sample {
            let stored = Set(documents.map(\.id))
            documents += try HomeSampleLibrary.sessions().filter { !stored.contains($0.id) }
        }
        return documents
    }

    /// A frame of the session's own video for the Latest session card, or nil (the card then draws court lines).
    static func posterFrame(for document: SessionDocument, library: LocalCaptureAvailability) async -> CGImage? {
        let url: URL?
        if document.sample != nil {
            url = HomeSampleLibrary.videoURL(for: document)
        } else if case .ready(let store) = library,
                  let segment = document.recording.segments.filter(\.finalized).min(by: { $0.index < $1.index }) {
            url = try? await store.fileURL(SessionID(rawValue: document.id), relativePath: segment.file.path)
        } else {
            url = nil
        }
        guard let url else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        // A moment into the rally rather than the first frame, which is often a fade or the camera settling.
        return try? await generator.image(at: CMTime(seconds: 3, preferredTimescale: 600)).image
    }

    private static let logger = Logger(subsystem: "com.islanddevcrew.jovra", category: "Home")
}

/// The demo library bundled with the app (`Resources/SampleLibrary.bundle`, a byte-identical copy of
/// spec/fixtures/sample; `HomeSampleBundleTests` fails on any difference).
enum HomeSampleLibrary {
    enum LoadError: Error { case missing }

    static func folder(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "SampleLibrary", withExtension: "bundle")
    }

    static func library(in bundle: Bundle = .main) throws -> SampleLibrary {
        guard let folder = folder(in: bundle) else { throw LoadError.missing }
        return try SampleLibrary.load(from: folder.appendingPathComponent("library", isDirectory: true),
                                      mediaManifest: folder.appendingPathComponent("media-manifest.json"),
                                      analysis: folder.appendingPathComponent("analysis", isDirectory: true))
    }

    static func sessions(in bundle: Bundle = .main) throws -> [SessionDocument] { try library(in: bundle).sessions }

    /// The rendered sample video bundled under SampleMedia/ (T11), when this build has it.
    static func videoURL(for document: SessionDocument, in bundle: Bundle = .main) -> URL? {
        guard let library = try? library(in: bundle) else { return nil }
        let catalog = SampleMediaCatalog(manifest: library.mediaManifest,
                                         directory: bundle.resourceURL?.appendingPathComponent("SampleMedia", isDirectory: true))
        for id in document.sample?.mediaIds ?? [] {
            if case .available(let url) = catalog.availability(mediaID: id) { return url }
        }
        return nil
    }
}
