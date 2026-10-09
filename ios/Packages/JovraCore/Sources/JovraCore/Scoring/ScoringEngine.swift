import Foundation

/// Replays the append-only log from the beginning; corrections never leave cached later scores.
public enum ScoringEngine {
    public static func fold(_ input: ScoringInput, mode: SessionMatchResolutionMode? = nil) throws -> MatchTimeline {
        var input = input; if let mode { input.resolutionMode = mode }
        let resolved = try LogResolver.resolve(input.log)
        try validate(input, resolved.orders)
        var overrides = try OrderOverrides(input, placed: resolved.placed)
        var match = try MatchState(input, orders: resolved.orders)
        var points: [TimelinePointRecord] = [], conflicts: [TimelineConflict] = [], checkpoints: [TimelineCheckpointResult] = []
        var determined = true, stretch: [String] = [], rallyLets = 0
        for event in resolved.placed {
            switch event {
            case .serverOverride, .receiverOverride: continue
            case .rallyLet: rallyLets += 1; continue
            case .checkpoint(let v):
                let derived: SideCounts? = !determined ? nil : (v.setIndex < match.sets.count ? match.sets[v.setIndex].games : (v.setIndex == match.setIndex && !match.over ? match.games : nil))
                let agrees: Bool? = determined ? derived == v.games : nil
                if agrees == false { conflicts.append(.init(type: .checkpointConflict, checkpointId: v.id, pointIds: stretch)) }
                checkpoints.append(.init(id: v.id, set: v.setIndex, called: v.games, derived: .init(derived), agrees: .init(agrees)))
                stretch = []; continue
            case .retirement(let v):
                if match.over { conflicts.append(.init(type: .eventAfterMatchEnd, eventId: v.id)); continue }
                if event.typeString == "walkover" && match.status != .notStarted { conflicts.append(.init(type: .walkoverAfterPlay, eventId: v.id)); continue }
                match.over = true; match.winner = match.sideOf[v.player]!.other
                match.status = event.typeString == "default" ? .defaulted : (event.typeString == "walkover" || match.status == .notStarted ? .walkover : .retired)
                continue
            case .penalty(let v) where v.kind == .game:
                if match.over { conflicts.append(.init(type: .eventAfterMatchEnd, eventId: v.id)); continue }
                if determined { try match.awardGame(match.sideOf[v.player]!.other); conflicts += match.pendingConflicts; match.pendingConflicts = [] }
                continue
            default: break
            }
            let outcome: SessionOutcome?, winner: Side?, chosen: String?, recordedServer: String?
            switch event {
            case .point(let v):
                guard let effective = v.reviewed ?? v.detected else { throw ScoringError(.outcomeMissing, v.id) }
                outcome = effective; winner = Side(rawValue: effective.winner.rawValue); chosen = v.decidingPointSide?.rawValue; recordedServer = v.recordedServer
            case .penalty(let v): outcome = nil; winner = match.sideOf[v.player]!.other; chosen = nil; recordedServer = nil
            default: continue
            }
            stretch.append(event.id)
            if match.over || !determined {
                points.append(OutcomeInterpreter.record(event: event, index: points.count, state: nil, afterEnd: match.over, outcome: outcome, winner: winner))
                if match.over { conflicts.append(.init(type: .pointsAfterMatchEnd, pointId: event.id)) }; continue
            }
            let server = try overrides.beforePoint(&match, event: event, winner: winner, conflicts: &conflicts)
            var state = try match.state(server: server, chosen: chosen)
            state.receiver = .init(overrides.receiver(match, server: server, courtSide: state.courtSide.value))
            if let chosen, !match.sideChosen { conflicts.append(.init(type: .decidingPointSideIgnored, pointId: event.id, recorded: chosen, derived: state.courtSide.value!.rawValue)) }
            if overrides.servers[event.id] == nil, let recordedServer, recordedServer != state.server { conflicts.append(.init(type: .serverMismatch, pointId: event.id, recorded: recordedServer, derived: state.server)) }
            var record = OutcomeInterpreter.record(event: event, index: points.count, state: state, afterEnd: false, outcome: outcome, winner: winner)
            guard let winner else { determined = false; points.append(record); continue }
            if let outcome, !OutcomeInterpreter.serveNumber(outcome).1 || !OutcomeInterpreter.consistent(outcome, winner: winner, server: state.serverSide) { conflicts.append(.init(type: .outcomeInconsistent, pointId: event.id)) }
            record.after = .value(try match.apply(winner, observedServer: state.server))
            conflicts += match.pendingConflicts; match.pendingConflicts = []; points.append(record)
        }
        var sets = match.sets, games = match.gameRecords
        if determined { if let current = match.currentSet { sets.append(current) }; if let current = match.currentGame { games.append(current) } }
        var next: TimelinePointState? = determined && !match.over ? try match.state() : nil
        if let state = next { next?.receiver = .init(overrides.receiver(match, server: state.server, courtSide: state.courtSide.value)) }
        return .init(match: .init(status: match.status, doubles: match.doubles, winner: .init(match.winner?.timeline), provisional: !determined,
            setsWon: match.setsWon, scoreline: .init(determined ? scoreline(sets, status: match.status, winner: match.winner) : nil),
            pointsPlayed: points.filter { !$0.afterMatchEnd }.count, rallyLets: rallyLets), sets: sets, games: games, points: points,
            next: .init(next), checkpoints: checkpoints, conflicts: conflicts, history: resolved.history)
    }
    private static func validate(_ input: ScoringInput, _ orders: [Int: SessionDoublesOrderEvent]) throws {
        let members = input.sides.A + input.sides.B
        let known = Set(members)
        guard (1...2).contains(input.sides.A.count), input.sides.A.count == input.sides.B.count,
              known.count == members.count, Set(input.players.map(\.id)) == known, input.players.count == members.count else { throw ScoringError(.invalidSetup, "sides") }
        guard input.toss.startingEnds.A.rawValue != input.toss.startingEnds.B.rawValue else { throw ScoringError(.invalidSetup, "startingEnds") }
        func valid(_ rule: SessionSetRule) -> Bool {
            switch rule {
            case .advantageSet(let r): return r.games > 0
            case .tiebreakSet(let r): return r.games > 0 && r.tiebreakAt > 0 && r.tiebreak.points > 0
            case .matchTiebreak(let r): return r.tiebreak.points > 0
            }
        }
        guard valid(input.format.set), input.format.finalSet.map(valid) ?? true else { throw ScoringError(.invalidSetup, "format") }
        guard known.contains(input.toss.firstServer) else { throw ScoringError(.unknownPlayer, input.toss.firstServer) }
        for event in input.log {
            let names: [String]
            switch event {
            case .point(let v): names = v.recordedServer.map { [$0] } ?? []
            case .penalty(let v): names = [v.player]
            case .checkpoint(let v):
                guard v.setIndex >= 0, v.games.A >= 0, v.games.B >= 0 else { throw ScoringError(.invalidSetup, v.id) }
                names = []
            case .retirement(let v): names = [v.player]
            case .doublesOrder(let v): names = [v.firstServer, v.secondServer, v.deuceReceivers.A, v.deuceReceivers.B]
            default: names = []
            }
            guard names.allSatisfy(known.contains) else { throw ScoringError(.unknownPlayer, event.id) }
        }
        if input.sides.A.count == 2 {
            for (index, order) in orders {
                guard input.sides.A.contains(order.firstServer) != input.sides.A.contains(order.secondServer),
                      input.sides.A.contains(order.deuceReceivers.A), input.sides.B.contains(order.deuceReceivers.B),
                      index != 0 || order.firstServer == input.toss.firstServer else { throw ScoringError(.doublesOrderInvalid, order.id) }
            }
        }
    }
    public static func scoreline(_ sets: [TimelineSetRecord], status: TimelineMatchSummaryStatus, winner: Side?) -> String {
        if status == .walkover { return "w/o" }
        let first = winner ?? .a
        var parts = sets.map { set -> String in
            if set.rule == .matchTiebreak, let tb = set.tiebreak.value, !(set.complete && set.byPenalty) { return "[\(tb[first])-\(tb[first.other])]" }
            var text = "\(set.games[first])-\(set.games[first.other])"
            if let tb = set.tiebreak.value, set.complete, let winner = set.winner.value.flatMap({ Side(rawValue: $0.rawValue) }) { text += "(\(tb[winner.other]))" }
            return text
        }
        if status == .retired { parts.append("ret.") }; if status == .defaulted { parts.append("def.") }
        return parts.joined(separator: " ")
    }
}
