import JovraBenchmark
import SwiftUI

/// Progress, the selected label and the key legend. The legend reads the same keymap the keys do.
struct Sidebar: View {
    @Environment(\.colorScheme) private var scheme
    let session: LabelSession

    var body: some View {
        let palette = Palette(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let document = session.document {
                    progress(document, palette)
                    selected(document, palette)
                }
                legend(palette)
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Metrics.sidebarWidth)
        .background(palette.panel)
        .overlay(alignment: .leading) { Rectangle().fill(palette.line).frame(width: 1) }
    }

    private func heading(_ text: String, _ palette: Palette) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(palette.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func progress(_ document: LabelDocument, _ palette: Palette) -> some View {
        let counts = document.labels.counts
        let candidates = document.candidateCounts()
        VStack(alignment: .leading, spacing: 10) {
            heading("Labelled", palette)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                count("Hits", counts.hits, id: "count-hits", palette)
                count("With a stroke type", counts.strokes, id: "count-strokes", palette)
                count("Bounces", counts.bounces, id: "count-bounces", palette)
                count("Rallies", counts.rallies, id: "count-rallies", palette)
                count("Court corners", document.labels.cameraPositions.reduce(0) { $0 + $1.corners.points.compactMap { $0 }.count }, id: "count-corners", palette)
            }
            if let open = document.openRallyStart {
                Label("Rally open since \(open.clock)", systemImage: "arrow.right.to.line")
                    .font(.callout)
                    .foregroundStyle(palette.warning)
                    .accessibilityIdentifier("open-rally")
            }
            Text(candidateLine(candidates))
                .font(.callout)
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("candidate-status")
        }
    }

    private func count(_ title: String, _ value: Int, id: String, _ palette: Palette) -> some View {
        GridRow {
            Text(title).foregroundStyle(palette.text)
            Text("\(value)")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(palette.text)
                .gridColumnAlignment(.trailing)
                .accessibilityIdentifier(id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
    }

    private func candidateLine(_ counts: (pending: Int, confirmed: Int, rejected: Int)) -> String {
        switch session.candidateSearch {
        case .idle: "Hit candidates: none yet."
        case .searching: "Listening for hit candidates in the sound…"
        case .noAudio: "No sound in this recording, so no hit candidates."
        case .failed(let reason): "Hit candidates unavailable: \(reason)"
        case .found: "Hit candidates: \(counts.pending) to review, \(counts.confirmed) confirmed, \(counts.rejected) rejected."
        }
    }

    @ViewBuilder private func selected(_ document: LabelDocument, _ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Selected", palette)
            Text(selectionText(document))
                .font(.callout)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("selection")
        }
    }

    private func selectionText(_ document: LabelDocument) -> String {
        switch session.selection {
        case .hit(let time, let player):
            let stroke = document.labels.hits.first { $0.time == time && $0.player == player }?.stroke
            return "Hit by the \(player.rawValue) player at \(time.clock). Stroke type: \(stroke?.rawValue ?? "not set")."
        case .bounce(let time):
            let inPlay = document.labels.bounces.first { $0.time == time }?.inPlay ?? true
            return "Bounce at \(time.clock), \(inPlay ? "in play" : "dead ball")."
        case .rally(let start):
            let end = document.labels.rallies.first { $0.start == start }?.end
            return "Rally from \(start.clock) to \(end?.clock ?? "…")."
        case .cameraPosition(let from):
            return "Camera position from \(from.clock). Next corner: \(LabelSession.cornerName(document.nextCorner))."
        case nil:
            return "Nothing selected. Marking a label selects it; , and . move between labels."
        }
    }

    private func legend(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Keys", palette)
            ForEach(LabelKeymap.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title).font(.callout.weight(.semibold)).foregroundStyle(palette.text)
                    ForEach(section.bindings, id: \.self) { binding in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            KeyCap(text: binding.stroke.display)
                            Text(binding.title).font(.callout).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(binding.title): \(binding.stroke.spoken)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keys")
        .accessibilityIdentifier("key-legend")
    }
}
