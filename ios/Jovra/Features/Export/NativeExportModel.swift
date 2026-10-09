import Foundation
import JovraCore
import JovraMedia
import Observation

/// Done means the shared store acknowledged the four durable files and their historical version.
@MainActor @Observable
final class NativeExportModel {
    private(set) var document: SessionDocument?
    private(set) var selectedSegmentID: String?
    private(set) var package: LocalExportPackage?
    private(set) var currentVersion: Int?
    private(set) var isWorking = false
    private(set) var error: String?
    var fromText = ""
    var toText = ""
    var includeAudio = false
    @ObservationIgnored private var library: LocalCaptureLibrary?
    @ObservationIgnored private var session: SessionID?
    @ObservationIgnored private var generation = UUID()

    var segments: [SessionSegment] {
        document?.recording.segments.filter {
            $0.finalized && $0.startMs >= 0 && $0.durationMs > 0 && !$0.startMs.addingReportingOverflow($0.durationMs).overflow
        }.sorted { $0.index < $1.index } ?? []
    }
    var isStale: Bool? {
        guard let package, let currentVersion else { return nil }
        return currentVersion > package.eventLogVersion
    }
    var canExport: Bool { !isWorking && document?.recording.mediaAvailable == true && selectedSegmentID != nil }

    func open(library: LocalCaptureLibrary, session: SessionID) async {
        generation = UUID(); let token = generation
        self.library = library; self.session = session
        document = nil; selectedSegmentID = nil; package = nil; currentVersion = nil; error = nil
        fromText = ""; toText = ""; includeAudio = false
        isWorking = true
        defer { if generation == token { isWorking = false } }
        do {
            let loaded = try await library.load(session)
            guard generation == token else { return }
            document = loaded
            currentVersion = loaded.match?.log.map(\.seq).max() ?? 0
            if let first = segments.first, loaded.recording.mediaAvailable { choose(first.id) }
            else { error = String(localized: "No playable original is available for this export.", table: "Export") }
        } catch {
            if generation == token { self.error = String(localized: "Couldn't open this session for export. Reopen the session to try again.", table: "Export") }
        }
    }

    func select(_ id: String) {
        guard !isWorking else { return }
        choose(id)
    }

    private func choose(_ id: String) {
        guard let segment = segments.first(where: { $0.id == id }) else { return }
        selectedSegmentID = id; package = nil; error = nil
        fromText = JovraFormat.count(segment.startMs)
        toText = JovraFormat.count(segment.startMs + segment.durationMs)
    }

    func export() async {
        guard canExport, let library, let session else { return }
        package = nil; error = nil
        guard let from = milliseconds(fromText), let to = milliseconds(toText), to > from,
              let segment = segments.first(where: { $0.id == selectedSegmentID }),
              from >= segment.startMs, to - segment.startMs <= segment.durationMs else {
            error = String(localized: "Choose a start and end inside one complete segment.", table: "Export"); return
        }
        let token = generation
        isWorking = true
        defer { if generation == token { isWorking = false } }
        do {
            let result = try await library.exportClip(session, range: .init(fromMs: from, toMs: to), includeAudio: includeAudio)
            guard generation == token else { return }
            package = result
            await refreshCurrentVersion()
        } catch {
            if generation == token { self.error = String(localized: "Couldn't confirm the export was saved. Reopen this session before trying again.", table: "Export") }
        }
    }

    func refreshCurrentVersion() async {
        guard let library, let session else { return }
        let token = generation
        do {
            let latest = try await library.load(session)
            if generation == token { currentVersion = latest.match?.log.map(\.seq).max() ?? 0 }
        } catch { if generation == token { currentVersion = nil } }
    }

    private func milliseconds(_ text: String) -> Int? {
        let formatter = NumberFormatter(); formatter.locale = .autoupdatingCurrent
        let normalized = text.replacingOccurrences(of: formatter.groupingSeparator ?? ",", with: "")
        let digits = normalized.compactMap(\.wholeNumberValue)
        guard !digits.isEmpty, digits.count == normalized.count else { return nil }
        return Int(digits.map(String.init).joined())
    }
}
