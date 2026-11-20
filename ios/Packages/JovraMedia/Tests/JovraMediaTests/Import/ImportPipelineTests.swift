@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import JovraBenchmark
import JovraCore
@testable import JovraMedia
import Testing

/// ImportPipeline over the committed import fixture set (T10). Expected outcomes are written out by hand
/// from the fixtures' ground truth, never derived from the code under test.
@Suite("ImportPipeline over the import fixture set", .serialized)
struct ImportPipelineTests {
    static let catalog = MediaFixtureCatalog.repository()

    /// Hand-written per-file expectations, in batch order (sorted ids, so duplicate-a precedes duplicate-b).
    enum Expected: Equatable { case imported, duplicateOf(String), unsupported(ImportUnsupportedReason) }
    static let expected: [(id: String, outcome: Expected)] = [
        ("import/duplicate-a", .imported),
        ("import/duplicate-b", .duplicateOf("import/duplicate-a")),
        ("import/ffv1-unsupported", .unsupported(.codec("FFV1"))),
        ("import/h264-1080p30-landscape", .imported),
        ("import/h264-360p2997-landscape", .imported),
        ("import/h264-720x1280-24-portrait", .imported),
        ("import/hevc-1080p30-portrait-rotated", .imported),
        ("import/hevc-720p240-slowmo", .imported),
        ("import/hevc-720p30-vfr", .imported),
        ("import/hevc-720p60-landscape", .imported),
        ("import/hevc-hlg-720p30", .imported),
    ]

    @Test("the whole set in one batch returns the exact per-file results; HDR, size, rate and rotation are kept")
    func fixtureSetBatch() async throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let pipeline = ImportPipeline(store: store)
        let truths = try Self.catalog.truths(inSet: "import").sorted { $0.id < $1.id }
        #expect(truths.map(\.id) == Self.expected.map(\.id), "The fixture set changed; update the expectations by hand")
        let items = try truths.map { ImportItem(url: try Self.catalog.mediaURL(for: $0), origin: .files) }
        let recorder = PhaseRecorder()
        let report = await pipeline.run(items, intent: .practice(playerName: "Fixture Player")) { id, phase in
            await recorder.record(id, phase)
        }

