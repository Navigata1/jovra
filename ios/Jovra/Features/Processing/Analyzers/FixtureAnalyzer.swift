import Foundation
import JovraCore

/// The UI-test analyzer, registered only with `-processingAnalyzer` (like the fixture camera). It
/// produces no results and no metrics: it only moves the analyze stage's progress over about ten
/// seconds, so tests can watch progress, pause, resume, an injected failure and a retry.
struct FixtureAnalyzer: SessionAnalyzer {
    struct InjectedFailure: Error {}

    static let step = 0.025
    static let interval: Duration = .milliseconds(250)
    /// `failsOnce` fails its first attempt here.
    static let failurePoint = 0.4

    var mode: LaunchConfiguration.ProcessingAnalyzer
    var capabilityID: String { "fixture.processing" }

    func analyze(_ session: SessionID, attempt: Int, from progress: Double,
                 report: @Sendable (Double) async throws -> Void) async throws {
        var current = progress
        while current < 1 {
            try await Task.sleep(for: Self.interval)
            current = min(1, current + Self.step)
            if mode == .failsOnce, attempt == 1, current >= Self.failurePoint { throw InjectedFailure() }
            try await report(current)
        }
    }
}
