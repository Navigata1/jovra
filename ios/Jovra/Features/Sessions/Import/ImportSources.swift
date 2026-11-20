import CoreTransferable
import Foundation
import JovraCore
import JovraMedia
import UniformTypeIdentifiers

/// The three source tiles on "Bring your game in" (story 101).
enum ImportSourceKind: String, CaseIterable, Identifiable {
    case photos, files, drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photos: String(localized: "Photos", table: "Sessions.Import")
        case .files: String(localized: "Files", table: "Sessions.Import")
        case .drive: String(localized: "Google Drive", table: "Sessions.Import")
        }
    }

    var subtitle: String {
        switch self {
        case .photos: String(localized: "Videos from your library", table: "Sessions.Import")
        case .files: String(localized: "From your device", table: "Sessions.Import")
        case .drive: String(localized: "Your JOVRA archive", table: "Sessions.Import")
        }
    }

    /// SF Symbols only: no third-party logos (CLAUDE.md rule 6).
    var symbol: String {
        switch self {
        case .photos: "photo.on.rectangle"
        case .files: "doc"
        case .drive: "externaldrive.badge.icloud"
        }
    }

    var origin: SessionRecordingImportSource? {
        switch self {
        case .photos: .photos
        case .files: .files
        case .drive: nil
        }
    }
}

/// App-owned temporary folders for files the Photos picker hands over. The picker deletes its own copy when
/// the transfer handler returns, so each file is copied here inside the handler and removed after import.
enum ImportInbox {
    static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("ImportInbox", isDirectory: true) }

    static func newFolder() throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func remove(_ urls: [URL]) {
        for url in urls where url.path.hasPrefix(root.path) {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    /// Anything left by a previous process (the copies never become sessions on their own).
    static func sweep() { try? FileManager.default.removeItem(at: root) }
}

/// A video from the system Photos picker, copied out inside the transfer handler. The picker runs out of
/// process, so JOVRA never asks for Photos library access (story 102).
struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let destination = try ImportInbox.newFolder().appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedVideo(url: destination)
        }
    }
}

/// UI-test seam behind `-importSelection`: paths prefixed `cloud:` report "not downloaded" for six seconds
/// after first being asked, then become available, like an iCloud Drive file arriving.
actor SimulatedImportAvailability: ImportSourceAvailability {
    private let cloudPaths: Set<String>
    private var firstAsked: [String: ContinuousClock.Instant] = [:]
    private let delay: Duration

    init(cloudPaths: Set<String>, delay: Duration = .seconds(6)) {
        self.cloudPaths = cloudPaths
        self.delay = delay
    }

    func status(of url: URL) async -> ImportSourceStatus {
        guard cloudPaths.contains(url.path) else { return .available }
        let start = firstAsked[url.path] ?? .now
        firstAsked[url.path] = start
        return ContinuousClock.now - start < delay ? .notDownloaded : .available
    }

    func requestDownload(of url: URL) async {}

    /// The selection the launch argument names, with its cloud-only paths.
    static func selection(_ entries: [String]) -> (urls: [URL], cloud: Set<String>) {
        var urls: [URL] = [], cloud: Set<String> = []
        for entry in entries {
            if entry.hasPrefix("cloud:") {
                let url = URL(fileURLWithPath: String(entry.dropFirst("cloud:".count)))
                urls.append(url)
                cloud.insert(url.path)
            } else {
                urls.append(URL(fileURLWithPath: entry))
            }
        }
        return (urls, cloud)
    }
}
