import Foundation

/// What leaving the lesson screen does (story 178): with no unsaved edits it simply leaves; with unsaved edits it asks
/// to save or discard first (the leave guard sheet), so notes are never lost.
public enum LessonLeaveDecision: Equatable, Sendable {
    case leave
    case askToSaveOrDiscard
}

/// An edit of one lesson's fields, held by the screen until it is saved or discarded. `LessonJournal.save` writes it
/// only while the stored lesson is still `original`.
public struct LessonEdit: Equatable, Sendable {
    /// The lesson as stored when the edit began.
    public let original: Lesson
    /// The fields being edited. Use the journal's relationship operations to change session, clip, cue or film links.
    public var draft: Lesson

    public init(original: Lesson) {
        self.original = original
        draft = original
    }

    public var hasUnsavedChanges: Bool { draft != original }

    public var leaveDecision: LessonLeaveDecision { hasUnsavedChanges ? .askToSaveOrDiscard : .leave }

    /// Drops the unsaved changes; nothing is written.
    public mutating func discard() { draft = original }
}

/// The practice checklist's progress line, "2 of 3 drills complete" (story 169).
public struct LessonPracticeSummary: Equatable, Sendable {
    public let complete: Int
    public let total: Int

    public init(complete: Int, total: Int) {
        self.complete = complete
        self.total = total
    }

    public var text: String { "\(complete) of \(total) \(total == 1 ? "drill" : "drills") complete" }
}

extension Lesson {
    public var practiceSummary: LessonPracticeSummary {
        LessonPracticeSummary(complete: practice.filter { $0.status == .done }.count, total: practice.count)
    }

    /// Notes not yet checked by a person (story 170): they show "Not reviewed".
    public var unreviewedNotes: [LessonNote] { notes.filter { $0.provenance == .manual } }
}
