import Foundation

extension ScoringEngine {
    public static func diff(previous: MatchTimeline, current: MatchTimeline) -> TimelineChanges {
        let oldTB = Set(previous.games.filter { $0.kind == .tiebreak }.map(\.set))
        let newTB = Set(current.games.filter { $0.kind == .tiebreak }.map(\.set))
        let oldPoints = Dictionary(uniqueKeysWithValues: previous.points.map { ($0.id, $0) })
        let changed = current.points.filter { point in
            guard let old = oldPoints[point.id] else { return false }
            return point.determined != old.determined || point.afterMatchEnd != old.afterMatchEnd || point.set != old.set || point.game != old.game ||
                point.gameInSet != old.gameInSet || point.tiebreak != old.tiebreak || point.pointInGame != old.pointInGame || point.server != old.server ||
                point.receiver != old.receiver || point.serverSide != old.serverSide || point.courtSide != old.courtSide || point.ends != old.ends ||
                point.before != old.before || point.call != old.call || point.pressure != old.pressure || point.after != old.after
        }.map(\.id)
        return .init(tiebreakAppeared: newTB.subtracting(oldTB).sorted(), tiebreakVanished: oldTB.subtracting(newTB).sorted(),
            matchIncomplete: previous.match.status == .completed && current.match.status == .inProgress, recalculatedPointIds: changed)
    }
    public static func checkpoints(_ input: ScoringInput, afterSeqs: [Int]) throws -> [MatchTimeline] {
        var previous: MatchTimeline?, results: [MatchTimeline] = []
        for seq in afterSeqs {
            var prefix = input; prefix.log = input.log.filter { $0.seq <= seq }
            var result = try fold(prefix)
            result.changes = previous.map { .value(diff(previous: $0, current: result)) } ?? .null
            results.append(result); previous = result
        }
        return results
    }
}

/// One scoring value that an edit changed: the "Recalculated" indicator (ios-v1-spec, Recalculation). Stats are not
/// listed here; the stats half of the diff is computed from the two timelines by StatsEngine.
public enum ChangedValue: Equatable, Hashable, Sendable {
    /// A point whose derived record changed, appeared or disappeared. The id is the effective id after the edit
    /// (the correcting event's id for a corrected point), or the id before it for a removed point.
    case point(id: String)
    /// A game, keyed by its set and its position in that set, whose record changed, appeared or disappeared.
    case game(set: Int, gameInSet: Int)
    /// A set whose score, tie-break, winner or completion changed, appeared or disappeared.
    case set(index: Int)
    /// The match result: status, winner, sets won or scoreline.
    case result
}

extension ScoringEngine {
    /// Lists what an edit changed between two complete folds, in order: points (after-edit order, then removed
    /// points), games and sets (ascending), then the result. Points are matched through the supersede history, so
    /// a corrected point is compared with the version it replaced.
    public static func diff(before: MatchTimeline, after: MatchTimeline) -> [ChangedValue] {
        let old = pointsByOrigin(before), new = pointsByOrigin(after)
        var changes: [ChangedValue] = new.order.compactMap { origin in
            guard let point = new.points[origin] else { return nil }
            guard let previous = old.points[origin], sameDerivedRecord(previous, point) else { return .point(id: point.id) }
            return nil
        }
        changes += old.order.filter { new.points[$0] == nil }.compactMap { old.points[$0].map { .point(id: $0.id) } }
        let oldGames = Dictionary(before.games.map { (GameKey(set: $0.set, game: $0.gameInSet), $0) }, uniquingKeysWith: { first, _ in first })
        let newGames = Dictionary(after.games.map { (GameKey(set: $0.set, game: $0.gameInSet), $0) }, uniquingKeysWith: { first, _ in first })
        changes += Set(oldGames.keys).union(newGames.keys).sorted().filter { oldGames[$0] != newGames[$0] }
            .map { .game(set: $0.set, gameInSet: $0.game) }
        let oldSets = Dictionary(before.sets.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        let newSets = Dictionary(after.sets.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        changes += Set(oldSets.keys).union(newSets.keys).sorted().filter { oldSets[$0] != newSets[$0] }.map { .set(index: $0) }
        let a = before.match, b = after.match
        if a.status != b.status || a.winner != b.winner || a.setsWon != b.setsWon || a.scoreline != b.scoreline { changes.append(.result) }
        return changes
    }

    private struct GameKey: Hashable, Comparable {
        let set: Int, game: Int
        static func < (l: Self, r: Self) -> Bool { (l.set, l.game) < (r.set, r.game) }
    }

    /// Points keyed by the id of the event that first created them, following `history.superseded` backwards.
    private static func pointsByOrigin(_ timeline: MatchTimeline) -> (order: [String], points: [String: TimelinePointRecord]) {
        let replacedBy = Dictionary(timeline.history.superseded.map { ($0.by, $0.id) }, uniquingKeysWith: { first, _ in first })
        func origin(_ id: String) -> String {
            var current = id, visited: Set<String> = []
            while let previous = replacedBy[current], visited.insert(current).inserted { current = previous }
            return current
        }
        var order: [String] = [], points: [String: TimelinePointRecord] = [:]
        for point in timeline.points { let key = origin(point.id); order.append(key); points[key] = point }
        return (order, points)
    }

    private static func sameDerivedRecord(_ lhs: TimelinePointRecord, _ rhs: TimelinePointRecord) -> Bool {
        var normalized = lhs; normalized.id = rhs.id
        return normalized == rhs
    }
}
