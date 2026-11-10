// l10n-lint: ignore-file (DEBUG-only court component gallery for UI tests and screenshots; absent from release builds)
#if DEBUG
import JovraCore
import SwiftUI

/// An opt-in gallery of the court components (T13); absent from release builds.
/// `JOVRA_COURT_GALLERY=<scenario>` replaces the app's root with one scenario. Every value is sample data and the
/// page says so with a Sample badge (CLAUDE.md rule 1).
struct CourtGalleryHarness: ViewModifier {
    func body(content: Content) -> some View {
        if let raw = ProcessInfo.processInfo.environment["JOVRA_COURT_GALLERY"], let scenario = CourtGallery.Scenario(rawValue: raw) {
            CourtGallery(scenario: scenario)
        } else {
            content
        }
    }
}

struct CourtGallery: View {
    enum Scenario: String, CaseIterable {
        case diagrams, markers, guide
        case guidePoor = "guide-poor"
        case guideLoupe = "guide-loupe"
        /// The far right bracket dragged to the middle of the court: a quad no camera can produce.
        case guideTwisted = "guide-twisted"
    }

    /// Tall enough to read a to-scale court (2.17 times longer than wide) and short enough to keep it on one screen.
    static let fullCourtHeight: CGFloat = 440

    var scenario: Scenario
    @State private var corners: [VideoPixel] = SyntheticCourtCamera.trueCorners
    @State private var deuce = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                ReadableColumn {
                    VStack(alignment: .leading, spacing: Space.x3) {
                        header
                        switch scenario {
                        case .diagrams: diagrams
                        case .markers: markers
                        case .guide, .guidePoor, .guideLoupe, .guideTwisted: guide
                        }
                    }
                    .padding(Space.screenMargin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentMargins(.bottom, proxy.safeAreaInsets.bottom, for: .scrollContent)
            .clipped()
            .padding(.top, proxy.safeAreaInsets.top)
            .ignoresSafeArea(.container, edges: .vertical)
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .onAppear {
            if scenario == .guidePoor { corners[2] = VideoPixel(x: corners[2].x + 9, y: corners[2].y - 7) }
            if scenario == .guideTwisted { corners[2] = CourtGuideReadout.twistedFarRight }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text("Court components")
                .font(.jovraHeadline)
                .foregroundStyle(.jovra(.textPrimary))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("screen.title")
            VStack(alignment: .leading, spacing: Space.x1) { sampleNote }
        }
    }

    @ViewBuilder private var sampleNote: some View {
        SampleBadge()
        Text("Synthetic sample placements")
            .font(.jovraCaption)
            .foregroundStyle(.jovra(.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Diagrams

    private var diagrams: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            courtCard {
                VStack(alignment: .leading, spacing: Space.half) {
                    Text("Jon vs Alex").font(.jovraHeadline).foregroundStyle(.jovra(.textOnEditorial))
                    Text("Oct 6, 2026 · Sample · 54 min · Singles").font(.jovraCaption).foregroundStyle(.jovra(.textSecondaryOnEditorial))
                }
                CourtDiagram(variant: .full, placements: SamplePlacements.forehands,
                             summary: "Forehand placements, sample, 15 placed: 9 deep, 2 short, 3 out, 1 needs review")
                    // As on the shot map (S11): the whole court, both baselines, sits in the card with its legend.
                    .frame(height: Self.fullCourtHeight)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("court.diagram.full")
                CourtMarkerLegend()
            }
            courtCard {
                HStack {
                    Text("Serve placement").font(.jovraHeadline).foregroundStyle(.jovra(.textOnEditorial))
                    Spacer(minLength: Space.x1)
                    Text(deuce ? "Deuce" : "Ad").font(.jovraLabel).foregroundStyle(.jovra(.accentInk))
                }
                CourtDiagram(variant: .serviceBox(deuce ? .deuce : .ad), placements: SamplePlacements.serves(deuce: deuce),
                             summary: "Deuce first serves in, sample, 8 placed: 4 wide, 3 body, 1 T", markerSize: 16)
                    .frame(maxWidth: 240)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("court.diagram.serviceBox")
            }
            courtCard {
                Text("Half court").font(.jovraHeadline).foregroundStyle(.jovra(.textOnEditorial))
                CourtDiagram(variant: .half, placements: Array(SamplePlacements.forehands.prefix(6)),
                             summary: "Half court, sample, 6 placed")
                    .accessibilityIdentifier("court.diagram.half")
            }
        }
    }

    // MARK: - Markers

    private var markers: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            courtCard {
                Text("Court markers").font(.jovraHeadline).foregroundStyle(.jovra(.textOnEditorial))
                let kinds = CourtMarkerKind.allCases
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Space.x2) { ForEach(kinds) { markerCell($0) } }
                } else {
                    VStack(spacing: Space.x2) {
                        HStack(alignment: .top, spacing: Space.x2) { ForEach(kinds.prefix(3)) { markerCell($0) } }
                        HStack(alignment: .top, spacing: Space.x2) { ForEach(kinds.suffix(2)) { markerCell($0) } }
                    }
                }
                CourtMarkerLegend(kinds: CourtMarkerKind.allCases)
            }
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("Read aloud").font(.jovraLabel).foregroundStyle(.jovra(.textSecondary))
                ForEach(SamplePlacements.spokenExamples) { placement in
                    HStack(spacing: Space.x2) {
                        ZStack { Circle().fill(Color.jovra(.courtSurface)); CourtMarker(kind: placement.kind, size: 14) }
                            .frame(width: 30, height: 30)
                        Text(placement.spoken(clamped: false))
                            .font(.jovraBody)
                            .foregroundStyle(.jovra(.textPrimary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .jovraCard()
        }
    }

    private func markerCell(_ kind: CourtMarkerKind) -> some View {
        let cell = typeSize.isAccessibilitySize ? AnyLayout(HStackLayout(spacing: Space.x2)) : AnyLayout(VStackLayout(spacing: Space.x1))
        return cell {
            CourtMarker(kind: kind, size: 28)
            // The glyph is decorative, so the word is the element: plain text the audit can place and measure.
            Text(kind.title)
                .font(.jovraCaption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.jovra(.textOnEditorial))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(kind.spokenLegend))
                .accessibilityIdentifier("court.markerKind.\(kind.rawValue)")
        }
        .frame(maxWidth: .infinity, alignment: typeSize.isAccessibilitySize ? .leading : .center)
    }

    // MARK: - Guide

    private var guide: some View {
        let readout = CourtGuideReadout(corners: corners)
        return VStack(alignment: .leading, spacing: Space.x2) {
            PerspectiveCourtGuide(videoSize: SyntheticCourtCamera.size, corners: $corners, defaults: SyntheticCourtCamera.trueCorners,
                                  pinnedLoupe: scenario == .guideLoupe ? 2 : nil) {
                SyntheticCourtFrame()
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(Color.jovra(.editorial))
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            // At accessibility sizes the badge would cover the far brackets; the page header carries it instead.
            .overlay(alignment: .topTrailing) {
                if !typeSize.isAccessibilitySize { SampleBadge(size: .small, onForest: true).padding(Space.x1) }
            }
            .accessibilityIdentifier("court.guide")
            VStack(alignment: .leading, spacing: Space.half) {
                Text(readout.passes ? "All four corners visible" : "Check the corners")
                    .font(.jovraHeadline)
                    .foregroundStyle(.jovra(.textPrimary))
                Text(readout.passes ? "Keep the phone steady and the net centered."
                     : "The court lines don't match. Drag the brackets onto the outer corners.")
                    .font(.jovraBody)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                Text(readout.residual)
                    .font(.jovraTimecode)
                    .foregroundStyle(.jovra(readout.passes ? .positiveInk : .attentionInk))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("court.check")
            }
        }
    }

    private func courtCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) { content() }
            .padding(Space.x2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.jovra(.courtSurface)))
            .environment(\.colorScheme, .dark)
    }
}

