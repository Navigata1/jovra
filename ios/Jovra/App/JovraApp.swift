import SwiftUI

@main
struct JovraApp: App {
    /// "system", "light" or "dark". UI tests pass `-appearance dark` as a launch argument.
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    var body: some Scene {
        WindowGroup {
            AppShell()
                .preferredColorScheme(appearance.colorScheme)
                .tint(.jovra(.textPrimary))
                .environment(\.launchConfiguration, .current)
        }
    }
}

/// The player's appearance choice (Profile → Appearance).
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System", table: "App", comment: "Appearance: follow the device")
        case .light: String(localized: "Light", table: "App", comment: "Appearance")
        case .dark: String(localized: "Dark", table: "App", comment: "Appearance")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
