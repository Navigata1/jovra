import Foundation

/// The people a player has recorded with before, offered first in the players editor (story 39). They come
/// only from sessions saved on this device; sample sessions never contribute a person.
public enum RecentPlayers {
    public static let defaultLimit = 8

    /// Everyone but the player themself, newest session first, once per name (ignoring case and spaces).
    /// The newest session's id and handedness win, so a picked opponent keeps their head-to-head history.
    public static func from(_ summaries: [SessionSummary], limit: Int = defaultLimit) -> [SessionSetup.Player] {
        var seen = Set<String>()
        var result: [SessionSetup.Player] = []
        let newestFirst = summaries.filter { !$0.sample }.sorted { $0.createdAt > $1.createdAt }
        for summary in newestFirst {
            for player in summary.players where !player.isSelf {
                let name = player.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = name.lowercased()
                guard !name.isEmpty, !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(.init(id: player.id, name: name, handedness: player.handedness, backhand: player.backhand))
                if result.count == max(limit, 0) { return result }
            }
        }
        return result
    }
}
