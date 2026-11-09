import CryptoKit
import Darwin
import Foundation

enum ProbeCustodyError: Error {
    case unsafePath, identityChanged, fileAlreadyPresent
    case filesystem(Int32)
}

enum ProbeFixture {
    static let id = "03268C75-58B5-4495-8C78-38929FBA1C63"
    static let sessionSHA256 = "003fe33ad9fc29b35b8e7628bc12a2823baa9da4d9afec51d92da9648ac6d331"
    static let mediaSHA256 = "b939a95362096f89cd5f8a1c4171d2ee8148f3eb0ecf87cbe7cd7af6675644b5"

    static func verify(session: Data, media: Data) throws {
        guard sha256(session) == sessionSHA256, sha256(media) == mediaSHA256 else {
            throw ProbeCustodyError.identityChanged
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Owns one fresh root inside the alternate app. Every fixture leaf is exclusive and descriptor-relative.
struct ProbeRoot {
    let url: URL
    private let name: String
    private let home: URL
    private let homeFD: Int32
    private let libraryFD: Int32
    private let rootFD: Int32

    static func create(home: URL, name: String) throws -> ProbeRoot {
        try validate(name)
        let homeFD = try directory(home.path)
        do {
            let libraryFD = try directory("Library", at: homeFD)
            do {
                guard mkdirat(libraryFD, name, 0o700) == 0 else { throw ProbeCustodyError.filesystem(errno) }
                let rootFD = try directory(name, at: libraryFD)
                let root = ProbeRoot(url: home.appendingPathComponent("Library").appendingPathComponent(name),
                                     name: name, home: home, homeFD: homeFD, libraryFD: libraryFD, rootFD: rootFD)
                do {
                    try root.verify()
                    guard try FileManager.default.contentsOfDirectory(atPath: root.url.path).isEmpty else {
                        throw ProbeCustodyError.fileAlreadyPresent
                    }
                    return root
                } catch {
                    Darwin.close(rootFD)
                    throw error
                }
            } catch {
                Darwin.close(libraryFD)
                throw error
            }
        } catch {
            Darwin.close(homeFD)
            throw error
        }
    }

    func close() {
        Darwin.close(rootFD)
        Darwin.close(libraryFD)
        Darwin.close(homeFD)
    }

    func verify() throws {
        let attachedHome = try Self.directory(home.path)
        defer { Darwin.close(attachedHome) }
        let attachedLibrary = try Self.directory("Library", at: homeFD)
        defer { Darwin.close(attachedLibrary) }
        let attachedRoot = try Self.directory(name, at: libraryFD)
        defer { Darwin.close(attachedRoot) }
        guard try Self.identity(attachedHome) == Self.identity(homeFD),
              try Self.identity(attachedLibrary) == Self.identity(libraryFD),
              try Self.identity(attachedRoot) == Self.identity(rootFD) else {
            throw ProbeCustodyError.identityChanged
        }
    }

    func write(_ bytes: Data, folders: [String], leaf: String) throws {
        try Self.validate(leaf)
        try withDirectory(folders) { parent in
            let fd = openat(parent, leaf, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw ProbeCustodyError.filesystem(errno) }
            let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try file.write(contentsOf: bytes)
            try file.synchronize()
            try file.close()
            guard fsync(parent) == 0 else { throw ProbeCustodyError.filesystem(errno) }
        }
        try verify()
    }

    func requireAbsent(folders: [String], leaf: String) throws {
        try Self.validate(leaf)
        try withDirectory(folders) { parent in
            var metadata = stat()
            let result = fstatat(parent, leaf, &metadata, AT_SYMLINK_NOFOLLOW)
            guard result == -1, errno == ENOENT else { throw ProbeCustodyError.fileAlreadyPresent }
        }
    }

    private func withDirectory<T>(_ folders: [String], use: (Int32) throws -> T) throws -> T {
        try verify()
        var opened: [Int32] = []
        defer { opened.reversed().forEach { _ = Darwin.close($0) } }
        var parent = rootFD
        for folder in folders {
            try Self.validate(folder)
            parent = try Self.directory(folder, at: parent)
            opened.append(parent)
        }
        try verify()
        return try use(parent)
    }

    private static func validate(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"),
              !name.utf8.contains(0) else { throw ProbeCustodyError.unsafePath }
    }

    private static func directory(_ name: String, at parent: Int32? = nil) throws -> Int32 {
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        let fd = parent.map { openat($0, name, flags) } ?? open(name, flags)
        guard fd >= 0 else { throw ProbeCustodyError.filesystem(errno) }
        return fd
    }

    private struct Identity: Equatable { let device: dev_t; let inode: ino_t }
    private static func identity(_ fd: Int32) throws -> Identity {
        var metadata = stat()
        guard fstat(fd, &metadata) == 0 else { throw ProbeCustodyError.filesystem(errno) }
        return Identity(device: metadata.st_dev, inode: metadata.st_ino)
    }
}
