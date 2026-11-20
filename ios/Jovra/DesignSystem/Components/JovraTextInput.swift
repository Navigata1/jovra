import SwiftUI
import UIKit

/// The actual UIKit input owns the full target, not only its SwiftUI background wrapper.
struct JovraTextInput: UIViewRepresentable {
    @Binding var text: String
    let title: String
    let identifier: String
    var keyboardType: UIKeyboardType = .default
    /// Shown while empty, in the secondary text colour (a search field's prompt). nil shows none.
    var placeholder: String? = nil
    var autocapitalization: UITextAutocapitalizationType = .words
    var returnKey: UIReturnKeyType = .done
    @ScaledMetric(relativeTo: .body) private var fontSize = 17.0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SizedTextField {
        let field = SizedTextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.autocorrectionType = .no
        field.adjustsFontSizeToFitWidth = false
        field.accessibilityLabel = title
        field.accessibilityIdentifier = identifier
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: SizedTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.font = .systemFont(ofSize: fontSize)
        field.keyboardType = keyboardType
        field.returnKeyType = returnKey
        field.autocapitalizationType = autocapitalization
        let appearance: Appearance = context.environment.colorScheme == .dark ? .dark : .light
        let highContrast = context.environment.colorSchemeContrast == .increased
        field.textColor = ColorRole.textPrimary.color(in: appearance, highContrast: highContrast).uiColor
        // Only while empty: a hidden prompt wider than the typed text still reads as clipped text to the audit.
        field.attributedPlaceholder = (text.isEmpty ? placeholder : nil).map {
            NSAttributedString(string: $0, attributes: [
                .foregroundColor: ColorRole.textSecondary.color(in: appearance, highContrast: highContrast).uiColor,
                .font: UIFont.systemFont(ofSize: fontSize),
            ])
        }
        field.tintColor = ColorRole.accent.uiColor
        field.invalidateIntrinsicContentSize()
    }

    final class SizedTextField: UITextField {
        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: max(64, (font?.lineHeight ?? 22) + 16))
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: JovraTextInput
        init(_ parent: JovraTextInput) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
