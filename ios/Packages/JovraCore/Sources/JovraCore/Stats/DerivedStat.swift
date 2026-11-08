import Foundation

/// The first overview's supported selectors. Every other stat is reachable by its contract name through `lines`.
public enum StatSelector: Equatable, Sendable {
    case points, pointsWon(Side), firstServeIn(Side), firstServePointsWon(Side), shots
}
public enum StatValue: Equatable, Sendable { case count(Int), ratio(RateRatio) }
public struct StatEvidence: Equatable, Sendable {
    /// The weakest provenance among the contributing points; nil when nothing contributed.
    public let provenance: Provenance?
    public let contributingPointIDs: [String]
    /// Contributing points not yet reviewed ("Estimated · includes 8 unreviewed points").
    public let unreviewedCount: Int
    public let sample: Bool
}
public struct DerivedStat: Equatable, Sendable {
    /// Absence means no contributing observations; the UI renders an em dash.
    public let value: StatValue?
    public let evidence: StatEvidence
}

/// Names one stat line: a stats.csv contract name, the side it belongs to (side-scoped rows) and, for doubles
/// per-server serve stats, the server's player id.
public struct StatKey: Hashable, Sendable, CustomStringConvertible {
    public let stat: String
    public let side: Side?
    public let server: String?
    public init(stat: String, side: Side? = nil, server: String? = nil) { self.stat = stat; self.side = side; self.server = server }
    public var description: String { [server.map { "server \($0)" }, side.map { "side \($0.rawValue)" }, stat].compactMap { $0 }.joined(separator: " ") }
}
public struct StatLine: Equatable, Sendable {
    public let key: StatKey
    public let stat: DerivedStat
}

extension StatsEngine {
    public static func stat(_ selector: StatSelector, in timeline: MatchTimeline, sample: Bool = false) throws -> DerivedStat {
        let stats = try compute(timeline)
        switch selector {
        case .points:
            return derived(.count(stats.countedPoints), points: counted(timeline), sample: sample)
        case .pointsWon(let side): return try line(.init(stat: "totalPointsWon", side: side), stats, timeline, sample)
        case .firstServeIn(let side): return try line(.init(stat: "firstServeIn", side: side), stats, timeline, sample)
        case .firstServePointsWon(let side): return try line(.init(stat: "firstServePointsWon", side: side), stats, timeline, sample)
        case .shots: return try line(.init(stat: "shots.total"), stats, timeline, sample)
        }
    }

    /// Every stat line in stats.csv order (then doubles per-server serve stats, by server id), each with its fraction,
    /// weakest-input provenance, contributing point ids and unreviewed count.
    public static func lines(_ timeline: MatchTimeline, sample: Bool = false) throws -> [StatLine] {
        let stats = try compute(timeline)
        return try catalogue(stats).map { StatLine(key: $0, stat: try line($0, stats, timeline, sample)) }
    }

    static func catalogue(_ stats: StatsResult) throws -> [StatKey] {
        guard let rows = try CSV.contract(.stats).rows else { throw DataExportError.unsupportedContract("stats rows") }
        let contract = rows.flatMap { row in
            row.scope == .side ? [StatKey(stat: row.stat, side: .a), StatKey(stat: row.stat, side: .b)] : [StatKey(stat: row.stat)]
        }
        let servers = stats.servers.keys.sorted().flatMap { id in serveFields.map { StatKey(stat: $0, server: id) } }
        return contract + servers
    }

    static let serveFields = ["servicePoints", "firstServeIn", "firstServePointsWon", "secondServePointsWon", "secondServeIn",
                              "aces", "doubleFaults", "serviceWinners", "servicePointsWon"]

    static func value(_ key: StatKey, _ stats: StatsResult) throws -> StatValue? {
        guard let server = key.server else { return try ExportStats.value(key.stat, side: key.side, stats: stats) }
        guard let serve = stats.servers[server] else { return nil }
        switch key.stat {
        case "servicePoints": return .count(serve.servicePoints)
        case "firstServeIn": return .ratio(serve.firstServeIn)
        case "firstServePointsWon": return .ratio(serve.firstServePointsWon)
        case "secondServePointsWon": return .ratio(serve.secondServePointsWon)
        case "secondServeIn": return .ratio(serve.secondServeIn)
        case "aces": return .count(serve.aces)
        case "doubleFaults": return .count(serve.doubleFaults)
        case "serviceWinners": return .count(serve.serviceWinners)
        case "servicePointsWon": return .ratio(serve.servicePointsWon)
        default: throw DataExportError.unsupportedContract(key.stat)
        }
    }

