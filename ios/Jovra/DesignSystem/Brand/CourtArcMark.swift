import SwiftUI

/// The J and V letterforms of the Court Arc mark, aspect-fitted into the rect.
/// Fit is computed against the full mark (ball included) so it aligns with `CourtArcBallShape`.
struct CourtArcLettersShape: Shape {
    func path(in rect: CGRect) -> Path {
        var fit = BrandGeometry.fitting(BrandGeometry.markBounds, into: rect)
        return Path(BrandGeometry.markLetters.copy(using: &fit) ?? CGMutablePath())
    }
}

/// The chartreuse ball accent at the top right of the V.
struct CourtArcBallShape: Shape {
    func path(in rect: CGRect) -> Path {
        var fit = BrandGeometry.fitting(BrandGeometry.markBounds, into: rect)
        return Path(BrandGeometry.markBall.copy(using: &fit) ?? CGMutablePath())
    }
}

/// The JV Court Arc mark: single-colour letters plus the ball accent. Scales to any size.
struct CourtArcMark: View {
    var letters: Color = .jovra(.brandMark)
    var ball: Color = .jovra(.accent)

    var body: some View {
        ZStack {
            CourtArcLettersShape().fill(letters)
            CourtArcBallShape().fill(ball)
        }
        .aspectRatio(BrandGeometry.markBounds.width / BrandGeometry.markBounds.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("JOVRA Tennis")
        .accessibilityAddTraits(.isImage)
    }
}

/// "JOVRA" drawn as paths (a wide geometric wordmark with a crossbar-less A).
struct JovraWordmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var fit = BrandGeometry.fitting(BrandGeometry.wordmarkBounds, into: rect)
        return Path(BrandGeometry.wordmark.copy(using: &fit) ?? CGMutablePath())
    }
}

/// The full lockup: mark, then "JOVRA" over letter-spaced "TENNIS". Drawn in a Canvas because it is
/// artwork (a fixed-proportion logo, not text that should reflow with Dynamic Type); VoiceOver reads
/// it as one image, "JOVRA Tennis".
struct JovraLockup: View {
    /// Height of the mark; everything else is proportional.
    var height: CGFloat = 40
    var markColor: Color = .jovra(.brandMark)
    var tennisColor: Color = .jovra(.accentInk)
    var ballColor: Color = .jovra(.accent)

    private var markWidth: CGFloat {
        height * BrandGeometry.markBounds.width / BrandGeometry.markBounds.height
    }
    private var gap: CGFloat { height * 0.14 }
    private var wordmarkHeight: CGFloat { height * 0.36 }
    private var wordmarkWidth: CGFloat {
        wordmarkHeight * BrandGeometry.wordmarkBounds.width / BrandGeometry.wordmarkBounds.height
    }

    var body: some View {
        Canvas { context, size in
            let markRect = CGRect(x: 0, y: 0, width: markWidth, height: size.height)
            context.fill(CourtArcLettersShape().path(in: markRect), with: .color(markColor))
            context.fill(CourtArcBallShape().path(in: markRect), with: .color(ballColor))

            let wordTop = height * 0.30
            let wordRect = CGRect(x: markWidth + gap, y: wordTop, width: wordmarkWidth, height: wordmarkHeight)
            context.fill(JovraWordmarkShape().path(in: wordRect), with: .color(markColor))

            // Centred under JOVRA at about half its width, as on the logo board. Tracking is added after
            // every glyph, the last included, so the centre shifts right by half of it.
            let tracking = height * 0.095
            let tennis = Text(verbatim: "TENNIS")
                .font(.system(size: height * 0.18, weight: .semibold))
                .tracking(tracking)
                .foregroundStyle(tennisColor)
            context.draw(tennis, at: CGPoint(x: wordRect.midX + tracking / 2, y: wordRect.maxY + height * 0.2), anchor: .center)
        }
        .frame(width: markWidth + gap + wordmarkWidth, height: height)
        .accessibilityElement()
        .accessibilityLabel("JOVRA Tennis")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("brand.lockup")
    }
}

#Preview("Lockup") {
    VStack(spacing: 32) {
        JovraLockup(height: 64)
        JovraLockup(height: 40)
        HStack(spacing: 24) {
            ForEach([120.0, 60, 40, 29], id: \.self) { size in
                CourtArcMark().frame(height: size)
            }
        }
    }
    .padding()
    .background(Color.jovra(.background))
}
