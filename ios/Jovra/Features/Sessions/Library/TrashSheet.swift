import JovraCore
import SwiftUI

/// Trash (S08 "Recently deleted"): sessions moved here keep their video until the player deletes them, one at a
/// time, after a dialog that states exactly what goes and whether a verified Google Drive copy exists (stories
/// 129–131). Nothing here is emptied automatically.
struct TrashSheet: View {
    nonisolated static let isPlaceholder = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.localCaptureLibrary) private var library
    @Environment(\.launchConfiguration) private var launch
    @State private var model = SessionLibraryModel()
    @State private var purging: LibraryEntry?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CloseControl(label: String(localized: "Close trash", table: "Sessions.Library"), identifier: "sheet.close") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, Space.x2)
            .padding(.top, Space.x1)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    VStack(alignment: .leading, spacing: Space.x1) {
                        Text("Trash", tableName: "Sessions.Library")
                            .jovraDisplayTitle()
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("screen.title")
                        Text("Sessions here keep their video until you delete them. Nothing is deleted automatically.",
                             tableName: "Sessions.Library")
                            .font(.jovraBody)
                            .foregroundStyle(.jovra(.textSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("trash.explainer")
                    }
                    content
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.top, Space.x1)
                .padding(.bottom, Space.x4)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.jovra(.background).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet.container")
        .task { await model.reload(library, launch: launch) }
        .alert(purging.map { PurgeScope($0).title } ?? "", isPresented: Binding(get: { purging != nil }, set: { if !$0 { purging = nil } }),
               presenting: purging) { entry in
            Button(String(localized: "Delete permanently", table: "Sessions.Library"), role: .destructive) {
                Task { _ = await model.purge(entry.id, in: library, launch: launch) }
            }
            .accessibilityIdentifier("trash.confirmPurge")
            Button(String(localized: "Cancel", table: "Sessions.Library"), role: .cancel) {}
        } message: { entry in
            Text(verbatim: PurgeScope(entry).message)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading, .recordingFixture:
            ProgressView(String(localized: "Loading Trash…", table: "Sessions.Library"))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .unavailable, .failed:
            StateCard(symbol: "externaldrive.badge.exclamationmark",
                      title: String(localized: "Trash could not be loaded", table: "Sessions.Library"),
                      message: String(localized: "Nothing in it was deleted. Try again.", table: "Sessions.Library"),
                      primaryAction: .init(title: String(localized: "Try again", table: "Sessions.Library")) {
                          Task { await model.reload(library, launch: launch) }
                      })
        case .loaded:
            if model.operationFailed {
                StateCard(symbol: "exclamationmark.triangle",
                          title: String(localized: "That didn't finish", table: "Sessions.Library"),
                          message: String(localized: "The session is where it was. Try again.", table: "Sessions.Library"))
            }
            if model.snapshot.trashed.isEmpty {
                StateCard(symbol: "trash",
                          title: String(localized: "Trash is empty", table: "Sessions.Library"),
                          message: String(localized: "Sessions you delete wait here until you delete them for good.", table: "Sessions.Library"))
            } else {
                ForEach(model.snapshot.trashed) { entry in
                    TrashRow(entry: entry,
                             restore: { Task { _ = await model.restore(entry.id, in: library, launch: launch) } },
                             purge: { purging = entry })
                }
            }
        }
    }
}

/// One trashed session: what it is, what it holds on this iPhone and whether Google Drive has it, then
/// Restore and Delete now.
private struct TrashRow: View {
    var entry: LibraryEntry
    var restore: () -> Void
    var purge: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let presentation = SessionCardPresentation(entry)
        let scope = PurgeScope(entry)
        VStack(alignment: .leading, spacing: Space.x2) {
            VStack(alignment: .leading, spacing: Space.half) {
                Text(presentation.title)
                    .font(.jovraHeadline)
                    .foregroundStyle(.jovra(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                if presentation.isSample { SampleBadge(size: .small) }
                Text(presentation.metadata)
                    .font(.jovraLabel)
                    .foregroundStyle(.jovra(.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                if let storage = presentation.storage {
                    Label(storage, systemImage: "internaldrive")
                        .font(.jovraCaption)
                        .foregroundStyle(.jovra(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            StatusPill(text: scope.drive == .verifiedOriginal
                       ? String(localized: "Backed up in Google Drive", table: "Sessions.Library")
                       : String(localized: "No verified Google Drive copy", table: "Sessions.Library"),
                       tone: scope.drive == .verifiedOriginal ? .positive : .attention,
                       symbol: scope.drive == .verifiedOriginal ? "checkmark.icloud.fill" : "icloud.slash")
            // Side by side, stacked at accessibility sizes (one layout in the tree, so the text always scales).
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Space.x1)) : AnyLayout(HStackLayout(spacing: Space.x1))
            layout { buttons }
        }
        .jovraCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trash.session.\(entry.id)")
    }

    @ViewBuilder private var buttons: some View {
        Button(String(localized: "Restore", table: "Sessions.Library"), action: restore)
            .buttonStyle(JovraButtonStyle(kind: .secondary, fullWidth: true, size: .compact))
            .accessibilityIdentifier("trash.restore.\(entry.id)")
        Button(String(localized: "Delete now", table: "Sessions.Library"), action: purge)
        .buttonStyle(JovraButtonStyle(kind: .primary, fullWidth: true, size: .compact))
        .accessibilityIdentifier("trash.purge.\(entry.id)")
    }
}
