import Foundation

public enum ProfileStoreError: Error, Equatable, Sendable {
    /// The file was written by a newer JOVRA; it is left as it is.
    case unsupportedVersion(Int)
    /// The profile folder or file is a symbolic link; nothing is read or written through it.
    case symbolicLink(String)
}

/// What Sign in with Apple leaves on this iPhone: Apple's stable user identifier and the given name, which Apple sends
/// only on the first sign-in. Kept in the Keychain (it outlives a reinstall), never sent anywhere.
public struct AppleIdentity: Codable, Equatable, Sendable {
    public var userID: String
    public var givenName: String?

    public init(userID: String, givenName: String?) {
        self.userID = userID
        self.givenName = givenName
    }
}

/// Where the Apple identity is kept: the Keychain in the app, memory in tests.
public protocol AppleIdentityVault: Sendable {
    func read() throws -> AppleIdentity?
    func write(_ identity: AppleIdentity) throws
    func delete() throws
}

/// What a Sign in with Apple means for this iPhone's profile.
public enum AppleSignInOutcome: Equatable, Sendable {
    /// The same Apple identifier signed in before and a profile exists: it is kept unchanged (story 5).
    case returning(PlayerProfile)
    /// No profile yet: onboarding opens with the name Apple gave (now or on an earlier sign-in) filled in.
    case newPlayer(prefilledName: String?)
}

/// The local player profile (ios-v1-spec ProfileStore): one JSON file in its own folder, written atomically, plus the
/// Apple identity in an `AppleIdentityVault`. Synchronous and small, so the welcome gate can read it at launch.
public final class ProfileStore: @unchecked Sendable {
    public static let fileName = "profile.json"

    private let folder: URL
    private let vault: any AppleIdentityVault
    private let lock = NSLock()

    /// Opens (and creates) `folder`. Refuses a folder that is a symbolic link.
    public init(folder: URL, vault: any AppleIdentityVault) throws {
        self.folder = folder
        self.vault = vault
        try Self.refuseSymbolicLink(folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private var fileURL: URL { folder.appendingPathComponent(Self.fileName) }

    /// The saved profile, or nil when there is none. An unreadable file throws: it is never mistaken for "no profile".
    public func load() throws -> PlayerProfile? {
        try locked { try unlockedLoad() }
    }

    public func save(_ profile: PlayerProfile) throws {
        try locked { try unlockedSave(profile) }
    }

    /// Records a successful Sign in with Apple and says what it means for the profile.
    public func recordAppleSignIn(userID: String, givenName: String?) throws -> AppleSignInOutcome {
        try locked {
            let given = givenName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let kept = try vault.read()
            let isSameIdentity = kept?.userID == userID
            if isSameIdentity, let profile = try unlockedLoad() {
                return .returning(profile)
            }
            // Apple sends the name once: keep the first one we were given for this identifier.
            let name = isSameIdentity ? (kept?.givenName ?? given) : given
            try vault.write(AppleIdentity(userID: userID, givenName: name))
            return .newPlayer(prefilledName: name)
        }
    }

    /// The Apple user identifier signed in on this iPhone, for the launch credential-state check.
    public func appleUserID() throws -> String? {
        try locked { try vault.read()?.userID }
    }

    /// Apple says the credential was revoked or is unknown: the identity goes, the local profile stays, now with no
    /// account.
    public func forgetAppleIdentity() throws {
        try locked {
            try vault.delete()
            if var profile = try unlockedLoad(), profile.account == .apple {
                profile.account = .none
                try unlockedSave(profile)
            }
        }
    }

    /// "Delete all JOVRA data": the profile file and the Apple identity.
    public func erase() throws {
        try locked {
            try Self.refuseSymbolicLink(fileURL)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try vault.delete()
        }
    }

    // MARK: Unlocked helpers (callers hold `lock`)

    /// Runs `body` holding the lock (written out, so the same code builds with Linux Foundation).
    private func locked<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func unlockedLoad() throws -> PlayerProfile? {
        try Self.refuseSymbolicLink(fileURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(PlayerProfile.self, from: Data(contentsOf: fileURL))
    }

    private func unlockedSave(_ profile: PlayerProfile) throws {
        try Self.refuseSymbolicLink(fileURL)
        var stored = profile
        stored.version = PlayerProfile.currentVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(stored).write(to: fileURL, options: .atomic)
    }

    private static func refuseSymbolicLink(_ url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values?.isSymbolicLink == true { throw ProfileStoreError.symbolicLink(url.lastPathComponent) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
