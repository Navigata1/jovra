import JovraCore
import JovraMedia
import SwiftUI

/// The capture route's question sheets: stop, delete and the interruption's "Resume?". Each says what is
/// already safe before it asks, and the safe choice is never the destructive one.
struct CaptureDecisionSheet<Detail: View>: View {
    struct Choice {
        var title: String
        var identifier: String
        var isDestructive = false
        var perform: () -> Void
    }

    var symbol: String
    var title: String
    var message: String
    var primary: Choice
    var secondary: Choice
    var identifier: String
    @ViewBuilder var detail: Detail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x2) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .foregroundStyle(.jovra(primary.isDestructive ? .destructiveInk : .textPrimary))
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("\(identifier).title")
                Text(verbatim: message)
                    .font(.jovraBody)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                detail
                VStack(spacing: Space.x1 + Space.half) {
                    button(primary, kind: .primary)
                    button(secondary, kind: .secondary)
                }
                .padding(.top, Space.x1)
            }
            .padding(Space.x3)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.jovra(.surface).ignoresSafeArea())
        // Full height: a floating medium sheet is drawn scaled, which shortens its text frames below the text.
        .presentationDetents([.large])
        // Each sheet ends only through one of its two answers, never a stray swipe.
        .interactiveDismissDisabled()
        .accessibilityIdentifier(identifier)
    }

    private func button(_ choice: Choice, kind: JovraButtonStyle.Kind) -> some View {
        Button(action: choice.perform) {
            Text(verbatim: choice.title).frame(maxWidth: .infinity, minHeight: HitTarget.capture - 12)
        }
        .buttonStyle(JovraButtonStyle(kind: kind, fullWidth: true))
        .tint(choice.isDestructive ? .jovra(.destructiveInk) : nil)
        .accessibilityIdentifier(choice.identifier)
    }
}

extension CaptureDecisionSheet where Detail == EmptyView {
    init(symbol: String, title: String, message: String, primary: Choice, secondary: Choice, identifier: String) {
        self.init(symbol: symbol, title: title, message: message, primary: primary, secondary: secondary,
                  identifier: identifier) { EmptyView() }
    }
}

/// The sheets the recording phase presents, one at a time.
enum CaptureSheet: String, Identifiable {
    case stopConfirmation, deleteConfirmation, interruption, editDetails
    var id: String { rawValue }
}
