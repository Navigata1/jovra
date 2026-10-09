// Generated concrete output models by scripts/spec/generate_scoring_models.py.
import Foundation

public struct MatchTimeline: Codable, Equatable, Sendable {
    public var match: TimelineMatchSummary
    public var sets: [TimelineSetRecord]
    public var games: [TimelineGameRecord]
    public var points: [TimelinePointRecord]
    public var next: ContractNullable<TimelinePointState>
    public var checkpoints: [TimelineCheckpointResult]
    public var conflicts: [TimelineConflict]
    public var history: TimelineHistory
    public var changes: ContractNullable<TimelineChanges>?

    private enum CodingKeys: String, CodingKey { case match, sets, games, points, next, checkpoints, conflicts, history, changes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        match = try c.decode(TimelineMatchSummary.self, forKey: .match)
        sets = try c.decode([TimelineSetRecord].self, forKey: .sets)
        games = try c.decode([TimelineGameRecord].self, forKey: .games)
        points = try c.decode([TimelinePointRecord].self, forKey: .points)
        next = try c.decode(ContractNullable<TimelinePointState>.self, forKey: .next)
        checkpoints = try c.decode([TimelineCheckpointResult].self, forKey: .checkpoints)
        conflicts = try c.decode([TimelineConflict].self, forKey: .conflicts)
        history = try c.decode(TimelineHistory.self, forKey: .history)
        changes = c.contains(.changes) ? try c.decode(ContractNullable<TimelineChanges>.self, forKey: .changes) : nil
    }
    public init(match: TimelineMatchSummary, sets: [TimelineSetRecord], games: [TimelineGameRecord], points: [TimelinePointRecord], next: ContractNullable<TimelinePointState>, checkpoints: [TimelineCheckpointResult], conflicts: [TimelineConflict], history: TimelineHistory, changes: ContractNullable<TimelineChanges>? = nil) {
        self.match = match
        self.sets = sets
        self.games = games
        self.points = points
        self.next = next
        self.checkpoints = checkpoints
        self.conflicts = conflicts
        self.history = history
        self.changes = changes
    }
}

public enum TimelineCall: Codable, Equatable, Sendable {
    case points(TimelineCallPoints)
    case deuce(TimelineCallDeuce)
    case advantage(TimelineCallAdvantage)
    case tiebreak(TimelineCallTiebreak)

    private enum CodingKeys: String, CodingKey { case kind }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(String.self, forKey: .kind)
        switch tag {
        case "points": self = .points(try TimelineCallPoints(from: decoder))
        case "deuce", "decidingPoint": self = .deuce(try TimelineCallDeuce(from: decoder))
        case "advantage": self = .advantage(try TimelineCallAdvantage(from: decoder))
        case "tiebreak": self = .tiebreak(try TimelineCallTiebreak(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown TimelineCall discriminator")
        }
    }
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .points(let value): try value.encode(to: encoder)
        case .deuce(let value): try value.encode(to: encoder)
        case .advantage(let value): try value.encode(to: encoder)
        case .tiebreak(let value): try value.encode(to: encoder)
        }
    }
}

public struct TimelineCallAdvantage: Codable, Equatable, Sendable {
    public var kind: TimelineCallAdvantageKind
    public var side: Side

    public init(kind: TimelineCallAdvantageKind = .value, side: Side) {
        self.kind = kind
        self.side = side
    }
}

public enum TimelineCallAdvantageKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "advantage"
}

public struct TimelineCallDeuce: Codable, Equatable, Sendable {
    public var kind: TimelineCallDeuceKind

    public init(kind: TimelineCallDeuceKind) {
        self.kind = kind
    }
}

public enum TimelineCallDeuceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case deuce = "deuce"
    case decidingPoint = "decidingPoint"
}

public struct TimelineCallPoints: Codable, Equatable, Sendable {
    public var kind: TimelineCallPointsKind
    public var server: TimelineCallPointsServer
    public var receiver: TimelineCallPointsReceiver

