import JovraRoom
import SwiftUI

/// Score in the shell (reference 62): the point score and games folded on the phone, labelled Manual. No buttons:
/// point and undo commands, receipts and conflicts are W05 and W16. Never an optimistic score or a winner.
struct ScoreShellPage: View {
    let model: WatchAppModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        WatchPage(surface: .score, isSample: model.isSample) {
            if let score = model.snapshot?.score, score.players.count == 2 {
                let (first, second) = (score.players[0], score.players[1])
                VStack(spacing: 2) {
                    HStack(spacing: 8) {
                        Text(verbatim: playerName(first))
                        Circle().fill(WatchPalette.ivorySecondary).frame(width: 4, height: 4)
                        Text(verbatim: playerName(second))
                    }
                    .font(.watchTitle)
                    .foregroundStyle(WatchPalette.ivory)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    WatchHeroNumber(value: "\(first.point.rawValue)–\(second.point.rawValue)", color: WatchPalette.ivory)
                    Text("Games \(first.games)–\(second.games)", tableName: "Watch")
                        .font(.watchValue)
                        .foregroundStyle(WatchPalette.secondaryText(contrast))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(
                    "\(playerName(first)) \(first.point.rawValue), \(playerName(second)) \(second.point.rawValue). Games \(first.games) \(second.games).",
                    tableName: "Watch"))
                .accessibilityIdentifier("watch.score.value")
                ProvenanceChip(symbol: "hand.point.up.left", text: Text("Manual score", tableName: "Watch"))
            } else {
                WatchStatePanel(symbol: "sportscourt",
                                title: Text("No score yet", tableName: "Watch"),
                                message: Text("The score appears when your phone scores a point.",
                                              tableName: "Watch"))
            }
        }
    }

    /// The phone sends player ids; display names arrive with the phone's view model (W05). Clipped to one line.
    private func playerName(_ player: ScoreSummary.Player) -> String {
        WatchCopy.clip(player.playerId.localizedCapitalized, limit: 9)
    }
}

/// Latest serve in the shell (reference 63): the last post-capture estimate, labelled Estimated, only when the phone
/// sends one with the capability on; otherwise "Not measured live". Never live, never Validated, never a wrist claim.
struct ServeShellPage: View {
    let model: WatchAppModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        WatchPage(surface: .serve, isSample: model.isSample) {
            Text("Latest serve", tableName: "Watch")
                .font(.watchTitle)
                .foregroundStyle(WatchPalette.ivory)
                .accessibilityAddTraits(.isHeader)
            if let estimate {
                estimateView(estimate)
            } else {
                WatchStatePanel(symbol: "gauge.with.dots.needle.0percent",
                                title: Text("Not measured live", tableName: "Watch"),
                                message: Text("Serve speed estimates are made on the phone after you mark contact and bounce.",
                                              tableName: "Watch"))
                    .accessibilityIdentifier("watch.serve.notMeasured")
            }
        }
    }

    /// A post-capture estimate the watch may show: capability on, a value with units, labelled estimated.
    private var estimate: AnalysisResult? {
        guard let snapshot = model.snapshot, snapshot.capabilities.serveSpeedResults == true,
              let result = snapshot.latestServe, result.kind == .serveSpeed, result.label == .estimated,
              result.value != nil, result.units != nil else { return nil }
        return result
    }

    private func estimateView(_ result: AnalysisResult) -> some View {
        let value = result.value ?? ""
        let units = result.units?.rawValue ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                WatchHeroNumber(value: value, color: WatchPalette.ivory)
                Text(verbatim: units).font(.watchTitle).foregroundStyle(WatchPalette.ivory)
            }
            ProvenanceChip(symbol: "function", text: Text("Estimated", tableName: "Watch"))
            if let range = result.uncertainty {
                Text("Range \(range.lower)–\(range.upper) \(units)", tableName: "Watch")
                    .font(.watchCaption)
                    .foregroundStyle(WatchPalette.secondaryText(contrast))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Estimated average serve speed, \(value) \(units).", tableName: "Watch"))
        .accessibilityIdentifier("watch.serve.estimate")
    }
}

/// Mark for review in the shell (reference 64): marks are reviewed on the phone; the last accepted mark receipt
/// is shown as a word and a shape. The mark command itself is W06. Never an In/Out call, never a score change.
struct MarkShellPage: View {
    let model: WatchAppModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        WatchPage(surface: .mark, isSample: model.isSample) {
            Text("Mark for review", tableName: "Watch")
                .font(.watchTitle)
                .foregroundStyle(WatchPalette.ivory)
                .accessibilityAddTraits(.isHeader)
            Text("Marks go to your phone, where you review the video.", tableName: "Watch")
                .font(.watchCaption)
                .foregroundStyle(WatchPalette.secondaryText(contrast))
                .fixedSize(horizontal: false, vertical: true)
            if lastAcceptedMark != nil {
                WatchCard {
                    Label {
                        Text("Marked for review", tableName: "Watch")
                            .font(.watchBody.weight(.semibold))
                            .foregroundStyle(WatchPalette.ivory)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(WatchPalette.chartreuse)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityIdentifier("watch.mark.receipt")
            }
        }
    }

    private var lastAcceptedMark: RoomReceipt? {
        model.snapshot?.receipts.last { $0.type == .markForReview && $0.status == .accepted }
    }
}

/// A provenance label as a chip: a symbol plus the word (never colour alone).
struct ProvenanceChip: View {
    let symbol: String
    let text: Text

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).accessibilityHidden(true)
            text
        }
        .font(.watchCaption.weight(.medium))
        .foregroundStyle(WatchPalette.ivory)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(WatchPalette.panel))
        .frame(maxWidth: .infinity)
    }
}
