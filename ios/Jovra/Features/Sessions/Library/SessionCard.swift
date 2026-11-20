import AVFoundation
import JovraCore
import SwiftUI

/// One session in the library (S08 SessionCard, full variant): court thumbnail, title with its Sample badge,
/// the score for matches, "Oct 6 · 54 min · Singles", the four independent facet pills, "Only on this iPhone"
/// and the bytes it uses here. Tapping opens replay; the trailing control (and the VoiceOver action) deletes. At accessibility text
/// sizes the thumbnail moves above the text.
struct SessionCard: View {
    var entry: LibraryEntry
    var open: () -> Void
    var delete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var presentation: SessionCardPresentation { SessionCardPresentation(entry) }
    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Button(action: open) { summary }
                .buttonStyle(SessionCardButtonStyle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(presentation.accessibilityLabel)
                .accessibilityHint(Text("Opens replay", tableName: "Sessions.Library"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text("Delete", tableName: "Sessions.Library"), delete)
                .accessibilityIdentifier("library.session.\(entry.id)")
                .overlay(alignment: .bottomTrailing) { deleteButton }
            ArchiveActionSlot(entry: entry)
        }
        .jovraCard(padding: Space.x1 + Space.half)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Space.x2 - Space.half) {
            let layout = isStacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x2 - Space.half))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Space.x2 - Space.half))
            layout {
                SessionThumbnail(entry: entry)
                    .frame(width: isStacked ? nil : 132)
                    .frame(maxWidth: isStacked ? .infinity : nil)
                heading
                if !isStacked {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.jovra(.textSecondary))
                        .accessibilityHidden(true)
                }
            }
            FacetFlowLayout(spacing: Space.x1 - 2) {
                ForEach(presentation.facets.all, id: \.axis) { facet in
                    StatusPill(text: facet.text, tone: facet.tone, symbol: facet.symbol)
                }
            }
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Space.half) {
            Text(presentation.title)
                .font(.jovraHeadline)
                .foregroundStyle(.jovra(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
            if presentation.isSample { SampleBadge(size: .small) }
            if let scoreline = presentation.scoreline {
                Text(verbatim: scoreline)
                    .font(.jovraScore)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(presentation.metadata)
                .font(.jovraLabel)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.half) {
            if presentation.facets.isOnlyOnThisIPhone {
                Label(SessionFacetLabels.onlyOnThisIPhone, systemImage: "iphone")
                    .font(.jovraLabel)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let storage = presentation.storage {
                Label(storage, systemImage: "internaldrive")
                    .font(.jovraCaption)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // The Delete control sits over this row's trailing edge.
        .padding(.trailing, HitTarget.minimum + Space.half)
        .frame(minHeight: HitTarget.minimum, alignment: .leading)
    }

    /// Delete sits outside the card's button, over the footer's trailing edge, so it is never a tap on the card.
    private var deleteButton: some View {
        Button(action: delete) {
            Image(systemName: "trash")
                .font(.body.weight(.medium))
                .foregroundStyle(.jovra(.textSecondary))
                .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                .background(Color.jovra(.surfaceSunken), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Delete \(entry.title)…", tableName: "Sessions.Library"))
        .accessibilityIdentifier("library.delete.\(entry.id)")
    }
}

/// The card's pressed state: a gentle dim, no scale under Reduce Motion.
private struct SessionCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .animation(Motion.standard.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// The poster frame of the session's first recording segment, or a drawn court when there is no video on this
/// iPhone (sample, archived-only or missing). 16:10, control radius. Decorative: the card's label says it all.
struct SessionThumbnail: View {
    var entry: LibraryEntry
    @Environment(\.localCaptureLibrary) private var library
    @State private var poster: CGImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        ZStack {
            Color.jovra(.courtSurface)
            CourtLinesBackdrop()
                .stroke(Color.jovra(.courtLine).opacity(0.85), lineWidth: 1.5)
            if let poster {
                Image(decorative: poster, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: LibraryFilter.matches.includes(entry.kind) ? "figure.tennis" : "tennisball.fill")
                    .font(.title2)
                    .foregroundStyle(.jovra(.courtLine))
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(shape)
        // A hairline keeps the drawn court distinct from the forest card surface in dark mode.
        .overlay(shape.strokeBorder(Color.jovra(.separator), lineWidth: 1))
        .accessibilityHidden(true)
        .task(id: entry.posterPath) { await loadPoster() }
    }

    private func loadPoster() async {
        guard let path = entry.posterPath, case .ready(let library) = library,
              let url = try? await library.fileURL(SessionID(rawValue: entry.id), relativePath: path) else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 300)
        poster = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
    }
}

/// Lays pills out left to right and wraps to a new line when the next one does not fit.
struct FacetFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var sizes: [CGSize] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(for width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [], current = Row()
        for index in subviews.indices {
            // A pill wider than the row wraps its own text instead of overflowing.
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.indices.append(index)
            current.sizes.append(size)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
