import Foundation
import JovraCore

/// What the processing scheduler may do around the foreground (spec: ProcessingQueue). Pure, so each
/// path is unit-tested: the simulator never launches background tasks.
///
/// - In the foreground every stage may start.
/// - On leaving JOVRA the running stage stops at its saved progress, unless it is an analysis carried by
///   the system's continued-processing task (iOS 26) or the overnight task is what is running it.
/// - In the background no new stage starts except inside the overnight `BGProcessingTask`; once nothing
///   is running and work is left, the overnight task is requested.
struct ProcessingBackgroundPolicy: Equatable {
    var inBackground: Bool
    /// A continued-processing task carries a running analysis outside JOVRA (false on iOS 18 and when
    /// the system refused it).
    var continuesInBackground: Bool
    /// The overnight `BGProcessingTask` is running.
    var overnightActive: Bool

    /// Whether a new stage may start now.
    var mayStart: Bool { !inBackground || overnightActive }

    /// Whether `running` must stop at its saved progress as JOVRA leaves the foreground.
    func interruptsOnLeaving(running stage: ProcessingStage?) -> Bool {
        guard let stage, !overnightActive else { return false }
        return !(continuesInBackground && stage == .analyze)
    }

    /// Whether to ask for the overnight task: JOVRA is in the background, nothing is running (an
    /// interrupted stage has settled back into the queue) and a stage the scheduler runs is waiting.
    func needsOvernight(running: Bool, jobs: some Sequence<ProcessingJob>) -> Bool {
        guard inBackground, !overnightActive, !running else { return false }
        return jobs.contains { job in
            job.originalSaved && (job.prepareReplay.status == .queued || job.analyze.status == .queued)
        }
    }
}
