import SwiftUI

/// Capsule buttons (a 26 pt continuous radius on a 52 pt button, so a label that wraps at large
/// text sizes gets a rounded rectangle rather than a blob). All are at least 44 pt tall; pressed state dims (and gently scales unless
/// Reduce Motion is on).
struct JovraButtonStyle: ButtonStyle {
    enum Kind {
        /// Chartreuse with forest text: the one main action on a screen or editorial card.
        case accent
        /// Forest (light) / ivory (dark) fill: primary actions on utility screens.
        case primary
        /// Outlined: secondary actions.
        case secondary
        /// Ivory outline and text, for secondary actions on forest (editorial cards, video chrome).
        case onForestSecondary
    }

    enum Size {
        /// 52 pt: screen-level actions.
        case regular
        /// 44 pt minimum: actions inside cards ("Save clip", "+ Import", "Review placements").
        case compact
    }

    var kind: Kind
    var fullWidth = false
    var size: Size = .regular

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size == .compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, size == .compact ? Space.x2 : Space.x3)
            .padding(.vertical, size == .compact ? Space.x1 : Space.x1 + Space.half)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size == .compact ? HitTarget.minimum : 52)
            .foregroundStyle(foreground)
            .background(background, in: shape)
            .overlay {
                if kind == .secondary {
                    shape.strokeBorder(Color.jovra(.textPrimary).opacity(0.55), lineWidth: 1.5)
                } else if kind == .onForestSecondary {
                    shape.strokeBorder(Color.jovra(.textOnEditorial).opacity(0.7), lineWidth: 1.5)
                }
            }
            .contentShape(shape)
            .opacity(isEnabled && configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(Motion.standard.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size == .compact ? HitTarget.minimum / 2 : 26, style: .continuous)
    }

    private var foreground: Color {
        if !isEnabled { return .jovra(kind == .onForestSecondary ? .textSecondaryOnEditorial : .textSecondary) }
        return switch kind {
        case .accent: .jovra(.onAccent)
        case .primary: .jovra(.onPrimaryFill)
        case .secondary: .jovra(.textPrimary)
        case .onForestSecondary: .jovra(.textOnEditorial)
        }
    }

    private var background: Color {
        if !isEnabled { return kind == .onForestSecondary ? .clear : .jovra(.surfaceSunken) }
        return switch kind {
        case .accent: .jovra(.accent)
        case .primary: .jovra(.primaryFill)
        case .secondary, .onForestSecondary: .clear
        }
    }
}

extension ButtonStyle where Self == JovraButtonStyle {
    static var jovraAccent: JovraButtonStyle { JovraButtonStyle(kind: .accent) }
    static var jovraPrimary: JovraButtonStyle { JovraButtonStyle(kind: .primary, fullWidth: true) }
    static var jovraSecondary: JovraButtonStyle { JovraButtonStyle(kind: .secondary, fullWidth: true) }
    static var jovraOnForestSecondary: JovraButtonStyle { JovraButtonStyle(kind: .onForestSecondary) }
    /// A 44 pt outlined action inside a card.
    static var jovraCompact: JovraButtonStyle { JovraButtonStyle(kind: .secondary, size: .compact) }
}
