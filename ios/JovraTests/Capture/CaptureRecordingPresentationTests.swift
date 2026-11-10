import JovraCore
import JovraMedia
import SwiftUI
import XCTest
@testable import Jovra

/// The recording phase's words and numbers. Expected strings are the user stories' own examples
/// ("REC 12:46", "Saved through 41:12", "Gap 41:12–41:31 · …", "Recording stopped at 41:12 — Resume?").
final class CaptureRecordingPresentationTests: XCTestCase {
    private let at4112 = 2_472_000   // 41:12
    private let at4131 = 2_491_000   // 41:31

    func testTheRecTimerCountsRecordedVideoAndLeavesGapsOut() {
        // 13:05 of session time with a 19 s phone call: 12:46 of video.
        let state = CaptureRecordingState(phase: .recording, sessionTimeMs: 785_000, savedThroughMs: 784_000,
                                          gaps: [SessionGap(startMs: 300_000, endMs: 319_000, reason: .interruption)])
        XCTAssertEqual(state.recordedMs, 766_000)
        XCTAssertEqual(CaptureRecordingCopy.pillText(state), "REC 12:46")
        XCTAssertEqual(CaptureRecordingCopy.pillAccessibilityLabel(state), "Recording, 12 minutes, 46 seconds")
    }

    func testAPausedPillSaysPausedWithoutTheRecordingDot() {
        let state = CaptureRecordingState(phase: .paused, sessionTimeMs: 766_000, savedThroughMs: 766_000)
        XCTAssertTrue(state.isPlayerPause)
        XCTAssertEqual(CaptureRecordingCopy.pillText(state), "Paused 12:46")
        XCTAssertEqual(CaptureRecordingCopy.pillAccessibilityLabel(state), "Paused, 12 minutes, 46 seconds recorded")
    }

    func testAStoppingOrStoppedEngineIsNeverDrawnAsRecording() {
        for phase: CapturePhase in [.stopping, .stopped] {
            let state = CaptureRecordingState(phase: phase, sessionTimeMs: 4_000, savedThroughMs: 4_000)
            XCTAssertEqual(state.pill, .stopped, "\(phase): no REC dot")
            XCTAssertEqual(CaptureRecordingCopy.pillText(state), "Stopped 0:04")
            XCTAssertEqual(CaptureRecordingCopy.pillAccessibilityLabel(state), "Stopped, 4 seconds recorded")
        }
        XCTAssertEqual(CaptureRecordingState(phase: .recording, sessionTimeMs: 0, savedThroughMs: nil).pill, .recording)
        XCTAssertEqual(CaptureRecordingState(phase: .pausing, sessionTimeMs: 0, savedThroughMs: nil).pill, .paused)
        XCTAssertEqual(CaptureRecordingCopy.stoppedBanner, "Stopped · Not recording")
        XCTAssertFalse(CaptureRecordingCopy.stoppedBanner.contains("Saved"))
    }

    func testAStoppedEngineWithNothingInFlightAndNoSaveIsAFailedStop() {
        let stopped = CaptureRecordingState(phase: .stopped, sessionTimeMs: 4_000, savedThroughMs: 4_000)
        XCTAssertNil(stopped.stopFailure(isWorking: true, recorded: nil), "still saving: not yet a failure")
        XCTAssertEqual(stopped.stopFailure(isWorking: false, recorded: nil), .saveFailed, "however the engine got here")
        XCTAssertEqual(stopped.stopFailure(isWorking: false, recorded: .deleteFailed), .deleteFailed)
        XCTAssertEqual(stopped.stopFailure(isWorking: true, recorded: .deleteFailed), .deleteFailed,
                       "the failure stays on screen while its retry runs")
        for phase: CapturePhase in [.recording, .pausing, .paused, .stopping] {
            let state = CaptureRecordingState(phase: phase, sessionTimeMs: 4_000, savedThroughMs: 4_000)
            XCTAssertNil(state.stopFailure(isWorking: false, recorded: .saveFailed), "\(phase)")
        }
    }

