import Foundation
import JovraCore
import Testing
@testable import Jovra

/// T18: the profile's eraser, the welcome gate, Sign in with Apple outcomes, the demo entry and the bundled sample
/// library. Expected values are the ticket's and the spec's literals.
private func temporaryFolder(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("t18-\(name)", isDirectory: true)
}

private func readyStore(_ folder: URL = temporaryFolder(), vault: MemoryAppleIdentityVault = .init()) throws -> ProfileStore {
    try ProfileStore(folder: folder, vault: vault)
}

/// The repository root, from this file (hosted tests run on the Mac that built them).
private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private struct ScriptedSignIn: AppleSignInClient {
    var result: AppleSignInResult
    var credential: AppleCredentialState = .authorized
    @MainActor func signIn() async -> AppleSignInResult { result }
    func credentialState(forUserID userID: String) async -> AppleCredentialState { credential }
}

@Suite("Profile eraser")
struct ProfileEraserTests {
    @Test("Delete all JOVRA data removes the profile and the Apple identity")
    func eraserRemovesTheProfile() async throws {
        let folder = temporaryFolder()
        let vault = MemoryAppleIdentityVault()
        let registry = DataEraserRegistry()
        guard case .ready(let store) = ProfileStoreKey.open(folder: folder, vault: vault, registry: registry) else {
            Issue.record("the store did not open"); return
        }
        _ = try store.recordAppleSignIn(userID: "apple.0001", givenName: "Sam")
        try store.save(PlayerProfile(name: "Sam", handedness: .left, backhand: .oneHanded))
        #expect(registry.registeredIDs == ["profile"])

        let results = await registry.eraseAll()

        #expect(results == [DataErasureResult(id: "profile", outcome: .erased)])
        #expect(try ProfileStore(folder: folder, vault: vault).load() == nil)
        #expect(try vault.read() == nil)
    }
}

@Suite("Welcome gate")
@MainActor
struct WelcomeGateTests {
    @Test("no profile opens Welcome; a profile, the demo profile or an unreadable file open the shell")
    func gate() {
        #expect(WelcomeGate.initialRoute(for: .loaded(nil)) == .welcome)
        #expect(WelcomeGate.initialRoute(for: .loaded(PlayerProfile(name: "Sam"))) == nil)
        #expect(WelcomeGate.initialRoute(for: .loaded(.sample)) == nil)
        #expect(WelcomeGate.initialRoute(for: .unreadable) == nil)
        #expect(WelcomeGate.initialRoute(for: .unavailable) == nil)
    }

    @Test("a launch's start route wins over the gate")
    func startRouteWins() {
        let router = AppRoot.initialRouter(launch: LaunchConfiguration(arguments: ["Jovra", "-startRoute", "profile"]), profile: .loaded(nil))
        #expect(router.preShell == nil)
        #expect(router.selectedTab == .profile)
        let gated = AppRoot.initialRouter(launch: LaunchConfiguration(arguments: ["Jovra"]), profile: .loaded(nil))
        #expect(gated.preShell == .welcome)
    }
}

@Suite("Player profile model")
@MainActor
struct PlayerProfileModelTests {
    @Test("a cancelled Apple sign-in stays on Welcome and changes nothing")
    func cancelled() async throws {
        let model = PlayerProfileModel(availability: .ready(try readyStore()))
        #expect(await model.signInWithApple(using: ScriptedSignIn(result: .cancelled)) == .stayOnWelcome(.cancelled))
        #expect(model.profile == nil)
        #expect(model.needsWelcome)
    }

    @Test("a failed Apple sign-in stays on Welcome with the failure")
    func failed() async throws {
        let model = PlayerProfileModel(availability: .ready(try readyStore()))
        #expect(await model.signInWithApple(using: ScriptedSignIn(result: .failed(reason: "offline"))) == .stayOnWelcome(.failed))
        #expect(model.needsWelcome)
    }

    @Test("a new Apple player goes to onboarding with the given name; finishing records the Apple account")
    func newApplePlayer() async throws {
        let model = PlayerProfileModel(availability: .ready(try readyStore()))
        #expect(await model.signInWithApple(using: ScriptedSignIn(result: .signedIn(userID: "apple.0001", givenName: "Sam"))) == .onboarding)
        #expect(model.draft.name == "Sam")
        try model.completeOnboarding()
        #expect(model.profile?.account == .apple)
        #expect(model.profile?.name == "Sam")
    }

