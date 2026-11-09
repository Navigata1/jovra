import JovraCore
import SwiftUI

/// One marker on a court diagram: where it landed on the court model and what it means.
struct CourtPlacement: Identifiable, Hashable {
    let id: String
    var court: CourtPoint
    var kind: CourtMarkerKind
    /// Where across the court the hitter stood, for "cross-court" or "down the line".
    var hitterX: Double?
    /// Read before the placement words, e.g. "Point 37".
    var context: String?
    /// Doubles: the alleys are in.
    var doubles = false

    /// "Point 37, Deep cross-court, in"; a clamped outlier adds "outside the court area" (S11).
    func spoken(clamped: Bool) -> String {
        var parts: [String] = []
        if let context { parts.append(context) }
        switch kind {
        case .in, .out, .needsReview:
            let result: PlacementResult = kind == .in ? .in : (kind == .out ? .out : .needsReview)
            parts.append(PlacementWords(landing: court, hitterX: hitterX, result: result, doubles: doubles).spoken)
        case .bookmark, .unscored:
            parts.append(kind.title)
        }
        if clamped {
            parts.append(String(localized: "outside the court area", table: "DesignSystem.Court",
                                comment: "Read after a marker that landed beyond the drawn court and is pinned to its edge"))
        }
        return parts.joined(separator: ", ")
    }
}

/// A top-down ITF court drawn from `CourtGeometry` through `CourtDiagramLayout` (full, half or service box), with
/// depth bands or serve zones and shape-first markers. The court keeps its proportions and scales with width only.
/// VoiceOver reads the diagram as one summarized container, each marker as its own element in words
/// ("Deep cross-court, in"), and offers a "Shots" rotor that walks the markers in order.
struct CourtDiagram: View {
    var variant: CourtDiagramLayout.Variant = .full
    var placements: [CourtPlacement] = []
    /// The diagram's accessibility label: what the map shows ("Forehand placements, 50 placed: …").
    var summary: String
    var markerSize: CGFloat = 14
    var showsBandLabels = true

    @Namespace private var rotorSpace
    @Environment(\.dynamicTypeSize) private var typeSize

    private var aspect: CGFloat {
        let probe = CourtDiagramLayout(variant: variant, width: 100)
        return CGFloat(probe.size.width / probe.size.height)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = CourtDiagramLayout(variant: variant, width: Double(proxy.size.width))
            ZStack(alignment: .topLeading) {
                CourtSurface(layout: layout, showsLabels: showsBandLabels)
                if showsBandLabels {
                    ForEach(layout.zones, id: \.zone) { zone in
                        zoneLabel(zone)
                    }
                }
                ForEach(placements) { placement in
                    marker(placement, layout: layout)
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(summary))
        .accessibilityRotor(Text("Shots", tableName: "DesignSystem.Court",
                                 comment: "VoiceOver rotor that walks the markers on a court diagram")) {
            ForEach(placements) { placement in
                AccessibilityRotorEntry(Text(placement.spoken(clamped: false)), id: placement.id, in: rotorSpace)
            }
        }
    }

    /// "Wide", "Body" and "T" as real text, so VoiceOver reads the zones and the words follow Dynamic Type. They
    /// sit at the net end of the box: serves land towards the service line, so markers never cover the words. At
    /// accessibility sizes a word is wider than a third of the box, so it reads up the zone from the net instead,
    /// like the depth labels along the run-off.
    @ViewBuilder private func zoneLabel(_ zone: CourtDiagramLayout.Zone) -> some View {
        let midX = zone.origin.x + zone.size.width / 2, netY = zone.origin.y + zone.size.height
        let word = Text(zone.zone.title)
            .font(.jovraCaption.weight(.semibold))
            .foregroundStyle(.jovra(.textSecondaryOnEditorial))
            .lineLimit(1)
            .fixedSize()
            .accessibilityIdentifier("court.zone.\(zone.zone.rawValue)")
        if typeSize.isAccessibilitySize {
            word.frame(width: zone.size.height / 2, alignment: .leading)
                .rotationEffect(.degrees(-90))
                .position(x: midX, y: netY - Self.zoneLabelInset / 2 - zone.size.height / 4)
        } else {
            word.position(x: midX, y: netY - Self.zoneLabelInset)
        }
    }

    /// From the net up to the middle of a zone word.
    static let zoneLabelInset: CGFloat = 22

    private func marker(_ placement: CourtPlacement, layout: CourtDiagramLayout) -> some View {
        let placed = layout.place(placement.court)
        return ZStack {
            CourtMarker(kind: placement.kind, size: markerSize)
            if placed.clamped {
                Image(systemName: "arrow.up.right")
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.bold)
                    .frame(width: markerSize * 0.55, height: markerSize * 0.55)
                    .foregroundStyle(.jovra(.courtLine))
                    .offset(x: markerSize * 0.75, y: -markerSize * 0.75)
            }
        }
        .frame(width: max(markerSize, 24), height: max(markerSize, 24))
        .contentShape(Rectangle())
        .position(x: placed.point.x, y: placed.point.y)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(placement.spoken(clamped: placed.clamped)))
        .accessibilityRotorEntry(id: placement.id, in: rotorSpace)
        .accessibilityIdentifier("court.marker.\(placement.id)")
    }

}

