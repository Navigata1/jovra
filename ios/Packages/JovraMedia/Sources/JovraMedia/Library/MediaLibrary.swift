import Foundation
import JovraCore

public enum MediaLibraryError: Error, Equatable { case unsafePath, alreadyExists, notFound }
public struct MediaByteCounts: Equatable, Sendable {
    public let originals: Int64
    public let cache: Int64
    public let exports: Int64
}

/// Media remains inside an existing local session. Source bytes are never relocated
/// or discarded by library queries, backup preferences or cache accounting.
public actor MediaLibrary {
    private let store: SessionStore
    public init(store: SessionStore) { self.store = store }

    public func recordingFolder(sessionID: String) async throws -> URL {
        let folder = try await store.sessionDirectory(sessionID)
        let enabled = try await store.load(sessionID).storage.includeInDeviceBackup
        for name in ["originals", "cache", "exports"] {
            var directory = folder.appendingPathComponent(name, isDirectory: true)
            try refuseLink(directory)
            if FileManager.default.fileExists(atPath: directory.path) {
                guard try FileManager.default.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else {
                    throw MediaLibraryError.unsafePath
                }
            } else { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false) }
            var values = URLResourceValues()
            values.isExcludedFromBackup = name != "originals" || !enabled
            try directory.setResourceValues(values)
        }
        return folder
    }

    public func reserveOriginalURL(sessionID: String, relativePath: String) async throws -> URL {
        guard relativePath.hasPrefix("originals/") else { throw MediaLibraryError.unsafePath }
        let folder = try await recordingFolder(sessionID: sessionID)
        let url = try confined(relativePath, folder: folder)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw MediaLibraryError.alreadyExists }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }

    public func fileURL(sessionID: String, relativePath: String) async throws -> URL {
        let folder = try await store.sessionDirectory(sessionID)
        let url = try confined(relativePath, folder: folder)
        guard FileManager.default.fileExists(atPath: url.path) else { throw MediaLibraryError.notFound }
        return url
    }

    public func includeOriginalsInDeviceBackup(_ enabled: Bool, sessionID: String) async throws {
        let folder = try await recordingFolder(sessionID: sessionID)
        var originals = folder.appendingPathComponent("originals", isDirectory: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = !enabled
        try originals.setResourceValues(values)
        do { try await store.setDeviceBackup(enabled, for: sessionID) }
        catch {
            let old = try await store.load(sessionID).storage.includeInDeviceBackup
            values.isExcludedFromBackup = !old
            try? originals.setResourceValues(values)
            throw error
        }
    }

    public func byteCounts(sessionID: String) async throws -> MediaByteCounts {
        let folder = try await recordingFolder(sessionID: sessionID)
        return try .init(originals: count(folder.appendingPathComponent("originals")),
                         cache: count(folder.appendingPathComponent("cache")),
                         exports: count(folder.appendingPathComponent("exports")))
    }

    private func confined(_ path: String, folder: URL) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 2, ["originals", "cache", "exports"].contains(components[0]),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains("\0") }) else {
            throw MediaLibraryError.unsafePath
        }
        var url = folder
        for component in components { url.appendPathComponent(component); try refuseLink(url) }
        return url
    }

    private func refuseLink(_ url: URL) throws {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw MediaLibraryError.unsafePath }
    }
    private func count(_ directory: URL) throws -> Int64 {
        try refuseLink(directory)
        var total: Int64 = 0
        for entry in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try refuseLink(entry)
            let attributes = try FileManager.default.attributesOfItem(atPath: entry.path)
            if attributes[.type] as? FileAttributeType == .typeDirectory { total += try count(entry) }
            else if attributes[.type] as? FileAttributeType == .typeRegular { total += (attributes[.size] as? NSNumber)?.int64Value ?? 0 }
        }
        return total
    }
}
