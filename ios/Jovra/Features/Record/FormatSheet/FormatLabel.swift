import Foundation
import JovraCore

/// Words for a match format, generated from its rules (`FormatSummary`), so the setup row, the format
/// sheet and the match overview label any stored format the same way. Game scoring is only ever "Ad" or
/// "No-Ad"; a set only ever ends "Tie-break at 6–6" or as an "Advantage set" (screen spec §0.2 rule 2):
/// the bare word "Advantage" never appears.
enum FormatLabel {
    static let separator = " · "

    /// "Best of 3 · Ad · Tie-break at 6–6".
    static func summary(_ summary: FormatSummary) -> String {
        parts(summary).joined(separator: separator)
    }

    static func parts(_ summary: FormatSummary) -> [String] {
        var parts = [length(summary.length)]
        if summary.length == .practiceSet {
            parts.append(String(localized: "No match end", table: "Record", comment: "Practice set: the set has no end"))
            return parts
        }
        guard let ending = summary.setEnding else { return parts } // A standalone tie-break has no games.
        parts.append(gameScoring(summary.gameScoring))
        if summary.decider == nil || ending == .advantageSet { parts.append(setEnding(ending)) }
        if let decider = summary.decider { parts.append(self.decider(decider)) }
        if summary.lets == .noLet { parts.append(String(localized: "No lets", table: "Record", comment: "Format: lets are not played")) }
        return parts
    }

    static func length(_ length: FormatSummary.Length) -> String {
        switch length {
        case .bestOf(let sets): String(localized: "Best of \(sets)", table: "Record", comment: "Format length, e.g. Best of 3")
        case .oneSet: String(localized: "One set", table: "Record", comment: "Format length")
        case .proSet(let games): String(localized: "Pro set to \(games)", table: "Record", comment: "Format length")
        case .shortSets(let games, _): String(localized: "Short sets to \(games)", table: "Record", comment: "Format length")
        case .tiebreakOnly(let points): String(localized: "Tie-break only to \(points)", table: "Record", comment: "Format length")
        case .practiceSet: String(localized: "Practice set", table: "Record", comment: "Format length")
        }
    }

    static func gameScoring(_ scoring: SessionMatchFormatGameScoring) -> String {
        switch scoring {
        case .ad: String(localized: "Ad", table: "Record", comment: "Game scoring: advantage games")
        case .noAd: String(localized: "No-Ad", table: "Record", comment: "Game scoring: deciding point at deuce")
        }
    }

    static func setEnding(_ ending: FormatSummary.SetEnding) -> String {
        switch ending {
        case .tiebreak(let games): String(localized: "Tie-break at \(games)–\(games)", table: "Record", comment: "How a set ends")
        case .advantageSet: String(localized: "Advantage set", table: "Record", comment: "How a set ends: win by two games")
        }
    }

    static func decider(_ decider: FormatSummary.Decider) -> String {
        switch decider {
        case .matchTiebreak(let points, let set):
            set == 5
                ? String(localized: "\(points)-point match tie-break for the fifth set", table: "Record", comment: "Deciding set")
                : String(localized: "\(points)-point match tie-break for the third set", table: "Record", comment: "Deciding set")
        case .longTiebreak(let games, let points, let set):
            set == 5
                ? String(localized: "\(points)-point tie-break at \(games)–\(games) in the fifth", table: "Record", comment: "Deciding set")
                : String(localized: "\(points)-point tie-break at \(games)–\(games) in the third", table: "Record", comment: "Deciding set")
        case .advantageSet(let set):
            set == 5
                ? String(localized: "Advantage set in the fifth", table: "Record", comment: "Deciding set")
                : String(localized: "Advantage set in the third", table: "Record", comment: "Deciding set")
        }
    }

    /// The preset's own name in the format sheet.
    static func presetTitle(_ preset: FormatPreset) -> String {
        switch preset {
        case .clubBestOf3: String(localized: "Club match", table: "Record", comment: "Format preset")
        case .matchTiebreakThird: String(localized: "Match tie-break in lieu of a third set", table: "Record", comment: "Format preset")
        case .noAdMatchTiebreak: String(localized: "No-Ad with a match tie-break", table: "Record", comment: "Format preset")
        case .bestOf5: String(localized: "Best of 5", table: "Record", comment: "Format preset")
        case .proSet8: String(localized: "Pro set", table: "Record", comment: "Format preset")
        case .shortSets: String(localized: "Short sets", table: "Record", comment: "Format preset")
        case .tiebreak7: String(localized: "Tie-break to 7", table: "Record", comment: "Format preset")
        case .tiebreak10: String(localized: "Tie-break to 10", table: "Record", comment: "Format preset")
        case .oneSet: String(localized: "One set", table: "Record", comment: "Format preset")
        case .fast4: String(localized: "Fast4", table: "Record", comment: "Format preset")
        case .practiceSet: String(localized: "Practice set", table: "Record", comment: "Format preset")
        }
    }

    /// Why a preset that is listed cannot be chosen yet.
    static func unavailable(_ availability: FormatPreset.Availability) -> String? {
        switch availability {
        case .offered: nil
        case .rulesUnconfirmed: String(localized: "Not available yet: its rules are still being confirmed.", table: "Record", comment: "Format preset unavailable")
        case .scoringNotBuilt:
            String(localized: "Not available yet: scoring for a set without a match end is still being built.", table: "Record", comment: "Format preset unavailable")
        }
    }

    static func decidingSide(_ side: SessionSetup.DecidingSide) -> String {
        switch side {
        case .receiverChooses: String(localized: "Receiver chooses", table: "Record", comment: "No-Ad deciding point side")
        case .deuce: String(localized: "Deuce court", table: "Record", comment: "No-Ad deciding point side")
        case .ad: String(localized: "Ad court", table: "Record", comment: "No-Ad deciding point side")
        }
    }
}
