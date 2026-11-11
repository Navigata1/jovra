import Foundation

/// The demo's deterministic worlds. `queue` is the normal one (the ST38 queue sample); every other case is a failure
/// state injected with the launch argument `-studioCloudScenario <rawValue>` (for UI tests, screenshots and S15's
/// `-studioState` harness).
public enum DemoCloudScenario: String, Codable, CaseIterable, Sendable {
    /// Upload complete (3 sources), Align angles complete and reviewed, Build film at 42% of its stage, Verify export
    /// queued.
    case queue
    case paused
    case retryable
    case terminal
    case canceled
    case budgetExhausted
    case quoteExpired
    case notSignedIn
    case aboveCap
    case partialUpload
    case expiredLink
    case revokedAccess
    case deletionRunning
    case deletionFailed

    /// The failure states (every case but `queue`).
    public static var failureStates: [DemoCloudScenario] { allCases.filter { $0 != .queue } }

    /// The scenario named after `-studioCloudScenario`, `queue` when the argument is absent. An unknown name or a
    /// missing value is refused, so a mistyped UI test fails instead of silently showing the normal queue.
    public init(launchArguments: [String]) throws(CloudError) {
        guard let index = launchArguments.firstIndex(of: CloudClients.scenarioArgument) else {
            self = .queue
            return
        }
        let next = launchArguments.index(after: index)
        guard next < launchArguments.endIndex, let scenario = DemoCloudScenario(rawValue: launchArguments[next]) else {
            throw .refused(code: "unknownScenario",
                           message: "\(CloudClients.scenarioArgument) needs one of \(Self.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        self = scenario
    }

    /// The launch arguments that select this scenario.
    public var launchArguments: [String] { [CloudClients.scenarioArgument, rawValue] }
}
