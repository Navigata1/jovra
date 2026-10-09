import Foundation
import JovraCore

/// Small restorable setup choices. The recording document is minted only after preflight.
struct CaptureSetupChoices: Hashable, Codable, Sendable {
    enum Format: String, CaseIterable, Codable, Sendable { case bestOfOne, bestOfThree }
    enum Player: String, CaseIterable, Codable, Sendable { case a, b }
    var title = ""
    var playerA = ""
    var playerB = ""
    var format = Format.bestOfThree
    var noAd = false
    var firstServer = Player.a
    var nearPlayer = Player.a

    var isValid: Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let players = [playerA, playerB].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return !title.isEmpty && title.unicodeScalars.count <= 120 && players.allSatisfy {
            !$0.isEmpty && $0.unicodeScalars.count <= 60
        }
    }

    var seed: CaptureSessionSeed {
        let names = [playerA, playerB].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let players = names.enumerated().map { index, name in
            SessionPlayer(id: index == 0 ? "player-a" : "player-b", displayName: name,
                          handedness: .unknown, backhand: .unknown, isSelf: index == 0)
        }
        return CaptureSessionSeed(title: title.trimmingCharacters(in: .whitespacesAndNewlines), players: players,
            format: .init(presetId: format == .bestOfOne ? .bestOf1 : (noAd ? .custom : .clubBo3),
                          setsToWin: format == .bestOfOne ? .value1 : .value2, gameScoring: noAd ? .noAd : .ad,
                          set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let),
            toss: .init(firstServer: firstServer == .a ? players[0].id : players[1].id,
                        startingEnds: .init(A: nearPlayer == .a ? .near : .far, B: nearPlayer == .a ? .far : .near)))
    }
}
