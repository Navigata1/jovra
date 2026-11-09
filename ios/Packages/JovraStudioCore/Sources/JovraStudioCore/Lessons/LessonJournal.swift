import Foundation
import JovraCore

/// Hashes the supplied current segments' owned originals in order, or throws if custody is unverified.
public typealias LessonMediaVerifier = @Sendable (String, [SessionSegment]) async throws -> [String]

/// Why a journal operation was refused.
public enum LessonJournalError: Error, Equatable, Sendable {
    /// The lesson would break a `jovra.lesson/1` record rule.
    case rule(LessonRejection)
    case lessonNotFound(String)
    case clipNotFound(String)
    case noteNotFound(String)
    case drillNotFound(String)
    case observationNotFound(String)
    case filmNotFound(String)
    /// The core session a clip names is not in the session store.
    case sessionNotFound(String)
    /// Sample and real data never mix: a Sample lesson links only Sample films and observations, and never a core
    /// session; a real lesson never links Sample content (CLAUDE.md rule 1).
    case sampleIsolation
    /// The range is empty, negative, or outside the session's recording.
    case badRange
    /// The session has no recorded video covering the range.
    case noVideo(String)
    /// This journal cannot check actual local media.
    case mediaVerificationUnavailable
    /// A rejected observation stays on record and is never a cue.
    case observationRejected(String)
    /// Text a person types: 1 to 500 characters, not only whitespace.
    case badText
    /// A date that is not a YYYY-MM-DD calendar day.
    case badDate(String)
    /// An edit tried to change the lesson's id or its Sample flag; neither ever changes.
    case identityChanged(String)
    /// The stored lesson changed after the edit began; the edit is kept by the caller, nothing is overwritten.
    case changedElsewhere(String)
    /// "Find the video": the candidate is not the same video (its SHA-256 differs, whatever its name).
    case notTheSameVideo(clipId: String)
    /// The clip was linked without a recorded hash, so no file can be proven to be its video.
    case cannotVerify(clipId: String)
    /// A list on the lesson is full (the contract's maxItems).
    case limitReached(String)
    /// The project store refused the read or write.
    case store(StudioProjectStoreError)
    /// A stored lesson file could not be read as `jovra.lesson/1`.
    case unreadable(String)
}

/// The lesson journal (Studio spec LessonJournal; stories 166–180): `jovra.lesson/1` records in a project's `lessons`
/// folder of the local Studio project store. Everything is local and offline: no operation touches the network, and
/// the core session store is read only to link and check clips.
///
/// - Notes carry the author as entered, the player (`user`) or the lesson's coach, and provenance Manual or Reviewed.
///   JOVRA never authors a note: `LessonNoteAuthor` has no case for it (see `LessonAttribution`).
/// - A clip remembers the SHA-256 of the original it was cut from (`<lessonId>.clip-sources.json`, a local file beside
///   the lesson, not a shared contract). When that original is deleted or replaced, the clip is `missing`; "Find the
///   video" re-links it only to a file with the same hash, never to one that merely has the same name.
/// - Each lesson update passes `LessonRules`. New links store their proof before the lesson update.
public struct LessonJournal: Sendable {
    public let projectId: String
    let store: StudioProjectStore
    let sessions: SessionStore?
    private let verifyMedia: LessonMediaVerifier?
    let now: @Sendable () -> Date
    let makeID: @Sendable (String) -> String

    public static let maxTextLength = 500

    public init(store: StudioProjectStore, projectId: String, sessions: SessionStore? = nil,
                now: @escaping @Sendable () -> Date = { Date() },
                makeID: @escaping @Sendable (String) -> String = { "\($0)-\(UUID().uuidString.lowercased().prefix(12))" },
                verifyMedia: LessonMediaVerifier? = nil) {
        self.store = store
        self.projectId = projectId
        self.sessions = sessions
        self.verifyMedia = verifyMedia
        self.now = now
        self.makeID = makeID
    }

    // MARK: Reading

