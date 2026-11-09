import Foundation
import JovraCore
import JovraStudioCore
import Testing

/// A lesson clip whose source was deleted shows as missing with "Find the video" (story 173), and only the same file,
/// proven by SHA-256, re-links it.
@Suite("Lessons: missing clips and Find the video")
struct LessonsClipRepairTests {
    struct Linked {
        let journal: LessonJournal
        let lessonId: String
        let clipId: String
        let sessionId: String
    }

    static func linked(_ s: LessonsScratch, bytes: Data) async throws -> Linked {
        let (journal, _) = try await s.journal()
        let session = try await s.session("practice-orig", bytes: bytes, kind: .servePractice)
        let lesson = try await journal.create(date: "2026-11-04", title: "Serve rhythm")
        let clip = try await journal.linkClip(sessionId: session.id, range: .init(startUs: 0, endUs: 6_200_000), to: lesson.lessonId)
        return Linked(journal: journal, lessonId: lesson.lessonId, clipId: clip.clipId, sessionId: session.id)
    }

    static func status(_ l: Linked) async throws -> LessonClipStatus? {
        try await l.journal.lesson(l.lessonId).clips.first { $0.clipId == l.clipId }?.status
    }

    @Test("deleting the source session marks the clip missing; restoring the same file by hash re-links it")
    func purgedSourceRelinksOnlyBySameHash() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let original = syntheticVideo("original serve practice")
        let l = try await Self.linked(s, bytes: original)
        // the hash recorded at link time is the original's, as the system tool computes it
        let file = try await s.sessions.sessionDirectory(l.sessionId).appendingPathComponent("media/segment-000.mov")
        let sources = try #require(try await s.store.record(named: "\(l.lessonId).clip-sources.json", in: .lessons, of: l.journal.projectId))
        #expect(String(decoding: sources, as: UTF8.self).contains(try systemSHA256(file)))
        #expect(try await l.journal.refreshClipAvailability(in: l.lessonId).clips.map(\.status) == [.available])

        try await s.sessions.trash(l.sessionId)
        try await s.sessions.purge(l.sessionId, confirmation: s.sessions.purgeConfirmation(for: l.sessionId))
        #expect(try await l.journal.refreshClipAvailability(in: l.lessonId).clips.map(\.status) == [.missing])

