import Foundation
import JovraCore

/// A lesson that breaks a `jovra.lesson/1` record rule (the reference layer of the invalid cases), with the code the
/// reference gives (`spec/reference/studio/records.py` check_lesson).
public struct LessonRejection: Error, Equatable, CustomStringConvertible, Sendable {
    public enum Code: String, Sendable {
        case duplicateId, unknownClip, unattributedCoach, clipWithoutSource, badInterval, provenanceMismatch
        case badPractice, badShare
    }

    public let code: Code
    public let message: String

    public init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { "\(code.rawValue): \(message)" }
}

/// Who wrote a note, as entered. There are exactly two authors: the player (`user`) and the lesson's coach. JOVRA is
/// never an author: `LessonNoteAuthor` has no case for it, so a note authored by JOVRA cannot be constructed, and the
/// exhaustive switch in `attribution` means a new author case cannot be added without deciding how it is attributed.
public enum LessonAttribution: Equatable, Sendable {
    case player
    /// The coach's words as the player or coach entered them, under the lesson's coach name.
    case coach(displayName: String)
}

extension Lesson {
    /// How `note` is attributed, or `unattributedCoach` when a coach note has no coach to attribute it to (story 171).
    public func attribution(of note: LessonNote) throws(LessonRejection) -> LessonAttribution {
        switch note.author {
        case .user: return .player
        case .coach:
            guard let coach = coach.value else {
                throw LessonRejection(.unattributedCoach, "a coach note needs the lesson's coach")
            }
            return .coach(displayName: coach.displayName)
        }
    }
}

extension LessonPracticeItem {
    /// The only status a count allows: done at the target, pending at zero, in progress between.
    public static func status(done: Int, target: Int) -> LessonPracticeItemStatus {
        done == target ? .done : (done == 0 ? .pending : .inProgress)
    }
}

/// The record rules of a lesson beyond its schema. Every write through `LessonJournal` passes them.
public enum LessonRules {
    public static func check(_ lesson: Lesson) throws(LessonRejection) {
        let clipIds = lesson.clips.map(\.clipId)
        try unique(clipIds, "clip")
        try unique(lesson.notes.map(\.noteId), "note")
        try unique(lesson.cues.map(\.cueId), "cue")
        try unique(lesson.practice.map(\.itemId), "practice item")
        let clips = Set(clipIds)
        for note in lesson.notes {
            guard note.clipIds.allSatisfy(clips.contains) else {
                throw LessonRejection(.unknownClip, "note \(note.noteId) links only this lesson's clips")
            }
            _ = try lesson.attribution(of: note)
        }
        for clip in lesson.clips {
            guard clip.sourceId.value != nil || clip.sessionId.value != nil else {
                throw LessonRejection(.clipWithoutSource, "clip \(clip.clipId) points at a source or session")
            }
            if let window = clip.window.value, window.startUs >= window.endUs {
                throw LessonRejection(.badInterval, "clip \(clip.clipId) window")
            }
        }
        for cue in lesson.cues {
            guard clips.contains(cue.clipId) else {
                throw LessonRejection(.unknownClip, "cue \(cue.cueId) is anchored to one of this lesson's clips")
            }
            if cue.provenance == .estimated, cue.observationId.value == nil || cue.reviewedBy.value != nil {
                throw LessonRejection(.provenanceMismatch, "an estimated cue comes from an observation and is not reviewed")
            }
            if cue.provenance == .reviewed, cue.reviewedBy.value == nil {
                throw LessonRejection(.provenanceMismatch, "a reviewed cue names its reviewer")
            }
        }
        for item in lesson.practice {
            guard item.done <= item.target else {
                throw LessonRejection(.badPractice, "\(item.itemId): done cannot exceed the target")
            }
            let expected = LessonPracticeItem.status(done: item.done, target: item.target)
            guard item.status == expected else {
                throw LessonRejection(.badPractice, "\(item.itemId): status must be \(expected.rawValue)")
            }
        }
        if lesson.share.mode == .private, !lesson.share.grantIds.isEmpty {
            throw LessonRejection(.badShare, "a private lesson has no grants")
        }
    }

    private static func unique(_ ids: [String], _ what: String) throws(LessonRejection) {
        var seen: Set<String> = []
        for id in ids where !seen.insert(id).inserted {
            throw LessonRejection(.duplicateId, "duplicate \(what) id \(id)")
        }
    }
}
