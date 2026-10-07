import SwiftUI

struct HomeView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        JovraScreen(title: "Home", subtitle: "Your game, in focus.") {
            Button { router.select(.profile) } label: {
                AvatarInitial(initial: nil, size: 52)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        } content: {
            EditorialCard {
                Text("Ready for your next session?")
                    .font(.jovraEditorial)
                    .foregroundStyle(.jovra(.textOnEditorial))
                    .fixedSize(horizontal: false, vertical: true)
                Button { router.select(.record) } label: {
                    Label("Record a session", systemImage: "arrow.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(.jovraAccent)
                .accessibilityIdentifier("home.recordSession")
            }
            ComingLaterCard(
                symbol: "house",
                message: "Your latest session, on-court time and weekly trends will appear here, computed from sessions saved on this device."
            )
        }
    }
}

/// Title first, icon after ("Record a session →").
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.x1) {
            configuration.title
            configuration.icon
        }
    }
}