    /// Every lesson of the project, oldest first (date, then id).
    public func lessons() async throws(LessonJournalError) -> [Lesson] {
        try await files().map(\.lesson).sorted { ($0.date, $0.lessonId) < ($1.date, $1.lessonId) }
    }

    public func lesson(_ lessonId: String) async throws(LessonJournalError) -> Lesson {
        try await file(of: lessonId).lesson
    }

    // MARK: Creating and editing

    /// A lesson entered by hand, with no recording (story 175): no sessions, clips, cues or drills yet.
    public func create(date: String, title: String, focus: String? = nil, coach: String? = nil,
                       nextGoal: String? = nil) async throws(LessonJournalError) -> Lesson {
        guard ProgressDay(date) != nil else { throw .badDate(date) }
        let project = try await project()
        let coachName = try Self.text(optional: coach)
        let lesson = Lesson(lessonId: makeID("lesson"), sample: project.sample, date: date, title: try Self.text(title),
                            focus: .init(try Self.text(optional: focus)), coach: .init(coachName.map { LessonCoach(displayName: $0) }),
                            sessionIds: [], notes: [], clips: [], cues: [], practice: [], nextGoal: .init(try Self.text(optional: nextGoal)),
                            filmIds: [], share: LessonShare(mode: .private, grantIds: []))
        let name = "\(lesson.lessonId).json"
        let bytes = try Self.encode(lesson)
        try await storeCall {
            try await store.updateRecord(named: name, in: .lessons, of: projectId) { current in
                guard current == nil else { throw StudioProjectStoreError.alreadyExists }
                return bytes
            }
        }
        return lesson
    }

    /// Starts editing a lesson's fields. The edit is a value: leaving with unsaved changes asks first (story 178).
    public func beginEdit(_ lessonId: String) async throws(LessonJournalError) -> LessonEdit {
        LessonEdit(original: try await lesson(lessonId))
    }

    /// Saves an edit when the stored lesson is still the one the edit began from; otherwise `changedElsewhere`, and
    /// the newer stored lesson is never overwritten.
    @discardableResult
    public func save(_ edit: LessonEdit) async throws(LessonJournalError) -> Lesson {
        guard edit.hasUnsavedChanges else { return edit.original }
        guard edit.draft.lessonId == edit.original.lessonId, edit.draft.sample == edit.original.sample else {
            throw .identityChanged(edit.original.lessonId)
        }
        return try await mutate(edit.original.lessonId) { stored in
            guard stored == edit.original else { throw LessonJournalError.changedElsewhere(edit.original.lessonId) }
            stored = edit.draft
        }
    }

    // MARK: Notes

    /// Adds a note as entered, Manual (not reviewed). A coach note needs the lesson's coach (story 171).
    @discardableResult
    public func addNote(_ text: String, author: LessonNoteAuthor, clipIds: [String] = [],
                        to lessonId: String) async throws(LessonJournalError) -> LessonNote {
        let note = LessonNote(noteId: makeID("note"), author: author, text: try Self.text(text), provenance: .manual,
                              clipIds: clipIds, createdAt: timestamp())
        try await mutate(lessonId) { lesson in
            guard lesson.notes.count < 100 else { throw LessonJournalError.limitReached("notes") }
            lesson.notes.append(note)
        }
        return note
    }

    /// "Mark reviewed": the player or coach has checked the note (story 170).
    @discardableResult
    public func markNoteReviewed(_ noteId: String, in lessonId: String) async throws(LessonJournalError) -> LessonNote {
        let lesson = try await mutate(lessonId) { lesson in
            guard let index = lesson.notes.firstIndex(where: { $0.noteId == noteId }) else {
                throw LessonJournalError.noteNotFound(noteId)
            }
            lesson.notes[index].provenance = .reviewed
        }
        return lesson.notes.first { $0.noteId == noteId }!
    }

    // MARK: Clips and cues

