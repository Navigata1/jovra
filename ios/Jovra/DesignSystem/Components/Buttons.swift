import SwiftUI

/// Capsule buttons. All are at least 44 pt tall; pressed state dims (and gently scales unless
/// Reduce Motion is on).
struct JovraButtonStyle: ButtonStyle {
    enum Kind {
        /// Chartreuse with forest text: the one main action on a screen or editorial card.
        case accent
        /// Forest (light) / ivory (dark) fill: primary actions on utility screens.
        case primary
        /// Outlined: secondary actions.
        case secondary
    }

    var kind: Kind
    var fullWidth = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.x3)
            .padding(.vertical, Space.x1 + Space.half)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 52)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay {
                if kind == .secondary {
                    Capsule().strokeBorder(Color.jovra(.textPrimary).opacity(0.55), lineWidth: 1.5)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .accent: .jovra(.onAccent)
        case .primary: .jovra(.onPrimaryFill)
        case .secondary: .jovra(.textPrimary)
        }
    }

    private var background: Color {
        switch kind {
        case .accent: .jovra(.accent)
        case .primary: .jovra(.primaryFill)
        case .secondary: .clear
        }
    }
}

extension ButtonStyle where Self == JovraButtonStyle {
    static var jovraAccent: JovraButtonStyle { JovraButtonStyle(kind: .accent) }
    static var jovraPrimary: JovraButtonStyle { JovraButtonStyle(kind: .primary, fullWidth: true) }
    static var jovraSecondary: JovraButtonStyle { JovraButtonStyle(kind: .secondary, fullWidth: true) }
}
