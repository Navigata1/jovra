import Foundation

/// The people a player has recorded with before, offered first in the players editor (story 39). They come
/// only from sessions saved on this device; sample sessions never contribute a person.
///
/// A session's player ids are local to that session: capture writes every opponent as `player-b`, and an
/// import writes `player-a` and `player-b` without knowing who the player is. A recent player's id is
/// therefore derived from their name, so two people never share an id and none clashes with a seat's
/// default id.
public enum RecentPlayers {
    public static let defaultLimit = 8

    /// Everyone but the player themself, newest session first, once per name (ignoring case and spaces).
    /// The newest session's handedness and backhand win.
    public static func from(_ summaries: [SessionSummary], limit: Int = .max) -> [SessionSetup.Player] {
        var seen = Set<String>()
        var result: [SessionSetup.Player] = []
        let newestFirst = summaries.filter { !$0.sample }.sorted { $0.createdAt > $1.createdAt }
        for summary in newestFirst {
            for player in summary.players where !player.isSelf {
                let name = player.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = normalized(name)
                guard !name.isEmpty, !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(.init(id: id(forName: name), name: name, handedness: player.handedness, backhand: player.backhand))
                if result.count >= max(limit, 0) { return result }
            }
        }
        return result
    }

    /// What the players editor offers for `setup`: nobody already named in a seat in play (the player
    /// themself included, which an imported session cannot tell apart), at most `limit` people.
    public static func offered(_ recents: [SessionSetup.Player], for setup: SessionSetup,
                               limit: Int = defaultLimit) -> [SessionSetup.Player] {
        let seated = Set(setup.seatsInPlay.map { normalized(setup[$0].name) }.filter { !$0.isEmpty })
        return Array(recents.filter { !seated.contains(normalized($0.name)) }.prefix(max(limit, 0)))
    }

    /// A stable id for a person known only by name: "recent-" and a 64-bit FNV-1a hash of the name,
    /// lowercased and trimmed. It satisfies the contract's id pattern for any name.
    public static func id(forName name: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in normalized(name).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return "recent-" + String(repeating: "0", count: 16 - hex.count) + hex
    }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
