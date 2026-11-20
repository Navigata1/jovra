import AVFoundation
import CryptoKit
import Darwin
import Foundation
import JovraCore

public struct FilesImportFingerprint: Equatable, Sendable {
    public let sha256: String
    public let bytes: Int
}

/// A verified, unpublished copy kept in private staging while the player decides about a duplicate.
/// It never appears in the library; relaunch sweeps it like any other abandoned staging folder.
public struct FilesImportHeldCopy: Equatable, Sendable {
    fileprivate let id: UUID
    fileprivate let document: SessionDocument
    fileprivate let witness: MediaAdoptionWitness

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

public struct FilesImportDuplicate: Equatable, Sendable {
    fileprivate let candidate: FilesImportDuplicateCandidate
    public let fingerprint: FilesImportFingerprint
    /// Present when the caller asked to hold the staged copy so "Import anyway" needs no new selection.
    public fileprivate(set) var held: FilesImportHeldCopy?
    public var sessionID: String { candidate.sessionID }
}

public enum FilesImportError: Error, Equatable, Sendable {
    case invalidPlayer, invalidMatchSetup, unreadableSource
    case unsupported(ImportUnsupportedReason)
    case duplicate(FilesImportDuplicate)
    case duplicateUnverified(FilesImportFingerprint)
    case differentDuplicateSelection
    case noHeldCopy
}

/// What the player said the footage is. Video metadata never supplies players or scoring facts.
public enum ImportIntent: Sendable {
    case practice(playerName: String)
    case match(FilesImportMatchSetup)

    public var isMatch: Bool {
        if case .match = self { return true }
        return false
    }
}

/// One local selection (Files or Photos). Copy without re-encoding, then verify the retained copy before publication.
public struct FilesImportService: Sendable {
    private let store: SessionStore
    public init(store: SessionStore) { self.store = store }

    public func importVideo(_ source: URL, playerName: String,
                            importingAgain permission: FilesImportFingerprint? = nil) async throws -> String {
        try await importItem(source, intent: .practice(playerName: playerName), importingAgain: permission)
    }

    public func importMatch(_ source: URL, setup: FilesImportMatchSetup,
                            importingAgain permission: FilesImportFingerprint? = nil) async throws -> String {
        try await importItem(source, intent: .match(setup), importingAgain: permission)
    }

    /// The general entry point. `origin` records where the player picked the file (story 119).
    /// With `holdingDuplicate`, a verified duplicate keeps its staged copy for `importHeldCopy` or `discardHeldCopy`.
    public func importItem(_ source: URL, intent: ImportIntent, origin: SessionRecordingImportSource = .files,
                           holdingDuplicate: Bool = false,
                           importingAgain permission: FilesImportFingerprint? = nil) async throws -> String {
        try Task.checkCancellation()
        let players: [SessionPlayer], scoring: ScoringInput?
        switch intent {
        case .practice(let playerName):
            let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.unicodeScalars.count <= 60 else { throw FilesImportError.invalidPlayer }
            players = [SessionPlayer(id: "player", displayName: name, handedness: .unknown, backhand: .unknown, isSelf: false)]
            scoring = nil
        case .match(let setup):
            let input = try setup.scoringInput()
            _ = try ScoringEngine.fold(input)
            players = input.players
            scoring = input
        }
        return try await importVideo(source, players: players, scoring: scoring, origin: origin,
                                     holdingDuplicate: holdingDuplicate, importingAgain: permission)
    }

    /// Revalidate the original if the player chooses to open it after a duplicate prompt.
    public func verifyExistingDuplicate(_ duplicate: FilesImportDuplicate) async throws -> String {
        try await confirmDuplicate(duplicate)
        return duplicate.sessionID
    }

    /// "Import anyway" for a held duplicate: publish the already-verified staged copy as a separate session.
    public func importHeldCopy(_ duplicate: FilesImportDuplicate) async throws -> String {
        guard let held = duplicate.held else { throw FilesImportError.noHeldCopy }
        do {
            switch try await store.commitFilesImport(held.document, id: held.id, allowDuplicate: true,
                                                    verifyOriginal: held.witness.verify) {
            case .published: return held.id.uuidString
            case .possibleDuplicates: throw FilesImportError.noHeldCopy
            }
        } catch {
            try? await store.discardFilesImport(held.id)
            throw error
        }
    }

    /// Remove a held copy ("Open existing", dismissal or cancellation). Safe to call twice.
    public func discardHeldCopy(_ duplicate: FilesImportDuplicate) async {
        guard let held = duplicate.held else { return }
        try? await store.discardFilesImport(held.id)
    }

