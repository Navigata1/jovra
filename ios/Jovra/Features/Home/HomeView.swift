import JovraCore
import SwiftUI

/// Home (S03, reference 03): the greeting, the next action (record), three honest headline numbers, the latest
/// session, the next useful step and one trend, all computed from stored sessions (`HomeDashboard`).
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.localCaptureLibrary) private var library
    @Environment(\.launchConfiguration) private var launch
    @State private var model = HomeModel()

    var body: some View {
        let dashboard: HomeDashboard? = if case .loaded(let value) = model.phase { value } else { nil }
        JovraScreen(title: HomeGreeting.text(name: dashboard?.playerName, at: model.now),
                    subtitle: String(localized: "Your game, in focus.", table: "Home")) {
            Button { router.select(.profile) } label: {
                AvatarInitial(initial: dashboard?.playerName, size: 52)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(profileLabel(dashboard?.playerName))
            .accessibilityIdentifier("home.profile")
        } content: {
            HomeHero { router.select(.record) }
            content(dashboard)
        }
        .task { await model.load(library: library, launch: launch) }
        .onChange(of: router.state.selectedTab) { _, tab in
            // Back on Home after recording, importing or reviewing elsewhere: recompute from the store.
            guard tab == .home else { return }
            Task { await model.load(library: library, launch: launch) }
        }
        .refreshable { await model.load(library: library, launch: launch) }
    }

    @ViewBuilder private func content(_ dashboard: HomeDashboard?) -> some View {
        switch model.phase {
        case .loading:
            ProgressView(String(localized: "Loading your sessions…", table: "Home", comment: "Home while sessions load"))
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("home.loading")
        case .unavailable:
            StateCard(symbol: "externaldrive.badge.exclamationmark",
                      title: String(localized: "Your sessions can't be opened right now", table: "Home", comment: "Home error title"),
                      message: String(localized: "Recording still works and nothing was deleted. Close JOVRA and open it again to see your numbers.",
                                      table: "Home", comment: "Home error message: local library unavailable"))
        case .failed:
            StateCard(symbol: "exclamationmark.triangle",
                      title: String(localized: "Your numbers could not be loaded", table: "Home", comment: "Home error title"),
                      message: String(localized: "Your videos are safe. Try loading them again.", table: "Home", comment: "Home error message"),
                      primaryAction: .init(title: String(localized: "Try again", table: "Home")) {
                          Task { await model.load(library: library, launch: launch) }
                      })
        case .loaded(let dashboard):
            switch dashboard.content {
            case .empty:
                HomeEmptyState(record: { router.select(.record) },
                               importVideo: { router.show(.push(.sessions(.importVideos))) })
            case .populated(let overview):
                populated(overview, nextSteps: dashboard.nextSteps)
            }
        }
    }

    @ViewBuilder private func populated(_ overview: HomeDashboard.Overview, nextSteps: [HomeNextStep]) -> some View {
        let caption = HomeCopy.windowCaption(overview.window, now: model.now)
        HomeStatTiles(overview: overview, windowCaption: caption)
        VStack(alignment: .leading, spacing: Space.x1 + Space.half) {
            SectionHeader(title: String(localized: "Latest session", table: "Home", comment: "Section header")) {
                Button { router.select(.sessions) } label: {
                    Label {
                        Text("View all", tableName: "Home", comment: "Opens the session library")
                    } icon: {
                        Image(systemName: "chevron.right").imageScale(.small)
                    }
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.jovraLabel)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: HitTarget.minimum)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.viewAll")
            }
            HomeLatestSessionCard(latest: overview.latest, thumbnail: model.thumbnail) {
                let id = SessionID(rawValue: overview.latest.id)
                router.show(.push(.sessions(overview.latest.format == nil ? .practiceOverview(id) : .matchOverview(id))))
            }
            ForEach(nextSteps) { step in
                HomeNextStepRow(step: step) { router.show(step.destination) }
            }
        }
        VStack(alignment: .leading, spacing: Space.x1 + Space.half) {
            SectionHeader(title: caption) {
                if overview.isSample { ProvenanceBadge(kind: .sample).accessibilityIdentifier("home.trend.sample") }
            }
            HomeTrendCard(trend: overview.trend, isSample: overview.isSample)
        }
    }

    private func profileLabel(_ name: String?) -> Text {
        if let name { return Text("Profile, \(name)", tableName: "Home", comment: "VoiceOver: the avatar button, e.g. “Profile, Jon”") }
        return Text("Profile", tableName: "Home")
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
                Text("A BETTER GAME TOMORROW", tableName: "Home")
                    .font(.jovraKicker)
                    .tracking(2.2)
                    .foregroundStyle(.jovra(.textOnEditorial))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("A better game tomorrow", tableName: "Home"))
            }
            .padding(.bottom, Space.x3)
            Text("Ready for\nyour next\nsession?", tableName: "Home")
                .font(.jovraEditorial)
                .tracking(-0.4)
                .foregroundStyle(.jovra(.textOnEditorial))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text("Ready for your next session?", tableName: "Home"))
                .accessibilityAddTraits(.isHeader)
            Button(action: recordSession) {
                Label(String(localized: "Record a session", table: "Home"), systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(.jovraAccent)
            .accessibilityIdentifier("home.recordSession")
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