    private static func line(_ key: StatKey, _ stats: StatsResult, _ timeline: MatchTimeline, _ sample: Bool) throws -> DerivedStat {
        guard let value = try value(key, stats) else { throw DataExportError.unsupportedContract(key.description) }
        return derived(value, points: try contributors(key, timeline), sample: sample)
    }

    private static func derived(_ value: StatValue, points: [TimelinePointRecord], sample: Bool) -> DerivedStat {
        let weakest = points.map(\.provenance).min { rank($0) < rank($1) }
        return .init(value: points.isEmpty ? nil : value,
            evidence: .init(provenance: weakest, contributingPointIDs: points.map(\.id),
                            unreviewedCount: points.filter { $0.reviewState != .reviewed }.count, sample: sample))
    }

    private static func counted(_ timeline: MatchTimeline) -> [TimelinePointRecord] {
        timeline.points.filter { $0.determined && !$0.afterMatchEnd && $0.winner.value != nil }
    }

    /// The population each stat is taken over: the denominator's points for a rate, the points scanned for a count.
    static func contributors(_ key: StatKey, _ timeline: MatchTimeline) throws -> [TimelinePointRecord] {
        let counted = counted(timeline)
        let played = counted.filter { $0.kind == .point }
        if let server = key.server {
            return serve(key.stat, played.filter { $0.server.value == server })
        }
        guard let side = key.side else {
            switch key.stat {
            case "shots.total": return played.filter { $0.strokeCount.value != nil }
            case let name where name.hasPrefix("rallyLength."): return played
            case "review.completion", "review.needsReview": return timeline.points.filter { $0.kind == .point && !$0.afterMatchEnd }
            default: throw DataExportError.unsupportedContract(key.stat)
            }
        }
        let served = played.filter { $0.serverSide.value == side.timeline }
        let returned = played.filter { $0.serverSide.value == side.other.timeline }
        let complete = timeline.games.filter(\.complete)
        func inGames(_ games: [TimelineGameRecord]) -> [TimelinePointRecord] {
            let indices = Set(games.map(\.index))
            return counted.filter { $0.game.value.map(indices.contains) ?? false }
        }
        let serviceGames = complete.filter { $0.kind == .standard && !$0.byPenalty && $0.serverSide == side }
        let returnGames = complete.filter { $0.kind == .standard && !$0.byPenalty && $0.serverSide == side.other }
        switch key.stat {
        case "totalPointsWon", "penaltyPointsAwarded", "longestPointStreak": return counted
        case "returnPointsWon": return returned
        case "returnFirstServePointsWon": return returned.filter { $0.serveNumber.value?.rawValue == 1 }
        case "returnSecondServePointsWon": return returned.filter { $0.serveNumber.value?.rawValue == 2 }
        case "serviceGamesWon": return inGames(serviceGames)
        case "returnGamesWon": return inGames(returnGames)
        case "breakPointsSaved": return counted.filter { $0.serverSide.value == side.timeline && $0.pressure.value?.breakPoint == true }
        case "breakPointsConverted": return counted.filter { $0.serverSide.value == side.other.timeline && $0.pressure.value?.breakPoint == true }
        case "winners", "forcedErrors", "unforcedErrors": return played
        case "longestGameStreak": return inGames(complete)
        case let name where serveFields.contains(name): return serve(name, served)
        default: throw DataExportError.unsupportedContract(key.stat)
        }
    }

    private static func serve(_ stat: String, _ served: [TimelinePointRecord]) -> [TimelinePointRecord] {
        switch stat {
        case "firstServeIn": return served.filter { $0.serveNumber.value != nil }
        case "firstServePointsWon": return served.filter { $0.serveNumber.value?.rawValue == 1 }
        case "secondServePointsWon", "secondServeIn": return served.filter { $0.serveNumber.value?.rawValue == 2 }
        default: return served
        }
    }

    private static func rank(_ provenance: Provenance) -> Int {
        switch provenance { case .estimated: 0; case .manual: 1; case .reviewed: 2; case .validated: 3 }
    }
}
