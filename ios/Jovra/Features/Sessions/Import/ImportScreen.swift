import JovraCore
import JovraMedia
import SwiftUI
import UniformTypeIdentifiers

struct ImportScreen: View {
    private enum Kind: Hashable { case practice, match }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(\.localCaptureLibrary) private var library
    @State private var kind = Kind.practice
    @State private var playerName = ""
    @State private var playerA = ""
    @State private var playerB = ""
    @State private var format: SinglesMatchFormat?
    @State private var gameScoring: SessionMatchFormatGameScoring?
    @State private var firstServer: Side?
    @State private var nearPlayer: Side?
    @State private var containsFullMatch = false
    @State private var showPicker = false
    @State private var pickerRequest: FilesImportRequest?
    @State private var duplicate: ImportDuplicateDecision?
    @State private var openingExisting = false
    @State private var work: Task<Void, Never>?
    @State private var cancelling = false
    @State private var imported: SessionID?
    @State private var issue: String?

    var body: some View {
        JovraScreen(title: String(localized: "Import videos", table: "App"),
                    subtitle: String(localized: "Save a local practice or match video from Files.", table: "Sessions.Import")) {
            Button(String(localized: "Back to sessions", table: "Sessions.Import")) { dismiss() }
                .buttonStyle(.jovraSecondary).accessibilityIdentifier("import.back")
            Text("Choose one H.264 or HEVC video in MOV or MP4 format. JOVRA keeps your selected file unchanged.", tableName: "Sessions.Import")
                .fixedSize(horizontal: false, vertical: true)
            if let duplicate {
                duplicateActions(duplicate).disabled(work != nil || pickerRequest != nil)
            } else {
                importFields.disabled(work != nil || pickerRequest != nil)
                if case .unavailable = library {
                    Text("Local library unavailable", tableName: "Sessions.Library")
                }
                Button(String(localized: "Choose video from Files", table: "Sessions.Import")) {
                    if let intent = importIntent { presentPicker(FilesImportRequest(intent: intent)) }
                }.buttonStyle(.jovraAccent).disabled(!canChoose).accessibilityIdentifier("import.choose")
            }
            if work != nil {
                ProgressView(progressTitle)
                Button(openingExisting ? String(localized: "Cancel", table: "Sessions.Import") :
                       String(localized: "Cancel import", table: "Sessions.Import")) {
                    cancelling = true
                    work?.cancel()
                }.buttonStyle(.jovraSecondary).disabled(cancelling)
            }
            if let issue { Text(issue).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("import.issue") }
            if let imported {
                Text("Video saved in your library", tableName: "Sessions.Import").accessibilityIdentifier("import.saved")
                Button(String(localized: "Open video", table: "Sessions.Import")) {
                    router.present(.replay(.init(session: imported, point: nil, filter: .all)))
                }.buttonStyle(.jovraSecondary)
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.movie], allowsMultipleSelection: false,
                      onCompletion: finishPicker, onCancellation: { pickerRequest = nil })
        .onDisappear { work?.cancel() }
    }

