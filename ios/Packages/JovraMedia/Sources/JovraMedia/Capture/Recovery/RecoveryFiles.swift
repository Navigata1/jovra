import CryptoKit
import Darwin
import Foundation
import JovraCore

struct RecoveryFingerprint: Codable, Equatable, Sendable {
    let sha256: String
    let bytes: Int
}
struct MediaFileIdentity: Equatable, Sendable {
    let device: UInt64, inode: UInt64, bytes: Int64
    let modifiedSeconds: Int, modifiedNanos: Int
    let changedSeconds: Int, changedNanos: Int

    init(_ value: stat) {
        device = UInt64(truncatingIfNeeded: value.st_dev); inode = UInt64(value.st_ino)
        bytes = value.st_size
        modifiedSeconds = value.st_mtimespec.tv_sec; modifiedNanos = value.st_mtimespec.tv_nsec
        changedSeconds = value.st_ctimespec.tv_sec; changedNanos = value.st_ctimespec.tv_nsec
    }
}

public struct MediaAdoptionWitness: Sendable {
    let directory: DurableDirectory.Identity
    let files: [String: MediaFileIdentity]

    /// A cheap final check within the store transaction, after the scanner decoded and hashed the files.
    public func verify(in folder: URL) throws {
        guard try DurableDirectory.identity(of: folder) == directory else { throw RecoveryError.changedFile }
        for (path, expected) in files {
            let source = try RecoveryFiles(folder: folder).url(path)
            var actual = stat()
            guard lstat(source.path, &actual) == 0, (actual.st_mode & S_IFMT) == S_IFREG,
                  MediaFileIdentity(actual) == expected else { throw RecoveryError.changedFile }
        }
    }
}

enum RecoveryError: Error, Equatable { case unsafePath, changedFile, invalidJournal, unfinishedRecording, noVideo; case filesystem(Int32) }

