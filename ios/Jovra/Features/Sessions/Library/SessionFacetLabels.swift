import Foundation
import JovraCore

/// One facet's status: its axis, the words, the tone and the symbol. Tone is carried by the symbol and the
/// words; colour only reinforces it (CLAUDE.md rule 8).
struct FacetLabel: Equatable, Sendable {
    enum Axis: CaseIterable, Sendable { case original, analysis, review, archive }

    var axis: Axis
    var text: String
    var tone: StatusPill.Tone
    var symbol: String

    /// The axis name VoiceOver reads before the status ("Video: On device").
    var axisName: String {
        switch axis {
        case .original: String(localized: "Video", table: "Sessions.Library", comment: "Facet axis: the original video")
        case .analysis: String(localized: "Analysis", table: "Sessions.Library", comment: "Facet axis")
        case .review: String(localized: "Review", table: "Sessions.Library", comment: "Facet axis")
        case .archive: String(localized: "Backup", table: "Sessions.Library", comment: "Facet axis: the Google Drive archive")
        }
    }
}

/// The four independent status labels of a session (story 123): where the original video is, what analysis
/// did, whether points need review, and what the Google Drive archive is doing. One stuck stage never hides
/// the others, so every axis is computed on its own.
struct SessionFacetLabels: Equatable, Sendable {
    let original: FacetLabel
    let analysis: FacetLabel
    let review: FacetLabel
    let archive: FacetLabel
    /// Story 124 and D7: the original exists on this iPhone and nowhere else (no verified backup of the
    /// original itself yet).
    let isOnlyOnThisIPhone: Bool

    var all: [FacetLabel] { [original, analysis, review, archive] }

    init(_ entry: LibraryEntry) {
        original = Self.original(entry.original)
        analysis = Self.analysis(entry.analysis)
        review = Self.review(entry.review)
        archive = Self.archive(entry.archive)
        let onDevice: Set<SessionOriginalStateState> = [.recording, .recovering, .saved, .savedWithGaps, .partial, .importing]
        let backedUpOriginal = entry.archive == .backedUp && entry.archiveCopy != .rallyOnlyCopy
        isOnlyOnThisIPhone = entry.original.map(onDevice.contains) == true && !backedUpOriginal
    }

    static var onlyOnThisIPhone: String {
        String(localized: "Only on this iPhone", table: "Sessions.Library", comment: "A session whose original has no second copy")
    }

    private static func original(_ state: SessionOriginalStateState?) -> FacetLabel {
        func label(_ text: String, _ tone: StatusPill.Tone, _ symbol: String) -> FacetLabel {
            FacetLabel(axis: .original, text: text, tone: tone, symbol: symbol)
        }
        switch state {
        case .recording: return label(String(localized: "Not finalized", table: "Sessions.Library"), .neutral, "record.circle")
        case .recovering: return label(String(localized: "Recovery in progress", table: "Sessions.Library"), .neutral, "arrow.clockwise.circle")
        case .saved: return label(String(localized: "On device", table: "Sessions.Library"), .positive, "checkmark.circle.fill")
        case .savedWithGaps: return label(String(localized: "Saved with gaps", table: "Sessions.Library"), .neutral, "film.stack")
        case .partial: return label(String(localized: "Partially saved", table: "Sessions.Library"), .attention, "exclamationmark.circle.fill")
        case .importing: return label(String(localized: "Importing", table: "Sessions.Library"), .neutral, "square.and.arrow.down")
        case .archiveOnly: return label(String(localized: "In Google Drive only", table: "Sessions.Library"), .neutral, "cloud")
        case .missing: return label(String(localized: "Video missing", table: "Sessions.Library"), .attention, "exclamationmark.triangle.fill")
        case .trashed: return label(String(localized: "In Trash", table: "Sessions.Library"), .neutral, "trash")
        case nil: return label(String(localized: "No video", table: "Sessions.Library"), .neutral, "video.slash")
        }
    }

    private static func analysis(_ state: SessionAnalysisState) -> FacetLabel {
        func label(_ text: String, _ tone: StatusPill.Tone, _ symbol: String) -> FacetLabel {
            FacetLabel(axis: .analysis, text: text, tone: tone, symbol: symbol)
        }
        switch state {
        case .notRequested: return label(String(localized: "Not analyzed", table: "Sessions.Library"), .neutral, "waveform.path")
        case .queued: return label(String(localized: "Analysis queued", table: "Sessions.Library"), .neutral, "clock")
        case .running: return label(String(localized: "Analyzing", table: "Sessions.Library"), .neutral, "waveform.path.ecg")
        case .paused: return label(String(localized: "Analysis paused", table: "Sessions.Library"), .neutral, "pause.circle")
        case .done: return label(String(localized: "Analysis ready", table: "Sessions.Library"), .positive, "checkmark.circle.fill")
        case .partial: return label(String(localized: "Partly analyzed", table: "Sessions.Library"), .neutral, "circle.lefthalf.filled")
        case .failed: return label(String(localized: "Analysis failed", table: "Sessions.Library"), .attention, "exclamationmark.circle.fill")
        case .unavailable: return label(String(localized: "Analysis unavailable", table: "Sessions.Library"), .neutral, "slash.circle")
        }
    }

    private static func review(_ state: SessionReviewState) -> FacetLabel {
        switch state {
        case .notStarted:
            FacetLabel(axis: .review, text: String(localized: "Not reviewed", table: "Sessions.Library"), tone: .neutral, symbol: "circle.dashed")
        case .inProgress:
            FacetLabel(axis: .review, text: String(localized: "Needs review", table: "Sessions.Library"), tone: .attention, symbol: "exclamationmark.circle.fill")
        case .complete:
            FacetLabel(axis: .review, text: String(localized: "Reviewed", table: "Sessions.Library"), tone: .positive, symbol: "checkmark.circle.fill")
        }
    }

