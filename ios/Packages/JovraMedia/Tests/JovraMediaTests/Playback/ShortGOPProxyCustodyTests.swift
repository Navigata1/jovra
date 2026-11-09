import Foundation
import JovraBenchmark
import JovraCore
@testable import JovraMedia
import Testing

@Suite("Short-GOP proxy destination custody", .serialized)
struct ShortGOPProxyCustodyTests {
    private let files = FileManager.default
    private let catalog = MediaFixtureCatalog.repository()
    private let sentinel = Data("foreign bytes".utf8)

    @Test(arguments: [false, true])
    func buildRefusesReceiverSymlinksAndLinkedAncestors(linkedAncestor: Bool) async throws {
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let foreign = try directory("foreign", in: root)
        let receiver = linkedAncestor ? try directory("proxies", in: foreign) : foreign
        let marker = receiver.appendingPathComponent("sentinel")
        try sentinel.write(to: marker, options: .withoutOverwriting)
        let link = root.appendingPathComponent("link", isDirectory: true)
        try files.createSymbolicLink(at: link, withDestinationURL: foreign)
        let proposed = linkedAncestor ? link.appendingPathComponent("proxies", isDirectory: true) : link
        let source = try fixture()
        let original = try Data(contentsOf: source)

        await #expect(throws: ShortGOPProxyError.writeFailed) {
            try await ShortGOPProxy.build(from: source, into: proposed, frameRate: .fps60)
        }
        #expect(try files.contentsOfDirectory(atPath: receiver.path) == ["sentinel"])
        #expect(try Data(contentsOf: marker) == sentinel)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test
    func aReplacedReceiverCannotPublishOrChangeEitherDirectory() async throws {
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let receiver = try directory("proxies", in: root)
        let source = try fixture()
        let original = try Data(contentsOf: source)
        let staged = try await ShortGOPProxy.encode(from: source, into: receiver, frameRate: .fps60)
        let encoded = try staged.movie.evidenceBytes()
        let detached = root.appendingPathComponent("detached")
        try files.moveItem(at: receiver, to: detached)
        _ = try directory("proxies", in: root)
        let marker = receiver.appendingPathComponent("sentinel")
        try sentinel.write(to: marker, options: .withoutOverwriting)

        await #expect(throws: ShortGOPProxyError.writeFailed) { try await staged.publish() }
        #expect(try staged.movie.evidenceBytes() == encoded)
        #expect(try files.contentsOfDirectory(atPath: receiver.path) == ["sentinel"])
        #expect(try Data(contentsOf: marker) == sentinel)
        #expect(try files.contentsOfDirectory(atPath: detached.path).isEmpty)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test
    func recreatingTheRetiredWriterNameCannotRedirectPublicationOrCleanup() async throws {
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let receiver = try directory("proxies", in: root)
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: receiver.path)
        let retiredWriter = try await publishWithReplacedRetiredName(into: receiver)
        defer { try? files.removeItem(at: retiredWriter.deletingLastPathComponent()) }
        #expect(try Data(contentsOf: retiredWriter) == sentinel)
    }

