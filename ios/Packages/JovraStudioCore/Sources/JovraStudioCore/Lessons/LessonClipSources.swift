import Foundation
import JovraCore

/// The originals each lesson clip was cut from, by SHA-256: `lessons/<lessonId>.clip-sources.json` beside the lesson.
/// A local app document (like `studio.json`), not a shared contract: `jovra.lesson/1` has no field for a hash, and the
/// hash is what lets "Find the video" tell the same file from one that only has the same name.
public struct LessonClipSources: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = "jovra.lesson-clip-sources/1"
    static let suffix = ".clip-sources.json"

    public struct File: Codable, Equatable, Sendable {
        /// The original's file name, for the repair sheet ("segment-000.mov"). Never used to match.
        public var name: String
        public var sha256: String
        /// Full segment coordinates. Absent in older receipts, which cannot prove a repaired mapping.
        public var startUs: Int?
        public var endUs: Int?

        var hasTimeline: Bool {
            guard let startUs, let endUs else { return false }
            return startUs >= 0 && startUs < endUs
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var clipId: String
        /// The session originally verified. Repair preserves this original receipt.
        public var sessionId: String
        public var window: StudioIntervalUs?
        /// Every original the clip's range covers.
        public var files: [File]
    }

    public var schemaVersion: String
    public var lessonId: String
    public var sample: Bool
    public var clips: [Entry]

    init(lessonId: String, sample: Bool) {
        schemaVersion = Self.currentSchemaVersion
        self.lessonId = lessonId
        self.sample = sample
        clips = []
    }

    static func fileName(_ lessonId: String) -> String { "\(lessonId)\(suffix)" }

    public func entry(_ clipId: String) -> Entry? { clips.first { $0.clipId == clipId } }

    mutating func insert(_ entry: Entry) throws {
        guard self.entry(entry.clipId) == nil else { throw LessonRejection(.duplicateId, "duplicate clip receipt") }
        clips.append(entry)
        clips.sort { $0.clipId < $1.clipId }
    }

    static func decode(_ data: Data) throws -> LessonClipSources {
        let sources = try ContractCodec.decode(LessonClipSources.self, from: data)
        guard sources.schemaVersion == currentSchemaVersion else {
            throw StudioProjectStoreError.unsupportedVersion(sources.schemaVersion)
        }
        return sources
    }

    func encoded() throws -> Data { try CanonicalJSON.encode(self) }

    /// Verify continuous coverage in the session clock and hash the original files in timeline order.
    static func verify(_ document: SessionDocument, range: StudioIntervalUs,
                       with verifier: LessonMediaVerifier) async throws -> [File] {
        guard range.startUs >= 0, range.startUs < range.endUs else { throw LessonJournalError.badRange }
        let limit = Int.max / 1_000
        if let duration = document.recording.durationMs {
            guard duration > 0, duration <= limit, range.endUs <= duration * 1_000 else {
                throw LessonJournalError.badRange
            }
        }
        guard document.recording.mediaAvailable, document.original?.state != .trashed else {
            throw LessonJournalError.noVideo(document.id)
        }
        for gap in document.recording.gaps {
            guard gap.startMs >= 0, gap.startMs <= gap.endMs, gap.endMs <= limit else {
                throw LessonJournalError.badRange
            }
            if gap.startMs < gap.endMs, gap.startMs * 1_000 < range.endUs, range.startUs < gap.endMs * 1_000 {
                throw LessonJournalError.noVideo(document.id)
            }
        }
        let segments = document.recording.segments.sorted { $0.startMs < $1.startMs }
        var covered = range.startUs
        var spans: [(segment: SessionSegment, startUs: Int, endUs: Int)] = []
        for segment in segments {
            let start = segment.startMs, duration = segment.durationMs
            guard start >= 0, start <= limit, duration > 0, duration <= limit - start else {
                throw LessonJournalError.badRange
            }
            let lo = start * 1_000, hi = (start + duration) * 1_000
            guard lo < range.endUs, range.startUs < hi else { continue }
            guard segment.finalized, hi > covered, spans.isEmpty ? lo <= covered : lo == covered else {
                throw LessonJournalError.noVideo(document.id)
            }
            spans.append((segment, lo, hi))
            covered = min(hi, range.endUs)
        }
        guard covered == range.endUs else { throw LessonJournalError.noVideo(document.id) }
        try Task.checkCancellation()
        let hashes = try await verifier(document.id, spans.map(\.segment))
        try Task.checkCancellation()
        guard hashes.count == spans.count else { throw LessonJournalError.noVideo(document.id) }
        return try zip(spans, hashes).map { span, hash in
            let file = span.segment.file
            guard hash.utf8.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  file.sha256 == nil || file.sha256 == hash else { throw LessonJournalError.noVideo(document.id) }
            let name = file.path.split(separator: "/").last.map(String.init) ?? file.path
            return File(name: name, sha256: hash, startUs: span.startUs, endUs: span.endUs)
        }
    }

    static func matches(_ expected: Entry, actual: [File]) -> Bool {
        !expected.files.isEmpty && expected.files.count == actual.count &&
            zip(expected.files, actual).allSatisfy { old, new in
                old.hasTimeline && old.sha256 == new.sha256 && old.startUs == new.startUs && old.endUs == new.endUs
            }
    }
}
