import Foundation
import JovraCore
import JovraMedia

/// What the recording screen knows, in milliseconds of session time, read only from the engine's
/// confirmed status (never a guess). Session time keeps running through gaps, so the REC timer
/// subtracts them: it counts recorded video, while "Saved through" and every gap use the session timeline.
struct CaptureRecordingState: Equatable {
    var phase: CapturePhase
    var sessionTimeMs: Int
    var savedThroughMs: Int?
    var gaps: [SessionGap]
    var interruption: CaptureInterruption?

    init(phase: CapturePhase, sessionTimeMs: Int, savedThroughMs: Int?, gaps: [SessionGap] = [],
         interruption: CaptureInterruption? = nil) {
        self.phase = phase; self.sessionTimeMs = sessionTimeMs; self.savedThroughMs = savedThroughMs
        self.gaps = gaps; self.interruption = interruption
    }

    init(_ status: CaptureStatus) {
        self.init(phase: status.phase, sessionTimeMs: status.recordingTime.map(Self.milliseconds) ?? 0,
                  savedThroughMs: status.savedThrough.map(Self.milliseconds), gaps: status.gaps,
                  interruption: status.interruption)
    }

    /// Recorded video: session time minus every recorded gap.
    var recordedMs: Int {
        max(0, sessionTimeMs - gaps.reduce(0) { $0 + max(0, $1.endMs - $1.startMs) })
    }

    /// What the status pill draws. The red dot belongs to `recording` alone: a stopping or stopped engine
    /// is never shown as recording.
    enum Pill: Equatable { case recording, paused, stopped }

    var pill: Pill {
        switch phase {
        case .idle, .ready, .recording: .recording
        case .pausing, .paused: .paused
        case .stopping, .stopped: .stopped
        }
    }

    /// Why this screen is still up after the engine stopped, or nil while recording, paused, or stopping
    /// and saving. A failure the coordinator recorded stands while its retry runs. Without one, a stopped
    /// engine with nothing in flight and no acknowledged save can only be a save that did not finish.
    func stopFailure(isWorking: Bool, recorded: CaptureStopFailure?) -> CaptureStopFailure? {
        guard phase == .stopped else { return nil }
        return recorded ?? (isWorking ? nil : .saveFailed)
    }

    var isPaused: Bool { phase == .paused || phase == .pausing }
    var isRecording: Bool { phase == .recording }
    /// Paused by the player rather than by a call, the camera or heat.
    var isPlayerPause: Bool { isPaused && interruption == nil }

    private static func milliseconds(_ time: JovraCore.MediaTime) -> Int {
        guard time.timescale > 0 else { return 0 }
        return Int(time.value * 1000 / Int64(time.timescale))
    }
}

/// Every word the recording phase says. One key per sentence, with interpolation, so a translation never
/// has to rebuild a sentence from fragments.
enum CaptureRecordingCopy {
    static func clock(_ milliseconds: Int) -> String { JovraFormat.clock(seconds: Double(milliseconds) / 1000) }

    static func spoken(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1000)
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// "REC 12:46" / "Paused 12:46" / "Stopped 12:46" as drawn.
    static func pillText(_ state: CaptureRecordingState) -> String {
        switch state.pill {
        case .recording: String(localized: "REC \(clock(state.recordedMs))", table: "Capture")
        case .paused: String(localized: "Paused \(clock(state.recordedMs))", table: "Capture")
        case .stopped: String(localized: "Stopped \(clock(state.recordedMs))", table: "Capture")
        }
    }

    /// "Recording, 12 minutes, 46 seconds" for VoiceOver (screen spec S06, Accessibility).
    static func pillAccessibilityLabel(_ state: CaptureRecordingState) -> String {
        switch state.pill {
        case .recording: String(localized: "Recording, \(spoken(state.recordedMs))", table: "Capture")
        case .paused: String(localized: "Paused, \(spoken(state.recordedMs)) recorded", table: "Capture")
        case .stopped: String(localized: "Stopped, \(spoken(state.recordedMs)) recorded", table: "Capture")
        }
    }

    static let savedOnDevice = String(localized: "Video saved on this iPhone", table: "Capture")
    static let savingFirstSeconds = String(localized: "Saving the first seconds on this iPhone", table: "Capture")

    static func savedThrough(_ milliseconds: Int) -> String {
        String(localized: "Saved through \(clock(milliseconds))", table: "Capture")
    }

    static let pausedBanner = String(localized: "Paused · Not recording", table: "Capture")
    static let stoppedBanner = String(localized: "Stopped · Not recording", table: "Capture")

    // MARK: A stop that did not end as a saved recording

    /// What failed (screen spec, Error state: what failed, what is still safe, and a way on).
    static func stopFailureTitle(_ failure: CaptureStopFailure) -> String {
        switch failure {
        case .saveFailed: String(localized: "JOVRA could not finish saving this recording", table: "Capture")
        case .deleteFailed: String(localized: "This recording could not be deleted", table: "Capture")
        }
    }

