import Foundation

struct ResolvedLog {
    var placed: [SessionLogEvent]
    var orders: [Int: SessionDoublesOrderEvent]
    var history: TimelineHistory
}

enum LogResolver {
    static func resolve(_ events: [SessionLogEvent]) throws -> ResolvedLog {
        var seen: [String: SessionLogEvent] = [:], last = 0
        for event in events {
            guard seen[event.id] == nil else { throw ScoringError(.duplicateId, event.id) }
            guard event.seq > last else { throw ScoringError(.seqNotIncreasing, event.id) }
            seen[event.id] = event; last = event.seq
        }
        for case .void(let event) in events {
            guard let target = seen[event.target] else { throw ScoringError(.voidTargetMissing, event.id) }
            guard target.seq < event.seq else { throw ScoringError(.voidTargetNotEarlier, event.id) }
        }
        var voided = Set<String>()
        for event in events.reversed() where !voided.contains(event.id) {
            if case .void(let v) = event { voided.insert(v.target) }
        }
        var order: [String] = [], replaced: [String: String] = [:], byID: [String: SessionLogEvent] = [:]
        var doubles: [Int: SessionDoublesOrderEvent] = [:], inert = voided, tombstones = Set<String>()
        func current(_ value: String) -> String { var id = value; while let next = replaced[id] { id = next }; return id }
        func slot(_ value: String) -> String {
            var id = current(value), visited = Set<String>()
            while !order.contains(id), let target = seen[id]?.supersedes {
                if !visited.insert(id).inserted { break }
                id = current(target)
            }
            return id
        }
        for event in events {
            switch event {
            case .void: continue
            case .doublesOrder(let v): if !voided.contains(v.id) { doubles[v.setIndex] = v }; continue
            default: break
            }
            if let supersedes = event.supersedes {
                if voided.contains(event.id) { continue }
                let target = current(supersedes)
                if inert.contains(target) { inert.insert(event.id); continue }
                guard let index = order.firstIndex(of: target) else { throw ScoringError(.supersedeTargetMissing, event.id) }
                guard byID[target]?.typeString == event.typeString else { throw ScoringError(.supersedeTypeMismatch, event.id) }
                order[index] = event.id; replaced[target] = event.id
            } else if let insert = event.insertBefore {
                let target = slot(insert)
                guard let index = order.firstIndex(of: target) else {
                    if voided.contains(event.id) { continue }
                    throw ScoringError(.insertTargetMissing, event.id)
                }
                order.insert(event.id, at: index)
            } else { order.append(event.id) }
            byID[event.id] = event
            if inert.contains(event.id) { tombstones.insert(event.id) }
        }
        return ResolvedLog(placed: order.filter { !tombstones.contains($0) }.compactMap { byID[$0] }, orders: doubles,
            history: TimelineHistory(voided: voided.sorted(), superseded: replaced.keys.sorted().map { .init(id: $0, by: replaced[$0]!) }))
    }
}