    private static func archive(_ state: SessionArchiveStateState) -> FacetLabel {
        func label(_ text: String, _ tone: StatusPill.Tone, _ symbol: String) -> FacetLabel {
            FacetLabel(axis: .archive, text: text, tone: tone, symbol: symbol)
        }
        switch state {
        case .localOnly: return label(String(localized: "Not backed up", table: "Sessions.Library"), .neutral, "icloud.slash")
        case .awaitingSetup: return label(String(localized: "Backup not set up", table: "Sessions.Library"), .neutral, "icloud.slash")
        case .queued: return label(String(localized: "Queued for backup", table: "Sessions.Library"), .neutral, "clock")
        case .waitingForWiFi: return label(String(localized: "Waiting for Wi-Fi", table: "Sessions.Library"), .neutral, "wifi")
        case .hashing: return label(String(localized: "Preparing backup", table: "Sessions.Library"), .neutral, "icloud")
        case .uploading: return label(String(localized: "Backing up", table: "Sessions.Library"), .neutral, "icloud.and.arrow.up")
        case .verifying: return label(String(localized: "Checking backup", table: "Sessions.Library"), .neutral, "checkmark.icloud")
        case .backedUp: return label(String(localized: "Backed up", table: "Sessions.Library"), .positive, "checkmark.icloud.fill")
        case .failed: return label(String(localized: "Retry backup", table: "Sessions.Library"), .attention, "exclamationmark.icloud.fill")
        case .needsReconnect: return label(String(localized: "Needs reconnect", table: "Sessions.Library"), .attention, "exclamationmark.icloud.fill")
        case .quotaBlocked: return label(String(localized: "Google Drive is full", table: "Sessions.Library"), .attention, "exclamationmark.icloud.fill")
        }
    }
}

/// Everything a SessionCard prints, computed from the entry: the metadata line, the score, the bytes on this
/// iPhone and the one-sentence VoiceOver label.
struct SessionCardPresentation: Equatable, Sendable {
    let title: String
    let isSample: Bool
    let scoreline: String?
    let metadata: String
    let storage: String?
    let facets: SessionFacetLabels
    let accessibilityLabel: String

    init(_ entry: LibraryEntry, calendar: Calendar = .autoupdatingCurrent, now: Date = .now,
         locale: Locale = .autoupdatingCurrent) {
        title = entry.title
        isSample = entry.isSample
        // The engine writes hyphens; the card sets scores with en dashes ("6–4 6–3", screen spec S08).
        scoreline = entry.scoreline.map { $0.replacingOccurrences(of: "-", with: "\u{2013}") }
        var parts: [String] = []
        if let date = entry.createdAt { parts.append(Self.date(date, calendar: calendar, now: now, locale: locale)) }
        if let ms = entry.durationMs, ms > 0 {
            // Under a minute the compact label would say "0 min"; a short recording states its seconds.
            parts.append(ms < 60_000 ? String(localized: "\(ms / 1000) sec", table: "Sessions.Library", comment: "Duration under a minute")
                                     : DurationLabel.compact(seconds: Double(ms) / 1000))
        }
        parts.append(Self.kind(entry))
        metadata = parts.joined(separator: " · ")
        // A session with nothing stored here (sample, archived-only) states no size rather than "Zero KB".
        storage = entry.bytes.flatMap { bytes in
            bytes.total <= 0 ? nil : String(localized: "\(Self.bytes(bytes.total, locale: locale)) on this iPhone", table: "Sessions.Library",
                          comment: "Storage a session uses, e.g. “1.2 GB on this iPhone”")
        }
        facets = SessionFacetLabels(entry)
        var sentence = [entry.title]
        if entry.isSample { sentence.append(String(localized: "Sample", table: "Sessions.Library")) }
        if let scoreline { sentence.append(scoreline) }
        var spoken = sentence.joined(separator: ", ") + ", " + metadata + "."
        for facet in facets.all { spoken += " \(facet.axisName): \(facet.text)." }
        if facets.isOnlyOnThisIPhone { spoken += " " + SessionFacetLabels.onlyOnThisIPhone + "." }
        if let storage { spoken += " " + storage }
        accessibilityLabel = spoken
    }

    static func bytes(_ count: Int64, locale: Locale = .autoupdatingCurrent) -> String {
        count.formatted(.byteCount(style: .file).locale(locale))
    }

    private static func date(_ date: Date, calendar: Calendar, now: Date, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                     timeZone: calendar.timeZone).month(.abbreviated).day()
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) { style = style.year() }
        return date.formatted(style)
    }

    private static func kind(_ entry: LibraryEntry) -> String {
        switch entry.kind {
        case .match: entry.isDoubles ? String(localized: "Doubles", table: "Sessions.Library") : String(localized: "Singles", table: "Sessions.Library")
        case .tiebreakOnly: String(localized: "Tiebreak", table: "Sessions.Library")
        case .practiceSet: String(localized: "Practice set", table: "Sessions.Library")
        case .servePractice: String(localized: "Serve practice", table: "Sessions.Library")
        case .strokePractice: String(localized: "Stroke practice", table: "Sessions.Library")
        case .rally: String(localized: "Rally", table: "Sessions.Library")
        case .lesson: String(localized: "Lesson", table: "Sessions.Library")
        case .drill: String(localized: "Drill", table: "Sessions.Library")
        }
    }
}
