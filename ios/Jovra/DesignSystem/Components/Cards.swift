import SwiftUI

/// Ivory-white card surface: ~22 pt continuous corners, a restrained shadow in light mode and a
/// hairline in dark mode (shadows disappear on forest).
struct CardSurface: ViewModifier {
    var padding: CGFloat = Space.x2
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Shadow the shape only: a shadow on the whole card would also halo every glyph.
                shape
                    .fill(Color.jovra(.surface))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 14, x: 0, y: 6)
            }
            .overlay(shape.strokeBorder(Color.jovra(.separator), lineWidth: colorScheme == .dark ? 1 : 0.5))
    }
}

extension View {
    func jovraCard(padding: CGFloat = Space.x2) -> some View { modifier(CardSurface(padding: padding)) }
}

/// Forest editorial card for hero content, with a quiet court-line backdrop instead of photography.
struct EditorialCard<Content: View>: View {
    @ViewBuilder var content: Content
    /// Read before the card forces a dark environment onto its contents.
    @Environment(\.colorScheme) private var outerScheme

    private var fill: Color {
        Color(uiColor: ColorRole.editorial.color(in: outerScheme == .dark ? .dark : .light).uiColor)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: Space.x2) { content }
            .padding(Space.x3)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .bottomLeading)
            .background {
                ZStack {
                    fill
                    CourtLinesBackdrop()
                        .stroke(Color.jovra(.textOnEditorial).opacity(0.14), lineWidth: 1.5)
                    LinearGradient(
                        colors: [fill.opacity(0), fill.opacity(0.85)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .accessibilityHidden(true)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.jovra(.textOnEditorial).opacity(0.08), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

/// A tennis court seen from behind the baseline, in perspective. Decorative.
struct CourtLinesBackdrop: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let horizon = rect.minY + rect.height * 0.18
        let near = rect.maxY + rect.height * 0.1
        let farHalf = rect.width * 0.16
        let nearHalf = rect.width * 0.72
        let centerX = rect.midX + rect.width * 0.18
        func x(_ fraction: CGFloat, atDepth t: CGFloat) -> CGFloat {
            let half = farHalf + (nearHalf - farHalf) * t
            return centerX + half * fraction
        }
        func y(_ t: CGFloat) -> CGFloat { horizon + (near - horizon) * t }
        // Doubles sidelines, singles sidelines (4.5 ft alleys on a 36 ft court).
        for fraction: CGFloat in [-1, -0.75, 0.75, 1] {
            path.move(to: CGPoint(x: x(fraction, atDepth: 0), y: y(0)))
            path.addLine(to: CGPoint(x: x(fraction, atDepth: 1), y: y(1)))
        }
        // Far baseline, far service line, net, near service line.
        for t: CGFloat in [0, 0.12, 0.3, 0.62] {
            let reach: CGFloat = (t == 0 || t == 0.3) ? 1 : 0.75
            path.move(to: CGPoint(x: x(-reach, atDepth: t), y: y(t)))
            path.addLine(to: CGPoint(x: x(reach, atDepth: t), y: y(t)))
        }
        // Centre service line between the service lines.
        path.move(to: CGPoint(x: x(0, atDepth: 0.12), y: y(0.12)))
        path.addLine(to: CGPoint(x: x(0, atDepth: 0.62), y: y(0.62)))
        return path
    }
}
