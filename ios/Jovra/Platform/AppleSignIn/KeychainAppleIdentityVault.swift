import Foundation
import JovraCore
import Security

/// Keeps the Apple identity (user identifier and given name) in the Keychain, this device only, so a reinstall can
/// recognise a returning player (screens.md S01, "Returning user after reinstall"). Nothing here is a token or a
/// credential: Sign in with Apple is local only in v1 (open question 1).
struct KeychainAppleIdentityVault: AppleIdentityVault {
    enum VaultError: Error, Equatable {
        case keychain(OSStatus)
    }

    var service = "com.islanddevcrew.jovra.apple-identity"
    var account = "self"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read() throws -> AppleIdentity? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw VaultError.keychain(status) }
        return try JSONDecoder().decode(AppleIdentity.self, from: data)
    }

    func write(_ identity: AppleIdentity) throws {
        let data = try JSONEncoder().encode(identity)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw VaultError.keychain(update) }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw VaultError.keychain(added) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.keychain(status) }
    }
}

/// A vault that lives only as long as the process: UI-test launches use it so they never touch the Keychain.
final class MemoryAppleIdentityVault: AppleIdentityVault, @unchecked Sendable {
    private let lock = NSLock()
    private var identity: AppleIdentity?

    func read() throws -> AppleIdentity? { lock.withLock { identity } }
    func write(_ identity: AppleIdentity) throws { lock.withLock { self.identity = identity } }
    func delete() throws { lock.withLock { identity = nil } }
}
