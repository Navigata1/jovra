import Foundation
import Testing
@testable import Jovra

@Suite("App preferences and the data eraser")
struct AppPreferencesTests {
    private static func freshDefaults() -> UserDefaults {
        let name = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("the v1 key set is the one the ticket declares")
    func keySet() {
        #expect(Set(AppPreferences.Key.allCases.map(\.rawValue)) == [
            "preferences.units", "appearance", "preferences.largerLiveScoreboard", "preferences.handsFreeMapping",
            "preferences.hapticConfirmations", "preferences.audioConfirmations", "preferences.appleHealth",
            "preferences.includeOriginalsInDeviceBackup", "preferences.backUpOriginals", "preferences.wifiOnly",
            "preferences.retention",
        ])
    }

    @Test("defaults: originals stay out of the iCloud backup, backup is off, Wi-Fi only, keep originals")
    func defaults() {
        let preferences = AppPreferences(defaults: Self.freshDefaults())
        #expect(preferences.appearance == .system)
        #expect(!preferences.largerLiveScoreboard)
        #expect(preferences.handsFreeMapping == .off)
        #expect(preferences.hapticConfirmations)
        #expect(!preferences.audioConfirmations)
        #expect(!preferences.appleHealth)
        #expect(!preferences.includeOriginalsInDeviceBackup)
        #expect(!preferences.backUpOriginals)
        #expect(preferences.wifiOnly)
        #expect(preferences.retention == .keepOnThisIPhone)
        #expect(preferences.units == UnitSystem.deviceDefault)
    }

    @Test("every declared key persists and reads back through a new instance")
    func persistsEveryKey() {
        let defaults = Self.freshDefaults()
        let writer = AppPreferences(defaults: defaults)
        writer.units = .metric
        writer.appearance = .dark
        writer.largerLiveScoreboard = true
        writer.handsFreeMapping = .cameraControl
        writer.hapticConfirmations = false
        writer.audioConfirmations = true
        writer.appleHealth = true
        writer.includeOriginalsInDeviceBackup = true
        writer.backUpOriginals = true
        writer.wifiOnly = false
        writer.retention = .offerRemovalAfter90Days

        // Every key now has a stored value: none was left out of the round trip below.
        for key in AppPreferences.Key.allCases {
            #expect(defaults.object(forKey: key.rawValue) != nil, "\(key.rawValue) is stored")
        }

        let reader = AppPreferences(defaults: defaults)
        #expect(reader.units == .metric)
        #expect(reader.appearance == .dark)
        #expect(reader.largerLiveScoreboard)
        #expect(reader.handsFreeMapping == .cameraControl)
        #expect(!reader.hapticConfirmations)
        #expect(reader.audioConfirmations)
        #expect(reader.appleHealth)
        #expect(reader.includeOriginalsInDeviceBackup)
        #expect(reader.backUpOriginals)
        #expect(!reader.wifiOnly)
        #expect(reader.retention == .offerRemovalAfter90Days)
    }

    @Test("the appearance key is the one Profile's @AppStorage and the -appearance argument use")
    func appearanceKey() {
        let defaults = Self.freshDefaults()
        defaults.set("light", forKey: "appearance")
        #expect(AppPreferences(defaults: defaults).appearance == .light)
        #expect(AppearancePreference.storageKey == "appearance")
    }

    @Test("an unreadable stored value falls back to the default instead of crashing")
    func unreadableValue() {
        let defaults = Self.freshDefaults()
        defaults.set("furlongs", forKey: AppPreferences.Key.units.rawValue)
        defaults.set(42, forKey: AppPreferences.Key.wifiOnly.rawValue)
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.units == UnitSystem.deviceDefault)
        #expect(preferences.wifiOnly)
    }

    @Test("the preferences eraser removes every key")
    func preferencesEraser() async throws {
        let defaults = Self.freshDefaults()
        let preferences = AppPreferences(defaults: defaults)
        preferences.backUpOriginals = true
        preferences.appearance = .dark
        try await preferences.eraser.erase()
        for key in AppPreferences.Key.allCases {
            #expect(defaults.object(forKey: key.rawValue) == nil, "\(key.rawValue) erased")
        }
        #expect(!preferences.backUpOriginals)
    }

    private struct DiskFull: Error, CustomStringConvertible {
        var description: String { "disk full" }
    }

    private actor Calls {
        var ids: [String] = []
        func record(_ id: String) { ids.append(id) }
    }

    @Test("DataEraser runs every registered eraser, even after one fails, and reports each result")
    func eraseAll() async {
        let registry = DataEraserRegistry()
        let calls = Calls()
        registry.register(DataEraser(id: "sessions") { await calls.record("sessions") })
        registry.register(DataEraser(id: "equipment") { await calls.record("equipment"); throw DiskFull() })
        registry.register(DataEraser(id: "preferences") { await calls.record("preferences") })

        let results = await registry.eraseAll()

        #expect(await calls.ids == ["sessions", "equipment", "preferences"])
        #expect(results == [
            DataErasureResult(id: "sessions", outcome: .erased),
            DataErasureResult(id: "equipment", outcome: .failed("disk full")),
            DataErasureResult(id: "preferences", outcome: .erased),
        ])
    }

    @Test("registering the same store twice keeps one eraser, the newest")
    func reRegistration() async {
        let registry = DataEraserRegistry()
        let calls = Calls()
        registry.register(DataEraser(id: "sessions") { await calls.record("old") })
        registry.register(DataEraser(id: "sessions") { await calls.record("new") })
        #expect(registry.registeredIDs == ["sessions"])
        _ = await registry.eraseAll()
        #expect(await calls.ids == ["new"])
    }

    @Test("an empty registry reports nothing")
    func emptyRegistry() async {
        #expect(await DataEraserRegistry().eraseAll().isEmpty)
    }

    @Test("the live preferences register their own eraser in the shared registry")
    func liveRegistration() {
        _ = AppPreferencesKey.live()
        #expect(DataEraserRegistry.shared.registeredIDs.contains("preferences"))
    }
}
