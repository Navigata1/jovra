import JovraMedia
import SwiftUI
import UniformTypeIdentifiers

struct ImportScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(\.localCaptureLibrary) private var library
    @State private var playerName = ""
    @State private var showPicker = false
    @State private var work: Task<Void, Never>?
    @State private var cancelling = false
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
                .disabled(work != nil)
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

    private func beginImport(_ url: URL) {
        guard work == nil, case .ready(let library) = library else { return }
        issue = nil; imported = nil
        let name = playerName
        work = Task {
            defer { work = nil; cancelling = false }
            do {
                // If publication completed before cancellation, acknowledge the actual saved session.
                imported = try await library.importFile(url, playerName: name)
            } catch is CancellationError {
                return
            } catch {
                issue = String(localized: "Import could not be confirmed. Check your library before trying again. Your selected file was not changed.", table: "Sessions.Import")
            }
        }
    }

    private var canChoose: Bool {
        guard case .ready = library, work == nil else { return false }
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.unicodeScalars.count <= 60
    }
}
