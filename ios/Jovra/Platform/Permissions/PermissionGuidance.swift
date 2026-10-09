import Foundation

/// What JOVRA tells the player about a permission in a given state: a short status, the consequence
/// (what works and what does not), and the one thing to do next. Settings (T56) shows these in its
/// rows; the explanation sheet shows them before and after Apple's prompt.
struct PermissionGuidance: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        /// Show the in-app explanation, then Apple's prompt.
        case explainThenRequest
        /// iOS shows its prompt once; after that only iOS Settings changes it (story 333).
        case openSettings
        /// Restricted by the device (Screen Time, a profile): nothing JOVRA can offer.
        case none
    }

    var permission: Permission
    var state: PermissionState

    init(_ permission: Permission, _ state: PermissionState) {
        self.permission = permission
        self.state = state
    }

    var name: String { Self.name(of: permission) }

    var action: Action {
        switch state {
        case .notDetermined: .explainThenRequest
        case .denied: .openSettings
        case .restricted: .none
        case .authorized: .none
        }
    }

    static func name(of permission: Permission) -> String {
        switch permission {
        case .camera: String(localized: "Camera", table: "Platform.Permissions")
        case .microphone: String(localized: "Microphone", table: "Platform.Permissions")
        case .photosAdd: String(localized: "Photos", table: "Platform.Permissions")
        case .notifications: String(localized: "Notifications", table: "Platform.Permissions")
        case .health: String(localized: "Apple Health", table: "Platform.Permissions")
        }
    }

    /// The short status a settings row shows.
    var status: String {
        switch state {
        case .notDetermined: String(localized: "Not asked yet", table: "Platform.Permissions", comment: "Permission status")
        case .denied: String(localized: "Off", table: "Platform.Permissions", comment: "Permission status")
        case .restricted: String(localized: "Restricted", table: "Platform.Permissions", comment: "Permission status")
        case .authorized: String(localized: "Allowed", table: "Platform.Permissions", comment: "Permission status")
        }
    }

    /// Why JOVRA wants the permission, shown before Apple's prompt.
    var explanation: String {
        switch permission {
        case .camera:
            String(localized: "JOVRA uses the camera to record your tennis sessions. Videos are saved on this iPhone before anything else happens.", table: "Platform.Permissions")
        case .microphone:
            String(localized: "Optional. With the microphone, recordings have sound, so JOVRA can suggest where rallies start and end. Recording works without it.", table: "Platform.Permissions")
        case .photosAdd:
            String(localized: "JOVRA adds the clips you choose to save to your photo library. It can't see your other photos, and importing never needs this.", table: "Platform.Permissions")
        case .notifications:
            String(localized: "JOVRA can remind you when your strings are due and tell you when analysis finishes.", table: "Platform.Permissions")
        case .health:
            String(localized: "JOVRA can save each tennis session to Apple Health as a workout with its start and end time only. It never reads your Health data.", table: "Platform.Permissions")
        }
    }

    /// What this state means for the player: what still works and what does not.
    var consequence: String {
        switch (permission, state) {
        case (.camera, .notDetermined):
            String(localized: "JOVRA asks for the camera only when you start recording. Importing videos and reviewing sessions work without it.", table: "Platform.Permissions")
        case (.camera, .denied):
            String(localized: "Recording is off because camera access is off. You can still import videos and review your sessions.", table: "Platform.Permissions")
        case (.camera, .restricted):
            String(localized: "Camera access is restricted on this iPhone, so JOVRA can't record. You can still import videos and review your sessions.", table: "Platform.Permissions")
        case (.camera, .authorized):
            String(localized: "JOVRA can record your sessions. Videos are saved on this iPhone.", table: "Platform.Permissions")
        case (.microphone, .notDetermined):
            String(localized: "Optional. JOVRA asks for the microphone only when you turn on sound for a recording. Recording works without it.", table: "Platform.Permissions")
        case (.microphone, .denied):
            String(localized: "Recordings have no sound, so rallies won't be found automatically. Recording and scoring still work.", table: "Platform.Permissions")
        case (.microphone, .restricted):
            String(localized: "Microphone access is restricted on this iPhone, so recordings have no sound and rallies won't be found automatically. Recording still works.", table: "Platform.Permissions")
        case (.microphone, .authorized):
            String(localized: "Recordings have sound, so JOVRA can suggest where rallies start and end.", table: "Platform.Permissions")
        case (.photosAdd, .notDetermined):
            String(localized: "JOVRA asks to add to your photo library only when you save a clip there. Importing from Photos never needs it.", table: "Platform.Permissions")
        case (.photosAdd, .denied):
            String(localized: "Clips can't be saved to Photos. You can still share them or save them to Files.", table: "Platform.Permissions")
        case (.photosAdd, .restricted):
            String(localized: "Saving to Photos is restricted on this iPhone. You can still share clips or save them to Files.", table: "Platform.Permissions")
        case (.photosAdd, .authorized):
            String(localized: "JOVRA can add the clips you save to your photo library (add only). It can't see your other photos.", table: "Platform.Permissions")
        case (.notifications, .notDetermined):
            String(localized: "JOVRA asks to send notifications only when you turn on a feature that needs them, such as restring reminders.", table: "Platform.Permissions")
        case (.notifications, .denied):
            String(localized: "Restring reminders and analysis alerts won't appear. Everything else works.", table: "Platform.Permissions")
        case (.notifications, .restricted):
            String(localized: "Notifications are restricted on this iPhone, so reminders and alerts won't appear. Everything else works.", table: "Platform.Permissions")
        case (.notifications, .authorized):
            String(localized: "JOVRA can remind you about restrings and tell you when analysis finishes.", table: "Platform.Permissions")
        case (.health, .notDetermined):
            String(localized: "JOVRA asks for Apple Health only if you turn on saving sessions as workouts.", table: "Platform.Permissions")
        case (.health, .denied):
            String(localized: "Sessions aren't saved to Apple Health. You can allow JOVRA in the Health app. Nothing else changes.", table: "Platform.Permissions")
        case (.health, .restricted):
            String(localized: "Apple Health isn't available on this device, so sessions can't be saved as workouts. Nothing else changes.", table: "Platform.Permissions")
        case (.health, .authorized):
            String(localized: "Each tennis session is saved to Apple Health as a workout with its start and end time only.", table: "Platform.Permissions")
        }
    }
}
