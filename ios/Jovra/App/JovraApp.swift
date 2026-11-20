import SwiftUI

/// The entry point. Services are not registered here: each declares its own `ServiceKey` in its own
/// file (App/Services/ServiceKey.swift). The one exception is background-task registration (T27), which
/// the system requires before launch finishes.
@main
struct JovraApp: App {
    init() {
        ProcessingBackgroundTasks.registerAtLaunch()
        Task { await ProcessingScheduler.shared.activate() }
    }

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
