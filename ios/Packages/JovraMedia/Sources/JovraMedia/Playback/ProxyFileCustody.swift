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

private func refuseProxyACL(_ descriptor: Int32) throws {
    if let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) {
        acl_free(UnsafeMutableRawPointer(acl))
        throw ShortGOPProxyError.writeFailed
    }
    guard errno == ENOENT else { throw ShortGOPProxyError.writeFailed }
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
            try refuseProxyACL(current)
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

/// Seals an authentic writer result in the process-private namespace before exposing a handoff.
final class ProxyMovie: Sendable {
    private let descriptor: Int32
    let retiredWriter: URL

    init(retiring name: String, in scratch: ProxyDirectory) throws {
        try scratch.verify()
        let fd = openat(scratch.descriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ShortGOPProxyError.writeFailed }
        do {
            let opened = try proxyMetadata(fd)
            guard opened.st_mode & S_IFMT == S_IFREG, opened.st_uid == geteuid(),
                  opened.st_nlink == 1, opened.st_size > 0 else { throw ShortGOPProxyError.writeFailed }
            try refuseProxyACL(fd)
            guard fchmod(fd, 0o600) == 0 else { throw ShortGOPProxyError.writeFailed }
            try scratch.verify()
            guard try scratch.entry(name, type: S_IFREG) == ProxyFileIdentity(opened),
                  unlinkat(scratch.descriptor, name, 0) == 0,
                  try proxyMetadata(fd).st_nlink == 0 else { throw ShortGOPProxyError.writeFailed }
            descriptor = fd
            retiredWriter = scratch.url.appendingPathComponent(name)
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    deinit { Darwin.close(descriptor) }

    func commit(to receiver: ProxyDirectory, as name: String) throws -> Commit {
        let source = try proxyMetadata(descriptor)
        guard source.st_nlink == 0, source.st_mode & 0o777 == 0o600 else { throw ShortGOPProxyError.writeFailed }
        try receiver.verify()
        guard fclonefileat(descriptor, receiver.descriptor, name, UInt32(CLONE_NOOWNERCOPY)) == 0 else {
            throw ShortGOPProxyError.writeFailed
        }
        return try Commit(movie: self, receiver: receiver, name: name, size: source.st_size)
    }

    final class Commit: Sendable {
        private let movie: ProxyMovie
        private let receiver: ProxyDirectory
        private let name: String
        private let size: off_t
        private let descriptor: Int32
        private let identity: ProxyFileIdentity
        private let modified: timespec
        private let changed: timespec

        init(movie: ProxyMovie, receiver: ProxyDirectory, name: String, size: off_t) throws {
            let fd = openat(receiver.descriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw ShortGOPProxyError.writeFailed }
            do {
                let metadata = try proxyMetadata(fd)
                try Self.requirePrivateFile(fd, metadata, size: size)
                self.movie = movie
                self.receiver = receiver
                self.name = name
                self.size = size
                descriptor = fd
                identity = ProxyFileIdentity(metadata)
                modified = metadata.st_mtimespec
                changed = metadata.st_ctimespec
            } catch {
                Darwin.close(fd)
                throw error
            }
        }

        deinit { Darwin.close(descriptor) }

        struct Verified: Sendable {
            fileprivate let commit: Commit

            /// Point-in-time acknowledgment. Keep the held file and receiver bound until the caller uses it.
            func acknowledge() throws -> URL {
                try Task.checkCancellation()
                let url = try commit.rebind()
                try Task.checkCancellation()
                return url
            }
        }

        func verified(beforeVerification: (@Sendable () -> Void)? = nil) async throws -> Verified {
            let verifier = Task.detached(priority: .utility) {
                beforeVerification?()
                try self.verifyBytes()
            }
            try await withTaskCancellationHandler {
                try await verifier.value
            } onCancel: {
                verifier.cancel()
            }
            try Task.checkCancellation()
            return Verified(commit: self)
        }

        private func verifyBytes() throws {
            var offset: off_t = 0
            while offset < size {
                try Task.checkCancellation()
                let length = Int(min(64 * 1024, size - offset))
                guard try ProxyMovie.read(movie.descriptor, at: offset, count: length)
                    == ProxyMovie.read(descriptor, at: offset, count: length) else {
                    throw ShortGOPProxyError.writeFailed
                }
                offset += off_t(length)
            }
            try Task.checkCancellation()
            _ = try rebind()
        }

        private func rebind() throws -> URL {
            try receiver.verify()
            let current = try proxyMetadata(descriptor)
            try Self.requirePrivateFile(descriptor, current, size: size)
            guard current.st_mtimespec.tv_sec == modified.tv_sec, current.st_mtimespec.tv_nsec == modified.tv_nsec,
                  current.st_ctimespec.tv_sec == changed.tv_sec, current.st_ctimespec.tv_nsec == changed.tv_nsec,
                  try receiver.entry(name, type: S_IFREG) == identity else { throw ShortGOPProxyError.writeFailed }
            return receiver.url.appendingPathComponent(name)
        }

        private static func requirePrivateFile(_ fd: Int32, _ metadata: stat, size: off_t) throws {
            try refuseProxyACL(fd)
            guard metadata.st_mode & S_IFMT == S_IFREG, metadata.st_mode & 0o777 == 0o600,
                  metadata.st_uid == geteuid(), metadata.st_nlink == 1, metadata.st_size == size else {
                throw ShortGOPProxyError.writeFailed
            }
        }
    }

    // The optional host handoff probe observes bytes without holding a writable stage pathname.
    func evidenceBytes() throws -> Data {
        try Self.read(descriptor, at: 0, count: Int(proxyMetadata(descriptor).st_size))
    }

    private static func read(_ fd: Int32, at offset: off_t, count: Int) throws -> Data {
        var bytes = Data(count: count)
        try bytes.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            guard let address = buffer.baseAddress else { throw ShortGOPProxyError.writeFailed }
            var readCount = 0
            while readCount < count {
                let amount = pread(fd, address.advanced(by: readCount), count - readCount, offset + off_t(readCount))
                if amount < 0, errno == EINTR { continue }
                guard amount > 0 else { throw ShortGOPProxyError.writeFailed }
                readCount += amount
            }
        }
        return bytes
    }
}