    @Test("a returning Apple identifier keeps the profile and enters the shell")
    func returning() async throws {
        let store = try readyStore()
        _ = try store.recordAppleSignIn(userID: "apple.0001", givenName: "Sam")
        let kept = PlayerProfile(name: "Sam", handedness: .left, backhand: .oneHanded, account: .apple)
        try store.save(kept)
        let model = PlayerProfileModel(availability: .ready(store))
        #expect(await model.signInWithApple(using: ScriptedSignIn(result: .signedIn(userID: "apple.0001", givenName: nil))) == .enterShell)
        #expect(model.profile == kept)
    }

    @Test("a revoked Apple credential at launch keeps the profile with no account")
    func revokedAtLaunch() async throws {
        let store = try readyStore()
        _ = try store.recordAppleSignIn(userID: "apple.0001", givenName: "Sam")
        try store.save(PlayerProfile(name: "Sam", account: .apple))
        let model = PlayerProfileModel(availability: .ready(store))
        await model.checkAppleCredential(using: ScriptedSignIn(result: .cancelled, credential: .revoked))
        #expect(model.profile?.account == ProfileAccount.none)
        #expect(model.profile?.name == "Sam")
        #expect(try store.appleUserID() == nil)
    }

    @Test("Make it yours replaces the sample profile; the demo ends")
    func makeItYours() throws {
        let model = PlayerProfileModel(availability: .ready(try readyStore()))
        try model.save(.sample)
        #expect(model.isDemo)
        model.beginOnboarding()
        model.draft.name = "Sam"
        model.draft.handedness = .left
        try model.completeOnboarding()
        #expect(!model.isDemo)
        #expect(model.profile?.isSample == false)
        #expect(model.profile?.handedness == .left)
    }

    @Test("Back from Play and on again keeps the units chosen there; starting onboarding afresh forgets them")
    func unitsSurviveGoingBack() throws {
        let model = PlayerProfileModel(availability: .ready(try readyStore()))
        model.beginOnboarding()
        #expect(model.draftUnits == nil, "the Play step fills in the saved preference when it first appears")
        model.draftUnits = .metric
        #expect(model.onboardingDraft.units == .metric)
        model.beginOnboarding()
        #expect(model.draftUnits == nil)
    }

    @Test("an unreadable profile is reported, never mistaken for a first run")
    func unreadable() throws {
        let folder = temporaryFolder()
        let store = try readyStore(folder)
        try Data("{".utf8).write(to: folder.appendingPathComponent(ProfileStore.fileName))
        let model = PlayerProfileModel(availability: .ready(store))
        #expect(model.state == .unreadable)
        #expect(!model.needsWelcome)
    }
}

@Suite("Onboarding state restoration")
@MainActor
struct OnboardingRestorationTests {
    private func onboardingState(step: Int) -> RouterState {
        var state = RouterState()
        state.preShell = .onboarding(step: step)
        return state
    }

    @Test("a restored onboarding step comes back with the answers and the Apple account saved beside it")
    func resumesWithTheSavedDraft() async throws {
        let before = PlayerProfileModel(availability: .ready(try readyStore()))
        #expect(await before.signInWithApple(using: ScriptedSignIn(result: .signedIn(userID: "apple.0001", givenName: "Sam"))) == .onboarding)
        before.draft.handedness = .left
        before.draft.backhand = .oneHanded
        before.draftUnits = .metric
        let saved = try JSONEncoder().encode(before.onboardingDraft)

        // A relaunch after iOS ended the app in the background: a fresh model, no profile saved yet.
        let after = PlayerProfileModel(availability: .ready(try readyStore()))
        let restored = AppRoot.restoration(of: onboardingState(step: 3), savedDraft: saved, model: after)

        #expect(restored?.preShell == .onboarding(step: 3))
        #expect(after.draft.name == "Sam")
        #expect(after.draft.handedness == .left)
        #expect(after.draft.backhand == .oneHanded)
        #expect(after.draftUnits == .metric)
        try after.completeOnboarding()
        #expect(after.profile?.account == .apple, "the Apple association survives the restore")
        #expect(after.profile?.handedness == .left)
    }

