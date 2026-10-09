// Generated concrete stats models by scripts/spec/generate_stats_models.py.
import Foundation

public struct ServeStats: Codable, Equatable, Sendable {
    public var servicePoints: Int
    public var firstServeIn: RateRatio
    public var firstServePointsWon: RateRatio
    public var secondServePointsWon: RateRatio
    public var secondServeIn: RateRatio
    public var aces: Int
    public var doubleFaults: Int
    public var serviceWinners: Int
    public var servicePointsWon: RateRatio

    public init(servicePoints: Int, firstServeIn: RateRatio, firstServePointsWon: RateRatio, secondServePointsWon: RateRatio, secondServeIn: RateRatio, aces: Int, doubleFaults: Int, serviceWinners: Int, servicePointsWon: RateRatio) {
        self.servicePoints = servicePoints
        self.firstServeIn = firstServeIn
        self.firstServePointsWon = firstServePointsWon
        self.secondServePointsWon = secondServePointsWon
        self.secondServeIn = secondServeIn
        self.aces = aces
        self.doubleFaults = doubleFaults
        self.serviceWinners = serviceWinners
        self.servicePointsWon = servicePointsWon
    }
}

public struct SideStats: Codable, Equatable, Sendable {
    public var totalPointsWon: RateRatio
    public var penaltyPointsAwarded: Int
    public var servicePoints: Int
    public var firstServeIn: RateRatio
    public var firstServePointsWon: RateRatio
    public var secondServePointsWon: RateRatio
    public var secondServeIn: RateRatio
    public var aces: Int
    public var doubleFaults: Int
    public var serviceWinners: Int
    public var servicePointsWon: RateRatio
    public var serviceGamesWon: RateRatio
    public var returnPointsWon: RateRatio
    public var returnFirstServePointsWon: RateRatio
    public var returnSecondServePointsWon: RateRatio
    public var returnGamesWon: RateRatio
    public var breakPointsSaved: RateRatio
    public var breakPointsConverted: RateRatio
    public var winners: Int
    public var forcedErrors: Int
    public var unforcedErrors: Int
    public var longestPointStreak: Int
    public var longestGameStreak: Int

    public init(totalPointsWon: RateRatio, penaltyPointsAwarded: Int, servicePoints: Int, firstServeIn: RateRatio, firstServePointsWon: RateRatio, secondServePointsWon: RateRatio, secondServeIn: RateRatio, aces: Int, doubleFaults: Int, serviceWinners: Int, servicePointsWon: RateRatio, serviceGamesWon: RateRatio, returnPointsWon: RateRatio, returnFirstServePointsWon: RateRatio, returnSecondServePointsWon: RateRatio, returnGamesWon: RateRatio, breakPointsSaved: RateRatio, breakPointsConverted: RateRatio, winners: Int, forcedErrors: Int, unforcedErrors: Int, longestPointStreak: Int, longestGameStreak: Int) {
        self.totalPointsWon = totalPointsWon
        self.penaltyPointsAwarded = penaltyPointsAwarded
        self.servicePoints = servicePoints
        self.firstServeIn = firstServeIn
        self.firstServePointsWon = firstServePointsWon
        self.secondServePointsWon = secondServePointsWon
        self.secondServeIn = secondServeIn
        self.aces = aces
        self.doubleFaults = doubleFaults
        self.serviceWinners = serviceWinners
        self.servicePointsWon = servicePointsWon
        self.serviceGamesWon = serviceGamesWon
        self.returnPointsWon = returnPointsWon
        self.returnFirstServePointsWon = returnFirstServePointsWon
        self.returnSecondServePointsWon = returnSecondServePointsWon
        self.returnGamesWon = returnGamesWon
        self.breakPointsSaved = breakPointsSaved
        self.breakPointsConverted = breakPointsConverted
        self.winners = winners
        self.forcedErrors = forcedErrors
        self.unforcedErrors = unforcedErrors
        self.longestPointStreak = longestPointStreak
        self.longestGameStreak = longestGameStreak
    }
}

public struct StatsResult: Codable, Equatable, Sendable {
    public var provisional: Bool
    public var countedPoints: Int
    public var excludedPoints: Int
    public var sides: StatsResultSides
    public var servers: [String: ServeStats]
    public var shots: StatsResultShots
    public var rallyLength: StatsResultRallyLength
    public var review: StatsResultReview
    public var durationMs: ContractNullable<Int>
    public var momentum: StatsResultMomentum

    public init(provisional: Bool, countedPoints: Int, excludedPoints: Int, sides: StatsResultSides, servers: [String: ServeStats], shots: StatsResultShots, rallyLength: StatsResultRallyLength, review: StatsResultReview, durationMs: ContractNullable<Int>, momentum: StatsResultMomentum) {
        self.provisional = provisional
        self.countedPoints = countedPoints
        self.excludedPoints = excludedPoints
        self.sides = sides
        self.servers = servers
        self.shots = shots
        self.rallyLength = rallyLength
        self.review = review
        self.durationMs = durationMs
        self.momentum = momentum
    }
}

public struct StatsResultMomentum: Codable, Equatable, Sendable {
    public var window: Int
    public var side: StatsResultMomentumSide
    public var series: [StatsMomentumPair]

    public init(window: Int, side: StatsResultMomentumSide = .value, series: [StatsMomentumPair]) {
        self.window = window
        self.side = side
        self.series = series
    }
}

public enum StatsResultMomentumSide: String, Codable, CaseIterable, Hashable, Sendable {
    case value = "A"
}

public struct StatsResultRallyLength: Codable, Equatable, Sendable {
    public var value0_4: Int
    public var value5_8: Int
    public var value9_: Int
    public var unknown: Int

    enum CodingKeys: String, CodingKey {
        case value0_4 = "0-4"
        case value5_8 = "5-8"
        case value9_ = "9+"
        case unknown = "unknown"
    }
    public init(value0_4: Int, value5_8: Int, value9_: Int, unknown: Int) {
        self.value0_4 = value0_4
        self.value5_8 = value5_8
        self.value9_ = value9_
        self.unknown = unknown
    }
}

public struct StatsResultReview: Codable, Equatable, Sendable {
    public var reviewed: Int
    public var needsReview: Int
    public var unreviewed: Int
    public var completion: RateRatio

    public init(reviewed: Int, needsReview: Int, unreviewed: Int, completion: RateRatio) {
        self.reviewed = reviewed
        self.needsReview = needsReview
        self.unreviewed = unreviewed
        self.completion = completion
    }
}

public struct StatsResultShots: Codable, Equatable, Sendable {
    public var total: Int
    public var pointsWithStrokeCount: Int

    public init(total: Int, pointsWithStrokeCount: Int) {
        self.total = total
        self.pointsWithStrokeCount = pointsWithStrokeCount
    }
}

public struct StatsResultSides: Codable, Equatable, Sendable {
    public var A: SideStats
    public var B: SideStats

    public init(A: SideStats, B: SideStats) {
        self.A = A
        self.B = B
    }
}
