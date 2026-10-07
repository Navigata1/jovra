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
            HomeHero { router.select(.record) }
            SampleStatTiles()
            ComingLaterCard(
                symbol: "house",
                message: "Your latest session, on-court time and weekly trends, computed from sessions saved on this device, replace the sample tiles above."
            )
        }
    }
}

/// The forest editorial card: the "A better game tomorrow" kicker, a three-line headline and the
/// chartreuse call to action.
private struct HomeHero: View {
    var recordSession: () -> Void

    var body: some View {
        EditorialCard {
            HStack(alignment: .center, spacing: Space.x1) {
                Rectangle()
                    .fill(Color.jovra(.textOnEditorial).opacity(0.6))
                    .frame(width: 20, height: 1)
                    .accessibilityHidden(true)
                Text("A BETTER GAME TOMORROW")
                    .font(.jovraKicker)
                    .tracking(2.2)
                    .foregroundStyle(.jovra(.textOnEditorial))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("A better game tomorrow")
            }
            .padding(.bottom, Space.x3)
            Text("Ready for\nyour next\nsession?")
                .font(.jovraEditorial)
                .tracking(-0.4)
                .foregroundStyle(.jovra(.textOnEditorial))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Ready for your next session?")
                .accessibilityAddTraits(.isHeader)
            Button(action: recordSession) {
                Label("Record a session", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(.jovraAccent)
            .accessibilityIdentifier("home.recordSession")
        }
    }
}

/// Three illustrative stat tiles under a visible "Sample" badge (CLAUDE.md rule 1) until the
/// session store lands; VoiceOver reads "sample data" on every tile too. The tiles share one
/// height in a row and stack vertically at accessibility text sizes.
private struct SampleStatTiles: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let tiles: [(value: String, label: String, symbol: String)] = [
        ("8", "Sessions", "tennisball"),
        ("6h 42m", "On court", "clock"),
        ("67%", "First serves", "scope"),
    ]

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Space.x1))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Space.x1))
        VStack(alignment: .leading, spacing: Space.x1 + Space.half) {
            SectionHeader(title: "This week") {
                ProvenanceBadge(kind: .sample)
            }
            layout {
                ForEach(tiles, id: \.label) { tile in
                    StatTile(value: tile.value, label: tile.label, symbol: tile.symbol)
                        .accessibilityLabel("\(tile.label): \(tile.value), sample data")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.sampleStats")
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