    @Test("with no answers to restore, a new player starts again on Welcome, never past blank fields")
    func noDraftRestartsAtWelcome() throws {
        let model = PlayerProfileModel(availability: .ready(try readyStore()))
        #expect(AppRoot.restoration(of: onboardingState(step: 3), savedDraft: nil, model: model)?.preShell == .welcome)
        #expect(AppRoot.restoration(of: onboardingState(step: 3), savedDraft: Data("{".utf8), model: model)?.preShell == .welcome,
                "answers that no longer decode count as none")
    }

    @Test("with no answers to restore, Make it yours starts again at its first step with a fresh draft")
    func noDraftRestartsMakeItYours() throws {
        let model = PlayerProfileModel(availability: .ready(try readyStore()))
        try model.save(.sample)
        model.draft.name = "stale"
        #expect(AppRoot.restoration(of: onboardingState(step: 3), savedDraft: nil, model: model)?.preShell == .onboarding(step: 2))
        #expect(model.draft == PlayerProfile())
    }

    @Test("other restored states are unchanged, and a shell state never overrides a missing profile")
    func otherStates() throws {
        let fresh = PlayerProfileModel(availability: .ready(try readyStore()))
        var shell = RouterState()
        shell.selectedTab = .sessions
        #expect(AppRoot.restoration(of: shell, savedDraft: nil, model: fresh) == nil, "no profile: the welcome gate wins")
        var welcome = RouterState()
        welcome.preShell = .welcome
        #expect(AppRoot.restoration(of: welcome, savedDraft: nil, model: fresh) == welcome)

        let onboarded = PlayerProfileModel(availability: .ready(try readyStore()))
        try onboarded.save(PlayerProfile(name: "Sam"))
        #expect(AppRoot.restoration(of: shell, savedDraft: nil, model: onboarded) == shell)
    }
}

@Suite("Bundled sample library")
struct BundledSampleLibraryTests {
    @Test("the app bundles the demo library: 8 sessions, every one Sample")
    func bundledLibrary() throws {
        let content = try BundledSampleLibrary.load(in: Bundle.main)
        #expect(content.library.sessions.count == 8)
        #expect(content.library.sessions.allSatisfy { $0.sample != nil })
    }

    @Test("installing it leaves 8 Sample sessions in a fresh local library, and installing again adds none")
    func installs() async throws {
        let library = try LocalCaptureLibrary(root: temporaryFolder())
        let content = try BundledSampleLibrary.load(in: Bundle.main)
        try await library.installSampleContent(content)
        try await library.installSampleContent(content)
        let sessions = try await library.sessions()
        #expect(sessions.count == 8)
        #expect(sessions.allSatisfy { $0.sample })
    }

    @Test("the bundled copy is byte-identical to spec/fixtures/sample (scripts/ios/sync-sample-library.sh)")
    func copyMatchesFixtures() throws {
        guard let bundled = BundledSampleLibrary.url(in: Bundle.main) else {
            Issue.record("SampleLibrary.bundle is not in the app"); return
        }
        let sample = repository.appendingPathComponent("spec/fixtures/sample")
        var pairs: [(String, URL)] = [("media-manifest.json", sample.appendingPathComponent("media-manifest.json"))]
        for name in ["equipment.json", "practice-plan.json"] {
            pairs.append(("library/\(name)", sample.appendingPathComponent("library/\(name)")))
        }
        for url in try FileManager.default.contentsOfDirectory(at: sample.appendingPathComponent("library/sessions"), includingPropertiesForKeys: nil) {
            pairs.append(("library/sessions/\(url.lastPathComponent)", url))
        }
        for url in try FileManager.default.contentsOfDirectory(at: sample.appendingPathComponent("analysis/sessions"), includingPropertiesForKeys: nil) {
            pairs.append(("analysis/sessions/\(url.lastPathComponent)", url))
        }
        #expect(pairs.count == 14)
        for (path, fixture) in pairs {
            let copy = try Data(contentsOf: bundled.appendingPathComponent(path))
            let original = try Data(contentsOf: fixture)
            #expect(copy == original, "\(path) differs; run scripts/ios/sync-sample-library.sh")
        }
    }
}

@Suite("Onboarding motion and Apple sign-in switch")
struct OnboardingMotionTests {
    @Test("with Reduce Motion every onboarding change is a cross-fade; without it steps slide")
    func motion() {
        #expect(OnboardingMotion.stepChange(forward: true, reduceMotion: true) == .crossFade)
        #expect(OnboardingMotion.stepChange(forward: false, reduceMotion: true) == .crossFade)
        #expect(OnboardingMotion.stepChange(forward: true, reduceMotion: false) == .slide(.trailing))
        #expect(OnboardingMotion.rootSwap == .crossFade)
    }

    @Test("Continue with Apple is offered only when the build setting says YES")
    func appleSwitch() {
        #expect(AppleSignInAvailability.isOffered(infoDictionary: ["JovraAppleSignInEnabled": "YES"]))
        #expect(!AppleSignInAvailability.isOffered(infoDictionary: ["JovraAppleSignInEnabled": "NO"]))
        #expect(!AppleSignInAvailability.isOffered(infoDictionary: [:]))
        // This build's own setting (ios/Config/Jovra.xcconfig).
        #expect(AppleSignInAvailability.isOffered(infoDictionary: Bundle.main.infoDictionary))
    }
}
