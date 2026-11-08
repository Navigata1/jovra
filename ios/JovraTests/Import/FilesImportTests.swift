import Foundation
import JovraCore
import JovraMedia
import XCTest
@testable import Jovra

final class FilesImportTests: XCTestCase {
    @MainActor
    func testPlayableSelectionIsCopiedAndReopensFromLibrary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let selected = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let before = try Data(contentsOf: selected)
        let id = try await library.importFile(selected, playerName: "Practice Player")

        let reopened = try LocalCaptureLibrary(root: root)
        let rows = try await reopened.sessions()
        XCTAssertEqual(rows.map(\.id), [id.rawValue])
        let saved = try await reopened.load(id)
        XCTAssertEqual(saved.recording.importSource, .files)
        XCTAssertEqual(saved.players.map(\.displayName), ["Practice Player"])
        XCTAssertNil(saved.match, "Import must not invent match setup or points")
        XCTAssertEqual(saved.original?.state, .saved)
        let segment = try XCTUnwrap(saved.recording.segments.first)
        let original = try await reopened.fileURL(id, relativePath: segment.file.path)
        XCTAssertNotEqual(original, selected)
        XCTAssertEqual(try Data(contentsOf: original), before)
        XCTAssertEqual(try Data(contentsOf: selected), before)
        XCTAssertEqual(segment.file.bytes, before.count)
        XCTAssertEqual(segment.file.sha256?.count, 64)
        XCTAssertTrue(try original.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let decoded = try await decodeCaptureToEnd(original)
        XCTAssertGreaterThan(decoded.videoFrames, 0)
        let replay = ReplayPlaybackModel()
        await replay.open(library: reopened, session: id)
        XCTAssertNotNil(replay.player)
        replay.close()
        let review = ReviewedPointModel()
        await review.open(library: reopened, session: id)
        XCTAssertNil(review.error)
        XCTAssertNil(review.document, "Practice video does not have a scoreboard")
        let receipt = XCTAttachment(data: try CanonicalJSON.encode(saved), uniformTypeIdentifier: "public.json")
        receipt.name = "files-import-session.json"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    @MainActor
    func testInvalidLinkedAndCancelledSelectionsNeverBecomeSessions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let invalid = root.appendingPathComponent("broken.mp4")
        let bytes = Data("not a video".utf8)
        try bytes.write(to: invalid)
        let linked = root.appendingPathComponent("linked.mp4")
        let real = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: real)
        for source in [invalid, linked] {
            do { _ = try await library.importFile(source, playerName: "Player"); XCTFail("Invalid source was accepted") }
            catch { XCTAssertFalse(error is CancellationError) }
        }
        let cancelled = Task { try await library.importFile(real, playerName: "Player") }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled source was accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
        let rows = try await library.sessions()
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(try Data(contentsOf: invalid), bytes)
        let staged = root.appendingPathComponent(".files-imports")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staged.path), [])
    }
    @MainActor
    func testCommitRefusesAStagedOriginalReplacedAfterValidation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let bytes = try Data(contentsOf: source)
        let store = try SessionStore(root: root) { checkpoint in
            guard case .temporaryFileFlushed(let temp) = checkpoint, temp.pathComponents.contains(".files-imports") else { return }
            try bytes.write(to: temp.deletingLastPathComponent().appendingPathComponent("originals/source.mp4"), options: .atomic)
        }
        do {
            _ = try await FilesImportService(store: store).importVideo(source, playerName: "Player")
            XCTFail("A replaced original must not be acknowledged")
        } catch {}
        let rows = try await store.list()
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    @MainActor
    func testStartupClearsAbandonedImportWithoutFollowingALink() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent(".files-imports")
        let abandoned = staging.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try Data("partial copy".utf8).write(to: abandoned.appendingPathComponent("incomplete.mp4"))
        let unrelated = root.appendingPathComponent("unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let link = staging.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: unrelated)
        let library = try LocalCaptureLibrary(root: root)
        let rows = try await library.sessions()
        XCTAssertTrue(rows.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), unrelated.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @MainActor
    func testCancellationAtStagedDocumentWriteDoesNotPublish() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let store = try SessionStore(root: root) { checkpoint in
            guard case .documentRenamed(let document) = checkpoint,
                  document.pathComponents.contains(".files-imports") else { return }
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let operation = Task { try await FilesImportService(store: store).importVideo(source, playerName: "Player") }
        do { _ = try await operation.value; XCTFail("Cancellation before publication must not be acknowledged") }
        catch { XCTAssertTrue(error is CancellationError) }
        let rows = try await store.list()
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".files-imports").path), [])
        let activeID = UUID()
        let active = try await store.beginFilesImport(activeID)
        try await store.discardAbandonedFilesImports()
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
        try await store.discardFilesImport(activeID)
    }

}
