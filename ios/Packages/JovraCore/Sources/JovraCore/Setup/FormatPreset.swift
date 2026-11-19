import Foundation

/// The match formats session setup knows (user story 42). Each one is exactly the format of a scoring
/// fixture in `spec/fixtures/scoring`, so a preset can never drift from what the engine was proved on.
public enum FormatPreset: String, CaseIterable, Codable, Hashable, Sendable {
    /// Best of 3 tie-break sets: the default.
    case clubBestOf3
    /// Best of 3 with a 10-point match tie-break in lieu of a third set.
    case matchTiebreakThird
    /// No-Ad games with a 10-point match tie-break in lieu of a third set.
    case noAdMatchTiebreak
    /// Best of 5 with a 10-point tie-break at 6–6 in the fifth.
    case bestOf5
    /// One set to 8 games with a tie-break at 8–8.
    case proSet8
    /// Sets to 4 games, No-Ad, with a match tie-break in lieu of a third set.
    case shortSets
    /// A standalone tie-break to 7.
    case tiebreak7
    /// A standalone tie-break to 10.
    case tiebreak10
    /// One tie-break set.
    case oneSet
    /// Fast4. Its rules are recorded as unverified, so it is defined and tested but not offered.
    case fast4
    /// A free-count practice set. The engine has no rule for a set without an end, so it is not offered.
    case practiceSet

    public enum Availability: Equatable, Sendable {
        case offered
        /// The rules behind this preset are not confirmed (`ruleStatus: unverified`).
        case rulesUnconfirmed
        /// The scoring engine cannot play this format yet.
        case scoringNotBuilt
    }

    public var availability: Availability {
        switch self {
        case .fast4: .rulesUnconfirmed
        case .practiceSet: .scoringNotBuilt
        default: .offered
        }
    }

    /// The presets a player can choose, in the order the format sheet lists them.
    public static let offered: [FormatPreset] = allCases.filter { $0.availability == .offered }

    public var format: SessionMatchFormat {
        let standard = SessionTiebreakRule(points: 7)
        let sixGames = SessionSetRule.tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: standard))
        let matchTiebreak = SessionSetRule.matchTiebreak(.init(tiebreak: .init(points: 10)))
        switch self {
        case .clubBestOf3:
            return .init(presetId: .clubBo3, setsToWin: .value2, gameScoring: .ad, set: sixGames, lets: .let)
        case .matchTiebreakThird:
            return .init(presetId: .ustaMtb, setsToWin: .value2, gameScoring: .ad, set: sixGames, finalSet: matchTiebreak, lets: .let)
        case .noAdMatchTiebreak:
            return .init(presetId: .noadMtb, setsToWin: .value2, gameScoring: .noAd, set: sixGames, finalSet: matchTiebreak, lets: .let)
        case .bestOf5:
            return .init(presetId: .slamBo5, setsToWin: .value3, gameScoring: .ad, set: sixGames,
                         finalSet: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 10))), lets: .let)
        case .proSet8:
            return .init(presetId: .proSet8, setsToWin: .value1, gameScoring: .ad,
                         set: .tiebreakSet(.init(games: 8, tiebreakAt: 8, tiebreak: standard)), lets: .let)
        case .shortSets:
            return .init(presetId: .shortSets, setsToWin: .value2, gameScoring: .noAd,
                         set: .tiebreakSet(.init(games: 4, tiebreakAt: 4, tiebreak: standard)), finalSet: matchTiebreak, lets: .let)
        case .tiebreak7:
            return .init(presetId: .tbOnly7, setsToWin: .value1, gameScoring: .ad, set: .matchTiebreak(.init(tiebreak: standard)), lets: .let)
        case .tiebreak10:
            return .init(presetId: .tbOnly10, setsToWin: .value1, gameScoring: .ad, set: matchTiebreak, lets: .let)
        case .oneSet:
            return .init(presetId: .bestOf1, setsToWin: .value1, gameScoring: .ad, set: sixGames, lets: .let)
        case .fast4:
            let short = SessionSetRule.tiebreakSet(.init(games: 4, tiebreakAt: 3,
                tiebreak: .init(points: 5, suddenDeathAt: 4, endChange: .after4)))
            return .init(presetId: .fast4, setsToWin: .value2, gameScoring: .noAd, set: short, finalSet: short,
                         lets: .noLet, ruleStatus: .unverified)
        case .practiceSet:
            // Games are counted with advantage scoring; there is no engine rule for "no match end" yet.
            return .init(presetId: .custom, setsToWin: .value1, gameScoring: .ad, set: .advantageSet(.init(games: 6)), lets: .let)
        }
    }

    /// What kind of session a match in this format is stored as.
    public var sessionKind: SessionDocumentSessionKind {
        switch self {
        case .tiebreak7, .tiebreak10: .tiebreakOnly
        case .practiceSet: .practiceSet
        default: .match
        }
    }
}

/// A preset plus the three overrides the format sheet offers: game scoring, how a set ends, and lets.
/// An override equal to the preset's own rule is not a change; any real change makes the format `custom`.
public struct FormatChoice: Codable, Hashable, Sendable {
    public enum SetEnding: String, Codable, CaseIterable, Hashable, Sendable {
        /// A tie-break at the preset's games-all score ("Tie-break at 6–6").
        case tiebreak
        /// Play on until one side leads by two games ("Advantage set").
        case advantageSet
    }

    public var preset: FormatPreset
    public var gameScoring: SessionMatchFormatGameScoring?
    public var setEnding: SetEnding?
    public var lets: SessionMatchFormatLets?

