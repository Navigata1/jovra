import JovraCore

/// The six brand colours from design-reference/brief/brand-decision.md.
enum BrandPalette {
    static let forest = SRGBColor(hex: "#092A25")!
    static let forestPanel = SRGBColor(hex: "#123C33")!
    static let ivory = SRGBColor(hex: "#F4F1E8")!
    static let charcoal = SRGBColor(hex: "#182F29")!
    static let chartreuse = SRGBColor(hex: "#D7F56A")!
    /// A flag/decorative accent. Never body text on ivory (3.0:1).
    static let clay = SRGBColor(hex: "#C47752")!
}

enum Appearance: String, Sendable, CaseIterable, CustomStringConvertible {
    case light
    case dark

    var description: String { rawValue }
}

/// Semantic colour roles. Views use roles, never raw hex, so light, dark and Increase Contrast
/// stay consistent. Every text role is checked for 4.5:1 contrast in `JovraTests`.
enum ColorRole: String, CaseIterable, Sendable, CustomStringConvertible {
    // Surfaces
    case background
    case surface
    case surfaceSunken
    case editorial
    case separator
    case tabBarBackground
    // Text and icons
    case textPrimary
    case textSecondary
    case textOnEditorial
    case textSecondaryOnEditorial
    case accentInk
    case positiveInk
    case attentionInk
    case tabSelected
    case tabUnselected
    // Brand and controls
    case brandMark
    case accent
    case onAccent
    case primaryFill
    case onPrimaryFill
    case clay

    var description: String { rawValue }

    func color(in appearance: Appearance, highContrast: Bool = false) -> SRGBColor {
        if highContrast, let strong = highContrastOverride(in: appearance) { return strong }
        let (light, dark) = values
        return appearance == .light ? light : dark
    }

    private var values: (light: SRGBColor, dark: SRGBColor) {
        switch self {
        case .background: (BrandPalette.ivory, BrandPalette.forest)
        case .surface: (hex("#FBFAF6"), BrandPalette.forestPanel)
        case .surfaceSunken: (hex("#EAE6DA"), hex("#1A4A40"))
        case .editorial: (BrandPalette.forest, BrandPalette.forestPanel)
        case .separator: (hex("#DCD7CA"), hex("#25544A"))
        case .tabBarBackground: (hex("#FBFAF6"), hex("#0D312B"))
        case .textPrimary: (BrandPalette.charcoal, BrandPalette.ivory)
        case .textSecondary: (hex("#4D5853"), hex("#B4C2BB"))
        case .textOnEditorial: (BrandPalette.ivory, BrandPalette.ivory)
        case .textSecondaryOnEditorial: (hex("#BAC8C1"), hex("#BAC8C1"))
        case .accentInk: (hex("#4C6610"), BrandPalette.chartreuse)
        case .positiveInk: (hex("#2E6A2E"), hex("#BFE77A"))
        case .attentionInk: (hex("#9A4524"), hex("#EBA785"))
        case .tabSelected: (BrandPalette.forest, BrandPalette.ivory)
        case .tabUnselected: (hex("#4D5853"), hex("#B4C2BB"))
        case .brandMark: (BrandPalette.forest, BrandPalette.ivory)
        case .accent: (BrandPalette.chartreuse, BrandPalette.chartreuse)
        case .onAccent: (BrandPalette.forest, BrandPalette.forest)
        case .primaryFill: (BrandPalette.forest, BrandPalette.ivory)
        case .onPrimaryFill: (BrandPalette.ivory, BrandPalette.forest)
        case .clay: (BrandPalette.clay, BrandPalette.clay)
        }
    }

    /// Increase Contrast: secondary text and hairlines move toward the primary text colour.
    private func highContrastOverride(in appearance: Appearance) -> SRGBColor? {
        let light = appearance == .light
        switch self {
        case .textSecondary, .tabUnselected: return light ? hex("#333C38") : hex("#D5DED9")
        case .textSecondaryOnEditorial: return hex("#DCE4E0")
        case .separator: return light ? hex("#9FA79F") : hex("#5C8379")
        default: return nil
        }
    }

    private func hex(_ value: String) -> SRGBColor { SRGBColor(hex: value)! }
}
