import Foundation
import JovraCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A point in an atomic write where a test can simulate the process dying.
public enum StudioProjectWriteCheckpoint: Sendable {
    /// The temporary file is written and flushed; the destination is still the previous document.
    case temporaryFileFlushed(URL)
    /// The rename has happened; the folder entry is not yet flushed.
    case documentRenamed(URL)
}

/// Write-temp-then-rename, the core session store's pattern (ADR-0002): write and flush a temporary file in the same
/// folder, rename it over the destination, then flush the folder. A reader never sees a half-written document; a
/// process that dies before the rename leaves the previous document and an orphan `.tmp` file that loads ignore.
struct StudioAtomicFile {
    let fault: (@Sendable (StudioProjectWriteCheckpoint) throws -> Void)?

    func write(_ bytes: Data, named name: String, in folder: URL) throws {
        let folderIdentity = try DurableDirectory.identity(of: folder)
        let destination = folder.appendingPathComponent(name)
        try StudioPath.refuseSymbolicLink(destination)
        let temporary = folder.appendingPathComponent(".\(name)-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw StudioProjectStoreError.writeFailed
        }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: bytes); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); try? FileManager.default.removeItem(at: temporary); throw error }
        try fault?(.temporaryFileFlushed(temporary))
        guard rename(temporary.path, destination.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw StudioProjectStoreError.renameFailed(errno)
        }
        try fault?(.documentRenamed(destination))
        do { try DurableDirectory.synchronize(folder, matching: folderIdentity) }
        catch DirectoryDurabilityError.filesystem(let failure) { throw StudioProjectStoreError.durabilityUnconfirmed(failure) }
    }
}

/// Path rules shared by the store and the sample installer.
enum StudioPath {
    /// The id charset core sessions use: letters, digits, `-` and `_`, at most 160 characters.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 160 && id != "." && id != ".." && id.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0)
        }
    }

    /// A record file name: an id-like stem plus `.json`, no folders.
    static func isValidFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".json") else { return false }
        let stem = String(name.dropLast(5))
        return !stem.isEmpty && stem.count <= 160 && !stem.hasPrefix(".") && stem.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.").contains($0)
        }
    }

    static func refuseSymbolicLink(_ url: URL) throws {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw StudioProjectStoreError.unsafePath }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { }
    }
}
