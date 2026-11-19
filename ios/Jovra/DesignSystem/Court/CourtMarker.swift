import JovraCore
import SwiftUI

/// What a court marker says (screens.md §5.2): shape first, colour second, so meaning never rests on colour alone
/// (CLAUDE.md rule 8). In = filled circle, Out = triangle, Needs review = ring, Bookmark = diamond, Unscored =
/// square outline.
enum CourtMarkerKind: String, CaseIterable, Identifiable, Sendable {
    case `in`, out, needsReview, bookmark, unscored

    var id: Self { self }

    init(_ result: PlacementResult) {
        switch result {
        case .in: self = .in
        case .out: self = .out
        case .needsReview: self = .needsReview
        }
    }

    /// The legend word (and the marker's spoken result when it is not a placement).
    var title: String {
        switch self {
        case .in: String(localized: "In", table: "DesignSystem.Court", comment: "Court marker legend: a filled circle")
        case .out: String(localized: "Out", table: "DesignSystem.Court", comment: "Court marker legend: a triangle")
        case .needsReview: String(localized: "Needs review", table: "DesignSystem.Court", comment: "Court marker legend: a ring")
        case .bookmark: String(localized: "Bookmark", table: "DesignSystem.Court", comment: "Court marker legend: a diamond")
        case .unscored: String(localized: "Unscored", table: "DesignSystem.Court", comment: "Court marker legend: a square outline")
        }
    }
}

/// One marker glyph, drawn from colour roles: In is a chartreuse disc with a forest outline, Out a clay triangle,
/// Needs review a chartreuse disc inside a clay ring, Bookmark an ivory diamond, Unscored an ivory square outline.
/// Decorative on its own: the diagram or legend that shows it carries the words.
struct CourtMarker: View {
    var kind: CourtMarkerKind
    /// The marker's width; every shape keeps the same visual weight at this size.
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            switch kind {
            case .in:
                Circle().fill(Color.jovra(.markerIn))
                Circle().strokeBorder(Color.jovra(.markerInOutline), lineWidth: max(1, size / 9))
            case .out:
                TriangleShape().fill(Color.jovra(.markerOut))
                TriangleShape().stroke(Color.jovra(.markerInOutline), lineWidth: max(1, size / 12))
            case .needsReview:
                Circle().strokeBorder(Color.jovra(.markerOut), lineWidth: max(1.5, size / 7))
                Circle().fill(Color.jovra(.markerIn)).padding(size * 0.27)
            case .bookmark:
                DiamondShape().fill(Color.jovra(.courtLine))
                DiamondShape().stroke(Color.jovra(.markerInOutline), lineWidth: max(1, size / 12))
            case .unscored:
                Rectangle().strokeBorder(Color.jovra(.courtLine), lineWidth: max(1.5, size / 7)).padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.04))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.06))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.06))
        p.closeSubpath()
        return p
    }
}

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

/// The legend under a court: each shape with its word ("● In", "▲ Out", "◎ Needs review"), so colour is never the
/// only signal. Wraps onto more lines at large text sizes instead of truncating.
struct CourtMarkerLegend: View {
    var kinds: [CourtMarkerKind] = [.in, .out, .needsReview]
    /// Legend text sits on the forest court card by default.
    var onCourtCard = true
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The shapes grow with the words beside them, so a legend read at an accessibility size keeps its glyphs legible.
    @ScaledMetric(relativeTo: .subheadline) private var glyph: CGFloat = 16

    var body: some View {
        // One row as in the reference; stacked once the words no longer fit beside each other.
        let layout = typeSize >= .xxLarge || kinds.count > 3
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x1))
            : AnyLayout(HStackLayout(spacing: Space.x3))
        layout { items }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(format: String(localized: "Legend: %@", table: "DesignSystem.Court",
                                                       comment: "VoiceOver summary of a court marker legend; %@ lists the shapes and words"),
                                        kinds.map(\.spokenLegend).formatted(.list(type: .and)))))
        .accessibilityIdentifier("court.legend")
    }

    @ViewBuilder private var items: some View {
        ForEach(kinds) { kind in
            HStack(spacing: Space.x1) {
                CourtMarker(kind: kind, size: glyph)
                Text(kind.title)
                    .font(.jovraLabel)
                    .foregroundStyle(.jovra(onCourtCard ? .textOnEditorial : .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension CourtMarkerKind {
    /// "filled circle, In": the legend read aloud names the shape too.
    var spokenLegend: String {
        let shape = switch self {
        case .in: String(localized: "filled circle", table: "DesignSystem.Court", comment: "Shape of the In marker, read in the legend")
        case .out: String(localized: "triangle", table: "DesignSystem.Court", comment: "Shape of the Out marker, read in the legend")
        case .needsReview: String(localized: "ring", table: "DesignSystem.Court", comment: "Shape of the Needs review marker, read in the legend")
        case .bookmark: String(localized: "diamond", table: "DesignSystem.Court", comment: "Shape of the Bookmark marker, read in the legend")
        case .unscored: String(localized: "square outline", table: "DesignSystem.Court", comment: "Shape of the Unscored marker, read in the legend")
        }
        return String(format: String(localized: "%1$@, %2$@", table: "DesignSystem.Court",
                                     comment: "A legend entry read aloud: the marker's shape, then its meaning"), shape, title)
    }
}
