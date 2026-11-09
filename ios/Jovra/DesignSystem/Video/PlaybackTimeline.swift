import SwiftUI

/// The whole-clip timeline (user story 164): every moment of the video is reachable, whether or not anything
/// was recognised there. Tap or drag anywhere to move; VoiceOver adjusts it in `adjustStep` frames (one second
/// by default; screens with points pass one point). Event markers are drawn by the screens that own them.
struct PlaybackTimeline: View {
    var frame: Int
    var frameCount: Int
    var adjustStep: Int
    var currentTimeText: String
    var durationText: String
    var onScrub: (Int) -> Void
    var onScrubEnded: (Int) -> Void


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
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // A mostly vertical movement is someone scrolling the page, not scrubbing.
                        guard !Self.isVertical(value.translation) else { return }
                        onScrub(frameIndex(at: value.location.x, width: width))
                    }
                    .onEnded { value in
                        guard !Self.isVertical(value.translation) else { return }
                        onScrubEnded(frameIndex(at: value.location.x, width: width))
                    })
            }
            .frame(height: HitTarget.minimum)
            .accessibilityElement()
            .accessibilityLabel(Text("Timeline", tableName: "DesignSystem.Video"))
            .accessibilityValue(Text("\(currentTimeText) of \(durationText)", tableName: "DesignSystem.Video",
                                     comment: "VoiceOver value of the timeline, e.g. “0:12.50 of 0:54.00”"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onScrubEnded(clamp(frame + adjustStep))
                case .decrement: onScrubEnded(clamp(frame - adjustStep))
                @unknown default: break
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

    private func frameIndex(at x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        return clamp(Int((min(max(x / width, 0), 1) * CGFloat(frameCount - 1)).rounded()))
    }

    static func isVertical(_ translation: CGSize) -> Bool {
        abs(translation.height) > 10 && abs(translation.height) > abs(translation.width)
    }

    private func clamp(_ value: Int) -> Int { min(max(value, 0), max(frameCount - 1, 0)) }
}
