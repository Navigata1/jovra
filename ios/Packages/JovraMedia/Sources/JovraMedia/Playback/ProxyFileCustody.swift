import Darwin
import Foundation

private let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC

struct ProxyFileIdentity: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t

    init(_ metadata: stat) {
        device = metadata.st_dev
        inode = metadata.st_ino
    }
}

private func proxyMetadata(_ descriptor: Int32) throws -> stat {
    var value = stat()
    guard fstat(descriptor, &value) == 0 else { throw ShortGOPProxyError.writeFailed }
    return value
}

/// Pins the receiver and its ancestors. Mutations use the held directory descriptor.
final class ProxyDirectory: Sendable {
    let url: URL
    let descriptor: Int32
    private let chain: [ProxyFileIdentity]

    init(_ url: URL) throws {
        var parts = url.path.split(separator: "/").map(String.init)
        guard url.isFileURL, url.host == nil || url.host == "", url.path.hasPrefix("/"),
              !parts.isEmpty, !parts.contains("."), !parts.contains("..") else {
            throw ShortGOPProxyError.writeFailed
        }
        // Foundation commonly returns these Darwin system aliases. No caller-supplied link is resolved.
        if let first = parts.first, first == "var" || first == "tmp",
           let alias = try? FileManager.default.destinationOfSymbolicLink(atPath: "/" + first) {
            guard alias == "private/" + first || alias == "/private/" + first else {
                throw ShortGOPProxyError.writeFailed
            }
            parts.insert("private", at: 0)
        }
        self.url = URL(fileURLWithPath: "/" + parts.joined(separator: "/"), isDirectory: true)
        var current = open("/", directoryFlags)
        guard current >= 0 else { throw ShortGOPProxyError.writeFailed }
        var identities: [ProxyFileIdentity] = []
        do {
            identities.append(ProxyFileIdentity(try proxyMetadata(current)))
            for part in parts {
                let next = openat(current, part, directoryFlags)
                guard next >= 0 else { throw ShortGOPProxyError.writeFailed }
                Darwin.close(current)
                current = next
                identities.append(ProxyFileIdentity(try proxyMetadata(current)))
            }
            let receiver = try proxyMetadata(current)
            guard receiver.st_uid == geteuid(), receiver.st_mode & 0o022 == 0 else {
                throw ShortGOPProxyError.writeFailed
            }
        } catch {
            Darwin.close(current)
            throw error
        }
        descriptor = current
        chain = identities
    }

    deinit { Darwin.close(descriptor) }

    func verify() throws {
        guard try ProxyDirectory(url).chain == chain else { throw ShortGOPProxyError.writeFailed }
    }

    func entry(_ name: String, type: mode_t) throws -> ProxyFileIdentity {
        var value = stat()
        guard fstatat(descriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0,
              value.st_mode & S_IFMT == type else { throw ShortGOPProxyError.writeFailed }
        return ProxyFileIdentity(value)
    }

    func privateChild(_ name: String) throws -> ProxyDirectory {
        try verify()
        guard mkdirat(descriptor, name, 0o700) == 0 else { throw ShortGOPProxyError.writeFailed }
        let child = try ProxyDirectory(url.appendingPathComponent(name, isDirectory: true))
        guard child.chain.dropLast().elementsEqual(chain),
              try entry(name, type: S_IFDIR) == child.chain.last else { throw ShortGOPProxyError.writeFailed }
        return child
    }

    func discardPrivateChild(_ child: ProxyDirectory) {
        let name = child.url.lastPathComponent
        guard (try? verify()) != nil, (try? child.verify()) != nil,
              let identity = try? entry(name, type: S_IFDIR), identity == child.chain.last else { return }
        _ = unlinkat(descriptor, name, AT_REMOVEDIR)
    }
}

/// An exclusive receiver partial, or the writer's completed regular file in its private scratch directory.
final class ProxyLeaf: Sendable {
    let directory: ProxyDirectory
    let name: String
    private let descriptor: Int32
    private let identity: ProxyFileIdentity
    var url: URL { directory.url.appendingPathComponent(name) }

    init(_ directory: ProxyDirectory, name: String, create: Bool) throws {
        try directory.verify()
        let access = create ? O_RDWR | O_CREAT | O_EXCL : O_RDONLY | O_NONBLOCK
        let fd = openat(directory.descriptor, name, access | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ShortGOPProxyError.writeFailed }
        do {
            let opened = try proxyMetadata(fd)
            let identity = ProxyFileIdentity(opened)
            guard opened.st_mode & S_IFMT == S_IFREG,
                  try directory.entry(name, type: S_IFREG) == identity else {
                throw ShortGOPProxyError.writeFailed
            }
            self.directory = directory
            self.name = name
            self.descriptor = fd
            self.identity = identity
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    deinit { Darwin.close(descriptor) }

    func copy(to target: ProxyLeaf) throws {
        try verify()
        try target.verify()
        let size = try proxyMetadata(descriptor).st_size
        guard size > 0, fcopyfile(descriptor, target.descriptor, nil, UInt32(COPYFILE_DATA)) == 0,
              try proxyMetadata(target.descriptor).st_size == size else { throw ShortGOPProxyError.writeFailed }
        try Task.checkCancellation()
        try verify()
        try target.verify()
    }

    func publish(as finalName: String) throws -> URL {
        try verify()
        guard renameatx_np(directory.descriptor, name, directory.descriptor, finalName,
                          UInt32(RENAME_EXCL)) == 0 else { throw ShortGOPProxyError.writeFailed }
        try directory.verify()
        guard try directory.entry(finalName, type: S_IFREG) == identity else { throw ShortGOPProxyError.writeFailed }
        return directory.url.appendingPathComponent(finalName)
    }

    func discard() {
        guard (try? verify()) != nil else { return }
        _ = unlinkat(directory.descriptor, name, 0)
    }

    private func verify() throws {
        try directory.verify()
        guard try directory.entry(name, type: S_IFREG) == identity else { throw ShortGOPProxyError.writeFailed }
    }
}
