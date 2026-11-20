import JovraCore
import SwiftUI

/// The session library (S08, reference 08): "Your sessions" with search and the All / Matches / Practice filter,
/// one SessionCard per session (newest first, Sample sessions badged), the sessions set aside in quarantine with
/// their reason, and Trash. Delete moves a session to Trash with Undo.
struct SessionsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.localCaptureLibrary) private var library
    @Environment(\.launchConfiguration) private var launch
    @State private var model = SessionLibraryModel()
    @State private var filter = LibraryFilter.all
    @State private var search = ""
    @State private var toasts = ToastCenter()
    @State private var deleting: LibraryEntry?

    var body: some View {
        JovraScreen(title: String(localized: "Your sessions", table: "Sessions.Library"),
                    subtitle: String(localized: "Review. Improve. Keep going.", table: "Sessions.Library")) {
            Button { router.show(.push(.sessions(.importVideos))) } label: {
                Label(String(localized: "Import", table: "Sessions.Library"), systemImage: "plus")
            }
            .buttonStyle(JovraButtonStyle(kind: .accent, size: .compact))
            .accessibilityLabel(Text("Import a video", tableName: "Sessions.Library"))
            .accessibilityIdentifier("library.import")
        } content: {
            LibrarySearchField(text: $search)
            FilterPills(options: LibraryFilter.allCases, selection: $filter) { $0.title }
            if filter == .matches {
                Text("Matches includes scored practice sets.", tableName: "Sessions.Library")
                    .font(.jovraLabel).foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            CaptureRecoveryNotice(summary: model.recovery)
            if model.operationFailed {
                StateCard(symbol: "exclamationmark.triangle",
                          title: String(localized: "That didn't finish", table: "Sessions.Library"),
                          message: String(localized: "The session is where it was. Try again.", table: "Sessions.Library"))
            }
            if !model.snapshot.quarantined.isEmpty, model.phase == .loaded {
                QuarantineNotice(records: model.snapshot.quarantined)
            }
            libraryContent
            if !model.snapshot.trashed.isEmpty, model.phase == .loaded { trashRow }
        }
        .toastHost(toasts)
        .task { await model.reload(library, launch: launch) }
        .refreshable { await model.reload(library, launch: launch) }
        // Trash restores and purges in its own sheet; the list catches up when it closes.
        .onChange(of: router.sheet) { old, new in
            if old == .trash, new == nil { Task { await model.reload(library, launch: launch) } }
        }
        .alert(deleting.map { String(localized: "Delete “\($0.title)”?", table: "Sessions.Library") } ?? "",
               isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { entry in
            Button(String(localized: "Move to Trash", table: "Sessions.Library"), role: .destructive) { moveToTrash(entry) }
            Button(String(localized: "Cancel", table: "Sessions.Library"), role: .cancel) {}
        } message: { entry in
            Text(verbatim: Self.deleteMessage(entry))
        }
    }

    @ViewBuilder private var libraryContent: some View {
        switch model.phase {
        case .loading:
            LibraryLoadingCards(caption: String(localized: "Loading your sessions…", table: "Sessions.Library"))
        case .recordingFixture(let seconds):
            LibraryLoadingCards(caption: String(localized: "Recording a \(seconds)-second fixture session…", table: "Sessions.Library"))
        case .unavailable:
            StateCard(symbol: "externaldrive.badge.exclamationmark",
                      title: String(localized: "Local library unavailable", table: "Sessions.Library"),
                      message: String(localized: "Close JOVRA and try again. Your existing videos are not removed.", table: "Sessions.Library"))
        case .failed:
            StateCard(symbol: "exclamationmark.triangle",
                      title: String(localized: "Sessions could not be loaded", table: "Sessions.Library"),
                      message: String(localized: "Your videos are not removed. Try loading the library again.", table: "Sessions.Library"),
                      primaryAction: .init(title: String(localized: "Try again", table: "Sessions.Library")) {
                          Task { await model.reload(library, launch: launch) }
                      })
        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder private var loadedContent: some View {
        let visible = LibraryListing.visible(model.snapshot.entries, search: search, filter: filter)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.snapshot.entries.isEmpty {
            StateCard(symbol: "video.badge.plus",
                      title: String(localized: "No sessions yet", table: "Sessions.Library"),
                      message: String(localized: "Record a match or practice, or import a video you already have.", table: "Sessions.Library"),
                      primaryAction: .init(title: String(localized: "Record a session", table: "Sessions.Library")) { router.show(.tab(.record)) },
                      secondaryAction: .init(title: String(localized: "Import a video", table: "Sessions.Library")) {
                          router.show(.push(.sessions(.importVideos)))
                      })
            .accessibilityIdentifier("library.empty")
        } else if visible.isEmpty, !query.isEmpty {
            StateCard(symbol: "magnifyingglass",
                      title: String(localized: "No sessions match “\(query)”", table: "Sessions.Library"),
                      message: String(localized: "Search looks at titles, players and notes.", table: "Sessions.Library"),
                      primaryAction: .init(title: String(localized: "Clear search", table: "Sessions.Library")) { search = "" })
            .accessibilityIdentifier("library.noResults")
        } else if visible.isEmpty {
            StateCard(symbol: "line.3.horizontal.decrease.circle",
                      title: filter == .practice ? String(localized: "No practice sessions yet", table: "Sessions.Library")
                                                 : String(localized: "No matches yet", table: "Sessions.Library"),
                      message: String(localized: "Choose All to see your other sessions.", table: "Sessions.Library"),
                      primaryAction: .init(title: String(localized: "Show all sessions", table: "Sessions.Library")) { filter = .all })
        } else {
            ForEach(visible) { entry in
                SessionCard(entry: entry,
                            open: { router.present(.replay(.init(session: SessionID(rawValue: entry.id), point: nil, filter: .all))) },
                            delete: { deleting = entry })
            }
        }
    }

    private var trashRow: some View {
        Button { router.present(sheet: .trash) } label: {
            HStack(spacing: Space.x1 + Space.half) {
                Image(systemName: "trash")
                    .foregroundStyle(.jovra(.textSecondary))
                    .accessibilityHidden(true)
                Text("Trash · \(model.snapshot.trashed.count)", tableName: "Sessions.Library",
                     comment: "Row that opens Trash, with how many sessions are in it")
                    .font(.jovraLabel)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.x1)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.jovra(.textSecondary))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: HitTarget.minimum)
            .padding(.horizontal, Space.x2)
            .background(Color.jovra(.surfaceSunken), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.trash")
    }

    private func moveToTrash(_ entry: LibraryEntry) {
        Task {
            guard await model.moveToTrash(entry, in: library, launch: launch) else { return }
            toasts.show(String(localized: "Moved to Trash", table: "Sessions.Library")) {
                Task { _ = await model.restore(entry.id, in: library, launch: launch) }
            }
        }
    }

    /// What moving to Trash does, said before it happens: nothing is deleted yet, and Drive is not touched.
    /// A session with nothing stored here (sample, archived-only, missing video) states no size rather than
    /// "Zero kB", the same rule the card's storage line and the purge dialog follow.
    nonisolated static func deleteMessage(_ entry: LibraryEntry, locale: Locale = .autoupdatingCurrent) -> String {
        let size = entry.bytes.flatMap { $0.total > 0 ? SessionCardPresentation.bytes($0.total, locale: locale) : nil }
        let first = size.map { String(localized: "The video (\($0)) and its points move to Trash.", table: "Sessions.Library") }
            ?? String(localized: "The session and its points move to Trash.", table: "Sessions.Library")
        let rest = entry.archive == .backedUp
            ? String(localized: "Nothing is deleted until you delete it there. Your Google Drive copy is not affected.", table: "Sessions.Library")
            : String(localized: "Nothing is deleted until you delete it there.", table: "Sessions.Library")
        return first + " " + rest
    }
}

/// The inline search pill (story 120): titles, players and notes. Clearing is one tap.
struct LibrarySearchField: View {
    @Binding var text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Space.x1 + Space.half) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(.jovra(.textSecondary))
                .accessibilityHidden(true)
            // The UIKit input owns its full 64 pt target (a SwiftUI TextField reports only its line of text).
            // At accessibility sizes the prompt shortens to one word so it is never cut off.
            JovraTextInput(text: $text,
                           title: String(localized: "Search players, courts, notes", table: "Sessions.Library"),
                           identifier: "library.search",
                           placeholder: dynamicTypeSize.isAccessibilitySize
                               ? String(localized: "Search", table: "Sessions.Library")
                               : String(localized: "Search players, courts, notes", table: "Sessions.Library"),
                           autocapitalization: .none, returnKey: .search)
                .frame(maxWidth: .infinity)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.jovra(.textSecondary))
                        .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search", tableName: "Sessions.Library"))
                .accessibilityIdentifier("library.search.clear")
            }
        }
        .padding(.leading, Space.x2)
        .padding(.trailing, text.isEmpty ? Space.x2 : Space.half)
        .background(Color.jovra(.surfaceSunken), in: Capsule())
    }
}