/// What the gallery says under the framing guide for the current brackets (story 66). Only a good check reads as
/// the good state. A fit that is refused, or one so twisted that it puts court lines beyond its own horizon, has
/// no residual: it says so in words and never prints 0.0 px. A twisted fit reads that way with nothing measured too.
struct CourtGuideReadout: Equatable {
    /// Where the `guide-twisted` scenario puts the far right bracket: the middle of the court in the 1080p frame.
    static let twistedFarRight = VideoPixel(x: 960, y: 600)

    let passes: Bool
    let residual: String

    init(corners: [VideoPixel], observations: [CalibrationObservation] = SyntheticCourtCamera.untappedObservations,
         frameHeight: Int = 1080) {
        let tapped = CourtGeometry.doublesCorners.map(\.point)
        guard let homography = try? Homography.fit(image: corners, court: tapped) else {
            passes = false
            residual = "Untapped lines: no fit through these corners"
            return
        }
        let check = CalibrationCheck(homography: homography, tapped: tapped, observations: observations, frameHeight: frameHeight)
        passes = check.verdict == .good
        let limit = String(format: "limit %.0f px", check.thresholdPx)
        switch (check.verdict, check.rmsePx) {
        case (.notMeasurable, _): residual = "Untapped lines: not measured"
        case (_, let rmsePx?): residual = String(format: "Untapped lines: %.1f px RMSE, ", rmsePx) + limit
        case (_, nil): residual = "Untapped lines: beyond the horizon, " + limit
        }
    }
}