/// The drawn court: forest surface, depth-band tint, ivory lines, a meshed net with posts. Decorative.
struct CourtSurface: View {
    var layout: CourtDiagramLayout
    /// Band labels ("Deep", "Short"), drawn in the canvas along the run-off: they scale with the court's width
    /// like the lines, and VoiceOver reads the diagram's summary and markers instead. Zone words are real text
    /// laid over the surface by `CourtDiagram`.
    var showsLabels = true

    var body: some View {
        Canvas { context, size in
            let line = GraphicsContext.Shading.color(.jovra(.courtLine))
            let unit = max(1.5, layout.scale * 0.07)   // lines read at every width; ITF lines are 5-10 cm wide
            // Deep band: a whisper of ivory so the two depths read apart without a legend.
            for band in layout.bands where band.bin == .deep {
                context.fill(Path(CGRect(x: band.origin.x, y: band.origin.y, width: band.size.width, height: band.size.height)),
                             with: .color(.jovra(.courtLine).opacity(0.06)))
            }
            for zone in layout.zones where zone.zone == .body {
                context.fill(Path(CGRect(x: zone.origin.x, y: zone.origin.y, width: zone.size.width, height: zone.size.height)),
                             with: .color(.jovra(.courtLine).opacity(0.05)))
            }
            for segment in layout.segments where segment.kind != .net {
                var path = Path()
                path.move(to: CGPoint(x: segment.from.x, y: segment.from.y))
                path.addLine(to: CGPoint(x: segment.to.x, y: segment.to.y))
                context.stroke(path, with: line, style: StrokeStyle(lineWidth: segment.kind == .baseline ? unit * 1.4 : unit, lineCap: .square))
            }
            // Zone dividers in a service box: thin, lighter than court lines.
            for zone in layout.zones.dropFirst() {
                var path = Path()
                let x = layout.minX < 0 ? zone.origin.x + zone.size.width : zone.origin.x
                path.move(to: CGPoint(x: x, y: zone.origin.y))
                path.addLine(to: CGPoint(x: x, y: zone.origin.y + zone.size.height))
                context.stroke(path, with: .color(.jovra(.courtLine).opacity(0.45)), style: StrokeStyle(lineWidth: max(1, unit * 0.5), dash: [3, 3]))
            }
            if let net = layout.segments.first(where: { $0.kind == .net }) {
                drawNet(net, in: &context, unit: unit)
            }
            if showsLabels { drawLabels(in: &context) }
            _ = size
        }
        .background(Color.jovra(.courtSurface))
        .accessibilityHidden(true)
    }

    private func drawLabels(in context: inout GraphicsContext) {
        let ink = Color.jovra(.textSecondaryOnEditorial)
        let size = max(9, min(13, layout.scale * 0.42))
        let runOff = layout.point(CourtPoint(x: -CourtGeometry.doublesHalfWidth, y: 0)).x
        for band in layout.bands {
            let text = context.resolve(Text(band.bin.title.uppercased()).font(.system(size: size, weight: .semibold)).tracking(1.2).foregroundStyle(ink))
            var rotated = context
            rotated.translateBy(x: runOff / 2, y: band.origin.y + band.size.height / 2)
            rotated.rotate(by: .degrees(-90))
            rotated.draw(text, at: .zero, anchor: .center)
        }
    }

    private func drawNet(_ net: CourtDiagramLayout.Segment, in context: inout GraphicsContext, unit: CGFloat) {
        let height = max(6, unit * 4)
        let band = CGRect(x: net.from.x, y: net.from.y - height / 2, width: net.to.x - net.from.x, height: height)
        context.fill(Path(band), with: .color(.jovra(.courtSurface)))
        var mesh = Path()
        var x = band.minX
        while x <= band.maxX {
            mesh.move(to: CGPoint(x: x, y: band.minY))
            mesh.addLine(to: CGPoint(x: x, y: band.maxY))
            x += 3
        }
        mesh.move(to: CGPoint(x: band.minX, y: band.midY))
        mesh.addLine(to: CGPoint(x: band.maxX, y: band.midY))
        context.stroke(mesh, with: .color(.jovra(.courtLine).opacity(0.35)), lineWidth: 0.6)
        var tape = Path()
        tape.move(to: CGPoint(x: band.minX, y: band.minY))
        tape.addLine(to: CGPoint(x: band.maxX, y: band.minY))
        context.stroke(tape, with: .color(.jovra(.courtLine)), lineWidth: max(1, unit * 0.8))
        for postX in [band.minX, band.maxX] {
            context.fill(Path(ellipseIn: CGRect(x: postX - unit, y: band.midY - unit, width: unit * 2, height: unit * 2)),
                         with: .color(.jovra(.courtLine)))
        }
    }
}

extension CourtGeometry.DepthBin {
    var title: String {
        switch self {
        case .short: String(localized: "Short", table: "DesignSystem.Court", comment: "Placement depth: inside the service line")
        case .deep: String(localized: "Deep", table: "DesignSystem.Court", comment: "Placement depth: between the service line and the baseline")
        case .long: String(localized: "Long", table: "DesignSystem.Court", comment: "Placement depth: beyond the baseline")
        }
    }
}

extension CourtGeometry.ServiceZone {
    var title: String {
        switch self {
        case .t: String(localized: "T", table: "DesignSystem.Court", comment: "Serve zone next to the centre service line")
        case .body: String(localized: "Body", table: "DesignSystem.Court", comment: "Serve zone: the middle third of the service box")
        case .wide: String(localized: "Wide", table: "DesignSystem.Court", comment: "Serve zone next to the sideline")
        }
    }
}