    /// Links the exact range `range` (session time, microseconds, half-open) of a core session to the lesson (story
    /// 167), and remembers the SHA-256 of the originals it covers so a deleted or replaced video is detected.
    @discardableResult
    public func linkClip(sessionId: String, range: StudioIntervalUs, label: String? = nil,
                         to lessonId: String) async throws(LessonJournalError) -> LessonClip {
        let current = try await lesson(lessonId)
        guard !current.sample else { throw .sampleIsolation }
        let document = try await session(sessionId)
        guard document.sample == nil else { throw .sampleIsolation }
        let covering = try await verifiedFiles(of: document, range: range)
        let clip = LessonClip(clipId: makeID("clip"), sourceId: .null, sessionId: .value(sessionId), keeperId: .null,
                              window: .value(range), status: .available, label: .init(try Self.text(optional: label)))
        let fingerprint = LessonClipSources.Entry(clipId: clip.clipId, sessionId: sessionId,
                                                  window: range, files: covering)
        // The fingerprint lands first: a clip is never stored without the hash that proves its video.
        try await updateSources(of: current) { try $0.insert(fingerprint) }
        try await mutate(lessonId) { lesson in
            guard lesson.clips.count < 100 else { throw LessonJournalError.limitReached("clips") }
            if !lesson.sessionIds.contains(sessionId) {
                guard lesson.sessionIds.count < 16 else { throw LessonJournalError.limitReached("sessions") }
                lesson.sessionIds.append(sessionId)
            }
            lesson.clips.append(clip)
        }
        return clip
    }

    /// Keeps an observation of `observationProjectId` as a cue on one of the lesson's clips, with the observation's
    /// provenance: an Estimated cue stays Estimated and unreviewed until a person confirms it; a rejected observation
    /// is refused. `text` is the cue as the player enters it.
    @discardableResult
    public func linkCue(observationId: String, from observationProjectId: String, clipId: String, text: String,
                        to lessonId: String) async throws(LessonJournalError) -> LessonCue {
        let current = try await lesson(lessonId)
        let observation = try await observation(observationId, in: observationProjectId)
        guard observation.sample == current.sample else { throw .sampleIsolation }
        guard observation.status != .rejected else { throw .observationRejected(observationId) }
        let status = observation.provenance.status
        let reviewer: LessonCueReviewedBy? = switch status {
        case .estimated, .manual: nil
        case .reviewed, .validated: observation.reviewedBy.value.flatMap { LessonCueReviewedBy(rawValue: $0.rawValue) }
        }
        let cue = LessonCue(cueId: makeID("cue"), text: try Self.text(text), clipId: clipId,
                            observationId: .value(observationId), provenance: status, reviewedBy: .init(reviewer))
        try await mutate(lessonId) { lesson in
            guard lesson.cues.count < 50 else { throw LessonJournalError.limitReached("cues") }
            guard lesson.clips.contains(where: { $0.clipId == clipId }) else { throw LessonJournalError.clipNotFound(clipId) }
            lesson.cues.append(cue)
        }
        return cue
    }

    /// Attaches a film of `filmProjectId` to the lesson (story 174). Attaching it again changes nothing.
    @discardableResult
    public func attachFilm(_ artifactId: String, from filmProjectId: String,
                           to lessonId: String) async throws(LessonJournalError) -> Lesson {
        let current = try await lesson(lessonId)
        let films = try await storeCall { try await store.films(filmProjectId) }
        guard let film = films.first(where: { $0.artifactId == artifactId }) else { throw .filmNotFound(artifactId) }
        guard film.sample == current.sample else { throw .sampleIsolation }
        return try await mutate(lessonId) { lesson in
            guard !lesson.filmIds.contains(artifactId) else { return }
            guard lesson.filmIds.count < 16 else { throw LessonJournalError.limitReached("films") }
            lesson.filmIds.append(artifactId)
        }
    }

    // MARK: Practice checklist

