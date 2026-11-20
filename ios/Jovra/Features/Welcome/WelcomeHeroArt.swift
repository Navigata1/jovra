import SwiftUI

/// Welcome's hero (screens.md S01, deliberate differences): a vector court at golden hour instead of the reference's
/// photograph, which has no usage clearance and puts product marks on the ball and racket. A hardcourt in perspective
/// from behind the baseline, a net with its tape, a low sun, and a charcoal racket with chartreuse mains and ivory
/// crosses lying beside a plain ball. Brand colours only; no marks; hidden from VoiceOver.
struct WelcomeHeroArt: View {
    var body: some View {
        Canvas { context, size in
            let scene = HeroScene(size: size)
            scene.drawSky(&context)
            scene.drawCourt(&context)
            scene.drawNet(&context)
            scene.drawBall(&context)
            scene.drawRacket(&context)
            scene.drawFade(&context)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct HeroScene {
    let size: CGSize
    private var w: CGFloat { size.width }
    private var h: CGFloat { size.height }
    /// The far edge of the court; above it, the sky and the tree line.
    private var horizon: CGFloat { h * 0.40 }
    private var vanishing: CGPoint { CGPoint(x: w * 0.5, y: horizon) }

    private static let forest = Color(uiColor: BrandPalette.forest.uiColor)
    private static let panel = Color(uiColor: BrandPalette.forestPanel.uiColor)
    private static let ivory = Color(uiColor: BrandPalette.ivory.uiColor)
    private static let charcoal = Color(uiColor: BrandPalette.charcoal.uiColor)
    private static let chartreuse = Color(uiColor: BrandPalette.chartreuse.uiColor)
    private static let clay = Color(uiColor: BrandPalette.clay.uiColor)

    /// Screen x of court position `u` (−1 left doubles sideline … 1 right) on the screen row `y`.
    private func x(_ u: CGFloat, atY y: CGFloat) -> CGFloat {
        let depth = max(0, (y - horizon) / (h - horizon))
        return vanishing.x + u * w * 1.05 * depth
    }

    /// Screen row at a depth fraction between the horizon (0) and the bottom edge (1).
    private func row(_ t: CGFloat) -> CGFloat { horizon + (h - horizon) * t }

    func drawSky(_ context: inout GraphicsContext) {
        let sky = CGRect(x: 0, y: 0, width: w, height: horizon + 2)
        context.fill(Path(sky), with: .linearGradient(
            Gradient(stops: [.init(color: Self.forest, location: 0),
                             .init(color: Self.panel, location: 0.55),
                             .init(color: Self.clay.opacity(0.85), location: 1)]),
            startPoint: CGPoint(x: w / 2, y: 0), endPoint: CGPoint(x: w / 2, y: horizon)))
        // The low sun, off the leading side of the horizon.
        let sun = CGPoint(x: w * 0.14, y: horizon - h * 0.06)
        context.fill(Path(sky), with: .radialGradient(
            Gradient(colors: [Self.ivory.opacity(0.95), Self.chartreuse.opacity(0.35), Self.clay.opacity(0)]),
            center: sun, startRadius: 2, endRadius: w * 0.55))
        // Tree line and windscreen along the far fence.
        var trees = Path()
        trees.move(to: CGPoint(x: 0, y: horizon))
        let crowns = 9
        for index in 0...crowns {
            let cx = w * CGFloat(index) / CGFloat(crowns)
            let top = horizon - h * (0.05 + 0.025 * CGFloat((index * 7) % 3))
            trees.addQuadCurve(to: CGPoint(x: cx + w / CGFloat(crowns) / 2, y: top),
                               control: CGPoint(x: cx, y: top - h * 0.015))
        }
        trees.addLine(to: CGPoint(x: w, y: horizon))
        trees.closeSubpath()
        context.fill(trees, with: .color(Self.forest.opacity(0.92)))
        context.fill(Path(CGRect(x: 0, y: horizon - h * 0.035, width: w, height: h * 0.035)), with: .color(Self.forest))
    }

    func drawCourt(_ context: inout GraphicsContext) {
        let ground = CGRect(x: 0, y: horizon, width: w, height: h - horizon)
        context.fill(Path(ground), with: .linearGradient(
            Gradient(colors: [Self.panel, Self.forest]),
            startPoint: CGPoint(x: w / 2, y: horizon), endPoint: CGPoint(x: w / 2, y: h)))
        // Warm light raking across the surface from the sun.
        context.fill(Path(ground), with: .linearGradient(
            Gradient(colors: [Self.clay.opacity(0.28), Self.clay.opacity(0)]),
            startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: w * 0.7, y: horizon + h * 0.25)))

        var lines = Path()
        let farBaseline = row(0.05), farService = row(0.16), nearService = row(0.55), bottom = h
        for y in [farBaseline, farService, nearService] {
            lines.move(to: CGPoint(x: x(-1, atY: y), y: y))
            lines.addLine(to: CGPoint(x: x(1, atY: y), y: y))
        }
        for u: CGFloat in [-1, -0.75, 0.75, 1] {
            lines.move(to: CGPoint(x: x(u, atY: farBaseline), y: farBaseline))
            lines.addLine(to: CGPoint(x: x(u, atY: bottom), y: bottom))
        }
        lines.move(to: CGPoint(x: x(0, atY: farService), y: farService))
        lines.addLine(to: CGPoint(x: x(0, atY: nearService), y: nearService))
        context.stroke(lines, with: .color(Self.ivory.opacity(0.55)), lineWidth: 1.6)
    }

    func drawNet(_ context: inout GraphicsContext) {
        let base = row(0.30)
        let height = (base - horizon) * 0.42
        let left = x(-1.12, atY: base), right = x(1.12, atY: base)
        var mesh = Path()
        mesh.addRect(CGRect(x: left, y: base - height, width: right - left, height: height))
        // Shadow of the net on the court, cast toward the viewer.
        context.fill(Path(CGRect(x: left, y: base, width: right - left, height: height * 0.35)), with: .color(Self.forest.opacity(0.35)))
        context.fill(mesh, with: .color(Self.forest.opacity(0.55)))
        var strands = Path()
        let columns = 46
        for index in 0...columns {
            let px = left + (right - left) * CGFloat(index) / CGFloat(columns)
            strands.move(to: CGPoint(x: px, y: base - height))
            strands.addLine(to: CGPoint(x: px, y: base))
        }
        for index in 1..<7 {
            let py = base - height * CGFloat(index) / 7
            strands.move(to: CGPoint(x: left, y: py))
            strands.addLine(to: CGPoint(x: right, y: py))
        }
        context.stroke(strands, with: .color(Self.ivory.opacity(0.16)), lineWidth: 0.6)
        context.fill(Path(CGRect(x: left, y: base - height - 2, width: right - left, height: 3.5)), with: .color(Self.ivory.opacity(0.9)))
        for post in [left, right] {
            context.fill(Path(roundedRect: CGRect(x: post - 2.5, y: base - height - 5, width: 5, height: height + 5), cornerRadius: 2),
                         with: .color(Self.charcoal))
        }
    }

    func drawBall(_ context: inout GraphicsContext) {
        let radius = min(w, h) * 0.055
        let centre = CGPoint(x: w * 0.17, y: h * 0.80)
        context.fill(Path(ellipseIn: CGRect(x: centre.x - radius * 0.6, y: centre.y + radius * 0.7, width: radius * 2.6, height: radius * 0.7)),
                     with: .color(Self.forest.opacity(0.6)))
        let ball = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        context.fill(ball, with: .radialGradient(
            Gradient(colors: [Self.ivory.opacity(0.9), Self.chartreuse, Self.chartreuse.opacity(0.85)]),
            center: CGPoint(x: centre.x - radius * 0.4, y: centre.y - radius * 0.4), startRadius: 0, endRadius: radius * 1.4))
        var seam = Path()
        seam.addArc(center: CGPoint(x: centre.x - radius * 1.25, y: centre.y), radius: radius * 0.95,
                    startAngle: .degrees(-50), endAngle: .degrees(50), clockwise: false)
        context.stroke(seam, with: .color(Self.ivory.opacity(0.85)), lineWidth: max(1, radius * 0.1))
    }

    func drawRacket(_ context: inout GraphicsContext) {
        var racket = context
        // Head toward the net, handle toward the lower trailing corner, as the reference lays it.
        let centre = CGPoint(x: w * 0.47, y: h * 0.70)
        racket.translateBy(x: centre.x, y: centre.y)
        racket.rotate(by: .degrees(26))
        let headWidth = w * 0.34, headHeight = w * 0.245
        let head = CGRect(x: -headWidth / 2, y: -headHeight / 2, width: headWidth, height: headHeight)

        // Shadow on the court.
        var shadow = racket
        shadow.translateBy(x: w * 0.03, y: h * 0.035)
        shadow.fill(Path(ellipseIn: head), with: .color(Self.forest.opacity(0.55)))
        shadow.fill(Path(roundedRect: CGRect(x: headWidth / 2, y: -headHeight * 0.07, width: headWidth * 0.9, height: headHeight * 0.14),
                         cornerRadius: headHeight * 0.07), with: .color(Self.forest.opacity(0.55)))

        // Strings, clipped to the head: chartreuse mains along the racket, ivory crosses across it.
        var strings = racket
        strings.clip(to: Path(ellipseIn: head.insetBy(dx: 5, dy: 5)))
        var crosses = Path(), mains = Path()
        for index in 0..<18 {
            let px = head.minX + head.width * CGFloat(index + 1) / 19
            crosses.move(to: CGPoint(x: px, y: head.minY)); crosses.addLine(to: CGPoint(x: px, y: head.maxY))
        }
        for index in 0..<14 {
            let py = head.minY + head.height * CGFloat(index + 1) / 15
            mains.move(to: CGPoint(x: head.minX, y: py)); mains.addLine(to: CGPoint(x: head.maxX, y: py))
        }
        strings.stroke(crosses, with: .color(Self.ivory.opacity(0.7)), lineWidth: 1)
        strings.stroke(mains, with: .color(Self.chartreuse), lineWidth: 1.4)

        // Frame, throat and handle.
        racket.stroke(Path(ellipseIn: head), with: .color(Self.charcoal), lineWidth: max(6, w * 0.018))
        // A thin sunlit rim so the charcoal frame reads against the dark court.
        racket.stroke(Path(ellipseIn: head.insetBy(dx: -3, dy: -3)), with: .color(Self.ivory.opacity(0.55)), lineWidth: 1.2)
        var throat = Path()
        throat.move(to: CGPoint(x: head.maxX - head.width * 0.06, y: -head.height * 0.33))
        throat.addQuadCurve(to: CGPoint(x: head.maxX + headWidth * 0.22, y: -headHeight * 0.06), control: CGPoint(x: head.maxX + headWidth * 0.08, y: -head.height * 0.1))
        throat.move(to: CGPoint(x: head.maxX - head.width * 0.06, y: head.height * 0.33))
        throat.addQuadCurve(to: CGPoint(x: head.maxX + headWidth * 0.22, y: headHeight * 0.06), control: CGPoint(x: head.maxX + headWidth * 0.08, y: head.height * 0.1))
        racket.stroke(throat, with: .color(Self.ivory.opacity(0.4)), lineWidth: max(5, w * 0.014) + 2)
        racket.stroke(throat, with: .color(Self.charcoal), lineWidth: max(5, w * 0.014))
        let handle = CGRect(x: head.maxX + headWidth * 0.2, y: -headHeight * 0.075, width: headWidth * 0.72, height: headHeight * 0.15)
        racket.stroke(Path(roundedRect: handle.insetBy(dx: -1.5, dy: -1.5), cornerRadius: handle.height / 2),
                      with: .color(Self.ivory.opacity(0.4)), lineWidth: 1.2)
        racket.fill(Path(roundedRect: handle, cornerRadius: handle.height / 2), with: .color(Self.charcoal))
        var grip = Path()
        for index in 1..<9 {
            let gx = handle.minX + handle.width * CGFloat(index) / 9
            grip.move(to: CGPoint(x: gx, y: handle.minY + 1)); grip.addLine(to: CGPoint(x: gx - 4, y: handle.maxY - 1))
        }
        racket.stroke(grip, with: .color(Self.ivory.opacity(0.18)), lineWidth: 1)
    }

    /// The lower edge melts into the forest panel under the hero.
    func drawFade(_ context: inout GraphicsContext) {
        let band = CGRect(x: 0, y: h * 0.82, width: w, height: h * 0.18)
        context.fill(Path(band), with: .linearGradient(
            Gradient(colors: [Self.forest.opacity(0), Self.forest]),
            startPoint: CGPoint(x: w / 2, y: band.minY), endPoint: CGPoint(x: w / 2, y: band.maxY)))
    }
}
