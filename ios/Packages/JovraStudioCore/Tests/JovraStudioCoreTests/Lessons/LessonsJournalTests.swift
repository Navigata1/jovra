import Foundation
import JovraCore
import JovraStudioCore
import Testing

/// LessonJournal (S36; stories 166–175, 178): lessons in the local project store, created by hand, edited with an
/// unsaved-edit guard, with notes, drills, clips, cues and films.
@Suite("Lessons: journal")
struct LessonsJournalTests {
    @Test("a lesson is created by hand with no recording and no core session store, and survives a reopen")
    func manualLessonWorksOffline() async throws {
        let scratch = try ProjectScratch()
        defer { scratch.cleanUp() }
        let store = try scratch.store()
        let project = try await store.create(kind: .lessonSeries)
        let journal = LessonJournal(store: store, projectId: project.projectId)   // no SessionStore at all
        let lesson = try await journal.create(date: "2026-11-04", title: "Backhand basics", focus: "Early preparation",
                                              coach: "Coach Dee", nextGoal: "Rally ten balls cross-court")
        #expect(lesson.sessionIds.isEmpty && lesson.clips.isEmpty && lesson.cues.isEmpty && lesson.practice.isEmpty)
        #expect(!lesson.sample)
        #expect(lesson.share == LessonShare(mode: .private, grantIds: []))
        let reopened = LessonJournal(store: try scratch.store(), projectId: project.projectId)
        #expect(try await reopened.lessons() == [lesson])
        await #expect(throws: LessonJournalError.badDate("2026-11-31")) {
            _ = try await journal.create(date: "2026-11-31", title: "Nope")
        }
        await #expect(throws: LessonJournalError.badText) { _ = try await journal.create(date: "2026-11-05", title: "   ") }
    }

    @Test("the installed Sample lessons read back exactly as shipped, oldest first, with their journey focus lines")
    func sampleLessonsReadBack() async throws {
        let scratch = try ProjectScratch()
        defer { scratch.cleanUp() }
        let store = try scratch.store()
        try await StudioSampleContent(records: StudioSampleRecords.load(from: StudioFixtures.root().appendingPathComponent("records")))
            .install(into: store)
        let journal = LessonJournal(store: store, projectId: StudioSampleContent.lessonProjectID)
        let lessons = try await journal.lessons()
        let shipped = try LessonsRecordRulesTests.samples.map {
            try StudioContractCodec.decode(Lesson.self, from: StudioFixtures.data("records/\($0)"))
        }
        #expect(lessons == shipped)
        let journey = try await journal.journey()
        #expect(journey.map(\.date) == ["2026-09-09", "2026-09-23", "2026-10-07"])
        #expect(journey.map(\.focusLine) == ["Find the rhythm", "Repeat the routine", "Same toss. Calm finish."])
        #expect(journey.map(\.clipCount) == [4, 2, 3])
        #expect(journey.allSatisfy { $0.sample })
        #expect(journey.last?.practice.text == "2 of 3 drills complete")
    }

    @Test("a coach note entered without a coach is refused; with one it is attributed to that coach as entered")
    func coachNotes() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let (journal, _) = try await s.journal()
        let solo = try await journal.create(date: "2026-11-01", title: "Solo hit")
        await #expect(throws: LessonJournalError.rule(LessonRejection(.unattributedCoach, "a coach note needs the lesson's coach"))) {
            _ = try await journal.addNote("Turn the shoulders", author: .coach, to: solo.lessonId)
        }
        #expect(try await journal.lesson(solo.lessonId).notes.isEmpty)
        let coached = try await journal.create(date: "2026-11-02", title: "Serve lesson", coach: "Coach Dee")
        let note = try await journal.addNote("Toss in front", author: .coach, to: coached.lessonId)
        let stored = try await journal.lesson(coached.lessonId)
        #expect(try stored.attribution(of: note) == .coach(displayName: "Coach Dee"))
        #expect(note.provenance == .manual)
        #expect(stored.unreviewedNotes == [note])
        let reviewed = try await journal.markNoteReviewed(note.noteId, in: coached.lessonId)
        #expect(reviewed.provenance == .reviewed)
        #expect(try await journal.lesson(coached.lessonId).unreviewedNotes.isEmpty)
        let mine = try await journal.addNote("Felt rushed", author: .user, to: coached.lessonId)
        #expect(try await journal.lesson(coached.lessonId).attribution(of: mine) == .player)
    }

    @Test("leaving with unsaved edits asks first; a save never overwrites a lesson changed since the edit began")
    func unsavedEditGuard() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let (journal, _) = try await s.journal()
        let lesson = try await journal.create(date: "2026-11-03", title: "Volleys", focus: "Soft hands")
        var edit = try await journal.beginEdit(lesson.lessonId)
        #expect(edit.leaveDecision == .leave)
        edit.draft.focus = .value("Firm wrist")
        #expect(edit.hasUnsavedChanges && edit.leaveDecision == .askToSaveOrDiscard)
        var discarded = edit
        discarded.discard()
        #expect(discarded.leaveDecision == .leave)
        #expect(try await journal.lesson(lesson.lessonId).focus == .value("Soft hands"))

        // a note added elsewhere after the edit began: saving the stale edit is refused, the note survives
        let note = try await journal.addNote("Split step", author: .user, to: lesson.lessonId)
        await #expect(throws: LessonJournalError.changedElsewhere(lesson.lessonId)) { try await journal.save(edit) }
        let stored = try await journal.lesson(lesson.lessonId)
        #expect(stored.notes == [note] && stored.focus == .value("Soft hands"))

        var relabel = try await journal.beginEdit(lesson.lessonId)
        relabel.draft.sample = true
        await #expect(throws: LessonJournalError.identityChanged(lesson.lessonId)) { try await journal.save(relabel) }

        var fresh = try await journal.beginEdit(lesson.lessonId)
        fresh.draft.focus = .value("Firm wrist")
        let saved = try await journal.save(fresh)
        #expect(saved.focus == .value("Firm wrist") && saved.notes == [note])
        #expect(try await journal.lesson(lesson.lessonId) == saved)
    }

    @Test("a practice checklist with counts reads 2 of 3 drills complete after ticking two drills to their targets")
    func practiceChecklist() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let (journal, _) = try await s.journal()
        let lesson = try await journal.create(date: "2026-11-03", title: "Serve rhythm")
        let shadow = try await journal.setDrill("Shadow serves", target: 10, in: lesson.lessonId)
        let target = try await journal.setDrill("Target serves", target: 20, in: lesson.lessonId)
        _ = try await journal.setDrill("Review clips", unit: .clips, target: 5, in: lesson.lessonId)
        #expect(try await journal.lesson(lesson.lessonId).practiceSummary.text == "0 of 3 drills complete")
        for _ in 0..<10 { _ = try await journal.tick(shadow.itemId, in: lesson.lessonId) }
        let once = try await journal.tick(target.itemId, in: lesson.lessonId)
        #expect(once.done == 1 && once.status == .inProgress)
        for _ in 0..<25 { _ = try await journal.tick(target.itemId, in: lesson.lessonId) }   // stops at the target
        let stored = try await journal.lesson(lesson.lessonId)
        #expect(stored.practice.map(\.done) == [10, 20, 0])
        #expect(stored.practice.map(\.status) == [.done, .done, .pending])
        #expect(stored.practiceSummary == LessonPracticeSummary(complete: 2, total: 3))
        #expect(stored.practiceSummary.text == "2 of 3 drills complete")
        // a target below what is already done is refused, not silently reset
        await #expect(throws: LessonJournalError.self) {
            _ = try await journal.setDrill("Target serves", target: 12, itemId: target.itemId, in: lesson.lessonId)
        }
        #expect(try await journal.lesson(lesson.lessonId).practice[1].done == 20)
        let back = try await journal.tick(target.itemId, by: -1, in: lesson.lessonId)
        #expect(back.done == 19 && back.status == .inProgress)
    }

    @Test("an exact clip range of any session links to a lesson; a range outside the recording is refused")
    func linkClip() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let (journal, _) = try await s.journal()
        let session = try await s.session("practice-1104", bytes: syntheticVideo("a"), kind: .servePractice)
        let lesson = try await journal.create(date: "2026-11-04", title: "Serve rhythm")
        let range = StudioIntervalUs(startUs: 12_400_000, endUs: 18_600_000)
        let clip = try await journal.linkClip(sessionId: session.id, range: range, label: "Toss drift", to: lesson.lessonId)
        let stored = try await journal.lesson(lesson.lessonId)
        #expect(stored.sessionIds == [session.id])
        #expect(stored.clips == [clip])
        #expect(clip.window == .value(range) && clip.status == .available && clip.sessionId == .value(session.id))
        let note = try await journal.addNote("Toss drifted right", author: .user, clipIds: [clip.clipId], to: lesson.lessonId)
        #expect(note.clipIds == [clip.clipId])
        do throws(LessonJournalError) {
            _ = try await journal.addNote("Elsewhere", author: .user, clipIds: ["other"], to: lesson.lessonId)
            Issue.record("a note on another lesson's clip was accepted")
        } catch { #expect({ if case .rule(let r) = error { r.code == .unknownClip } else { false } }()) }
        let beyond = StudioIntervalUs(startUs: 0, endUs: (session.recording.durationMs! + 1) * 1000)
        await #expect(throws: LessonJournalError.badRange) {
            _ = try await journal.linkClip(sessionId: session.id, range: beyond, to: lesson.lessonId)
        }
        await #expect(throws: LessonJournalError.badRange) {
            _ = try await journal.linkClip(sessionId: session.id, range: .init(startUs: 5, endUs: 5), to: lesson.lessonId)
        }
        await #expect(throws: LessonJournalError.sessionNotFound("no-such-session")) {
            _ = try await journal.linkClip(sessionId: "no-such-session", range: range, to: lesson.lessonId)
        }
    }

    @Test("an observation becomes a cue with its own provenance; a rejected observation never becomes one")
    func linkCue() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        let (journal, _) = try await s.journal()
        let match = try await s.store.create(kind: .match)
        for (name, status) in [("observation.estimated-cue.json", "proposed"), ("observation.reviewed-cue.json", "accepted"),
                               ("observation.estimated-cue.json", "rejected")] {
            var text = String(decoding: try StudioFixtures.data("records/\(name)"), as: UTF8.self)
                .replacingOccurrences(of: #""sample": true"#, with: #""sample": false"#)
                .replacingOccurrences(of: #""projectId": "sample-court-day""#, with: #""projectId": "\#(match.projectId)""#)
            if status == "rejected" {
                text = text.replacingOccurrences(of: #""status": "proposed""#, with: #""status": "rejected""#)
                    .replacingOccurrences(of: #""observationId": "obs-01""#, with: #""observationId": "obs-09""#)
            }
            try await s.store.writeRecord(Data(text.utf8), named: "\(status)-\(name)", in: .observations, of: match.projectId)
        }
        let session = try await s.session("match-1104", bytes: syntheticVideo("m"))
        let lesson = try await journal.create(date: "2026-11-04", title: "Serve rhythm", coach: "Coach Dee")
        let clip = try await journal.linkClip(sessionId: session.id, range: .init(startUs: 1_216_000_000, endUs: 1_219_000_000),
                                              to: lesson.lessonId)
        let estimated = try await journal.linkCue(observationId: "obs-01", from: match.projectId, clipId: clip.clipId,
                                                  text: "Toss slightly in front", to: lesson.lessonId)
        #expect(estimated.provenance == .estimated && estimated.reviewedBy == .null && estimated.observationId == .value("obs-01"))
        let reviewed = try await journal.linkCue(observationId: "obs-02", from: match.projectId, clipId: clip.clipId,
                                                 text: "Calm setup", to: lesson.lessonId)
        #expect(reviewed.provenance == .reviewed && reviewed.reviewedBy == .value(.coach))
        await #expect(throws: LessonJournalError.observationRejected("obs-09")) {
            _ = try await journal.linkCue(observationId: "obs-09", from: match.projectId, clipId: clip.clipId,
                                          text: "Rejected", to: lesson.lessonId)
        }
        await #expect(throws: LessonJournalError.clipNotFound("l9-clip")) {
            _ = try await journal.linkCue(observationId: "obs-02", from: match.projectId, clipId: "l9-clip",
                                          text: "Calm setup", to: lesson.lessonId)
        }
        #expect(try await journal.lesson(lesson.lessonId).cues == [estimated, reviewed])
    }

    @Test("a film attaches to a lesson of its own kind; Sample and real content never mix")
    func attachFilm() async throws {
        let s = try LessonsScratch()
        defer { s.cleanUp() }
        try await StudioSampleContent(records: StudioSampleRecords.load(from: StudioFixtures.root().appendingPathComponent("records")))
            .install(into: s.store)
        let sample = s.journal(StudioSampleContent.lessonProjectID)
        let film = try #require(try await s.store.films(StudioSampleContent.matchProjectID).first)
        let attached = try await sample.attachFilm(film.artifactId, from: StudioSampleContent.matchProjectID, to: "lesson-1007")
        #expect(attached.filmIds == [film.artifactId])
        #expect(try await sample.attachFilm(film.artifactId, from: StudioSampleContent.matchProjectID, to: "lesson-1007") == attached)
        await #expect(throws: LessonJournalError.filmNotFound("no-film")) {
            _ = try await sample.attachFilm("no-film", from: StudioSampleContent.matchProjectID, to: "lesson-1007")
        }
        let (real, _) = try await s.journal()
        let mine = try await real.create(date: "2026-11-04", title: "Mine")
        await #expect(throws: LessonJournalError.sampleIsolation) {
            _ = try await real.attachFilm(film.artifactId, from: StudioSampleContent.matchProjectID, to: mine.lessonId)
        }
        // the Sample lesson never links a core session
        let session = try await s.session("real-1104", bytes: syntheticVideo("r"))
        await #expect(throws: LessonJournalError.sampleIsolation) {
            _ = try await sample.linkClip(sessionId: session.id, range: .init(startUs: 0, endUs: 1_000_000), to: "lesson-1007")
        }
    }

    @Test("the lesson journal has no network path: no source file in Lessons or Progress names a network API")
    func noNetworkPath() throws {
        let root = StudioFixtures.repositoryRoot().appendingPathComponent("ios/Packages/JovraStudioCore/Sources/JovraStudioCore")
        var scanned = 0
        for folder in ["Lessons", "Progress"] {
            let url = root.appendingPathComponent(folder)
            for name in try FileManager.default.contentsOfDirectory(atPath: url.path) where name.hasSuffix(".swift") {
                let text = try String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)
                for api in ["URLSession", "URLRequest", "NWConnection", "import Network", "http://", "https://"] {
                    #expect(!text.contains(api), "\(folder)/\(name) names \(api)")
                }
                scanned += 1
            }
        }
        #expect(scanned >= 6)
    }
}
