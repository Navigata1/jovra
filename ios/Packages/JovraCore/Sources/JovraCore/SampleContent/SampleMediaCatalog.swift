import Foundation

public enum SampleMediaAvailability: Equatable, Sendable {
    case available(URL)
    /// The manifest names it but the rendered file is not on this device: show the missing-media state.
    case missing(fileName: String)
    case unknown
}

public enum SampleVideoCoverage: Equatable, Sendable {
    /// `offsetMs` is the time inside the sample video file.
    case inSampleVideo(mediaID: String, offsetMs: Int)
    /// The UI reads "Not in the sample video" (the older sessions have short thumbnail clips only).
    case notInSampleVideo
}

/// Resolves sample media by its stable manifest id to the rendered files (T11), which the app bundles.
public struct SampleMediaCatalog: Sendable {
    public let manifest: SampleMediaManifest
    public let directory: URL?
    public init(manifest: SampleMediaManifest, directory: URL?) {
        self.manifest = manifest
        self.directory = directory
    }

    public func availability(mediaID: String) -> SampleMediaAvailability {
        guard let entry = manifest.media.first(where: { $0.mediaId == mediaID }) else { return .unknown }
        guard let url = directory?.appendingPathComponent(entry.fileName),
              (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular
        else { return .missing(fileName: entry.fileName) }
        return .available(url)
    }

    /// Where a session time falls in that session's sample video, if anywhere.
    public func coverage(sessionID: String, timeMs: Int) -> SampleVideoCoverage {
        guard let video = manifest.media.first(where: { $0.sessionId == sessionID && $0.role == .sessionVideo }),
              timeMs >= video.coversSessionMs.fromMs, timeMs < video.coversSessionMs.toMs else { return .notInSampleVideo }
        return .inSampleVideo(mediaID: video.mediaId, offsetMs: timeMs - video.coversSessionMs.fromMs)
    }
}
