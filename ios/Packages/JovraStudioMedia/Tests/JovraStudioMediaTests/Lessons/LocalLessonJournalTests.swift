import Foundation
import JovraCore
import JovraStudioCore
import JovraStudioMedia
import Testing

@Suite("Lesson owned originals")
struct LocalLessonJournalTests {
    @Test func verifiesUnhashedFilesAndRejectsReplacementsLinksAndShiftedRepairs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = try SessionStore(root: root.appendingPathComponent("Core"))
        let store = try StudioProjectStore(root: root.appendingPathComponent("Studio"), sessions: sessions)
        let project = try await store.create(kind: .lessonSeries)
        let journal = LocalLessonJournal.make(store: store, projectId: project.projectId, sessions: sessions)
        let fixture = StudioFixtures.repositoryRoot().appendingPathComponent("ios/Jovra/Resources/Fixtures/fixture-camera-720p30.mp4")
        let bytes = try Data(contentsOf: fixture)
        let range = StudioIntervalUs(startUs: 1_000_000, endUs: 2_000_000)
        let original = try await addSession("source", fileName: "segment-0.mp4", start: 0, bytes: bytes, store: sessions)
        let lesson = try await journal.create(date: "2026-11-04", title: "Review the clip")
        let clip = try await journal.linkClip(sessionId: "source", range: range, to: lesson.lessonId)
        #expect(clip.status == .available)
        #expect(try await sessions.load("source").recording.segments[0].file.sha256 == nil)

        var changed = bytes
        changed[changed.startIndex] ^= 0xff
        try changed.write(to: original, options: .atomic)
        #expect(try await journal.refreshClipAvailability(in: lesson.lessonId).clips.first?.status == .missing)
        await #expect(throws: LessonJournalError.notTheSameVideo(clipId: clip.clipId)) {
            _ = try await journal.findTheVideo(clipId: clip.clipId, in: lesson.lessonId, candidateSessionId: "source")
        }

        try FileManager.default.removeItem(at: original)
        #expect(try await journal.refreshClipAvailability(in: lesson.lessonId).clips.first?.status == .missing)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: fixture)
        await #expect(throws: LessonJournalError.notTheSameVideo(clipId: clip.clipId)) {
            _ = try await journal.findTheVideo(clipId: clip.clipId, in: lesson.lessonId, candidateSessionId: "source")
        }

        // Both candidates cover the requested range, but only the unshifted one keeps the source-frame mapping.
        _ = try await addSession("shifted", fileName: "segment-0.mp4", start: 500, bytes: bytes, store: sessions)
        await #expect(throws: LessonJournalError.notTheSameVideo(clipId: clip.clipId)) {
            _ = try await journal.findTheVideo(clipId: clip.clipId, in: lesson.lessonId, candidateSessionId: "shifted")
        }
        _ = try await addSession("restored", fileName: "renamed.mp4", start: 0, bytes: bytes, store: sessions)
        let repaired = try await journal.findTheVideo(clipId: clip.clipId, in: lesson.lessonId, candidateSessionId: "restored")
        #expect(repaired.sessionId.value == "restored" && repaired.window.value == range && repaired.status == .available)
        #expect(try Data(contentsOf: fixture) == bytes)
    }

    private func addSession(_ id: String, fileName: String, start: Int, bytes: Data, store: SessionStore) async throws -> URL {
        let path = "originals/\(fileName)"
        let fixtureDurationMs = 12_000 // The bundled fixture's 360 frames at 30 fps.
        let segment = SessionSegment(id: "segment-0", index: 0, file: .init(path: path, bytes: bytes.count),
            startMs: start, durationMs: fixtureDurationMs, frameRate: .init(num: 30, den: 1), width: 1_280, height: 720,
            codec: .h264, hasAudio: true, finalized: true)
        let document = SessionDocument(id: id, sport: .value, createdAt: "2026-11-04T00:00:00Z",
            updatedAt: "2026-11-04T00:00:00Z", title: id, sessionKind: .strokePractice,
            players: [.init(id: "player", displayName: "Player", handedness: .unknown, backhand: .unknown, isSelf: false)],
            recording: .init(mode: .camera, durationMs: start + fixtureDurationMs, segments: [segment], gaps: [],
                             microphone: .notRequested, mediaAvailable: true),
            archive: .init(state: .localOnly), storage: .init(originals: .onDevice, includeInDeviceBackup: false),
            original: .init(state: .saved))
        try await store.create(document)
        let folder = try await store.sessionDirectory(id)
        let file = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: false)
        try bytes.write(to: file)
        return file
    }
}
