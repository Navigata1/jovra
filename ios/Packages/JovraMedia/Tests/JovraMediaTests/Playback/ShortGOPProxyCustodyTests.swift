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

    @Test(arguments: [false, true])
    func aReplacedReceiverOrPartialCannotPublishOrBeCleaned(replacedReceiver: Bool) async throws {
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let receiver = try directory("proxies", in: root)
        let source = try fixture()
        let original = try Data(contentsOf: source)
        let staged = try await ShortGOPProxy.encode(from: source, into: receiver, frameRate: .fps60)
        let ownBytes = try Data(contentsOf: staged.partial)
        let detached = root.appendingPathComponent("detached")
        let authentic: URL
        if replacedReceiver {
            try files.moveItem(at: receiver, to: detached)
            _ = try directory("proxies", in: root)
            authentic = detached.appendingPathComponent(staged.partial.lastPathComponent)
        } else {
            try files.moveItem(at: staged.partial, to: detached)
            authentic = detached
        }
        try sentinel.write(to: staged.partial, options: .withoutOverwriting)

        #expect(throws: ShortGOPProxyError.writeFailed) { try staged.publish() }
        staged.discard()
        #expect(!files.fileExists(atPath: staged.final.path))
        #expect((try? Data(contentsOf: staged.partial)) == sentinel)
        #expect(try Data(contentsOf: authentic) == ownBytes)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test
    func reparentedReceiverCannotPublishEvenWhenItsInodeIsUnchanged() async throws {
        let root = try scratch()
        defer { try? files.removeItem(at: root) }
        let parent = try directory("parent", in: root)
        let receiver = try directory("proxies", in: parent)
        let staged = try await ShortGOPProxy.encode(from: fixture(), into: receiver, frameRate: .fps60)
        let ownBytes = try Data(contentsOf: staged.partial)
        let detached = root.appendingPathComponent("detached")
        try files.moveItem(at: parent, to: detached)
        _ = try directory("parent", in: root)
        try files.moveItem(at: detached.appendingPathComponent("proxies"), to: receiver)

        #expect(throws: ShortGOPProxyError.writeFailed) { try staged.publish() }
        staged.discard()
        #expect(!files.fileExists(atPath: staged.final.path))
        #expect((try? Data(contentsOf: staged.partial)) == ownBytes)
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
