import SwiftUI

/// The entry point. Services are not registered here: each declares its own `ServiceKey` in its own
/// file (App/Services/ServiceKey.swift), so no ticket after T07 edits this file.
@main
struct JovraApp: App {
    /// "system", "light" or "dark". UI tests pass `-appearance dark` as a launch argument.
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .preferredColorScheme(appearance.colorScheme)
                .tint(.jovra(.textPrimary))
                .environment(\.launchConfiguration, .current)
        }
    }
}
