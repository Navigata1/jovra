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
            }.disabled(work != nil)
            if case .unavailable = library {
                Text("Local library unavailable", tableName: "Sessions.Library")
            }
            Button(String(localized: "Choose video from Files", table: "Sessions.Import")) { showPicker = true }
                .buttonStyle(.jovraAccent).disabled(!canChoose).accessibilityIdentifier("import.choose")
            if work != nil {
                ProgressView(cancelling ? String(localized: "Cancelling import…", table: "Sessions.Import") :
                    String(localized: "Copying and checking the video…", table: "Sessions.Import"))
                Button(String(localized: "Cancel import", table: "Sessions.Import")) {
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
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.movie]) { result in
            if case .success(let url) = result {
                beginImport(url)
            } else if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                issue = String(localized: "Could not open that file.", table: "Sessions.Import")
            }
        }
        .onDisappear { work?.cancel() }
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

    private func beginImport(_ url: URL) {
        guard canChoose, case .ready(let library) = library else { return }
        issue = nil; imported = nil
        let name = playerName
        let setup = kind == .match ? matchSetup : nil
        if setup != nil { containsFullMatch = false }
        work = Task {
            defer { work = nil; cancelling = false }
            do {
                // If publication completed before cancellation, acknowledge the actual saved session.
                if let setup {
                    imported = try await library.importMatch(url, setup: setup)
                } else {
                    imported = try await library.importFile(url, playerName: name)
                }
            } catch is CancellationError {
                return
            } catch {
                issue = String(localized: "Import could not be confirmed. Check your library before trying again. Your selected file was not changed.", table: "Sessions.Import")
            }
        }
    }

    private var canChoose: Bool {
        guard case .ready = library, work == nil else { return false }
        if kind == .match { return matchSetup?.isValid == true }
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.unicodeScalars.count <= 60
    }
}
