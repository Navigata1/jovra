import Foundation
import JovraCore
import JovraVision
import os

/// The analyze stage's JovraVision pipeline (V00): it reads the session's saved recording segment by
/// segment and runs the given stages through `AnalysisRunner`, which checkpoints every window in the
/// session's analysis folder. An app kill or a pause stops it at its last checkpoint; the next run resumes
/// there. A retry after a failure starts again from the beginning.
///
/// Observations stay in the analysis folder. Turning them into session events (`SessionSuggestions`) is the
/// job of the V tickets that ship a gated capability.
struct VisionAnalyzer: SessionAnalyzer {
    struct NoRecording: Error {}

    var capabilityID: String
    var library: LocalCaptureLibrary
    var stages: @Sendable () -> [any AnalysisStage]
    var budget: any AnalysisBudget = DeviceAnalysisBudget()

    private static let log = Logger(subsystem: "com.islanddevcrew.jovra", category: "processing.vision")

    func analyze(_ session: SessionID, attempt: Int, from progress: Double,
                 report: @Sendable (Double) async throws -> Void) async throws {
        let sources = try await library.analysisSources(session)
        guard !sources.isEmpty else { throw NoRecording() }
        let reader = try await RecordingWindowReader.open(sources)
        let runner = AnalysisRunner(stages: stages(), reader: reader, workspace: await library.analysisFolder(session),
                                    budget: budget) { pause in
            Self.log.notice("analysis held: \(pause.rawValue, privacy: .public)")
        }
        // The queue resets progress to 0 only for a retry, which starts again rather than resuming.
        let restart = attempt > 1 && progress == 0
        try await runner.run(restart: restart, progress: report)
    }
}