    private var importFields: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Picker(selection: $kind) {
                Text("Practice", tableName: "Sessions.Import").tag(Kind.practice)
                Text("Singles match", tableName: "Sessions.Import").tag(Kind.match)
            } label: {
                Text("Import as", tableName: "Sessions.Import")
            }.pickerStyle(.segmented)
            if kind == .match {
                matchFields
            } else {
                playerField(String(localized: "Player name", table: "Sessions.Import"),
                            text: $playerName, identifier: "import.player")
            }
        }
    }

    private func duplicateActions(_ decision: ImportDuplicateDecision) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            if let existing = decision.existing {
                Text("This video is already in your library", tableName: "Sessions.Import")
                    .font(.headline).accessibilityAddTraits(.isHeader).accessibilityIdentifier("import.duplicate.title")
                Text("Open the existing session, or select the same video again to save a separate copy.", tableName: "Sessions.Import")
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Open Existing", table: "Sessions.Import")) {
                    openExisting(existing)
                }.buttonStyle(.jovraAccent).accessibilityIdentifier("import.duplicate.open")
            } else {
                Text("The existing copy could not be verified", tableName: "Sessions.Import")
                    .font(.headline).accessibilityAddTraits(.isHeader).accessibilityIdentifier("import.duplicate.title")
                Text("Select the same video again to save a separate copy.", tableName: "Sessions.Import")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if decision.intent.isMatch {
                Toggle(isOn: Binding(get: { duplicate?.confirmsFullMatch ?? false },
                                     set: { duplicate?.confirmsFullMatch = $0 })) {
                    Text("I confirm the video I select again contains every point of the match.", tableName: "Sessions.Import")
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(minHeight: 52).accessibilityIdentifier("import.duplicate.complete")
            }
            Button(String(localized: "Import Anyway", table: "Sessions.Import")) {
                if let request = duplicate?.makeRetryRequest() { presentPicker(request) }
            }.buttonStyle(.jovraSecondary).disabled(!decision.canRetry).accessibilityIdentifier("import.duplicate.retry")
            Button(String(localized: "Cancel", table: "Sessions.Import")) {
                duplicate = nil
                issue = nil
            }.buttonStyle(.jovraSecondary).accessibilityIdentifier("import.duplicate.cancel")
        }
    }

    private var progressTitle: String {
        if openingExisting { return String(localized: "Checking the existing video…", table: "Sessions.Import") }
        if cancelling { return String(localized: "Cancelling import…", table: "Sessions.Import") }
        return String(localized: "Copying and checking the video…", table: "Sessions.Import")
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
                .fixedSize(horizontal: false, vertical: true)
            sidePicker(String(localized: "First server", table: "Sessions.Import"),
                       selection: $firstServer, identifier: "import.match.firstServer")
            sidePicker(String(localized: "Player at the near end at the start", table: "Sessions.Import"),
                       selection: $nearPlayer, identifier: "import.match.nearPlayer")
            Toggle(isOn: $containsFullMatch) {
                Text("The video I choose contains every point from the start to the end of the match.", tableName: "Sessions.Import")
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(minHeight: 52).accessibilityIdentifier("import.match.complete")
            Text("Review every point in order to build the score. Import partial footage as practice.", tableName: "Sessions.Import")
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
            Text(title).font(.jovraLabel)
            JovraTextInput(text: text, title: title, identifier: identifier)
                .padding(.horizontal, Space.x2)
                .background(.jovra(.surface), in: RoundedRectangle(cornerRadius: Radius.card))
        }
    }

    private var matchSetup: FilesImportMatchSetup? {
        guard let format, let gameScoring, let firstServer, let nearPlayer else { return nil }
        return .init(playerA: playerA, playerB: playerB, format: format, gameScoring: gameScoring,
                     firstServer: firstServer, nearPlayer: nearPlayer, containsFullMatch: containsFullMatch)
    }

    private func presentPicker(_ request: FilesImportRequest) {
        guard work == nil, pickerRequest == nil, case .ready = library else { return }
        issue = nil
        pickerRequest = request
        showPicker = true
    }

    private func finishPicker(_ result: Result<[URL], any Error>) {
        guard let request = pickerRequest else { return }
        pickerRequest = nil
        switch result {
        case .success(let urls) where urls.count == 1:
            beginImport(urls[0], request: request)
        case .failure(let error) where (error as? CocoaError)?.code == .userCancelled:
            break
        default:
            issue = String(localized: "Could not open that file.", table: "Sessions.Import")
        }
    }

    private func beginImport(_ url: URL, request: FilesImportRequest) {
        guard work == nil, case .ready(let library) = library else { return }
        issue = nil; imported = nil
        if request.intent.isMatch { containsFullMatch = false }
        work = Task {
            defer { work = nil; cancelling = false }
            await completeFilesImport {
                switch request.intent {
                case .match(let setup):
                    return try await library.importMatch(url, setup: setup, importingAgain: request.duplicatePermission)
                case .practice(let name):
                    return try await library.importFile(url, playerName: name, importingAgain: request.duplicatePermission)
                }
            } onPublished: { id in
                imported = id
                duplicate = nil
            } onFailure: { error in
                presentImportFailure(error, intent: request.intent)
            }
        }
    }

    private func presentImportFailure(_ error: any Error, intent: FilesImportIntent) {
        switch error as? FilesImportError {
        case .duplicate(let existing):
            duplicate = .init(intent: intent, fingerprint: existing.fingerprint, existing: existing)
        case .duplicateUnverified(let fingerprint):
            duplicate = .init(intent: intent, fingerprint: fingerprint, existing: nil)
        case .differentDuplicateSelection:
            issue = String(localized: "That is a different video. Select the same video or cancel to start a new import.", table: "Sessions.Import")
        default:
            issue = String(localized: "Import could not be confirmed. Check your library before trying again. Your selected file was not changed.", table: "Sessions.Import")
        }
    }

    private func openExisting(_ existing: FilesImportDuplicate) {
        guard work == nil, pickerRequest == nil, case .ready(let library) = library else { return }
        issue = nil
        openingExisting = true
        work = Task {
            defer { work = nil; openingExisting = false; cancelling = false }
            do {
                let id = try await library.verifyExistingDuplicate(existing)
                try Task.checkCancellation()
                duplicate = nil
                router.present(.replay(.init(session: id, point: nil, filter: .all)))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                duplicate?.existing = nil
                duplicate?.confirmsFullMatch = false
            }
        }
    }

    private var importIntent: FilesImportIntent? {
        if kind == .match {
            guard let setup = matchSetup, setup.isValid else { return nil }
            return .match(setup)
        }
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.unicodeScalars.count <= 60 else { return nil }
        return .practice(playerName: name)
    }

    private var canChoose: Bool {
        guard case .ready = library, work == nil, pickerRequest == nil else { return false }
        return importIntent != nil
    }
}
