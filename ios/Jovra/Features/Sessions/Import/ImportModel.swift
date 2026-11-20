import Foundation
import JovraCore
import JovraMedia
import Observation

/// The per-file state of one import batch on "Bring your game in" (S07). Rows mirror `ImportPipeline`'s
/// phases and outcomes; duplicate choices, rotation and cancellation act on one row at a time.
@MainActor @Observable
final class ImportModel {
    struct SavedVideo: Equatable {
        var session: SessionID
        var title: String
        var durationMs: Int?
        var shortSide: Int
        var recordedAt: Date?
        var source: SessionRecordingImportSource?
        var rotationDegrees: Int
        /// Quarter turns the player added on this screen (shown as "Turned 90° clockwise").
        var manualQuarterTurns = 0
    }

    enum Status: Equatable {
        /// A Photos item is still being handed over by the system picker (it may be downloading from iCloud Photos).
        case receiving
        case queued
        case waitingForDownload
        case copying
        case saved(SavedVideo)
        case duplicate(FilesImportDuplicate, existingTitle: String?)
        /// A duplicate or rotation action is running for this row.
        case working
        case unsupported(ImportUnsupportedReason)
        case failed(ImportFailure)
        case cancelled
        /// The player chose "Open existing"; the held copy is gone.
        case openedExisting(SessionID)
        /// A duplicate choice or rotation failed; nothing was published or changed.
        case actionFailed
    }

    struct Row: Identifiable, Equatable {
        let id: UUID
        var name: String
        var status: Status
    }

    private(set) var rows: [Row] = []
    private(set) var isRunning = false
    private(set) var isCancelling = false
    /// Photos items are still being handed over; `task` is the hand-over, not the pipeline.
    private var isReceiving = false
    private var task: Task<Void, Never>?

    /// Called once for every session this screen saves (an import or Import anyway), before its row shows it.
    /// The screen passes T27's processing queue; tests pass a recorder.
    private let onSaved: @MainActor (SessionID) async -> Void

    init(onSaved: @escaping @MainActor (SessionID) async -> Void = { _ in }) {
        self.onSaved = onSaved
    }

    var hasRows: Bool { !rows.isEmpty }

    /// Rows still waiting for the player (a held duplicate) or for the pipeline.
    var needsAttention: Bool {
        rows.contains { if case .duplicate = $0.status { true } else { false } }
    }

    /// Show rows for Photos items while the picker hands their files over. `handOver` loads them and then calls
    /// `start` or `finishReceiving`; "Cancel import" cancels it (an iCloud Photos download can take minutes).
    func beginReceiving(_ count: Int, handOver: @escaping @MainActor () async -> Void) {
        guard !isRunning else { return }
        rows = (0..<count).map { Row(id: UUID(), name: String(localized: "Video \($0 + 1)", table: "Sessions.Import"), status: .receiving) }
        isRunning = true
        isCancelling = false
        isReceiving = true
        task = Task { await handOver() }
    }

    /// Run the pipeline. `onFinished` receives the one saved session when a single video imported cleanly,
    /// so the screen can present its processing route.
    func start(_ items: [ImportItem], intent: ImportIntent, library: LocalCaptureLibrary,
               availability: any ImportSourceAvailability, failedBeforeCopy: Int = 0,
               cleanup: @escaping @Sendable () -> Void = {}, onFinished: @escaping (SessionID?) -> Void) {
        if isReceiving, isCancelling {
            // Cancelled during the hand-over: nothing is imported and the received copies are removed.
            cleanup()
            finishCancelledHandOver()
            onFinished(nil)
            return
        }
        if !isReceiving { task?.cancel() }
        isReceiving = false
        rows = items.map { Row(id: $0.id, name: $0.displayName, status: .queued) }
            + Self.failedRows(failedBeforeCopy, startingAt: items.count)
        isRunning = true
        isCancelling = false
        // The import holds the model until it finishes, so late results still reach their rows.
        task = Task { [self] in
            let report = await library.runImport(items, intent: intent, availability: availability) { id, phase in
                await self.apply(phase, to: id, library: library)
            }
            cleanup()
            isRunning = false
            isCancelling = false
            task = nil
            let saved = report.importedSessionIDs
            onFinished(rows.count == 1 && saved.count == 1 ? SessionID(rawValue: saved[0]) : nil)
        }
    }

