import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum SessionStoreError: Error, Equatable, Sendable {
    case invalidID, unsafePath, alreadyExists, notFound, invalidEvents, noMatch, invalidCapture, invalidExports
    case confirmationRequired, unsupportedMigration, renameFailed(Int32), durabilityUnconfirmed(Int32)
}

public enum SessionFacet: Sendable {
    case original(SessionOriginalState)
    case analysis(SessionAnalysis)
    case review(SessionReview)
    case archive(SessionArchiveState)
}

public enum SessionWriteCheckpoint: Sendable {
    case temporaryFileFlushed(URL)
    case documentRenamed(URL)
}

public struct SessionQuery: Sendable {
    public var search: String
    public var kind: SessionDocumentSessionKind?
    public var sample: Bool?
    public var original: SessionOriginalStateState?
    public var analysis: SessionAnalysisState?
    public var review: SessionReviewState?
    public var archive: SessionArchiveStateState?
    public init(search: String = "", kind: SessionDocumentSessionKind? = nil, sample: Bool? = nil,
                original: SessionOriginalStateState? = nil, analysis: SessionAnalysisState? = nil,
                review: SessionReviewState? = nil, archive: SessionArchiveStateState? = nil) {
        self.search = search; self.kind = kind; self.sample = sample; self.original = original
        self.analysis = analysis; self.review = review; self.archive = archive
    }
}

public struct SessionSummary: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let createdAt: String
    public let kind: SessionDocumentSessionKind
    public let players: [SessionPlayer]
    public let sides: SessionSides?
    public let hasMatch: Bool
    public let sample: Bool
    public let notes: String?
    public let original: SessionOriginalState?
    public let analysis: SessionAnalysis?
    public let review: SessionReview?
    public let archive: SessionArchiveState
    init(_ value: SessionDocument) {
        id = value.id; title = value.title; createdAt = value.createdAt; kind = value.sessionKind
        players = value.players; sides = value.sides; hasMatch = value.match != nil
        sample = value.sample != nil; notes = value.notes
        original = value.original; analysis = value.analysis; review = value.review; archive = value.archive
    }
}

public struct QuarantinedSession: Codable, Equatable, Sendable {
    public let sessionID: String
    public let reason: String
    public let folderName: String
}

