import SwiftUI

/// The JV Court Arc mark and the JOVRA wordmark, drawn from the iOS app's `BrandGeometry` (the same source file is
/// compiled into this target), so the watch never ships a second copy of the logo.
private struct MarkLettersShape: Shape {
    func path(in rect: CGRect) -> Path {
        var fit = BrandGeometry.fitting(BrandGeometry.markBounds, into: rect)
        return Path(BrandGeometry.markLetters.copy(using: &fit) ?? CGMutablePath())
    }
}

private struct MarkBallShape: Shape {
    func path(in rect: CGRect) -> Path {
        var fit = BrandGeometry.fitting(BrandGeometry.markBounds, into: rect)
        return Path(BrandGeometry.markBall.copy(using: &fit) ?? CGMutablePath())
    }
}

private struct WordmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var fit = BrandGeometry.fitting(BrandGeometry.wordmarkBounds, into: rect)
        return Path(BrandGeometry.wordmark.copy(using: &fit) ?? CGMutablePath())
    }
}

/// The header lockup in the top-leading toolbar slot, beside the system time: mark plus "JOVRA". It is artwork, so it
/// keeps its size at every text size, and VoiceOver reads it once as "JOVRA".
struct WatchBrandHeader: View {
    private let height: CGFloat = 15

    var body: some View {
        HStack(spacing: height * 0.35) {
            ZStack {
                MarkLettersShape().fill(WatchPalette.ivory)
                MarkBallShape().fill(WatchPalette.chartreuse)
            }
            .aspectRatio(BrandGeometry.markBounds.width / BrandGeometry.markBounds.height, contentMode: .fit)
            .frame(height: height)
            WordmarkShape()
                .fill(WatchPalette.ivory)
                .aspectRatio(BrandGeometry.wordmarkBounds.width / BrandGeometry.wordmarkBounds.height,
                             contentMode: .fit)
                .frame(height: height * 0.52)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "JOVRA")) // the brand name is never translated
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("watch.brand")
    }
}
