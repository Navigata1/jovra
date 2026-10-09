import Foundation

struct OrderOverrides {
    let mode: SessionMatchResolutionMode
    var servers: [String: SessionServerOverrideEvent] = [:], receivers: [String: SessionReceiverOverrideEvent] = [:]
    var receivingOrders: [Side: (game: Int, player: String)] = [:]
    init(_ input: ScoringInput, placed: [SessionLogEvent]) throws {
        mode = input.resolutionMode ?? .rules
        var sideOf: [String: Side] = [:]
        for side in Side.allCases { for player in input.sides[side] { sideOf[player] = side } }
        let byID = Dictionary(uniqueKeysWithValues: input.log.map { ($0.id, $0) }), doubles = input.sides.A.count == 2
        for event in input.log {
            let targetID: String
            switch event { case .serverOverride(let v): targetID = v.targetPointId; case .receiverOverride(let v): targetID = v.targetPointId; default: continue }
            guard let target = byID[targetID] else { throw ScoringError(.overrideTargetMissing, event.id) }
            guard case .point = target, target.seq < event.seq else { throw ScoringError(.overrideTargetInvalid, event.id) }
            switch event {
            case .serverOverride(let v):
                guard ([v.server] + (v.rotation ?? [])).allSatisfy({ sideOf[$0] != nil }) else { throw ScoringError(.unknownPlayer, event.id) }
                if v.continuation == .pointOnly {
                    guard v.discoveryAfterPointId == nil, v.rotation == nil else { throw ScoringError(.overrideMetadataInvalid, event.id) }
                } else {
                    guard v.discoveryAfterPointId == v.targetPointId else { throw ScoringError(.overrideMetadataInvalid, event.id) }
                    if doubles {
                        guard let rotation = v.rotation, rotation.count == 4, Set(rotation) == Set(sideOf.keys), rotation[0] == v.server,
                              (0..<4).allSatisfy({ sideOf[rotation[$0]] != sideOf[rotation[($0 + 1) % 4]] }) else { throw ScoringError(.overrideRotationInvalid, event.id) }
                    } else if v.rotation != nil { throw ScoringError(.overrideRotationInvalid, event.id) }
                }
            case .receiverOverride(let v):
                guard sideOf[v.deuceReceiver] != nil else { throw ScoringError(.unknownPlayer, event.id) }
                guard doubles, sideOf[v.deuceReceiver]?.rawValue == v.receivingSide.rawValue else { throw ScoringError(.receiverOverrideInvalid, event.id) }
            default: break
            }
        }
        let active = Set(placed.compactMap { event -> String? in if case .point = event { event.id } else { nil } })
        for event in placed {
            switch event {
            case .serverOverride(let v) where active.contains(v.targetPointId): servers[v.targetPointId] = v
            case .receiverOverride(let v) where active.contains(v.targetPointId): receivers[v.targetPointId] = v
            default: break
            }
        }
    }
    mutating func beforePoint(_ match: inout MatchState, event: SessionLogEvent, winner: Side?, conflicts: inout [TimelineConflict]) throws -> String {
        var server = match.server()
        if let observation = servers[event.id] {
            if mode == .rules {
                if observation.server != server { conflicts.append(.init(type: .serverMismatch, pointId: event.id, recorded: observation.server, derived: server)) }
            } else {
                server = observation.server
                var valid = observation.continuation == .pointOnly
                if observation.continuation == .completedStandardGame {
                    if match.tb == nil, let winner { var probe = match; valid = try probe.apply(winner).gameWon }
                } else if observation.continuation == .oddTiebreak { valid = match.tb != nil && (match.pointInGame + 1) % 2 == 1 }
                if !valid { conflicts.append(.init(type: .overrideContextChanged, pointId: event.id, eventId: observation.id)) }
                else if observation.continuation != .pointOnly {
                    let offset = match.tb == nil ? 0 : (match.pointInGame + 1) / 2, side = match.sideOf[server]!
                    match.firstSide = (match.matchGame + offset) % 2 == 0 ? side : side.other
                    if match.doubles {
                        let current = (match.gameInSet + offset) % 4, rotation = observation.rotation!
                        match.rotation = (0..<4).map { rotation[($0 - current + 4) % 4] }
                    }
                }
            }
        }
        if let receiver = receivers[event.id] {
            let side = Side(rawValue: receiver.receivingSide.rawValue)!
            if mode == .rules {
                let derived = match.deuceReceivers[side]!
                if receiver.deuceReceiver != derived { conflicts.append(.init(type: .receiverMismatch, pointId: event.id, recorded: receiver.deuceReceiver, derived: derived)) }
            } else if side != match.sideOf[server]!.other { conflicts.append(.init(type: .overrideContextChanged, pointId: event.id, eventId: receiver.id)) }
            else { receivingOrders[side] = (match.matchGame, receiver.deuceReceiver) }
        }
        return server
    }
    func receiver(_ match: MatchState, server: String, courtSide: TimelinePointStateCourtSide?) -> String? {
        let side = match.sideOf[server]!.other
        if let order = receivingOrders[side], order.game == match.matchGame, let courtSide { return courtSide == .deuce ? order.player : match.partner(order.player) }
        return match.receiver(server, courtSide)
    }
}
