import Foundation
import Testing
@testable import Jovra

/// The Google Drive OAuth client comes from ios/Config/Drive.xcconfig through Info.plist (ADR-0008).
/// Without it the app must read Drive as not configured ("Awaiting Google Drive setup").
@Suite("Drive client configuration")
struct DriveClientConfigurationTests {
    @Test("the app as built here, without a Drive xcconfig, reads Drive as not configured")
    func builtAppIsNotConfigured() throws {
        let info = try #require(Bundle.main.infoDictionary)
        // A developer who has created ios/Config/Drive.xcconfig builds a configured app; this check
        // is about the default chain, which CI and a clean checkout always use.
        try #require(info["JovraDriveXcconfigLoaded"] as? String != "YES", "built with a local Drive.xcconfig")
        #expect(info["JovraDriveClientID"] as? String == "")
        #expect(info["JovraDriveRedirectScheme"] as? String == DriveClientConfiguration.unconfiguredScheme)
        #expect(DriveClientConfiguration(infoDictionary: info) == .notConfigured)
        #expect(DriveClientConfiguration.bundled == .notConfigured)
    }

    @Test("every URL scheme the app registers is a valid, non-empty scheme (RFC 3986), Drive placeholder included")
    func registeredSchemesAreValid() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let types = try #require(info["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.count == types.count, "every URL type registers exactly one scheme")
        let valid = /[A-Za-z][A-Za-z0-9+.\-]*/
        for scheme in schemes {
            #expect(scheme.wholeMatch(of: valid) != nil, "invalid URL scheme '\(scheme)'")
        }
    }

    @Test("the inert placeholder scheme without a client id is not configured")
    func placeholderSchemeIsNotConfigured() {
        let info = ["JovraDriveClientID": "", "JovraDriveRedirectScheme": DriveClientConfiguration.unconfiguredScheme]
        #expect(DriveClientConfiguration(infoDictionary: info) == .notConfigured)
        #expect(DriveClientConfiguration.unconfiguredScheme.wholeMatch(of: /[a-z][a-z0-9.\-]*/) != nil)
    }

    @Test("an empty, blank, missing or unexpanded client id is not configured", arguments: [
        [String: String](),
        ["JovraDriveClientID": "", "JovraDriveRedirectScheme": ""],
        ["JovraDriveClientID": "   ", "JovraDriveRedirectScheme": " "],
        ["JovraDriveClientID": "$(JOVRA_DRIVE_CLIENT_ID)", "JovraDriveRedirectScheme": "$(JOVRA_DRIVE_REVERSED_CLIENT_ID)"],
    ])
    func notConfigured(info: [String: String]) {
        #expect(DriveClientConfiguration(infoDictionary: info) == .notConfigured)
    }

    @Test("a client id with its reversed redirect scheme is configured")
    func configured() {
        let info = [
            "JovraDriveClientID": "123456789012-abcdef.apps.googleusercontent.com",
            "JovraDriveRedirectScheme": "com.googleusercontent.apps.123456789012-abcdef",
        ]
        #expect(DriveClientConfiguration(infoDictionary: info) == .configured(
            clientID: "123456789012-abcdef.apps.googleusercontent.com",
            redirectScheme: "com.googleusercontent.apps.123456789012-abcdef"
        ))
    }

    @Test("a redirect scheme that is not the reversed client id is misconfigured, never configured")
    func mismatchedScheme() {
        let info = [
            "JovraDriveClientID": "123456789012-abcdef.apps.googleusercontent.com",
            "JovraDriveRedirectScheme": "com.googleusercontent.apps.999",
        ]
        #expect(DriveClientConfiguration(infoDictionary: info) == .misconfigured(
            "JovraDriveRedirectScheme must be com.googleusercontent.apps.123456789012-abcdef"
        ))
    }

    @Test("a client id that is not an iOS OAuth client id is misconfigured")
    func notAGoogleClientID() {
        let info = ["JovraDriveClientID": "my-client", "JovraDriveRedirectScheme": "com.example"]
        #expect(DriveClientConfiguration(infoDictionary: info) == .misconfigured(
            "JovraDriveClientID must end in .apps.googleusercontent.com"
        ))
    }
}
