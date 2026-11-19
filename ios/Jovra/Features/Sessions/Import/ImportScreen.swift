import JovraCore
import JovraMedia
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// "Bring your game in" (S07, T26): Photos, Files and Google Drive sources, what the footage is, and a
/// per-file result for every picked video. A single clean import presents the session's processing route.
struct ImportScreen: View {
    private enum Kind: Hashable { case practice, match }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(\.localCaptureLibrary) private var library
    @Environment(\.launchConfiguration) private var launch
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var source = ImportSourceKind.photos
    @State private var kind = Kind.practice
    @State private var playerName = ""
    @State private var playerA = ""
    @State private var playerB = ""
    @State private var format: SinglesMatchFormat?
    @State private var gameScoring: SessionMatchFormatGameScoring?
    @State private var firstServer: Side?
    @State private var nearPlayer: Side?
    @State private var containsFullMatch = false
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var pickerIssue: String?
    @State private var model = ImportModel()

    var body: some View {
        JovraScreen(title: String(localized: "Bring your game in", table: "Sessions.Import"),
                    subtitle: String(localized: "Import your footage and let JOVRA do the rest.", table: "Sessions.Import")) {
            Button { dismiss() } label: {
                Label(String(localized: "Back to sessions", table: "Sessions.Import"), systemImage: "chevron.left")
            }
            .buttonStyle(.jovraCompact)
            .accessibilityIdentifier("import.back")
        } content: {
            sourceTiles
            if source == .drive {
                DriveTileExplanation { select(.files) }
            } else {
                footageCard
                chooseSection
            }
            if model.hasRows { resultsSection }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie], allowsMultipleSelection: kind == .practice) { result in
            switch result {
            case .success(let urls):
                start(urls.map { ImportItem(url: $0, origin: .files) })
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    pickerIssue = String(localized: "Files couldn't open that selection. Your files were not changed.", table: "Sessions.Import")
                }
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoSelection, maxSelectionCount: kind == .practice ? 20 : 1,
                      selectionBehavior: .ordered, matching: .videos, preferredItemEncoding: .current)
        .onChange(of: photoSelection) { _, picked in receivePhotos(picked) }
        .onAppear { if !model.isRunning, !model.needsAttention { ImportInbox.sweep() } }
        .onDisappear {
            // Covered by a full-screen route, the screen keeps its work; popped, held copies are discarded.
            guard !router.state.sessionsPath.contains(.importVideos), case .ready(let library) = library else { return }
            Task { await model.discardHeldCopies(library: library) }
        }
    }

    // MARK: Sources

    private var sourceTiles: some View {
        let tiles = ForEach(ImportSourceKind.allCases) { tile in
            ImportSourceTile(source: tile, isSelected: source == tile) { select(tile) }
        }
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: Space.x1) { tiles }
            } else {
                HStack(alignment: .top, spacing: Space.x1) { tiles }
            }
        }
        .disabled(model.isRunning)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Import from", table: "Sessions.Import"))
    }

    private func select(_ tile: ImportSourceKind) {
        source = tile
        pickerIssue = nil
    }

    // MARK: Footage

    private var footageCard: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            SectionHeader(title: String(localized: "About this footage", table: "Sessions.Import"))
            Picker(selection: $kind) {
                Text("Practice", tableName: "Sessions.Import").tag(Kind.practice)
                Text("Singles match", tableName: "Sessions.Import").tag(Kind.match)
            } label: {
                Text("Import as", tableName: "Sessions.Import")
            }
            .pickerStyle(.segmented)
            if kind == .match {
                matchFields
            } else {
                playerField(String(localized: "Player name", table: "Sessions.Import"), text: $playerName, identifier: "import.player")
            }
        }
        .jovraCard()
        .disabled(model.isRunning)
    }

    private var matchFields: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            playerField(String(localized: "Player A", table: "Sessions.Import"), text: $playerA, identifier: "import.match.playerA")
            playerField(String(localized: "Player B", table: "Sessions.Import"), text: $playerB, identifier: "import.match.playerB")
            Picker(selection: $format) {
                Text("Choose", tableName: "Sessions.Import").tag(nil as SinglesMatchFormat?)
                Text("Best of one set", tableName: "Sessions.Import").tag(SinglesMatchFormat.bestOfOne as SinglesMatchFormat?)
                Text("Best of three sets", tableName: "Sessions.Import").tag(SinglesMatchFormat.bestOfThree as SinglesMatchFormat?)
            } label: {
                Text("Match format", tableName: "Sessions.Import")
            }.pickerStyle(.menu).frame(minHeight: 52).accessibilityIdentifier("import.match.format")
            Picker(selection: $gameScoring) {
                Text("Choose", tableName: "Sessions.Import").tag(nil as SessionMatchFormatGameScoring?)
                Text("Ad scoring", tableName: "Sessions.Import").tag(SessionMatchFormatGameScoring.ad as SessionMatchFormatGameScoring?)
                Text("No-ad", tableName: "Sessions.Import").tag(SessionMatchFormatGameScoring.noAd as SessionMatchFormatGameScoring?)
            } label: {
                Text("Game scoring", tableName: "Sessions.Import")
            }.pickerStyle(.menu).frame(minHeight: 52).accessibilityIdentifier("import.match.scoring")
            Text("Six-game sets · Seven-point tiebreak at 6–6 · Let serves", tableName: "Sessions.Import")
                .font(.jovraCaption)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            sidePicker(String(localized: "First server", table: "Sessions.Import"), selection: $firstServer, identifier: "import.match.firstServer")
            sidePicker(String(localized: "Player at the near end at the start", table: "Sessions.Import"),
                       selection: $nearPlayer, identifier: "import.match.nearPlayer")
            Toggle(isOn: $containsFullMatch) {
                Text("The video I choose contains every point from the start to the end of the match.", tableName: "Sessions.Import")
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(minHeight: 52).accessibilityIdentifier("import.match.complete")
            Text("Review every point in order to build the score. Import partial footage as practice.", tableName: "Sessions.Import")
                .font(.jovraCaption)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sidePicker(_ title: String, selection: Binding<Side?>, identifier: String) -> some View {
        Picker(selection: selection) {
            Text("Choose", tableName: "Sessions.Import").tag(nil as Side?)
            Text("Player A", tableName: "Sessions.Import").tag(Side.a as Side?)
            Text("Player B", tableName: "Sessions.Import").tag(Side.b as Side?)
        } label: {
            Text(title)
        }.pickerStyle(.menu).frame(minHeight: 52).accessibilityIdentifier(identifier)
    }

    private func playerField(_ title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: Space.half) {
            Text(title).font(.jovraLabel).foregroundStyle(.jovra(.textPrimary))
            JovraTextInput(text: text, title: title, identifier: identifier)
                .padding(.horizontal, Space.x2)
                .background(.jovra(.surfaceSunken), in: RoundedRectangle(cornerRadius: Radius.control))
        }
    }

    // MARK: Choosing

    @ViewBuilder private var chooseSection: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            if case .unavailable = library {
                StateCard(symbol: "externaldrive.badge.exclamationmark",
                          title: String(localized: "Local library unavailable", table: "Sessions.Import"),
                          message: String(localized: "JOVRA couldn't open its library on this iPhone, so nothing can be imported. Restart JOVRA and try again.", table: "Sessions.Import"))
            }
            Button(chooseTitle) { choose() }
                .buttonStyle(JovraButtonStyle(kind: .accent, fullWidth: true))
                .disabled(!canChoose)
                .accessibilityIdentifier("import.choose")
            Text(kind == .practice
                 ? String(localized: "HEVC or H.264 · MOV or MP4 · 24–240 fps · HDR kept. Your original is never changed.", table: "Sessions.Import")
                 : String(localized: "One HEVC or H.264 video with the whole match. Your original is never changed.", table: "Sessions.Import"))
                .font(.jovraCaption)
                .foregroundStyle(.jovra(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            if let pickerIssue {
                Text(pickerIssue)
                    .font(.jovraBody)
                    .foregroundStyle(.jovra(.attentionInk))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("import.issue")
            }
        }
    }

    private var chooseTitle: String {
        switch (source, kind) {
        case (.photos, .practice): String(localized: "Choose videos from Photos", table: "Sessions.Import")
        case (.photos, .match): String(localized: "Choose the match from Photos", table: "Sessions.Import")
        case (_, .practice): String(localized: "Choose videos from Files", table: "Sessions.Import")
        case (_, .match): String(localized: "Choose the match from Files", table: "Sessions.Import")
        }
    }

    private func choose() {
        pickerIssue = nil
        if !launch.importSelection.isEmpty {
            // UI-test seam: the named files stand in for the system picker's selection.
            let selection = SimulatedImportAvailability.selection(launch.importSelection)
            let origin = source.origin ?? .files
            start(selection.urls.map { ImportItem(url: $0, origin: origin) },
                  availability: SimulatedImportAvailability(cloudPaths: selection.cloud))
            return
        }
        if source == .photos { showPhotos = true } else { showFiles = true }
    }

    private func receivePhotos(_ picked: [PhotosPickerItem]) {
        guard !picked.isEmpty else { return }
        photoSelection = []
        model.beginReceiving(picked.count) {
            var items: [ImportItem] = [], failures = 0
            for item in picked {
                // "Cancel import" cancels this hand-over; `start` then removes what already arrived.
                if Task.isCancelled { break }
                do {
                    guard let video = try await item.loadTransferable(type: PickedVideo.self) else { failures += 1; continue }
                    items.append(ImportItem(url: video.url, origin: .photos))
                } catch {
                    failures += 1
                }
            }
            if items.isEmpty {
                model.finishReceiving(failures: failures)
            } else {
                start(items, failedBeforeCopy: failures)
            }
        }
    }

    private func start(_ items: [ImportItem], failedBeforeCopy: Int = 0,
                       availability: any ImportSourceAvailability = SystemImportSourceAvailability()) {
        guard case .ready(let library) = library, !items.isEmpty, let intent else { return }
        if intent.isMatch { containsFullMatch = false }
        let inbox = items.map(\.url)
        model.start(items, intent: intent, library: library, availability: availability, failedBeforeCopy: failedBeforeCopy,
                    cleanup: { ImportInbox.remove(inbox) }) { single in
            if let single { router.present(.processing(single)) }
        }
    }

    private var intent: ImportIntent? {
        switch kind {
        case .practice: return .practice(playerName: playerName)
        case .match: return matchSetup.map(ImportIntent.match)
        }
    }

    private var matchSetup: FilesImportMatchSetup? {
        guard let format, let gameScoring, let firstServer, let nearPlayer else { return nil }
        return .init(playerA: playerA, playerB: playerB, format: format, gameScoring: gameScoring,
                     firstServer: firstServer, nearPlayer: nearPlayer, containsFullMatch: containsFullMatch)
    }

    private var canChoose: Bool {
        guard case .ready = library, !model.isRunning, source != .drive else { return false }
        if kind == .match { return matchSetup?.isValid == true }
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.unicodeScalars.count <= 60
    }

    // MARK: Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            SectionHeader(title: String(localized: "Your imports", table: "Sessions.Import"))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(Color.jovra(.separator)) }
                    ImportResultRow(row: row,
                                    viewSession: { router.present(.replay(.init(session: $0, point: nil, filter: .all))) },
                                    rotate: { act { await model.rotate(row.id, library: $0) } },
                                    openExisting: { act { library in
                                        if let id = await model.openExisting(row.id, library: library) {
                                            router.present(.replay(.init(session: id, point: nil, filter: .all)))
                                        }
                                    } },
                                    importAnyway: { act { await model.importAnyway(row.id, library: $0) } })
                }
            }
            .jovraCard()
            if model.isRunning {
                Button(model.isCancelling ? String(localized: "Cancelling import…", table: "Sessions.Import")
                                          : String(localized: "Cancel import", table: "Sessions.Import")) { model.cancel() }
                    .buttonStyle(.jovraSecondary)
                    .disabled(model.isCancelling)
                    .accessibilityIdentifier("import.cancel")
            } else if model.rows.contains(where: { if case .saved = $0.status { true } else { false } }) {
                InfoCard(symbol: "checkmark.shield", title: String(localized: "Your videos are safe on this iPhone.", table: "Sessions.Import"),
                         message: String(localized: "You can leave this screen. Your selected originals were not changed.", table: "Sessions.Import"),
                         tone: .positive)
                    .accessibilityIdentifier("import.safe")
            }
        }
    }

    private func act(_ work: @escaping @MainActor (LocalCaptureLibrary) async -> Void) {
        guard case .ready(let library) = library else { return }
        Task { await work(library) }
    }
}
