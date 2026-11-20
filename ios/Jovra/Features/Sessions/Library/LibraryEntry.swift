import Foundation
import JovraCore

/// One session as the library shows it: the stored document's four independent facets (original, analysis,
/// review, archive) plus what the card adds: duration, the final score and the bytes it uses on this iPhone.
/// Built from the session document itself, never from the disposable index.
struct LibraryEntry: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var createdAt: Date?
    var kind: SessionDocumentSessionKind
    var isDoubles: Bool
    var playerNames: [String]
    var notes: String?
    var isSample: Bool
    /// The original video's state. A document without one (the shipped sample library) is derived from its
    /// recording, the same rule the store applies when it restores from Trash.
    var original: SessionOriginalStateState?
    var analysis: SessionAnalysisState
    var review: SessionReviewState
    var archive: SessionArchiveStateState
    var archiveCopy: SessionArchiveStateCopy?
    var durationMs: Int?
    /// The final or current score from the scoring engine ("6-4 6-3"); nil without scored points.
    var scoreline: String?
    /// Bytes on this iPhone; nil when the folder could not be measured.
    var bytes: SessionBytes?
    var exportCount: Int
    /// The first recording segment, relative to the session folder, for the card's poster frame.
    var posterPath: String?

    init(document: SessionDocument, bytes: SessionBytes?) {
        id = document.id
        title = document.title
        createdAt = ISO8601DateFormatter().date(from: document.createdAt)
        kind = document.sessionKind
        isDoubles = (document.sides?.A.count ?? 1) > 1
        playerNames = document.players.map(\.displayName)
        notes = document.notes
        isSample = document.sample != nil
        original = document.original?.state ?? Self.derivedOriginal(document)
        analysis = document.analysis?.state ?? .notRequested
        review = document.review?.state ?? .notStarted
        archive = document.archive.state
        archiveCopy = document.archive.copy
        let segments = document.recording.segments
        durationMs = document.recording.durationMs ?? segments.map { $0.startMs + $0.durationMs }.max()
        scoreline = Self.scoreline(document)
        self.bytes = bytes
        exportCount = document.exports?.count ?? 0
        posterPath = document.recording.mediaAvailable ? segments.min { $0.index < $1.index }?.file.path : nil
    }

    var isMatch: Bool { LibraryFilter.matches.includes(kind) }

    private static func derivedOriginal(_ document: SessionDocument) -> SessionOriginalStateState? {
        let recording = document.recording
        if recording.mediaAvailable && !recording.segments.isEmpty {
            return recording.gaps.isEmpty ? .saved : .savedWithGaps
        }
        if let media = document.sample?.mediaIds, !media.isEmpty { return .saved }
        return document.storage.originals == .archivedOnly ? .archiveOnly : nil
    }

    private static func scoreline(_ document: SessionDocument) -> String? {
        guard let match = document.match, !match.log.isEmpty,
              let timeline = try? ScoringEngine.fold(ScoringInput(session: document)) else { return nil }
        return timeline.match.scoreline.value
    }
}

/// Bytes a session uses on this iPhone, by folder: the original video, cached proxies and frames, exports.
struct SessionBytes: Equatable, Sendable {
    var originals: Int64
    var cache: Int64
    var exports: Int64
    var total: Int64 { originals + cache + exports }
}

/// What one library read returns: the sessions to list, those in Trash, and the documents set aside in
/// quarantine because they could not be read.
struct LibrarySnapshot: Equatable, Sendable {
    var entries: [LibraryEntry]
    var trashed: [LibraryEntry]
    var quarantined: [QuarantinedSession]
}
