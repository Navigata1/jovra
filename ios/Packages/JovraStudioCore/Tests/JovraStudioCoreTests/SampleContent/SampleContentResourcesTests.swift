import Foundation
import Testing
import JovraStudioCore

/// The app's bundled sample records (`ios/Jovra/Resources/StudioSample`) are byte-identical to the shared fixtures
/// (`spec/studio/fixtures/records`); `scripts/studio/sync-sample-resources.sh` refreshes them.
@Suite("Studio sample content: bundled resources")
struct SampleContentResourcesTests {
    private static var bundled: URL {
        StudioFixtures.repositoryRoot().appendingPathComponent("ios/Jovra/Resources/StudioSample", isDirectory: true)
    }

    @Test("the bundled sample records are byte-identical to spec/studio/fixtures/records (sha256 equality)")
    func bundledCopyMatches() throws {
        let fixtures = try StudioFixtures.root().appendingPathComponent("records", isDirectory: true)
        let differences = try StudioSampleResources.differences(bundled: Self.bundled, fixtures: fixtures)

        #expect(differences.isEmpty, "run scripts/studio/sync-sample-resources.sh: \(differences)")
        #expect(try StudioSampleResources.hashes(in: Self.bundled).count
                == (try FileManager.default.contentsOfDirectory(atPath: fixtures.path).filter { $0.hasSuffix(".json") }.count))
    }

    @Test("changing one byte in a scratch copy of the bundled records fails the check, naming the file")
    func oneByteFails() throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let copy = scratch.root.appendingPathComponent("StudioSample", isDirectory: true)
        try FileManager.default.copyItem(at: Self.bundled, to: copy)
        let file = copy.appendingPathComponent("sync-map.json")
        var bytes = try Data(contentsOf: file)
        let index = bytes.firstIndex(of: UInt8(ascii: "2"))!
        bytes[index] = UInt8(ascii: "3")
        try bytes.write(to: file)

        let differences = try StudioSampleResources.differences(
            bundled: copy, fixtures: StudioFixtures.root().appendingPathComponent("records"))

        #expect(differences.count == 1)
        guard case .changed(let name, let bundled, let fixture)? = differences.first else {
            Issue.record("expected one changed file, got \(differences)"); return
        }
        #expect(name == "sync-map.json")
        #expect(bundled == (try systemSHA256(file)))
        #expect(fixture == (try systemSHA256(StudioFixtures.url("records/sync-map.json"))))
    }

    @Test("a missing or an extra file in the bundled copy fails the check")
    func missingAndExtraFail() throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let copy = scratch.root.appendingPathComponent("StudioSample", isDirectory: true)
        try FileManager.default.copyItem(at: Self.bundled, to: copy)
        try FileManager.default.removeItem(at: copy.appendingPathComponent("quote.sample-illustrative.json"))
        try Data("{}".utf8).write(to: copy.appendingPathComponent("stray.json"))

        let differences = try StudioSampleResources.differences(
            bundled: copy, fixtures: StudioFixtures.root().appendingPathComponent("records"))

        #expect(differences == [.missing("quote.sample-illustrative.json"), .extra("stray.json")])
    }

    @Test("the SHA-256 here agrees with the published test vectors and with the system tool")
    func sha256Vectors() throws {
        #expect(StudioSHA256.hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(StudioSHA256.hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(StudioSHA256.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
                == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        let manifest = try StudioFixtures.url("records/source-manifest.json")
        #expect(StudioSHA256.hex(try Data(contentsOf: manifest)) == (try systemSHA256(manifest)))
    }
}