    private func importVideo(_ source: URL, players: [SessionPlayer], scoring: ScoringInput?,
                             origin: SessionRecordingImportSource, holdingDuplicate: Bool,
                             importingAgain permission: FilesImportFingerprint?) async throws -> String {
        guard source.isFileURL else { throw FilesImportError.unreadableSource }
        if let reason = ImportValidation.container(of: source) { throw FilesImportError.unsupported(reason) }
        let ext = source.pathExtension.lowercased()

        let id = UUID()
        let staging = try await store.beginFilesImport(id)
        var keepStaging = false
        do {
            let stagingIdentity = try DurableDirectory.identity(of: staging)
            let relative = "originals/source.\(ext)"
            let original = staging.appendingPathComponent(relative)
            let originals = original.deletingLastPathComponent()
            try excludeFromBackup(staging.deletingLastPathComponent())
            try DurableDirectory.create(at: originals)
            try excludeFromBackup(originals)
            let (file, identity) = try copy(source, to: original, relativePath: relative)
            guard let digest = file.sha256, let bytes = file.bytes else { throw FilesImportError.unreadableSource }
            let fingerprint = FilesImportFingerprint(sha256: digest, bytes: bytes)
            guard permission == nil || permission == fingerprint else { throw FilesImportError.differentDuplicateSelection }
            let info: MediaInfo
            do { info = try await MediaProbe.probe(original) }
            catch is CancellationError { throw CancellationError() }
            catch { throw FilesImportError.unsupported(.noVideoTrack) }
            if let reason = ImportValidation.reason(for: info) { throw FilesImportError.unsupported(reason) }
            guard let video = info.video, let rate = video.frameRate else { throw FilesImportError.unsupported(.noVideoTrack) }
            let codec: SessionSegmentCodec = video.codec == .hevc ? .hevc : .h264
            let decoded: DecodedCapture
            do { decoded = try await decodeCaptureToEnd(original) }
            catch is CancellationError { throw CancellationError() }
            catch { throw FilesImportError.unsupported(.notDecodable(ImportValidation.codecDisplayName(video.fourCC))) }
            try Task.checkCancellation()
            let duration = decoded.duration.convertScale(1000, method: .roundHalfAwayFromZero)
            guard duration.isNumeric, duration.value > 0, let milliseconds = Int(exactly: duration.value) else {
                throw FilesImportError.unsupported(.notDecodable(ImportValidation.codecDisplayName(video.fourCC)))
            }
            let metadata = await ImportSourceMetadata.read(original)
            let segment = SessionSegment(id: "segment-0", index: 0, file: file, startMs: 0, durationMs: milliseconds,
                frameRate: .init(num: rate.frames, den: rate.perSeconds), width: video.codedWidth, height: video.codedHeight,
                codec: codec, hasAudio: info.audio != nil,
                rotationDegrees: .init(rawValue: video.rotationDegrees), finalized: true)
            let now = Date.now.ISO8601Format()
            let title = String(source.deletingPathExtension().lastPathComponent.unicodeScalars.prefix(120))
            let document = SessionDocument(id: id.uuidString, sport: .value, createdAt: now, updatedAt: now,
                title: title, sessionKind: scoring == nil ? .strokePractice : .match,
                players: players, sides: scoring?.sides,
                match: scoring.map { .init(format: $0.format, toss: $0.toss, log: $0.log) },
                recording: .init(mode: .import, importSource: origin, startedAt: metadata.recordedAt?.ISO8601Format(),
                    durationMs: milliseconds, segments: [segment], gaps: [], microphone: .notRequested, mediaAvailable: true,
                    device: metadata.device),
                analysis: .init(state: .notRequested, runs: []), review: .init(state: .notStarted),
                archive: .init(state: .localOnly), storage: .init(originals: .onDevice, includeInDeviceBackup: false),
                original: .init(state: .saved))
            let finalIdentity = try refreshStagedIdentity(file, in: staging, copied: identity)
            let witness = MediaAdoptionWitness(directory: stagingIdentity, files: [relative: finalIdentity])
            switch try await store.commitFilesImport(document, id: id, allowDuplicate: permission != nil,
                                                    verifyOriginal: witness.verify) {
            case .published:
                return id.uuidString
            case .possibleDuplicates(let candidates):
                for candidate in candidates {
                    var duplicate = FilesImportDuplicate(candidate: candidate, fingerprint: fingerprint)
                    do { try await confirmDuplicate(duplicate) }
                    catch FilesImportError.duplicateUnverified(_) { continue }
                    if holdingDuplicate {
                        duplicate.held = FilesImportHeldCopy(id: id, document: document, witness: witness)
                        keepStaging = true
                    }
                    throw FilesImportError.duplicate(duplicate)
                }
                try Task.checkCancellation()
                throw FilesImportError.duplicateUnverified(fingerprint)
            }
        } catch {
            if !keepStaging { try? await store.discardFilesImport(id) }
            throw error
        }
    }

