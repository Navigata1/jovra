import Foundation
import JovraCore
import Testing
@testable import Jovra

/// T27: what screen 7's stage timeline says for each queue state. Expected copy is the brief's and the
/// spec's words, written out by hand.
@Suite("Processing stage presentation")
struct ProcessingStagePresentationTests {
    private let english = Locale(identifier: "en_US")

    private func job(analyze: ProcessingStageState, prepare: ProcessingStageState = .init(status: .done, progress: 1),
                     backup: ProcessingStageState = .init(status: .blocked, reason: .awaitingArchiveSetup)) -> ProcessingJob {
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: true)
        var job = queue.job("s1")!
        job.prepareReplay = prepare
        job.analyze = analyze
        job.backup = backup
        return job
    }

    @Test("the four stages, in order, with the brief's names")
    func stageNames() {
        let rows = ProcessingStagePresentation.rows(original: .init(state: .saved), recordingMode: .import,
                                                    job: job(analyze: .init(status: .running, progress: 0.62)), hold: nil, locale: english)
        #expect(rows.map(\.title) == ["Saved locally", "Preparing replay", "Analyzing points", "Backing up"])
        #expect(rows[0].detail == "Video copied to your device")
        #expect(rows[0].trailing == "100%")
        #expect(rows[2].trailing == "62%")
        #expect(rows[2].indicator == .active(0.62))
        #expect(rows[3].detail == "Awaiting Google Drive setup")
        #expect(rows[3].trailing == "—")
    }

    @Test("View session is available as soon as the original is saved, not before")
    func viewable() {
        #expect(ProcessingStagePresentation.isViewable(.init(state: .saved)))
        #expect(ProcessingStagePresentation.isViewable(.init(state: .savedWithGaps)))
        #expect(ProcessingStagePresentation.isViewable(.init(state: .partial)))
        #expect(ProcessingStagePresentation.isViewable(.init(state: .recording)) == false)
        #expect(ProcessingStagePresentation.isViewable(.init(state: .missing)) == false)
        #expect(ProcessingStagePresentation.isViewable(nil) == false)
    }

    @Test("no analyzer registered: the analyze stage says unavailable and why")
    func unavailable() {
        let rows = ProcessingStagePresentation.rows(original: .init(state: .saved), recordingMode: .camera,
                                                    job: job(analyze: .init(status: .unavailable, reason: .noAnalyzerRegistered)),
                                                    hold: nil, locale: english)
        #expect(rows[2].status == "Unavailable")
        #expect(rows[2].indicator == .unavailable)
        #expect(rows[2].detail.hasPrefix("Unavailable: no automatic analysis is installed in this version yet."))
    }

    @Test("no analyzer under a Low Power Mode or heat hold: Unavailable with its reason, no Pause, no background line",
          arguments: [ProcessingHold.lowPower, .tooWarm])
    func unavailableUnderAHold(_ hold: ProcessingHold) {
        // A freshly saved session, queued while the hold is in force, as the scheduler sees it on enqueue
        // with nothing registered: the queue marks the analysis unavailable whatever the hold.
        var queue = ProcessingQueue()
        queue.enqueue("s1", originalSaved: true)
        queue.markQueuedUnavailable(.analyze, reason: .noAnalyzerRegistered)
        let job = queue.job("s1")
        let analyze = ProcessingStagePresentation.rows(original: .init(state: .saved), recordingMode: .camera,
                                                       job: job, hold: hold, locale: english)[2]
        #expect(analyze.status == "Unavailable")
        #expect(analyze.indicator == .unavailable)
        #expect(analyze.detail.hasPrefix("Unavailable: no automatic analysis is installed in this version yet."))
        #expect(ProcessingStagePresentation.holdDetail(hold).map { analyze.detail.contains($0) } == false,
                "the hold's waiting copy is not shown for an analysis this build cannot run")
        #expect(ProcessingStagePresentation.analysisAction(for: job?.analyze.status) == nil, "no Pause analysis")
        for continues in [true, false] {
            #expect(ProcessingStagePresentation.backgroundNote(analysis: job?.analyze.status, continuesInBackground: continues) == nil,
                    "no 'Runs on this iPhone' line")
        }
    }

    @Test("the analysis control and background line follow the analyze stage")
    func controlsFollowTheStage() {
        #expect(ProcessingStagePresentation.analysisAction(for: .running) == .pause)
        #expect(ProcessingStagePresentation.analysisAction(for: .queued) == .pause)
        #expect(ProcessingStagePresentation.analysisAction(for: .paused) == .resume)
        #expect(ProcessingStagePresentation.analysisAction(for: .failed) == .retry)
        #expect(ProcessingStagePresentation.analysisAction(for: .done) == nil)
        #expect(ProcessingStagePresentation.analysisAction(for: nil) == nil)
        #expect(ProcessingStagePresentation.backgroundNote(analysis: .running, continuesInBackground: true)
                == "Analysis continues if you switch apps")
        #expect(ProcessingStagePresentation.backgroundNote(analysis: .paused, continuesInBackground: false)
                == "Analysis pauses if you leave JOVRA")
        #expect(ProcessingStagePresentation.backgroundNote(analysis: .failed, continuesInBackground: false) == nil)
        #expect(ProcessingStagePresentation.backgroundNote(analysis: .done, continuesInBackground: true) == nil)
    }

    @Test("a failed analysis keeps the video's promise; a paused one keeps its percentage")
    func failedAndPaused() {
        let failed = ProcessingStagePresentation.rows(original: .init(state: .saved), recordingMode: .camera,
                                                      job: job(analyze: .init(status: .failed, progress: 0.4, reason: .analyzerFailed)),
                                                      hold: nil, locale: english)[2]
        #expect(failed.status == "Failed")
        #expect(failed.detail == "Analysis stopped. Your video is safe and still plays.")
        let paused = ProcessingStagePresentation.rows(original: .init(state: .saved), recordingMode: .camera,
                                                      job: job(analyze: .init(status: .paused, progress: 0.4)), hold: nil, locale: english)[2]
        #expect(paused.status == "Paused")
        #expect(paused.trailing == "40%")
    }

    @Test("backup says why it has not started")
    func backupCopy() {
        func backupDetail(_ state: ProcessingStageState) -> String {
            ProcessingStagePresentation.rows(original: .init(state: .saved), recordingMode: .camera,
                                             job: job(analyze: .init(status: .queued), backup: state), hold: nil, locale: english)[3].detail
        }
        #expect(backupDetail(.init(status: .blocked, reason: .waitingForWiFi)) == "Backup waits for Wi-Fi")
        #expect(backupDetail(.init(status: .queued)) == "Queued for your Google Drive archive")
    }

    @Test("a held queue says what it waits for")
    func holds() {
        let rows = ProcessingStagePresentation.rows(original: .init(state: .saved), recordingMode: .camera,
                                                    job: job(analyze: .init(status: .queued)), hold: .tooWarm, locale: english)
        #expect(rows[2].detail == "Waiting for your iPhone to cool down")
        #expect(ProcessingStagePresentation.holdDetail(.captureActive) == "Waits while you record")
    }
}
