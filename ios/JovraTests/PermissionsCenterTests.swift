import Foundation
import Testing
@testable import Jovra

@Suite("Permissions center")
struct PermissionsCenterTests {
    /// The consequence of every state of every permission, written out by hand from screen spec S20
    /// and the copy rules: what still works, what does not, never a fake number or a medical claim.
    static let expectedConsequences: [Permission: [PermissionState: String]] = [
        .camera: [
            .notDetermined: "JOVRA asks for the camera only when you start recording. Importing videos and reviewing sessions work without it.",
            .denied: "Recording is off because camera access is off. You can still import videos and review your sessions.",
            .restricted: "Camera access is restricted on this iPhone, so JOVRA can't record. You can still import videos and review your sessions.",
            .authorized: "JOVRA can record your sessions. Videos are saved on this iPhone.",
        ],
        .microphone: [
            .notDetermined: "Optional. JOVRA asks for the microphone only when you turn on sound for a recording. Recording works without it.",
            .denied: "Recordings have no sound, so rallies won't be found automatically. Recording and scoring still work.",
            .restricted: "Microphone access is restricted on this iPhone, so recordings have no sound and rallies won't be found automatically. Recording still works.",
            .authorized: "Recordings have sound, so JOVRA can suggest where rallies start and end.",
        ],
        .photosAdd: [
            .notDetermined: "JOVRA asks to add to your photo library only when you save a clip there. Importing from Photos never needs it.",
            .denied: "Clips can't be saved to Photos. You can still share them or save them to Files.",
            .restricted: "Saving to Photos is restricted on this iPhone. You can still share clips or save them to Files.",
            .authorized: "JOVRA can add the clips you save to your photo library (add only). It can't see your other photos.",
        ],
        .notifications: [
            .notDetermined: "JOVRA asks to send notifications only when you turn on a feature that needs them, such as restring reminders.",
            .denied: "Restring reminders and analysis alerts won't appear. Everything else works.",
            .restricted: "Notifications are restricted on this iPhone, so reminders and alerts won't appear. Everything else works.",
            .authorized: "JOVRA can remind you about restrings and tell you when analysis finishes.",
        ],
        .health: [
            .notDetermined: "JOVRA asks for Apple Health only if you turn on saving sessions as workouts.",
            .denied: "Sessions aren't saved to Apple Health. You can allow JOVRA in the Health app. Nothing else changes.",
            .restricted: "Apple Health isn't available on this device, so sessions can't be saved as workouts. Nothing else changes.",
            .authorized: "Each tennis session is saved to Apple Health as a workout with its start and end time only.",
        ],
    ]

    static let expectedStatus: [PermissionState: String] = [
        .notDetermined: "Not asked yet", .denied: "Off", .restricted: "Restricted", .authorized: "Allowed",
    ]

    static let expectedAction: [PermissionState: PermissionGuidance.Action] = [
        .notDetermined: .explainThenRequest, .denied: .openSettings, .restricted: .none, .authorized: .none,
    ]

    @Test("the fake drives every state of every permission, and each state's consequence and next step are stated",
          arguments: Permission.allCases, PermissionState.allCases)
    func everyStateOfEveryPermission(permission: Permission, state: PermissionState) async throws {
        let center = FakePermissionsCenter(states: [permission: state])
        let reported = await center.status(of: permission)
        #expect(reported == state)
        let guidance = PermissionGuidance(permission, reported)
        #expect(guidance.consequence == Self.expectedConsequences[permission]?[state])
        #expect(guidance.status == Self.expectedStatus[state])
        #expect(guidance.action == Self.expectedAction[state])
        #expect(!guidance.explanation.isEmpty)
    }

    @Test("the consequence text is different for every state, so no state reads like another")
    func consequencesAreDistinct() {
        for permission in Permission.allCases {
            let texts = PermissionState.allCases.map { PermissionGuidance(permission, $0).consequence }
            #expect(Set(texts).count == PermissionState.allCases.count, "\(permission)")
        }
    }

    @Test("a request prompts only when not yet asked; denied, restricted and authorized are returned unchanged")
    func requestOnlyWhenNotDetermined() async {
        let center = FakePermissionsCenter(
            states: [.camera: .notDetermined, .microphone: .denied, .photosAdd: .restricted, .notifications: .authorized],
            answer: .denied
        )
        #expect(await center.request(.camera) == .denied, "the prompt's answer")
        #expect(await center.status(of: .camera) == .denied, "and it sticks")
        #expect(await center.request(.microphone) == .denied)
        #expect(await center.request(.photosAdd) == .restricted)
        #expect(await center.request(.notifications) == .authorized)
        #expect(center.requests == [.camera, .microphone, .photosAdd, .notifications])
    }

    @Test("an unlisted permission starts not determined")
    func defaultState() async {
        #expect(await FakePermissionsCenter().status(of: .health) == .notDetermined)
    }

    @Test("launch-injected states apply to the listed permissions; the rest use the live center")
    func injectedStates() async {
        let live = FakePermissionsCenter(states: [.microphone: .authorized])
        let center = InjectedPermissionsCenter(states: [.camera: .denied], live: live)
        #expect(await center.status(of: .camera) == .denied)
        #expect(await center.status(of: .microphone) == .authorized)
        _ = await center.request(.microphone)
        #expect(live.requests == [.microphone], "an unlisted permission's request reaches the live center")
    }

    @Test("the launch argument selects the injected center; no argument selects the live one")
    func keySelection() async {
        let injected = PermissionsCenterKey.resolve(LaunchConfiguration(arguments: ["Jovra", "-permissions", "camera=restricted"]))
        #expect(injected is InjectedPermissionsCenter)
        #expect(await injected.status(of: .camera) == .restricted)
        #expect(PermissionsCenterKey.resolve(LaunchConfiguration(arguments: ["Jovra"])) is LivePermissionsCenter)
    }

    @Test("the live adapter has started no system prompt since this app launched (cold start)")
    @MainActor
    func noRequestOnColdStart() async throws {
        // The test host is the app itself, launched as a player would launch it (no harness
        // arguments), so its shell is up; give it a moment to settle on the main actor.
        try await Task.sleep(for: .milliseconds(500))
        #expect(LaunchConfiguration.current.permissions.isEmpty, "the host launched with live permissions")
        #expect(PermissionRequestLog.all.isEmpty)
    }
}
