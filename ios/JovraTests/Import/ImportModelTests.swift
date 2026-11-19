import Foundation
import JovraCore
import JovraMedia
import XCTest
@testable import Jovra

/// The S07 import model and copy over the real library (T26). Expected values are hand-written.
final class ImportModelTests: XCTestCase {
    @MainActor
    func testBatchReportsEachFileAndHoldsTheDuplicateUntilImportAnyway() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let notVideo = root.appendingPathComponent("notes.mp4")
        try Data("not a video".utf8).write(to: notVideo)
        let again = root.appendingPathComponent("same rally again.mov")
        try FileManager.default.copyItem(at: fixture, to: again)
        let items = [ImportItem(url: fixture, origin: .files), ImportItem(url: notVideo, origin: .files),
                     ImportItem(url: again, origin: .photos)]

        let model = ImportModel()
        let finished = expectation(description: "batch finished")
        var single: SessionID?? = .none
        model.start(items, intent: .practice(playerName: "Practice Player"), library: library,
                    availability: SystemImportSourceAvailability()) { single = .some($0); finished.fulfill() }
        await fulfillment(of: [finished], timeout: 30)

        XCTAssertEqual(single, .some(nil), "a batch does not jump to one session's processing route")
        XCTAssertEqual(model.rows.map(\.name), ["fixture-camera-720p30.mp4", "notes.mp4", "same rally again.mov"])
        guard case .saved(let saved) = model.rows[0].status else { return XCTFail("\(model.rows[0].status)") }
        XCTAssertEqual(saved.shortSide, 720)
        XCTAssertEqual(saved.source, .files)
        XCTAssertNil(saved.recordedAt, "the fixture states no creation date")
        XCTAssertEqual(model.rows[1].status, .unsupported(.noVideoTrack))
        guard case .duplicate(_, let existing) = model.rows[2].status else { return XCTFail("\(model.rows[2].status)") }
        XCTAssertEqual(existing, "fixture-camera-720p30")
        XCTAssertTrue(model.needsAttention)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".files-imports").path).count, 1)

        await model.importAnyway(model.rows[2].id, library: library)
        guard case .saved(let copy) = model.rows[2].status else { return XCTFail("\(model.rows[2].status)") }
        XCTAssertEqual(copy.source, .photos)
        XCTAssertNotEqual(copy.session, saved.session)
        let sessions = try await library.sessions()
        XCTAssertEqual(Set(sessions.map(\.id)), [saved.session.rawValue, copy.session.rawValue])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".files-imports").path), [])

        await model.rotate(model.rows[0].id, library: library)
        guard case .saved(let turned) = model.rows[0].status else { return XCTFail() }
        XCTAssertEqual(turned.manualQuarterTurns, 1)
        let rotated = try await library.load(saved.session).recording.segments.first?.rotationDegrees
        XCTAssertEqual(rotated, .value90)
    }

    @MainActor
    func testOneCleanImportHandsItsSessionToTheProcessingRoute() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let model = ImportModel()
        let finished = expectation(description: "finished")
        var single: SessionID?
        model.start([ImportItem(url: fixture, origin: .files)], intent: .practice(playerName: "P"), library: library,
                    availability: SystemImportSourceAvailability()) { single = $0; finished.fulfill() }
        await fulfillment(of: [finished], timeout: 30)
        let id = try XCTUnwrap(single)
        let sessions = try await library.sessions()
        XCTAssertEqual(sessions.map(\.id), [id.rawValue])
    }

    @MainActor
    func testDiscardingLeavesNoHeldCopyAndOpenExistingKeepsOneSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let first = try await library.importFile(fixture, playerName: "P")
        for choice in ["open", "leave"] {
            let model = ImportModel()
            let finished = expectation(description: choice)
            model.start([ImportItem(url: fixture, origin: .files)], intent: .practice(playerName: "P"), library: library,
                        availability: SystemImportSourceAvailability()) { _ in finished.fulfill() }
            await fulfillment(of: [finished], timeout: 30)
            if choice == "open" {
                let opened = await model.openExisting(model.rows[0].id, library: library)
                XCTAssertEqual(opened, first)
                XCTAssertEqual(model.rows[0].status, .openedExisting(first))
            } else {
                await model.discardHeldCopies(library: library)
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".files-imports").path), [])
        }
        let sessions = try await library.sessions()
        XCTAssertEqual(sessions.map(\.id), [first.rawValue])
    }

    /// Process death mid-import, simulated in process: the first library's import is frozen with its staged
    /// copy and document on disk (never published); a second library on the same root is the relaunch.
    func testRelaunchAfterDeathMidImportLeavesTheCompletedSessionAndNoPartialFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let completed = try await LocalCaptureLibrary(root: root).importFile(fixture, playerName: "Completed")

        let frozen = DispatchSemaphore(value: 0), reached = DispatchSemaphore(value: 0)
        let dying = try LocalCaptureLibrary(root: root) { checkpoint in
            guard case .documentRenamed(let url) = checkpoint, url.pathComponents.contains(".files-imports") else { return }
            reached.signal()
            frozen.wait()
        }
        let second = root.appendingPathComponent("second.mov")
        var bytes = try Data(contentsOf: fixture)
        bytes[15] ^= 1 // a different file (ftyp minor version), so it is not a duplicate
        try bytes.write(to: second)
        let abandoned = Task.detached { try? await dying.importFile(second, playerName: "Interrupted") }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { reached.wait(); continuation.resume() }
        }
        let staging = root.appendingPathComponent(".files-imports")
        let partial = try FileManager.default.contentsOfDirectory(atPath: staging.path)
        XCTAssertEqual(partial.count, 1, "the interrupted import has a partial folder on disk")

        let relaunched = try LocalCaptureLibrary(root: root)
        let sessions = try await relaunched.sessions()
        XCTAssertEqual(sessions.map(\.id), [completed.rawValue])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [], "relaunch removed the partial folder")
        frozen.signal()
        _ = await abandoned.value
        let after = try await relaunched.sessions()
        XCTAssertEqual(after.map(\.id), [completed.rawValue], "the frozen import can never publish into the relaunched library")
    }

    func testUnsupportedAndFailedRowsNameTheProblem() {
        XCTAssertEqual(ImportRowCopy.unsupported(.codec("FFV1")),
                       "It uses the FFV1 codec. Convert it to HEVC or H.264, then import it again.")
        XCTAssertEqual(ImportRowCopy.unsupported(.container("mkv")),
                       "MKV files aren't supported. Save it as MOV or MP4, then import it again.")
        XCTAssertEqual(ImportRowCopy.unsupported(.frameRate(FrameRate(frames: 15))), "It's 15 fps. JOVRA imports 24 to 240 fps.")
        XCTAssertEqual(ImportRowCopy.unsupported(.resolution(width: 7680, height: 4320)),
                       "It's 7680 × 4320. JOVRA imports up to 4K (4096 pixels on the long side) and at least 240p.")
        XCTAssertEqual(ImportRowCopy.title(for: .waitingForDownload), "Waiting for download")
        let video = ImportModel.SavedVideo(session: .init(rawValue: "s"), title: "t", durationMs: 12_000, shortSide: 1080,
                                           recordedAt: nil, source: .photos, rotationDegrees: 0)
        XCTAssertEqual(ImportRowCopy.metadata(video), "12 sec · 1080p · Photos · Date not in file")
        XCTAssertNil(ImportRowCopy.rotationText(quarterTurns: 4))
    }
}
