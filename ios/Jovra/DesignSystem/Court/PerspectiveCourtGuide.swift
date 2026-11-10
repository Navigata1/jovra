import JovraCore
import SwiftUI

/// The framing overlay (S05): four CornerHandles on the doubles corners over the video, and, once all four fix a
/// homography, the whole court model (singles and doubles sidelines, service lines, the centre service line only
/// between them, centre marks, net) projected through it in ivory at 70% so the player sees whether it matches.
/// Taps are converted to video pixels (`VideoFrameMapping`) before fitting; dragging shows a 2x loupe above the
/// finger. The background (the live preview or a recorded frame) is drawn aspect-fit by the caller.
struct PerspectiveCourtGuide<Background: View>: View {
    /// The video frame size in pixels, display-oriented.
    var videoSize: CGSize
    /// The four doubles corners in `CourtGeometry.doublesCorners` order, in video pixels.
    @Binding var corners: [VideoPixel]
    /// Where each bracket returns to ("Place at default", double tap).
    var defaults: [VideoPixel]
    var gravity: VideoGravity = .resizeAspect
    /// Shows the loupe on this corner without a touch (screenshots and previews only).
    var pinnedLoupe: Int?
    @ViewBuilder var background: () -> Background

    @State private var dragging: Int?
    @State private var dragStart: PlanePoint?
    @State private var touch: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var lineOpacity: Double { 0.7 }
    static var loupeDiameter: CGFloat { 112 }

    private var calibration: Homography? {
        guard corners.count == 4 else { return nil }
        return try? Homography.fit(image: corners, court: CourtGeometry.doublesCorners.map(\.point))
    }

    var body: some View {
        GeometryReader { proxy in
            let mapping = VideoFrameMapping(viewSize: PlaneSize(width: proxy.size.width, height: proxy.size.height),
                                            videoSize: PlaneSize(width: videoSize.width, height: videoSize.height), gravity: gravity)
            ZStack(alignment: .topLeading) {
                background().frame(width: proxy.size.width, height: proxy.size.height)
                if let calibration {
                    ProjectedCourt(homography: calibration, mapping: mapping)
                        .stroke(Color.jovra(.courtLine).opacity(Self.lineOpacity), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                ForEach(Array(CourtGeometry.doublesCorners.enumerated()), id: \.offset) { index, corner in
                    handle(index, corner: corner, mapping: mapping)
                }
                if let touch = touch ?? pinnedTouch(mapping) {
                    Loupe(center: touch, contentSize: proxy.size, diameter: Self.loupeDiameter) {
                        ZStack(alignment: .topLeading) {
                            background()
                            if let calibration {
                                ProjectedCourt(homography: calibration, mapping: mapping)
                                    .stroke(Color.jovra(.courtLine).opacity(Self.lineOpacity), lineWidth: 0.75)
                            }
                        }
                    }
                    .position(LoupePlacement.centre(touch: touch, in: proxy.size, diameter: Self.loupeDiameter))
                    .transition(Motion.transition(edge: .bottom, reduceMotion: reduceMotion))
                }
            }
            .jovraAnimation(.reveal, value: touch == nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Court corners", tableName: "DesignSystem.Court", comment: "VoiceOver name of the framing guide"))
    }

    private func handle(_ index: Int, corner: CourtIntersection, mapping: VideoFrameMapping) -> some View {
        let position = corners.indices.contains(index) ? corners[index] : defaults[index]
        let point = mapping.viewPoint(fromVideo: position)
        return CornerHandle(corner: corner, position: position, step: max(1, videoSize.height / 540), isActive: dragging == index,
                            move: { corners[index] = clamp($0) }, reset: { corners[index] = defaults[index] })
            .position(x: point.x, y: point.y)
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { value in
                        dragging = index
                        let start = dragStart ?? point
                        dragStart = start
                        let view = PlanePoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                        touch = CGPoint(x: view.x, y: view.y)
                        if let pixel = mapping.videoPixel(fromView: view) { corners[index] = pixel }
                    }
                    .onEnded { _ in
                        dragging = nil
                        dragStart = nil
                        touch = nil
                    }
            )
            .onTapGesture(count: 2) { corners[index] = defaults[index] }
    }

    private func pinnedTouch(_ mapping: VideoFrameMapping) -> CGPoint? {
        guard let pinnedLoupe, corners.indices.contains(pinnedLoupe) else { return nil }
        let p = mapping.viewPoint(fromVideo: corners[pinnedLoupe])
        return CGPoint(x: p.x, y: p.y)
    }

    private func clamp(_ pixel: VideoPixel) -> VideoPixel {
        VideoPixel(x: min(max(pixel.x, 0), videoSize.width), y: min(max(pixel.y, 0), videoSize.height))
    }
}

/// Every court line projected through a homography into view points. Each line is sampled so a line that crosses
/// the horizon is drawn only where it lies on the ground.
struct ProjectedCourt: Shape {
    var homography: Homography
    var mapping: VideoFrameMapping
    static let samples = 24

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for line in CourtGeometry.lines {
            var drawing = false
            for i in 0...Self.samples {
                let t = Double(i) / Double(Self.samples)
                let court = CourtPoint(x: line.from.x + (line.to.x - line.from.x) * t, y: line.from.y + (line.to.y - line.from.y) * t)
                guard let pixel = homography.project(court) else { drawing = false; continue }
                let view = mapping.viewPoint(fromVideo: pixel)
                let point = CGPoint(x: view.x, y: view.y)
                if drawing { path.addLine(to: point) } else { path.move(to: point) }
                drawing = true
            }
        }
        return path
    }
}
