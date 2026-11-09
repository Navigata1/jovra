import JovraCore
import Testing
@testable import Jovra

/// The brand rules from design-reference/brief/brand-decision.md and the WCAG targets in
/// implementation-states.md, asserted against the shipped semantic colour roles in light, dark and
/// Increase Contrast (screens.md §5.3: every text role ≥4.5:1, every graphic role ≥3:1).
@Suite("Semantic colour contrast")
struct ColorRoleContrastTests {
    /// What sits under a pair's background when the background is translucent.
    enum Backdrop {
        /// The background role is opaque, or sits on the page background.
        case page
        /// Video chrome: the worst case is a white video frame under the 55% scrim. Video chrome is
        /// always drawn forest (screens.md §0.5), so these pairs resolve in the dark appearance.
        case videoUnderScrim
    }

    struct Pair: CustomStringConvertible {
        var foreground: ColorRole
        var background: ColorRole
        var requirement: ContrastRequirement
        var backdrop: Backdrop = .page
        var description: String { "\(foreground) on \(background)" }
    }

    /// Every text role the design system renders, on every surface it is allowed to sit on.
    static func pairs(_ list: [(ColorRole, ColorRole)], _ requirement: ContrastRequirement) -> [Pair] {
        list.map { Pair(foreground: $0.0, background: $0.1, requirement: requirement) }
    }

    static let textPairs: [Pair] = pairs([
        (.textPrimary, .background), (.textPrimary, .surface), (.textPrimary, .surfaceSunken),
        (.textSecondary, .background), (.textSecondary, .surface), (.textSecondary, .surfaceSunken),
        (.textOnEditorial, .editorial), (.textSecondaryOnEditorial, .editorial),
        (.onAccent, .accent), (.onPrimaryFill, .primaryFill),
        (.accentInk, .background), (.accentInk, .surface),
        (.positiveInk, .surface), (.attentionInk, .surface), (.attentionInk, .background),
        (.tabSelected, .tabBarBackground), (.tabUnselected, .tabBarBackground),
        // §5.3 additions: tinted banners and cards, destructive titles.
        (.textPrimary, .positiveFill), (.textSecondary, .positiveFill), (.positiveInk, .positiveFill),
        (.textPrimary, .attentionFill), (.textSecondary, .attentionFill), (.attentionInk, .attentionFill),
        (.destructiveInk, .surface), (.destructiveInk, .background),
    ], .normalText) + [
        // Chips and panels over video.
        Pair(foreground: .textOnEditorial, background: .overlaySurface, requirement: .normalText, backdrop: .videoUnderScrim),
        Pair(foreground: .textSecondaryOnEditorial, background: .overlaySurface, requirement: .normalText, backdrop: .videoUnderScrim),
    ]

    /// Every graphic role that carries meaning (markers, the REC dot, chart lines), on its background.
    static let graphicPairs: [Pair] = pairs([
        (.recording, .background), (.recording, .surface), (.recording, .editorial), (.onRecording, .recording),
        (.courtLine, .courtSurface), (.markerIn, .courtSurface), (.markerInOutline, .markerIn),
        (.markerOut, .courtSurface), (.chartLine, .surface), (.chartLine, .background),
    ], .nonText) + [
        Pair(foreground: .recording, background: .overlaySurface, requirement: .nonText, backdrop: .videoUnderScrim),
    ]

    /// Roles that are surfaces or carry no meaning on their own. A new role must be classified here
    /// or appear as a foreground in a pair above, so no role escapes the contrast gate.
    static func isSurfaceOrDecorative(_ role: ColorRole) -> Bool {
        switch role {
        case .background, .surface, .surfaceSunken, .editorial, .separator, .tabBarBackground,
             .accent, .primaryFill, .videoScrim, .overlaySurface, .courtSurface,
             .positiveFill, .attentionFill, .chartArea, .chartGrid:
            true
        // Brand-only: the mark is checked against the brand board, clay never carries meaning.
        case .brandMark, .clay:
            true
        case .textPrimary, .textSecondary, .textOnEditorial, .textSecondaryOnEditorial, .accentInk,
             .positiveInk, .attentionInk, .tabSelected, .tabUnselected, .onAccent, .onPrimaryFill,
             .recording, .onRecording, .courtLine, .markerIn, .markerInOutline, .markerOut, .chartLine,
             .destructiveInk:
            false
        }
    }

    typealias Resolver = @Sendable (ColorRole, Appearance, Bool) -> SRGBColor

    /// The colours the app shows: each role composited over what is underneath it.
    static let shipped: Resolver = { role, appearance, highContrast in
        role.color(in: appearance, highContrast: highContrast)
    }

