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
struct LocalCaptureLibraryKey: ServiceKey {
    static let defaultValue: LocalCaptureAvailability = resolve(.current)
    static func usesFake(_ configuration: LaunchConfiguration) -> Bool {
        configuration.library != nil || configuration.demo == .sample
    }
    static func fake(for configuration: LaunchConfiguration) -> LocalCaptureAvailability {
        open(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("JOVRA-fresh-\(UUID().uuidString)", isDirectory: true),
             seed: LibraryLaunchSeed.forLaunch(configuration))
    }
    static func live() -> LocalCaptureAvailability {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
                .appendingPathComponent("JOVRA", isDirectory: true)
            return open(root: root)
        } catch { return .unavailable }
    }

    private static func open(root: URL, seed: LibraryLaunchSeed? = nil) -> LocalCaptureAvailability {
        do { return .ready(try LocalCaptureLibrary(root: root, launchSeed: seed)) } catch { return .unavailable }
    }
}

extension EnvironmentValues {
    var localCaptureLibrary: LocalCaptureAvailability {
        get { self[LocalCaptureLibraryKey.self] }
        set { self[LocalCaptureLibraryKey.self] = newValue }
    }
}