    public init(kind: TimelineCallPointsKind = .value, server: TimelineCallPointsServer, receiver: TimelineCallPointsReceiver) {
        self.kind = kind
        self.server = server
        self.receiver = receiver
    }
}

public enum TimelineCallPointsKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "points"
}

public enum TimelineCallPointsReceiver: String, Codable, CaseIterable, Hashable, Sendable {
    case value0 = "0"
    case value15 = "15"
    case value30 = "30"
    case value40 = "40"
}

public enum TimelineCallPointsServer: String, Codable, CaseIterable, Hashable, Sendable {
    case value0 = "0"
    case value15 = "15"
    case value30 = "30"
    case value40 = "40"
}

public struct TimelineCallTiebreak: Codable, Equatable, Sendable {
    public var kind: TimelineCallTiebreakKind
    public var server: Int
    public var receiver: Int

    public init(kind: TimelineCallTiebreakKind = .value, server: Int, receiver: Int) {
        self.kind = kind
        self.server = server
        self.receiver = receiver
    }
}

public enum TimelineCallTiebreakKind: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "tiebreak"
}

public struct TimelineChanges: Codable, Equatable, Sendable {
    public var tiebreakAppeared: [Int]
    public var tiebreakVanished: [Int]
    public var matchIncomplete: Bool
    public var recalculatedPointIds: [String]

    public init(tiebreakAppeared: [Int], tiebreakVanished: [Int], matchIncomplete: Bool, recalculatedPointIds: [String]) {
        self.tiebreakAppeared = tiebreakAppeared
        self.tiebreakVanished = tiebreakVanished
        self.matchIncomplete = matchIncomplete
        self.recalculatedPointIds = recalculatedPointIds
    }
}

public struct TimelineCheckpointResult: Codable, Equatable, Sendable {
    public var id: String
    public var set: Int
    public var called: SideCounts
    public var derived: ContractNullable<SideCounts>
    public var agrees: ContractNullable<Bool>

    public init(id: String, set: Int, called: SideCounts, derived: ContractNullable<SideCounts>, agrees: ContractNullable<Bool>) {
        self.id = id
        self.set = set
        self.called = called
        self.derived = derived
        self.agrees = agrees
    }
}

public struct TimelineConflict: Codable, Equatable, Sendable {
    public var type: TimelineConflictType
    public var pointId: String?
    public var eventId: String?
    public var checkpointId: String?
    public var pointIds: [String]?
    public var recorded: String?
    public var derived: String?

    public init(type: TimelineConflictType, pointId: String? = nil, eventId: String? = nil, checkpointId: String? = nil, pointIds: [String]? = nil, recorded: String? = nil, derived: String? = nil) {
        self.type = type
        self.pointId = pointId
        self.eventId = eventId
        self.checkpointId = checkpointId
        self.pointIds = pointIds
        self.recorded = recorded
        self.derived = derived
    }
}

public enum TimelineConflictType: String, Codable, CaseIterable, Hashable, Sendable {
    case serverMismatch = "serverMismatch"
    case pointsAfterMatchEnd = "pointsAfterMatchEnd"
    case checkpointConflict = "checkpointConflict"
    case outcomeInconsistent = "outcomeInconsistent"
    case eventAfterMatchEnd = "eventAfterMatchEnd"
    case walkoverAfterPlay = "walkoverAfterPlay"
    case doublesOrderConflict = "doublesOrderConflict"
    case decidingPointSideIgnored = "decidingPointSideIgnored"
    case receiverMismatch = "receiverMismatch"
    case overrideContextChanged = "overrideContextChanged"
}

public struct TimelineEnds: Codable, Equatable, Sendable {
    public var A: TimelineEndsA
    public var B: TimelineEndsB

    public init(A: TimelineEndsA, B: TimelineEndsB) {
        self.A = A
        self.B = B
    }
}

public enum TimelineEndsA: String, Codable, CaseIterable, Hashable, Sendable {
    case near = "near"
    case far = "far"
}

