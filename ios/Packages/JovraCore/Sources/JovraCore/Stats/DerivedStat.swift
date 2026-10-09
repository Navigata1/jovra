import Foundation

/// The first overview's supported selectors. Other stats remain in the closed numeric result.
public enum StatsMetric: Equatable, Sendable {
    case points, pointsWon(Side), firstServeIn(Side), firstServePointsWon(Side), shots
}
public enum StatValue: Equatable, Sendable { case count(Int), ratio(RateRatio) }
public struct StatEvidence: Equatable, Sendable {
    public let provenance: Provenance?
    public let contributingPointIDs: [String]
    public let unreviewedCount: Int
    public let sample: Bool
}
public struct DerivedStat: Equatable, Sendable {
    /// Absence means no contributing observations; the UI renders an em dash.
    public let value: StatValue?
    public let evidence: StatEvidence
}

extension StatsEngine {
    public static func metric(_ metric: StatsMetric, in timeline: MatchTimeline, sample: Bool = false) throws -> DerivedStat {
        let stats = try compute(timeline)
        let counted = timeline.points.filter { $0.determined && !$0.afterMatchEnd && $0.winner.value != nil }
        let played = counted.filter { $0.kind == .point }
        let points: [TimelinePointRecord]
        let value: StatValue
        switch metric {
        case .points: points = counted; value = .count(stats.countedPoints)
        case .pointsWon(let side):
            points = counted; value = .ratio(side == .a ? stats.sides.A.totalPointsWon : stats.sides.B.totalPointsWon)
        case .firstServeIn(let side):
            points = played.filter { $0.serverSide.value == side.timeline && $0.serveNumber.value != nil }
            value = .ratio(side == .a ? stats.sides.A.firstServeIn : stats.sides.B.firstServeIn)
        case .firstServePointsWon(let side):
            points = played.filter { $0.serverSide.value == side.timeline && $0.serveNumber.value?.rawValue == 1 }
            value = .ratio(side == .a ? stats.sides.A.firstServePointsWon : stats.sides.B.firstServePointsWon)
        case .shots:
            points = played.filter { $0.strokeCount.value != nil }; value = .count(stats.shots.total)
        }
        let weakest = points.map(\.provenance).min { rank($0) < rank($1) }
        return .init(value: points.isEmpty ? nil : value,
            evidence: .init(provenance: weakest, contributingPointIDs: points.map(\.id),
                            unreviewedCount: points.filter { $0.reviewState != .reviewed }.count, sample: sample))
    }
    private static func rank(_ provenance: Provenance) -> Int {
        switch provenance { case .estimated: 0; case .manual: 1; case .reviewed: 2; case .validated: 3 }
    }
}
