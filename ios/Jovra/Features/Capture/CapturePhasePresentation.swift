import Foundation
import JovraMedia

/// Engine phase is not proof of sink acknowledgment; only the coordinator's saved result is.
enum CapturePhasePresentation {
    static func title(for phase: CapturePhase) -> String {
        switch phase {
        case .idle: String(localized: "Preparing your recording", table: "Capture")
        case .ready: String(localized: "Frame your court", table: "Capture")
        case .recording: String(localized: "Recording", table: "Capture")
        case .pausing: String(localized: "Pausing recording", table: "Capture")
        case .paused: String(localized: "Paused · Not recording", table: "Capture")
        case .stopping: String(localized: "Stopping and saving", table: "Capture")
        case .stopped: String(localized: "Stopped · Not recording", table: "Capture")
        }
    }
}
