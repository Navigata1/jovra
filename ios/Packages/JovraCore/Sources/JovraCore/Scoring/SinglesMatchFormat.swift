/// The singles formats offered by Capture and Files import.
public enum SinglesMatchFormat: String, CaseIterable, Codable, Sendable {
    case bestOfOne
    case bestOfThree

    public func rules(gameScoring: SessionMatchFormatGameScoring) -> SessionMatchFormat {
        .init(presetId: self == .bestOfOne ? .bestOf1 : (gameScoring == .noAd ? .custom : .clubBo3),
              setsToWin: self == .bestOfOne ? .value1 : .value2, gameScoring: gameScoring,
              set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let)
    }
}