    func testAFailedStopSaysWhatFailedAndWhatIsStillOnThisIPhone() {
        XCTAssertEqual(CaptureRecordingCopy.stopFailureTitle(.saveFailed), "JOVRA could not finish saving this recording")
        XCTAssertEqual(CaptureRecordingCopy.stopFailureMessage(.saveFailed, savedThroughMs: at4112),
                       "Video up to 41:12 is on this iPhone. JOVRA will look for it the next time it opens.")
        for nothing in [nil, 0] as [Int?] {
            XCTAssertEqual(CaptureRecordingCopy.stopFailureMessage(.saveFailed, savedThroughMs: nothing),
                           "Nothing from this recording was confirmed as saved on this iPhone.", "no time is invented")
        }
        XCTAssertEqual(CaptureRecordingCopy.stopFailureTitle(.deleteFailed), "This recording could not be deleted")
        XCTAssertEqual(CaptureRecordingCopy.stopFailureMessage(.deleteFailed, savedThroughMs: at4112),
                       "It is still on this iPhone. Try deleting it again.")
        XCTAssertEqual(CaptureRecordingCopy.stopFailureAnnouncement(.saveFailed), "Recording stopped. JOVRA could not finish saving it.")
        XCTAssertEqual(CaptureRecordingCopy.stopFailureAnnouncement(.deleteFailed),
                       "Recording stopped. It could not be deleted and is still on this iPhone.")
    }

    func testAnAutomaticStopIsExplainedOnlyFromStoredCaptureEvents() {
        func recording(_ events: [SessionCaptureEvent]?) -> SessionRecording {
            SessionRecording(mode: .simulatorFixture, durationMs: at4112, segments: [], gaps: [], microphone: .notRequested,
                             mediaAvailable: true, captureEvents: events)
        }
        XCTAssertNil(CaptureRecordingCopy.automaticStopReason(recording(nil)), "the player's own Stop needs no reason")
        XCTAssertNil(CaptureRecordingCopy.automaticStopReason(recording([.init(tMs: 10, kind: .courtModeOn)])))
        XCTAssertEqual(CaptureRecordingCopy.automaticStopReason(recording([.init(tMs: at4112, kind: .lowStorageStop)])),
                       "Storage full. Everything up to 41:12 is saved.")
        XCTAssertEqual(CaptureRecordingCopy.automaticStopReason(recording([.init(tMs: at4112, kind: .lowBatteryStop)])),
                       "Battery almost empty. Everything up to 41:12 is saved.")
    }

    func testAnInterruptedPauseIsNotThePlayersPause() {
        let state = CaptureRecordingState(phase: .paused, sessionTimeMs: at4112, savedThroughMs: at4112,
                                          interruption: CaptureInterruption(startMs: at4112, reason: .interruption))
        XCTAssertFalse(state.isPlayerPause, "the interruption sheet, not the Paused banner, explains this pause")
    }

    func testSaveStatusGapsAndTheInterruptionQuestionUseTheStoriesWords() {
        XCTAssertEqual(CaptureRecordingCopy.savedThrough(at4112), "Saved through 41:12")
        XCTAssertEqual(CaptureRecordingCopy.gap(SessionGap(startMs: at4112, endMs: at4131, reason: .interruption)),
                       "Gap 41:12–41:31 · interruption")
        XCTAssertEqual(CaptureRecordingCopy.gap(SessionGap(startMs: 7_000, endMs: 8_000, reason: .other)), "Gap 0:07–0:08 · not saved")
        XCTAssertEqual(CaptureRecordingCopy.gap(SessionGap(startMs: 7_000, endMs: 7_000, reason: .other)), "Stopped at 0:07 · not saved",
                       "a crash gap with no proven length is not drawn as an empty range")
        XCTAssertEqual(CaptureRecordingCopy.gap(SessionGap(startMs: 7_200, endMs: 7_900, reason: .other)), "Stopped at 0:07 · not saved",
                       "a gap shorter than the clock can show is not drawn as 0:07–0:07")
        let interruption = CaptureInterruption(startMs: at4112, reason: .interruption)
        XCTAssertEqual(CaptureRecordingCopy.interruptionTitle(interruption), "Recording stopped at 41:12\u{00A0}— Resume?")
        XCTAssertEqual(CaptureRecordingCopy.interruptionMessage(interruption),
                       "Something else needed the camera, such as a call, Siri or an alarm. Everything up to 41:12 is saved.")
        XCTAssertEqual(CaptureRecordingCopy.segmentSaved(at4112), "Segment saved · Saved through 41:12")
        XCTAssertEqual(CaptureRecordingCopy.interruptedAnnouncement(interruption),
                       "Recording interrupted. Everything up to 41:12 is saved.")
    }