    /// Adds a practice-checklist item ("10 shadow serves"), or with `itemId` changes its label, unit or drill target.
    /// A target below the count already done is refused (`badPractice`); nothing is silently reset.
    @discardableResult
    public func setDrill(_ label: String, unit: LessonPracticeItemUnit = .reps, target: Int, itemId: String? = nil,
                         in lessonId: String) async throws(LessonJournalError) -> LessonPracticeItem {
        let text = try Self.text(label)
        guard (1...10_000).contains(target) else { throw .rule(LessonRejection(.badPractice, "a drill target is 1 to 10000")) }
        let id = itemId ?? makeID("drill")
        let lesson = try await mutate(lessonId) { lesson in
            if let index = lesson.practice.firstIndex(where: { $0.itemId == id }) {
                let done = lesson.practice[index].done
                guard done <= target else {
                    throw LessonJournalError.rule(LessonRejection(.badPractice, "\(id): \(done) done is above the target \(target)"))
                }
                lesson.practice[index] = LessonPracticeItem(itemId: id, label: text, unit: unit, target: target, done: done,
                                                            status: LessonPracticeItem.status(done: done, target: target))
            } else {
                guard itemId == nil else { throw LessonJournalError.drillNotFound(id) }
                guard lesson.practice.count < 30 else { throw LessonJournalError.limitReached("practice") }
                lesson.practice.append(LessonPracticeItem(itemId: id, label: text, unit: unit, target: target, done: 0,
                                                          status: .pending))
            }
        }
        return lesson.practice.first { $0.itemId == id }!
    }

    /// One more done (story 169). At the target it stays done; `by: -1` steps back.
    @discardableResult
    public func tick(_ itemId: String, by step: Int = 1, in lessonId: String) async throws(LessonJournalError) -> LessonPracticeItem {
        let lesson = try await mutate(lessonId) { lesson in
            guard let index = lesson.practice.firstIndex(where: { $0.itemId == itemId }) else {
                throw LessonJournalError.drillNotFound(itemId)
            }
            var item = lesson.practice[index]
            item.done = min(item.target, max(0, item.done + step))
            item.status = LessonPracticeItem.status(done: item.done, target: item.target)
            lesson.practice[index] = item
        }
        return lesson.practice.first { $0.itemId == itemId }!
    }

    // MARK: Missing videos

    /// Checks every clip of a real lesson against the core session store (story 173): a clip whose session is gone,
    /// in Trash, or no longer holds an original with the recorded hash becomes `missing`; one whose original is back
    /// (same hash) becomes `available` again. A Sample lesson never reads the core store and is returned as stored.
    @discardableResult
    public func refreshClipAvailability(in lessonId: String) async throws(LessonJournalError) -> Lesson {
        let current = try await lesson(lessonId)
        guard !current.sample, current.clips.contains(where: { $0.status != .deleted && $0.sessionId.value != nil }) else {
            return current
        }
        guard sessions != nil, verifyMedia != nil else { throw .mediaVerificationUnavailable }
        let sources = try await clipSources(of: current)
        var found: [String: LessonClipStatus] = [:]
        for clip in current.clips where clip.status != .deleted {
            guard let sessionId = clip.sessionId.value else { continue }
            let present = try await holdsOriginal(sessionId, range: clip.window.value, matching: sources.entry(clip.clipId))
            let status: LessonClipStatus = present ? (clip.status == .missing ? .available : clip.status) : .missing
            if status != clip.status { found[clip.clipId] = status }
        }
        guard !found.isEmpty else { return current }
        let changes = found
        return try await mutate(lessonId) { lesson in
            guard lesson.clips == current.clips else { throw LessonJournalError.changedElsewhere(lessonId) }
            for index in lesson.clips.indices {
                if let status = changes[lesson.clips[index].clipId] { lesson.clips[index].status = status }
            }
        }
    }