public enum TimelineEndsB: String, Codable, CaseIterable, Hashable, Sendable {
    case near = "near"
    case far = "far"
}

public struct TimelineGameRecord: Codable, Equatable, Sendable {
    public var index: Int
    public var set: Int
    public var gameInSet: Int
    public var kind: TimelineGameRecordKind
    public var server: String
    public var serverSide: Side
    public var winner: ContractNullable<TimelineSideOrNull>
    public var points: SideCounts
    public var byPenalty: Bool
    public var complete: Bool
    public var `break`: Bool

    public init(index: Int, set: Int, gameInSet: Int, kind: TimelineGameRecordKind, server: String, serverSide: Side, winner: ContractNullable<TimelineSideOrNull>, points: SideCounts, byPenalty: Bool, complete: Bool, `break`: Bool) {
        self.index = index
        self.set = set
        self.gameInSet = gameInSet
        self.kind = kind
        self.server = server
        self.serverSide = serverSide
        self.winner = winner
        self.points = points
        self.byPenalty = byPenalty
        self.complete = complete
        self.`break` = `break`
    }
}

public enum TimelineGameRecordKind: String, Codable, CaseIterable, Hashable, Sendable {
    case standard = "standard"
    case tiebreak = "tiebreak"
    case matchTiebreak = "matchTiebreak"
}

public struct TimelineHistory: Codable, Equatable, Sendable {
    public var voided: [String]
    public var superseded: [TimelineHistorySupersededItem]

    public init(voided: [String], superseded: [TimelineHistorySupersededItem]) {
        self.voided = voided
        self.superseded = superseded
    }
}

public struct TimelineHistorySupersededItem: Codable, Equatable, Sendable {
    public var id: String
    public var by: String

    public init(id: String, by: String) {
        self.id = id
        self.by = by
    }
}

public struct TimelineMatchSummary: Codable, Equatable, Sendable {
    public var status: TimelineMatchSummaryStatus
    public var doubles: Bool
    public var winner: ContractNullable<TimelineSideOrNull>
    public var provisional: Bool
    public var setsWon: SideCounts
    public var scoreline: ContractNullable<String>
    public var pointsPlayed: Int
    public var rallyLets: Int

    public init(status: TimelineMatchSummaryStatus, doubles: Bool, winner: ContractNullable<TimelineSideOrNull>, provisional: Bool, setsWon: SideCounts, scoreline: ContractNullable<String>, pointsPlayed: Int, rallyLets: Int) {
        self.status = status
        self.doubles = doubles
        self.winner = winner
        self.provisional = provisional
        self.setsWon = setsWon
        self.scoreline = scoreline
        self.pointsPlayed = pointsPlayed
        self.rallyLets = rallyLets
    }
}

public enum TimelineMatchSummaryStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case notStarted = "notStarted"
    case inProgress = "inProgress"
    case completed = "completed"
    case retired = "retired"
    case defaulted = "defaulted"
    case walkover = "walkover"
}

public struct TimelinePointRecord: Codable, Equatable, Sendable {
    public var id: String
    public var index: Int
    public var kind: TimelinePointRecordKind
    public var determined: Bool
    public var afterMatchEnd: Bool
    public var set: ContractNullable<Int>
    public var game: ContractNullable<Int>
    public var gameInSet: ContractNullable<Int>
    public var tiebreak: ContractNullable<TimelinePointRecordTiebreak>
    public var pointInGame: ContractNullable<Int>
    public var server: ContractNullable<String>
    public var receiver: ContractNullable<String>
    public var serverSide: ContractNullable<TimelineSideOrNull>
    public var courtSide: ContractNullable<TimelinePointRecordCourtSide>
    public var ends: ContractNullable<TimelineEnds>
    public var before: ContractNullable<TimelineScoreState>
    public var call: ContractNullable<TimelineCall>
    public var pressure: ContractNullable<TimelinePressure>
    public var winner: ContractNullable<TimelineSideOrNull>
    public var endType: TimelinePointRecordEndType
    public var serveNumber: ContractNullable<TimelinePointRecordServeNumber>
    public var strokeCount: ContractNullable<Int>
    public var rallyLength: ContractNullable<Int>
    public var provenance: Provenance
    public var reviewState: TimelinePointRecordReviewState
    public var tStartMs: Int?
    public var tEndMs: Int?
    public var after: ContractNullable<TimelinePointRecordAfter>

