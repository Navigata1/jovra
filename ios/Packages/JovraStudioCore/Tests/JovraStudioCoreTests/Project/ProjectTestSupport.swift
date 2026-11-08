import Foundation
import JovraCore
import JovraStudioCore

/// A fresh folder under the system temporary directory, removed by `cleanUp()`.
struct ProjectScratch {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("jovra-studio-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var studio: URL { root.appendingPathComponent("studio", isDirectory: true) }
    var core: URL { root.appendingPathComponent("core", isDirectory: true) }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    /// A store at this scratch root with a fixed clock, so every written timestamp is known. Local Studio is on
    /// unless a test says otherwise, so the suite also runs in the `JOVRA_STUDIO_LOCAL_OFF` scratch build.
    func store(entitlements: StudioEntitlements = StudioEntitlements(localStudio: true), sessions: SessionStore? = nil,
               writeFault: (@Sendable (StudioProjectWriteCheckpoint) throws -> Void)? = nil) throws -> StudioProjectStore {
        try StudioProjectStore(root: studio, entitlements: entitlements, sessions: sessions,
                               now: { ProjectScratch.fixedNow }, writeFault: writeFault)
    }

    /// 2026-10-07T22:30:00Z, the Sample project lock's `createdAt` (records/project-lock.json).
    static let fixedNow = Date(timeIntervalSince1970: 1_791_412_200)
}

/// Thrown by an injected fault to simulate the process dying at a write checkpoint.
struct SimulatedProcessDeath: Error {}

/// Lowercase hex SHA-256 of a file, through the system tool, so the store's own hashing is never the oracle.
func systemSHA256(_ url: URL) throws -> String {
    let process = Process()
    #if os(Linux)
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sha256sum")
    process.arguments = [url.path]
    #else
    process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
    process.arguments = ["-a", "256", url.path]
    #endif
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(decoding: output, as: UTF8.self)
    return String(text.prefix { !$0.isWhitespace })
}

/// A real (non-sample) core session with one recorded original: a match between "Riley" and "Sam" built from the
/// shipped sample Jon vs Alex log with its Sample label removed and a new id, plus synthetic media bytes on disk.
enum CoreFixtureSessions {
    static func sampleLibrary() throws -> SampleLibrary {
        let root = StudioFixtures.repositoryRoot()
        return try SampleLibrary.load(
            from: root.appendingPathComponent("spec/fixtures/sample/library", isDirectory: true),
            mediaManifest: root.appendingPathComponent("spec/fixtures/sample/media-manifest.json"))
    }

    /// The shipped Jon vs Alex sample session (core T09).
    static func jonVsAlex() throws -> SessionDocument {
        let library = try sampleLibrary()
        guard let session = library.sessions.first(where: { $0.id == StudioSampleContent.matchSessionID }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return session
    }

    /// Every shipped sample session turned into a real one (no Sample label, a new id), so a test library holds
    /// real matches and practice whose stats the sample-scope rule must protect.
    static func realCopies() throws -> [SessionDocument] {
        try sampleLibrary().sessions.enumerated().map { index, session in
            var copy = session
            copy.id = "real-\(index)-\(session.id.prefix(8))"
            copy.sample = nil
            return copy
        }
    }

    /// Creates `document` in `store` and writes `bytes` as its original media file; returns the file.
    @discardableResult
    static func install(_ document: SessionDocument, bytes: Data, in store: SessionStore) async throws -> URL {
        try await store.create(document)
        let folder = try await store.sessionDirectory(document.id)
        let media = folder.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let file = media.appendingPathComponent("segment-000.mov")
        try bytes.write(to: file)
        return file
    }
}
