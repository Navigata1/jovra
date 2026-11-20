import Foundation
import JovraCore
import Observation
import OSLog

/// The player profile as the app sees it (T18): loaded once at launch for the welcome gate, edited by onboarding and
/// the Profile hub, and read by Home for the demo banner and its empty state. One instance, owned by `AppRoot` and
/// shared through the environment.
@MainActor
@Observable
final class PlayerProfileModel {
    enum State: Equatable {
        case loaded(PlayerProfile?)
        /// The saved file could not be read. It is left untouched; the app opens and the hub says so.
        case unreadable
        /// The profile folder could not be opened.
        case unavailable
    }

    private(set) var state: State
    /// What onboarding is filling in, kept across its steps (the router recreates each step's view).
    var draft = PlayerProfile()
    /// The account the next completed onboarding records ("Continue with Apple" sets it).
    private(set) var pendingAccount: ProfileAccount = .none
    /// The demo library is installed on this iPhone (its sessions are badged Sample).
    private(set) var hasSampleContent = false
    /// At least one of the player's own sessions is saved; nil until counted.
    private(set) var hasOwnSessions: Bool?

    private let availability: ProfileStoreAvailability
    private let logger = Logger(subsystem: "com.islanddevcrew.jovra", category: "Profile")

    init(availability: ProfileStoreAvailability) {
        self.availability = availability
        guard case .ready(let store) = availability else {
            state = .unavailable
            return
        }
        do {
            state = .loaded(try store.load())
        } catch {
            state = .unreadable
            Logger(subsystem: "com.islanddevcrew.jovra", category: "Profile")
                .error("The saved profile could not be read; it is left as it is. \(String(describing: error), privacy: .public)")
        }
    }

    var profile: PlayerProfile? {
        if case .loaded(let profile) = state { return profile }
        return nil
    }

    /// The demo is on: the profile is the sample "Jon", so Home and the hub show the DemoBanner.
    var isDemo: Bool { profile?.isSample == true }

    /// Home's empty state (S03): the player's own profile and no sessions of their own. Installed sample sessions never
    /// count as yours (GLOSSARY: Sample data), so after "Make it yours" this is still the honest state. False until the
    /// library has been counted.
    var isFirstRunEmpty: Bool { !isDemo && hasOwnSessions == false }

    /// No profile is saved and nothing went wrong reading one: the launch opens on Welcome (screens.md §0.1).
    var needsWelcome: Bool { state == .loaded(nil) }

    // MARK: Onboarding

    /// Starts onboarding from scratch, keeping a name Apple gave.
    func beginOnboarding(prefilledName: String? = nil, account: ProfileAccount = .none) {
        draft = PlayerProfile(name: prefilledName ?? "")
        pendingAccount = account
    }

    /// Saves the draft as the player's own profile. A demo profile is replaced; sample sessions stay installed and
    /// badged, and the banner goes because the profile is no longer Sample.
    func completeOnboarding() throws {
        var profile = draft
        profile.isSample = false
        profile.account = pendingAccount
        try save(profile)
    }

    func save(_ profile: PlayerProfile) throws {
        guard case .ready(let store) = availability else { throw ProfileModelError.storeUnavailable }
        try store.save(profile)
        state = .loaded(profile)
    }

    // MARK: Sign in with Apple

    /// Signs in and says where to go next. A cancelled or failed sign-in changes nothing.
    func signInWithApple(using client: any AppleSignInClient) async -> AppleSignInStep {
        switch await client.signIn() {
        case .cancelled:
            return .stayOnWelcome(.cancelled)
        case .failed(let reason):
            logger.notice("Sign in with Apple did not finish: \(reason, privacy: .public)")
            return .stayOnWelcome(.failed)
        case .signedIn(let userID, let givenName):
            guard case .ready(let store) = availability else { return .stayOnWelcome(.failed) }
            do {
                switch try store.recordAppleSignIn(userID: userID, givenName: givenName) {
                case .returning(let profile):
                    state = .loaded(profile)
                    return .enterShell
                case .newPlayer(let name):
                    beginOnboarding(prefilledName: name, account: .apple)
                    return .onboarding
                }
            } catch {
                logger.error("Sign in with Apple could not be recorded: \(String(describing: error), privacy: .public)")
                return .stayOnWelcome(.failed)
            }
        }
    }

    /// At launch: if Apple no longer recognises the stored identifier, forget it (the local profile stays, with no
    /// account).
    func checkAppleCredential(using client: any AppleSignInClient) async {
        guard case .ready(let store) = availability, let userID = try? store.appleUserID() else { return }
        let credential = await client.credentialState(forUserID: userID)
        guard credential == .revoked || credential == .notFound else { return }
        do {
            try store.forgetAppleIdentity()
            state = .loaded(try store.load())
        } catch {
            logger.error("A revoked Apple identity could not be forgotten: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Demo

    /// "Explore a demo": installs the sample library and, unless the player already has their own profile, the
    /// sample profile "Jon". Everything installed is badged Sample.
    func exploreDemo(library: LocalCaptureAvailability, content: SampleContent) async throws {
        try await installSample(library: library, content: content)
        if profile == nil || profile?.isSample == true {
            try save(.sample)
        }
    }

    /// "Explore the sample" with a profile of your own: sample sessions alongside yours, no demo banner.
    func installSample(library: LocalCaptureAvailability, content: SampleContent) async throws {
        guard case .ready(let library) = library else { throw ProfileModelError.libraryUnavailable }
        try await library.installSampleContent(content)
        hasSampleContent = true
    }

    /// Counts sample and own sessions for Home's banner, tiles and empty state.
    func refreshLibrary(_ library: LocalCaptureAvailability) async {
        guard case .ready(let library) = library else { return }
        do {
            hasSampleContent = !(try await library.sessions(.init(sample: true))).isEmpty
            hasOwnSessions = !(try await library.sessions(.init(sample: false))).isEmpty
        } catch {
            logger.error("The library could not be counted: \(String(describing: error), privacy: .public)")
        }
    }
}

enum ProfileModelError: Error {
    case storeUnavailable
    case libraryUnavailable
    case sampleLibraryMissing
}

/// Where Welcome goes after "Continue with Apple".
enum AppleSignInStep: Equatable {
    enum Problem: Equatable { case cancelled, failed }
    /// Back on Welcome with a plain message; "Get started" still works.
    case stayOnWelcome(Problem)
    /// A returning player: their profile is kept and the shell opens.
    case enterShell
    /// A new player: onboarding opens with Apple's name filled in.
    case onboarding
}

/// The demo library bundled with the app (`SampleLibrary.bundle`, a byte-identical copy of spec/fixtures/sample kept by
/// scripts/ios/sync-sample-library.sh).
enum BundledSampleLibrary {
    static func url(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "SampleLibrary", withExtension: "bundle")
    }

    static func load(from folder: URL) throws -> SampleContent {
        SampleContent(library: try SampleLibrary.load(
            from: folder.appendingPathComponent("library", isDirectory: true),
            mediaManifest: folder.appendingPathComponent("media-manifest.json"),
            analysis: folder.appendingPathComponent("analysis", isDirectory: true)))
    }

    static func load(in bundle: Bundle = .main) throws -> SampleContent {
        guard let folder = url(in: bundle) else { throw ProfileModelError.sampleLibraryMissing }
        return try load(from: folder)
    }
}
