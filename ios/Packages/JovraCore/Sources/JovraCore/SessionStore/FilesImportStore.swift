import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension SessionStore {
    /// Private sibling staging keeps incomplete imports out of all library queries.
    public func beginFilesImport(_ id: UUID) throws -> URL {
        let staging = try importFolder(id)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        return staging
    }

    public func discardFilesImport(_ id: UUID) throws {
        let staging = try importFolder(id)
        if FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.removeItem(at: staging) }
    }

    /// Publish the original and its session together via a same-volume directory rename.
    /// Once renamed, a failed sync is unacknowledged but the completed folder is retained.
    public func commitFilesImport(_ document: SessionDocument, id: UUID) throws {
        try Task.checkCancellation()
        let recording = document.recording
        guard document.id == id.uuidString, recording.mode == .import, recording.importSource == .files,
              document.original?.state == .saved, recording.mediaAvailable, recording.segments.count == 1,
              let segment = recording.segments.first, segment.finalized,
              ["originals/source.mov", "originals/source.mp4"].contains(segment.file.path),
              let bytes = segment.file.bytes, bytes > 0, segment.file.sha256?.count == 64 else {
            throw SessionStoreError.invalidCapture
        }
        let staging = try importFolder(id)
        let original = staging.appendingPathComponent(segment.file.path)
        let originals = original.deletingLastPathComponent()
        try Self.refuseSymbolicLink(originals)
        try Self.refuseSymbolicLink(original)
        let attributes = try FileManager.default.attributesOfItem(atPath: original.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue == bytes else { throw SessionStoreError.invalidCapture }

        let destination = try folder(document.id)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw SessionStoreError.alreadyExists }
        let parent = staging.deletingLastPathComponent()
        let parentIdentity = try DurableDirectory.identity(of: parent)
        let sessionsIdentity = try DurableDirectory.identity(of: sessions)
        let stagingIdentity = try DurableDirectory.identity(of: staging)
        try DurableDirectory.synchronize(originals)
        try write(document, to: staging)
        try Task.checkCancellation()
        try DurableDirectory.synchronize(staging, matching: stagingIdentity)
        guard rename(staging.path, destination.path) == 0 else { throw SessionStoreError.renameFailed(errno) }
        try DurableDirectory.synchronize(destination, matching: stagingIdentity)
        try DurableDirectory.synchronize(sessions, matching: sessionsIdentity)
        try DurableDirectory.synchronize(parent, matching: parentIdentity)
    }

    private func importFolder(_ id: UUID) throws -> URL {
        let staging = try auxiliaryFolder(".files-imports").appendingPathComponent(id.uuidString, isDirectory: true)
        try Self.refuseSymbolicLink(staging)
        return staging
    }
}
