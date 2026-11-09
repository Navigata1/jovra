import SwiftUI

/// The accessible alternative to pinch zoom: zoom out, the level, zoom in. It moves through `VideoZoom.levels`
/// (100% to 400%, the same range a pinch covers) and is one adjustable element for VoiceOver.
struct ZoomControl: View {
    @Binding var zoom: VideoZoom
    /// The surface size the pan limits are computed against.
    var surfaceSize: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            stepButton(up: false)
            Text(verbatim: JovraFormat.percent(zoom.percent))
                .font(.jovraLabel.monospacedDigit())
                .foregroundStyle(.jovra(.textPrimary))
                .frame(minWidth: 56, minHeight: HitTarget.minimum)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Zoom", tableName: "DesignSystem.Video"))
                .accessibilityValue(Text(verbatim: JovraFormat.percent(zoom.percent)))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: change(up: true)
                    case .decrement: change(up: false)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier("video.zoom")
            stepButton(up: true)
        }
        .padding(.horizontal, Space.half)
        .background(Color.jovra(.surfaceSunken), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.jovra(.separator), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func stepButton(up: Bool) -> some View {
        Button { change(up: up) } label: {
            Label {
                if up { Text("Zoom in", tableName: "DesignSystem.Video") } else { Text("Zoom out", tableName: "DesignSystem.Video") }
            } icon: {
                Image(systemName: up ? "plus.magnifyingglass" : "minus.magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(.jovra(.textPrimary))
            .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(up ? !zoom.canZoomIn : !zoom.canZoomOut)
        .accessibilityIdentifier(up ? "video.zoom.in" : "video.zoom.out")
    }

    private func change(up: Bool) {
        withAnimation(Motion.standard.animation(reduceMotion: reduceMotion)) {
            zoom.step(up: up, in: surfaceSize)
        }
    }
}
