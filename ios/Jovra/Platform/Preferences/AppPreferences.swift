import Foundation
import SwiftUI

/// The player's v1 preferences, declared in one place so capture reads them and Settings renders them
/// without either ticket depending on the other. Stored in `UserDefaults`; a view that must update
/// live uses `@AppStorage(AppPreferences.Key.<key>.rawValue)` with the same defaults.
///
/// `UserDefaults` is documented as thread-safe, so the value is Sendable.
struct AppPreferences: @unchecked Sendable {
    /// Every v1 preference key. `appearance` keeps the foundation's key, which `-appearance` also sets.
    enum Key: String, CaseIterable, Sendable {
        case units = "preferences.units"
        case appearance = "appearance"
        case largerLiveScoreboard = "preferences.largerLiveScoreboard"
        case handsFreeMapping = "preferences.handsFreeMapping"
        case hapticConfirmations = "preferences.hapticConfirmations"
        case audioConfirmations = "preferences.audioConfirmations"
        case appleHealth = "preferences.appleHealth"
        case includeOriginalsInDeviceBackup = "preferences.includeOriginalsInDeviceBackup"
        case backUpOriginals = "preferences.backUpOriginals"
        case wifiOnly = "preferences.wifiOnly"
        case retention = "preferences.retention"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Speeds, weights and distances (S20 "Units"); defaults to the device's measurement system.
    var units: UnitSystem {
        get { value(.units) ?? .deviceDefault }
        nonmutating set { set(newValue, .units) }
    }

    var appearance: AppearancePreference {
        get { value(.appearance) ?? .system }
        nonmutating set { set(newValue, .appearance) }
    }

    /// A larger scoreboard while recording (S20 Accessibility).
    var largerLiveScoreboard: Bool {
        get { flag(.largerLiveScoreboard, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.largerLiveScoreboard.rawValue) }
    }

    /// What marks a point hands-free while recording (P1-12).
    var handsFreeMapping: HandsFreeMapping {
        get { value(.handsFreeMapping) ?? .off }
        nonmutating set { set(newValue, .handsFreeMapping) }
    }

    /// A haptic when a point is marked or recording starts.
    var hapticConfirmations: Bool {
        get { flag(.hapticConfirmations, default: true) }
        nonmutating set { defaults.set(newValue, forKey: Key.hapticConfirmations.rawValue) }
    }

    /// A tone or spoken confirmation, e.g. "Marked by volume button".
    var audioConfirmations: Bool {
        get { flag(.audioConfirmations, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.audioConfirmations.rawValue) }
    }

    /// Save sessions to Apple Health as workouts (opt-in, P1-22).
    var appleHealth: Bool {
        get { flag(.appleHealth, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.appleHealth.rawValue) }
    }

    /// Include originals in the iPhone's iCloud backup (D7 and ADR-0009: off by default).
    var includeOriginalsInDeviceBackup: Bool {
        get { flag(.includeOriginalsInDeviceBackup, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.includeOriginalsInDeviceBackup.rawValue) }
    }

    /// Upload a copy of originals to the player's archive (Google Drive); off until the player chooses.
    var backUpOriginals: Bool {
        get { flag(.backUpOriginals, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.backUpOriginals.rawValue) }
    }

    /// Upload only on Wi-Fi.
    var wifiOnly: Bool {
        get { flag(.wifiOnly, default: true) }
        nonmutating set { defaults.set(newValue, forKey: Key.wifiOnly.rawValue) }
    }

    /// What happens to originals after a verified backup (S19 RetentionEditor).
    var retention: OriginalRetention {
        get { value(.retention) ?? .keepOnThisIPhone }
        nonmutating set { set(newValue, .retention) }
    }

    /// Removes every stored preference, so each reads its default again.
    func reset() {
        for key in Key.allCases { defaults.removeObject(forKey: key.rawValue) }
    }

    /// This store's part of "Delete all JOVRA data".
    var eraser: DataEraser {
        DataEraser(id: "preferences") { reset() }
    }

    // MARK: Storage

    private func flag(_ key: Key, default value: Bool) -> Bool {
        defaults.object(forKey: key.rawValue) as? Bool ?? value
    }

    private func value<Value: RawRepresentable>(_ key: Key) -> Value? where Value.RawValue == String {
        defaults.string(forKey: key.rawValue).flatMap(Value.init(rawValue:))
    }

    private func set<Value: RawRepresentable>(_ value: Value, _ key: Key) where Value.RawValue == String {
        defaults.set(value.rawValue, forKey: key.rawValue)
    }
}

/// The player's appearance choice (Profile → Appearance).
enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    static let storageKey = AppPreferences.Key.appearance.rawValue

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

/// S20 "Units".
enum UnitSystem: String, CaseIterable, Identifiable, Sendable {
    case imperial, metric

    var id: String { rawValue }

    var title: String {
        switch self {
        case .imperial: String(localized: "mph · lb · ft", table: "Platform.Preferences", comment: "Units choice")
        case .metric: String(localized: "km/h · kg · m", table: "Platform.Preferences", comment: "Units choice")
        }
    }

    static var deviceDefault: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }
}

/// S20 "Hands-free Mark point" (P1-12).
enum HandsFreeMapping: String, CaseIterable, Identifiable, Sendable {
    case off, volumeButtons, cameraControl, airPods

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: String(localized: "Off", table: "Platform.Preferences", comment: "Hands-free Mark point")
        case .volumeButtons: String(localized: "Volume buttons", table: "Platform.Preferences", comment: "Hands-free Mark point")
        case .cameraControl: String(localized: "Camera Control", table: "Platform.Preferences", comment: "Hands-free Mark point")
        case .airPods: String(localized: "AirPods", table: "Platform.Preferences", comment: "Hands-free Mark point")
        }
    }
}

/// S19 RetentionEditor: "After a verified backup".
enum OriginalRetention: String, CaseIterable, Identifiable, Sendable {
    case keepOnThisIPhone, offerRemovalAfter30Days, offerRemovalAfter90Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepOnThisIPhone: String(localized: "Keep originals on this iPhone", table: "Platform.Preferences", comment: "Retention")
        case .offerRemovalAfter30Days: String(localized: "Offer to remove originals older than 30 days", table: "Platform.Preferences", comment: "Retention")
        case .offerRemovalAfter90Days: String(localized: "Offer to remove originals older than 90 days", table: "Platform.Preferences", comment: "Retention")
        }
    }
}

/// Registers the preferences (the ServiceKey seam) and their eraser.
struct AppPreferencesKey: ServiceKey {
    static let defaultValue: AppPreferences = resolve(.current)

    static func live() -> AppPreferences {
        let preferences = AppPreferences(defaults: .standard)
        DataEraserRegistry.shared.register(preferences.eraser)
        return preferences
    }

    /// The demo keeps the player's own preferences.
    static func fake(for configuration: LaunchConfiguration) -> AppPreferences { live() }
}

extension EnvironmentValues {
    var appPreferences: AppPreferences {
        get { self[AppPreferencesKey.self] }
        set { self[AppPreferencesKey.self] = newValue }
    }
}