    public init(preset: FormatPreset = .clubBestOf3, gameScoring: SessionMatchFormatGameScoring? = nil,
                setEnding: SetEnding? = nil, lets: SessionMatchFormatLets? = nil) {
        self.preset = preset; self.gameScoring = gameScoring; self.setEnding = setEnding; self.lets = lets
    }

    /// A standalone tie-break has no games: Ad or No-Ad does not apply.
    public var allowsGameScoringOverride: Bool {
        if case .matchTiebreak = preset.format.set { false } else { true }
    }

    /// Only a format played in sets of games can end its sets another way.
    public var allowsSetEndingOverride: Bool { allowsGameScoringOverride }

    public var effectiveGameScoring: SessionMatchFormatGameScoring {
        allowsGameScoringOverride ? gameScoring ?? preset.format.gameScoring : preset.format.gameScoring
    }

    public var effectiveSetEnding: SetEnding? {
        guard allowsSetEndingOverride else { return nil }
        if let setEnding { return setEnding }
        if case .advantageSet = preset.format.set { return .advantageSet }
        return .tiebreak
    }

    public var effectiveLets: SessionMatchFormatLets { lets ?? preset.format.lets }

    public var format: SessionMatchFormat {
        let base = preset.format
        var result = base
        result.gameScoring = effectiveGameScoring
        result.lets = effectiveLets
        if let ending = effectiveSetEnding {
            switch (ending, base.set) {
            case (.advantageSet, .tiebreakSet(let rule)):
                result.set = .advantageSet(.init(games: rule.games))
                // A deciding match tie-break stays; a deciding set of games follows the other sets.
                if case .matchTiebreak = base.finalSet { result.finalSet = base.finalSet } else { result.finalSet = nil }
            case (.tiebreak, .advantageSet(let rule)):
                result.set = .tiebreakSet(.init(games: rule.games, tiebreakAt: rule.games, tiebreak: .init(points: 7)))
            default: break
            }
        }
        if result != base { result.presetId = .custom }
        return result
    }

    public var summary: FormatSummary {
        var summary = FormatSummary(format)
        if preset == .practiceSet { summary.length = .practiceSet }
        return summary
    }

    private enum CodingKeys: String, CodingKey { case preset, gameScoring, setEnding, lets }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = try container.decodeIfPresent(FormatPreset.self, forKey: .preset) ?? .clubBestOf3
        gameScoring = try container.decodeIfPresent(SessionMatchFormatGameScoring.self, forKey: .gameScoring)
        setEnding = try container.decodeIfPresent(SetEnding.self, forKey: .setEnding)
        lets = try container.decodeIfPresent(SessionMatchFormatLets.self, forKey: .lets)
    }
}

/// What a format's rules are, in the terms a label needs. It is derived from the rules alone, so the
/// match overview can label any stored format, not only one that came from a preset. The app turns it
/// into words; game scoring is only ever "Ad" or "No-Ad" and a set only ever ends with a tie-break or
/// as an advantage set (copy rule 2).
public struct FormatSummary: Equatable, Sendable {
    public enum Length: Equatable, Sendable {
        case bestOf(Int)
        case oneSet
        case proSet(games: Int)
        case shortSets(games: Int, bestOf: Int)
        case tiebreakOnly(points: Int)
        case practiceSet
    }

    public enum SetEnding: Equatable, Sendable {
        case tiebreak(at: Int)
        case advantageSet
    }

    /// How the last possible set differs from the others. `set` is its number (3 or 5).
    public enum Decider: Equatable, Sendable {
        case matchTiebreak(points: Int, set: Int)
        case longTiebreak(at: Int, points: Int, set: Int)
        case advantageSet(set: Int)
    }

    public var length: Length
    public var gameScoring: SessionMatchFormatGameScoring
    /// Nil for a standalone tie-break.
    public var setEnding: SetEnding?
    public var decider: Decider?
    public var lets: SessionMatchFormatLets

    public init(length: Length, gameScoring: SessionMatchFormatGameScoring, setEnding: SetEnding?, decider: Decider?,
                lets: SessionMatchFormatLets) {
        self.length = length; self.gameScoring = gameScoring; self.setEnding = setEnding; self.decider = decider; self.lets = lets
    }

    public init(_ format: SessionMatchFormat) {
        let sets = format.setsToWin.rawValue * 2 - 1
        gameScoring = format.gameScoring
        lets = format.lets
        decider = nil
        switch format.set {
        case .matchTiebreak(let rule):
            length = .tiebreakOnly(points: rule.tiebreak.points); setEnding = nil
            return
        case .advantageSet(let rule):
            length = Self.length(games: rule.games, sets: sets); setEnding = .advantageSet
        case .tiebreakSet(let rule):
            length = Self.length(games: rule.games, sets: sets); setEnding = .tiebreak(at: rule.tiebreakAt)
        }
        guard sets > 1, let final = format.finalSet, final != format.set else { return }
        switch final {
        case .matchTiebreak(let rule): decider = .matchTiebreak(points: rule.tiebreak.points, set: sets)
        case .tiebreakSet(let rule): decider = .longTiebreak(at: rule.tiebreakAt, points: rule.tiebreak.points, set: sets)
        case .advantageSet: decider = .advantageSet(set: sets)
        }
    }

    private static func length(games: Int, sets: Int) -> Length {
        if sets == 1 { return games == 6 ? .oneSet : .proSet(games: games) }
        return games < 6 ? .shortSets(games: games, bestOf: sets) : .bestOf(sets)
    }
}
