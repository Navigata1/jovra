import Foundation

/// Whether a picked item's bytes are on this device yet (story 111).
public enum ImportSourceStatus: Equatable, Sendable {
    /// The bytes are local and can be copied now.
    case available
    /// A cloud-only item (iCloud Drive or another file provider) that must download first.
    case notDownloaded
}

/// Answers whether an item is local and asks the provider to fetch it. The system implementation reads the
/// ubiquitous-item resource values; tests and UI tests inject a simulated provider.
public protocol ImportSourceAvailability: Sendable {
    func status(of url: URL) async -> ImportSourceStatus
    func requestDownload(of url: URL) async
}

public struct SystemImportSourceAvailability: ImportSourceAvailability {
    public init() {}

    public func status(of url: URL) async -> ImportSourceStatus {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true, let status = values.ubiquitousItemDownloadingStatus else { return .available }
        return status == .notDownloaded ? .notDownloaded : .available
    }

    public func requestDownload(of url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}