    /// "Find the video" (the core missing-file repair): re-links a clip to `candidateSessionId` when that session
    /// holds the same original bytes at the recorded timeline coordinates. A legacy receipt without a timeline
    /// cannot prove a repair. The immutable receipt is left untouched when the clip is relinked.
    @discardableResult
    public func findTheVideo(clipId: String, in lessonId: String,
                             candidateSessionId: String) async throws(LessonJournalError) -> LessonClip {
        let current = try await lesson(lessonId)
        guard !current.sample else { throw .sampleIsolation }
        guard let clip = current.clips.first(where: { $0.clipId == clipId }), clip.status != .deleted else {
            throw .clipNotFound(clipId)
        }
        guard let range = clip.window.value, let entry = try await clipSources(of: current).entry(clipId),
              entry.window == range, !entry.files.isEmpty, entry.files.allSatisfy(\.hasTimeline) else {
            throw .cannotVerify(clipId: clipId)
        }
        let candidate = try await session(candidateSessionId)
        guard candidate.sample == nil else { throw .sampleIsolation }
        guard try await holdsOriginal(candidate.id, range: range, matching: entry) else {
            throw .notTheSameVideo(clipId: clipId)
        }
        let lesson = try await mutate(lessonId) { lesson in
            guard let index = lesson.clips.firstIndex(where: { $0.clipId == clipId }), lesson.clips[index] == clip else {
                throw LessonJournalError.changedElsewhere(lessonId)
            }
            let previous = lesson.clips[index].sessionId.value
            lesson.clips[index].sessionId = .value(candidateSessionId)
            lesson.clips[index].status = .available
            if !lesson.sessionIds.contains(candidateSessionId) { lesson.sessionIds.append(candidateSessionId) }
            if let previous, previous != candidateSessionId,
               !lesson.clips.contains(where: { $0.sessionId.value == previous }) {
                lesson.sessionIds.removeAll { $0 == previous }
            }
            guard lesson.sessionIds.count <= 16 else { throw LessonJournalError.limitReached("sessions") }
        }
        return lesson.clips.first { $0.clipId == clipId }!
    }

    // MARK: Internals

    /// Reads the lesson, applies `change`, checks the rules and writes it back, all inside one store transaction.
    @discardableResult
    func mutate(_ lessonId: String, _ change: @escaping @Sendable (inout Lesson) throws -> Void) async throws(LessonJournalError) -> Lesson {
        let name = try await file(of: lessonId).name
        let box = ResultBox()
        try await storeCall {
            try await store.updateRecord(named: name, in: .lessons, of: projectId) { current in
                guard let current else { throw LessonJournalError.lessonNotFound(lessonId) }
                let stored: Lesson
                do { stored = try StudioContractCodec.decode(Lesson.self, from: current) }
                catch { throw LessonJournalError.unreadable(name) }
                var lesson = stored
                try change(&lesson)
                guard lesson != stored else { box.set(stored); return nil }
                box.set(lesson)
                return try Self.encode(lesson)
            }
        }
        return box.value!
    }

    private func updateSources(of lesson: Lesson, _ change: @escaping @Sendable (inout LessonClipSources) throws -> Void) async throws(LessonJournalError) {
        let name = LessonClipSources.fileName(lesson.lessonId)
        let empty = LessonClipSources(lessonId: lesson.lessonId, sample: lesson.sample)
        try await storeCall {
            try await store.updateRecord(named: name, in: .lessons, of: projectId) { current in
                var sources = try current.map { try LessonClipSources.decode($0) } ?? empty
                guard sources.lessonId == lesson.lessonId, sources.sample == lesson.sample else {
                    throw LessonJournalError.unreadable(name)
                }
                try change(&sources)
                return try sources.encoded()
            }
        }
    }

    func clipSources(of lesson: Lesson) async throws(LessonJournalError) -> LessonClipSources {
        let name = LessonClipSources.fileName(lesson.lessonId)
        guard let bytes = try await storeCall({ try await store.record(named: name, in: .lessons, of: projectId) }) else {
            return LessonClipSources(lessonId: lesson.lessonId, sample: lesson.sample)
        }
        do {
            let sources = try LessonClipSources.decode(bytes)
            guard sources.lessonId == lesson.lessonId, sources.sample == lesson.sample else {
                throw LessonJournalError.unreadable(name)
            }
            return sources
        } catch { throw .unreadable(name) }
    }

    private func holdsOriginal(_ sessionId: String, range: StudioIntervalUs?,
                               matching entry: LessonClipSources.Entry?) async throws(LessonJournalError) -> Bool {
        guard let range, let entry, entry.window == range,
              !entry.files.isEmpty, entry.files.allSatisfy(\.hasTimeline) else { return false }
        do {
            let document = try await session(sessionId)
            guard document.sample == nil else { return false }
            let files = try await verifiedFiles(of: document, range: range)
            return LessonClipSources.matches(entry, actual: files)
        } catch .sessionNotFound, .noVideo, .badRange {
            return false
        }
    }