/// Synchronous filesystem transactions deliberately contain no suspension point. All
/// writers must share this actor: its document is authoritative, never the library index.
public actor SessionStore {
    private let root: URL
    private let sessions: URL
    private let writeFault: (@Sendable (SessionWriteCheckpoint) throws -> Void)?

    public init(root: URL, writeFault: (@Sendable (SessionWriteCheckpoint) throws -> Void)? = nil) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.sessions = self.root.appendingPathComponent("sessions", isDirectory: true)
        self.writeFault = writeFault
        try DurableDirectory.create(at: sessions)
        try Self.refuseSymbolicLink(self.sessions)
    }

    public func create(_ document: SessionDocument) throws {
        let folder = try folder(document.id)
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw SessionStoreError.alreadyExists }
        let parentIdentity = try DurableDirectory.identity(of: sessions)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let folderIdentity = try DurableDirectory.identity(of: folder)
        do {
            try write(document, to: folder, upgradeVersion: false)
            try DurableDirectory.synchronize(sessions, matching: parentIdentity)
        }
        catch {
            // A renamed document may survive a refused directory flush. Retain it,
            // and never clean up through a parent that was replaced with a link.
            if (try? DurableDirectory.identity(of: sessions)) == parentIdentity,
               (try? DurableDirectory.identity(of: folder)) == folderIdentity,
               !FileManager.default.fileExists(atPath: folder.appendingPathComponent("session.json").path) {
                try? FileManager.default.removeItem(at: folder)
            }
            throw error
        }
    }

    public func load(_ id: String) throws -> SessionDocument {
        let folder = try folder(id)
        let url = folder.appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw SessionStoreError.notFound }
        try Self.refuseSymbolicLink(url)
        let document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: url))
        guard document.id == id else { throw SessionStoreError.invalidID }
        return document
    }

    public func update(_ id: String, facet: SessionFacet) throws {
        var document = try load(id)
        switch facet {
        case .original(let value): document.original = value
        case .analysis(let value): document.analysis = value
        case .review(let value): document.review = value
        case .archive(let value): document.archive = value
        }
        try write(document, to: folder(id))
    }

    public func append(_ events: [SessionLogEvent], to id: String) throws {
        guard !events.isEmpty else { return }
        var document = try load(id)
        guard var match = document.match else { throw SessionStoreError.noMatch }
        var ids = Set(match.log.map(\.id))
        var sequences = Set(match.log.map(\.seq))
        var previous = match.log.map(\.seq).max() ?? 0
        for event in events {
            guard !event.id.isEmpty, ids.insert(event.id).inserted,
                  sequences.insert(event.seq).inserted, event.seq > previous else { throw SessionStoreError.invalidEvents }
            if case .point(let point) = event, point.detected == nil, point.reviewed == nil {
                throw SessionStoreError.invalidEvents
            }
            previous = event.seq
        }
        match.log.append(contentsOf: events)
        document.match = match
        try write(document, to: folder(id))
    }

    public func updateRecording(_ recording: SessionRecording, for id: String) throws {
        var document = try load(id)
        document.recording = recording
        try write(document, to: folder(id))
    }

    /// Recording and manual marks commit together; retrying a journal handoff never
    /// overwrites marks that the player has already edited in the saved document.
    public func saveCapture(_ recording: SessionRecording, marks: [SessionMark], for id: String) throws {
        let complete = recording.mediaAvailable && !recording.segments.isEmpty && recording.segments.allSatisfy(\.finalized)
        let original = SessionOriginalState(state: complete ? (recording.gaps.isEmpty ? .saved : .savedWithGaps) : .partial,
                                           reason: complete ? nil : "Recording contains unconfirmed media")
        try persistCapture(recording, marks: marks, original: original, for: id)
    }

    /// A scanner supplies only verified media and an explicit report. The raw WAL remains
    /// separate; its available marks, recording and original facet commit in one transaction.
    public func applyRecoveredCapture(_ recording: SessionRecording, marks: [SessionMark],
                                      original: SessionOriginalState, for id: String) throws {
        guard recording.recovery != nil else { throw SessionStoreError.invalidCapture }
        try persistCapture(recording, marks: marks, original: original, for: id)
    }

    private func persistCapture(_ recording: SessionRecording, marks: [SessionMark],
                                original: SessionOriginalState, for id: String) throws {
        guard recording.mode == .camera || recording.mode == .simulatorFixture else {
            throw SessionStoreError.invalidCapture
        }
        var document = try load(id)
        var merged = document.marks ?? []
        var ids = Set(merged.map(\.id))
        for mark in marks where ids.insert(mark.id).inserted { merged.append(mark) }
        document.marks = merged
        document.recording = recording
        if recording.mediaAvailable && !recording.segments.isEmpty { document.storage.originals = .onDevice }
        document.original = original
        if recording.mode == .simulatorFixture {
            document.sample = .init(synthetic: true, generator: "JOVRAFixtureCamera")
        }
        try write(document, to: folder(id))
    }

    /// Only a validated, existing session can receive media files.
    public func sessionDirectory(_ id: String) throws -> URL {
        _ = try load(id)
        return try folder(id)
    }

    public func setDeviceBackup(_ enabled: Bool, for id: String) throws {
        var document = try load(id)
        document.storage.includeInDeviceBackup = enabled
        try write(document, to: folder(id))
    }

    /// The media service supplies flushed/decoded artifacts. Merge only their records,
    /// keeping corrections made while rendering and the historical source log version.
    public func recordExports(_ records: [SessionExportRecord], artifacts: [RecordFileReference], for id: String,
                              expectedFolderIdentity: DurableDirectory.Identity? = nil) throws {
        var document = try load(id)
        let folder = try folder(id)
        try DurableDirectory.synchronize(folder, matching: expectedFolderIdentity)
        var existing = document.exports ?? []
        var ids = Set(existing.map(\.id))
        let version = document.match?.log.map(\.seq).max() ?? 0
        guard !records.isEmpty, artifacts.count == 4, Set(artifacts.map(\.path)).count == 4 else {
            throw SessionStoreError.invalidExports
        }
        for record in records {
            guard !record.id.isEmpty, ids.insert(record.id).inserted,
                  record.status == .done, record.destination == .app,
                  record.eventLogVersion >= 0, record.eventLogVersion <= version,
                  let file = record.file, artifacts.contains(file) else { throw SessionStoreError.invalidExports }
        }
        // All four files are checked inside the same non-suspending transaction as
        // registration, including CSVs that have no individual session export record.
        for file in artifacts {
            guard let bytes = file.bytes, bytes >= 0 else { throw SessionStoreError.invalidExports }
            let parts = file.path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count >= 3, parts[0] == "exports", parts.allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains("\0")
            }) else { throw SessionStoreError.unsafePath }
            var url = folder
            for part in parts { url.appendPathComponent(String(part)); try Self.refuseSymbolicLink(url) }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.intValue == bytes else { throw SessionStoreError.invalidExports }
        }
        existing.append(contentsOf: records)
        document.exports = existing
        try write(document, to: folder)
    }

    /// Folder-derived on every call: even a stale or malicious index cannot hide a session.
    public func list(_ query: SessionQuery = .init()) throws -> [SessionSummary] {
        let all = try rebuildIndex()
        let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { summary in
            (query.kind == nil || query.kind == summary.kind) &&
            (query.sample == nil || query.sample == summary.sample) &&
            (query.original == nil || query.original == summary.original?.state) &&
            (query.analysis == nil || query.analysis == summary.analysis?.state) &&
            (query.review == nil || query.review == summary.review?.state) &&
            (query.archive == nil || query.archive == summary.archive.state) &&
            (search.isEmpty || ([summary.title, summary.notes ?? ""] + summary.players.map(\.displayName))
                .joined(separator: " ").localizedCaseInsensitiveContains(search))
        }
    }

    @discardableResult public func rebuildIndex() throws -> [SessionSummary] {
        var summaries: [SessionSummary] = []
        for entry in try FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: [.isDirectoryKey]) {
            let type = try FileManager.default.attributesOfItem(atPath: entry.path)[.type] as? FileAttributeType
            guard type == .typeDirectory || type == .typeSymbolicLink else { continue }
            let document: SessionDocument
            do { document = try load(entry.lastPathComponent) }
            catch is ContractError { try quarantineEntry(entry, reason: "Invalid or unsupported document"); continue }
            catch is DecodingError { try quarantineEntry(entry, reason: "Invalid document fields"); continue }
            catch let error as SessionStoreError {
                guard [.invalidID, .unsafePath, .notFound].contains(error) else { throw error }
                try quarantineEntry(entry, reason: String(describing: error)); continue
            }
            // Migration I/O failures propagate without relocating a healthy original.
            let migrated: SessionDocument
            do { migrated = try migrate(document) }
            catch SessionStoreError.unsupportedMigration {
                try quarantineEntry(entry, reason: "Unsupported document version"); continue
            }
            if migrated != document { try write(migrated, to: folder(document.id), upgradeVersion: false) }
            summaries.append(SessionSummary(migrated))
        }
        summaries.sort { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
        // The index is disposable: lack of room for this cache must not hide originals.
        try? CanonicalJSON.encode(summaries).write(to: root.appendingPathComponent("index.json"), options: .atomic)
        return summaries
    }

    public func quarantine(_ id: String, reason: String) throws {
        // Move the entry itself, including a malicious link, without following it.
        // The report lives in a new container, never inside untrusted media.
        try quarantineEntry(folder(id, allowSymbolicLink: true), reason: reason)
    }

    private func quarantineEntry(_ source: URL, reason: String) throws {
        let id = source.lastPathComponent
        let destination = try auxiliaryFolder("quarantine")
        let name = UUID().uuidString
        let container = destination.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: false)
        let record = QuarantinedSession(sessionID: id, reason: reason, folderName: name)
        do {
            try CanonicalJSON.encode(record).write(to: container.appendingPathComponent("quarantine.json"), options: .atomic)
            try FileManager.default.moveItem(at: source, to: container.appendingPathComponent("session"))
        } catch { try? FileManager.default.removeItem(at: container); throw error }
    }

    /// Pure additive migration. Unknown fields already refused by ContractCodec remain preserved in quarantine.
    public func migrate(_ document: SessionDocument) throws -> SessionDocument {
        guard document.schemaVersion.major == 1, (document.schemaVersion.minor < SchemaVersion.current.minor ||
               (document.schemaVersion.minor == SchemaVersion.current.minor &&
                document.schemaVersion.patch <= SchemaVersion.current.patch)) else {
            throw SessionStoreError.unsupportedMigration
        }
        var result = document
        result.schemaVersion = .current
        return result
    }

    public func opponentHistory(playerID: String, opponentID: String) throws -> [SessionSummary] {
        guard playerID != opponentID else { return [] }
        return try list(.init(sample: false)).filter { summary in
            guard summary.hasMatch, let sides = summary.sides else { return false }
            return (sides.A.contains(playerID) && sides.B.contains(opponentID)) ||
                (sides.B.contains(playerID) && sides.A.contains(opponentID))
        }
    }

    public func headToHead(playerID: String, opponentID: String) throws -> [SessionSummary] {
        try opponentHistory(playerID: playerID, opponentID: opponentID)
    }

    public func quarantinedSessions() throws -> [QuarantinedSession] {
        let directory = try auxiliaryFolder("quarantine")
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map { entry in
                try Self.refuseSymbolicLink(entry)
                let record = entry.appendingPathComponent("quarantine.json")
                try Self.refuseSymbolicLink(record)
                return try ContractCodec.decode(QuarantinedSession.self, from: Data(contentsOf: record))
            }.sorted { $0.sessionID < $1.sessionID }
    }

    private func auxiliaryFolder(_ name: String) throws -> URL {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try Self.refuseSymbolicLink(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func folder(_ id: String, allowSymbolicLink: Bool = false) throws -> URL {
        guard !id.isEmpty, id.count <= 160, id != ".", id != "..",
              id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0) }) else {
            throw SessionStoreError.invalidID
        }
        let result = sessions.appendingPathComponent(id, isDirectory: true)
        try Self.refuseSymbolicLink(sessions)
        if !allowSymbolicLink { try Self.refuseSymbolicLink(result) }
        return result
    }

    private func write(_ document: SessionDocument, to folder: URL, upgradeVersion: Bool = true) throws {
        let folderIdentity = try DurableDirectory.identity(of: folder)
        let destination = folder.appendingPathComponent("session.json")
        try Self.refuseSymbolicLink(destination)
        let temporary = folder.appendingPathComponent(".session-\(UUID().uuidString).tmp")
        let persisted = upgradeVersion ? try migrate(document) : document
        let bytes = try CanonicalJSON.encode(persisted)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: bytes); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); try? FileManager.default.removeItem(at: temporary); throw error }
        // A simulated process death leaves a temp file; loads intentionally ignore it.
        try writeFault?(.temporaryFileFlushed(temporary))
        guard rename(temporary.path, destination.path) == 0 else { throw SessionStoreError.renameFailed(errno) }
        try writeFault?(.documentRenamed(destination))
        // The path must still identify the directory this transaction wrote into.
        // A replacement directory must not turn another tree's rename into an acknowledgment.
        do { try DurableDirectory.synchronize(folder, matching: folderIdentity) }
        catch DirectoryDurabilityError.filesystem(let failure) { throw SessionStoreError.durabilityUnconfirmed(failure) }

    }

    private static func refuseSymbolicLink(_ url: URL) throws {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw SessionStoreError.unsafePath }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { }
    }
}
