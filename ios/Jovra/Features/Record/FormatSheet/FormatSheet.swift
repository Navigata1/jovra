import JovraCore
import SwiftUI

/// The match format sheet (S04, reused by the match overview S09). The preset list and the overrides
/// are `FormatChooser`, a view over a `FormatChoice` binding, so the overview can present the same
/// choices for a saved session.
struct FormatSheet: View {
    nonisolated static let isPlaceholder = false
    var context: FormatSheetContext
    @Environment(\.sessionSetupStore) private var store

    var body: some View {
        @Bindable var store = store
        SetupSheet(route: .matchFormat(context),
                   subtitle: String(localized: "The scoreboard follows the format you are actually playing.", table: "Record", comment: "Format sheet subtitle")) {
            switch context {
            case .sessionSetup:
                FormatChooser(choice: $store.setup.format, decidingSide: $store.setup.noAdDecidingSide)
            case .session:
                SavedSessionFormatNote()
            }
        }
    }
}

/// Presets with one-line descriptions, then the overrides: games Ad / No-Ad, how a set ends, lets, and
/// for No-Ad games the side the receiver takes for the deciding point (stories 41–43, 45).
struct FormatChooser: View {
    @Binding var choice: FormatChoice
    @Binding var decidingSide: SessionSetup.DecidingSide

    var body: some View {
        SetupSection(title: String(localized: "Presets", table: "Record", comment: "Format sheet section")) {
            ForEach(FormatPreset.offered + [.practiceSet], id: \.self) { preset in
                let available = preset.availability == .offered
                ChoiceRow(title: FormatLabel.presetTitle(preset),
                          detail: available ? FormatLabel.summary(FormatChoice(preset: preset).summary) : FormatLabel.unavailable(preset.availability),
                          isSelected: choice.preset == preset, isEnabled: available,
                          identifier: "format.preset.\(preset.rawValue)") {
                    choice = FormatChoice(preset: preset)
                }
            }
        }
        SetupSection(title: String(localized: "Rules", table: "Record", comment: "Format sheet section"),
                     footnote: rulesFootnote) {
            if choice.allowsGameScoringOverride {
                SegmentField(String(localized: "Games", table: "Record", comment: "Game scoring field"),
                             values: SessionMatchFormatGameScoring.allCases, selection: gameScoring,
                             identifier: "format.games", title: FormatLabel.gameScoring)
                SegmentField(String(localized: "Sets", table: "Record", comment: "Set ending field"),
                             values: FormatChoice.SetEnding.allCases, selection: setEnding,
                             identifier: "format.sets", title: setEndingTitle)
            }
            SegmentField(String(localized: "Lets", table: "Record", comment: "Lets field"),
                         values: SessionMatchFormatLets.allCases, selection: lets, identifier: "format.lets") { value in
                value == .let ? String(localized: "Play lets", table: "Record", comment: "Lets on")
                              : String(localized: "No lets", table: "Record", comment: "Lets off")
            }
            if choice.allowsGameScoringOverride, choice.effectiveGameScoring == .noAd {
                SegmentField(String(localized: "Deciding point at deuce", table: "Record", comment: "No-Ad deciding side field"),
                             values: SessionSetup.DecidingSide.allCases, selection: $decidingSide,
                             identifier: "format.decidingSide", title: FormatLabel.decidingSide)
            }
        }
        VStack(alignment: .leading, spacing: Space.half) {
            Text("Scoring", tableName: "Record", comment: "Format summary label")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.jovra(.textSecondary))
            Text(FormatLabel.summary(choice.summary))
                .font(.body.weight(.semibold))
                .foregroundStyle(.jovra(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("format.summary")
    }

    private var rulesFootnote: String {
        choice.allowsGameScoringOverride
            ? String(localized: "Changing a rule makes this a custom format.", table: "Record", comment: "Format rules footnote")
            : String(localized: "A tie-break has no games, so Ad and set endings do not apply.", table: "Record", comment: "Format rules footnote, tie-break only")
    }

    private func setEndingTitle(_ ending: FormatChoice.SetEnding) -> String {
        switch ending {
        case .tiebreak:
            if case .tiebreak(let games) = choice.summary.setEnding { return FormatLabel.setEnding(.tiebreak(at: games)) }
            if case .advantageSet(let rule) = choice.preset.format.set { return FormatLabel.setEnding(.tiebreak(at: rule.games)) }
            if case .tiebreakSet(let rule) = choice.preset.format.set { return FormatLabel.setEnding(.tiebreak(at: rule.tiebreakAt)) }
            return FormatLabel.setEnding(.tiebreak(at: 6))
        case .advantageSet: return FormatLabel.setEnding(.advantageSet)
        }
    }

    private var gameScoring: Binding<SessionMatchFormatGameScoring> {
        Binding(get: { choice.effectiveGameScoring }, set: { choice.gameScoring = $0 })
    }

    private var setEnding: Binding<FormatChoice.SetEnding> {
        Binding(get: { choice.effectiveSetEnding ?? .tiebreak }, set: { choice.setEnding = $0 })
    }

    private var lets: Binding<SessionMatchFormatLets> {
        Binding(get: { choice.effectiveLets }, set: { choice.lets = $0 })
    }
}

/// A saved session's format is changed from its match overview (T22), where every score and stat is
/// recomputed; until then this sheet says so rather than offering a change it cannot apply.
private struct SavedSessionFormatNote: View {
    var body: some View {
        InfoCard(symbol: "trophy",
                 title: String(localized: "Edit from the match overview", table: "Record", comment: "Format sheet for a saved session"),
                 message: String(localized: "Changing a saved match's format recomputes every score and stat, so it is done from the match overview.", table: "Record", comment: "Format sheet for a saved session"))
    }
}
