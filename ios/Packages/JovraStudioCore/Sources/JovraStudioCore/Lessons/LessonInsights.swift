import Foundation
import JovraCore

extension LessonJournal {
    /// The Progress Story comparison between two lessons for one stat, read now from the core session store: each
    /// lesson's scope is its sessions' stored events folded by the core engine, dated by the lesson. A correction to
    /// any of those sessions is in the next comparison (story 180); nothing is cached in the lesson.
    public func compare(_ stat: ProgressStat, method: ProgressMethod, earlier earlierLessonId: String,
                        later laterLessonId: String, selection: ProgressSelectionRule = .all) async throws -> ProgressComparison {
        let earlier = try await scope(stat, method: method, lessonId: earlierLessonId, selection: selection)
        let later = try await scope(stat, method: method, lessonId: laterLessonId, selection: selection)
        return try ProgressStoryBuilder.compare(stat.statDefinitionId, earlier: earlier, later: later)
    }

    /// The Progress Story journey of this project's lessons.
    public func journey() async throws(LessonJournalError) -> [ProgressMilestone] {
        ProgressStoryBuilder.journey(try await lessons())
    }

    private func scope(_ stat: ProgressStat, method: ProgressMethod, lessonId: String,
                       selection: ProgressSelectionRule) async throws -> ProgressScope {
        let lesson = try await lesson(lessonId)
        guard !lesson.sample, let sessions else { throw LessonJournalError.sampleIsolation }
        var documents: [SessionDocument] = []
        for id in lesson.sessionIds {
            do { documents.append(try await sessions.load(id)) }
            catch SessionStoreError.notFound { throw LessonJournalError.sessionNotFound(id) }
        }
        return try ProgressStoryBuilder.scope(stat, date: lesson.date, sessions: documents, method: method, selection: selection)
    }
}
