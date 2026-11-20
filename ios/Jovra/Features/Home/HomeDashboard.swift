import Foundation
import JovraCore

/// Everything Home (S03) shows, computed from the stored session documents and nothing else (CLAUDE.md rule 1).
///
/// The sample-scope rule (`SampleScope`) decides what counts: Sample sessions count only when no session of the
/// player's own exists, and then every block is badged Sample. The tiles and the trend cover the four weeks ending
/// on the latest session's day (`TrendPool.bucketBounds(.fourWeeks)`), the same window the sample library oracle
/// (spec/fixtures/sample/library/library.expected.json) uses. Percentages come from the engines' `RateRatio`s:
/// first serves in from `StatsEngine`, the weekly trend pooled by `TrendPool` (numerators and denominators summed,
/// never averaged; buckets under the minimum denominator hidden), the delta from the two displayed integers.
struct HomeDashboard: Equatable, Sendable {
    /// The player's own name for the greeting: the `isSelf` player of the newest session in scope.
    var playerName: String?
    var content: Content
    /// The next useful actions, in order: resume an interrupted recording, finish reviewing, back up.
    var nextSteps: [HomeNextStep]

    enum Content: Equatable, Sendable {
        /// No sessions: one inviting state replaces the tiles, the latest session and the trend.
        case empty
        case populated(Overview)
    }

    struct Overview: Equatable, Sendable {
        /// Every number below is Sample data (the whole scope is sample): tiles and chart carry the badge.
        var isSample: Bool
        /// The four weeks the counts and the trend cover, ending on the latest session's day.
        var window: ClosedRange<CalendarDay>
        var sessionCount: Int
        var onCourtSeconds: Int
        var firstServes: FirstServes
        var latest: LatestSession
        var trend: Trend
    }

    /// The player's first serves in for the latest match (screen spec open question 7: "Latest match").
    struct FirstServes: Equatable, Sendable {
        /// nil when there is no match in scope ("No match yet").
        var matchID: String?
        /// A zero denominator when there is nothing to divide by; the tile then shows an em dash.
        var ratio: RateRatio
        /// The weakest provenance of the points it counts.
        var provenance: Provenance?
    }

    enum MatchFormat: Equatable, Sendable { case singles, doubles }

    struct LatestSession: Equatable, Sendable {
        var id: String
        var title: String
        var kind: SessionDocumentSessionKind
        /// nil for a session without a match.
        var format: MatchFormat?
        /// "6–4 6–3" (en dashes), from the scoring engine's final state; nil without a scored match.
        var scoreline: String?
        /// The winning side's player names, for VoiceOver ("Jon won 6–4, 6–3").
        var winnerNames: String?
        var durationSeconds: Int
        var startedAt: Date?
        var isSample: Bool
        /// Points awaiting the player's decision (GLOSSARY: Needs review); shown as the card's status line.
        var needsReview: Int
        var mediaIDs: [String]
    }

    struct Trend: Equatable, Sendable {
        var weeks: [TrendBucket]
        var state: TrendState
        var headline: TrendHeadline?
        /// Some counted point is an automatic estimate nobody has reviewed yet.
        var includesEstimated: Bool
    }

