import SwiftUI

/// The tool's colours, from the JOVRA palette (forest, ivory, chartreuse, clay), for light and dark.
/// Meaning never rests on colour alone: every state also has words or a shape.
struct Palette {
    let background: Color
    let panel: Color
    let raised: Color
    let line: Color
    let text: Color
    let secondary: Color
    let accent: Color
    let onAccent: Color
    let warning: Color
    let danger: Color
    let heldOut: Color

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            background = Color(hex: 0x092A25)
            panel = Color(hex: 0x0E332C)
            raised = Color(hex: 0x123C33)
            line = Color(hex: 0xF4F1E8).opacity(0.14)
            text = Color(hex: 0xF4F1E8)
            secondary = Color(hex: 0xF4F1E8).opacity(0.72)
            accent = Color(hex: 0xD7F56A)
            onAccent = Color(hex: 0x092A25)
            warning = Color(hex: 0xE9A27F)
            danger = Color(hex: 0xFFB4A2)
            heldOut = Color(hex: 0xC47752)
        } else {
            background = Color(hex: 0xF4F1E8)
            panel = Color(hex: 0xFBFAF5)
            raised = Color(hex: 0xECE8DB)
            line = Color(hex: 0x182F29).opacity(0.16)
            text = Color(hex: 0x182F29)
            secondary = Color(hex: 0x182F29).opacity(0.74)
            accent = Color(hex: 0x123C33)
            onAccent = Color(hex: 0xF4F1E8)
            warning = Color(hex: 0x8A4424)
            danger = Color(hex: 0x9C2B16)
            heldOut = Color(hex: 0xA5552F)
        }
    }

    // Marks drawn on the picture sit on video, so they keep one high-contrast set in both appearances.
    static let markNear = Color(hex: 0xD7F56A)
    static let markFar = Color(hex: 0x7FD6FF)
    static let markBounce = Color(hex: 0xFFD166)
    static let markCourt = Color(hex: 0xFFFFFF)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

enum Metrics {
    static let sidebarWidth: CGFloat = 332
    static let gutter: CGFloat = 16
    static let corner: CGFloat = 10
}

/// A small capsule that states one fact ("VFR", "Unsaved changes").
struct Chip: View {
    @Environment(\.colorScheme) private var scheme
    let text: String
    var systemImage: String?
    var emphasised = false

    var body: some View {
        let palette = Palette(scheme)
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(emphasised ? palette.onAccent : palette.text)
        .background(emphasised ? palette.accent : palette.raised, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A key cap, as printed in the legend.
struct KeyCap: View {
    @Environment(\.colorScheme) private var scheme
    let text: String

    var body: some View {
        let palette = Palette(scheme)
        Text(text)
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .padding(.horizontal, 7)
            .frame(minWidth: 30, minHeight: 24)
            .foregroundStyle(palette.text)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(palette.line))
    }
}

/// The one filled button of a screen, in the palette's accent whatever the window's key state.
struct ProminentButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let palette = Palette(scheme)
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .foregroundStyle(palette.onAccent)
            .background(palette.accent.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}
