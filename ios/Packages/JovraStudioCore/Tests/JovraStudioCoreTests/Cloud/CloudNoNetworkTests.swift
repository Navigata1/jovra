import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import JovraCore
import JovraStudioCore

/// SD11 acceptance 3 (network): there is no code path in DemoCloudClient that constructs a request. Two checks: the
/// demo folder names no networking type at all (the same scan CI runs in `.github/workflows/studio.yml`), and a
/// URLProtocol trap, proven live first, records no request while every demo call of every scenario runs.
@Suite("Cloud: the demo has no network", .serialized)
struct CloudNoNetworkTests {
    /// A protocol that answers every request itself, at once, with an error, and remembers its URL.
    final class Trap: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var urls: [String] = []

        static func reset() { lock.lock(); urls = []; lock.unlock() }
        static var seen: [String] { lock.lock(); defer { lock.unlock() }; return urls }

        override class func canInit(with request: URLRequest) -> Bool {
            lock.lock(); urls.append(request.url?.absoluteString ?? "?"); lock.unlock()
            return true
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
        override func stopLoading() {}
    }

    static let forbidden = ["URLRequest", "URLSession", "URLProtocol", "FoundationNetworking", "Network.framework",
                            "import Network", "Authorization", "Bearer", "Keychain", "accessToken", "refreshToken"]

    static var demoFolder: URL {
        StudioFixtures.repositoryRoot().appendingPathComponent("ios/Packages/JovraStudioCore/Sources/JovraStudioCore/Cloud/Demo")
    }

    @Test("no file of the demo client names a networking type, a request header or a token")
    func sourceScan() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.demoFolder.path).filter { $0.hasSuffix(".swift") }.sorted()
        #expect(names.contains("DemoCloudClient.swift"))
        for name in names {
            let text = try String(contentsOf: Self.demoFolder.appendingPathComponent(name), encoding: .utf8)
            for word in Self.forbidden { #expect(!text.contains(word), "\(name) names \(word)") }
        }
    }

    @Test("the trap catches a real request, then sees none while every demo scenario runs every call")
    func urlProtocolTrap() async throws {
        _ = URLProtocol.registerClass(Trap.self)
        defer { URLProtocol.unregisterClass(Trap.self) }
        Trap.reset()
        try await Self.selfCheck()
        #expect(Trap.seen == ["https://trap.example.test/self-check"], "the trap is live")

        Trap.reset()
        for scenario in DemoCloudScenario.allCases { _ = try await CloudDemoTranscript.record(scenario) }
        let client = try DemoCloudClient()
        _ = try await client.pause("job-queue-38")
        _ = try await client.resume("job-queue-38")
        _ = try await client.cancel("job-queue-38")
        #expect(Trap.seen.isEmpty, "the demo made \(Trap.seen.count) requests")
    }

    /// One request through the shared session, which the registered trap must answer.
    static func selfCheck() async throws {
        let url = try #require(URL(string: "https://trap.example.test/self-check"))
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            URLSession.shared.dataTask(with: url) { _, _, _ in done.resume() }.resume()
        }
    }
}

/// The demo's embedded Sample records are the repository's fixtures, byte for byte.
@Suite("Cloud: embedded Sample records")
struct CloudDemoFixtureSourceTests {
    @Test("each embedded record equals its file in spec/studio/fixtures/records")
    func byteForByte() throws {
        #expect(DemoCloudFixtureSource.texts.count == 4)
        for (name, text) in DemoCloudFixtureSource.texts {
            #expect(Data(text.utf8) == (try StudioFixtures.data("records/\(name)")), "\(name) drifted")
        }
    }
}