    private func verifiedFiles(of document: SessionDocument, range: StudioIntervalUs) async throws(LessonJournalError) -> [LessonClipSources.File] {
        guard let verifyMedia else { throw .mediaVerificationUnavailable }
        do {
            return try await LessonClipSources.verify(document, range: range, with: verifyMedia)
        } catch let error as LessonJournalError {
            throw error
        } catch is CancellationError {
            throw .mediaVerificationUnavailable
        } catch {
            throw .noVideo(document.id)
        }
    }

    private func session(_ id: String) async throws(LessonJournalError) -> SessionDocument {
        guard let sessions else { throw .sessionNotFound(id) }
        do { return try await sessions.load(id) }
        catch SessionStoreError.notFound { throw .sessionNotFound(id) }
        catch SessionStoreError.invalidID { throw .sessionNotFound(id) }
        catch { throw .unreadable(id) }
    }

    private func observation(_ id: String, in projectId: String) async throws(LessonJournalError) -> Observation {
        let names = try await storeCall { try await store.recordNames(in: .observations, of: projectId) }
        for name in names {
            guard let bytes = try await storeCall({ try await store.record(named: name, in: .observations, of: projectId) }),
                  (try? StudioRecordHeader(json: bytes))?.schemaVersion.kind == "observation",
                  let observation = try? StudioContractCodec.decode(Observation.self, from: bytes),
                  observation.observationId == id else { continue }
            return observation
        }
        throw .observationNotFound(id)
    }

    private func project() async throws(LessonJournalError) -> StudioProject {
        try await storeCall { try await store.project(projectId) }
    }

    struct LessonFile: Sendable {
        let name: String
        let lesson: Lesson
    }

    /// Every `jovra.lesson/1` file of the project (the clip-sources files beside them are skipped).
    func files() async throws(LessonJournalError) -> [LessonFile] {
        let names = try await storeCall { try await store.recordNames(in: .lessons, of: projectId) }
        var out: [LessonFile] = []
        for name in names where !name.hasSuffix(LessonClipSources.suffix) {
            guard let bytes = try await storeCall({ try await store.record(named: name, in: .lessons, of: projectId) }),
                  (try? StudioRecordHeader(json: bytes))?.schemaVersion.kind == "lesson" else { continue }
            do { out.append(LessonFile(name: name, lesson: try StudioContractCodec.decode(Lesson.self, from: bytes))) }
            catch { throw .unreadable(name) }
        }
        return out
    }

    private func file(of lessonId: String) async throws(LessonJournalError) -> LessonFile {
        guard let found = try await files().first(where: { $0.lesson.lessonId == lessonId }) else {
            throw .lessonNotFound(lessonId)
        }
        return found
    }

    @discardableResult
    private func storeCall<T>(_ body: () async throws -> T) async throws(LessonJournalError) -> T {
        do { return try await body() }
        catch let error as LessonJournalError { throw error }
        catch let error as LessonRejection { throw .rule(error) }
        catch let error as StudioProjectStoreError { throw .store(error) }
        catch { throw .unreadable(String(describing: error)) }
    }

    static func encode(_ lesson: Lesson) throws(LessonJournalError) -> Data {
        do throws(LessonRejection) { try LessonRules.check(lesson) } catch { throw .rule(error) }
        do { return try StudioContractCodec.encode(lesson) } catch { throw .badText }
    }

    static func text(optional value: String?) throws(LessonJournalError) -> String? {
        guard let value else { return nil }
        return try text(value)
    }

    static func text(_ value: String) throws(LessonJournalError) -> String {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= maxTextLength else {
            throw .badText
        }
        return value
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: now())
    }
}

/// Carries the lesson a store transaction produced out of its `@Sendable` closure.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Lesson?
    var value: Lesson? { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ lesson: Lesson) { lock.lock(); stored = lesson; lock.unlock() }
}