        // a different file with the same name is not the video
        let impostor = try await s.session("practice-impostor", bytes: syntheticVideo("another day entirely"), kind: .servePractice)
        #expect(impostor.recording.segments[0].file.path == "media/segment-000.mov")
        await #expect(throws: LessonJournalError.notTheSameVideo(clipId: l.clipId)) {
            _ = try await l.journal.findTheVideo(clipId: l.clipId, in: l.lessonId, candidateSessionId: impostor.id)
        }
        #expect(try await Self.status(l) == .missing)

        // the same bytes, restored into a new session, re-link the clip
        let restored = try await s.session("practice-restored", bytes: original, fileName: "IMG_0412.MOV", kind: .servePractice)
        let clip = try await l.journal.findTheVideo(clipId: l.clipId, in: l.lessonId, candidateSessionId: restored.id)
        #expect(clip.status == .available && clip.sessionId == .value(restored.id))
        let lesson = try await l.journal.lesson(l.lessonId)
        #expect(lesson.sessionIds == [restored.id])
        #expect(try await l.journal.refreshClipAvailability(in: l.lessonId).clips.map(\.status) == [.available])
    }

    @Test("a source moved to Trash is missing, and Undo (restore from Trash) brings the clip back")
    func trashedSourceComesBackOnRestore() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let l = try await Self.linked(s, bytes: syntheticVideo("trash and undo"))
        try await s.sessions.trash(l.sessionId)
        #expect(try await l.journal.refreshClipAvailability(in: l.lessonId).clips.map(\.status) == [.missing])
        try await s.sessions.restoreFromTrash(l.sessionId)
        #expect(try await l.journal.refreshClipAvailability(in: l.lessonId).clips.map(\.status) == [.available])
    }

    @Test("a source whose declared hash contradicts its on-disk bytes is not available")
    func replacedOriginalIsMissing() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let l = try await Self.linked(s, bytes: syntheticVideo("first take"))
        var document = try await s.sessions.load(l.sessionId)
        document.recording.segments[0].file.sha256 = StudioSHA256.hex(syntheticVideo("second take"))
        try await s.sessions.updateRecording(document.recording, for: l.sessionId)
        #expect(try await l.journal.refreshClipAvailability(in: l.lessonId).clips.map(\.status) == [.missing])
        await #expect(throws: LessonJournalError.notTheSameVideo(clipId: l.clipId)) {
            _ = try await l.journal.findTheVideo(clipId: l.clipId, in: l.lessonId, candidateSessionId: l.sessionId)
        }
    }

    @Test func linksOrdinaryCaptureWithoutAStoredHash() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let (journal, _) = try await s.journal()
        var document = try await s.session("ordinary-capture", bytes: syntheticVideo("actual bytes"))
        document.recording.segments[0].file.sha256 = nil
        try await s.sessions.updateRecording(document.recording, for: document.id)
        let lesson = try await journal.create(date: "2026-11-04", title: "Ordinary capture")
        let clip = try await journal.linkClip(sessionId: document.id, range: .init(startUs: 0, endUs: 1_000_000), to: lesson.lessonId)
        #expect(clip.status == .available)
    }

    @Test(arguments: [false, true])
    func missingOrReplacedBytesWithUnchangedMetadataAreNotAvailable(remove: Bool) async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let linked = try await Self.linked(s, bytes: syntheticVideo("original"))
        let folder = try await s.sessions.sessionDirectory(linked.sessionId)
        let file = folder.appendingPathComponent("media/segment-000.mov")
        if remove {
            try FileManager.default.removeItem(at: file)
        } else {
            try syntheticVideo("impostor").write(to: file)
        }
        #expect(try await linked.journal.refreshClipAvailability(in: linked.lessonId).clips.map(\.status) == [.missing])
        await #expect(throws: LessonJournalError.notTheSameVideo(clipId: linked.clipId)) {
            _ = try await linked.journal.findTheVideo(clipId: linked.clipId, in: linked.lessonId, candidateSessionId: linked.sessionId)
        }
    }

    @Test func sameBytesAtDifferentSessionOffsetCannotRepairTheClip() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let bytes = syntheticVideo("same exact bytes")
        let linked = try await Self.linked(s, bytes: bytes)
        var shifted = try await s.session("shifted", bytes: bytes, kind: .servePractice)
        shifted.recording.segments[0].startMs = 1
        try await s.sessions.updateRecording(shifted.recording, for: shifted.id)
        await #expect(throws: LessonJournalError.notTheSameVideo(clipId: linked.clipId)) {
            _ = try await linked.journal.findTheVideo(clipId: linked.clipId, in: linked.lessonId, candidateSessionId: shifted.id)
        }
        #expect(try await linked.journal.lesson(linked.lessonId).clips.first?.sessionId.value == linked.sessionId)
    }

    @Test func aDeclaredGapInsideTheClipIsNotCovered() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let (journal, _) = try await s.journal()
        var document = try await s.session("interrupted", bytes: syntheticVideo("recorded media"))
        document.recording.gaps = [.init(startMs: 500, endMs: 600, reason: .interruption)]
        try await s.sessions.updateRecording(document.recording, for: document.id)
        let lesson = try await journal.create(date: "2026-11-04", title: "Interrupted")
        await #expect(throws: LessonJournalError.noVideo(document.id)) {
            _ = try await journal.linkClip(sessionId: document.id, range: .init(startUs: 0, endUs: 1_000_000),
                                           to: lesson.lessonId)
        }
        #expect(try await journal.lesson(lesson.lessonId) == lesson)
    }

    @Test func missingVerifierAndLegacyReceiptFailClosed() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let linked = try await Self.linked(s, bytes: syntheticVideo("actual legacy source"))
        let unavailable = LessonJournal(store: s.store, projectId: linked.journal.projectId, sessions: s.sessions)
        let original = try await unavailable.lesson(linked.lessonId)
        await #expect(throws: LessonJournalError.mediaVerificationUnavailable) {
            _ = try await unavailable.refreshClipAvailability(in: linked.lessonId)
        }
        #expect(try await unavailable.lesson(linked.lessonId) == original)

        let name = "\(linked.lessonId).clip-sources.json"
        let data = try #require(try await s.store.record(named: name, in: .lessons, of: linked.journal.projectId))
        var receipt = try JSONDecoder().decode(LessonClipSources.self, from: data)
        receipt.clips[0].window = nil
        receipt.clips[0].files[0].startUs = nil
        receipt.clips[0].files[0].endUs = nil
        let legacy = try JSONEncoder().encode(receipt)
        try await s.store.writeRecord(legacy, named: name, in: .lessons, of: linked.journal.projectId)
        await #expect(throws: LessonJournalError.cannotVerify(clipId: linked.clipId)) {
            _ = try await linked.journal.findTheVideo(clipId: linked.clipId, in: linked.lessonId,
                                                     candidateSessionId: linked.sessionId)
        }
        #expect(try await linked.journal.lesson(linked.lessonId) == original)
        #expect(try await s.store.record(named: name, in: .lessons, of: linked.journal.projectId) == legacy)
    }

    @Test("a Sample lesson never reads the core session store: its clips are shown as shipped")
    func sampleLessonsAreNotChecked() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        try await StudioSampleContent(records: StudioSampleRecords.load(from: StudioFixtures.root().appendingPathComponent("records")))
            .install(into: s.store)
        let journal = s.journal(StudioSampleContent.lessonProjectID)
        let before = try await journal.lesson("lesson-0909")
        #expect(try await journal.refreshClipAvailability(in: "lesson-0909") == before)
        await #expect(throws: LessonJournalError.sampleIsolation) {
            _ = try await journal.findTheVideo(clipId: "l1-clip-1", in: "lesson-0909", candidateSessionId: "anything")
        }
    }
}

