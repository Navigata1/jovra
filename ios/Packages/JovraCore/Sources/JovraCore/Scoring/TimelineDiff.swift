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