/// Sample placements for the gallery, landings normalized onto the far half (S11). Never real data.
enum SamplePlacements {
    static let forehands: [CourtPlacement] = {
        let ins: [(Double, Double)] = [(-3.0, 10.0), (-1.4, 9.2), (2.6, 10.6), (3.4, 8.1), (0.4, 7.4), (-3.6, 7.9), (1.8, 11.2),
                                       (-2.2, 4.5), (2.9, 3.6)]
        var out = ins.enumerated().map { i, p in
            CourtPlacement(id: "fh\(i)", court: CourtPoint(x: p.0, y: p.1), kind: .in, hitterX: 2.0, context: "Point \(31 + i)")
        }
        out.append(CourtPlacement(id: "fh-out1", court: CourtPoint(x: -4.6, y: 9.8), kind: .out, hitterX: 2.0, context: "Point 41"))
        out.append(CourtPlacement(id: "fh-out2", court: CourtPoint(x: 1.2, y: 12.4), kind: .out, hitterX: 2.0, context: "Point 44"))
        out.append(CourtPlacement(id: "fh-out3", court: CourtPoint(x: 8.5, y: 13.9), kind: .out, hitterX: 2.0, context: "Point 46"))
        out.append(CourtPlacement(id: "fh-review", court: CourtPoint(x: 3.9, y: 11.6), kind: .needsReview, hitterX: -1.0, context: "Point 49"))
        out.insert(CourtPlacement(id: "p37", court: CourtPoint(x: -2.9, y: 10.3), kind: .in, hitterX: 2.0, context: "Point 37"), at: 0)
        return out
    }()

    static func serves(deuce: Bool) -> [CourtPlacement] {
        let sign: Double = deuce ? -1 : 1
        let xs: [(Double, Double, CourtMarkerKind)] = [(3.7, 5.6, .in), (3.4, 4.8, .in), (3.9, 3.9, .in), (3.1, 6.0, .in),
                                                       (2.2, 5.1, .in), (1.9, 4.2, .in), (1.5, 5.9, .in), (0.4, 5.5, .in)]
        return xs.enumerated().map { i, p in
            CourtPlacement(id: "sv\(i)", court: CourtPoint(x: sign * p.0, y: p.1), kind: p.2, hitterX: -sign * 0.5, context: "Serve \(i + 1)")
        }
    }

    static let spokenExamples: [CourtPlacement] = [
        CourtPlacement(id: "ex1", court: CourtPoint(x: -3, y: 10), kind: .in, hitterX: 2, context: nil),
        CourtPlacement(id: "ex2", court: CourtPoint(x: 3, y: 4), kind: .in, hitterX: 2, context: nil),
        CourtPlacement(id: "ex3", court: CourtPoint(x: 0.8, y: 9), kind: .needsReview, hitterX: -2.5, context: nil),
        CourtPlacement(id: "ex4", court: CourtPoint(x: 4.6, y: 8), kind: .out, hitterX: -1, context: nil),
    ]
}

/// The renderer's behind-baseline camera at 1080p (scripts/media/jovra_media/court3d.py; eye 15 m behind the near
/// baseline, 7.5 m up, aimed at the far service line): the synthetic calibrated frame of spec/fixtures/calibration,
/// so the true corners are exact. Plain geometry outside any view, so drawing code and constant tables can call it
/// without actor isolation.
enum SyntheticCourtCamera {
    static let size = CGSize(width: 1920, height: 1080)