    /// Picker failures before any copy (Photos could not hand a file over).
    func finishReceiving(failures: Int) {
        guard !(isReceiving && isCancelling) else { return finishCancelledHandOver() }
        rows = Self.failedRows(failures, startingAt: 0)
        isRunning = false
        isCancelling = false
        isReceiving = false
        task = nil
    }

    private func finishCancelledHandOver() {
        rows = rows.map { Row(id: $0.id, name: $0.name, status: .cancelled) }
        isRunning = false
        isCancelling = false
        isReceiving = false
        task = nil
    }

    private static func failedRows(_ count: Int, startingAt offset: Int) -> [Row] {
        (0..<count).map { Row(id: UUID(), name: String(localized: "Video \(offset + $0 + 1)", table: "Sessions.Import"), status: .failed(.unreadable)) }
    }

    func cancel() {
        guard isRunning else { return }
        isCancelling = true
        task?.cancel()
    }

    func importAnyway(_ rowID: UUID, library: LocalCaptureLibrary) async {
        guard let index = rows.firstIndex(where: { $0.id == rowID }), case .duplicate(let duplicate, _) = rows[index].status else { return }
        rows[index].status = .working
        do {
            let id = try await library.importAnyway(duplicate)
            await onSaved(id)
            await setStatus(rowID, to: (try? await saved(id, library: library)).map(Status.saved) ?? .actionFailed)
        } catch {
            setStatus(rowID, to: .actionFailed)
        }
    }

    func openExisting(_ rowID: UUID, library: LocalCaptureLibrary) async -> SessionID? {
        guard let index = rows.firstIndex(where: { $0.id == rowID }), case .duplicate(let duplicate, _) = rows[index].status else { return nil }
        rows[index].status = .working
        do {
            let id = try await library.openExisting(duplicate)
            setStatus(rowID, to: .openedExisting(id))
            return id
        } catch {
            setStatus(rowID, to: .actionFailed)
            return nil
        }
    }

    func rotate(_ rowID: UUID, library: LocalCaptureLibrary) async {
        guard let index = rows.firstIndex(where: { $0.id == rowID }), case .saved(var video) = rows[index].status else { return }
        do {
            video.rotationDegrees = try await library.rotateImport(video.session).rawValue
            video.manualQuarterTurns = (video.manualQuarterTurns + 1) % 4
            setStatus(rowID, to: .saved(video))
        } catch {
            setStatus(rowID, to: .actionFailed)
        }
    }

    /// Leaving the screen never publishes a held duplicate; its private copy is removed.
    func discardHeldCopies(library: LocalCaptureLibrary) async {
        task?.cancel()
        for row in rows {
            if case .duplicate(let duplicate, _) = row.status { await library.discardHeldImport(duplicate) }
        }
    }

    private func apply(_ phase: ImportItemPhase, to id: UUID, library: LocalCaptureLibrary) async {
        switch phase {
        case .queued: setStatus(id, to: .queued)
        case .waitingForDownload: setStatus(id, to: .waitingForDownload)
        case .copying: setStatus(id, to: .copying)
        case .finished(let outcome):
            switch outcome {
            case .imported(let session):
                await onSaved(SessionID(rawValue: session))
                setStatus(id, to: (try? await saved(SessionID(rawValue: session), library: library)).map(Status.saved) ?? .actionFailed)
            case .duplicate(let duplicate):
                let title = try? await library.load(SessionID(rawValue: duplicate.sessionID)).title
                setStatus(id, to: .duplicate(duplicate, existingTitle: title))
            case .unsupported(let reason): setStatus(id, to: .unsupported(reason))
            case .failed(let failure): setStatus(id, to: .failed(failure))
            case .cancelled: setStatus(id, to: .cancelled)
            }
        }
    }

    private func setStatus(_ id: UUID, to status: Status) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].status = status
    }

    private func saved(_ id: SessionID, library: LocalCaptureLibrary) async throws -> SavedVideo {
        let document = try await library.load(id)
        let segment = document.recording.segments.first
        return SavedVideo(session: id, title: document.title ?? "", durationMs: document.recording.durationMs,
                          shortSide: min(segment?.width ?? 0, segment?.height ?? 0),
                          recordedAt: document.recording.startedAt.flatMap { try? Date($0, strategy: .iso8601) },
                          source: document.recording.importSource, rotationDegrees: segment?.rotationDegrees?.rawValue ?? 0)
    }
}
