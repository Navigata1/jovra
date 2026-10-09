import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum DirectoryDurabilityError: Error, Equatable, Sendable { case filesystem(Int32), unsafePath }

/// Persist directory entries as well as file contents before acknowledging a local write.
/// This ordering is testable; it is not a claim of physical power-loss validation.
public enum DurableDirectory {
    public static func create(at url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: url.path) {
            try create(at: parent)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
        try synchronize(url)
        // Also confirms this directory's own entry, including a retry after a prior sync refusal.
        try synchronize(parent)
    }

    public struct Identity: Equatable, Sendable {
        fileprivate let device: UInt64
        fileprivate let inode: UInt64
    }

    public static func identity(of url: URL) throws -> Identity {
        try withDirectory(url) { _, identity in identity }
    }

    public static func synchronize(_ url: URL, matching expected: Identity? = nil) throws {
        try withDirectory(url) { descriptor, actual in
            guard expected == nil || expected == actual else { throw DirectoryDurabilityError.unsafePath }
            guard fsync(descriptor) == 0 else { throw DirectoryDurabilityError.filesystem(errno) }
        }
    }

    private static func withDirectory<Result>(_ url: URL, body: (Int32, Identity) throws -> Result) throws -> Result {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw DirectoryDurabilityError.filesystem(errno) }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw DirectoryDurabilityError.filesystem(errno) }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw DirectoryDurabilityError.unsafePath }
        return try body(descriptor, Identity(device: UInt64(truncatingIfNeeded: metadata.st_dev), inode: UInt64(truncatingIfNeeded: metadata.st_ino)))
    }
}
