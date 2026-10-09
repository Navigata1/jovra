import Foundation

public enum StatsError: Error, Equatable, Sendable { case invalidTimeline, overflow }

/// Every number comes from the effective fold; no analysis or network work runs here.
public enum StatsEngine {
    public static func compute(_ timeline: MatchTimeline) throws -> StatsResult {
        let counted = timeline.points.filter { $0.determined && !$0.afterMatchEnd && $0.winner.value != nil }
        guard counted.allSatisfy({ $0.serverSide.value != nil && $0.server.value != nil && $0.pressure.value != nil }) else {
            throw StatsError.invalidTimeline
        }
        let played = counted.filter { $0.kind == .point }
        let games = timeline.games.filter(\.complete)
        let a = try sideStats(.a, counted: counted, played: played, games: games)
        let b = try sideStats(.b, counted: counted, played: played, games: games)
        var servers: [String: ServeStats] = [:]
        if timeline.match.doubles {
            for (id, points) in Dictionary(grouping: played, by: { $0.server.value! }) {
                servers[id] = try serveStats(points)
            }
        }
        let shots = played.compactMap { $0.strokeCount.value }
        var totalShots = 0
        for count in shots {
            guard count >= 0 else { throw StatsError.invalidTimeline }
            let next = totalShots.addingReportingOverflow(count)
            guard !next.overflow else { throw StatsError.overflow }; totalShots = next.partialValue
        }
        let rally = played.map { $0.rallyLength.value }
        let review = timeline.points.filter { $0.kind == .point && !$0.afterMatchEnd }
        let reviewed = review.filter { $0.reviewState == .reviewed }.count
        let timed = counted.filter { $0.tStartMs != nil && $0.tEndMs != nil }
        guard timed.allSatisfy({ $0.tStartMs! >= 0 && $0.tEndMs! >= $0.tStartMs! }) else { throw StatsError.invalidTimeline }
        let duration = !timed.isEmpty && timed.count == counted.count ? timed.map { $0.tEndMs! }.max()! - timed.map { $0.tStartMs! }.min()! : nil
        let momentum = counted.indices.map { index in
            let window = counted[max(0, index - 9)...index]
            return StatsMomentumPair(pointsWon: window.filter { $0.winner.value == .a }.count, pointsInWindow: window.count)
        }
        return .init(provisional: timeline.match.provisional, countedPoints: counted.count,
            excludedPoints: timeline.points.filter { !$0.afterMatchEnd }.count - counted.count,
            sides: .init(A: a, B: b), servers: servers,
            shots: .init(total: totalShots, pointsWithStrokeCount: shots.count),
            rallyLength: .init(value0_4: rally.filter { $0.map { (0...4).contains($0) } ?? false }.count,
                              value5_8: rally.filter { $0.map { (5...8).contains($0) } ?? false }.count,
                              value9_: rally.filter { $0.map { $0 >= 9 } ?? false }.count,
                              unknown: rally.filter { $0 == nil }.count),
            review: .init(reviewed: reviewed, needsReview: review.filter { $0.reviewState == .needsReview }.count,
                          unreviewed: review.filter { $0.reviewState == .unreviewed }.count,
                          completion: try Percent.ratio(n: reviewed, d: review.count)),
            durationMs: .init(duration), momentum: .init(window: 10, series: momentum))
    }

    private static func serveStats(_ points: [TimelinePointRecord]) throws -> ServeStats {
        let known = points.filter { $0.serveNumber.value != nil }
        let first = known.filter { $0.serveNumber.value?.rawValue == 1 }
        let second = known.filter { $0.serveNumber.value?.rawValue == 2 }
        let serverSide = points.first?.serverSide.value
        let faults = points.filter { $0.endType == .doubleFault }.count
        return .init(servicePoints: points.count,
            firstServeIn: try Percent.ratio(n: first.count, d: known.count),
            firstServePointsWon: try Percent.ratio(n: first.filter { $0.winner.value == serverSide }.count, d: first.count),
            secondServePointsWon: try Percent.ratio(n: second.filter { $0.winner.value == serverSide }.count, d: second.count),
            secondServeIn: try Percent.ratio(n: second.count - faults, d: second.count),
            aces: points.filter { $0.endType == .ace }.count, doubleFaults: faults,
            serviceWinners: points.filter { $0.endType == .serviceWinner }.count,
            servicePointsWon: try Percent.ratio(n: points.filter { $0.winner.value == serverSide }.count, d: points.count))
    }

