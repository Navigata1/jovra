import JovraCore
import SwiftUI

struct SessionsView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, matches, practice
        var id: String { rawValue }

        /// Matches groups the three kinds with a scoring format; Practice contains the
        /// remaining practice/lesson kinds. This is a bounded UI grouping, not a schema change.
        func includes(_ kind: SessionDocumentSessionKind) -> Bool {
            let isScored = kind == .match || kind == .tiebreakOnly || kind == .practiceSet
            switch self {
            case .all: return true
            case .matches: return isScored
            case .practice: return !isScored
            }
        }

        var title: String {
            switch self {
            case .all: String(localized: "All", table: "Sessions", comment: "Session filter")
            case .matches: String(localized: "Matches", table: "Sessions", comment: "Session filter")
            case .practice: String(localized: "Practice", table: "Sessions", comment: "Session filter")
            }
        }
    }

    private enum LoadState {
        case loading, unavailable, failed
        case loaded([JovraCore.SessionSummary])
    }

    @Environment(AppRouter.self) private var router
    @Environment(\.localCaptureLibrary) private var library
    @State private var filter = Filter.all
    @State private var state = LoadState.loading
    @State private var reloadToken = UUID()

    var body: some View {
        JovraScreen(title: String(localized: "Your sessions", table: "Sessions"), subtitle: String(localized: "Review. Improve. Keep going.", table: "Sessions")) {
            FilterPills(options: Filter.allCases, selection: $filter) { $0.title }
            if filter == .matches {
                Text("Matches includes scored practice sets.", tableName: "Sessions.Library")
                    .font(.jovraLabel).foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            libraryContent
        }
        .task(id: filter) { await reload() }
        .refreshable { await reload() }
    }

    @ViewBuilder private var libraryContent: some View {
        switch state {
        case .loading:
            ProgressView(String(localized: "Loading your sessions…", table: "Sessions.Library"))
        case .unavailable:
            StateCard(symbol: "externaldrive.badge.exclamationmark",
                      title: String(localized: "Local library unavailable", table: "Sessions.Library"),
                      message: String(localized: "Close JOVRA and try again. Your existing videos are not removed.", table: "Sessions.Library"))
        case .failed:
            StateCard(symbol: "exclamationmark.triangle",
                      title: String(localized: "Sessions could not be loaded", table: "Sessions.Library"),
                      message: String(localized: "Your videos are not removed. Try loading the library again.", table: "Sessions.Library"),
                      primaryAction: .init(title: String(localized: "Try again", table: "Sessions.Library")) { Task { await reload() } })
        case .loaded(let sessions):
            if sessions.isEmpty {
                StateCard(symbol: "video",
                          title: String(localized: "No sessions in this view", table: "Sessions.Library"),
                          message: String(localized: "Choose All to see other sessions, or record a new session.", table: "Sessions.Library"),
                          primaryAction: .init(title: String(localized: "Record a session", table: "Sessions.Library")) { router.show(.tab(.record)) })
            } else {
                ForEach(sessions, id: \.id) { session in
                    LibrarySessionRow(session: session) {
                        router.present(.replay(.init(session: SessionID(rawValue: session.id), point: nil, filter: .all)))
                    }
                }
            }
        }
    }

    private func reload() async {
        let token = UUID()
        reloadToken = token
        guard case .ready(let library) = library else { state = .unavailable; return }
        state = .loading
        let selectedFilter = filter
        do {
            let sessions = try await library.sessions()
            guard !Task.isCancelled, reloadToken == token else { return }
            state = .loaded(sessions.filter { selectedFilter.includes($0.kind) })
        } catch {
            guard !Task.isCancelled, reloadToken == token else { return }
            state = .failed
        }
    }
}
