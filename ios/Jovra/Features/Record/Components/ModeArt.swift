import JovraCore
import SwiftUI

/// Vector art for each mode row (S04 replaces the reference's photographs): a court seen from behind
/// the baseline with the players as discs, or the ball's path for practice. Decorative; hidden from
/// VoiceOver. Colours are fixed brand inks so the art reads the same on a selected or plain row.
struct ModeArt: View {
    var mode: SessionSetup.Mode

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [Self.forestTop, Self.forestBottom]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let court = CourtLinesBackdrop().path(in: rect.insetBy(dx: -size.width * 0.05, dy: 0))
            context.stroke(court, with: .color(Self.line.opacity(0.55)), lineWidth: 1.2)
            switch mode {
            case .singlesMatch:
                player(context, at: CGPoint(x: size.width * 0.66, y: size.height * 0.26), radius: 3.5)
                player(context, at: CGPoint(x: size.width * 0.42, y: size.height * 0.86), radius: 6)
                ball(context, at: CGPoint(x: size.width * 0.56, y: size.height * 0.46), size: size)
            case .doublesMatch:
                for x in [0.58, 0.74] { player(context, at: CGPoint(x: size.width * x, y: size.height * 0.26), radius: 3.5) }
                for x in [0.3, 0.62] { player(context, at: CGPoint(x: size.width * x, y: size.height * 0.84), radius: 6) }
                ball(context, at: CGPoint(x: size.width * 0.5, y: size.height * 0.5), size: size)
            case .servePractice:
                var arc = Path()
                arc.move(to: CGPoint(x: size.width * 0.3, y: size.height * 0.9))
                arc.addQuadCurve(to: CGPoint(x: size.width * 0.7, y: size.height * 0.3),
                                 control: CGPoint(x: size.width * 0.32, y: size.height * 0.05))
                context.stroke(arc, with: .color(Self.ball.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3, 4]))
                ball(context, at: CGPoint(x: size.width * 0.7, y: size.height * 0.3), size: size)
                player(context, at: CGPoint(x: size.width * 0.3, y: size.height * 0.9), radius: 6)
            case .strokePractice:
                var swing = Path()
                swing.addArc(center: CGPoint(x: size.width * 0.42, y: size.height * 0.62), radius: size.height * 0.34,
                             startAngle: .degrees(200), endAngle: .degrees(330), clockwise: false)
                context.stroke(swing, with: .color(Self.line.opacity(0.9)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                player(context, at: CGPoint(x: size.width * 0.42, y: size.height * 0.66), radius: 6)
                ball(context, at: CGPoint(x: size.width * 0.74, y: size.height * 0.4), size: size)
            }
        }
        .accessibilityHidden(true)
    }

    private func player(_ context: GraphicsContext, at point: CGPoint, radius: CGFloat) {
        let disc = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        context.fill(disc, with: .color(Self.line))
    }

    private func ball(_ context: GraphicsContext, at point: CGPoint, size: CGSize) {
        let radius = max(size.height * 0.05, 3)
        let disc = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        context.fill(disc, with: .color(Self.ball))
    }

    // Brand inks (BrandPalette): forest court, ivory lines, chartreuse ball.
    private static let forestTop = Color(uiColor: BrandPalette.forestPanel.uiColor)
    private static let forestBottom = Color(uiColor: BrandPalette.forest.uiColor)
    private static let line = Color(uiColor: BrandPalette.ivory.uiColor)
    private static let ball = Color(uiColor: BrandPalette.chartreuse.uiColor)
}
