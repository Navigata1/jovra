import OSLog
import SwiftUI

extension LaunchConfiguration {
    /// The configuration this process was launched with. Problems are logged once, at first use.
    static let current: LaunchConfiguration = {
        let configuration = LaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
        let logger = Logger(subsystem: "com.islanddevcrew.jovra", category: "LaunchConfiguration")
        for problem in configuration.problems {
            logger.error("Ignored launch argument. \(problem, privacy: .public)")
        }
        return configuration
    }()

    /// The tab named by the start route, if it names one.
    var startTab: AppTab? {
        startRoute.flatMap(AppTab.init(rawValue:))
    }

    /// The full-screen route named by the start route, if it names one.
    var startFullScreenRoute: FullScreenRoute? {
        startRoute.flatMap(FullScreenRoute.init(rawValue:))
    }

    /// A start route that names neither a tab nor a full-screen route.
    var unresolvedStartRoute: String? {
        guard let startRoute, startTab == nil, startFullScreenRoute == nil else { return nil }
        return startRoute
    }
}

private struct LaunchConfigurationKey: EnvironmentKey {
    static let defaultValue = LaunchConfiguration()
}

extension EnvironmentValues {
    /// The launch configuration, for services and views that switch between live and fake behaviour.
    var launchConfiguration: LaunchConfiguration {
        get { self[LaunchConfigurationKey.self] }
        set { self[LaunchConfigurationKey.self] = newValue }
    }
}