    public init(id: String, index: Int, kind: TimelinePointRecordKind, determined: Bool, afterMatchEnd: Bool, set: ContractNullable<Int>, game: ContractNullable<Int>, gameInSet: ContractNullable<Int>, tiebreak: ContractNullable<TimelinePointRecordTiebreak>, pointInGame: ContractNullable<Int>, server: ContractNullable<String>, receiver: ContractNullable<String>, serverSide: ContractNullable<TimelineSideOrNull>, courtSide: ContractNullable<TimelinePointRecordCourtSide>, ends: ContractNullable<TimelineEnds>, before: ContractNullable<TimelineScoreState>, call: ContractNullable<TimelineCall>, pressure: ContractNullable<TimelinePressure>, winner: ContractNullable<TimelineSideOrNull>, endType: TimelinePointRecordEndType, serveNumber: ContractNullable<TimelinePointRecordServeNumber>, strokeCount: ContractNullable<Int>, rallyLength: ContractNullable<Int>, provenance: Provenance, reviewState: TimelinePointRecordReviewState, tStartMs: Int? = nil, tEndMs: Int? = nil, after: ContractNullable<TimelinePointRecordAfter>) {
        self.id = id
        self.index = index
        self.kind = kind
        self.determined = determined
        self.afterMatchEnd = afterMatchEnd
        self.set = set
        self.game = game
        self.gameInSet = gameInSet
        self.tiebreak = tiebreak
        self.pointInGame = pointInGame
        self.server = server
        self.receiver = receiver
        self.serverSide = serverSide
        self.courtSide = courtSide
        self.ends = ends
        self.before = before
        self.call = call
        self.pressure = pressure
        self.winner = winner
        self.endType = endType
        self.serveNumber = serveNumber
        self.strokeCount = strokeCount
        self.rallyLength = rallyLength
        self.provenance = provenance
        self.reviewState = reviewState
        self.tStartMs = tStartMs
        self.tEndMs = tEndMs
        self.after = after
    }
}

public struct TimelinePointRecordAfter: Codable, Equatable, Sendable {
    public var gameWon: Bool
    public var setWon: Bool
    public var matchWon: Bool
    public var endChange: Bool
    public var rest: TimelinePointRecordAfterRest

    public init(gameWon: Bool, setWon: Bool, matchWon: Bool, endChange: Bool, rest: TimelinePointRecordAfterRest) {
        self.gameWon = gameWon
        self.setWon = setWon
        self.matchWon = matchWon
        self.endChange = endChange
        self.rest = rest
    }
}

public enum TimelinePointRecordAfterRest: String, Codable, CaseIterable, Hashable, Sendable {
    case point = "point"
    case changeoverNoRest = "changeoverNoRest"
    case changeover = "changeover"
    case setBreak = "setBreak"
    case matchEnd = "matchEnd"
}

public enum TimelinePointRecordCourtSide: String, Codable, CaseIterable, Hashable, Sendable {
    case deuce = "deuce"
    case ad = "ad"
}

public enum TimelinePointRecordEndType: String, Codable, CaseIterable, Hashable, Sendable {
    case ace = "ace"
    case serviceWinner = "serviceWinner"
    case doubleFault = "doubleFault"
    case winner = "winner"
    case forcedError = "forcedError"
    case unforcedError = "unforcedError"
    case hindrance = "hindrance"
    case penalty = "penalty"
    case unknown = "unknown"
}

public enum TimelinePointRecordKind: String, Codable, CaseIterable, Hashable, Sendable {
    case point = "point"
    case penaltyPoint = "penaltyPoint"
}