    private func publishWithReplacedRetiredName(into receiver: URL) async throws -> URL {
        let staged = try await ShortGOPProxy.encode(from: fixture(), into: receiver, frameRate: .fps60)
        let encoded = try staged.movie.evidenceBytes()
        let retired = staged.retiredWriter
        try #require(!files.fileExists(atPath: retired.deletingLastPathComponent().path))
        try files.createDirectory(at: retired.deletingLastPathComponent(), withIntermediateDirectories: false,
                                  attributes: [.posixPermissions: 0o700])
        try sentinel.write(to: retired, options: .withoutOverwriting)
        let proxy = try await staged.publish()
        #expect(try Data(contentsOf: proxy.url) == encoded)
        let permissions = try files.attributesOfItem(atPath: proxy.url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        let stepper = try ProxyBackwardStepper(proxy: proxy, frameRate: .fps60)
        let frame = try await stepper.frame(at: 57)
        let truth = try catalog.truth(id: "frameCounter/fc-060")
        #expect(try FrameCode.read(from: LumaPlane(image: frame.image), truth: truth) == 57)
        return retired
    }

    @Test
    func anUnboundWriterFailureFileIsNotRemovedByDirectoryCleanup() throws {
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let parent = try ProxyDirectory(root)
        let scratch = try parent.privateChild("writer")
        let unbound = scratch.url.appendingPathComponent("encoded.mov")
        try sentinel.write(to: unbound, options: .withoutOverwriting)
        parent.discardPrivateChild(scratch)
        #expect(try Data(contentsOf: unbound) == sentinel)
    }

    @Test
    func reparentedReceiverCannotPublishEvenWhenItsInodeIsUnchanged() async throws {
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let parent = try directory("parent", in: root)
        let receiver = try directory("proxies", in: parent)
        let staged = try await ShortGOPProxy.encode(from: fixture(), into: receiver, frameRate: .fps60)
        let ownBytes = try staged.movie.evidenceBytes()
        let detached = root.appendingPathComponent("detached")
        try files.moveItem(at: parent, to: detached)
        _ = try directory("parent", in: root)
        try files.moveItem(at: detached.appendingPathComponent("proxies"), to: receiver)

        await #expect(throws: ShortGOPProxyError.writeFailed) { try await staged.publish() }
        #expect(try staged.movie.evidenceBytes() == ownBytes)
        #expect(!files.fileExists(atPath: staged.final.path))
        #expect(try files.contentsOfDirectory(atPath: receiver.path).isEmpty)
    }

    @Test
    func earlyWriterCancellationNeverPublishesAndAnyResidueStaysPrivate() async throws {
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let temporary = files.temporaryDirectory.resolvingSymlinksInPath()
        let before = Set(try files.contentsOfDirectory(atPath: temporary.path))
        let gate = FirstProxyFrameGate()
        let source = try fixture()
        let task = Task {
            try await ShortGOPProxy.encode(from: source, into: root, frameRate: .fps60) { await gate.hold() }
        }
        defer {
            task.cancel()
            Task { await gate.release() }
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while await !gate.isHolding, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        let held = await gate.isHolding
        let newNames = try files.contentsOfDirectory(atPath: temporary.path)
            .filter { $0.hasPrefix("JOVRA-Proxy-") && !before.contains($0) }
        let writerDirectory = newNames.count == 1 ? temporary.appendingPathComponent(newNames[0]) : nil
        let sawWriterFile = writerDirectory.map { files.fileExists(atPath: $0.appendingPathComponent("encoded.mov").path) }
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        try #require(held && sawWriterFile == true, "The real writer appended its first frame in one new stage")
        let stage = try #require(writerDirectory)
        #expect(try files.contentsOfDirectory(atPath: root.path).isEmpty)
        if files.fileExists(atPath: stage.path) {
            let metadata = try files.attributesOfItem(atPath: stage.path)
            #expect(metadata[.type] as? FileAttributeType == .typeDirectory)
            #expect(metadata[.posixPermissions] as? Int == 0o700)
            print("Early cancellation retained protected writer scratch")
            try files.removeItem(at: stage)
        } else {
            print("Early cancellation left no writer scratch")
        }
    }

    private func scratch() throws -> URL {
        try directory(UUID().uuidString, in: files.temporaryDirectory)
    }

    private func directory(_ name: String, in parent: URL) throws -> URL {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try files.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }

    private func fixture() throws -> URL {
        try catalog.mediaURL(for: catalog.truth(id: "frameCounter/fc-060"))
    }
}


private actor FirstProxyFrameGate {
    private var pending: CheckedContinuation<Void, Never>?
    private var released = false
    var isHolding: Bool { pending != nil }

    func hold() async {
        guard !released else { return }
        await withCheckedContinuation { pending = $0 }
    }

    func release() {
        released = true
        let continuation = pending
        pending = nil
        continuation?.resume()
    }
}
