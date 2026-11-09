import Darwin
import JovraCore
import JovraMedia
import SwiftUI
import UIKit
import XCTest
@testable import Jovra

@MainActor
final class ReplayMissingOriginalTests: XCTestCase {
    func testArchiveOnlyReplayShowsMissingVideoAndRetainsTheReviewedPoint() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let id = SessionID(rawValue: UUID().uuidString)
        let segmentPath = "originals/segment-000.mp4"
        try await store.create(archiveSession(id: id, segmentPath: segmentPath))
        let point = try await store.appendReviewedPoint(winner: .a, startMs: 100, endMs: 500, for: id.rawValue)
        let library = try LocalCaptureLibrary(root: root)
        let saved = try await library.load(id)
        XCTAssertEqual(saved.original?.state, .archiveOnly)
        XCTAssertEqual(saved.storage.originals, .archivedOnly)
        XCTAssertEqual(saved.archive.state, .backedUp)
        let folder = root.appendingPathComponent("sessions").appendingPathComponent(id.rawValue)
        let document = folder.appendingPathComponent("session.json")
        let original = folder.appendingPathComponent(segmentPath)
        let before = try Data(contentsOf: document)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        do {
            _ = try await library.fileURL(id, relativePath: segmentPath)
            XCTFail("archive-only fixture unexpectedly has a local original")
        } catch {
            XCTAssertEqual(error as? MediaLibraryError, .notFound)
        }

        let window = try mount(ReplayRequest(session: id, point: PointID(rawValue: point.id), filter: nil), library: library)
        defer { window.isHidden = true }
        let view = try XCTUnwrap(window.rootViewController?.view)
        let reviewed = await waitFor("review.point.1", in: view)
        XCTAssertEqual(try XCTUnwrap(reviewed).accessibilityLabel, "Point 1 · Jon")
        XCTAssertNotNil(find("review.correct.B", in: view), "review remains available without local media")
        XCTAssertNil(find("replay.play", in: view))
        XCTAssertNil(find("playback.timeline", in: view))
        XCTAssertEqual(try Data(contentsOf: document), before, "opening Replay does not write the session")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        let state = await waitFor("video.state", in: view)
        XCTAssertNotNil(state, "archive-only Replay uses the shared missing-video card")
        XCTAssertNil(find("replay.error", in: view), "the card replaces the generic error")
    }

    func testSavedMetadataWithAnAbsentLocalOriginalShowsTheMissingVideoCard() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let id = SessionID(rawValue: UUID().uuidString)
        var session = archiveSession(id: id, segmentPath: "originals/segment-000.mp4")
        session.recording.mediaAvailable = true
        session.original = .init(state: .saved)
        session.storage.originals = .onDevice
        session.archive = .init(state: .localOnly)
        try await store.create(session)
        let library = try LocalCaptureLibrary(root: root)
        let window = try mount(ReplayRequest(session: id, point: nil, filter: nil), library: library)
        defer { window.isHidden = true }
        let view = try XCTUnwrap(window.rootViewController?.view)
        let state = await waitFor("video.state", in: view)
        XCTAssertNotNil(state)
        XCTAssertNil(find("replay.error", in: view))
        XCTAssertNil(find("replay.play", in: view))
    }

    func testSessionOpenErrorIsNotPresentedAsMissingOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let window = try mount(ReplayRequest(session: SessionID(rawValue: UUID().uuidString), point: nil, filter: nil), library: library)
        defer { window.isHidden = true }
        let view = try XCTUnwrap(window.rootViewController?.view)
        let error = await waitFor("replay.error", in: view)
        XCTAssertEqual(try XCTUnwrap(error).accessibilityLabel, "Couldn't open the session. Try again.")
        XCTAssertNil(find("video.state", in: view))
        XCTAssertNil(find("replay.play", in: view))
    }

    private func archiveSession(id: SessionID, segmentPath: String) -> SessionDocument {
        let timestamp = "2026-09-15T12:00:00Z"
        let segment = SessionSegment(
            id: "segment-0", index: 0, file: .init(path: segmentPath, mimeType: "video/mp4"),
            startMs: 0, durationMs: 2_000, frameRate: .init(num: 60, den: 1),
            width: 640, height: 360, codec: .h264, hasAudio: false, finalized: true)
        return .init(
            schemaVersion: .current, id: id.rawValue, sport: .value, createdAt: timestamp, updatedAt: timestamp,
            title: "Archive-only fixture", sample: .init(synthetic: true, generator: "JOVRAReplayTests"),
            sessionKind: .match, capturePurpose: .match, players: [
                .init(id: "a", displayName: "Jon", handedness: .unknown, backhand: .unknown, isSelf: true),
                .init(id: "b", displayName: "Alex", handedness: .unknown, backhand: .unknown, isSelf: false),
            ], sides: .init(A: ["a"], B: ["b"]),
            match: .init(
                format: .init(presetId: .bestOf1, setsToWin: .value1, gameScoring: .ad,
                              set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let),
                toss: .init(firstServer: "a", startingEnds: .init(A: .near, B: .far)), log: []),
            recording: .init(mode: .simulatorFixture, durationMs: 2_000, segments: [segment], gaps: [],
                             microphone: .notRequested, mediaAvailable: false),
            marks: [], annotations: [], analysis: .init(state: .notRequested, runs: []), review: .init(state: .notStarted),
            archive: .init(state: .backedUp, copy: .original, provider: .value, manifest: "archive/manifest.json", backedUpAt: timestamp),
            storage: .init(originals: .archivedOnly, includeInDeviceBackup: false),
            exports: [], original: .init(state: .archiveOnly))
    }

    private func mount(_ request: ReplayRequest, library: LocalCaptureLibrary) throws -> UIWindow {
        let handle = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW))
        defer { dlclose(handle) }
        let symbol = try XCTUnwrap(dlsym(handle, "_AXSApplicationAccessibilitySetEnabled"))
        typealias SetEnabled = @convention(c) (Bool) -> Void
        unsafeBitCast(symbol, to: SetEnabled.self)(true)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: ReplayScreen(request: request)
            .environment(AppRouter(selectedTab: .sessions))
            .environment(\.localCaptureLibrary, .ready(library)))
        window.makeKeyAndVisible()
        return window
    }

    private func waitFor(_ identifier: String, in root: NSObject) async -> NSObject? {
        for _ in 0..<200 {
            if let result = find(identifier, in: root) { return result }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    private func find(_ identifier: String, in root: NSObject, depth: Int = 0) -> NSObject? {
        if (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == identifier { return root }
        if root.responds(to: NSSelectorFromString("accessibilityIdentifier")),
           root.value(forKey: "accessibilityIdentifier") as? String == identifier { return root }
        guard depth < 40 else { return nil }
        var children: [Any] = root.accessibilityElements ?? []
        if children.isEmpty {
            let count = root.accessibilityElementCount()
            if count != NSNotFound, count > 0 { children = (0..<count).compactMap { root.accessibilityElement(at: $0) } }
        }
        if let view = root as? UIView { children += view.subviews }
        for case let child as NSObject in children {
            if let found = find(identifier, in: child, depth: depth + 1) { return found }
        }
        return nil
    }
}
