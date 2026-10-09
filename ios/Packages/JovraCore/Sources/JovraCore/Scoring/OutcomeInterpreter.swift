import Foundation

enum OutcomeInterpreter {
    static func serveNumber(_ outcome: SessionOutcome) -> (Int?, Bool) {
        let attempts = (outcome.serves ?? []).filter { $0.result != .let }.map { $0.result }
        if outcome.endType == .doubleFault { return (2, attempts.isEmpty || attempts == [.fault, .fault]) }
        if attempts.isEmpty { return (nil, true) }
        if attempts == [.in] { return (1, true) }
        if attempts == [.fault] || attempts == [.fault, .in] { return (2, true) }
        return (nil, false)
    }
    static func rallyLength(_ outcome: SessionOutcome) -> Int? {
        if let length = outcome.rallyLength { return length }
        if outcome.endType == .doubleFault { return 0 }
        guard let count = outcome.strokeCount else { return nil }
        switch outcome.endType {
        case .forcedError, .unforcedError: return count > 0 ? count - 1 : nil
        case .serviceWinner where count == 2: return count - 1
        case .winner, .ace, .serviceWinner: return count
        default: return nil
        }
    }
    static func consistent(_ outcome: SessionOutcome, winner: Side, server: Side) -> Bool {
        let n = outcome.strokeCount
        switch outcome.endType {
        case .doubleFault: return winner != server && (n == nil || n == 0)
        case .ace: return winner == server && (n == nil || n == 1)
        case .serviceWinner: return winner == server && (n == nil || n == 1 || n == 2)
        case .winner, .forcedError, .unforcedError:
            guard let n else { return true }; guard n >= 2 else { return false }
            let hitter = n % 2 == 1 ? server : server.other
            return outcome.endType == .winner ? hitter == winner : hitter != winner
        default: return true
        }
    }
    static func record(event: SessionLogEvent, index: Int, state: TimelinePointState?, afterEnd: Bool, outcome: SessionOutcome?, winner: Side?) -> TimelinePointRecord {
        let point: SessionPointEvent? = { if case .point(let v) = event { v } else { nil } }()
        let penalty = outcome == nil
        return .init(id: event.id, index: index, kind: penalty ? .penaltyPoint : .point, determined: state != nil, afterMatchEnd: afterEnd,
            set: .init(state?.set), game: .init(state?.game), gameInSet: .init(state?.gameInSet),
            tiebreak: .init(state?.tiebreak.value.flatMap { TimelinePointRecordTiebreak(rawValue: $0.rawValue) }), pointInGame: .init(state?.pointInGame),
            server: .init(state?.server), receiver: state?.receiver ?? .null, serverSide: .init(state?.serverSide.timeline),
            courtSide: .init(state?.courtSide.value.flatMap { TimelinePointRecordCourtSide(rawValue: $0.rawValue) }), ends: .init(state?.ends),
            before: .init(state?.before), call: .init(state?.call), pressure: .init(state?.pressure), winner: .init(winner?.timeline),
            endType: penalty ? .penalty : TimelinePointRecordEndType(rawValue: outcome!.endType.rawValue)!,
            serveNumber: .init(outcome.flatMap { serveNumber($0).0 }.flatMap(TimelinePointRecordServeNumber.init(rawValue:))),
            strokeCount: .init(outcome?.strokeCount), rallyLength: .init(outcome.flatMap(rallyLength)), provenance: outcome?.provenance ?? .manual,
            reviewState: penalty ? .reviewed : TimelinePointRecordReviewState(rawValue: point?.reviewState?.rawValue ?? "unreviewed")!,
            tStartMs: point?.tStartMs, tEndMs: point?.tEndMs, after: .null)
    }
}