    /// Pairs below their requirement, as readable strings; empty when all pass.
    static func failures(_ pairs: [Pair], appearance: Appearance, highContrast: Bool,
                         resolve: Resolver = shipped) -> [String] {
        pairs.compactMap { pair in
            let appearance = pair.backdrop == .videoUnderScrim ? .dark : appearance
            let backdrop: SRGBColor = switch pair.backdrop {
            case .page: resolve(.background, appearance, highContrast)
            case .videoUnderScrim:
                ColorRole.videoScrim.composite(resolve(.videoScrim, appearance, highContrast),
                                               over: SRGBColor(red: 1, green: 1, blue: 1), highContrast: highContrast)
            }
            let background = pair.background.composite(resolve(pair.background, appearance, highContrast),
                                                        over: backdrop, highContrast: highContrast)
            let foreground = pair.foreground.composite(resolve(pair.foreground, appearance, highContrast),
                                                       over: background, highContrast: highContrast)
            let ratio = foreground.contrastRatio(with: background)
            guard ratio < pair.requirement.minimumRatio else { return nil }
            return "\(pair) in \(appearance)\(highContrast ? " (Increase Contrast)" : ""): \(ratio):1 < \(pair.requirement.minimumRatio):1"
        }
    }

    @Test("text roles meet 4.5:1 and graphic roles 3:1 in light, dark and Increase Contrast",
          arguments: [Appearance.light, .dark], [false, true])
    func everyPairMeetsItsRequirement(_ appearance: Appearance, highContrast: Bool) {
        let failed = Self.failures(Self.textPairs + Self.graphicPairs, appearance: appearance, highContrast: highContrast)
        #expect(failed.isEmpty, "\(failed)")
    }

    @Test("a seeded low-contrast value fails the gate")
    func seededLowContrastFails() {
        // The Increase Contrast hairline grey is a separator, not a text colour; seeding it as
        // secondary text must be caught (about 2.4:1 on ivory).
        let seeded: Resolver = { role, appearance, highContrast in
            role == .textSecondary ? SRGBColor(hex: "#9FA79F")! : role.color(in: appearance, highContrast: highContrast)
        }
        let failed = Self.failures(Self.textPairs, appearance: .light, highContrast: false, resolve: seeded)
        #expect(failed.contains { $0.hasPrefix("textSecondary on background") })
        // And a seeded graphic below 3:1: an Out marker as dark as the court.
        let darkMarker: Resolver = { role, appearance, highContrast in
            role == .markerOut ? SRGBColor(hex: "#1F4A3B")! : role.color(in: appearance, highContrast: highContrast)
        }
        #expect(Self.failures(Self.graphicPairs, appearance: .dark, highContrast: false, resolve: darkMarker)
            .contains { $0.hasPrefix("markerOut on courtSurface") })
    }

    @Test("every colour role is either contrast-tested or classified as a surface")
    func everyRoleIsGated() {
        let foregrounds = Set((Self.textPairs + Self.graphicPairs).map(\.foreground))
        for role in ColorRole.allCases where !Self.isSurfaceOrDecorative(role) {
            #expect(foregrounds.contains(role), "\(role) is a foreground role without a contrast pair")
        }
    }

    @Test("Increase Contrast makes video overlays and the scrim opaque")
    func overlaysBecomeOpaque() {
        #expect(ColorRole.overlaySurface.opacity(highContrast: false) == 0.88)
        #expect(ColorRole.overlaySurface.opacity(highContrast: true) == 1)
        #expect(ColorRole.videoScrim.opacity(highContrast: false) == 0.55)
        #expect(ColorRole.videoScrim.opacity(highContrast: true) == 1)
        #expect(ColorRole.videoScrim.color(in: .dark, highContrast: true) == BrandPalette.forest)
        #expect(ColorRole.textPrimary.opacity(highContrast: false) == 1)
    }

    @Test("§5.3 token values match the screen spec")
    func specValues() {
        #expect(ColorRole.recording.color(in: .light) == SRGBColor(hex: "#D63A2E"))
        #expect(ColorRole.recording.color(in: .dark) == SRGBColor(hex: "#E5483B"))
        #expect(ColorRole.markerOut.color(in: .light) == BrandPalette.clay)
        #expect(ColorRole.markerOut.color(in: .dark) == SRGBColor(hex: "#D98B66"))
        #expect(ColorRole.positiveFill.color(in: .light) == SRGBColor(hex: "#E7EFD3"))
        #expect(ColorRole.attentionFill.color(in: .dark) == SRGBColor(hex: "#4A2E22"))
        #expect(ColorRole.courtSurface.color(in: .light) == BrandPalette.forestPanel)
        for appearance in [Appearance.light, .dark] {
            #expect(ColorRole.destructiveInk.color(in: appearance) == ColorRole.attentionInk.color(in: appearance))
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
            #expect(pair.foreground.color(in: .light) != BrandPalette.clay)
        }
    }
}
