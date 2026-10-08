import Foundation

/// The Google Drive OAuth client this build was configured with (ADR-0008).
///
/// The values come from the git-ignored `ios/Config/Drive.xcconfig` through two Info.plist keys
/// (`JovraDriveClientID`, `JovraDriveRedirectScheme`); the redirect scheme is also registered as a URL
/// type. Without that file the client id is empty and the redirect scheme is the inert placeholder
/// `unconfiguredScheme` (an empty CFBundleURLSchemes entry is invalid), so Drive reads as
/// `.notConfigured`, which the UI shows as "Awaiting Google Drive setup", never as a fake "Connected".
enum DriveClientConfiguration: Equatable, Sendable {
    case notConfigured
    case configured(clientID: String, redirectScheme: String)
    /// Values are present but inconsistent; treated as not configured, with the reason for the log.
    case misconfigured(String)

    static let clientIDKey = "JovraDriveClientID"
    static let redirectSchemeKey = "JovraDriveRedirectScheme"
    /// The default of JOVRA_DRIVE_REVERSED_CLIENT_ID in ios/Config/Jovra.xcconfig: a valid URL scheme
    /// that no Google client uses, registered only so the Drive URL type is never an empty scheme.
    static let unconfiguredScheme = "com.islanddevcrew.jovra.drive-unconfigured"
    private static let clientIDSuffix = ".apps.googleusercontent.com"
    private static let schemePrefix = "com.googleusercontent.apps."

    /// The configuration built into this app.
    static var bundled: DriveClientConfiguration {
        DriveClientConfiguration(infoDictionary: Bundle.main.infoDictionary)
    }

    init(infoDictionary: [String: Any]?) {
        let clientID = Self.value(infoDictionary?[Self.clientIDKey])
        let scheme = Self.value(infoDictionary?[Self.redirectSchemeKey])
        guard let clientID else {
            self = .notConfigured
            return
        }
        guard clientID.hasSuffix(Self.clientIDSuffix) else {
            self = .misconfigured("\(Self.clientIDKey) must end in \(Self.clientIDSuffix)")
            return
        }
        let expectedScheme = Self.schemePrefix + clientID.dropLast(Self.clientIDSuffix.count)
        guard scheme == expectedScheme else {
            self = .misconfigured("\(Self.redirectSchemeKey) must be \(expectedScheme)")
            return
        }
        self = .configured(clientID: clientID, redirectScheme: expectedScheme)
    }

    var isConfigured: Bool {
        if case .configured = self { true } else { false }
    }

    /// A usable value: present, not blank, and not an unexpanded `$(BUILD_SETTING)` reference.
    private static func value(_ raw: Any?) -> String? {
        guard let string = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty, !string.hasPrefix("$(") else { return nil }
        return string
    }
}
