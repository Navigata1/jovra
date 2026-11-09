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

    /// "REC 12:46" / "Paused 12:46" as drawn.
    static func pillText(_ state: CaptureRecordingState) -> String {
        state.isPaused ? String(localized: "Paused \(clock(state.recordedMs))", table: "Capture")
            : String(localized: "REC \(clock(state.recordedMs))", table: "Capture")
    }

    /// "Recording, 12 minutes, 46 seconds" for VoiceOver (screen spec S06, Accessibility).
    static func pillAccessibilityLabel(_ state: CaptureRecordingState) -> String {
        state.isPaused ? String(localized: "Paused, \(spoken(state.recordedMs)) recorded", table: "Capture")
            : String(localized: "Recording, \(spoken(state.recordedMs))", table: "Capture")
    }

    static let savedOnDevice = String(localized: "Video saved on this iPhone", table: "Capture")
    static let savingFirstSeconds = String(localized: "Saving the first seconds on this iPhone", table: "Capture")

    static func savedThrough(_ milliseconds: Int) -> String {
        String(localized: "Saved through \(clock(milliseconds))", table: "Capture")
    }

    static let pausedBanner = String(localized: "Paused · Not recording", table: "Capture")

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
