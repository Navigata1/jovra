import Foundation
import JovraCore
import JovraVision

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
    /// Extra time per window of the vision fixture: a few seconds of recording take several seconds to analyse.
    static let visionFixturePace: Duration = .milliseconds(750)

    static func registered(for launch: LaunchConfiguration, library: LocalCaptureAvailability) -> [any SessionAnalyzer] {
        var analyzers: [any SessionAnalyzer] = []
        switch launch.processingAnalyzer {
        case .visionFixture?:
            // V00: the JovraVision fixture stages, paced so a UI test can kill JOVRA or record mid-run.
            if case .ready(let library) = library {
                analyzers.append(VisionAnalyzer(capabilityID: "fixture.vision", library: library,
                                                stages: { FixtureStages.pipeline(pace: visionFixturePace) }))
            }
        case let mode?:
            analyzers.append(FixtureAnalyzer(mode: mode))
        case nil:
            break
        }
        return analyzers
    }
}
