import BackgroundTasks
import Foundation
import JovraCore
import os

/// The system side of processing (spec: ProcessingQueue).
///
/// - iOS 26 and later: when analysis starts in the foreground, a user-initiated
///   `BGContinuedProcessingTask` carries it on with system progress after the player leaves JOVRA.
/// - iOS 18 (and whenever the system refuses that task): work runs in the foreground from resumable
///   progress, stops when JOVRA leaves the foreground ("Analysis pauses if you leave JOVRA") and does not
///   restart there; once the interrupted stage is back in the queue, an overnight `BGProcessingTask` on
///   external power is requested to finish what is left (`ProcessingBackgroundPolicy`).
///
/// Both background paths are UNVERIFIED on a device: the simulator never launches background tasks.
@MainActor
enum ProcessingBackgroundTasks {
    static let overnightIdentifier = "com.islanddevcrew.jovra.processing.overnight"
    static let continuedIdentifier = "com.islanddevcrew.jovra.continued.processing"

    private static let log = Logger(subsystem: "com.islanddevcrew.jovra", category: "processing.background")
    private static var registeredContinued = false
    private static var continued: AnyObject?

    static var supportsContinuedProcessing: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26, *) { return true }
        #endif
        return false
    }

    /// Registers the overnight task. Must run before the app finishes launching (JovraApp.init).
    static func registerAtLaunch() {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: overnightIdentifier, using: .main) { task in
            MainActor.assumeIsolated { runOvernight(task) }
        }
        if !registered { log.error("overnight processing task was not registered") }
    }

    /// Asks for an overnight run on power when work is left as JOVRA goes to the background.
    static func scheduleOvernight() {
        let request = BGProcessingTaskRequest(identifier: overnightIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        do { try BGTaskScheduler.shared.submit(request) } catch {
            log.notice("overnight processing not scheduled: \(String(describing: error), privacy: .public)")
        }
    }

    private static func runOvernight(_ task: BGTask) {
        let scheduler = ProcessingScheduler.shared
        let run = OvernightRun(task)
        task.expirationHandler = {
            Task { @MainActor in
                // Stop first, so the interrupted stage is not restarted, then report the run unfinished.
                scheduler.overnightExpired()
                run.complete(success: false)
            }
        }
        Task { @MainActor in
            await scheduler.runOvernight()
            run.complete(success: true)
        }
    }

    /// Completes the overnight task exactly once (expiry and the queue going idle can both get there).
    @MainActor private final class OvernightRun {
        private let task: BGTask
        private var completed = false
        init(_ task: BGTask) { self.task = task }
        func complete(success: Bool) {
            guard !completed else { return }
            completed = true
            task.setTaskCompleted(success: success)
        }
    }

    // MARK: Continued processing (iOS 26)

    static func beginContinuedProcessing(for session: SessionID, scheduler: ProcessingScheduler) {
        #if compiler(>=6.2)
        guard #available(iOS 26, *) else { return }
        if !registeredContinued {
            registeredContinued = BGTaskScheduler.shared.register(forTaskWithIdentifier: continuedIdentifier, using: .main) { task in
                MainActor.assumeIsolated {
                    guard let task = task as? BGContinuedProcessingTask else { return }
                    task.progress.totalUnitCount = 1000
                    continued = task
                    task.expirationHandler = {
                        Task { @MainActor in
                            ProcessingScheduler.shared.interruptRunning()
                            endContinuedProcessing(success: false)
                        }
                    }
                }
            }
        }
        let request = BGContinuedProcessingTaskRequest(
            identifier: continuedIdentifier,
            title: String(localized: "Analyzing points", table: "Processing"),
            subtitle: String(localized: "JOVRA keeps analyzing while you use other apps.", table: "Processing")
        )
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request) } catch {
            log.notice("continued processing refused: \(String(describing: error), privacy: .public)")
            scheduler.continuedProcessingRefused()
        }
        #else
        _ = session
        _ = scheduler
        #endif
    }

    static func updateContinuedProcessing(progress: Double) {
        #if compiler(>=6.2)
        guard #available(iOS 26, *), let task = continued as? BGContinuedProcessingTask else { return }
        task.progress.completedUnitCount = Int64((progress * 1000).rounded())
        #endif
    }

    static func endContinuedProcessing(success: Bool) {
        #if compiler(>=6.2)
        guard #available(iOS 26, *), let task = continued as? BGContinuedProcessingTask else { return }
        continued = nil
        task.setTaskCompleted(success: success)
        #endif
    }
}