    private static func sideStats(_ side: Side, counted: [TimelinePointRecord], played: [TimelinePointRecord], games: [TimelineGameRecord]) throws -> SideStats {
        let served = played.filter { $0.serverSide.value == side.timeline }
        let returned = played.filter { $0.serverSide.value == side.other.timeline }
        let serve = try serveStats(served), opponent = try serveStats(returned)
        let serviceGames = games.filter { $0.kind == .standard && !$0.byPenalty && $0.serverSide == side }
        let returnGames = games.filter { $0.kind == .standard && !$0.byPenalty && $0.serverSide == side.other }
        // Point penalties occupy a break-point slot, but never a service/return point.
        let faced = counted.filter { $0.serverSide.value == side.timeline && $0.pressure.value!.breakPoint }
        let chances = counted.filter { $0.serverSide.value == side.other.timeline && $0.pressure.value!.breakPoint }
        return .init(totalPointsWon: try Percent.ratio(n: counted.filter { $0.winner.value == side.timeline }.count, d: counted.count),
            penaltyPointsAwarded: counted.filter { $0.kind == .penaltyPoint && $0.winner.value == side.timeline }.count,
            servicePoints: serve.servicePoints, firstServeIn: serve.firstServeIn,
            firstServePointsWon: serve.firstServePointsWon, secondServePointsWon: serve.secondServePointsWon,
            secondServeIn: serve.secondServeIn, aces: serve.aces, doubleFaults: serve.doubleFaults,
            serviceWinners: serve.serviceWinners, servicePointsWon: serve.servicePointsWon,
            serviceGamesWon: try Percent.ratio(n: serviceGames.filter { $0.winner.value == side.timeline }.count, d: serviceGames.count),
            returnPointsWon: try Percent.ratio(n: returned.filter { $0.winner.value == side.timeline }.count, d: returned.count),
            returnFirstServePointsWon: try Percent.ratio(n: opponent.firstServeIn.n - opponent.firstServePointsWon.n, d: opponent.firstServeIn.n),
            returnSecondServePointsWon: try Percent.ratio(n: opponent.secondServePointsWon.d - opponent.secondServePointsWon.n, d: opponent.secondServePointsWon.d),
            returnGamesWon: try Percent.ratio(n: returnGames.filter { $0.winner.value == side.timeline }.count, d: returnGames.count),
            breakPointsSaved: try Percent.ratio(n: faced.filter { $0.winner.value == side.timeline }.count, d: faced.count),
            breakPointsConverted: try Percent.ratio(n: chances.filter { $0.winner.value == side.timeline }.count, d: chances.count),
            winners: played.filter { $0.endType == .winner && $0.winner.value == side.timeline }.count,
            forcedErrors: played.filter { $0.endType == .forcedError && $0.winner.value == side.other.timeline }.count,
            unforcedErrors: played.filter { $0.endType == .unforcedError && $0.winner.value == side.other.timeline }.count,
            longestPointStreak: streak(counted.map { $0.winner.value }, side: side),
            longestGameStreak: streak(games.map { $0.winner.value }, side: side))
    }

    private static func streak(_ winners: [TimelineSideOrNull?], side: Side) -> Int {
        var best = 0, run = 0
        for winner in winners { run = winner == side.timeline ? run + 1 : 0; best = max(best, run) }
        return best
    }
}
