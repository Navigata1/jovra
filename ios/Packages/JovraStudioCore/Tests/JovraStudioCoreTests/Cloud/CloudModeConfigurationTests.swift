import Foundation
import Testing
import JovraStudioCore

/// SD11 modes from configuration (stories 20 and 190): demo is the default; Test refuses to start without its
/// configuration; Live is compiled but unavailable in every configuration this ticket can build.
@Suite("Cloud: mode from configuration")
struct CloudModeConfigurationTests {
    /// Synthetic values only: `.test` is a reserved top-level domain, and the key is not a key.
    static var fullTest: [String: Any] { [
        CloudConfiguration.Key.environment: "test",
        CloudConfiguration.Key.testGatewayURL: "https://gateway.example.test",
        CloudConfiguration.Key.testIssuer: "https://auth.example.test",
        CloudConfiguration.Key.testPublishableKey: "synthetic-publishable-placeholder",
    ] }

    static func mode(_ info: [String: Any], _ arguments: [String] = []) async throws -> CloudMode {
        try await CloudClients.make(configuration: CloudConfiguration(info: info), launchArguments: arguments).mode()
    }

    @Test("STUDIO_ENVIRONMENT=demo gives the demo mode, labelled Local demo")
    func demo() async throws {
        let mode = try await Self.mode([CloudConfiguration.Key.environment: "demo"])
        #expect(mode == .demo)
        #expect(mode.label == "Local demo")
    }

    @Test("no STUDIO_ENVIRONMENT at all is the demo (the committed default)")
    func missingIsDemo() async throws {
        #expect(try await Self.mode([:]) == .demo)
        #expect(try await Self.mode([CloudConfiguration.Key.environment: ""]) == .demo)
    }

    @Test("STUDIO_ENVIRONMENT=test with no URL is unavailable: Test backend not configured")
    func testWithoutURL() async throws {
        let mode = try await Self.mode([CloudConfiguration.Key.environment: "test"])
        #expect(mode == .unavailable(.testBackendNotConfigured))
        #expect(mode.unavailableMessage == "Test backend not configured")
        #expect(mode.label == "Cloud unavailable")
    }

    @Test("each missing or unusable Test setting alone keeps Test unavailable",
          arguments: [CloudConfiguration.Key.testGatewayURL, CloudConfiguration.Key.testIssuer,
                      CloudConfiguration.Key.testPublishableKey])
    func testMissingOne(key: String) async throws {
        var info = Self.fullTest
        info[key] = nil
        #expect(try await Self.mode(info) == .unavailable(.testBackendNotConfigured))
        info[key] = "   "
        #expect(try await Self.mode(info) == .unavailable(.testBackendNotConfigured))
    }

    @Test("an unexpanded build setting or a URL with no host is not a configuration")
    func testUnusableURL() async throws {
        for url in ["$(STUDIO_TEST_GATEWAY_URL)", "gateway.example.test", "https://", "ftp://gateway.example.test"] {
            var info = Self.fullTest
            info[CloudConfiguration.Key.testGatewayURL] = url
            #expect(try await Self.mode(info) == .unavailable(.testBackendNotConfigured), "\(url)")
        }
    }

    @Test("a complete Test configuration still has no HTTP client in this build (S97), so it says so")
    func testShellConfigured() async throws {
        let mode = try await Self.mode(Self.fullTest)
        #expect(mode == .unavailable(.testClientNotInThisBuild))
        #expect(mode.unavailableMessage == "Test backend isn't in this build yet")
    }

    @Test("a Test configuration never reaches a demo or test client when STUDIO_ENVIRONMENT is demo or live")
    func testKeysIgnoredOutsideTest() async throws {
        var info = Self.fullTest
        info[CloudConfiguration.Key.environment] = "demo"
        #expect(try await Self.mode(info) == .demo)
        info[CloudConfiguration.Key.environment] = "live"
        #expect(try await Self.mode(info) == .unavailable(.liveNotActivated))
    }

    @Test("Live is unavailable in every configuration of this ticket, even with the activation flag and settings")
    func liveAlwaysUnavailable() async throws {
        let variants: [[String: Any]] = [
            [CloudConfiguration.Key.environment: "live"],
            [CloudConfiguration.Key.environment: "live", CloudConfiguration.Key.liveActivated: true],
            [CloudConfiguration.Key.environment: "live", CloudConfiguration.Key.liveActivated: "YES",
             CloudConfiguration.Key.testGatewayURL: "https://gateway.example.test",
             CloudConfiguration.Key.testIssuer: "https://auth.example.test",
             CloudConfiguration.Key.testPublishableKey: "synthetic-publishable-placeholder"],
        ]
        for info in variants {
            let mode = try await Self.mode(info)
            #expect(mode == .unavailable(.liveNotActivated))
            #expect(mode.unavailableMessage == "Cloud production isn't available right now.")
        }
        #expect(LiveCloudClient.recordedGates.isEmpty)
    }

    @Test("an unknown environment name is unavailable, never silently the demo or Live")
    func unknownEnvironment() async throws {
        #expect(try await Self.mode([CloudConfiguration.Key.environment: "prod"]) == .unavailable(.unknownEnvironment))
    }

    @Test("an unavailable client refuses every cloud action with its reason and keeps no job")
    func unavailableRefusesActions() async throws {
        let client = try CloudClients.make(configuration: CloudConfiguration(info: [CloudConfiguration.Key.environment: "test"]),
                                           launchArguments: [])
        #expect(try await client.identity() == .signedOut)
        await #expect(throws: CloudError.unavailable(.testBackendNotConfigured)) {
            _ = try await client.quote(CloudQuoteRequest(projectId: "sample-court-day", planRevision: 1))
        }
        await #expect(throws: CloudError.unavailable(.testBackendNotConfigured)) {
            _ = try await client.deleteCloudCopies(projectId: "sample-court-day")
        }
        var count = 0
        for await _ in await client.job("job-queue-38") { count += 1 }
        #expect(count == 0)
    }

    @Test("the Studio Info.plist key is the one Studio.xcconfig feeds")
    func infoPlistKey() throws {
        #expect(CloudConfiguration.Key.environment == "JovraStudioEnvironment")
        let plist = try String(contentsOf: StudioFixtures.repositoryRoot().appendingPathComponent("ios/project.yml"),
                               encoding: .utf8)
        #expect(plist.contains("JovraStudioEnvironment: $(STUDIO_ENVIRONMENT)"))
    }
}
