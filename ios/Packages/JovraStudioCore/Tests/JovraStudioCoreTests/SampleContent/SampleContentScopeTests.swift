import Foundation
import Testing
import JovraCore
import JovraStudioCore

/// Story 15 and the core sample-scope rule: installing the Studio sample changes none of the player's numbers. The
/// core stats (LibrarySummary, StatsEngine through it) and trends (TrendPool) queries are run on the core session
/// store before and after installation and must be equal. The goals query (core T48) is not an ancestor of this
/// ticket and is not run here; the S34 status report lists it as not run.
@Suite("Studio sample content: the sample-scope rule")
struct SampleContentScopeTests {
    private struct Numbers: Equatable {
        let summary: LibrarySummary
        let realTrend: TrendSeries
        let sampleTrend: TrendSeries
        let sessionIDs: [String]
    }

    /// The core library numbers: the summary Home and Progress read, and a 4-week first-serve-in trend in both
    /// scopes, built from the player's (isSelf) first serves of every match in the store.
    private static func numbers(_ sessions: SessionStore) async throws -> Numbers {
        let listed = try await sessions.list(.init(includeTrashed: true))
        var documents: [SessionDocument] = []
        for summary in listed { documents.append(try await sessions.load(summary.id)) }
        let summary = try LibrarySummary.compute(sessions: documents, equipment: [])
        var trendSessions: [TrendSession] = []
        for document in documents where document.match != nil {
            guard let me = document.players.first(where: \.isSelf), let sides = document.sides else { continue }
            let stats = try StatsEngine.compute(ScoringEngine.fold(ScoringInput(session: document)))
            let ratio = sides.A.contains(me.id) ? stats.sides.A.firstServeIn : stats.sides.B.firstServeIn
            let day = try CalendarDay(String(document.createdAt.prefix(10)))
            trendSessions.append(TrendSession(id: document.id, date: day, comparableKind: "singlesMatch",
                                              sample: document.sample != nil, n: ratio.n, d: ratio.d))
        }
        let asOf = try CalendarDay("2026-10-31")
        return Numbers(
            summary: summary,
            realTrend: try TrendPool.bucketed(trendSessions, range: .threeMonths, asOf: asOf, comparableKind: "singlesMatch", scope: .real),
            sampleTrend: try TrendPool.bucketed(trendSessions, range: .threeMonths, asOf: asOf, comparableKind: "singlesMatch", scope: .sample),
            sessionIDs: listed.map(\.id))
    }

    @Test("with real and core sample sessions in the library, installing the Studio sample leaves stats and trends unchanged")
    func statsAndTrendsUnchanged() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let sessions = try SessionStore(root: scratch.core)
        for document in try CoreFixtureSessions.realCopies() { try await sessions.create(document) }
        try await SampleContent(library: CoreFixtureSessions.sampleLibrary()).install(into: sessions)
        let before = try await Self.numbers(sessions)
        // The library has real numbers to protect, and the core sample is present but out of the real scope.
        #expect(before.summary.sample == false)
        #expect(before.summary.sessionCount == 8)
        #expect(before.realTrend.sessionCount > 0)
        #expect(before.sampleTrend.sessionCount > 0)

        let studio = try scratch.store(sessions: sessions)
        try await SampleContentTests.content().install(into: studio)
        let after = try await Self.numbers(sessions)

        #expect(after == before)
        #expect(try await studio.projects(sample: false).isEmpty)
    }

    @Test("with only real sessions, installing and removing the Studio sample adds no session and changes no number")
    func realOnlyLibrary() async throws {
        let scratch = try ProjectScratch(); defer { scratch.cleanUp() }
        let sessions = try SessionStore(root: scratch.core)
        for document in try CoreFixtureSessions.realCopies() { try await sessions.create(document) }
        let before = try await Self.numbers(sessions)
        let studio = try scratch.store(sessions: sessions)
        let content = try SampleContentTests.content()

        try await content.install(into: studio)
        #expect(try await Self.numbers(sessions) == before)
        try await content.remove(from: studio)
        #expect(try await Self.numbers(sessions) == before)
        #expect(before.sampleTrend.sessionCount == 0)
    }
}
