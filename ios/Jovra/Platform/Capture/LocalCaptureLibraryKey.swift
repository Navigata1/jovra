import JovraCore
import SwiftUI

enum LocalCaptureAvailability: Sendable {
    case ready(LocalCaptureLibrary)
    case unavailable
}

/// The app's single local actor is shared by capture, library and review. Demo choices never
/// switch this registration to another store; FixtureCamera writes visibly marked sample sessions.
struct LocalCaptureLibraryKey: ServiceKey {
    static let defaultValue: LocalCaptureAvailability = resolve(.current)
    /// The real store either way; `-importStall` (a UI-test seam) only adds a pause before an import publishes.
    static func usesFake(_ configuration: LaunchConfiguration) -> Bool { configuration.importStall }
    static func fake(for configuration: LaunchConfiguration) -> LocalCaptureAvailability {
        make { checkpoint in
            guard case .documentRenamed(let url) = checkpoint, url.pathComponents.contains(".files-imports") else { return }
            // The staged copy and its document are on disk but unpublished: the state a crash must clean up.
            Thread.sleep(forTimeInterval: 600)
        }
    }
    static func live() -> LocalCaptureAvailability { make(nil) }

    private static func make(_ writeFault: (@Sendable (SessionWriteCheckpoint) throws -> Void)?) -> LocalCaptureAvailability {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
                .appendingPathComponent("JOVRA", isDirectory: true)
            return .ready(try LocalCaptureLibrary(root: root, writeFault: writeFault))
        } catch { return .unavailable }
    }
}

extension EnvironmentValues {
    var localCaptureLibrary: LocalCaptureAvailability {
        get { self[LocalCaptureLibraryKey.self] }
        set { self[LocalCaptureLibraryKey.self] = newValue }
    }
}
