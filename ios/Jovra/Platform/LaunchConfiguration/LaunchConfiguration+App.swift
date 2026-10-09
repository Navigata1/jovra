import OSLog
import SwiftUI

extension LaunchConfiguration {
    /// The configuration this process was launched with. Problems are logged once, at first use.
    static let current: LaunchConfiguration = {
        let configuration = LaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
        let logger = Logger(subsystem: "com.islanddevcrew.jovra", category: "LaunchConfiguration")
        for problem in configuration.reportedProblems {
            logger.error("Ignored launch argument. \(problem, privacy: .public)")
        }
        return configuration
    }()

    /// The destination named by the start route: a tab, a pre-shell route, a push, a full-screen
    /// route or a sheet, by its launch name (`AppDestination.catalog`, e.g. `replay`,
    /// `sessions.matchOverview`, `sheet.pointEditor`).
    var startDestination: AppDestination? {
        startRoute.flatMap(AppDestination.init(launchName:))
    }

    /// Every problem logged at launch: the parser's `problems` and, since only the app knows its
    /// routes, a start route that names no destination.
    var reportedProblems: [String] {
        guard let unresolvedStartRoute else { return problems }
        return problems + ["\(Key.startRoute): unknown route “\(unresolvedStartRoute)” (expected a launch name from AppDestination.catalog, such as home, replay, sessions.matchOverview or sheet.pointEditor)"]
    }

    /// A start route that names no destination.
    var unresolvedStartRoute: String? {
        guard let startRoute, startDestination == nil else { return nil }
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
