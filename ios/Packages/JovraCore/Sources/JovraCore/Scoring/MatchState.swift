import Foundation

/// Value semantics make hypothetical pressure probes independent of the actual fold.
struct MatchState {
    let input: ScoringInput
    let sideOf: [String: Side]
    let doubles: Bool
    let orders: [Int: SessionDoublesOrderEvent]
    var firstSide: Side
    var ends: TimelineEnds
    var sets: [TimelineSetRecord] = [], setsWon = SideCounts.zero
    var setIndex = 0, matchGame = 0, gameInSet = 0, games = SideCounts.zero, points = SideCounts.zero, pointInGame = 0
    var rule: SessionSetRule
    var tb: SessionTiebreakRule?, tbKind: TimelinePointStateTiebreak?
    var over = false, status: TimelineMatchSummaryStatus = .notStarted, winner: Side?
    var rotation: [String] = [], deuceReceivers: [Side: String] = [:]
    var gameRecords: [TimelineGameRecord] = [], gameStartServer: String?
    var hypothetical = false, pendingConflicts: [TimelineConflict] = []

    init(_ input: ScoringInput, orders: [Int: SessionDoublesOrderEvent]) throws {
        self.input = input; self.orders = orders
        var lookup: [String: Side] = [:]
        for side in Side.allCases { for id in input.sides[side] { lookup[id] = side } }
        guard let first = lookup[input.toss.firstServer] else { throw ScoringError(.unknownPlayer, input.toss.firstServer) }
        sideOf = lookup; firstSide = first; doubles = input.sides.A.count == 2
        ends = .init(A: .init(rawValue: input.toss.startingEnds.A.rawValue)!, B: .init(rawValue: input.toss.startingEnds.B.rawValue)!)
        rule = input.format.set
        try startSet()
    }
    func partner(_ id: String) -> String { let playersOnSide = input.sides[sideOf[id]!]; return playersOnSide[0] == id ? playersOnSide[1] : playersOnSide[0] }
    mutating func startSet() throws {
        let deciding = setsWon.A == input.format.setsToWin.rawValue - 1 && setsWon.B == input.format.setsToWin.rawValue - 1
        rule = deciding ? input.format.finalSet ?? input.format.set : input.format.set
        games = .zero; gameInSet = 0; tb = nil; tbKind = nil
        if case .matchTiebreak(let r) = rule { tb = r.tiebreak; tbKind = .match }
        if doubles {
            let servingSide = matchGame % 2 == 0 ? firstSide : firstSide.other
            var first: String, second: String
            if let order = orders[setIndex] {
                first = order.firstServer; second = order.secondServer
                deuceReceivers = [.a: order.deuceReceivers.A, .b: order.deuceReceivers.B]
                if sideOf[first] != servingSide {
                    swap(&first, &second)
                    pendingConflicts.append(.init(type: .doublesOrderConflict, eventId: order.id, recorded: second, derived: first))
                }
            } else {
                guard setIndex > 0 else { throw ScoringError(.doublesOrderMissing, "set 0") }
                first = rotation.first { sideOf[$0] == servingSide }!; second = rotation.first { sideOf[$0] == servingSide.other }!
            }
            rotation = [first, second, partner(first), partner(second)]
        }
    }
    func server() -> String {
        let offset = tb == nil ? 0 : (pointInGame + 1) / 2
        if doubles { return rotation[(gameInSet + offset) % 4] }
        return input.sides[(matchGame + offset) % 2 == 0 ? firstSide : firstSide.other][0]
    }
    var decidingPoint: Bool { tb == nil && input.format.gameScoring == .noAd && points.A == 3 && points.B == 3 }
    var sideChosen: Bool {
        decidingPoint || (tb?.suddenDeathSide == .receiverChooses && tb?.suddenDeathAt != nil && points.A == tb?.suddenDeathAt && points.B == tb?.suddenDeathAt)
    }
    func courtSide(_ chosen: String?) -> TimelinePointStateCourtSide? {
        sideChosen ? chosen.flatMap(TimelinePointStateCourtSide.init(rawValue:)) : (pointInGame % 2 == 0 ? .deuce : .ad)
    }
    func receiver(_ server: String, _ side: TimelinePointStateCourtSide?) -> String? {
        let receivingSide = sideOf[server]!.other
        if !doubles { return input.sides[receivingSide][0] }
        guard let side else { return nil }
        let deuce = deuceReceivers[receivingSide]!
        return side == .deuce ? deuce : partner(deuce)
    }
    func call(_ server: Side) -> TimelineCall {
        let s = points[server], r = points[server.other]
        if tb != nil { return .tiebreak(.init(server: s, receiver: r)) }
        if decidingPoint { return .deuce(.init(kind: .decidingPoint)) }
        if s >= 3 && r >= 3 {
            if s == r { return .deuce(.init(kind: .deuce)) }
            return .advantage(.init(side: s > r ? server : server.other))
        }
        let labels = ["0", "15", "30", "40"]
        return .points(.init(server: .init(rawValue: labels[s])!, receiver: .init(rawValue: labels[r])!))
    }
    func pressure(_ server: Side) throws -> TimelinePressure {
        var game: [Side] = [], set: [Side] = [], match: [Side] = []
        for side in Side.allCases {
            var copy = self; copy.hypothetical = true
            let result = try copy.apply(side)
            if result.gameWon { game.append(side) }; if result.setWon { set.append(side) }; if result.matchWon { match.append(side) }
        }
        return .init(gamePointFor: game, breakPoint: tb == nil && game.contains(server.other), setPointFor: set, matchPointFor: match)
    }
    func state(server: String? = nil, chosen: String? = nil, receiverOverride: String? = nil) throws -> TimelinePointState {
        let server = server ?? self.server(), side = courtSide(chosen), serverSide = sideOf[server]!
        return .init(set: setIndex, game: matchGame, gameInSet: gameInSet, tiebreak: .init(tbKind), pointInGame: pointInGame + 1, server: server,
            receiver: .init(receiverOverride ?? receiver(server, side)), serverSide: serverSide, courtSide: .init(side), ends: ends,
            before: .init(sets: setsWon, games: games, points: points), call: call(serverSide), pressure: try pressure(serverSide))
    }
    mutating func flipEnds() { let a = ends.A.rawValue; ends.A = .init(rawValue: ends.B.rawValue)!; ends.B = .init(rawValue: a)! }
    func gameWon(_ side: Side) -> Bool {
        let p = points[side], q = points[side.other]
        if let tb { return p >= tb.points && (p - q >= 2 || (tb.suddenDeathAt != nil && p == tb.suddenDeathAt! + 1 && q == tb.suddenDeathAt!)) }
        return p >= 4 && (input.format.gameScoring == .noAd || p - q >= 2)
    }
    mutating func apply(_ side: Side, observedServer: String? = nil) throws -> TimelinePointRecordAfter {
        if status == .notStarted { status = .inProgress }
        if pointInGame == 0 { gameStartServer = observedServer ?? server() }
        points[side] += 1; pointInGame += 1
        if gameWon(side) { return try completeGame(side, penalty: false) }
        var change = false
        if let tb {
            switch tb.endChange ?? .every6 {
            case .coman: change = pointInGame == 1 || (pointInGame - 1) % 4 == 0
            case .after4: change = pointInGame == 4
            case .every6: change = pointInGame % 6 == 0
            }
        }
        if change { flipEnds() }
        return .init(gameWon: false, setWon: false, matchWon: false, endChange: change, rest: change ? .changeoverNoRest : .point)
    }
    mutating func awardGame(_ side: Side) throws {
        if status == .notStarted { status = .inProgress }
        if pointInGame == 0 { gameStartServer = server() }
        _ = try completeGame(side, penalty: true)
    }
    mutating func completeGame(_ side: Side, penalty: Bool) throws -> TimelinePointRecordAfter {
        let tbPoints: SideCounts? = tb == nil ? nil : points
        let kind: TimelineGameRecordKind = tb == nil ? .standard : (tbKind == .match ? .matchTiebreak : .tiebreak)
        let server = gameStartServer!, serverSide = sideOf[server]!
        gameRecords.append(.init(index: matchGame, set: setIndex, gameInSet: gameInSet, kind: kind, server: server, serverSide: serverSide,
            winner: .value(side.timeline), points: points, byPenalty: penalty, complete: true, break: kind == .standard && !penalty && side != serverSide))
        let gameNumber = gameInSet + 1
        games[side] += 1
        var setWon = tb != nil
        switch rule {
        case .tiebreakSet(let r): setWon = setWon || (games[side] >= r.games && games[side] - games[side.other] >= 2)
        case .advantageSet(let r): setWon = setWon || (games[side] >= r.games && games[side] - games[side.other] >= 2)
        case .matchTiebreak: break
        }
        matchGame += 1; gameInSet += 1; points = .zero; pointInGame = 0; tb = nil; tbKind = nil
        let change = gameNumber % 2 == 1
        if setWon {
            sets.append(.init(index: setIndex, rule: ruleKind, games: games, tiebreak: .init(tbPoints), winner: .value(side.timeline), complete: true, byPenalty: penalty))
            setsWon[side] += 1
            if setsWon[side] == input.format.setsToWin.rawValue {
                over = true; status = .completed; winner = side
                return .init(gameWon: true, setWon: true, matchWon: true, endChange: false, rest: .matchEnd)
            }
            setIndex += 1
            if change { flipEnds() }; if !hypothetical { try startSet() }
            return .init(gameWon: true, setWon: true, matchWon: false, endChange: change, rest: .setBreak)
        }
        if case .tiebreakSet(let r) = rule, games.A == r.tiebreakAt, games.B == r.tiebreakAt { tb = r.tiebreak; tbKind = .set }
        if change { flipEnds() }
        return .init(gameWon: true, setWon: false, matchWon: false, endChange: change, rest: change ? (gameNumber == 1 ? .changeoverNoRest : .changeover) : .point)
    }
    var ruleKind: TimelineSetRecordRule { switch rule { case .tiebreakSet: .tiebreakSet; case .advantageSet: .advantageSet; case .matchTiebreak: .matchTiebreak } }
    var currentSet: TimelineSetRecord? {
        guard status != .completed, games != .zero || pointInGame > 0 else { return nil }
        return .init(index: setIndex, rule: ruleKind, games: games, tiebreak: .init(tb == nil ? nil : points), winner: .null, complete: false, byPenalty: false)
    }
    var currentGame: TimelineGameRecord? {
        guard pointInGame > 0, let server = gameStartServer else { return nil }
        return .init(index: matchGame, set: setIndex, gameInSet: gameInSet, kind: tb == nil ? .standard : (tbKind == .match ? .matchTiebreak : .tiebreak),
            server: server, serverSide: sideOf[server]!, winner: .null, points: points, byPenalty: false, complete: false, break: false)
    }
}