    /// What is still on this iPhone. `savedThroughMs` is the journal's confirmed time, never a guess, and
    /// "will look for it" is what the next launch's recovery scan does; it is not a promise of the result.
    static func stopFailureMessage(_ failure: CaptureStopFailure, savedThroughMs: Int?) -> String {
        switch failure {
        case .saveFailed:
            guard let saved = savedThroughMs, saved > 0 else {
                return String(localized: "Nothing from this recording was confirmed as saved on this iPhone.", table: "Capture")
            }
            return String(localized: "Video up to \(clock(saved)) is on this iPhone. JOVRA will look for it the next time it opens.", table: "Capture")
        case .deleteFailed:
            return String(localized: "It is still on this iPhone. Try deleting it again.", table: "Capture")
        }
    }

    /// Spoken politely when the stop lands in the failed state.
    static func stopFailureAnnouncement(_ failure: CaptureStopFailure) -> String {
        switch failure {
        case .saveFailed: String(localized: "Recording stopped. JOVRA could not finish saving it.", table: "Capture")
        case .deleteFailed: String(localized: "Recording stopped. It could not be deleted and is still on this iPhone.", table: "Capture")
        }
    }

    /// Why the engine stopped by itself, read from the capture events stored with the recording
    /// (screen spec S06, Low storage and Low battery); nil when the player stopped it.
    static func automaticStopReason(_ recording: SessionRecording) -> String? {
        guard let kind = recording.captureEvents?.last(where: { $0.kind == .lowStorageStop || $0.kind == .lowBatteryStop })?.kind else { return nil }
        let end = clock(recording.durationMs ?? recording.segments.map { $0.startMs + $0.durationMs }.max() ?? 0)
        return kind == .lowStorageStop
            ? String(localized: "Storage full. Everything up to \(end) is saved.", table: "Capture")
            : String(localized: "Battery almost empty. Everything up to \(end) is saved.", table: "Capture")
    }

    static func reason(_ reason: SessionGapReason) -> String {
        switch reason {
        case .interruption: String(localized: "interruption", table: "Capture", comment: "Gap reason: a call, Siri, an alarm or another app took the camera")
        case .thermal: String(localized: "phone too hot", table: "Capture", comment: "Gap reason")
        case .backgrounded: String(localized: "JOVRA left the screen", table: "Capture", comment: "Gap reason")
        case .lowStorage: String(localized: "storage full", table: "Capture", comment: "Gap reason")
        case .cameraError: String(localized: "camera stopped", table: "Capture", comment: "Gap reason")
        case .userPaused: String(localized: "paused", table: "Capture", comment: "Gap reason")
        case .other: String(localized: "not saved", table: "Capture", comment: "Gap reason: the app stopped before this stretch was saved")
        }
    }

    /// "Gap 41:12–41:31 · interruption" (user story 96).
    /// A crash gap can have no proven length (the journal shows only where saving stopped), or one shorter
    /// than the clock can show, so it reads "Stopped at 0:07 · not saved" rather than an empty range.
    static func gap(_ gap: SessionGap) -> String {
        let start = clock(gap.startMs), end = clock(gap.endMs)
        guard gap.endMs > gap.startMs, start != end else {
            return String(localized: "Stopped at \(start) · \(reason(gap.reason))", table: "Capture")
        }
        return String(localized: "Gap \(start)–\(end) · \(reason(gap.reason))", table: "Capture")
    }

    /// "Recording stopped at 41:12 — Resume?" (user story 93). A no-break space keeps the dash with the
    /// time, so the question never starts a line with a dash.
    static func interruptionTitle(_ interruption: CaptureInterruption) -> String {
        String(localized: "Recording stopped at \(clock(interruption.startMs))\u{00A0}— Resume?", table: "Capture")
    }

    static func interruptionMessage(_ interruption: CaptureInterruption) -> String {
        let time = clock(interruption.startMs)
        return switch interruption.reason {
        case .thermal: String(localized: "Your phone got too hot. Everything up to \(time) is saved.", table: "Capture")
        case .backgrounded: String(localized: "JOVRA left the screen, so the camera stopped. Everything up to \(time) is saved.", table: "Capture")
        case .lowStorage: String(localized: "This iPhone ran out of space. Everything up to \(time) is saved.", table: "Capture")
        case .cameraError: String(localized: "The camera stopped working. Everything up to \(time) is saved.", table: "Capture")
        case .interruption, .userPaused, .other:
            String(localized: "Something else needed the camera, such as a call, Siri or an alarm. Everything up to \(time) is saved.", table: "Capture")
        }
    }

    /// The toast after a segment closes on an interruption (user story 97).
    static func segmentSaved(_ milliseconds: Int) -> String {
        String(localized: "Segment saved · Saved through \(clock(milliseconds))", table: "Capture")
    }

    /// Spoken politely when an interruption stops the camera.
    static func interruptedAnnouncement(_ interruption: CaptureInterruption) -> String {
        String(localized: "Recording interrupted. Everything up to \(clock(interruption.startMs)) is saved.", table: "Capture")
    }

    /// A recovery report names "originals/segment-0.mp4"; the player reads "Part 1".
    static func segmentName(_ path: String) -> String {
        let file = (path as NSString).lastPathComponent
        guard file.hasPrefix("segment-"), let index = Int(file.dropFirst("segment-".count).prefix { $0.isNumber }) else { return file }
        return String(localized: "Part \(index + 1)", table: "Capture")
    }

    static let savedAnnouncement = String(localized: "Recording stopped. Video saved on this iPhone.", table: "Capture")
    static let deletedAnnouncement = String(localized: "Recording deleted from this iPhone.", table: "Capture")
}
