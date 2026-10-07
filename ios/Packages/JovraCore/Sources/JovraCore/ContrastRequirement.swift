/// WCAG 2.x AA contrast minimums (success criteria 1.4.3 and 1.4.11).
public enum ContrastRequirement: Sendable, CaseIterable {
    /// Body and caption text: 4.5:1.
    case normalText
    /// Text at least 18 pt regular or 14 pt bold: 3:1.
    case largeText
    /// Icons, focus indicators and the parts of a control needed to identify it: 3:1.
    case nonText

    public var minimumRatio: Double {
        switch self {
        case .normalText: 4.5
        case .largeText, .nonText: 3.0
        }
    }

    public func isMet(by foreground: SRGBColor, on background: SRGBColor) -> Bool {
        foreground.contrastRatio(with: background) >= minimumRatio
    }
}