public enum TimelinePointRecordReviewState: String, Codable, CaseIterable, Hashable, Sendable {
    case unreviewed = "unreviewed"
    case needsReview = "needsReview"
    case reviewed = "reviewed"
}

public enum TimelinePointRecordServeNumber: Int, Codable, CaseIterable, Hashable, Sendable {
    case value1 = 1
    case value2 = 2
}

public enum TimelinePointRecordTiebreak: String, Codable, CaseIterable, Hashable, Sendable {
    case set = "set"
    case match = "match"
}

public struct TimelinePointState: Codable, Equatable, Sendable {
    public var set: Int
    public var game: Int
    public var gameInSet: Int
    public var tiebreak: ContractNullable<TimelinePointStateTiebreak>
    public var pointInGame: Int
    public var server: String
    public var receiver: ContractNullable<String>
    public var serverSide: Side
    public var courtSide: ContractNullable<TimelinePointStateCourtSide>
    public var ends: TimelineEnds
    public var before: TimelineScoreState
    public var call: TimelineCall
    public var pressure: TimelinePressure

    public init(set: Int, game: Int, gameInSet: Int, tiebreak: ContractNullable<TimelinePointStateTiebreak>, pointInGame: Int, server: String, receiver: ContractNullable<String>, serverSide: Side, courtSide: ContractNullable<TimelinePointStateCourtSide>, ends: TimelineEnds, before: TimelineScoreState, call: TimelineCall, pressure: TimelinePressure) {
        self.set = set
        self.game = game
        self.gameInSet = gameInSet
        self.tiebreak = tiebreak
        self.pointInGame = pointInGame
        self.server = server
        self.receiver = receiver
        self.serverSide = serverSide
        self.courtSide = courtSide
        self.ends = ends
        self.before = before
        self.call = call
        self.pressure = pressure
    }
}

public enum TimelinePointStateCourtSide: String, Codable, CaseIterable, Hashable, Sendable {
    case deuce = "deuce"
    case ad = "ad"
}

public enum TimelinePointStateTiebreak: String, Codable, CaseIterable, Hashable, Sendable {
    case set = "set"
    case match = "match"
}

public struct TimelinePressure: Codable, Equatable, Sendable {
    public var gamePointFor: [Side]
    public var breakPoint: Bool
    public var setPointFor: [Side]
    public var matchPointFor: [Side]

    public init(gamePointFor: [Side], breakPoint: Bool, setPointFor: [Side], matchPointFor: [Side]) {
        self.gamePointFor = gamePointFor
        self.breakPoint = breakPoint
        self.setPointFor = setPointFor
        self.matchPointFor = matchPointFor
    }
}

public struct TimelineScoreState: Codable, Equatable, Sendable {
    public var sets: SideCounts
    public var games: SideCounts
    public var points: SideCounts

    public init(sets: SideCounts, games: SideCounts, points: SideCounts) {
        self.sets = sets
        self.games = games
        self.points = points
    }
}

public struct TimelineSetRecord: Codable, Equatable, Sendable {
    public var index: Int
    public var rule: TimelineSetRecordRule
    public var games: SideCounts
    public var tiebreak: ContractNullable<SideCounts>
    public var winner: ContractNullable<TimelineSideOrNull>
    public var complete: Bool
    public var byPenalty: Bool

    public init(index: Int, rule: TimelineSetRecordRule, games: SideCounts, tiebreak: ContractNullable<SideCounts>, winner: ContractNullable<TimelineSideOrNull>, complete: Bool, byPenalty: Bool) {
        self.index = index
        self.rule = rule
        self.games = games
        self.tiebreak = tiebreak
        self.winner = winner
        self.complete = complete
        self.byPenalty = byPenalty
    }
}

public enum TimelineSetRecordRule: String, Codable, CaseIterable, Hashable, Sendable {
    case tiebreakSet = "tiebreakSet"
    case advantageSet = "advantageSet"
    case matchTiebreak = "matchTiebreak"
}

public enum TimelineSideOrNull: String, Codable, CaseIterable, Hashable, Sendable {
    case a = "A"
    case b = "B"
}
