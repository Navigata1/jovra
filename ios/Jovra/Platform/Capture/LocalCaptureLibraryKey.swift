import JovraCore
import SwiftUI

enum LocalCaptureAvailability: Sendable {
    case ready(LocalCaptureLibrary)
    case unavailable
}

/// The app's single local actor is shared by capture, library and review. FixtureCamera writes visibly
/// marked sample sessions. A harness launch that asks for a library of its own gets a new one in a temporary
/// folder, so a UI test does not depend on the sessions earlier tests left in the app container and never
/// writes into the library saved on the device: `-library fresh` (empty), `-library facets` (the facet
/// fixtures) and `-demo sample` (the shipped Sample library, installed through SampleContent).
/// `-importStall` (a T26 UI-test seam) only pauses an import just before it publishes; on its own it keeps
/// the library saved on the device.
struct LocalCaptureLibraryKey: ServiceKey {
    static let defaultValue: LocalCaptureAvailability = resolve(.current)
    static func usesFake(_ configuration: LaunchConfiguration) -> Bool {
        usesTemporaryLibrary(configuration) || configuration.importStall
    }
    static func fake(for configuration: LaunchConfiguration) -> LocalCaptureAvailability {
        let stall: (@Sendable (SessionWriteCheckpoint) throws -> Void)? = configuration.importStall ? stallBeforePublishing : nil
        guard usesTemporaryLibrary(configuration) else { return live(writeFault: stall) }
        return open(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("JOVRA-fresh-\(UUID().uuidString)", isDirectory: true),
                    seed: LibraryLaunchSeed.forLaunch(configuration), writeFault: stall)
    }
    private static func usesTemporaryLibrary(_ configuration: LaunchConfiguration) -> Bool {
        configuration.library != nil || configuration.demo == .sample
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

    private static func open(root: URL, seed: LibraryLaunchSeed? = nil,
                             writeFault: (@Sendable (SessionWriteCheckpoint) throws -> Void)? = nil) -> LocalCaptureAvailability {
        do { return .ready(try LocalCaptureLibrary(root: root, launchSeed: seed, writeFault: writeFault)) } catch { return .unavailable }
    }
}

extension EnvironmentValues {
    var localCaptureLibrary: LocalCaptureAvailability {
        get { self[LocalCaptureLibraryKey.self] }
        set { self[LocalCaptureLibraryKey.self] = newValue }
    }
}
