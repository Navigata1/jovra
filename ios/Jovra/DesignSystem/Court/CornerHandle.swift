import JovraCore
import SwiftUI

/// A chartreuse corner bracket on a court corner (S05): a 44 pt target whose arms point into the court. VoiceOver
/// treats it as an adjustable element: swipe up or down to move it vertically, the Actions rotor moves it left or
/// right or puts it back at its default. Positions are video pixels; the guide places the bracket in the view.
struct CornerHandle: View {
    var corner: CourtIntersection
    /// Where the bracket sits, in video pixels (what the fit uses).
    var position: VideoPixel
    /// One accessibility step, in video pixels.
    var step: Double
    var isActive = false
    var move: (VideoPixel) -> Void
    var reset: () -> Void

    static let armLength: CGFloat = 18
    static let armWidth: CGFloat = 4

    var body: some View {
        BracketShape(corner: corner)
            .stroke(Color.jovra(.accent), style: StrokeStyle(lineWidth: Self.armWidth, lineCap: .square))
            .frame(width: Self.armLength, height: Self.armLength)
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
            .scaleEffect(isActive ? 1.15 : 1)
            .frame(width: HitTarget.minimum, height: HitTarget.minimum)
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(Text(corner.bracketName))
            .accessibilityValue(Text(String(format: String(localized: "x %1$d, y %2$d", table: "DesignSystem.Court",
                                                           comment: "A corner bracket's position in video pixels, read by VoiceOver"),
                                            Int(position.x.rounded()), Int(position.y.rounded()))))
            .accessibilityHint(Text("Swipe up or down to move it vertically. Use the actions rotor to move it left or right.",
                                    tableName: "DesignSystem.Court", comment: "VoiceOver hint on a court corner bracket"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(VideoPixel(x: position.x, y: position.y - step))
                case .decrement: move(VideoPixel(x: position.x, y: position.y + step))
                @unknown default: break
                }
            }
            .accessibilityAction(named: Text("Move left", tableName: "DesignSystem.Court", comment: "VoiceOver action on a corner bracket")) {
                move(VideoPixel(x: position.x - step, y: position.y))
            }
            .accessibilityAction(named: Text("Move right", tableName: "DesignSystem.Court", comment: "VoiceOver action on a corner bracket")) {
                move(VideoPixel(x: position.x + step, y: position.y))
            }
            .accessibilityAction(named: Text("Place at default", tableName: "DesignSystem.Court",
                                             comment: "VoiceOver action that puts a corner bracket back where it started")) { reset() }
            .accessibilityIdentifier("court.corner.\(corner.rawValue)")
    }
}

/// An L-shaped bracket whose arms run along the court's two edges from the corner (into the court).
struct BracketShape: Shape {
    var corner: CourtIntersection

    func path(in rect: CGRect) -> Path {
        // Near corners sit at the bottom of the frame (arms go up), far corners at the top (arms go down);
        // left corners open to the right, right corners to the left.
        let near = corner == .nearLeftDoubles || corner == .nearRightDoubles || corner == .nearLeftSingles || corner == .nearRightSingles
        let left = corner == .nearLeftDoubles || corner == .farLeftDoubles || corner == .nearLeftSingles || corner == .farLeftSingles
        let x = left ? rect.minX : rect.maxX, y = near ? rect.maxY : rect.minY
        var p = Path()
        p.move(to: CGPoint(x: x, y: near ? rect.minY : rect.maxY))
        p.addLine(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: left ? rect.maxX : rect.minX, y: y))
        return p
    }
}

/// The 2x magnifier shown above the finger while a bracket is dragged, so the player can see the corner the finger
/// covers. It redraws the content under the touch point at twice the size, with a crosshair on the point.
struct Loupe<Content: View>: View {
    /// The touch point in the content's coordinates.
    var center: CGPoint
    /// The size the content is drawn at.
    var contentSize: CGSize
    var diameter: CGFloat = 112
    @ViewBuilder var content: () -> Content

    static var magnification: CGFloat { 2 }

    var body: some View {
        let m = Self.magnification
        content()
            .frame(width: contentSize.width, height: contentSize.height)
            .scaleEffect(m, anchor: .topLeading)
            .offset(x: diameter / 2 - center.x * m, y: diameter / 2 - center.y * m)
            .frame(width: diameter, height: diameter, alignment: .topLeading)
            .clipShape(Circle())
            .overlay {
                ZStack {
                    Rectangle().fill(Color.jovra(.accent)).frame(width: 1.5, height: 18)
                    Rectangle().fill(Color.jovra(.accent)).frame(width: 18, height: 1.5)
                }
            }
            .overlay(Circle().strokeBorder(Color.jovra(.accent), lineWidth: 3))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Where the loupe goes for a touch: 96 pt above the finger when the whole circle fits there, otherwise beside the
/// finger towards the middle of the frame (never below it, where the hand is). It always stays inside the frame it
/// magnifies, so a far corner near the top edge is still shown whole.
enum LoupePlacement {
    /// Centre-to-finger distance: clear of a fingertip and of the 44 pt bracket target.
    static let lift: CGFloat = 96

    static func centre(touch: CGPoint, in container: CGSize, diameter: CGFloat) -> CGPoint {
        let radius = diameter / 2
        func inside(_ value: CGFloat, _ extent: CGFloat) -> CGFloat {
            extent < diameter ? extent / 2 : min(max(value, radius), extent - radius)
        }
        if touch.y - lift >= radius || container.width < diameter {
            return CGPoint(x: inside(touch.x, container.width), y: inside(touch.y - lift, container.height))
        }
        let towardsMiddle: CGFloat = touch.x > container.width / 2 ? -lift : lift
        return CGPoint(x: inside(touch.x + towardsMiddle, container.width), y: inside(touch.y, container.height))
    }
}

extension CourtIntersection {
    /// "Near left corner bracket", the VoiceOver name of a corner handle (S05).
    var bracketName: String {
        switch self {
        case .nearLeftDoubles, .nearLeftSingles:
            String(localized: "Near left corner bracket", table: "DesignSystem.Court", comment: "VoiceOver name of a court corner handle")
        case .nearRightDoubles, .nearRightSingles:
            String(localized: "Near right corner bracket", table: "DesignSystem.Court", comment: "VoiceOver name of a court corner handle")
        case .farRightDoubles, .farRightSingles:
            String(localized: "Far right corner bracket", table: "DesignSystem.Court", comment: "VoiceOver name of a court corner handle")
        default:
            String(localized: "Far left corner bracket", table: "DesignSystem.Court", comment: "VoiceOver name of a court corner handle")
        }
    }
}
