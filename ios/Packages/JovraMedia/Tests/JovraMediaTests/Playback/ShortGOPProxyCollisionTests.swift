import Foundation
import JovraBenchmark
import JovraCore
@testable import JovraMedia
import Testing

@Suite("Short-GOP proxy name collisions", .serialized)
struct ShortGOPProxyCollisionTests {
    private let catalog = MediaFixtureCatalog.repository()
    private let sentinel = Data("keep the pre-existing file".utf8)

    @Test
    func buildPreservesAnExistingBasenameProxy() async throws {
        let workspace = try scratch()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let truth = try catalog.truth(id: "frameCounter/fc-060")
        let original = try copiedSource(truth, in: workspace, folder: "first")
        let sourceBytes = try Data(contentsOf: original)
        let directory = try proxyFolder(in: workspace)
        let existing = directory.appendingPathComponent("contact.proxy.mov")
        try sentinel.write(to: existing, options: .withoutOverwriting)

        let proxy = try await ShortGOPProxy.build(from: original, into: directory, frameRate: .fps60)
        #expect(proxy.url != existing)
        #expect(try Data(contentsOf: existing) == sentinel)
        #expect(try Data(contentsOf: original) == sourceBytes)
        #expect(try await decodedCode(proxy, truth: truth, frame: 57) == 57)
    }

    @Test
    func concurrentSameBasenameSourcesKeepSeparateDecodableProxies() async throws {
        let workspace = try scratch()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let firstTruth = try catalog.truth(id: "frameCounter/fc-060")
        let secondTruth = try catalog.truth(id: "frameCounter/fc-240")
        let first = try copiedSource(firstTruth, in: workspace, folder: "first")
        let second = try copiedSource(secondTruth, in: workspace, folder: "second")
        let firstBytes = try Data(contentsOf: first)
        let secondBytes = try Data(contentsOf: second)
        let directory = try proxyFolder(in: workspace)

        async let firstOutput = ShortGOPProxy.build(from: first, into: directory, frameRate: .fps60)
        async let secondOutput = ShortGOPProxy.build(from: second, into: directory, frameRate: .fps240)
        let (firstProxy, secondProxy) = try await (firstOutput, secondOutput)
        #expect(firstProxy.url != secondProxy.url)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) ==
                [firstProxy.url.lastPathComponent, secondProxy.url.lastPathComponent])
        #expect(try Data(contentsOf: first) == firstBytes)
        #expect(try Data(contentsOf: second) == secondBytes)
        #expect(try await decodedCode(firstProxy, truth: firstTruth, frame: 57) == 57)
        #expect(try await decodedCode(secondProxy, truth: secondTruth, frame: 400) == 400)
    }

    @Test
    func publicationRefusesACollisionAtTheExactStagedDestination() async throws {
        let workspace = try scratch()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let truth = try catalog.truth(id: "frameCounter/fc-060")
        let original = try copiedSource(truth, in: workspace, folder: "first")
        let sourceBytes = try Data(contentsOf: original)
        let directory = try proxyFolder(in: workspace)
        let staged = try await ShortGOPProxy.encode(from: original, into: directory, frameRate: .fps60)
        let encoded = try staged.movie.evidenceBytes()
        try sentinel.write(to: staged.final, options: .withoutOverwriting)

        #expect(throws: ShortGOPProxyError.writeFailed) { try staged.publish() }
        #expect(try Data(contentsOf: staged.final) == sentinel)
        #expect(try staged.movie.evidenceBytes() == encoded)
        #expect(!FileManager.default.fileExists(atPath: staged.retiredWriter.path))
        #expect(try Data(contentsOf: staged.final) == sentinel)
        #expect(try Data(contentsOf: original) == sourceBytes)
    }

    private func decodedCode(_ proxy: ShortGOPProxy, truth: GroundTruth, frame: Int) async throws -> Int {
        let stepper = try ProxyBackwardStepper(proxy: proxy, frameRate: truth.video.frameRate.frameRate)
        let decoded = try await stepper.frame(at: frame)
        return try FrameCode.read(from: LumaPlane(image: decoded.image), truth: truth)
    }

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return url
    }

    private func copiedSource(_ truth: GroundTruth, in workspace: URL, folder: String) throws -> URL {
        let source = workspace.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let destination = source.appendingPathComponent("contact.mp4")
        try FileManager.default.copyItem(at: catalog.mediaURL(for: truth), to: destination)
        return destination
    }

    private func proxyFolder(in workspace: URL) throws -> URL {
        let directory = workspace.appendingPathComponent("proxies", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
