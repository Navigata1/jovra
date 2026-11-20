import JovraCore
import JovraMedia

/// What the capture engine is asked to record for a session setup: the camera preset chosen on S04
/// (stories 49, 50) and the microphone choice (story 52). The setup screen's camera row, storage
/// estimate and microphone row describe exactly this recording.
enum CaptureRecordingPlan {
    /// What the capture route records when it opens without a setup (and the fixture clip's own format).
    static let defaultPreset = CapturePreset(width: 1280, height: 720, bitRate: 4_000_000)

    /// The chosen preset among those this camera offers, or the first offered one when the remembered
    /// preset is not offered here (as the camera row shows); the default when nothing is offered.
    static func preset(for setup: SessionSetup?, offered: [CaptureFormatOption]) -> CapturePreset {
        guard let setup, let option = CaptureFormatCatalog.option(id: setup.cameraFormatID, in: offered) else {
            return defaultPreset
        }
        return option.preset
    }

    enum Microphone: Equatable, Sendable {
        case record(SessionRecordingMicrophone)
        /// iOS has not asked yet: the in-app explanation comes first (story 17, never at launch).
        case askFirst
    }

    /// Off records without sound and never asks. On records with sound when allowed and without it when
    /// refused: recording never waits on the microphone (CLAUDE.md rule 3).
    static func microphone(on: Bool, permission: PermissionState) -> Microphone {
        guard on else { return .record(.notRequested) }
        switch permission {
        case .authorized: return .record(.granted)
        case .denied, .restricted: return .record(.denied)
        case .notDetermined: return .askFirst
        }
    }
}
