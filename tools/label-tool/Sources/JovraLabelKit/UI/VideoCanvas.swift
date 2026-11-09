import AppKit
import AVFoundation
import JovraBenchmark
import SwiftUI

/// The frame on screen with the labels that belong to it drawn on top. The picture and the marks are plain
/// SwiftUI; a transparent AppKit view the exact size of the picture tells the window where the picture is.
struct VideoCanvas: View {
    @Environment(\.colorScheme) private var scheme
    let session: LabelSession

    var body: some View {
        GeometryReader { proxy in
            let size = pictureSize
            let fitted = AVMakeRect(aspectRatio: size, insideRect: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                Color.black
                if let frame = session.frame {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: fitted.width, height: fitted.height)
                        .offset(x: fitted.minX, y: fitted.minY)
                    MarksOverlay(session: session)
                        .frame(width: fitted.width, height: fitted.height)
                        .offset(x: fitted.minX, y: fitted.minY)
                        .allowsHitTesting(false)
                }
                if let prompt = placementPrompt {
                    Text(prompt)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(Color.black)
                        .background(Palette.markBounce, in: Capsule())
                        .padding(12)
                        // At the bottom, clear of the label burned into sample video and of the frame's badges.
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("placement-prompt")
                }
                if session.frame != nil {
                    PointerCatcher(session: session)
                        .frame(width: fitted.width, height: fitted.height)
                        .offset(x: fitted.minX, y: fitted.minY)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording frame at \(session.displayedTime.clock)")
    }

    private var pictureSize: CGSize {
        if let recording = session.labels?.recording { return CGSize(width: recording.width, height: recording.height) }
        return CGSize(width: 16, height: 9)
    }

    private var placementPrompt: String? {
        switch session.placement {
        case .bounce: "Click where the ball touches the ground"
        case .corner: "Click the \(LabelSession.cornerName(session.document?.nextCorner ?? 0)) corner"
        case nil: nil
        }
    }
}

/// Bounces near this frame, the court corners in force and the hits on this frame.
private struct MarksOverlay: View {
    let session: LabelSession

    var body: some View {
        // Read here, in `body`, so the canvas redraws when the document or the frame changes.
        let current = session.document
        let now = session.displayedTime
        return Canvas { context, size in
            guard let document = current else { return }
            func place(_ point: ImagePoint) -> CGPoint { CGPoint(x: point.x * size.width, y: point.y * size.height) }

            if let position = document.cameraPosition(at: now) {
                let points = position.corners.points
                var outline = Path()
                var started = false
                for point in points + [points.first ?? nil] {
                    guard let point else { started = false; continue }
                    if started { outline.addLine(to: place(point)) } else { outline.move(to: place(point)); started = true }
                }
                context.stroke(outline, with: .color(Palette.markCourt.opacity(0.85)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                for (index, point) in points.enumerated() {
                    guard let point else { continue }
                    let centre = place(point)
                    let box = CGRect(x: centre.x - 5, y: centre.y - 5, width: 10, height: 10)
                    context.stroke(Path(box), with: .color(.black.opacity(0.7)), lineWidth: 3)
                    context.stroke(Path(box), with: .color(Palette.markCourt), lineWidth: 1.5)
                    let label = Text(["FL", "FR", "NR", "NL"][index]).font(.system(size: 10, weight: .bold)).foregroundColor(Palette.markCourt)
                    context.draw(label, at: CGPoint(x: centre.x, y: centre.y - 14))
                }
            }
            for bounce in document.labels.bounces where abs(bounce.time.seconds - now.seconds) <= 0.5 {
                let centre = place(bounce.imagePoint), onFrame = bounce.time == now
                let radius: CGFloat = onFrame ? 9 : 6
                let ring = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
                context.stroke(ring, with: .color(.black.opacity(0.7)), lineWidth: 4)
                context.stroke(ring, with: .color(Palette.markBounce.opacity(onFrame ? 1 : 0.6)),
                               style: StrokeStyle(lineWidth: 2, dash: bounce.inPlay ? [] : [3, 3]))
                if onFrame {
                    var cross = Path()
                    cross.move(to: CGPoint(x: centre.x - 3, y: centre.y)); cross.addLine(to: CGPoint(x: centre.x + 3, y: centre.y))
                    cross.move(to: CGPoint(x: centre.x, y: centre.y - 3)); cross.addLine(to: CGPoint(x: centre.x, y: centre.y + 3))
                    context.stroke(cross, with: .color(Palette.markBounce), lineWidth: 1.5)
                }
            }
        }
        .overlay(alignment: .topTrailing) { frameBadges }
    }

    @ViewBuilder private var frameBadges: some View {
        if let document = session.document {
            let now = session.displayedTime
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(document.labels.hits.filter { $0.time == now }, id: \.self) { hit in
                    badge("Hit · \(hit.player.rawValue) player" + (hit.stroke.map { " · \($0.rawValue)" } ?? ""),
                          colour: hit.player == .near ? Palette.markNear : Palette.markFar)
                }
                if let bounce = document.labels.bounces.first(where: { $0.time == now }) {
                    badge(bounce.inPlay ? "Bounce · in play" : "Bounce · dead ball", colour: Palette.markBounce)
                }
                if document.pendingCandidate(near: now) != nil {
                    badge("Hit candidate · H or J confirms, R rejects", colour: .white)
                }
            }
            .padding(12)
        }
    }

    private func badge(_ text: String, colour: Color) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(Color.black)
            .background(colour, in: Capsule())
    }
}

/// Marks where the picture is. It draws nothing and handles nothing itself: `LabelWindow` reads its frame to
/// turn clicks and pointer moves over the picture into normalized image points, the same way it routes keys,
/// so a click on the picture can never be swallowed by whatever SwiftUI lays out around it.
struct PointerCatcher: NSViewRepresentable {
    let session: LabelSession

    func makeNSView(context: Context) -> PointerCatcherView {
        PointerCatcherView()
    }

    func updateNSView(_ view: PointerCatcherView, context: Context) {}
}

final class PointerCatcherView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    /// The normalized image point under a window location, or nil when it is outside the picture.
    func imagePoint(atWindowLocation location: NSPoint) -> ImagePoint? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let local = convert(location, from: nil)
        guard bounds.contains(local) else { return nil }
        return ImagePoint(x: local.x / bounds.width, y: local.y / bounds.height).normalized
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}
