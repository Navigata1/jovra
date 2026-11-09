import SwiftUI

/// Hero and editorial art (screens.md §6 open question 2): vector only, drawn in brand colours —
/// court lines in perspective, a ball's flight and a sweeping court arc. No photographs, no marks,
/// and hidden from VoiceOver, because it carries no information.
struct CourtHeroArt: View {
    enum Emphasis {
        /// Behind text on an editorial card: lines stay quiet.
        case backdrop
        /// A standalone illustration (Welcome, empty states): a little brighter.
        case feature
    }

    var emphasis: Emphasis = .backdrop

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let line = Color.jovra(.courtLine)
            let lineOpacity = emphasis == .backdrop ? 0.14 : 0.24

            // The court, seen from behind the near baseline.
            context.stroke(CourtLinesBackdrop().path(in: rect), with: .color(line.opacity(lineOpacity)), lineWidth: 1.5)

            // A sweeping arc echoing the court-arc mark, off the top trailing corner.
            var arc = Path()
            arc.addArc(center: CGPoint(x: rect.maxX + rect.width * 0.08, y: rect.minY - rect.height * 0.05),
                       radius: rect.width * 0.55, startAngle: .degrees(100), endAngle: .degrees(185), clockwise: false)
            context.stroke(arc, with: .color(Color.jovra(.accent).opacity(emphasis == .backdrop ? 0.16 : 0.28)), lineWidth: 2)

            // The ball's flight: a dashed parabola ending at the ball.
            let start = CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.92)
            let ball = CGPoint(x: rect.minX + rect.width * 0.86, y: rect.minY + rect.height * 0.30)
            var flight = Path()
            flight.move(to: start)
            flight.addQuadCurve(to: ball, control: CGPoint(x: rect.midX + rect.width * 0.05, y: rect.minY - rect.height * 0.12))
            context.stroke(flight, with: .color(line.opacity(lineOpacity + 0.06)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 7]))

            let radius = max(4, min(size.width, size.height) * 0.028)
            let halo = CGRect(x: ball.x - radius * 3, y: ball.y - radius * 3, width: radius * 6, height: radius * 6)
            context.fill(Path(ellipseIn: halo), with: .radialGradient(
                Gradient(colors: [Color.jovra(.accent).opacity(0.35), Color.jovra(.accent).opacity(0)]),
                center: ball, startRadius: radius, endRadius: radius * 3))
            context.fill(Path(ellipseIn: CGRect(x: ball.x - radius, y: ball.y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(Color.jovra(.accent)))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
