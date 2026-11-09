import SwiftUI

/// The frame-quantized scrubber (user stories 154, 355). A ruler of frame ticks slides under a fixed needle:
/// drag left to move forward, right to move back; drag down while scrubbing for single-frame precision.
/// It is at least 48 pt tall, sits above the transport row and away from the bottom edge, defers system edge
/// gestures, and is one adjustable accessibility element that moves exactly one frame per swipe.
struct JogStrip: View {
    var frame: Int
    var frameCount: Int
    /// Frames per second, rounded, for the per-second ticks.
    var framesPerSecond: Int
    /// Spoken with the frame number ("Frame 46,000, 12:46.67").
    var timeText: String
    /// A drag position (chase-seek coarsely).
    var onScrub: (Int) -> Void
    /// The finger lifted on this frame (seek exactly).
    var onScrubEnded: (Int) -> Void
    /// One frame forward (+1) or back (−1): each VoiceOver increment or decrement.
    var onStep: (Int) -> Void

    static let pointsPerFrame: CGFloat = 8
    static let precisionPointsPerFrame: CGFloat = 24
    /// How far down the finger must move to enter precision mode.
    static let precisionDrop: CGFloat = 28

    @State private var dragStart: Int?
    @State private var precision = false
    @State private var lastTranslation: CGFloat = 0
    @State private var anchorFrame: Int = 0

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(maxWidth: .infinity, minHeight: VideoMetrics.jogStripHeight, maxHeight: VideoMetrics.jogStripHeight)
        .background(Color.jovra(.surfaceSunken), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Color.jovra(precision ? .textPrimary : .separator), lineWidth: precision ? 2 : 1)
        }
        .contentShape(Rectangle())
        .gesture(drag)
        .defersSystemGestures(on: .all)
        .accessibilityElement()
        .accessibilityLabel(Text("Jog strip", tableName: "DesignSystem.Video"))
        .accessibilityValue(Text("Frame \(JovraFormat.count(frame)), \(timeText)", tableName: "DesignSystem.Video",
                                 comment: "VoiceOver value of the jog strip, e.g. “Frame 46,000, 12:46.67”"))
        .accessibilityHint(Text("Swipe up or down to move one frame.", tableName: "DesignSystem.Video"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onStep(1)
            case .decrement: onStep(-1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("playback.jog")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                // Scrubbing starts with a sideways movement; a vertical swipe is the page scrolling.
                if dragStart == nil, abs(value.translation.height) > abs(value.translation.width) { return }
                if dragStart == nil {
                    dragStart = frame
                    anchorFrame = frame
                    lastTranslation = value.translation.width
                }
                let nowPrecise = value.translation.height > Self.precisionDrop
                if nowPrecise != precision {
                    // Re-anchor so switching modes never jumps the playhead.
                    anchorFrame = frame
                    lastTranslation = value.translation.width
                    precision = nowPrecise
                }
                let perFrame = precision ? Self.precisionPointsPerFrame : Self.pointsPerFrame
                let delta = Int(((lastTranslation - value.translation.width) / perFrame).rounded())
                let target = clamp(anchorFrame + delta)
                if target != frame { onScrub(target) }
            }
            .onEnded { value in
                guard dragStart != nil else { return }
                let perFrame = precision ? Self.precisionPointsPerFrame : Self.pointsPerFrame
                let delta = Int(((lastTranslation - value.translation.width) / perFrame).rounded())
                onScrubEnded(clamp(anchorFrame + delta))
                dragStart = nil
                precision = false
            }
    }

    private func clamp(_ value: Int) -> Int { min(max(value, 0), max(frameCount - 1, 0)) }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let perFrame = precision ? Self.precisionPointsPerFrame : Self.pointsPerFrame
        let centre = size.width / 2
        let visible = Int(size.width / perFrame / 2) + 2
        let tickColor = Color.jovra(.textSecondary)
        for offset in -visible...visible {
            let index = frame + offset
            guard index >= 0, index < frameCount else { continue }
            let x = centre + CGFloat(offset) * perFrame
            let isSecond = framesPerSecond > 0 && index % framesPerSecond == 0
            let isTen = index % 10 == 0
            let height: CGFloat = isSecond ? size.height * 0.62 : (isTen ? size.height * 0.42 : size.height * 0.24)
            var path = Path()
            path.move(to: CGPoint(x: x, y: (size.height - height) / 2))
            path.addLine(to: CGPoint(x: x, y: (size.height + height) / 2))
            context.stroke(path, with: .color(tickColor.opacity(isSecond || isTen ? 0.9 : 0.5)), lineWidth: isSecond ? 2 : 1)
        }
        // The needle: forest/ivory ink with an accent cap, so it reads in both appearances.
        var needle = Path()
        needle.move(to: CGPoint(x: centre, y: 4))
        needle.addLine(to: CGPoint(x: centre, y: size.height - 4))
        context.stroke(needle, with: .color(.jovra(.textPrimary)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        let cap = Path(ellipseIn: CGRect(x: centre - 5, y: 1, width: 10, height: 10))
        context.fill(cap, with: .color(.jovra(.accent)))
        context.stroke(cap, with: .color(.jovra(.textPrimary)), lineWidth: 1.5)
    }
}
