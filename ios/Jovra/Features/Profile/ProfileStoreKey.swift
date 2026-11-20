import Foundation
import JovraCore
import SwiftUI

enum ProfileStoreAvailability: Sendable {
    case ready(ProfileStore)
    /// The profile folder could not be opened. The app still opens; the Profile hub says so.
    case unavailable
}

/// Registers the player profile store (the ServiceKey seam) and its "Delete all JOVRA data" eraser. Live: one JSON file
/// in Application Support/JOVRAProfile and the Apple identity in the Keychain. A launch that names `-profile` gets a
/// store in a temporary folder and an in-memory Apple identity, so a UI test never reads or leaves a profile.
struct ProfileStoreKey: ServiceKey {
    static let defaultValue: ProfileStoreAvailability = resolve(.current)

    static func usesFake(_ configuration: LaunchConfiguration) -> Bool { configuration.profile != nil }

    static func live() -> ProfileStoreAvailability {
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
                .appendingPathComponent("JOVRAProfile", isDirectory: true)
            return open(folder: folder, vault: KeychainAppleIdentityVault())
        } catch {
            return .unavailable
        }
    }

    static func fake(for configuration: LaunchConfiguration) -> ProfileStoreAvailability {
        let temporary = FileManager.default.temporaryDirectory
        switch configuration.profile ?? .fresh {
        case .fresh:
            return open(folder: temporary.appendingPathComponent("JOVRA-profile-\(UUID().uuidString)"), vault: MemoryAppleIdentityVault())
        case .onboarded:
            let availability = open(folder: temporary.appendingPathComponent("JOVRA-profile-\(UUID().uuidString)"),
                                    vault: MemoryAppleIdentityVault())
            if case .ready(let store) = availability { try? store.save(PlayerProfile()) }
            return availability
        case .persistentNew:
            try? FileManager.default.removeItem(at: persistentTestFolder)
            return open(folder: persistentTestFolder, vault: MemoryAppleIdentityVault())
        case .persistent:
            return open(folder: persistentTestFolder, vault: MemoryAppleIdentityVault())
        }
    }

    /// The one folder a UI test keeps between two launches (`persistentNew`, then `persistent`).
    static var persistentTestFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("JOVRA-profile-uitest", isDirectory: true)
    }

    static func open(folder: URL, vault: any AppleIdentityVault, registry: DataEraserRegistry = .shared) -> ProfileStoreAvailability {
        do {
            let store = try ProfileStore(folder: folder, vault: vault)
            registry.register(eraser(for: store))
            return .ready(store)
        } catch {
            return .unavailable
        }
    }

    /// The profile's part of "Delete all JOVRA data": the profile file and the Apple identity.
    static func eraser(for store: ProfileStore) -> DataEraser {
        DataEraser(id: "profile") { try store.erase() }
    }
}

extension EnvironmentValues {
    var profileStore: ProfileStoreAvailability {
        get { self[ProfileStoreKey.self] }
        set { self[ProfileStoreKey.self] = newValue }
    }
}
