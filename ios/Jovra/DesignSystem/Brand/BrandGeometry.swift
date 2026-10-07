import CoreGraphics
import Foundation

/// Vector geometry for the JOVRA brand: the Court Arc JV mark and the JOVRA wordmark.
///
/// CoreGraphics only (no UIKit/SwiftUI) so the same file is compiled into the app and into
/// `scripts/ios/app-icon/`, which renders the App Store icon from this exact geometry.
/// All paths are filled outlines in a private design space; callers fit them into a rect.
enum BrandGeometry {
    // MARK: Court Arc mark

    /// Stroke width of the mark, in design units (the mark is ~100 units wide).
    private static let markStroke: CGFloat = 10.5
    /// Negative space between the J hook and the V's first stroke.
    private static let markGap: CGFloat = 2.6
    /// Both strokes of the V lean at this angle from horizontal.
    private static let vAngle: CGFloat = 62.5 * .pi / 180

    /// The J and V letterforms of the Court Arc mark, without the ball.
    // CGPath is immutable once built, so sharing these constants across isolation domains is safe.
    nonisolated(unsafe) static let markLetters: CGPath = {
        let vertex = CGPoint(x: 61.8, y: 66.5)
        let run = 1 / tan(vAngle) // horizontal travel per unit of vertical travel

        // V: a short flag (the J's top) bends into the first diagonal, meets the vertex, rises to the top.
        let flagY: CGFloat = 26.2
        let corner = CGPoint(x: vertex.x - (vertex.y - flagY) * run, y: flagY)
        let down = CGPoint(x: cos(vAngle), y: sin(vAngle))
        let v = CGMutablePath()
        v.move(to: CGPoint(x: 25.3, y: flagY))
        v.addLine(to: CGPoint(x: corner.x - 6.5, y: flagY))
        v.addQuadCurve(
            to: CGPoint(x: corner.x + down.x * 7, y: corner.y + down.y * 7),
            control: corner
        )
        v.addLine(to: vertex)
        let topY: CGFloat = 6
        v.addLine(to: CGPoint(x: vertex.x + (vertex.y - topY) * run, y: topY))
        let vStroked = v.copy(strokingWithWidth: markStroke, lineCap: .butt, lineJoin: .round, miterLimit: 4)
        // Cut the rising stroke's terminal level, as on the logo board.
        let vClipped = vStroked.intersection(CGPath(rect: CGRect(x: -50, y: 14.2, width: 250, height: 200), transform: nil))

        // J: a bowl whose hook rises toward the V and is cut by a gap parallel to the V's first stroke.
        let bowl = CGMutablePath()
        bowl.addArc(
            center: CGPoint(x: 24.2, y: 50),
            radius: 18.9,
            startAngle: .pi,
            endAngle: -0.25,
            clockwise: true
        )
        let bowlStroked = bowl.copy(strokingWithWidth: markStroke, lineCap: .butt, lineJoin: .round, miterLimit: 4)
        let gapBand = CGMutablePath()
        gapBand.move(to: CGPoint(x: corner.x - down.x * 30, y: corner.y - down.y * 30))
        gapBand.addLine(to: vertex)
        let gapStroked = gapBand.copy(strokingWithWidth: markStroke + markGap * 2, lineCap: .butt, lineJoin: .miter, miterLimit: 4)
        let j = bowlStroked.subtracting(gapStroked)

        return j.union(vClipped)
    }()

    /// The tennis-ball accent at the top right of the V.
    nonisolated(unsafe) static let markBall = CGPath(
        ellipseIn: CGRect(x: 94.6 - 6.6, y: 4.8 - 6.6, width: 13.2, height: 13.2),
        transform: nil
    )

    /// Bounds of the full mark (letters and ball) in design units.
    static let markBounds: CGRect = markLetters.boundingBoxOfPath.union(markBall.boundingBoxOfPath)

    // MARK: Wordmark

    private static let capHeight: CGFloat = 20
    private static let wordStroke: CGFloat = 3.8
    private static let letterGap: CGFloat = 6.2

    /// "JOVRA" with a crossbar-less A, geometric and wide.
    nonisolated(unsafe) static let wordmark: CGPath = {
        let letters = [letterJ(), letterO(), letterV(), letterR(), letterLambda()]
        let word = CGMutablePath()
        var cursor: CGFloat = 0
        for letter in letters {
            let outline = letter.copy(strokingWithWidth: wordStroke, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
                .intersection(CGPath(rect: CGRect(x: -20, y: 0, width: 80, height: capHeight), transform: nil))
            let bounds = outline.boundingBoxOfPath
            var shift = CGAffineTransform(translationX: cursor - bounds.minX, y: 0)
            if let placed = outline.copy(using: &shift) { word.addPath(placed) }
            cursor += bounds.width + letterGap
        }
        return word
    }()

    static let wordmarkBounds: CGRect = wordmark.boundingBoxOfPath

    private static func letterJ() -> CGPath {
        let p = CGMutablePath()
        let stem: CGFloat = 12.8
        let base = capHeight - wordStroke / 2
        p.move(to: CGPoint(x: stem, y: -2))
        p.addLine(to: CGPoint(x: stem, y: 11.5))
        p.addQuadCurve(to: CGPoint(x: stem - 6.2, y: base), control: CGPoint(x: stem, y: base))
        p.addLine(to: CGPoint(x: 0, y: base))
        return p
    }

    private static func letterO() -> CGPath {
        let half = wordStroke / 2
        return CGPath(ellipseIn: CGRect(x: half, y: half, width: 18.75 - wordStroke, height: capHeight - wordStroke), transform: nil)
    }

    private static func letterV() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -1.4, y: -3))
        p.addLine(to: CGPoint(x: 11.7, y: capHeight + 1))
        p.addLine(to: CGPoint(x: 24.8, y: -3))
        return p
    }

    private static func letterR() -> CGPath {
        let half = wordStroke / 2
        let bowlTop = half
        let bowlBottom: CGFloat = 11.4
        let radius = (bowlBottom - bowlTop) / 2
        let p = CGMutablePath()
        p.move(to: CGPoint(x: half, y: capHeight + 2))
        p.addLine(to: CGPoint(x: half, y: bowlTop))
        p.addLine(to: CGPoint(x: 10, y: bowlTop))
        p.addArc(center: CGPoint(x: 10, y: bowlTop + radius), radius: radius, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        p.addLine(to: CGPoint(x: half, y: bowlBottom))
        p.move(to: CGPoint(x: 8.6, y: bowlBottom))
        p.addLine(to: CGPoint(x: 16.9, y: capHeight + 1.5))
        return p
    }

    private static func letterLambda() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -1.3, y: capHeight + 3))
        p.addLine(to: CGPoint(x: 10.95, y: -1))
        p.addLine(to: CGPoint(x: 23.2, y: capHeight + 3))
        return p
    }

    // MARK: Fitting

    /// A transform that aspect-fits `bounds` into `rect`, centred.
    static func fitting(_ bounds: CGRect, into rect: CGRect) -> CGAffineTransform {
        guard bounds.width > 0, bounds.height > 0 else { return .identity }
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let offsetX = rect.midX - bounds.midX * scale
        let offsetY = rect.midY - bounds.midY * scale
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offsetX, ty: offsetY)
    }
}
