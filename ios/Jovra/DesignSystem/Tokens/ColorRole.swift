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
/// stay consistent. Every text role is checked for 4.5:1 and every graphic role for 3:1 contrast in
/// `JovraTests` (ColorRoleContrastTests), in light, dark and Increase Contrast.
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
    // Video, court, markers, fills and charts (screens.md §5.3)
    /// REC dot and Stop disc (graphic).
    case recording
    /// The Stop glyph on `recording`.
    case onRecording
    /// Legibility gradient over video: black, 0→55% (opaque forest under Increase Contrast).
    case videoScrim
    /// Chips and panels over video: forest at 88% (opaque under Increase Contrast).
    case overlaySurface
    case courtSurface
    case courtLine
    /// In markers: a chartreuse filled circle with a forest outline.
    case markerIn
    case markerInOutline
    /// Out triangles (graphic only).
    case markerOut
    /// Positive InfoCard and safe-card background.
    case positiveFill
    /// Attention banners and the "Needs review" pill background.
    case attentionFill
    case chartLine
    /// Chartreuse at 22% under a chart line (decorative).
    case chartArea
    case chartGrid
    /// "Delete…" titles; the same ink as `attentionInk`.
    case destructiveInk

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
        case .recording: (hex("#D63A2E"), hex("#E5483B"))
        case .onRecording: (hex("#FFFFFF"), hex("#FFFFFF"))
        case .videoScrim: (hex("#000000"), hex("#000000"))
        case .overlaySurface: (BrandPalette.forest, BrandPalette.forest)
        case .courtSurface: (BrandPalette.forestPanel, BrandPalette.forestPanel)
        case .courtLine: (BrandPalette.ivory, BrandPalette.ivory)
        case .markerIn: (BrandPalette.chartreuse, BrandPalette.chartreuse)
        case .markerInOutline: (BrandPalette.forest, BrandPalette.forest)
        case .markerOut: (BrandPalette.clay, hex("#D98B66"))
        case .positiveFill: (hex("#E7EFD3"), hex("#1F4A3B"))
        case .attentionFill: (hex("#F6E3D8"), hex("#4A2E22"))
        case .chartLine: (BrandPalette.forest, BrandPalette.ivory)
        case .chartArea: (BrandPalette.chartreuse, BrandPalette.chartreuse)
        case .chartGrid: ColorRole.separator.values
        case .destructiveInk: ColorRole.attentionInk.values
        }
    }

    /// The role's opacity. Translucent roles become opaque under Increase Contrast, so text over
    /// video never depends on what the frame shows.
    func opacity(highContrast: Bool = false) -> Double {
        switch self {
        case .videoScrim: highContrast ? 1 : 0.55
        case .overlaySurface: highContrast ? 1 : 0.88
        case .chartArea: 0.22
        default: 1
        }
    }

    /// `color` drawn at this role's opacity over `backdrop` (source-over in sRGB, as the renderer
    /// composites), the colour a reader actually sees.
    func composite(_ color: SRGBColor, over backdrop: SRGBColor, highContrast: Bool = false) -> SRGBColor {
        let alpha = opacity(highContrast: highContrast)
        return SRGBColor(red: color.red * alpha + backdrop.red * (1 - alpha),
                         green: color.green * alpha + backdrop.green * (1 - alpha),
                         blue: color.blue * alpha + backdrop.blue * (1 - alpha))
    }

    /// Increase Contrast: secondary text and hairlines move toward the primary text colour.
    private func highContrastOverride(in appearance: Appearance) -> SRGBColor? {
        let light = appearance == .light
        switch self {
        case .textSecondary, .tabUnselected: return light ? hex("#333C38") : hex("#D5DED9")
        case .textSecondaryOnEditorial: return hex("#DCE4E0")
        case .separator, .chartGrid: return light ? hex("#9FA79F") : hex("#5C8379")
        // An opaque scrim is forest, so video chrome reads like an editorial panel.
        case .videoScrim: return BrandPalette.forest
        default: return nil
        }
    }

    private func hex(_ value: String) -> SRGBColor { SRGBColor(hex: value)! }
}