    static func project(_ p: CourtPoint) -> VideoPixel {
        let eye = (0.0, -15.0 - CourtGeometry.halfLength, 7.5), target = (0.0, 9.0 - CourtGeometry.halfLength, 0.0)
        func sub(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> (Double, Double, Double) { (a.0 - b.0, a.1 - b.1, a.2 - b.2) }
        func dot(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double { a.0 * b.0 + a.1 * b.1 + a.2 * b.2 }
        func unit(_ a: (Double, Double, Double)) -> (Double, Double, Double) { let n = dot(a, a).squareRoot(); return (a.0 / n, a.1 / n, a.2 / n) }
        let f = unit(sub(target, eye))
        let r = unit((f.1 * 1 - f.2 * 0, f.2 * 0 - f.0 * 1, f.0 * 0 - f.1 * 0))
        let u = (r.1 * f.2 - r.2 * f.1, r.2 * f.0 - r.0 * f.2, r.0 * f.1 - r.1 * f.0)
        let d = sub((p.x, p.y, 0), eye), z = dot(d, f), focal = 1.05 * size.width
        return VideoPixel(x: size.width / 2 + focal * dot(d, r) / z, y: size.height / 2 - focal * dot(d, u) / z)
    }

    static let trueCorners = CourtGeometry.doublesCorners.map { project($0.point) }
    static let untappedObservations = CourtIntersection.allCases.filter { !CourtGeometry.doublesCorners.contains($0) }
        .map { CalibrationObservation(court: $0.point, pixel: project($0.point)) }
}

/// A vector stand-in for a recorded frame: the court as `SyntheticCourtCamera` sees it. Not footage.
struct SyntheticCourtFrame: View {
    var body: some View {
        GeometryReader { proxy in
            let mapping = VideoFrameMapping(viewSize: PlaneSize(width: proxy.size.width, height: proxy.size.height),
                                            videoSize: PlaneSize(width: SyntheticCourtCamera.size.width, height: SyntheticCourtCamera.size.height))
            Canvas { context, _ in
                func quad(_ points: [CourtPoint]) -> Path {
                    var path = Path()
                    for (i, p) in points.enumerated() {
                        let v = mapping.viewPoint(fromVideo: SyntheticCourtCamera.project(p))
                        i == 0 ? path.move(to: CGPoint(x: v.x, y: v.y)) : path.addLine(to: CGPoint(x: v.x, y: v.y))
                    }
                    path.closeSubpath()
                    return path
                }
                let frame = mapping.viewPoint(fromVideo: VideoPixel(x: 0, y: 0)), end = mapping.viewPoint(fromVideo: VideoPixel(x: 1920, y: 1080))
                let rect = CGRect(x: frame.x, y: frame.y, width: end.x - frame.x, height: end.y - frame.y)
                context.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(red: 0.36, green: 0.49, blue: 0.62), Color(red: 0.55, green: 0.66, blue: 0.74)]),
                                                                startPoint: rect.origin, endPoint: CGPoint(x: rect.minX, y: rect.midY)))
                context.clip(to: Path(rect))
                let d = CourtGeometry.doublesHalfWidth, l = CourtGeometry.halfLength
                context.fill(quad([CourtPoint(x: -d - 3.66, y: -l - 6.4), CourtPoint(x: d + 3.66, y: -l - 6.4),
                                   CourtPoint(x: d + 3.66, y: l + 6.4), CourtPoint(x: -d - 3.66, y: l + 6.4)]),
                             with: .color(Color(red: 0.22, green: 0.43, blue: 0.31)))
                context.fill(quad([CourtPoint(x: -d, y: -l), CourtPoint(x: d, y: -l), CourtPoint(x: d, y: l), CourtPoint(x: -d, y: l)]),
                             with: .color(Color(red: 0.20, green: 0.38, blue: 0.56)))
                for line in CourtGeometry.lines where line.kind != .net {
                    var path = Path()
                    let a = mapping.viewPoint(fromVideo: SyntheticCourtCamera.project(line.from)), b = mapping.viewPoint(fromVideo: SyntheticCourtCamera.project(line.to))
                    path.move(to: CGPoint(x: a.x, y: a.y))
                    path.addLine(to: CGPoint(x: b.x, y: b.y))
                    context.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 1.2)
                }
                let left = mapping.viewPoint(fromVideo: SyntheticCourtCamera.project(CourtPoint(x: -6.4, y: 0)))
                let right = mapping.viewPoint(fromVideo: SyntheticCourtCamera.project(CourtPoint(x: 6.4, y: 0)))
                let netHeight = (mapping.viewPoint(fromVideo: SyntheticCourtCamera.project(CourtPoint(x: 0, y: -0.9))).y - left.y) * 0.9
                context.fill(Path(CGRect(x: left.x, y: left.y - netHeight, width: right.x - left.x, height: netHeight)),
                             with: .color(Color(red: 0.12, green: 0.16, blue: 0.2).opacity(0.75)))
                context.stroke(Path { $0.move(to: CGPoint(x: left.x, y: left.y - netHeight)); $0.addLine(to: CGPoint(x: right.x, y: right.y - netHeight)) },
                               with: .color(.white.opacity(0.9)), lineWidth: 1.2)
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
