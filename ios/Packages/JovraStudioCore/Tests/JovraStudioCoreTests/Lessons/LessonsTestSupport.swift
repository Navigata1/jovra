import Foundation
import JovraCore
import JovraStudioCore

/// A scratch Studio store and core session store for lesson tests, with a fixed clock and counting ids.
struct LessonsScratch {
    let scratch: ProjectScratch
    let sessions: SessionStore
    let store: StudioProjectStore

    init() throws {
        scratch = try ProjectScratch()
        sessions = try SessionStore(root: scratch.core)
        store = try scratch.store(sessions: sessions)
    }

    func cleanUp() { scratch.cleanUp() }

    /// A new real lesson-series project and its journal.
    func journal() async throws -> (LessonJournal, String) {
        let project = try await store.create(kind: .lessonSeries)
        return (journal(project.projectId), project.projectId)
    }

    func journal(_ projectId: String) -> LessonJournal {
        LessonJournal(store: store, projectId: projectId, sessions: sessions, now: { ProjectScratch.fixedNow },
                      makeID: LessonsIDs().next, verifyMedia: { [sessions] id, segments in
                          let directory = try await sessions.sessionDirectory(id)
                          return try segments.map { try StudioSHA256.hex(Data(contentsOf: directory.appendingPathComponent($0.file.path))) }
                      })
    }

    /// A real practice or match session with one recorded original whose SHA-256 is that of `bytes`, written into the
    /// session's media folder under `fileName`. The match log is the shipped Jon vs Alex log (all points reviewed).
    @discardableResult
    func session(_ id: String, bytes: Data, fileName: String = "segment-000.mov",
                 kind: SessionDocumentSessionKind = .match) async throws -> SessionDocument {
        var document = try CoreFixtureSessions.jonVsAlex()
        document.id = id
        document.sample = nil
        document.sessionKind = kind
        let duration = try lessonsRequire(document.recording.durationMs)
        let sha = StudioSHA256.hex(bytes)
        document.recording.mode = .camera
        document.recording.mediaAvailable = true
        document.recording.segments = [
            SessionSegment(id: "seg-0", index: 0,
                           file: RecordFileReference(path: "media/\(fileName)", mimeType: "video/quicktime",
                                                     bytes: bytes.count, sha256: sha),
                           startMs: 0, durationMs: duration, frameRate: RecordedFrameRate(num: 30, den: 1),
                           width: 1920, height: 1080, codec: .hevc, hasAudio: false, finalized: true),
        ]
        document.original = SessionOriginalState(state: .saved)
        let file = try await CoreFixtureSessions.install(document, bytes: bytes, in: sessions)
        if file.lastPathComponent != fileName {
            try FileManager.default.moveItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent(fileName))
        }
        return document
    }
}

/// Deterministic ids: `clip-1`, `note-2`, ...
final class LessonsIDs: @unchecked Sendable {
    private var count = 0
    private let lock = NSLock()

    var next: @Sendable (String) -> String {
        { [self] prefix in
            lock.lock(); defer { lock.unlock() }
            count += 1
            return "\(prefix)-\(count)"
        }
    }
}

func lessonsRequire<T>(_ value: T?, _ what: String = "value") throws -> T {
    guard let value else { throw CocoaError(.coderValueNotFound, userInfo: [NSDebugDescriptionErrorKey: what]) }
    return value
}

/// Bytes standing in for a video original (synthetic, never real footage).
func syntheticVideo(_ seed: String) -> Data { Data("JOVRA synthetic test original · \(seed)".utf8) }