/// Owned relative paths only. Hashes stream; bounded metadata may be retained for decoding.
struct RecoveryFiles {
    let folder: URL
    func url(_ path: String) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains("\0") }) else {
            throw RecoveryError.unsafePath
        }
        var value = folder
        try Self.refuseLink(value)
        for component in components { value.appendPathComponent(String(component)); try Self.refuseLink(value) }
        return value
    }
    static func refuseLink(_ url: URL) throws {
        do {
            if try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeSymbolicLink {
                throw RecoveryError.unsafePath
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { }
    }
    func read(_ path: String, retainingUpTo limit: Int? = nil) throws -> (RecoveryFingerprint, Data, MediaFileIdentity) {
        let source = try url(path)
        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        return try read(descriptor, source: source, path: path, retainingUpTo: limit)
    }

    /// Open the importer-owned directory and original without following either through a link.
    func readOwnedOriginal(_ path: String) throws -> (RecoveryFingerprint, Data, MediaFileIdentity) {
        let source = try url(path)
        let components = path.split(separator: "/")
        guard components.count == 2, components.first == "originals", let name = components.last else {
            throw RecoveryError.unsafePath
        }
        let root = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard root >= 0 else { throw RecoveryError.filesystem(errno) }
        defer { close(root) }
        let directory = openat(root, "originals", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw RecoveryError.filesystem(errno) }
        defer { close(directory) }
        let descriptor = openat(directory, String(name), O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        return try read(descriptor, source: source, path: path, retainingUpTo: nil, checkingCancellation: true)
    }

    private func read(_ descriptor: Int32, source: URL, path: String,
                      retainingUpTo limit: Int?, checkingCancellation: Bool = false) throws -> (RecoveryFingerprint, Data, MediaFileIdentity) {
        guard descriptor >= 0 else { throw RecoveryError.filesystem(errno) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat(), after = stat(), declared = stat()
        guard fstat(descriptor, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG,
              before.st_size >= 0, before.st_size <= Int64(Int.max) else { throw RecoveryError.unsafePath }
        if let limit, before.st_size > Int64(limit) { throw RecoveryError.invalidJournal }
        var hash = SHA256(), total = 0, retained = Data()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            if checkingCancellation { try Task.checkCancellation() }
            let next = total.addingReportingOverflow(chunk.count)
            guard !next.overflow else { throw RecoveryError.changedFile }; total = next.partialValue
            if let limit {
                guard total <= limit else { throw RecoveryError.invalidJournal }
                retained.append(chunk)
            }
            hash.update(data: chunk)
        }
        _ = try url(path) // Recheck every owned component before acknowledging this fingerprint.
        guard fstat(descriptor, &after) == 0, lstat(source.path, &declared) == 0,
              MediaFileIdentity(before) == MediaFileIdentity(declared),
              MediaFileIdentity(before) == MediaFileIdentity(after), Int64(total) == before.st_size else { throw RecoveryError.changedFile }
        return (.init(sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(), bytes: total), retained, MediaFileIdentity(after))
    }
    func writeReceipt(_ bytes: Data) throws {
        let destination = try url("capture-recovery.json")
        let identity = try DurableDirectory.identity(of: folder)
        let temporary = folder.appendingPathComponent(".recovery-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw RecoveryError.filesystem(errno) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: bytes); try handle.synchronize(); try handle.close()
        _ = try url("capture-recovery.json")
        guard rename(temporary.path, destination.path) == 0 else { throw RecoveryError.filesystem(errno) }
        try DurableDirectory.synchronize(folder, matching: identity)
    }
}

/// Torn-segment truncation. The prefix is cloned (APFS copy-on-write, or a streamed copy where cloning is
/// unavailable), truncated and decoded before it may replace the torn file in one atomic rename.
extension RecoveryFiles {
    static let clonePrefix = ".recovery-", cloneSuffix = ".mp4"

    func truncatedClone(of path: String, length: UInt64) throws -> String {
        let source = try url(path)
        let directory = (path as NSString).deletingLastPathComponent
        let clonePath = "\(directory)/\(Self.clonePrefix)\(UUID().uuidString)\(Self.cloneSuffix)"
        let clone = try url(clonePath)
        if clonefile(source.path, clone.path, UInt32(CLONE_NOFOLLOW)) != 0 { try copyPrefix(source, to: clone, length: length) }
        let descriptor = open(clone.path, O_WRONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw RecoveryError.filesystem(errno) }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, UInt64(info.st_size) >= length,
              ftruncate(descriptor, off_t(length)) == 0, fsync(descriptor) == 0 else { throw RecoveryError.filesystem(errno) }
        return clonePath
    }
    private func copyPrefix(_ source: URL, to clone: URL, length: UInt64) throws {
        let input = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard input >= 0 else { throw RecoveryError.filesystem(errno) }
        let reader = FileHandle(fileDescriptor: input, closeOnDealloc: true)
        defer { try? reader.close() }
        let output = open(clone.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard output >= 0 else { throw RecoveryError.filesystem(errno) }
        let writer = FileHandle(fileDescriptor: output, closeOnDealloc: true)
        defer { try? writer.close() }
        var remaining = length
        while remaining > 0, let chunk = try reader.read(upToCount: Int(min(remaining, 1_048_576))), !chunk.isEmpty {
            try writer.write(contentsOf: chunk); remaining -= UInt64(chunk.count)
        }
        guard remaining == 0 else { throw RecoveryError.changedFile }
    }
    func remove(_ path: String) throws {
        let target = try url(path)
        guard unlink(target.path) == 0 || errno == ENOENT else { throw RecoveryError.filesystem(errno) }
    }
    /// Clones left by a scan that was itself interrupted. Only this scanner's own temporary names match.
    func removeAbandonedClones() throws {
        let originals = try url("originals")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: originals.path) else { return }
        for name in names where name.hasPrefix(Self.clonePrefix) && name.hasSuffix(Self.cloneSuffix)
            && UUID(uuidString: String(name.dropFirst(Self.clonePrefix.count).dropLast(Self.cloneSuffix.count))) != nil {
            try remove("originals/\(name)")
        }
    }
    /// Replaces the torn file with its verified prefix, refusing if the torn file changed since it was read.
    func commit(_ clonePath: String, over path: String, source: MediaFileIdentity, kept: RecoveryFingerprint) throws -> MediaFileIdentity {
        let target = try url(path), clone = try url(clonePath)
        var current = stat()
        guard lstat(target.path, &current) == 0, MediaFileIdentity(current) == source else { throw RecoveryError.changedFile }
        guard rename(clone.path, target.path) == 0 else { throw RecoveryError.filesystem(errno) }
        try DurableDirectory.synchronize(target.deletingLastPathComponent())
        let (fingerprint, _, identity) = try read(path)
        guard fingerprint == kept else { throw RecoveryError.changedFile }
        return identity
    }
}
