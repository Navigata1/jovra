import SwiftUI

/// Caps reading content at 720 pt and centres it (screens.md §0.5): full width on iPhone, a readable
/// column on iPad and in landscape. Every tab screen uses it through `JovraScreen`.
struct ReadableColumn<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: readableColumnMaximumWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

private let readableColumnMaximumWidth: CGFloat = 720

extension ReadableColumn where Content == EmptyView {
    /// The column's maximum width in points.
    static var maximumWidth: CGFloat { readableColumnMaximumWidth }
}

/// The compact header of full-screen routes (S10, S14, N1, N10): a 44 pt Close control, the small
/// lockup, trailing actions, and the title, which steps aside in compact height (landscape iPhone) so
/// the video gets the room.
struct FocusedHeader<Trailing: View>: View {
    var title: String
    var closeLabel: String
    var onClose: () -> Void
    @ViewBuilder var trailing: Trailing
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            HStack(spacing: Space.x1) {
                CloseControl(label: closeLabel, identifier: "focusedHeader.close", action: onClose)
                Spacer(minLength: Space.x1)
                JovraLockup(height: 28)
                    .accessibilityHidden(true)
                Spacer(minLength: Space.x1)
                trailing
                    .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
            }
            if verticalSizeClass != .compact {
                Text(title)
                    .font(.jovraHeadline)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("focusedHeader.title")
            }
        }
        .padding(.horizontal, Space.x2)
        .padding(.vertical, Space.x1)
    }
}

extension FocusedHeader where Trailing == EmptyView {
    init(title: String, closeLabel: String, onClose: @escaping () -> Void) {
        self.init(title: title, closeLabel: closeLabel, onClose: onClose) { EmptyView() }
    }
}
