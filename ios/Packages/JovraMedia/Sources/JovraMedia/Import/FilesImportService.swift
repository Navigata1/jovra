import AVFoundation
import CryptoKit
import Darwin
import Foundation
import JovraCore

public enum FilesImportError: Error, Equatable, Sendable {
    case invalidPlayer, invalidMatchSetup, unsupportedFile, unsupportedVideo, unreadableSource
}

/// One local Files selection. Copy without re-encoding, then verify the retained copy before publication.
public struct FilesImportService: Sendable {
    private let store: SessionStore
    public init(store: SessionStore) { self.store = store }

    public func importVideo(_ source: URL, playerName: String) async throws -> String {
        try Task.checkCancellation()
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.unicodeScalars.count <= 60 else { throw FilesImportError.invalidPlayer }
        let player = SessionPlayer(id: "player", displayName: name, handedness: .unknown, backhand: .unknown, isSelf: false)
        return try await importVideo(source, players: [player], scoring: nil)
    }

    public func importMatch(_ source: URL, setup: FilesImportMatchSetup) async throws -> String {
        try Task.checkCancellation()
        let scoring = try setup.scoringInput()
        _ = try ScoringEngine.fold(scoring)
        return try await importVideo(source, players: scoring.players, scoring: scoring)
    }

    private func importVideo(_ source: URL, players: [SessionPlayer], scoring: ScoringInput?) async throws -> String {
        let ext = source.pathExtension.lowercased()
        guard source.isFileURL, ["mov", "mp4"].contains(ext) else { throw FilesImportError.unsupportedFile }

        let id = UUID()
        let staging = try await store.beginFilesImport(id)
        do {
            let stagingIdentity = try DurableDirectory.identity(of: staging)
            let relative = "originals/source.\(ext)"
            let original = staging.appendingPathComponent(relative)
            let originals = original.deletingLastPathComponent()
            try excludeFromBackup(staging.deletingLastPathComponent())
            try DurableDirectory.create(at: originals)
            try excludeFromBackup(originals)
            let (file, identity) = try copy(source, to: original, relativePath: relative)
            let witness = MediaAdoptionWitness(directory: stagingIdentity, files: [relative: identity])
            let info = try await MediaProbe.probe(original)
            guard let video = info.video, video.isDecodable, let rate = video.frameRate,
                  video.codedWidth > 0, video.codedHeight > 0 else { throw FilesImportError.unsupportedVideo }
            let codec: SessionSegmentCodec
            switch video.codec {
            case .h264: codec = .h264
            case .hevc: codec = .hevc
            case .other: throw FilesImportError.unsupportedVideo
            }
            let decoded = try await decodeCaptureToEnd(original)
            let duration = decoded.duration.convertScale(1000, method: .roundHalfAwayFromZero)
            guard duration.isNumeric, duration.value > 0,
                  let milliseconds = Int(exactly: duration.value) else { throw FilesImportError.unsupportedVideo }
            let asset = AVURLAsset(url: original)
            let dateItem = try? await asset.load(.creationDate)
            let recordedDate = try? await dateItem?.load(.dateValue)
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
                recording: .init(mode: .import, importSource: .files, startedAt: recordedDate?.ISO8601Format(),
                    durationMs: milliseconds, segments: [segment], gaps: [], microphone: .notRequested, mediaAvailable: true),
                analysis: .init(state: .notRequested, runs: []), review: .init(state: .notStarted),
                archive: .init(state: .localOnly), storage: .init(originals: .onDevice, includeInDeviceBackup: false),
                original: .init(state: .saved))
            try await store.commitFilesImport(document, id: id, verifyOriginal: witness.verify)
            return id.uuidString
        } catch {
            try? await store.discardFilesImport(id)
            throw error
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
