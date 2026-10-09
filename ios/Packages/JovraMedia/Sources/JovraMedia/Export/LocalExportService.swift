import AVFoundation
import Darwin
import Foundation
import JovraCore

public enum LocalExportError: Error, Equatable, Sendable {
    case invalidRange, noPlayableSegment, unsafePath, filesystem(Int32)
}
public enum LocalExportProgress: Equatable, Sendable { case artifactsReady }
public struct LocalExportPackage: Sendable {
    public let directory: URL
    public let videoFrames: Int
    public var clip: URL { directory.appendingPathComponent("clip.mp4") }
    public var sessionJSON: URL { directory.appendingPathComponent("session.json") }
    public var pointsCSV: URL { directory.appendingPathComponent("points.csv") }
    public var statsCSV: URL { directory.appendingPathComponent("stats.csv") }
}

/// One local range and an immutable data snapshot, using the existing single-writer store.
/// No originals are rewritten. Failed work stays unregistered for inspection/safe retry.
public actor LocalExportService {
    private let store: SessionStore
    private let library: MediaLibrary
    public init(store: SessionStore) { self.store = store; self.library = MediaLibrary(store: store) }

    public func export(sessionID: String, range: MediaRange, includeAudio: Bool = false,
                       onProgress: @Sendable (LocalExportProgress) async throws -> Void = { _ in }) async throws -> LocalExportPackage {
        try Task.checkCancellation()
        let snapshot = try await store.load(sessionID)
        guard range.fromMs >= 0, range.toMs > range.fromMs else { throw LocalExportError.invalidRange }
        let candidates = snapshot.recording.segments.filter { segment in
            segment.finalized && segment.startMs >= 0 && range.fromMs >= segment.startMs &&
            range.toMs - segment.startMs <= segment.durationMs
        }
        guard snapshot.recording.mediaAvailable, candidates.count == 1,
              let segment = candidates.first else { throw LocalExportError.noPlayableSegment }
        guard segment.file.path.hasPrefix("originals/") else { throw LocalExportError.unsafePath }
        let data = try DataExporter.exportSession(snapshot) // Precedes its own export records.
        let version = snapshot.match?.log.map(\.seq).max() ?? 0
        let folder = try await library.recordingFolder(sessionID: sessionID)
        let folderIdentity = try DurableDirectory.identity(of: folder)
        let source = try await library.fileURL(sessionID: sessionID, relativePath: segment.file.path)
        let exports = folder.appendingPathComponent("exports", isDirectory: true)
        let exportsIdentity = try DurableDirectory.identity(of: exports)
        let id = UUID().uuidString
        let directory = exports.appendingPathComponent(id, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw LocalExportError.unsafePath }
        try DurableDirectory.create(at: directory)
        let directoryIdentity = try DurableDirectory.identity(of: directory)
        let package = LocalExportPackage(directory: directory, videoFrames: 0)
        let result = try await ClipExporter.exportClip(source: source,
            range: CMTimeRange(start: CMTime(value: Int64(range.fromMs - segment.startMs), timescale: 1000),
                               duration: CMTime(value: Int64(range.toMs - range.fromMs), timescale: 1000)),
            destination: package.clip, includeAudio: includeAudio)
        try write(data.sessionJSON, to: package.sessionJSON)
        try write(data.pointsCSV, to: package.pointsCSV)
        try write(data.statsCSV, to: package.statsCSV)
        func confirmDirectories() throws {
            try DurableDirectory.synchronize(directory, matching: directoryIdentity)
            try DurableDirectory.synchronize(exports, matching: exportsIdentity)
            try DurableDirectory.synchronize(folder, matching: folderIdentity)
        }
        try confirmDirectories()
        try await onProgress(.artifactsReady)
        try Task.checkCancellation()
        try confirmDirectories()
        let clipBytes = try FileManager.default.attributesOfItem(atPath: package.clip.path)[.size] as? NSNumber
        guard let clipBytes, clipBytes.int64Value > 0 else { throw LocalExportError.unsafePath }
        let createdAt = Date.now.ISO8601Format()
        let prefix = "exports/\(id)/"
        let clipFile = RecordFileReference(path: prefix + "clip.mp4", mimeType: "video/mp4", bytes: clipBytes.intValue)
        let jsonFile = RecordFileReference(path: prefix + "session.json", mimeType: "application/json", bytes: data.sessionJSON.count)
        let artifacts = [clipFile, jsonFile,
            RecordFileReference(path: prefix + "points.csv", mimeType: "text/csv", bytes: data.pointsCSV.count),
            RecordFileReference(path: prefix + "stats.csv", mimeType: "text/csv", bytes: data.statsCSV.count)]
        let records = [
            SessionExportRecord(id: id + "-clip", kind: .clip, createdAt: createdAt,
                eventLogVersion: version, includesAudio: result.includesAudio, range: range, destination: .app,
                file: clipFile, status: .done),
            SessionExportRecord(id: id + "-data", kind: .sessionData, createdAt: createdAt,
                eventLogVersion: version, includesAudio: false, destination: .app,
                file: jsonFile, status: .done)
        ]
        try await store.recordExports(records, artifacts: artifacts, for: sessionID, expectedFolderIdentity: folderIdentity)
        return LocalExportPackage(directory: directory, videoFrames: result.videoFrames)
    }

    private func write(_ data: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw LocalExportError.filesystem(errno) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: data); try handle.synchronize(); try handle.close()
    }
}
