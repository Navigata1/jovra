import Foundation

enum PointCSV {
    static func cell(_ name: String, point p: TimelinePointRecord, names: [String: String], sideNames: [Side: String], contract: CSVContract) throws -> String? {
        switch name {
        case "point_number": return String(p.index + 1)
        case "point_id": return p.id
        case "kind": return p.kind.rawValue
        case "set_number": return p.set.value.map { String($0 + 1) }
        case "game_number": return p.game.value.map { String($0 + 1) }
        case "game_in_set": return p.gameInSet.value.map { String($0 + 1) }
        case "tiebreak": return p.tiebreak.value?.rawValue
        case "server": return p.server.value.flatMap { names[$0] }
        case "receiver": return p.receiver.value.flatMap { names[$0] }
        case "server_side": return p.serverSide.value?.rawValue
        case "court_side": return p.courtSide.value?.rawValue
        case "score_before": return p.call.value.map { call($0, serverSide: p.serverSide.value) }
        case "games_before": return p.before.value.map { "\($0.games.A)-\($0.games.B)" }
        case "sets_before": return p.before.value.map { "\($0.sets.A)-\($0.sets.B)" }
        case "winner_side": return p.winner.value?.rawValue
        case "winner": return p.winner.value.flatMap { Side(rawValue: $0.rawValue) }.flatMap { sideNames[$0] }
        case "end_type": return p.endType.rawValue
        case "serve_number": return p.serveNumber.value.map { String($0.rawValue) }
        case "stroke_count": return p.strokeCount.value.map { String($0) }
        case "rally_length": return p.rallyLength.value.map { String($0) }
        case "break_point": return p.pressure.value.map { CSV.boolean($0.breakPoint, contract: contract) }
        case "t_start_ms": return p.tStartMs.map { String($0) }
        case "t_end_ms": return p.tEndMs.map { String($0) }
        case "provenance": return p.provenance.rawValue
        case "review_state": return p.reviewState.rawValue
        case "determined": return CSV.boolean(p.determined, contract: contract)
        case "after_match_end": return CSV.boolean(p.afterMatchEnd, contract: contract)
        default: throw DataExportError.unsupportedContract(name)
        }
    }
    private static func call(_ call: TimelineCall, serverSide: TimelineSideOrNull?) -> String {
        switch call {
        case .points(let value): return value.server.rawValue + "-" + value.receiver.rawValue
        case .deuce: return "40-40"
        case .advantage(let value): return value.side.rawValue == serverSide?.rawValue ? "AD-40" : "40-AD"
        case .tiebreak(let value): return "\(value.server)-\(value.receiver)"
        }
    }
}