/// Corrections to a session update the lesson insights that use it (story 180).
@Suite("Lessons: insights follow corrections")
struct LessonsInsightTests {
    static let pointsWon = ProgressStat(statDefinitionId: "points-won-a", key: StatKey(stat: "totalPointsWon", side: .a))
    static let method = ProgressMethod(methodId: "manual-tagging-v1", methodVersion: "1", capabilityVersion: nil)

    @Test("correcting a point in a lesson's session changes that lesson's comparison the next time it is read")
    func correctionPropagates() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let (journal, _) = try await s.journal()
        // two real matches with one reviewed point each, then the later one corrected
        let ids = ["match-early", "match-late"]
        for (id, date) in zip(ids, ["2026-10-01", "2026-10-29"]) {
            try await s.session(id, bytes: syntheticVideo(id))
            let lesson = try await journal.create(date: date, title: "Match review \(date)")
            _ = try await journal.linkClip(sessionId: id, range: .init(startUs: 0, endUs: 1_000_000), to: lesson.lessonId)
        }
        // replace each log with reviewed points: early A wins 1 of 2, late A wins 2 of 2
        for (index, winners) in [[Side.a, .b], [Side.a, .a]].enumerated() {
            let id = ids[index]
            try await Self.resetLog(id, in: s.sessions)
            for (n, winner) in winners.enumerated() {
                _ = try await s.sessions.appendReviewedPoint(winner: winner, startMs: n * 1000, endMs: (n + 1) * 1000, for: id)
            }
        }
        let lessons = try await journal.lessons()
        let before = try await journal.compare(Self.pointsWon, method: Self.method, earlier: lessons[0].lessonId, later: lessons[1].lessonId)
        #expect(before.summary == "1 / 2 · 50% → 2 / 2 · 100%, +50 percentage points")

        let late = try await s.sessions.load("match-late")
        let first = try #require(late.match?.log.first?.id)
        _ = try await s.sessions.correctReviewedWinner(pointID: first, winner: .b, for: "match-late")
        let after = try await journal.compare(Self.pointsWon, method: Self.method, earlier: lessons[0].lessonId, later: lessons[1].lessonId)
        #expect(after.summary == "1 / 2 · 50% → 1 / 2 · 50%, 0 percentage points")
        #expect(after.claim == .noChange)
        // the lesson records themselves did not change: the insight is read from the session, never stored
        #expect(try await journal.lessons() == lessons)
    }

    /// Empties a session's match log so a test starts from a known score (the shipped log is the 124-point Sample).
    static func resetLog(_ id: String, in store: SessionStore) async throws {
        let folder = try await store.sessionDirectory(id)
        let url = folder.appendingPathComponent("session.json")
        var document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: url))
        document.match?.log = []
        try CanonicalJSON.encode(document).write(to: url)
    }
}
