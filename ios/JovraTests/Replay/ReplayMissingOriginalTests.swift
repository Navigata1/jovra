import AVFoundation
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

    func testLegacyArchiveOnlyWithoutOriginalFacetStillShowsMissingVideo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let id = SessionID(rawValue: UUID().uuidString)
        var session = archiveSession(id: id, segmentPath: "originals/segment-000.mp4")
        session.schemaVersion = .v1_1
        session.original = nil
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

    func testUnverifiedLookupFailureDoesNotClaimVideoIsMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let id = SessionID(rawValue: UUID().uuidString)
        let path = "originals/segment-000.mp4"
        try await store.create(onDeviceSession(id: id, path: path))
        let library = try LocalCaptureLibrary(root: root)
        do {
            _ = try await library.fileURL(id, relativePath: path)
            XCTFail("test fixture must reach the library lookup failure")
        } catch {
            XCTAssertEqual(error as? MediaLibraryError, .notFound)
        }
        try await assertOriginalUnavailable(id, library: library)
    }

    func testUnfinishedRecordingDoesNotClaimVideoIsMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let id = SessionID(rawValue: UUID().uuidString)
        var session = onDeviceSession(id: id, path: "originals/segment-000.mp4")
        session.recording = .init(mode: .simulatorFixture, segments: [], gaps: [],
                                  microphone: .notRequested, mediaAvailable: false)
        session.original = .init(state: .recording)
        try await store.create(session)
        try await assertOriginalUnavailable(id, library: LocalCaptureLibrary(root: root))
    }

    func testDirectoryAtOriginalPathIsUnavailableAndDoesNotCreateAPlayer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let id = SessionID(rawValue: UUID().uuidString)
        let path = "originals/segment-000.mp4"
        try await store.create(onDeviceSession(id: id, path: path))
        let leaf = root.appendingPathComponent("sessions").appendingPathComponent(id.rawValue).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: true)
        let library = try LocalCaptureLibrary(root: root)
        let resolved = try await library.fileURL(id, relativePath: path)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: resolved.path)[.type] as? FileAttributeType, .typeDirectory)
        try await assertOriginalUnavailable(id, library: library)
    }

    func testMissingFirstSegmentKeepsTheExistingSegmentPickerReachable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LocalCaptureLibrary(root: root)
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        let clock = VirtualCaptureClock()
        let camera = FixtureCamera(url: bundled, duration: CMTime(value: 1, timescale: 1), clock: clock)
        let capture = NativeCaptureCoordinator(library: library, source: camera, clock: clock)
        let seed = CaptureSessionSeed(title: "Synthetic two-segment Replay", players: [
            .init(id: "a", displayName: "Jon", handedness: .unknown, backhand: .unknown, isSelf: true),
            .init(id: "b", displayName: "Alex", handedness: .unknown, backhand: .unknown, isSelf: false),
        ], format: .init(presetId: .bestOf1, setsToWin: .value1, gameScoring: .ad,
                         set: .tiebreakSet(.init(games: 6, tiebreakAt: 6, tiebreak: .init(points: 7))), lets: .let),
           toss: .init(firstServer: "a", startingEnds: .init(A: .near, B: .far)))
        try await capture.prepare(seed: seed, preset: .init(width: 1280, height: 720), microphone: .denied)
        try await capture.start()
        try await camera.waitUntilFinished()
        try await capture.pause()
        clock.advance(by: CMTimeSubtract(CMTime(value: 3, timescale: 1), clock.now()))
        try await capture.resume()
        try await camera.waitUntilFinished()
        try await capture.stop()
        let id = try XCTUnwrap(capture.sessionID)
        let saved = try XCTUnwrap(capture.savedRecording)
        guard saved.segments.count == 2 else {
            return XCTFail("the owned synthetic test must have two finalized segments")
        }
        XCTAssertTrue(saved.segments.allSatisfy(\.finalized))
        XCTAssertEqual(saved.gaps, [SessionGap(startMs: 1_000, endMs: 3_000, reason: .userPaused)])
        let request = ReplayRequest(session: id, point: nil, filter: nil)
        let healthyWindow = try mount(request, library: library)
        let healthyView = try XCTUnwrap(healthyWindow.rootViewController?.view)
        let healthyFrame = await waitFor("replay.frame", in: healthyView)
        XCTAssertNotNil(healthyFrame)
        let calibrationPicker = await waitForSegmentPicker(in: healthyView)
        if calibrationPicker == nil { attachHealthyReplayDiagnostic(window: healthyWindow, root: healthyView) }
        _ = try XCTUnwrap(calibrationPicker, "positive control: the existing picker is discoverable while video is healthy")
        healthyWindow.isHidden = true
        healthyWindow.rootViewController = nil

        let first = try await library.fileURL(id, relativePath: saved.segments[0].file.path)
        let later = try await library.fileURL(id, relativePath: saved.segments[1].file.path)
        let document = root.appendingPathComponent("sessions").appendingPathComponent(id.rawValue).appendingPathComponent("session.json")
        let beforeDocument = try Data(contentsOf: document)
        let beforeLater = try Data(contentsOf: later)
        let ownedRoot = root.resolvingSymlinksInPath().path + "/"
        guard first.resolvingSymlinksInPath().path.hasPrefix(ownedRoot) else {
            return XCTFail("refuse to remove a fixture outside the owned test store")
        }
        try FileManager.default.removeItem(at: first)
        let reopened = try mount(request, library: library)
        defer { reopened.isHidden = true }
        let failedView = try XCTUnwrap(reopened.rootViewController?.view)
        let issue = await waitFor("replay.error", in: failedView)
        XCTAssertNotNil(issue)
        XCTAssertNil(find("replay.play", in: failedView))
        let remainingPicker = await waitForSegmentPicker(in: failedView)
        XCTAssertNotNil(remainingPicker, "the same picker must survive the first segment's lookup failure")

        // The hosted accessibility proof above observes the real picker. Exercise the selection
        // through the public model rather than claiming that the system menu was operated here.
        let model = ReplayPlaybackModel()
        await model.open(library: library, session: id)
        defer { model.close() }
        XCTAssertNil(model.player)
        XCTAssertEqual(model.selectedSegmentID, saved.segments[0].id)
        await model.selectSegment(saved.segments[1].id)
        let laterPlayer = try XCTUnwrap(model.player)
        XCTAssertEqual(laterPlayer.timeControlStatus, .paused)
        XCTAssertEqual(model.frame?.index, 0)
        await model.step(1)
        XCTAssertEqual(model.frame?.index, 1)
        model.play()
        await model.selectSegment(saved.segments[0].id)
        XCTAssertNil(model.player)
        XCTAssertEqual(laterPlayer.rate, 0)
        XCTAssertNotNil(model.error)
        await model.selectSegment(saved.segments[1].id)
        XCTAssertEqual(model.player?.timeControlStatus, .paused)
        XCTAssertEqual(model.frame?.index, 0)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.document?.recording.gaps, saved.gaps)
        XCTAssertEqual(try Data(contentsOf: document), beforeDocument)
        XCTAssertEqual(try Data(contentsOf: later), beforeLater)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
    }

    private func onDeviceSession(id: SessionID, path: String) -> SessionDocument {
        var session = archiveSession(id: id, segmentPath: path)
        session.recording.mediaAvailable = true
        session.original = .init(state: .saved)
        session.storage.originals = .onDevice
        session.archive = .init(state: .localOnly)
        return session
    }

    private func assertOriginalUnavailable(_ id: SessionID, library: LocalCaptureLibrary) async throws {
        let window = try mount(ReplayRequest(session: id, point: nil, filter: nil), library: library)
        defer { window.isHidden = true }
        let view = try XCTUnwrap(window.rootViewController?.view)
        let issue = await waitFor("replay.error", in: view)
        XCTAssertEqual(issue?.accessibilityLabel, "The original isn't available on this iPhone.")
        XCTAssertNil(find("video.state", in: view))
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

    private func attachHealthyReplayDiagnostic(window: UIWindow, root: UIView) {
        var visited = Set<ObjectIdentifier>()
        var lines: [String] = []

        func visit(_ node: NSObject, depth: Int) {
            guard depth < 40, lines.count < 350, visited.insert(ObjectIdentifier(node)).inserted else { return }
            let identifier = (node as? UIAccessibilityIdentification)?.accessibilityIdentifier
                ?? (node.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                    ? node.value(forKey: "accessibilityIdentifier") as? String : nil)
            let frame = NSStringFromCGRect(node.accessibilityFrame)
            lines.append("\(depth) \(type(of: node)) label=\(node.accessibilityLabel ?? "-") value=\(node.accessibilityValue ?? "-") id=\(identifier ?? "-") traits=\(node.accessibilityTraits.rawValue) frame=\(frame)")
            var children: [Any] = node.accessibilityElements ?? []
            if children.isEmpty {
                let count = node.accessibilityElementCount()
                if count != NSNotFound, count > 0 { children = (0..<count).compactMap { node.accessibilityElement(at: $0) } }
            }
            if let view = node as? UIView { children += view.subviews }
            for case let child as NSObject in children { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)

        let hierarchy = XCTAttachment(string: lines.joined(separator: "\n"))
        hierarchy.name = "Healthy two-segment Replay accessibility tree"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let screenshot = XCTAttachment(image: image)
        screenshot.name = "Healthy two-segment Replay"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func waitForSegmentPicker(in root: NSObject) async -> NSObject? {
        for _ in 0..<200 {
            if let picker = find(in: root, matching: { item in
                item.accessibilityLabel == "Recording segment"
                    || (item.accessibilityLabel == "Segment 1" && item.accessibilityTraits.contains(.button))
            }) { return picker }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    private func find(_ identifier: String, in root: NSObject) -> NSObject? {
        find(in: root) { item in
            if (item as? UIAccessibilityIdentification)?.accessibilityIdentifier == identifier { return true }
            return item.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                && item.value(forKey: "accessibilityIdentifier") as? String == identifier
        }
    }

    private func find(in root: NSObject, depth: Int = 0, matching: (NSObject) -> Bool) -> NSObject? {
        if matching(root) { return root }
        guard depth < 40 else { return nil }
        var children: [Any] = root.accessibilityElements ?? []
        if children.isEmpty {
            let count = root.accessibilityElementCount()
            if count != NSNotFound, count > 0 { children = (0..<count).compactMap { root.accessibilityElement(at: $0) } }
        }
        if let view = root as? UIView { children += view.subviews }
        for case let child as NSObject in children {
            if let found = find(in: child, depth: depth + 1, matching: matching) { return found }
        }
        return nil
    }
}
