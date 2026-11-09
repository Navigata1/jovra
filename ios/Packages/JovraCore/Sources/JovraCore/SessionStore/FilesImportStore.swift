import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct FilesImportDuplicateCandidate: Equatable, Sendable {
    public let sessionID: String
    public let file: RecordFileReference
}

public enum FilesImportCommit: Sendable {
    case published
    case possibleDuplicates([FilesImportDuplicateCandidate])
}

extension SessionStore {
    /// Private sibling staging keeps incomplete imports out of all library queries.
    public func beginFilesImport(_ id: UUID) throws -> URL {
        let staging = try importFolder(id)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        activeFilesImports.insert(id)
        return staging
    }

    public func discardFilesImport(_ id: UUID) throws {
        guard activeFilesImports.remove(id) != nil else { return }
        let staging = try importFolder(id)
        if FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.removeItem(at: staging) }
    }

    /// The single app store sweeps its private staging namespace once on launch.
    public func discardAbandonedFilesImports() throws {
        let parent = try auxiliaryFolder(".files-imports")
        for item in try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: item.lastPathComponent), id.uuidString == item.lastPathComponent,
                  !activeFilesImports.contains(id),
                  try FileManager.default.attributesOfItem(atPath: item.path)[.type] as? FileAttributeType == .typeDirectory else { continue }
            try FileManager.default.removeItem(at: item)
        }
        try DurableDirectory.synchronize(parent)
    }

    /// Publish the original and its session together via a same-volume directory rename.
    /// Duplicate arbitration is serialized among callers sharing this app's SessionStore actor.
    /// Once renamed, a failed sync is unacknowledged but the completed folder is retained.
    public func commitFilesImport(_ document: SessionDocument, id: UUID, allowDuplicate: Bool = false,
                                  verifyOriginal: @Sendable (URL) throws -> Void) throws -> FilesImportCommit {
        try Task.checkCancellation()
        let recording = document.recording
        guard activeFilesImports.contains(id), document.id == id.uuidString, recording.mode == .import, recording.importSource == .files,
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
        let duplicates = allowDuplicate ? [] : try filesImportDuplicates(matching: segment.file)
        try Task.checkCancellation()
        try verifyOriginal(staging)
        if !duplicates.isEmpty { return .possibleDuplicates(duplicates) }
        try Task.checkCancellation()
        guard rename(staging.path, destination.path) == 0 else { throw SessionStoreError.renameFailed(errno) }
        activeFilesImports.remove(id)
        try DurableDirectory.synchronize(destination, matching: stagingIdentity)
        try DurableDirectory.synchronize(sessions, matching: sessionsIdentity)
        try DurableDirectory.synchronize(parent, matching: parentIdentity)
        return .published
    }

    /// Check the exact candidate again in the store actor after media bytes were read outside it.
    public func confirmFilesImportDuplicate(_ candidate: FilesImportDuplicateCandidate,
                                            verifyOriginal: @Sendable (URL) throws -> Void) throws {
        try Task.checkCancellation()
        guard filesImportOriginal(try load(candidate.sessionID)) == candidate.file else {
            throw SessionStoreError.invalidCapture
        }
        try verifyOriginal(try folder(candidate.sessionID))
    }

    private func filesImportDuplicates(matching selected: RecordFileReference) throws -> [FilesImportDuplicateCandidate] {
        var candidates: [FilesImportDuplicateCandidate] = []
        let entries = try FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil)
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try Task.checkCancellation()
            let document: SessionDocument
            do { document = try load(entry.lastPathComponent) }
            catch SessionStoreError.notFound, SessionStoreError.invalidID, SessionStoreError.unsafePath { continue }
            catch is ContractError { continue }
            catch is DecodingError { continue }
            guard let file = filesImportOriginal(document), file.sha256 == selected.sha256,
                  file.bytes == selected.bytes else { continue }
            candidates.append(FilesImportDuplicateCandidate(sessionID: document.id, file: file))
        }
        return candidates
    }

    private func filesImportOriginal(_ document: SessionDocument) -> RecordFileReference? {
        let recording = document.recording
        guard document.sample == nil, document.original?.state == .saved, document.storage.originals == .onDevice,
              recording.mode == .import, recording.importSource == .files, recording.mediaAvailable,
              recording.segments.count == 1, let segment = recording.segments.first, segment.finalized,
              ["originals/source.mov", "originals/source.mp4"].contains(segment.file.path) else { return nil }
        return segment.file
    }

    private func importFolder(_ id: UUID) throws -> URL {
        let staging = try auxiliaryFolder(".files-imports").appendingPathComponent(id.uuidString, isDirectory: true)
        try Self.refuseSymbolicLink(staging)
        return staging
    }
}
