import Foundation
import JovraCore

/// One picked video, copied out of the picker's temporary location before the handler returns.
public struct ImportItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let origin: SessionRecordingImportSource
    /// The name the player recognises (the picked file's name).
    public let displayName: String

    public init(id: UUID = UUID(), url: URL, origin: SessionRecordingImportSource, displayName: String? = nil) {
        self.id = id
        self.url = url
        self.origin = origin
        self.displayName = displayName ?? url.lastPathComponent
    }
}

/// Why an item failed for a reason other than its format.
public enum ImportFailure: Equatable, Sendable {
    /// The source could not be read, changed while copying, or is a link.
    case unreadable
    /// A matching session exists but its original no longer verifies, so it cannot be offered to open.
    case duplicateUnverified
    /// The player or match details were not valid.
    case invalidSetup
    /// A singles match imports exactly one video.
    case oneMatchPerImport
    /// The copy could not be saved (storage or filesystem).
    case couldNotSave
}

/// The per-file result the spec names: success, duplicate, unsupported(reason), failed(reason), cancelled.
public enum ImportItemOutcome: Equatable, Sendable {
    case imported(sessionID: String)
    /// A verified duplicate; its staged copy is held for "Import anyway" until resolved or discarded.
    case duplicate(FilesImportDuplicate)
    case unsupported(ImportUnsupportedReason)
    case failed(ImportFailure)
    case cancelled
}

public enum ImportItemPhase: Equatable, Sendable {
    case queued
    /// A cloud-only item; the pipeline asked the provider to download it and waits (story 111).
    case waitingForDownload
    case copying
    case finished(ImportItemOutcome)
}

public struct ImportItemResult: Equatable, Sendable {
    public let item: ImportItem
    public let outcome: ImportItemOutcome
}

public struct ImportReport: Equatable, Sendable {
    public let results: [ImportItemResult]

    public var importedSessionIDs: [String] {
        results.compactMap { if case .imported(let id) = $0.outcome { id } else { nil } }
    }
}

/// `import(items) -> ImportReport` (spec, ImportPipeline). Items run one at a time so one bad file never fails
/// the batch; each copies into private staging, is probed and validated, then publishes atomically or is removed.
/// Cancelling the task removes the current partial copy and reports every unfinished item as cancelled.
public struct ImportPipeline: Sendable {
    private let service: FilesImportService
    private let availability: any ImportSourceAvailability
    private let downloadPollInterval: Duration

    public init(store: SessionStore, availability: any ImportSourceAvailability = SystemImportSourceAvailability(),
                downloadPollInterval: Duration = .milliseconds(500)) {
        service = FilesImportService(store: store)
        self.availability = availability
        self.downloadPollInterval = downloadPollInterval
    }

    public func run(_ items: [ImportItem], intent: ImportIntent,
                    progress: @escaping @Sendable (ImportItem.ID, ImportItemPhase) async -> Void = { _, _ in }) async -> ImportReport {
        if intent.isMatch, items.count > 1 {
            let results = items.map { ImportItemResult(item: $0, outcome: .failed(.oneMatchPerImport)) }
            for result in results { await progress(result.item.id, .finished(result.outcome)) }
            return ImportReport(results: results)
        }
        var results: [ImportItemResult] = []
        for item in items {
            let outcome = Task.isCancelled ? .cancelled : await importOne(item, intent: intent, progress: progress)
            results.append(ImportItemResult(item: item, outcome: outcome))
            await progress(item.id, .finished(outcome))
        }
        return ImportReport(results: results)
    }

    /// "Import anyway": publish the held copy as a second, independent session.
    public func importAnyway(_ duplicate: FilesImportDuplicate) async throws -> String {
        try await service.importHeldCopy(duplicate)
    }

    /// "Open existing": verify the existing original again, then drop the held copy.
    public func openExisting(_ duplicate: FilesImportDuplicate) async throws -> String {
        do {
            let id = try await service.verifyExistingDuplicate(duplicate)
            await service.discardHeldCopy(duplicate)
            return id
        } catch {
            await service.discardHeldCopy(duplicate)
            throw error
        }
    }

    /// The player left without choosing: nothing is published and the held copy is removed.
    public func discard(_ duplicate: FilesImportDuplicate) async {
        await service.discardHeldCopy(duplicate)
    }

    private func importOne(_ item: ImportItem, intent: ImportIntent,
                           progress: @Sendable (ImportItem.ID, ImportItemPhase) async -> Void) async -> ImportItemOutcome {
        do {
            if let reason = ImportValidation.container(of: item.url) { return .unsupported(reason) }
            if await availability.status(of: item.url) == .notDownloaded {
                await progress(item.id, .waitingForDownload)
                await availability.requestDownload(of: item.url)
                while await availability.status(of: item.url) == .notDownloaded {
                    try await Task.sleep(for: downloadPollInterval)
                }
            }
            try Task.checkCancellation()
            await progress(item.id, .copying)
            let id = try await service.importItem(item.url, intent: intent, origin: item.origin, holdingDuplicate: true)
            return .imported(sessionID: id)
        } catch {
            return Self.outcome(for: error)
        }
    }

    static func outcome(for error: any Error) -> ImportItemOutcome {
        switch error {
        case is CancellationError: return .cancelled
        case FilesImportError.unsupported(let reason): return .unsupported(reason)
        case FilesImportError.duplicate(let duplicate): return .duplicate(duplicate)
        case FilesImportError.duplicateUnverified: return .failed(.duplicateUnverified)
        case FilesImportError.invalidPlayer, FilesImportError.invalidMatchSetup: return .failed(.invalidSetup)
        case FilesImportError.unreadableSource, is RecoveryError: return .failed(.unreadable)
        default: return .failed(.couldNotSave)
        }
    }
}
