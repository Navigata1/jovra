import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum SessionStoreError: Error, Equatable, Sendable {
    case invalidID, unsafePath, alreadyExists, notFound, invalidEvents, noMatch
    case confirmationRequired, unsupportedMigration, renameFailed(Int32)
}

public enum SessionFacet: Sendable {
    case original(SessionOriginalState)
    case analysis(SessionAnalysis)
    case review(SessionReview)
    case archive(SessionArchiveState)
}

/// Synchronous filesystem transactions deliberately contain no suspension point. All
/// writers must share this actor: its document is authoritative, never the library index.
public actor SessionStore {
    private let root: URL
    private let sessions: URL
    private let writeFault: (@Sendable (URL) throws -> Void)?

    public init(root: URL, writeFault: (@Sendable (URL) throws -> Void)? = nil) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.sessions = self.root.appendingPathComponent("sessions", isDirectory: true)
        self.writeFault = writeFault
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        guard self.sessions.resolvingSymlinksInPath().path == self.sessions.path else { throw SessionStoreError.unsafePath }
    }

    public func create(_ document: SessionDocument) throws {
        let folder = try folder(document.id)
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw SessionStoreError.alreadyExists }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do { try write(document, to: folder) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
    }

    public func load(_ id: String) throws -> SessionDocument {
        let folder = try folder(id)
        let url = folder.appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw SessionStoreError.notFound }
        guard url.resolvingSymlinksInPath().path == url.path else { throw SessionStoreError.unsafePath }
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
        var previous = match.log.map(\.seq).max() ?? -1
        for event in events {
            guard !event.id.isEmpty, ids.insert(event.id).inserted,
                  sequences.insert(event.seq).inserted, event.seq > previous else { throw SessionStoreError.invalidEvents }
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

    private func folder(_ id: String) throws -> URL {
        guard !id.isEmpty, id.count <= 160, id != ".", id != "..",
              id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0) }) else {
            throw SessionStoreError.invalidID
        }
        let result = sessions.appendingPathComponent(id, isDirectory: true)
        guard result.resolvingSymlinksInPath().path == result.path else { throw SessionStoreError.unsafePath }
        return result
    }

    private func write(_ document: SessionDocument, to folder: URL) throws {
        let destination = folder.appendingPathComponent("session.json")
        guard destination.resolvingSymlinksInPath().path == destination.path else { throw SessionStoreError.unsafePath }
        let temporary = folder.appendingPathComponent(".session-\(UUID().uuidString).tmp")
        let bytes = try CanonicalJSON.encode(document)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: bytes); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); try? FileManager.default.removeItem(at: temporary); throw error }
        // A simulated process death leaves a temp file; loads intentionally ignore it.
        try writeFault?(temporary)
        guard rename(temporary.path, destination.path) == 0 else { throw SessionStoreError.renameFailed(errno) }
        let descriptor = open(folder.path, O_RDONLY)
        if descriptor >= 0 { _ = fsync(descriptor); _ = close(descriptor) }
    }
}
