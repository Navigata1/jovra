import AuthenticationServices
import OSLog
import SwiftUI
import UIKit

/// The answer to "Continue with Apple". Apple's identifier and given name only: no email (nothing uses it), no token
/// kept, no server (open question 1; the button is behind `JOVRA_APPLE_SIGN_IN_ENABLED`).
enum AppleSignInResult: Equatable, Sendable {
    case signedIn(userID: String, givenName: String?)
    /// The player closed Apple's sheet.
    case cancelled
    /// Apple's sheet failed (offline, no Apple ID, a missing capability on this build). The reason is for the log.
    case failed(reason: String)
}

/// Apple's view of a stored identifier, checked at launch.
enum AppleCredentialState: Equatable, Sendable {
    case authorized, revoked, notFound, unknown
}

protocol AppleSignInClient: Sendable {
    @MainActor func signIn() async -> AppleSignInResult
    func credentialState(forUserID userID: String) async -> AppleCredentialState
}

/// Sign in with Apple through `ASAuthorizationController`, scope `.fullName` only.
struct LiveAppleSignInClient: AppleSignInClient {
    @MainActor
    func signIn() async -> AppleSignInResult {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName]
        let session = AppleSignInSession()
        return await session.run(request)
    }

    func credentialState(forUserID userID: String) async -> AppleCredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                let mapped: AppleCredentialState = switch state {
                case .authorized: .authorized
                case .revoked: .revoked
                case .notFound: .notFound
                default: .unknown
                }
                continuation.resume(returning: mapped)
            }
        }
    }
}

/// One authorization run: the controller's delegate callbacks become one async answer.
@MainActor
private final class AppleSignInSession: NSObject, ASAuthorizationControllerDelegate,
                                        ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleSignInResult, Never>?
    private var controller: ASAuthorizationController?

    func run(_ request: ASAuthorizationAppleIDRequest) async -> AppleSignInResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.failed(reason: "unexpected credential type"))
            return
        }
        finish(.signedIn(userID: credential.user, givenName: credential.fullName?.givenName))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            finish(.cancelled)
        } else {
            finish(.failed(reason: String(describing: error)))
        }
    }

    private func finish(_ result: AppleSignInResult) {
        continuation?.resume(returning: result)
        continuation = nil
        controller = nil
    }
}

/// The launch harness's answer (`-appleSignIn cancelled`): Apple's sheet never shows. The fixture identifier is a
/// made-up string, not an account.
struct FixtureAppleSignInClient: AppleSignInClient {
    static let userID = "fixture.apple.user.0001"
    static let givenName = "Jon"

    var fixture: LaunchConfiguration.AppleSignInFixture

    @MainActor
    func signIn() async -> AppleSignInResult {
        switch fixture {
        case .succeeded: .signedIn(userID: Self.userID, givenName: Self.givenName)
        case .cancelled: .cancelled
        case .failed: .failed(reason: "fixture: failed")
        }
    }

    func credentialState(forUserID userID: String) async -> AppleCredentialState { .authorized }
}

/// Registers Sign in with Apple (the ServiceKey seam): Apple's own, or the fixture a launch names.
struct AppleSignInClientKey: ServiceKey {
    static let defaultValue: any AppleSignInClient = resolve(.current)
    static func usesFake(_ configuration: LaunchConfiguration) -> Bool { configuration.appleSignIn != nil }
    static func live() -> any AppleSignInClient { LiveAppleSignInClient() }
    static func fake(for configuration: LaunchConfiguration) -> any AppleSignInClient {
        FixtureAppleSignInClient(fixture: configuration.appleSignIn ?? .succeeded)
    }
}

extension EnvironmentValues {
    var appleSignInClient: any AppleSignInClient {
        get { self[AppleSignInClientKey.self] }
        set { self[AppleSignInClientKey.self] = newValue }
    }
}

/// Whether Welcome offers "Continue with Apple": the `JovraAppleSignInEnabled` build setting (screens.md §6, open
/// question 1). Anything but YES hides it.
enum AppleSignInAvailability {
    static func isOffered(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> Bool {
        (infoDictionary?["JovraAppleSignInEnabled"] as? String)?.uppercased() == "YES"
    }
}

/// Apple's required button (`.continue`, white, 26 pt corners), drawn by the system.
struct AppleSignInButton: UIViewRepresentable {
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .continue, authorizationButtonStyle: .white)
        button.cornerRadius = 26
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        button.accessibilityIdentifier = "welcome.continueWithApple"
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
