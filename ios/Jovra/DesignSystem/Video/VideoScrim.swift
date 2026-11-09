import SwiftUI

/// The darkening behind text and controls drawn over video. A soft gradient normally; under Increase Contrast
/// a solid backing, so overlay text never depends on what the footage happens to show (screens.md §0.4).
struct VideoScrim: View {
    enum Edge { case top, bottom }

    var edge: Edge = .bottom
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if contrast == .increased {
                Color.jovra(.videoScrim)
            } else {
                LinearGradient(colors: [Color.jovra(.videoScrim).opacity(0), Color.jovra(.videoScrim)],
                               startPoint: edge == .bottom ? .top : .bottom,
                               endPoint: edge == .bottom ? .bottom : .top)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Puts a `VideoScrim` behind this overlay content.
    func videoScrim(_ edge: VideoScrim.Edge = .bottom) -> some View {
        background(VideoScrim(edge: edge))
    }

    /// A small dark backing for one overlay element (a badge, a score) that stays legible on any frame:
    /// translucent normally, opaque under Increase Contrast.
    func videoOverlayBacking(cornerRadius: CGFloat = Radius.control) -> some View {
        modifier(VideoOverlayBacking(cornerRadius: cornerRadius))
    }
}

private struct VideoOverlayBacking: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background(Color.jovra(.videoScrim).opacity(contrast == .increased ? 1 : 0.72),
                           in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
