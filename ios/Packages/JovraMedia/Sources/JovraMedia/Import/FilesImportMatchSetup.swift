import Foundation
import JovraCore

/// Caller-supplied setup for complete singles footage. Video metadata never supplies scoring facts.
public struct FilesImportMatchSetup: Sendable {
    public let playerA: String
    public let playerB: String
    public let format: SinglesMatchFormat
    public let gameScoring: SessionMatchFormatGameScoring
    public let firstServer: Side
    public let nearPlayer: Side
    public let containsFullMatch: Bool

    public init(playerA: String, playerB: String, format: SinglesMatchFormat,
                gameScoring: SessionMatchFormatGameScoring, firstServer: Side, nearPlayer: Side,
                containsFullMatch: Bool) {
        self.playerA = playerA.trimmingCharacters(in: .whitespacesAndNewlines)
        self.playerB = playerB.trimmingCharacters(in: .whitespacesAndNewlines)
        self.format = format
        self.gameScoring = gameScoring
        self.firstServer = firstServer
        self.nearPlayer = nearPlayer
        self.containsFullMatch = containsFullMatch
    }

    public var isValid: Bool {
        containsFullMatch && [playerA, playerB].allSatisfy { !$0.isEmpty && $0.unicodeScalars.count <= 60 }
    }

    func scoringInput() throws -> ScoringInput {
        guard isValid else { throw FilesImportError.invalidMatchSetup }
        let a = SessionPlayer(id: "player-a", displayName: playerA, handedness: .unknown, backhand: .unknown, isSelf: false)
        let b = SessionPlayer(id: "player-b", displayName: playerB, handedness: .unknown, backhand: .unknown, isSelf: false)
        return ScoringInput(format: format.rules(gameScoring: gameScoring), players: [a, b],
            sides: .init(A: [a.id], B: [b.id]), toss: .init(firstServer: firstServer == .a ? a.id : b.id,
                startingEnds: .init(A: nearPlayer == .a ? .near : .far, B: nearPlayer == .a ? .far : .near)), log: [])
    }
}