    static func make(sessions documents: [SessionDocument], now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> HomeDashboard {
        let scope = SampleScope.sessions(documents)
        let dated = scope.items.compactMap { document in day(of: document).map { Dated(document: document, day: $0) } }
            .sorted { ($0.day, $0.document.recording.startedAt ?? $0.document.createdAt, $0.document.id)
                < ($1.day, $1.document.recording.startedAt ?? $1.document.createdAt, $1.document.id) }
        guard let newest = dated.last else { return HomeDashboard(playerName: nil, content: .empty, nextSteps: []) }
        let window = TrendPool.bucketBounds(.fourWeeks, asOf: newest.day)
        let range = window[0].from...newest.day
        let inWindow = dated.filter { range.contains($0.day) }
        let matches = dated.filter { $0.document.sessionKind == .match && $0.document.match != nil }
        let latestMatch = matches.last
        let overview = Overview(
            isSample: scope.isSample,
            window: range,
            sessionCount: inWindow.count,
            onCourtSeconds: inWindow.reduce(0) { $0 + duration(of: $1.document) / 1000 },
            firstServes: firstServes(latestMatch?.document),
            latest: latest(newest.document),
            trend: trend(matches, sample: scope.isSample, asOf: newest.day, format: latestMatch.map { format(of: $0.document) }))
        return HomeDashboard(playerName: newest.document.players.first(where: \.isSelf)?.displayName,
                             content: .populated(overview),
                             nextSteps: HomeNextStep.steps(for: dated.map(\.document)))
    }

    private struct Dated {
        var document: SessionDocument
        var day: CalendarDay
    }

    // MARK: Tiles

    private static func firstServes(_ match: SessionDocument?) -> FirstServes {
        let none = (try? Percent.ratio(n: 0, d: 0)) ?? RateRatio(n: 0, d: 0, pct: .null, display: FractionPresentation.noData)
        guard let match, let side = selfSide(of: match), let timeline = try? ScoringEngine.fold(ScoringInput(session: match)),
              let stat = try? StatsEngine.stat(.firstServeIn(side), in: timeline, sample: match.sample != nil)
        else { return FirstServes(matchID: match?.id, ratio: none, provenance: nil) }
        guard case .ratio(let ratio)? = stat.value else { return FirstServes(matchID: match.id, ratio: none, provenance: nil) }
        return FirstServes(matchID: match.id, ratio: ratio, provenance: stat.evidence.provenance)
    }

    private static func latest(_ document: SessionDocument) -> LatestSession {
        let timeline = document.match == nil ? nil : try? ScoringEngine.fold(ScoringInput(session: document))
        let winner = timeline?.match.winner.value.flatMap { side -> String? in
            let ids = side == .a ? document.sides?.A : document.sides?.B
            let names = document.players.filter { ids?.contains($0.id) == true }.map(\.displayName)
            return names.isEmpty ? nil : ListFormatter.localizedString(byJoining: names)
        }
        let needsReview = timeline.flatMap { try? StatsEngine.compute($0).review.needsReview } ?? 0
        return LatestSession(
            id: document.id, title: document.title, kind: document.sessionKind,
            format: document.match == nil ? nil : format(of: document),
            scoreline: timeline?.match.scoreline.value.map(displayScoreline),
            winnerNames: winner, durationSeconds: duration(of: document) / 1000,
            startedAt: (document.recording.startedAt ?? document.createdAt).flatMapISO8601,
            isSample: document.sample != nil, needsReview: needsReview,
            mediaIDs: document.sample?.mediaIds ?? [])
    }

    // MARK: Trend

    private static func trend(_ matches: [Dated], sample: Bool, asOf: CalendarDay, format: MatchFormat?) -> Trend {
        var estimated = false
        let sessions: [TrendSession] = matches.compactMap { entry in
            guard let side = selfSide(of: entry.document),
                  let timeline = try? ScoringEngine.fold(ScoringInput(session: entry.document)),
                  let stat = try? StatsEngine.stat(.firstServeIn(side), in: timeline, sample: sample),
                  case .ratio(let ratio)? = stat.value else { return nil }
            if stat.evidence.provenance == .estimated, stat.evidence.unreviewedCount > 0 { estimated = true }
            return TrendSession(id: entry.document.id, date: entry.day, comparableKind: kindKey(self.format(of: entry.document)),
                                sample: entry.document.sample != nil, n: ratio.n, d: ratio.d)
        }
        guard let format,
              let series = try? TrendPool.bucketed(sessions, range: .fourWeeks, asOf: asOf, comparableKind: kindKey(format),
                                                   scope: sample ? .sample : .real)
        else { return Trend(weeks: [], state: .noData, headline: nil, includesEstimated: false) }
        return Trend(weeks: series.buckets, state: series.state, headline: series.headline.value, includesEstimated: estimated)
    }

    private static func kindKey(_ format: MatchFormat) -> String {
        format == .singles ? "singlesMatch" : "doublesMatch"
    }

    // MARK: Session facts

    /// The session's calendar day on the wall clock where it was played.
    static func day(of document: SessionDocument) -> CalendarDay? {
        guard let instant = (document.recording.startedAt ?? document.createdAt).flatMapISO8601 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = document.recording.timeZone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return try? CalendarDay(year: year, month: month, day: day)
    }

    /// Milliseconds recorded: the recording's length, else its finalized segments.
    static func duration(of document: SessionDocument) -> Int {
        document.recording.durationMs ?? document.recording.segments.filter(\.finalized).reduce(0) { $0 + $1.durationMs }
    }

    private static func selfSide(of document: SessionDocument) -> Side? {
        guard let me = document.players.first(where: \.isSelf), let sides = document.sides else { return nil }
        if sides.A.contains(me.id) { return .a }
        if sides.B.contains(me.id) { return .b }
        return nil
    }

    private static func format(of document: SessionDocument) -> MatchFormat {
        max(document.sides?.A.count ?? 1, document.sides?.B.count ?? 1) > 1 ? .doubles : .singles
    }

    /// The engine's "6-4 7-6(5)" with en dashes between games, as the scoreboard prints it.
    static func displayScoreline(_ scoreline: String) -> String {
        scoreline.replacingOccurrences(of: "-", with: "–")
    }
}

private extension String {
    var flatMapISO8601: Date? {
        ISO8601DateFormatter().date(from: self) ?? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: self)
        }()
    }
}
