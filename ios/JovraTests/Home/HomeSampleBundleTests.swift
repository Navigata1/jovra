import CryptoKit
import Foundation
import Testing
@testable import Jovra

/// The demo Home reads the app's bundled copy of the sample library (Resources/SampleLibrary.bundle). It must stay a
/// byte-identical copy of spec/fixtures/sample, so the demo numbers are the fixtures' numbers.
@Suite("Home sample bundle")
struct HomeSampleBundleTests {
    @Test("The bundled sample library equals spec/fixtures/sample byte for byte")
    func bundleMatchesFixtures() throws {
        let bundle = try #require(Bundle.main.url(forResource: "SampleLibrary", withExtension: "bundle"))
        let fixtures = HomeTestFixtures.sampleFolder
        let bundled = try files(under: bundle)
        var expected: [String: URL] = [:]
        for (path, url) in try files(under: fixtures.appendingPathComponent("library")) where !path.hasSuffix(".expected.json") {
            expected["library/" + path] = url
        }
        for (path, url) in try files(under: fixtures.appendingPathComponent("analysis/sessions")) {
            expected["analysis/sessions/" + path] = url
        }
        expected["media-manifest.json"] = fixtures.appendingPathComponent("media-manifest.json")
        #expect(Set(bundled.keys) == Set(expected.keys))
        for (path, url) in expected {
            let copy = try #require(bundled[path], "\(path) is bundled")
            #expect(try digest(copy) == digest(url), "\(path) differs from spec/fixtures/sample")
        }
    }

    @Test("The demo source loads all eight sample sessions from the bundle")
    func demoSourceLoadsBundle() throws {
        let sessions = try HomeSampleLibrary.sessions()
        #expect(sessions.count == 8)
        #expect(sessions.allSatisfy { $0.sample != nil })
    }

    private func files(under root: URL) throws -> [String: URL] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        var result: [String: URL] = [:]
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        while let url = enumerator?.nextObject() as? URL {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            result[String(path.dropFirst(base.count))] = url
        }
        return result
    }

    private func digest(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
}
