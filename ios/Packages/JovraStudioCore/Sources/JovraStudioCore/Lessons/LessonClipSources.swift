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
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var clipId: String
        /// The session the clip is linked to now.
        public var sessionId: String
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

    mutating func upsert(_ entry: Entry) {
        if let index = clips.firstIndex(where: { $0.clipId == entry.clipId }) { clips[index] = entry }
        else { clips.append(entry) }
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

    /// The finalized originals of `document` that overlap `range` (session microseconds, half-open) and carry a
    /// SHA-256.
    static func segments(of document: SessionDocument, covering range: StudioIntervalUs) -> [(name: String, sha256: String)] {
        document.recording.segments.compactMap { segment in
            let start = segment.startMs * 1000, end = (segment.startMs + segment.durationMs) * 1000
            guard segment.finalized, start < range.endUs, range.startUs < end,
                  let sha = segment.file.sha256, sha.count == 64 else { return nil }
            let name = segment.file.path.split(separator: "/").last.map(String.init) ?? segment.file.path
            return (name, sha)
        }
    }

    /// True when `document` holds a finalized original with every hash of `entry`.
    static func holds(_ document: SessionDocument, _ entry: Entry) -> Bool {
        guard document.recording.mediaAvailable else { return false }
        let hashes = Set(document.recording.segments.filter(\.finalized).compactMap(\.file.sha256))
        return entry.files.allSatisfy { hashes.contains($0.sha256) }
    }
}
