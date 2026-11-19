import Foundation
import JovraCore

/// One row of the stage timeline (screen 7): what the player reads for a stage, decided from the
/// session's original facet and its processing job. Pure, so it is unit-tested without the UI.
struct StageRow: Equatable, Identifiable {
    enum Indicator: Hashable {
        case done
        case active(Double)
        case paused(Double)
        case waiting
        case failed
        case unavailable
    }

    var id: String
    var title: String
    var detail: String
    var indicator: Indicator
    /// "100%", "62%" or an em dash when there is nothing to measure.
    var trailing: String
    /// The state in words, for VoiceOver (meaning is never carried by the indicator alone).
    var status: String
}

enum ProcessingStagePresentation {
    static func rows(original: SessionOriginalState?, recordingMode: SessionRecordingMode?, job: ProcessingJob?,
                     hold: ProcessingHold?, locale: Locale = .autoupdatingCurrent) -> [StageRow] {
        [saved(original, mode: recordingMode, locale: locale),
         prepareReplay(job?.prepareReplay, hold: hold, locale: locale),
         analyze(job?.analyze, hold: hold, locale: locale),
         backup(job?.backup)]
    }

    /// The video can be watched as soon as the original is saved, whatever analysis is doing.
    static func isViewable(_ original: SessionOriginalState?) -> Bool {
        guard let state = original?.state else { return false }
        return [.saved, .savedWithGaps, .partial].contains(state)
    }

    // MARK: Rows

    private static func saved(_ original: SessionOriginalState?, mode: SessionRecordingMode?, locale: Locale) -> StageRow {
        let title = String(localized: "Saved locally", table: "Processing")
        let doneDetail = mode == .import
            ? String(localized: "Video copied to your device", table: "Processing")
            : String(localized: "Recording saved on this iPhone", table: "Processing")
        switch original?.state {
        case .saved?:
            return row("saved", title, doneDetail, .done, percent(1, locale), done)
        case .savedWithGaps?:
            return row("saved", title, String(localized: "Saved with gaps where recording stopped", table: "Processing"),
                       .done, percent(1, locale), done)
        case .partial?:
            return row("saved", title, String(localized: "Partly saved. Every saved part plays.", table: "Processing"),
                       .done, percent(1, locale), done)
        case .recording?, .importing?, .recovering?:
            return row("saved", title, String(localized: "Saving the video to this iPhone…", table: "Processing"),
                       .active(0), dash, inProgress)
        default:
            return row("saved", title, String(localized: "The original is not on this iPhone", table: "Processing"),
                       .unavailable, dash, unavailableWord)
        }
    }

    private static func prepareReplay(_ stage: ProcessingStageState?, hold: ProcessingHold?, locale: Locale) -> StageRow {
        let title = String(localized: "Preparing replay", table: "Processing")
        let working = String(localized: "Checking video and audio for replay", table: "Processing")
        guard let stage else { return row("prepareReplay", title, working, .waiting, dash, waitingWord) }
        switch stage.status {
        case .done:
            return row("prepareReplay", title, String(localized: "Ready to replay", table: "Processing"), .done, percent(1, locale), done)
        case .running:
            return row("prepareReplay", title, working, .active(stage.progress), percent(stage.progress, locale), inProgress)
        case .failed:
            return row("prepareReplay", title, String(localized: "Replay check failed. The original is unchanged.", table: "Processing"),
                       .failed, dash, failedWord)
        case .queued, .blocked, .paused:
            return row("prepareReplay", title, holdDetail(hold) ?? working, .waiting, dash, waitingWord)
        case .unavailable:
            return row("prepareReplay", title, reasonDetail(stage.reason), .unavailable, dash, unavailableWord)
        }
    }