    /// AVFoundation or the filesystem may update metadata after the copy without changing the bytes.
    /// Rebind a ctime-only change to the same inode only after re-reading and matching the exact copied fingerprint.
    private func refreshStagedIdentity(_ file: RecordFileReference, in folder: URL,
                                       copied: MediaFileIdentity) throws -> MediaFileIdentity {
        let files = RecoveryFiles(folder: folder)
        let path = try files.url(file.path)
        var status = stat()
        guard lstat(path.path, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { throw RecoveryError.changedFile }
        let current = MediaFileIdentity(status)
        if current == copied { return current }
        guard current.device == copied.device, current.inode == copied.inode, current.bytes == copied.bytes,
              current.modifiedSeconds == copied.modifiedSeconds, current.modifiedNanos == copied.modifiedNanos else {
            throw RecoveryError.changedFile
        }
        let (fingerprint, _, identity) = try files.readOwnedOriginal(file.path)
        guard identity == current, fingerprint.sha256 == file.sha256, fingerprint.bytes == file.bytes else {
            throw RecoveryError.changedFile
        }
        return identity
    }

    private func confirmDuplicate(_ duplicate: FilesImportDuplicate) async throws {
        let candidate = duplicate.candidate
        do {
            try Task.checkCancellation()
            let directory = try await store.sessionDirectory(candidate.sessionID)
            let identity = try DurableDirectory.identity(of: directory)
            let (fingerprint, _, fileIdentity) = try RecoveryFiles(folder: directory).readOwnedOriginal(candidate.file.path)
            guard fingerprint.sha256 == candidate.file.sha256, fingerprint.bytes == candidate.file.bytes else {
                throw RecoveryError.changedFile
            }
            let witness = MediaAdoptionWitness(directory: identity, files: [candidate.file.path: fileIdentity])
            try await store.confirmFilesImportDuplicate(candidate, verifyOriginal: witness.verify)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FilesImportError.duplicateUnverified(duplicate.fingerprint)
        }
    }

    private func excludeFromBackup(_ url: URL) throws {
        var item = url, values = URLResourceValues()
        values.isExcludedFromBackup = true
        try item.setResourceValues(values)
    }

    private func copy(_ source: URL, to destination: URL, relativePath: String) throws -> (RecordFileReference, MediaFileIdentity) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var selected = stat()
        guard lstat(source.path, &selected) == 0, selected.st_mode & S_IFMT == S_IFREG else {
            throw FilesImportError.unreadableSource
        }
        var coordinationError: NSError?
        var copied: Result<(RecordFileReference, MediaFileIdentity), Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinated in
            copied = Result { try streamCopy(coordinated, to: destination, relativePath: relativePath) }
        }
        if let coordinationError { throw coordinationError }
        guard let copied else { throw FilesImportError.unreadableSource }
        return try copied.get()
    }

    private func streamCopy(_ source: URL, to destination: URL, relativePath: String) throws -> (RecordFileReference, MediaFileIdentity) {
        let inputFD = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard inputFD >= 0 else { throw FilesImportError.unreadableSource }
        let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true)
        defer { try? input.close() }
        var before = stat(), after = stat(), declared = stat(), retained = stat()
        guard fstat(inputFD, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size > 0 else {
            throw FilesImportError.unreadableSource
        }
        let outputFD = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard outputFD >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        defer { try? output.close() }
        try excludeFromBackup(destination)
        var hash = SHA256(), bytes = 0
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: chunk)
            hash.update(data: chunk)
            bytes += chunk.count
        }
        guard fstat(inputFD, &after) == 0, lstat(source.path, &declared) == 0,
              MediaFileIdentity(before) == MediaFileIdentity(after),
              MediaFileIdentity(before) == MediaFileIdentity(declared), Int64(bytes) == before.st_size else {
            throw FilesImportError.unreadableSource
        }
        try output.synchronize()
        guard fstat(outputFD, &retained) == 0, retained.st_size == Int64(bytes) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try output.close()
        let reference = RecordFileReference(path: relativePath, bytes: bytes,
            sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
        return (reference, MediaFileIdentity(retained))
    }
}