    func testEveryGapReasonHasItsOwnWords() {
        let words = SessionGapReason.allCases.map(CaptureRecordingCopy.reason)
        XCTAssertEqual(Set(words).count, SessionGapReason.allCases.count)
        XCTAssertFalse(words.contains(where: \.isEmpty))
    }

    func testARecoveryReportNamesSegmentsAsThePlayerSeesThem() {
        XCTAssertEqual(CaptureRecordingCopy.segmentName("originals/segment-0.mp4"), "Part 1")
        XCTAssertEqual(CaptureRecordingCopy.segmentName("originals/segment-11.mp4"), "Part 12")
        XCTAssertEqual(CaptureRecordingCopy.segmentName("originals/clip.mp4"), "clip.mp4")
    }

    func testTheRoutePhaseFollowsTheEngineAndOnlyAnAcknowledgedSaveIsSaved() {
        XCTAssertEqual(CaptureRoutePhase(enginePhase: nil, isSaved: false), .framing)
        XCTAssertEqual(CaptureRoutePhase(enginePhase: .ready, isSaved: false), .framing)
        for phase: CapturePhase in [.recording, .pausing, .paused, .stopping] {
            XCTAssertEqual(CaptureRoutePhase(enginePhase: phase, isSaved: false), .recording, "\(phase)")
        }
        XCTAssertEqual(CaptureRoutePhase(enginePhase: .stopped, isSaved: false), .recording,
                       "a stop whose save failed stays where the failure is shown")
        XCTAssertEqual(CaptureRoutePhase(enginePhase: .stopped, isSaved: true), .saved)
    }

    func testWithoutASetupTheRouteOpensWithAValidSinglesDraft() {
        let draft = CaptureSetupChoices.defaultSinglesDraft
        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.title, "Singles match")
        XCTAssertEqual(draft.seed.players.map(\.displayName), ["Player A", "Player B"])
        XCTAssertEqual(draft.seed.format.setsToWin, .value2)
    }

    @MainActor
    func testAnnouncementsWaitForCurrentSpeech() {
        let announcement = PoliteAnnouncer.announcement("Segment saved · Saved through 0:04")
        XCTAssertEqual(String(announcement.characters), "Segment saved · Saved through 0:04")
        XCTAssertEqual(announcement.accessibilitySpeechAnnouncementPriority, .low)
    }
}

final class CaptureKeepAwakeTests: XCTestCase {
    @MainActor
    func testTheScreenStaysAwakeOnlyWhileRecording() {
        var applied: [Bool] = []
        let keepAwake = CaptureKeepAwake { applied.append($0) }
        keepAwake.update(for: .ready)
        keepAwake.update(for: .recording)
        keepAwake.update(for: .recording)
        keepAwake.update(for: .pausing)
        keepAwake.update(for: .paused)
        keepAwake.update(for: .recording)
        keepAwake.release()
        keepAwake.update(for: .stopped)
        XCTAssertEqual(applied, [true, false, true, false])
        XCTAssertFalse(keepAwake.isHoldingScreenAwake)
    }
}