    private static func analyze(_ stage: ProcessingStageState?, hold: ProcessingHold?, locale: Locale) -> StageRow {
        let title = String(localized: "Analyzing points", table: "Processing")
        let working = String(localized: "Detecting shots, rallies and key moments", table: "Processing")
        guard let stage else { return row("analyze", title, working, .waiting, dash, waitingWord) }
        switch stage.status {
        case .done:
            return row("analyze", title, String(localized: "Analysis finished", table: "Processing"), .done, percent(1, locale), done)
        case .running:
            return row("analyze", title, working, .active(stage.progress), percent(stage.progress, locale), inProgress)
        case .paused:
            return row("analyze", title, String(localized: "Paused. Resume when you're ready.", table: "Processing"),
                       .paused(stage.progress), percent(stage.progress, locale), String(localized: "Paused", table: "Processing"))
        case .failed:
            return row("analyze", title, String(localized: "Analysis stopped. Your video is safe and still plays.", table: "Processing"),
                       .failed, stage.progress > 0 ? percent(stage.progress, locale) : dash, failedWord)
        case .unavailable:
            return row("analyze", title, reasonDetail(stage.reason), .unavailable, dash, unavailableWord)
        case .queued, .blocked:
            let detail = holdDetail(hold) ?? (stage.progress > 0
                ? String(localized: "Continues from where it stopped", table: "Processing")
                : String(localized: "Starts when replay is ready", table: "Processing"))
            return row("analyze", title, detail, stage.progress > 0 ? .paused(stage.progress) : .waiting,
                       stage.progress > 0 ? percent(stage.progress, locale) : dash, waitingWord)
        }
    }

    private static func backup(_ stage: ProcessingStageState?) -> StageRow {
        let title = String(localized: "Backing up", table: "Processing")
        guard let stage else {
            return row("backup", title, String(localized: "Awaiting Google Drive setup", table: "Processing"), .waiting, dash, waitingWord)
        }
        switch stage.status {
        case .done:
            return row("backup", title, String(localized: "Backed up to your Google Drive archive", table: "Processing"), .done, dash, done)
        case .failed:
            return row("backup", title, String(localized: "Backup failed. The video stays on this iPhone.", table: "Processing"), .failed, dash, failedWord)
        case .blocked, .unavailable:
            return row("backup", title, reasonDetail(stage.reason), .waiting, dash, waitingWord)
        case .queued, .running, .paused:
            return row("backup", title, String(localized: "Queued for your Google Drive archive", table: "Processing"), .waiting, dash, waitingWord)
        }
    }

    // MARK: Words

    static func reasonDetail(_ reason: ProcessingReason?) -> String {
        switch reason {
        case .noAnalyzerRegistered?:
            String(localized: "Unavailable: no automatic analysis is installed in this version yet. Replay and manual scoring work as usual.", table: "Processing")
        case .analyzerFailed?:
            String(localized: "Analysis stopped. Your video is safe and still plays.", table: "Processing")
        case .mediaUnreadable?:
            String(localized: "JOVRA could not read this video for replay.", table: "Processing")
        case .originalMissing?:
            String(localized: "The original is not on this iPhone", table: "Processing")
        case .awaitingArchiveSetup?:
            String(localized: "Awaiting Google Drive setup", table: "Processing")
        case .waitingForWiFi?:
            String(localized: "Backup waits for Wi-Fi", table: "Processing")
        case nil:
            String(localized: "Waiting", table: "Processing")
        }
    }

    static func holdDetail(_ hold: ProcessingHold?) -> String? {
        switch hold {
        case .captureActive?: String(localized: "Waits while you record", table: "Processing")
        case .tooWarm?: String(localized: "Waiting for your iPhone to cool down", table: "Processing")
        case .lowPower?: String(localized: "Waiting for a charger while Low Power Mode is on", table: "Processing")
        case nil: nil
        }
    }

    private static var done: String { String(localized: "Done", table: "Processing") }
    private static var inProgress: String { String(localized: "In progress", table: "Processing") }
    private static var waitingWord: String { String(localized: "Waiting", table: "Processing") }
    private static var failedWord: String { String(localized: "Failed", table: "Processing") }
    private static var unavailableWord: String { String(localized: "Unavailable", table: "Processing") }
    private static let dash = "—"

    private static func percent(_ fraction: Double, _ locale: Locale) -> String {
        JovraFormat.percent(Int((fraction * 100).rounded(.down)), locale: locale)
    }

    private static func row(_ id: String, _ title: String, _ detail: String, _ indicator: StageRow.Indicator,
                            _ trailing: String, _ status: String) -> StageRow {
        StageRow(id: id, title: title, detail: detail, indicator: indicator, trailing: trailing, status: status)
    }
}
