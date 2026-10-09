import SwiftUI

enum LocalCaptureAvailability: Sendable {
    case ready(LocalCaptureLibrary)
    case unavailable
}

/// The app's single local actor is shared by capture, library and review. Demo choices never
/// switch this registration to another store; FixtureCamera writes visibly marked sample sessions.
struct LocalCaptureLibraryKey: ServiceKey {
    static let defaultValue: LocalCaptureAvailability = resolve(.current)
    static func usesFake(_ configuration: LaunchConfiguration) -> Bool { false }
    static func fake(for configuration: LaunchConfiguration) -> LocalCaptureAvailability { defaultValue }
    static func live() -> LocalCaptureAvailability {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
                .appendingPathComponent("JOVRA", isDirectory: true)
            return .ready(try LocalCaptureLibrary(root: root))
        } catch { return .unavailable }
    }
}

extension EnvironmentValues {
    var localCaptureLibrary: LocalCaptureAvailability {
        get { self[LocalCaptureLibraryKey.self] }
        set { self[LocalCaptureLibraryKey.self] = newValue }
    }
}
