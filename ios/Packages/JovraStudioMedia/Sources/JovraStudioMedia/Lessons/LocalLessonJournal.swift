import JovraCore
import JovraMedia
import JovraStudioCore

/// The local journal backed by the same original custody as native Capture, Files import and Replay.
public enum LocalLessonJournal {
    public static func make(store: StudioProjectStore, projectId: String, sessions: SessionStore) -> LessonJournal {
        let media = MediaLibrary(store: sessions)
        return LessonJournal(store: store, projectId: projectId, sessions: sessions, verifyMedia: { expected, segments in
            try await media.originalSHA256s(expected: expected, segments: segments)
        })
    }
}
