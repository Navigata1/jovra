import CryptoKit
import Darwin
import Foundation
import JovraCore

struct RecoveryFingerprint: Codable, Equatable, Sendable {
    let sha256: String
    let bytes: Int
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
    func read(_ path: String, retainingUpTo limit: Int? = nil) throws -> (RecoveryFingerprint, Data) {
        let source = try url(path)
        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw RecoveryError.filesystem(errno) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat(), after = stat(), declared = stat()
        guard fstat(descriptor, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG,
              before.st_size >= 0, before.st_size <= Int64(Int.max) else { throw RecoveryError.unsafePath }
        if let limit, before.st_size > Int64(limit) { throw RecoveryError.invalidJournal }
        var hash = SHA256(), total = 0, retained = Data()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
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
              before.st_dev == declared.st_dev, before.st_ino == declared.st_ino,
              before.st_size == after.st_size, Int64(total) == before.st_size else { throw RecoveryError.changedFile }
        return (.init(sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(), bytes: total), retained)
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
