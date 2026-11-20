import Foundation
import JovraCore
import Testing
@testable import Jovra

/// T27: what the processing scheduler does as JOVRA leaves and re-enters the foreground. The simulator
/// never launches background tasks, so each path is decided by this pure policy and tested here.
@Suite("Processing background policy")
struct ProcessingBackgroundPolicyTests {
    private let foreground = ProcessingBackgroundPolicy(inBackground: false, continuesInBackground: false, overnightActive: false)
    private let leftOnIOS18 = ProcessingBackgroundPolicy(inBackground: true, continuesInBackground: false, overnightActive: false)
    private let leftWithContinued = ProcessingBackgroundPolicy(inBackground: true, continuesInBackground: true, overnightActive: false)
    private let overnight = ProcessingBackgroundPolicy(inBackground: true, continuesInBackground: false, overnightActive: true)

    private func jobs(analyze: ProcessingStageState.Status, prepare: ProcessingStageState.Status = .done,
                      originalSaved: Bool = true) -> [ProcessingJob] {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: originalSaved)
        var job = queue.job("s1")!
        job.prepareReplay.status = prepare
        job.analyze.status = analyze
        return [job]
    }

    @Test("stages start in the foreground and during the overnight task, never otherwise in the background")
    func mayStart() {
        #expect(foreground.mayStart)
        #expect(overnight.mayStart)
        #expect(!leftOnIOS18.mayStart, "an interrupted stage must not restart while JOVRA is in the background")
        #expect(!leftWithContinued.mayStart, "continued processing carries the running analysis only, not new stages")
    }

    @Test("leaving JOVRA without continued processing stops the running stage at its saved progress")
    func interruptsWithoutContinuedProcessing() {
        #expect(leftOnIOS18.interruptsOnLeaving(running: .analyze))
        #expect(leftOnIOS18.interruptsOnLeaving(running: .prepareReplay))
        #expect(!leftOnIOS18.interruptsOnLeaving(running: nil))
    }

    @Test("continued processing keeps the running analysis going; nothing else it covers")
    func continuedProcessingCarriesAnalysisOnly() {
        #expect(!leftWithContinued.interruptsOnLeaving(running: .analyze))
        #expect(leftWithContinued.interruptsOnLeaving(running: .prepareReplay))
        #expect(!overnight.interruptsOnLeaving(running: .analyze), "the overnight task is background work by design")
    }

    @Test("the interrupted analysis, queued again, asks for the overnight task once the interrupt has settled")
    func overnightAfterTheInterruptSettles() {
        // While the cancellation is settling the stage still reads running: nothing is asked for yet...
        #expect(!leftOnIOS18.needsOvernight(running: true, jobs: jobs(analyze: .running)))
        // ...and once it is queued again at its saved progress, the overnight task is requested.
        #expect(leftOnIOS18.needsOvernight(running: false, jobs: jobs(analyze: .queued)))
        #expect(leftOnIOS18.needsOvernight(running: false, jobs: jobs(analyze: .unavailable, prepare: .queued)),
                "prepare replay left over counts too")
    }

    @Test("no overnight request in the foreground, during the overnight task, or with nothing it could run")
    func noOvernightRequest() {
        #expect(!foreground.needsOvernight(running: false, jobs: jobs(analyze: .queued)))
        #expect(!overnight.needsOvernight(running: false, jobs: jobs(analyze: .queued)))
        for status: ProcessingStageState.Status in [.done, .paused, .failed, .unavailable] {
            #expect(!leftOnIOS18.needsOvernight(running: false, jobs: jobs(analyze: status)), "\(status)")
        }
        #expect(!leftOnIOS18.needsOvernight(running: false, jobs: jobs(analyze: .queued, prepare: .queued, originalSaved: false)),
                "nothing runs before the original is saved")
    }
}
