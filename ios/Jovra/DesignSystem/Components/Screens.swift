import SwiftUI

/// The standard tab screen: brand lockup row, large display title, grey subtitle, then content,
/// on the appearance-aware background.
struct JovraScreen<Accessory: View, Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                HStack(alignment: .center) {
                    JovraLockup(height: 40)
                    Spacer(minLength: Space.x2)
                    accessory
                }
                VStack(alignment: .leading, spacing: Space.half) {
                    Text(title)
                        .jovraDisplayTitle()
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("screen.title")
                    if let subtitle {
                        Text(subtitle)
                            .font(.jovraSubtitle)
                            .foregroundStyle(.jovra(.textSecondary))
                    }
                }
                content
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.top, Space.x1)
            .padding(.bottom, Space.x4)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        // Content stops at the tab bar instead of sliding beneath it, so nothing is ever half-covered.
        .clipped()
        .background(Color.jovra(.background).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension JovraScreen where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

/// The obvious "not built yet" state, so placeholder screens are never mistaken for features.
struct ComingLaterCard: View {
    var symbol: String
    var title = "Coming in a later ticket"
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.jovra(.onAccent))
                .frame(width: 52, height: 52)
                .background(Color.jovra(.accent), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.jovraHeadline)
                .foregroundStyle(.jovra(.textPrimary))
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.jovraBody)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            Label("Placeholder screen", systemImage: "hammer")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .jovraCard(padding: Space.x3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("placeholder.comingLater")
    }
}
