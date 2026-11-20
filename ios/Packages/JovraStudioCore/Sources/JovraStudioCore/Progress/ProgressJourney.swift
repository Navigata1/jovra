import Foundation
import JovraCore

/// One lesson on the progress journey: its date, title and focus line (the journey's caption), with its clip count
/// and practice progress.
public struct ProgressMilestone: Equatable, Sendable {
    public let lessonId: String
    public let date: String
    public let title: String
    /// The lesson's focus line ("Find the rhythm"); nil when none was entered. Never the title.
    public let focusLine: String?
    public let clipCount: Int
    public let practice: LessonPracticeSummary
    /// Sample lessons are always shown labelled "Sample".
    public let sample: Bool
}

/// A stat a Progress Story can compare: its stat definition id and the core stats line it reads (a fraction).
public struct ProgressStat: Hashable, Sendable {
    public let statDefinitionId: String
    public let key: StatKey

    public init(statDefinitionId: String, key: StatKey) {
        self.statDefinitionId = statDefinitionId
        self.key = key
    }
}

extension ProgressStoryBuilder {
    /// The lessons in order (date, then id), each with its focus line.
    public static func journey(_ lessons: [Lesson]) -> [ProgressMilestone] {
        lessons.sorted { ($0.date, $0.lessonId) < ($1.date, $1.lessonId) }.map { lesson in
            ProgressMilestone(lessonId: lesson.lessonId, date: lesson.date, title: lesson.title,
                              focusLine: lesson.focus.value, clipCount: lesson.clips.count,
                              practice: lesson.practiceSummary, sample: lesson.sample)
        }
    }

    /// A scope computed now from the stored events of `sessions` by the core fold and StatsEngine: the stat's
    /// numerators and denominators are summed (never averaged) and the provenance is the weakest contributing one.
    /// Nothing is cached, so a correction to a session changes every comparison that reads it (story 180).
    public static func scope(_ stat: ProgressStat, date: String, sessions: [SessionDocument], method: ProgressMethod,
                             selection: ProgressSelectionRule = .all) throws(ProgressRejection) -> ProgressScope {
        guard let first = sessions.first else { throw ProgressRejection(.badScope, "a scope needs a session") }
        guard sessions.allSatisfy({ $0.sessionKind == first.sessionKind }) else {
            throw ProgressRejection(.badScope, "the sessions of one scope are one session kind")
        }
        guard sessions.allSatisfy({ ($0.sample == nil) == (first.sample == nil) }) else {
            throw ProgressRejection(.badScope, "Sample and real sessions never share a scope")
        }
        var parts: [(n: Int, d: Int)] = []
        var provenances: [Provenance] = []
        for session in sessions {
            let line: StatLine?
            do {
                line = try StatsEngine.lines(ScoringEngine.fold(ScoringInput(session: session)), sample: session.sample != nil)
                    .first { $0.key == stat.key }
            } catch { throw ProgressRejection(.badScope, "session \(session.id) cannot be folded: \(error)") }
            guard let line else { throw ProgressRejection(.badScope, "no stat line \(stat.key)") }
            switch line.stat.value {
            case .ratio(let ratio)?: parts.append((ratio.n, ratio.d))
            case nil: parts.append((0, 0))
            case .count?: throw ProgressRejection(.badScope, "\(stat.key) is a count, not a fraction")
            }
            if let provenance = line.stat.evidence.provenance { provenances.append(provenance) }
        }
        let pooled: RateRatio
        do { pooled = try Percent.pool(parts) } catch { throw ProgressRejection(.badFraction, "\(stat.key)") }
        let weakest = provenances.min { rank($0) < rank($1) } ?? .manual
        return ProgressScope(date: date, sessionIds: sessions.map(\.id), sessionKind: first.sessionKind.rawValue,
                             statDefinitionId: stat.statDefinitionId, method: method, selectionRule: selection,
                             numerator: pooled.n, denominator: pooled.d, provenance: weakest)
    }

    private static func rank(_ provenance: Provenance) -> Int {
        switch provenance { case .estimated: 0; case .manual: 1; case .reviewed: 2; case .validated: 3 }
    }
}
