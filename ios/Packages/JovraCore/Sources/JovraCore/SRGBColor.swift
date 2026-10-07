import Foundation

/// An opaque colour in the sRGB space, with the WCAG 2.x relative-luminance and contrast-ratio maths.
///
/// Design tokens are declared with this type so their accessibility (text contrast) can be asserted
/// on any platform, including Linux CI, without UIKit.
public struct SRGBColor: Hashable, Sendable {
    /// Channel values in 0...1.
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// Parses `#RRGGBB` or `RRGGBB` (case-insensitive). Returns `nil` for anything else.
    public init?(hex: String) {
        var digits = Substring(hex)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        // Check every character first: UInt32(_:radix:) on its own would accept a leading "+" or "-".
        let isASCIIHex: (Character) -> Bool = { $0.isASCII && $0.isHexDigit }
        guard digits.count == 6, digits.allSatisfy(isASCIIHex), let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// WCAG 2.x relative luminance (0 for black, 1 for white).
    public var relativeLuminance: Double {
        0.2126 * Self.linearize(red) + 0.7152 * Self.linearize(green) + 0.0722 * Self.linearize(blue)
    }

    /// WCAG 2.x contrast ratio between this colour and `other`, from 1 (identical) to 21 (black on white).
    /// Symmetric: the lighter colour is always the numerator.
    public func contrastRatio(with other: SRGBColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func linearize(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
}
