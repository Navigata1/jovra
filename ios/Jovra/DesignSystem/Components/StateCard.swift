import SwiftUI

/// Shared empty, error, permission and unsupported states. Copy and actions belong to the caller;
/// an error must explain what is safe and what the player can do next.
struct StateCard: View {
    struct Action {
        var title: String
        var perform: () -> Void
    }

    var symbol: String
    var title: String
    var message: String
    var primaryAction: Action? = nil
    var secondaryAction: Action? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.jovra(.textPrimary))
                .accessibilityHidden(true)
            Text(title)
                .font(.jovraHeadline)
                .foregroundStyle(.jovra(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.jovraBody)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            if let primaryAction { actionButton(primaryAction, kind: .primary) }
            if let secondaryAction { actionButton(secondaryAction, kind: .secondary) }
        }
        .jovraCard()
        .accessibilityElement(children: .contain)
    }

    private func actionButton(_ action: Action, kind: JovraButtonStyle.Kind) -> some View {
        Button(action.title, action: action.perform)
            .buttonStyle(JovraButtonStyle(kind: kind, fullWidth: true))
    }
}

/// Sample mode is always visible; the caller connects its action to onboarding or another safe exit.
struct DemoBanner: View {
    var actionTitle: String = String(localized: "Make it yours", table: "DesignSystem.Components")
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            SampleBadge()
            Text(String(localized: "You're exploring sample data", table: "DesignSystem.Components"))
                .font(.jovraHeadline)
                .foregroundStyle(.jovra(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .buttonStyle(.jovraSecondary)
        }
        .jovraCard()
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Color.jovra(.textPrimary), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}
