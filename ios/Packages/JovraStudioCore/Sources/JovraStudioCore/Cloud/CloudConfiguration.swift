import Foundation

/// The cloud settings a build carries, read from the app's Info.plist (`ios/Config/Studio.xcconfig` feeds
/// `JovraStudioEnvironment`; the Test keys come from configuration kept outside source control, never from source).
public struct CloudConfiguration: Equatable, Sendable {
    public enum Key {
        public static let environment = "JovraStudioEnvironment"
        public static let testGatewayURL = "JovraStudioTestGatewayURL"
        public static let testIssuer = "JovraStudioTestIssuer"
        public static let testPublishableKey = "JovraStudioTestPublishableKey"
        public static let liveActivated = "JovraStudioLiveActivated"
    }

    /// The Test backend's settings, present only when every one is usable.
    public struct TestBackend: Equatable, Sendable {
        public let gatewayURL: URL
        public let issuer: URL
        public let publishableKey: String
    }

    /// The raw STUDIO_ENVIRONMENT value, trimmed; empty means the committed default (demo).
    public let environmentName: String
    public let testBackend: TestBackend?
    public let liveActivationFlag: Bool

    /// Reads an Info.plist dictionary. Values that are missing, blank or an unexpanded `$(...)` build setting count as
    /// absent, so a half-configured build is unavailable rather than pointed somewhere unintended.
    public init(info: [String: Any]) {
        environmentName = Self.text(info[Key.environment]) ?? ""
        if let gateway = Self.url(info[Key.testGatewayURL]), let issuer = Self.url(info[Key.testIssuer]),
           let key = Self.text(info[Key.testPublishableKey]) {
            testBackend = TestBackend(gatewayURL: gateway, issuer: issuer, publishableKey: key)
        } else {
            testBackend = nil
        }
        liveActivationFlag = Self.flag(info[Key.liveActivated])
    }

    /// The app's own configuration.
    public static var main: CloudConfiguration { CloudConfiguration(info: Bundle.main.infoDictionary ?? [:]) }

    /// The environment this configuration selects; nil for an unknown name.
    public var environment: StudioEnvironment? {
        environmentName.isEmpty ? .demo : StudioEnvironment(rawValue: environmentName.lowercased())
    }

    private static func text(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text.hasPrefix("$(") ? nil : text
    }

    private static func url(_ value: Any?) -> URL? {
        guard let text = text(value), let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private static func flag(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        return ["yes", "true", "1"].contains(text(value)?.lowercased() ?? "")
    }
}

/// The one place a cloud client is chosen.
public enum CloudClients {
    /// The launch argument that injects a demo scenario: `-studioCloudScenario <name>` (`DemoCloudScenario`).
    public static let scenarioArgument = "-studioCloudScenario"

    /// demo → `DemoCloudClient` (scenario from the launch arguments), test → `TestCloudClient`, live →
    /// `LiveCloudClient`, anything else → a client that is unavailable for an unknown environment.
    public static func make(configuration: CloudConfiguration, launchArguments: [String]) throws(CloudError) -> any CloudClient {
        switch configuration.environment {
        case .demo?: try DemoCloudClient(scenario: DemoCloudScenario(launchArguments: launchArguments))
        case .test?: TestCloudClient(configuration: configuration)
        case .live?: LiveCloudClient(configuration: configuration)
        case nil: UnavailableCloudClient(reason: .unknownEnvironment)
        }
    }
}
