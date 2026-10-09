import Foundation
import Synchronization

/// The permissions JOVRA can ask for: camera, microphone, Photos add-only, notifications and
/// HealthKit (spec, PermissionsCenter). The launch-argument vocabulary is the same type, so UI tests
/// inject exactly these.
typealias Permission = LaunchConfiguration.Permission
typealias PermissionState = LaunchConfiguration.PermissionState

/// One adapter for every permission. Callers ask for the status, show the in-app explanation, and
/// only then call `request(_:)`, at the moment the permission is needed: never at launch, never in
/// onboarding (story 17), and never with an imitation of the system dialog (story 346).
protocol PermissionsCenter: Sendable {
    /// The current state, without prompting.
    func status(of permission: Permission) async -> PermissionState
    /// Shows Apple's own prompt when the state is `notDetermined`; otherwise returns the state
    /// unchanged (iOS shows a prompt once; after that the player changes it in iOS Settings).
    func request(_ permission: Permission) async -> PermissionState
}

/// Every system prompt the live adapter starts, counted for the launch test (no request on a cold
/// start) and for diagnostics.
enum PermissionRequestLog {
    private static let requests = Mutex<[Permission]>([])

    static func record(_ permission: Permission) {
        requests.withLock { $0.append(permission) }
    }

    /// Requests started since launch, in order.
    static var all: [Permission] {
        requests.withLock { $0 }
    }
}
