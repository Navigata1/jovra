import SwiftUI

/// Registers the permissions center (the ServiceKey seam): live system permissions, or the injected
/// states when the launch names any (`-permissions camera=denied`).
struct PermissionsCenterKey: ServiceKey {
    static let defaultValue: any PermissionsCenter = resolve(.current)

    static func live() -> any PermissionsCenter { LivePermissionsCenter() }

    static func fake(for configuration: LaunchConfiguration) -> any PermissionsCenter {
        InjectedPermissionsCenter(states: configuration.permissions)
    }

    static func usesFake(_ configuration: LaunchConfiguration) -> Bool {
        !configuration.permissions.isEmpty
    }
}

extension EnvironmentValues {
    var permissionsCenter: any PermissionsCenter {
        get { self[PermissionsCenterKey.self] }
        set { self[PermissionsCenterKey.self] = newValue }
    }
}
