import JovraCore
import SwiftUI
import UIKit

extension SRGBColor {
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }
}

extension ColorRole {
    /// A dynamic colour that follows the trait collection's appearance and Increase Contrast setting.
    var uiColor: UIColor {
        UIColor { traits in
            let appearance: Appearance = traits.userInterfaceStyle == .dark ? .dark : .light
            return color(in: appearance, highContrast: traits.accessibilityContrast == .high).uiColor
        }
    }
}

extension Color {
    /// The colour for a semantic role, e.g. `Color.jovra(.textSecondary)`.
    static func jovra(_ role: ColorRole) -> Color { Color(uiColor: role.uiColor) }
}

extension ShapeStyle where Self == Color {
    static func jovra(_ role: ColorRole) -> Color { Color.jovra(role) }
}
