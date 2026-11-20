import Foundation
import JovraCore

/// One on-device analysis the analyze stage runs over a saved session (ADR-0031: every result is
/// `estimated` and is gated by its benchmark before it is registered here).
protocol SessionAnalyzer: Sendable {
    /// The capability registry id the analyzer produces results for.
    var capabilityID: String { get }
    /// Runs from `progress` (0…1, the saved resume point), reporting progress as it goes. `attempt` is 1
    /// for the first run and counts retries. Throws to fail the stage; cancellation pauses it.
    func analyze(_ session: SessionID, attempt: Int, from progress: Double,
                 report: @Sendable (Double) async throws -> Void) async throws
}

/// The registered analyzers. Each lives in its own file in this folder and is listed here; the
/// production list is empty until a V-track ticket passes its benchmark gate, so the analyze stage
/// reports unavailable with its reason instead of pretending to analyse.
enum AnalyzerRegistry {
    static func registered(for launch: LaunchConfiguration) -> [any SessionAnalyzer] {
        var analyzers: [any SessionAnalyzer] = []
        if let fixture = launch.processingAnalyzer {
            analyzers.append(FixtureAnalyzer(mode: fixture))
        }
        return analyzers
    }
}