/// Session documents that could not be read were set aside, never deleted (story 386). Each says why; every
/// other session still lists.
struct QuarantineNotice: View {
    var records: [QuarantinedSession]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1 + Space.half) {
            Label {
                Text(records.count == 1
                     ? String(localized: "1 session couldn't be opened", table: "Sessions.Library")
                     : String(localized: "\(records.count) sessions couldn't be opened", table: "Sessions.Library"))
                    .font(.jovraHeadline)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.jovra(.attentionInk))
            }
            .accessibilityAddTraits(.isHeader)
            Text("Their files were set aside on this iPhone, not deleted, so the rest of your library still opens.",
                 tableName: "Sessions.Library")
                .font(.jovraBody)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(records, id: \.folderName) { record in
                VStack(alignment: .leading, spacing: Space.half) {
                    Text(verbatim: record.sessionID)
                        .font(.jovraLabel.monospaced())
                        .foregroundStyle(.jovra(.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.reason(record.reason))
                        .font(.jovraCaption)
                        .foregroundStyle(.jovra(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.x1 + Space.half)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.jovra(.surfaceSunken), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("library.quarantined.\(record.sessionID)")
            }
        }
        .jovraCard()
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.jovra(.attentionInk).opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.quarantine")
    }

    /// The store's reason in the player's words.
    static func reason(_ reason: String) -> String {
        switch reason {
        case "Invalid or unsupported document":
            String(localized: "Reason: the file is not a session this version of JOVRA can read.", table: "Sessions.Library")
        case "Invalid document fields":
            String(localized: "Reason: some of the session's details could not be read.", table: "Sessions.Library")
        case "Unsupported document version":
            String(localized: "Reason: the session was saved by a newer version of JOVRA.", table: "Sessions.Library")
        default:
            String(localized: "Reason: the session folder could not be read.", table: "Sessions.Library")
        }
    }
}

/// The loading state: redacted card shapes with the caption, so the screen keeps its layout while it reads.
private struct LibraryLoadingCards: View {
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Label {
                Text(caption).fixedSize(horizontal: false, vertical: true)
            } icon: {
                ProgressView()
            }
            .font(.jovraLabel)
            .foregroundStyle(.jovra(.textSecondary))
            .accessibilityIdentifier("library.loading")
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: Space.x2 - Space.half) {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Color.jovra(.surfaceSunken))
                        .frame(width: 132, height: 82)
                    VStack(alignment: .leading, spacing: Space.x1) {
                        Capsule().fill(Color.jovra(.surfaceSunken)).frame(height: 14)
                        Capsule().fill(Color.jovra(.surfaceSunken)).frame(width: 90, height: 12)
                    }
                }
                .jovraCard(padding: Space.x1 + Space.half)
                .accessibilityHidden(true)
            }
        }
    }
}
