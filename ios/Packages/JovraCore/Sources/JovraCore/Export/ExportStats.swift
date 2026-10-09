import Foundation

enum ExportStats {
    static func value(_ name: String, side: Side?, stats: StatsResult) throws -> StatValue {
        guard let side else {
            switch name {
            case "shots.total": return .count(stats.shots.total)
            case "rallyLength.0-4": return .count(stats.rallyLength.value0_4)
            case "rallyLength.5-8": return .count(stats.rallyLength.value5_8)
            case "rallyLength.9+": return .count(stats.rallyLength.value9_)
            case "rallyLength.unknown": return .count(stats.rallyLength.unknown)
            case "review.completion": return .ratio(stats.review.completion)
            case "review.needsReview": return .count(stats.review.needsReview)
            default: throw DataExportError.unsupportedContract(name)
            }
        }
        let value = side == .a ? stats.sides.A : stats.sides.B
        switch name {
        case "totalPointsWon": return .ratio(value.totalPointsWon)
        case "servicePoints": return .count(value.servicePoints)
        case "firstServeIn": return .ratio(value.firstServeIn)
        case "firstServePointsWon": return .ratio(value.firstServePointsWon)
        case "secondServePointsWon": return .ratio(value.secondServePointsWon)
        case "secondServeIn": return .ratio(value.secondServeIn)
        case "aces": return .count(value.aces)
        case "doubleFaults": return .count(value.doubleFaults)
        case "serviceWinners": return .count(value.serviceWinners)
        case "servicePointsWon": return .ratio(value.servicePointsWon)
        case "serviceGamesWon": return .ratio(value.serviceGamesWon)
        case "returnPointsWon": return .ratio(value.returnPointsWon)
        case "returnFirstServePointsWon": return .ratio(value.returnFirstServePointsWon)
        case "returnSecondServePointsWon": return .ratio(value.returnSecondServePointsWon)
        case "returnGamesWon": return .ratio(value.returnGamesWon)
        case "breakPointsSaved": return .ratio(value.breakPointsSaved)
        case "breakPointsConverted": return .ratio(value.breakPointsConverted)
        case "winners": return .count(value.winners)
        case "forcedErrors": return .count(value.forcedErrors)
        case "unforcedErrors": return .count(value.unforcedErrors)
        case "penaltyPointsAwarded": return .count(value.penaltyPointsAwarded)
        case "longestPointStreak": return .count(value.longestPointStreak)
        case "longestGameStreak": return .count(value.longestGameStreak)
        default: throw DataExportError.unsupportedContract(name)
        }
    }
}
