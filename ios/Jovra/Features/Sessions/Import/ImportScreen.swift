import JovraMedia
import SwiftUI
import UniformTypeIdentifiers

struct ImportScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(\.localCaptureLibrary) private var library
    @State private var playerName = ""
    @State private var showPicker = false
    @State private var selection: URL?
    @State private var imported: SessionID?
    @State private var issue: String?

    var body: some View {
        JovraScreen(title: String(localized: "Import videos", table: "App"),
                    subtitle: String(localized: "Save a local practice video from Files.", table: "Sessions.Import")) {
            Button(String(localized: "Back to sessions", table: "Sessions.Import")) { dismiss() }
                .buttonStyle(.jovraSecondary).accessibilityIdentifier("import.back")
            Text("Choose one H.264 or HEVC video in MOV or MP4 format. JOVRA keeps your selected file unchanged.", tableName: "Sessions.Import")
                .fixedSize(horizontal: false, vertical: true)
            Text("Player name", tableName: "Sessions.Import").font(.jovraLabel)
            JovraTextInput(text: $playerName, title: String(localized: "Player name", table: "Sessions.Import"),
                          identifier: "import.player")
                .padding(.horizontal, Space.x2)
                .background(.jovra(.surface), in: RoundedRectangle(cornerRadius: Radius.card))
                .disabled(selection != nil)
            if case .unavailable = library {
                Text("Local library unavailable", tableName: "Sessions.Library")
            }
            Button(String(localized: "Choose video from Files", table: "Sessions.Import")) { showPicker = true }
                .buttonStyle(.jovraAccent).disabled(!canChoose).accessibilityIdentifier("import.choose")
            if selection != nil {
                ProgressView(String(localized: "Copying and checking the video…", table: "Sessions.Import"))
                Button(String(localized: "Cancel import", table: "Sessions.Import")) { selection = nil }
                    .buttonStyle(.jovraSecondary)
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
                issue = nil; imported = nil; selection = url
            } else if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                issue = String(localized: "Could not open that file.", table: "Sessions.Import")
            }
        }
        .task(id: selection) {
            guard let selection, case .ready(let library) = library else { return }
            do {
                let id = try await library.importFile(selection, playerName: playerName)
                guard !Task.isCancelled else { return }
                imported = id
            } catch {
                guard !Task.isCancelled else { return }
                issue = String(localized: "Import could not be confirmed. Check your library before trying again. Your selected file was not changed.", table: "Sessions.Import")
            }
            self.selection = nil
        }
    }

    private var canChoose: Bool {
        guard case .ready = library, selection == nil else { return false }
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.unicodeScalars.count <= 60
    }
}
