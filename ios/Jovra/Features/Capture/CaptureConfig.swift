import JovraCore
import SwiftUI

/// What the capture route is told from outside, so later tickets plug in without editing the container.
/// - `competitionMode` (T58): the score overlay shows only the score; no prompts beyond checkpoints.
/// - `onConsentWithdrawn` (T58): called after "Delete this recording" has removed the session folder, so
///   consent records can note the withdrawal. The deletion itself never waits on it.
struct CaptureConfig {
    var competitionMode = false
    var onConsentWithdrawn: (@MainActor (SessionID) -> Void)?

    static let standard = CaptureConfig()
}

private struct CaptureConfigKey: EnvironmentKey {
    static let defaultValue = CaptureConfig.standard
}

extension EnvironmentValues {
    var captureConfig: CaptureConfig {
        get { self[CaptureConfigKey.self] }
        set { self[CaptureConfigKey.self] = newValue }
    }
}
