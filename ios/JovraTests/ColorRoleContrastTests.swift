import JovraCore
import Testing
@testable import Jovra

/// The brand rules from design-reference/brief/brand-decision.md and the WCAG targets in
/// implementation-states.md, asserted against the shipped semantic colour roles in both appearances.
@Suite("Semantic colour contrast")
struct ColorRoleContrastTests {
    /// Every text role the design system renders, on every surface it is allowed to sit on.
    static let textPairs: [(text: ColorRole, surface: ColorRole)] = [
        (.textPrimary, .background), (.textPrimary, .surface), (.textPrimary, .surfaceSunken),
        (.textSecondary, .background), (.textSecondary, .surface), (.textSecondary, .surfaceSunken),
        (.textOnEditorial, .editorial), (.textSecondaryOnEditorial, .editorial),
        (.onAccent, .accent), (.onPrimaryFill, .primaryFill),
        (.accentInk, .background), (.accentInk, .surface),
        (.positiveInk, .surface), (.attentionInk, .surface), (.attentionInk, .background),
        (.tabSelected, .tabBarBackground), (.tabUnselected, .tabBarBackground),
    ]

    @Test("text roles meet 4.5:1 in light and dark", arguments: [Appearance.light, .dark])
    func textContrast(_ appearance: Appearance) {
        for pair in Self.textPairs {
            let ratio = pair.text.color(in: appearance).contrastRatio(with: pair.surface.color(in: appearance))
            #expect(ratio >= 4.5, "\(pair.text) on \(pair.surface) in \(appearance) is \(ratio):1")
        }
    }

    @Test("text roles still meet 4.5:1 with Increase Contrast", arguments: [Appearance.light, .dark])
    func highContrast(_ appearance: Appearance) {
        for pair in Self.textPairs {
            let text = pair.text.color(in: appearance, highContrast: true)
            let surface = pair.surface.color(in: appearance, highContrast: true)
            #expect(text.contrastRatio(with: surface) >= 4.5, "\(pair.text) on \(pair.surface)")
        }
    }

    @Test("Increase Contrast strengthens secondary text", arguments: [Appearance.light, .dark])
    func increasedContrastIsStronger(_ appearance: Appearance) {
        let background = ColorRole.background.color(in: appearance)
        let normal = ColorRole.textSecondary.color(in: appearance).contrastRatio(with: background)
        let high = ColorRole.textSecondary.color(in: appearance, highContrast: true).contrastRatio(with: background)
        #expect(high > normal)
    }

    @Test("chartreuse buttons always carry forest text")
    func chartreuseUsesForest() {
        for appearance in [Appearance.light, .dark] {
            #expect(ColorRole.accent.color(in: appearance) == BrandPalette.chartreuse)
            #expect(ColorRole.onAccent.color(in: appearance) == BrandPalette.forest)
        }
    }

    @Test("dark uses forest backgrounds with ivory text; light uses ivory with charcoal text")
    func appearanceFoundations() {
        #expect(ColorRole.background.color(in: .dark) == BrandPalette.forest)
        #expect(ColorRole.textPrimary.color(in: .dark) == BrandPalette.ivory)
        #expect(ColorRole.background.color(in: .light) == BrandPalette.ivory)
        #expect(ColorRole.textPrimary.color(in: .light) == BrandPalette.charcoal)
    }

    @Test("brand palette matches the brief's hex values")
    func brandHex() {
        #expect(BrandPalette.forest == SRGBColor(hex: "#092A25"))
        #expect(BrandPalette.forestPanel == SRGBColor(hex: "#123C33"))
        #expect(BrandPalette.ivory == SRGBColor(hex: "#F4F1E8"))
        #expect(BrandPalette.charcoal == SRGBColor(hex: "#182F29"))
        #expect(BrandPalette.chartreuse == SRGBColor(hex: "#D7F56A"))
        #expect(BrandPalette.clay == SRGBColor(hex: "#C47752"))
    }

    @Test("clay is too light for body text on ivory, so no text role may use it")
    func clayIsNeverText() {
        #expect(!ContrastRequirement.normalText.isMet(by: BrandPalette.clay, on: BrandPalette.ivory))
        for pair in Self.textPairs {
            #expect(pair.text.color(in: .light) != BrandPalette.clay)
        }
    }
}