        #expect(report.results.map(\.item) == items)
        var sessionsByFixture: [String: String] = [:]
        for (truth, result) in zip(truths, report.results) {
            let expected = try #require(Self.expected.first { $0.id == truth.id }).outcome
            switch (expected, result.outcome) {
            case (.imported, .imported(let id)):
                sessionsByFixture[truth.id] = id
                try await Self.expectFaithfulCopy(of: truth, session: id, in: store)
            case (.duplicateOf(let original), .duplicate(let duplicate)):
                #expect(duplicate.sessionID == sessionsByFixture[original])
                #expect(duplicate.held != nil, "The pipeline holds the verified copy for Import anyway")
                await pipeline.discard(duplicate)
            case (.unsupported(let reason), .unsupported(let actual)):
                #expect(actual == reason)
            default:
                Issue.record("\(truth.id): expected \(expected), got \(result.outcome)")
            }
            let phases = await recorder.phases(for: result.item.id)
            #expect(phases.first == .copying || phases.first == .finished(result.outcome))
            #expect(phases.last == .finished(result.outcome))
        }
        #expect(try await store.list().count == 9)
        #expect(try Self.staged(in: root).isEmpty)
    }

    @Test("Import anyway publishes the held copy; Open existing verifies the original and drops it")
    func heldDuplicateChoices() async throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let pipeline = ImportPipeline(store: store)
        let a = try Self.fixture("import/duplicate-a"), b = try Self.fixture("import/duplicate-b")
        let first = try #require(await pipeline.run([.init(url: a, origin: .files)], intent: .practice(playerName: "P")).importedSessionIDs.first)
        let original = try await store.load(first)

        let open = try Self.duplicate(in: await pipeline.run([.init(url: b, origin: .photos)], intent: .practice(playerName: "P")))
        #expect(try Self.staged(in: root).count == 1, "the duplicate's verified copy waits in private staging")
        #expect(try await pipeline.openExisting(open) == first)
        #expect(try Self.staged(in: root).isEmpty)
        #expect(try await store.list().map(\.id) == [first])

        let anyway = try Self.duplicate(in: await pipeline.run([.init(url: b, origin: .photos)], intent: .practice(playerName: "Q")))
        let second = try await pipeline.importAnyway(anyway)
        #expect(second != first)
        #expect(Set(try await store.list().map(\.id)) == [first, second])
        #expect(try await store.load(first) == original, "the existing session is untouched")
        let copy = try await store.load(second)
        #expect(copy.recording.importSource == .photos)
        #expect(copy.players.map(\.displayName) == ["Q"])
        #expect(try Self.staged(in: root).isEmpty)
        await #expect(throws: (any Error).self, "a held copy publishes once") { _ = try await pipeline.importAnyway(anyway) }
        #expect(try await store.list().count == 2)
    }

    @Test("cancelling removes the partial copy and reports every unfinished file as cancelled")
    func cancellationRemovesPartialFolder() async throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root) { checkpoint in
            guard case .documentRenamed(let url) = checkpoint, url.pathComponents.contains(".files-imports") else { return }
            // The staged folder exists with a full copy and its document; cancel before publication.
            #expect(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("originals").path))
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let pipeline = ImportPipeline(store: store)
        let items = try ["import/h264-1080p30-landscape", "import/hevc-720p60-landscape", "import/duplicate-a"].map {
            ImportItem(url: try Self.fixture($0), origin: .files)
        }
        let report = await Task { await pipeline.run(items, intent: .practice(playerName: "P")) }.value
        #expect(report.results.map(\.outcome) == [.cancelled, .cancelled, .cancelled])
        #expect(try await store.list().isEmpty)
        #expect(try Self.staged(in: root).isEmpty)
    }

    @Test("a cloud-only file shows Waiting for download, asks once, and completes when it arrives")
    func cloudOnlyFileWaitsThenCompletes() async throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let cloud = SimulatedCloud(pendingChecks: 3)
        let pipeline = ImportPipeline(store: store, availability: cloud, downloadPollInterval: .milliseconds(10))
        let item = ImportItem(url: try Self.fixture("import/hevc-720p60-landscape"), origin: .files)
        let recorder = PhaseRecorder()
        let report = await pipeline.run([item], intent: .practice(playerName: "P")) { await recorder.record($0, $1) }
        let id = try #require(report.importedSessionIDs.first)
        #expect(await recorder.phases(for: item.id) == [.waitingForDownload, .copying, .finished(.imported(sessionID: id))])
        #expect(await cloud.downloadRequests == 1)
    }

    @Test("a cloud-only file that never arrives stays waiting until the player cancels, leaving nothing behind")
    func cloudOnlyFileCancelled() async throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let pipeline = ImportPipeline(store: store, availability: SimulatedCloud(pendingChecks: .max),
                                      downloadPollInterval: .milliseconds(10))
        let item = ImportItem(url: try Self.fixture("import/duplicate-a"), origin: .files)
        let recorder = PhaseRecorder()
        let task = Task { await pipeline.run([item], intent: .practice(playerName: "P")) { await recorder.record($0, $1) } }
        while await recorder.phases(for: item.id).isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        #expect(await task.value.results.map(\.outcome) == [.cancelled])
        #expect(await recorder.phases(for: item.id) == [.waitingForDownload, .finished(.cancelled)])
        #expect(try await store.list().isEmpty)
    }

    @Test("one bad file in a batch is reported on its own; the good files still save")
    func batchWithBadFiles() async throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let notVideo = root.appendingPathComponent("notes.mp4")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not a video".utf8).write(to: notVideo)
        let matroska = root.appendingPathComponent("rally.mkv")
        try FileManager.default.copyItem(at: try Self.fixture("import/duplicate-a"), to: matroska)
        let items = [ImportItem(url: try Self.fixture("import/h264-1080p30-landscape"), origin: .files),
                     ImportItem(url: notVideo, origin: .files),
                     ImportItem(url: matroska, origin: .files),
                     ImportItem(url: try Self.fixture("import/ffv1-unsupported"), origin: .files),
                     ImportItem(url: try Self.fixture("import/hevc-720p240-slowmo"), origin: .files)]
        let report = await ImportPipeline(store: store).run(items, intent: .practice(playerName: "P"))
        let outcomes = report.results.map(\.outcome)
        guard case .imported = outcomes[0], case .imported = outcomes[4] else {
            Issue.record("good files must import: \(outcomes)"); return
        }
        #expect(outcomes[1] == .unsupported(.noVideoTrack))
        #expect(outcomes[2] == .unsupported(.container("mkv")))
        #expect(outcomes[3] == .unsupported(.codec("FFV1")))
        #expect(try await store.list().count == 2)
        #expect(try Self.staged(in: root).isEmpty)
    }

    @Test("a singles match imports exactly one video")
    func matchTakesOneVideo() async throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let setup = FilesImportMatchSetup(playerA: "A", playerB: "B", format: .bestOfOne, gameScoring: .ad,
                                          firstServer: .a, nearPlayer: .a, containsFullMatch: true)
        let items = try ["import/duplicate-a", "import/hevc-720p60-landscape"].map { ImportItem(url: try Self.fixture($0), origin: .files) }
        let report = await ImportPipeline(store: store).run(items, intent: .match(setup))
        #expect(report.results.map(\.outcome) == [.failed(.oneMatchPerImport), .failed(.oneMatchPerImport)])
        #expect(try await store.list().isEmpty)
    }

    @Test("the real recording date and camera come from the file's metadata; an undated file stays undated")
    func realDateAndSourceMetadata() async throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dated = root.appendingPathComponent("Court 3 rally.mov")
        try await Self.writeDatedCopy(of: try Self.fixture("import/hevc-720p60-landscape"), to: dated,
                                      date: "2026-10-06T09:41:00Z", model: "Sample Camera")
        let store = try SessionStore(root: root)
        let report = await ImportPipeline(store: store).run(
            [.init(url: dated, origin: .photos), .init(url: try Self.fixture("import/duplicate-a"), origin: .files)],
            intent: .practice(playerName: "P"))
        let ids = report.importedSessionIDs
        try #require(ids.count == 2)
        let withDate = try await store.load(ids[0])
        #expect(withDate.recording.importSource == .photos)
        #expect(withDate.title == "Court 3 rally")
        let started = try #require(withDate.recording.startedAt)
        #expect(ISO8601DateFormatter().date(from: started) == ISO8601DateFormatter().date(from: "2026-10-06T09:41:00Z"))
        #expect(withDate.recording.device?.model == "Sample Camera")
        let undated = try await store.load(ids[1])
        #expect(undated.recording.importSource == .files)
        #expect(undated.recording.startedAt == nil, "no creation date is invented from the copy time")
        #expect(undated.recording.device == nil)
    }

    @Test("a manual quarter turn is stored as metadata; the original bytes never change")
    func manualRotation() async throws {
        let root = Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let source = try Self.fixture("import/hevc-1080p30-portrait-rotated")
        let id = try #require(await ImportPipeline(store: store).run([.init(url: source, origin: .files)],
                                                                    intent: .practice(playerName: "P")).importedSessionIDs.first)
        #expect(try await store.load(id).recording.segments.first?.rotationDegrees == .value90)
        #expect(try await store.rotateImportedVideo(id) == .value180)
        #expect(try await store.rotateImportedVideo(id, clockwiseQuarterTurns: 3) == .value90)
        #expect(try await store.rotateImportedVideo(id, clockwiseQuarterTurns: 2) == .value270)
        let saved = try await store.load(id)
        let segment = try #require(saved.recording.segments.first)
        #expect(segment.rotationDegrees == .value270)
        #expect(segment.width == 1920 && segment.height == 1080, "rotation never crops or resizes")
        let copy = try await store.sessionDirectory(id).appendingPathComponent(segment.file.path)
        #expect(try Data(contentsOf: copy) == (try Data(contentsOf: source)))
    }

    @Test("validation names the specific problem", arguments: [
        (VideoCodec.hevc, "hvc1", FrameRate(frames: 15), 1920, 1080, ImportUnsupportedReason.frameRate(FrameRate(frames: 15))),
        (VideoCodec.h264, "avc1", FrameRate(frames: 480), 1280, 720, .frameRate(FrameRate(frames: 480))),
        (VideoCodec.hevc, "hvc1", FrameRate.fps30, 7680, 4320, .resolution(width: 7680, height: 4320)),
        (VideoCodec.h264, "avc1", FrameRate.fps30, 320, 180, .resolution(width: 320, height: 180)),
        (VideoCodec.other(fourCC: "vp09"), "vp09", FrameRate.fps30, 1920, 1080, .codec("VP9")),
        (VideoCodec.other(fourCC: "apcn"), "apcn", FrameRate.fps30, 1920, 1080, .codec("Apple ProRes")),
    ])
    func validationReasons(codec: VideoCodec, fourCC: String, rate: FrameRate, width: Int, height: Int,
                           reason: ImportUnsupportedReason) {
        let video = MediaInfo.Video(codec: codec, fourCC: fourCC, codedWidth: width, codedHeight: height, rotationDegrees: 0,
            displayWidth: width, displayHeight: height, orientation: .landscape, frameRate: rate, isVariableFrameRate: false,
            isHDR: false, bitDepth: 8, isDecodable: true)
        #expect(ImportValidation.reason(for: MediaInfo(duration: .zero, video: video, audio: nil)) == reason)
    }

    @Test("24, 29.97, 60 and 240 fps 4K HEVC and H.264 are accepted")
    func validationAccepts() {
        for rate in [FrameRate(frames: 24), FrameRate(frames: 30000, perSeconds: 1001), .fps60, .fps240] {
            let video = MediaInfo.Video(codec: .hevc, fourCC: "hvc1", codedWidth: 3840, codedHeight: 2160, rotationDegrees: 90,
                displayWidth: 2160, displayHeight: 3840, orientation: .portrait, frameRate: rate, isVariableFrameRate: true,
                isHDR: true, bitDepth: 10, isDecodable: true)
            #expect(ImportValidation.reason(for: MediaInfo(duration: .zero, video: video, audio: nil)) == nil)
        }
    }

    // MARK: Helpers

    static func expectFaithfulCopy(of truth: GroundTruth, session id: String, in store: SessionStore) async throws {
        let document = try await store.load(id)
        let segment = try #require(document.recording.segments.first)
        #expect(document.recording.mode == .import && document.recording.importSource == .files)
        #expect(document.original?.state == .saved)
        #expect(segment.width == truth.video.codedWidth && segment.height == truth.video.codedHeight)
        #expect(segment.rotationDegrees?.rawValue == truth.video.rotationDegrees)
        #expect(segment.frameRate.num == truth.video.frameRate.num && segment.frameRate.den == truth.video.frameRate.den)
        #expect(segment.codec.rawValue == truth.video.codec)
        #expect(segment.hasAudio == (truth.audio != nil))
        let copy = try await store.sessionDirectory(id).appendingPathComponent(segment.file.path)
        let source = try catalog.mediaURL(for: truth)
        #expect(SHA256.hash(data: try Data(contentsOf: copy)) == SHA256.hash(data: try Data(contentsOf: source)))
        let probed = try #require(try await MediaProbe.probe(copy).video)
        #expect(probed.isHDR == (truth.video.hdr != nil), "HDR is preserved in the saved original")
        #expect(probed.bitDepth == truth.video.bitDepth)
        #expect(probed.displayWidth == truth.video.displayWidth && probed.displayHeight == truth.video.displayHeight)
    }

    static func duplicate(in report: ImportReport) throws -> FilesImportDuplicate {
        guard case .duplicate(let duplicate) = try #require(report.results.first).outcome else {
            throw CocoaError(.fileReadUnknown)
        }
        return duplicate
    }

    static func fixture(_ id: String) throws -> URL { try catalog.mediaURL(for: try catalog.truth(id: id)) }

    static func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("import-pipeline-\(UUID().uuidString)")
    }

    static func staged(in root: URL) throws -> [String] {
        let folder = root.appendingPathComponent(".files-imports")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: folder.path)
    }

    /// A passthrough rewrite (no re-encode) that adds a QuickTime creation date and camera model.
    static func writeDatedCopy(of source: URL, to destination: URL, date: String, model: String) async throws {
        let session = try #require(AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough))
        let creation = AVMutableMetadataItem()
        creation.identifier = .quickTimeMetadataCreationDate
        creation.value = date as NSString
        let camera = AVMutableMetadataItem()
        camera.identifier = .quickTimeMetadataModel
        camera.value = model as NSString
        session.metadata = [creation, camera]
        session.outputURL = destination
        session.outputFileType = .mov
        await session.export()
        #expect(session.status == .completed, "\(String(describing: session.error))")
    }
}

actor PhaseRecorder {
    private var log: [(ImportItem.ID, ImportItemPhase)] = []
    func record(_ id: ImportItem.ID, _ phase: ImportItemPhase) { log.append((id, phase)) }
    func phases(for id: ImportItem.ID) -> [ImportItemPhase] { log.filter { $0.0 == id }.map(\.1) }
}

/// A file provider that reports a cloud-only item for `pendingChecks` status queries, then local.
actor SimulatedCloud: ImportSourceAvailability {
    private var remaining: Int
    private(set) var downloadRequests = 0
    init(pendingChecks: Int) { remaining = pendingChecks }

    func status(of url: URL) async -> ImportSourceStatus {
        guard remaining > 0 else { return .available }
        remaining -= 1
        return .notDownloaded
    }

    func requestDownload(of url: URL) async { downloadRequests += 1 }
}
