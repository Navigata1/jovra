import JovraCore
import SwiftUI

enum LocalCaptureAvailability: Sendable {
    case ready(LocalCaptureLibrary)
    case unavailable
}

/// The app's single local actor is shared by capture, library and review. Demo choices never
/// switch this registration to another store; FixtureCamera writes visibly marked sample sessions.
/// Only `-library fresh` does: a new, empty library in a temporary folder, so a UI test does not
/// depend on the sessions earlier tests left in the app container. `-library relaunchable` and
/// `-library relaunch` (V00) do the same in one fixed folder that survives a relaunch, so a test can kill
/// JOVRA mid-analysis and open the same library again. `-importStall` (a T26 UI-test seam) keeps the real
/// store and only pauses an import just before it publishes.
struct LocalCaptureLibraryKey: ServiceKey {
    static let defaultValue: LocalCaptureAvailability = resolve(.current)
    /// The fixed folder of the `relaunchable` test library, inside this app's temporary directory.
    static let relaunchableFolder = "JOVRA-relaunchable"

    static func usesFake(_ configuration: LaunchConfiguration) -> Bool {
        configuration.library != nil || configuration.importStall
    }
    static func fake(for configuration: LaunchConfiguration) -> LocalCaptureAvailability {
        let stall: (@Sendable (SessionWriteCheckpoint) throws -> Void)? = configuration.importStall ? stallBeforePublishing : nil
        let temporary = FileManager.default.temporaryDirectory
        switch configuration.library {
        case nil:
            return live(writeFault: stall)
        case .fresh:
            return open(root: temporary.appendingPathComponent("JOVRA-fresh-\(UUID().uuidString)", isDirectory: true), writeFault: stall)
        case .relaunchable:
            let root = temporary.appendingPathComponent(relaunchableFolder, isDirectory: true)
            try? FileManager.default.removeItem(at: root)
            return open(root: root, writeFault: stall)
        case .relaunch:
            return open(root: temporary.appendingPathComponent(relaunchableFolder, isDirectory: true), writeFault: stall)
        }
    }
    static func live() -> LocalCaptureAvailability { live(writeFault: nil) }

    /// The staged copy and its document are on disk but unpublished: the state a crash must clean up.
    @Sendable private static func stallBeforePublishing(_ checkpoint: SessionWriteCheckpoint) throws {
        guard case .documentRenamed(let url) = checkpoint, url.pathComponents.contains(".files-imports") else { return }
        Thread.sleep(forTimeInterval: 600)
    }

    private static func live(writeFault: (@Sendable (SessionWriteCheckpoint) throws -> Void)?) -> LocalCaptureAvailability {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
                .appendingPathComponent("JOVRA", isDirectory: true)
            return open(root: root, writeFault: writeFault)
        } catch { return .unavailable }
    }

    private static func open(root: URL, writeFault: (@Sendable (SessionWriteCheckpoint) throws -> Void)? = nil) -> LocalCaptureAvailability {
        do { return .ready(try LocalCaptureLibrary(root: root, writeFault: writeFault)) } catch { return .unavailable }
    }
}

extension EnvironmentValues {
    var localCaptureLibrary: LocalCaptureAvailability {
        get { self[LocalCaptureLibraryKey.self] }
        set { self[LocalCaptureLibraryKey.self] = newValue }
    }
}
