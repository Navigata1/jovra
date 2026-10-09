import AVFoundation
import Foundation
import JovraBenchmark
import JovraCore
import JovraMedia
import Testing

@Suite("Durable local export package", .serialized)
struct LocalExportServiceTests {
    @Test func realClipAndSnapshotCommitWithoutLosingAnInterveningPoint() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        var document = try sample()
        document.match?.log = []
        document.exports = nil
        try await store.create(document)
        let recording = try await capture(store: store, id: document.id)
        let first = try await store.appendReviewedPoint(winner: .a, startMs: 0, endMs: 1000, for: document.id)
        let folder = try await store.sessionDirectory(document.id)
        let original = folder.appendingPathComponent(try #require(recording.segments.first).file.path)
        let originalBytes = try Data(contentsOf: original)
        let id = document.id
        let package = try await LocalExportService(store: store).export(sessionID: id,
            range: MediaRange(fromMs: 0, toMs: 1000)) { progress in
                if progress == .artifactsReady { _ = try await store.correctReviewedWinner(pointID: first.id, winner: .b, for: id) }
            }
        #expect(package.videoFrames == 30)
        #expect(try await AVURLAsset(url: package.clip).loadTracks(withMediaType: .audio).isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: package.directory.path).sorted()
        #expect(names == ["clip.mp4", "points.csv", "session.json", "stats.csv"])
        let snapshot = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: package.sessionJSON))
        #expect((snapshot.match?.log ?? []) == [SessionLogEvent.point(first)])
        #expect(snapshot.exports == nil)
        let expected = try DataExporter.exportSession(snapshot)
        #expect(try Data(contentsOf: package.pointsCSV) == expected.pointsCSV)
        #expect(try Data(contentsOf: package.statsCSV) == expected.statsCSV)
        let saved = try await store.load(id)
        #expect(saved.match?.log.count == 2)
        #expect(saved.match?.log.first == .point(first))
        let currentStats = try StatsEngine.compute(ScoringEngine.fold(ScoringInput(session: saved)))
        #expect(currentStats.sides.B.totalPointsWon.n == 1)
        #expect(saved.exports?.count == 2)
        #expect(saved.exports?.allSatisfy { $0.eventLogVersion == 1 && $0.status == .done && !$0.includesAudio } == true)
        #expect(Set(saved.exports?.map(\.kind) ?? []) == [.clip, .sessionData])
        #expect(try Data(contentsOf: original) == originalBytes)
        if let target = ProcessInfo.processInfo.environment["JOVRA_LOCAL_EXPORT_EVIDENCE_DIR"] {
            try FileManager.default.copyItem(at: folder, to: URL(fileURLWithPath: target))
        }
    }

    @Test func metadataFailureRetainsFourFilesButNeverRegistersDone() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fault = ExportWriteFault()
        let store = try SessionStore(root: root) { checkpoint in
            if case .temporaryFileFlushed = checkpoint, fault.enabled { throw ExportFailure.injected }
        }
        var document = try sample()
        document.match?.log = []; document.exports = nil
        try await store.create(document)
        _ = try await capture(store: store, id: document.id)
        let id = document.id
        await #expect(throws: ExportFailure.injected) {
            _ = try await LocalExportService(store: store).export(sessionID: id,
                range: MediaRange(fromMs: 0, toMs: 1000)) { progress in
                    if progress == .artifactsReady { fault.enable() }
                }
        }
        #expect(try await store.load(document.id).exports == nil)
        let exports = try await store.sessionDirectory(document.id).appendingPathComponent("exports")
        let packages = try FileManager.default.contentsOfDirectory(at: exports, includingPropertiesForKeys: nil)
        #expect(packages.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: #require(packages.first).path).count == 4)
        let retained = try Data(contentsOf: #require(packages.first).appendingPathComponent("clip.mp4"))
        fault.disable()
        let retry = try await LocalExportService(store: store).export(sessionID: id, range: .init(fromMs: 0, toMs: 1000))
        #expect(retry.directory != packages.first)
        #expect(try Data(contentsOf: #require(packages.first).appendingPathComponent("clip.mp4")) == retained)
        #expect(try await store.load(id).exports?.count == 2)
    }

    @Test func invalidRangesNeverPublishARecordOrAnArtifact() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        var document = try sample()
        document.match?.log = []; document.exports = nil
        try await store.create(document)
        _ = try await capture(store: store, id: document.id)
        let service = LocalExportService(store: store)
        for range in [MediaRange(fromMs: -1, toMs: 500), .init(fromMs: 0, toMs: 3000), .init(fromMs: 1000, toMs: 1000)] {
            await #expect(throws: (any Error).self) { _ = try await service.export(sessionID: document.id, range: range) }
        }
        #expect(try await store.load(document.id).exports == nil)
        let exports = try await store.sessionDirectory(document.id).appendingPathComponent("exports")
        #expect(try FileManager.default.contentsOfDirectory(atPath: exports.path).isEmpty)
    }

    @Test func redirectedExportFolderCannotWriteOutsideTheSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        var document = try sample()
        document.match?.log = []; document.exports = nil
        try await store.create(document)
        _ = try await capture(store: store, id: document.id)
        let exports = try await store.sessionDirectory(document.id).appendingPathComponent("exports")
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try FileManager.default.removeItem(at: exports)
        try FileManager.default.createSymbolicLink(at: exports, withDestinationURL: outside)
        await #expect(throws: (any Error).self) {
            _ = try await LocalExportService(store: store).export(sessionID: document.id, range: .init(fromMs: 0, toMs: 1000))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        #expect(try await store.load(document.id).exports == nil)
    }

    @Test(arguments: ["points.csv", "stats.csv", "redirected-stats.csv"])
    func everyArtifactMustStillBeOwnedAndPresentAtRegistration(change: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        var document = try sample()
        document.match?.log = []; document.exports = nil
        try await store.create(document)
        _ = try await capture(store: store, id: document.id)
        let id = document.id
        let folder = try await store.sessionDirectory(id)
        await #expect(throws: (any Error).self) {
            _ = try await LocalExportService(store: store).export(sessionID: id, range: .init(fromMs: 0, toMs: 1000)) { _ in
                let packages = try FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("exports"), includingPropertiesForKeys: nil)
                let package = try #require(packages.first)
                let file = package.appendingPathComponent(change == "redirected-stats.csv" ? "stats.csv" : change)
                let bytes = try Data(contentsOf: file)
                try FileManager.default.removeItem(at: file)
                if change == "redirected-stats.csv" {
                    let outside = root.appendingPathComponent("outside.csv")
                    try bytes.write(to: outside)
                    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
                }
            }
        }
        #expect(try await store.load(id).exports == nil)
    }

    private func sample() throws -> SessionDocument {
        let path = MediaFixtureCatalog.repository().root.appendingPathComponent("spec/fixtures/sample/jon-vs-alex.session.json")
        var document = try ContractCodec.decode(SessionDocument.self, from: Data(contentsOf: path))
        document.marks = nil; document.voiceNotes = nil; document.comparisons = nil; document.derivedValues = nil
        return document
    }
    private func capture(store: SessionStore, id: String) async throws -> SessionRecording {
        let catalog = MediaFixtureCatalog.repository()
        let truth = try catalog.truth(id: "fixtureCamera/fixture-camera")
        let clock = VirtualCaptureClock()
        let camera = FixtureCamera(url: try catalog.mediaURL(for: truth), duration: CMTime(value: 2, timescale: 1), clock: clock)
        let engine = CaptureEngine(source: camera, clock: clock, sink: ExportCaptureSink(store: store))
        _ = try await engine.prepare(CapturePreset(width: 1280, height: 720), microphone: .granted)
        try await engine.start(sessionID: id, folder: MediaLibrary(store: store).recordingFolder(sessionID: id))
        try await camera.waitUntilFinished()
        return try await engine.stop()
    }
}

private actor ExportCaptureSink: RecordingSink {
    let store: SessionStore
    init(store: SessionStore) { self.store = store }
    func saveRecording(sessionID: String, recording: SessionRecording, marks: [SessionMark]) async throws {
        try await store.saveCapture(recording, marks: marks, for: sessionID)
    }
}
private enum ExportFailure: Error { case injected }
private final class ExportWriteFault: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var enabled: Bool { lock.withLock { value } }
    func enable() { lock.withLock { value = true } }
    func disable() { lock.withLock { value = false } }
}
