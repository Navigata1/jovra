import Foundation
import Testing
import JovraCore

/// T18: the local player profile. Expected values are the spec's literals (screens.md S01/S02, user stories 5, 10,
/// 12, 16), never recomputed from the store.
private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("profile-\(UUID().uuidString)", isDirectory: true)
}

/// The Keychain's role in a test: remembers one Apple identity across store instances (as the Keychain survives a
/// reinstall).
private final class MemoryVault: AppleIdentityVault, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AppleIdentity?
    init(_ identity: AppleIdentity? = nil) { stored = identity }
    func read() throws -> AppleIdentity? { lock.withLock { stored } }
    func write(_ identity: AppleIdentity) throws { lock.withLock { stored = identity } }
    func delete() throws { lock.withLock { stored = nil } }
}

private func leftHandedPlayer() -> PlayerProfile {
    var profile = PlayerProfile(name: "Sam")
    profile.handedness = .left
    profile.backhand = .oneHanded
    profile.level = .clubPlayer
    profile.goals = [.serveConsistency, .matchStrategy]
    return profile
}

@Suite("ProfileStore")
struct ProfileStoreTests {
    @Test func aNewStoreHasNoProfile() throws {
        let store = try ProfileStore(folder: temporaryFolder(), vault: MemoryVault())
        #expect(try store.load() == nil)
    }

    @Test func aSavedProfileIsReadBackByANewStoreOnTheSameFolder() throws {
        let folder = temporaryFolder()
        try ProfileStore(folder: folder, vault: MemoryVault()).save(leftHandedPlayer())

        let reopened = try #require(try ProfileStore(folder: folder, vault: MemoryVault()).load())
        #expect(reopened.name == "Sam")
        #expect(reopened.handedness == .left)
        #expect(reopened.backhand == .oneHanded)
        #expect(reopened.level == .clubPlayer)
        #expect(reopened.goals == [.serveConsistency, .matchStrategy])
        #expect(reopened.isSample == false)
    }

    @Test func editingHandednessReplacesTheStoredValue() throws {
        let store = try ProfileStore(folder: temporaryFolder(), vault: MemoryVault())
        try store.save(leftHandedPlayer())
        var edited = try #require(try store.load())
        edited.handedness = .right
        edited.backhand = .twoHanded
        try store.save(edited)
        let reread = try #require(try store.load())
        #expect(reread.handedness == .right)
        #expect(reread.backhand == .twoHanded)
    }

    @Test func nothingIsPreselected() {
        let profile = PlayerProfile()
        #expect(profile.name == "")
        #expect(profile.handedness == .unknown)
        #expect(profile.backhand == .unknown)
        #expect(profile.level == nil)
        #expect(profile.goals.isEmpty)
        #expect(profile.account == .none)
    }

    @Test func aFourthGoalIsRefusedAndTheFirstThreeKeepTheirOrder() {
        var profile = PlayerProfile()
        #expect(profile.toggleGoal(.serveConsistency) == .selected)
        #expect(profile.toggleGoal(.matchStrategy) == .selected)
        #expect(profile.toggleGoal(.improveFitness) == .selected)
        #expect(profile.toggleGoal(.winMoreMatches) == .refusedLimitReached)
        #expect(profile.goals == [.serveConsistency, .matchStrategy, .improveFitness])
        #expect(profile.toggleGoal(.matchStrategy) == .deselected)
        #expect(profile.goals == [.serveConsistency, .improveFitness])
    }

    @Test func aReturningAppleIdentifierKeepsTheExistingProfile() throws {
        let vault = MemoryVault()
        let store = try ProfileStore(folder: temporaryFolder(), vault: vault)
        #expect(try store.recordAppleSignIn(userID: "apple.0001", givenName: "Sam") == .newPlayer(prefilledName: "Sam"))
        var profile = leftHandedPlayer()
        profile.account = .apple
        try store.save(profile)

        // Apple sends the name only once; a later sign-in with another name must not rename the player.
        let outcome = try store.recordAppleSignIn(userID: "apple.0001", givenName: "Someone else")
        #expect(outcome == .returning(profile))
        #expect(try store.load() == profile)
    }

    @Test func afterAReinstallTheKeptIdentityPrefillsTheName() throws {
        // The Keychain outlives the app's files: a new folder, the same vault.
        let vault = MemoryVault()
        _ = try ProfileStore(folder: temporaryFolder(), vault: vault).recordAppleSignIn(userID: "apple.0001", givenName: "Sam")

        let reinstalled = try ProfileStore(folder: temporaryFolder(), vault: vault)
        #expect(try reinstalled.recordAppleSignIn(userID: "apple.0001", givenName: nil) == .newPlayer(prefilledName: "Sam"))
    }

    @Test func aRevokedAppleCredentialLeavesTheLocalProfileWithNoAccount() throws {
        let vault = MemoryVault()
        let store = try ProfileStore(folder: temporaryFolder(), vault: vault)
        _ = try store.recordAppleSignIn(userID: "apple.0001", givenName: "Sam")
        var profile = leftHandedPlayer()
        profile.account = .apple
        try store.save(profile)

        try store.forgetAppleIdentity()

        #expect(try store.appleUserID() == nil)
        let kept = try #require(try store.load())
        #expect(kept.account == .none)
        #expect(kept.name == "Sam")
    }

    @Test func eraseRemovesTheProfileAndTheAppleIdentity() throws {
        let vault = MemoryVault()
        let folder = temporaryFolder()
        let store = try ProfileStore(folder: folder, vault: vault)
        _ = try store.recordAppleSignIn(userID: "apple.0001", givenName: "Sam")
        try store.save(leftHandedPlayer())

        try store.erase()

        #expect(try store.load() == nil)
        #expect(try store.appleUserID() == nil)
        #expect(try ProfileStore(folder: folder, vault: vault).load() == nil)
    }

    @Test func theSampleProfileIsJonAndLabelledSample() {
        let sample = PlayerProfile.sample
        #expect(sample.name == "Jon")
        #expect(sample.isSample)
        #expect(sample.handedness == .right)
        #expect(sample.backhand == .oneHanded)
        #expect(sample.level == .clubPlayer)
        #expect(sample.goals == [.serveConsistency, .matchStrategy])
    }

    @Test func anUnreadableProfileFileIsReportedNotTreatedAsNoProfile() throws {
        let folder = temporaryFolder()
        let store = try ProfileStore(folder: folder, vault: MemoryVault())
        try Data("not json".utf8).write(to: folder.appendingPathComponent(ProfileStore.fileName))
        #expect(throws: (any Error).self) { try store.load() }
    }

    @Test func aProfileFromANewerAppIsRefused() throws {
        let folder = temporaryFolder()
        let store = try ProfileStore(folder: folder, vault: MemoryVault())
        try Data(#"{"version": 99, "name": "Sam"}"#.utf8).write(to: folder.appendingPathComponent(ProfileStore.fileName))
        #expect(throws: ProfileStoreError.unsupportedVersion(99)) { try store.load() }
    }
}
