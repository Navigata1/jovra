import SwiftUI

/// The watch palette (watch spec "Layouts", brand-decision.md): dark forest background, ivory text, chartreuse for
/// the primary action and fresh counts, clay for attention. The values are the iOS `BrandPalette` hexes; the watch is
/// always dark. Every state also carries a word and a shape (`FreshnessMark`), so colour never carries meaning alone.
enum WatchPalette {
    /// Page background, top of the gradient.
    static let forest = Color(hex: 0x092A25)
    /// Page background, bottom of the gradient (darker, so the OLED edge falls away).
    static let forestDeep = Color(hex: 0x041613)
    /// Cards and rows.
    static let panel = Color(hex: 0x123C33)
    /// Pressed rows and secondary buttons.
    static let panelRaised = Color(hex: 0x1A4A40)
    static let ivory = Color(hex: 0xF4F1E8)
    /// Secondary text on forest (8.3:1 on `forest`, 6.6:1 on `panel`).
    static let ivorySecondary = Color(hex: 0xB4C2BB)
    /// Secondary text with Increase Contrast on.
    static let ivorySecondaryHighContrast = Color(hex: 0xD5DED9)
    /// Primary action fill and fresh counts.
    static let chartreuse = Color(hex: 0xD7F56A)
    /// Text on a chartreuse fill.
    static let onChartreuse = Color(hex: 0x092A25)
    /// Attention fills and rings (shapes, never small text).
    static let clay = Color(hex: 0xC47752)
    /// Attention text on forest (7.6:1 on `forest`, 6.0:1 on `panel`).
    static let clayInk = Color(hex: 0xEBA785)

    static let background = LinearGradient(colors: [forest, forestDeep], startPoint: .top, endPoint: .bottom)

    static func secondaryText(_ contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? ivorySecondaryHighContrast : ivorySecondary
    }
}

extension Color {
    /// An sRGB colour from a 0xRRGGBB literal.
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
