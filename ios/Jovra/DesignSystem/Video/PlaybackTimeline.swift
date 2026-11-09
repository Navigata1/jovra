import SwiftUI

/// The whole-clip timeline (user story 164): every moment of the video is reachable, whether or not anything
/// was recognised there. Tap or drag sideways to move. VoiceOver adjusts one frame at a time.
/// Event markers are drawn by the screens that own them.
struct PlaybackTimeline: View {
    var frame: Int
    var frameCount: Int
    var currentTimeText: String
    var durationText: String
    var onScrub: (Int) -> Void
    var onTap: (Int) -> Void
    var onScrubEnded: (Int) -> Void

    @State private var interaction = TimelineScrubInteraction()
    @GestureState private var dragInProgress = false

    private var progress: CGFloat {
        frameCount > 1 ? CGFloat(frame) / CGFloat(frameCount - 1) : 0
    }

    var body: some View {
        VStack(spacing: Space.half) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.jovra(.separator)).frame(height: 4)
                    Capsule().fill(Color.jovra(.textPrimary)).frame(width: max(4, width * progress), height: 4)
                    Circle()
                        .fill(Color.jovra(.accent))
                        .overlay(Circle().strokeBorder(Color.jovra(.textPrimary), lineWidth: 2))
                        .frame(width: 18, height: 18)
                        .offset(x: width * progress - 9)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(scrubGesture(width: width))
                .onChange(of: dragInProgress) { _, inProgress in
                    guard !inProgress else { return }
                    // Let a normal end deliver its release coordinate before handling cancellation.
                    Task { @MainActor in
                        guard !dragInProgress, let target = interaction.cancel() else { return }
                        onScrubEnded(target)
                    }
                }
            }
            .frame(height: HitTarget.minimum)
            .accessibilityElement()
            .accessibilityLabel(Text("Timeline", tableName: "DesignSystem.Video"))
            .accessibilityValue(Text("Frame \(JovraFormat.count(frame)), \(currentTimeText) of \(durationText)",
                                     tableName: "DesignSystem.Video",
                                     comment: "VoiceOver value of the timeline, e.g. “Frame 750, 0:12.50 of 0:54.00”"))
            .accessibilityHint(Text("Swipe up or down to move one frame.", tableName: "DesignSystem.Video"))
            .accessibilityAdjustableAction { direction in
                let increasing: Bool
                switch direction {
                case .increment: increasing = true
                case .decrement: increasing = false
                @unknown default: return
                }
                if let target = TimelineScrubInteraction.adjustedFrame(frame, increasing: increasing, frameCount: frameCount) {
                    onScrubEnded(target)
                }
            }
            .accessibilityIdentifier("playback.timeline")
            HStack {
                Text(verbatim: currentTimeText)
                Spacer(minLength: Space.x1)
                Text(verbatim: durationText)
            }
            .font(.jovraCaption.monospacedDigit())
            .foregroundStyle(.jovra(.textSecondary))
            .accessibilityHidden(true)
        }
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        let drag = DragGesture(minimumDistance: TimelineScrubInteraction.dragThreshold)
            .updating($dragInProgress) { _, inProgress, _ in inProgress = true }
            .onChanged { value in
                if let target = interaction.change(translation: value.translation, x: value.location.x,
                                                   width: width, frameCount: frameCount) {
                    onScrub(target)
                }
            }
            .onEnded { value in
                if let target = interaction.end(x: value.location.x, width: width, frameCount: frameCount) {
                    onScrubEnded(target)
                }
            }
        let tap = SpatialTapGesture().onEnded { value in
            if let target = TimelineScrubInteraction.frame(at: value.location.x, width: width, frameCount: frameCount) {
                onTap(target)
            }
        }
        return drag.exclusively(before: tap)
    }
}
