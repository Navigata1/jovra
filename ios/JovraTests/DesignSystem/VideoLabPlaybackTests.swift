#if DEBUG
@preconcurrency import AVFoundation
import Foundation
import JovraMedia
import Testing
@testable import Jovra

@MainActor
@Suite("VideoLab source switching", .serialized)
struct VideoLabPlaybackTests {
    private enum DecoderFailure: Error { case refused }

    @Test(arguments: [false, true])
    func olderFailureCannotReplaceTheLatestReadySource(generic: Bool) async throws {
        let fixture = try Sources()
        defer { fixture.remove() }
        let gate = LoadGate()
        let playback = VideoLabPlayback { source, _ in
            if source == fixture.older {
                await gate.hold()
                if generic { throw DecoderFailure.refused }
                throw PlaybackOpenError.missingFile
            }
            return try await PlaybackController.open(url: source)
        }
        defer { playback.close() }
        let older = Task { await playback.load(fixture.older) }
        defer { older.cancel(); gate.release() }
        try await gate.requireHeld()
        await playback.load(fixture.latest)
        let latest = try #require(playback.controller)
        #expect(latest.url == fixture.latest)
        if generic { older.cancel() }
        gate.release()
        await older.value

        #expect(playback.error == nil)
        #expect(playback.controller === latest)
        await latest.seek(toFrame: 13)
        #expect(latest.readout.frame == 13)
        #expect(abs(latest.player.currentTime().seconds - 13.0 / 30) < 0.001)
    }

    @Test
    func staleSuccessIsClosedAndCannotReplaceTheLatestController() async throws {
        let fixture = try Sources()
        defer { fixture.remove() }
        let stale = try await PlaybackController.open(url: fixture.older)
        defer { stale.close() }
        let gate = LoadGate()
        let playback = VideoLabPlayback { source, _ in
            if source == fixture.older { await gate.hold(); return stale }
            return try await PlaybackController.open(url: source)
        }
        defer { playback.close() }
        let older = Task { await playback.load(fixture.older) }
        defer { older.cancel(); gate.release() }
        try await gate.requireHeld()
        await playback.load(fixture.latest)
        let latest = try #require(playback.controller)
        defer { latest.close() }
        gate.release()
        await older.value

        #expect(playback.controller === latest)
        #expect(!stale.setRate(.double))
        #expect(latest.setRate(.half))
        #expect(playback.error == nil)
    }

    @Test
    func disappearanceInvalidatesAnOpenEvenWithoutCooperativeCancellation() async throws {
        let fixture = try Sources()
        defer { fixture.remove() }
        let opened = try await PlaybackController.open(url: fixture.older)
        defer { opened.close() }
        let gate = LoadGate()
        let playback = VideoLabPlayback { _, _ in await gate.hold(); return opened }
        defer { playback.close() }
        let pending = Task { await playback.load(fixture.older) }
        defer { pending.cancel(); gate.release() }
        try await gate.requireHeld()
        playback.close()
        gate.release()
        await pending.value

        #expect(playback.controller == nil)
        #expect(playback.error == nil)
        #expect(!opened.setRate(.double))
    }

    @Test(arguments: [false, true])
    func aCurrentFailureRemainsVisible(generic: Bool) async throws {
        let fixture = try Sources()
        defer { fixture.remove() }
        let playback = VideoLabPlayback { _, _ in
            if generic { throw DecoderFailure.refused }
            throw PlaybackOpenError.missingFile
        }
        await playback.load(fixture.latest)
        #expect(playback.controller == nil)
        #expect(playback.error == (generic ? .unreadable : .missingFile))
    }
}

@MainActor
private final class LoadGate {
    private var pending: CheckedContinuation<Void, Never>?
    private var released = false

    func hold() async {
        guard !released else { return }
        await withCheckedContinuation { pending = $0 }
    }

    func release() {
        released = true
        let waiting = pending
        pending = nil
        waiting?.resume()
    }

    func requireHeld() async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while pending == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        try #require(pending != nil, "The old opener reached the controlled suspension")
    }
}

private struct Sources {
    let folder: URL
    var older: URL { folder.appendingPathComponent("older.mp4") }
    var latest: URL { folder.appendingPathComponent("latest.mp4") }

    init() throws {
        #if SWIFT_PACKAGE
        let fixture = try #require(Bundle.module.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        #else
        let fixture = try #require(Bundle.main.url(forResource: "fixture-camera-720p30", withExtension: "mp4"))
        #endif
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        do {
            try FileManager.default.copyItem(at: fixture, to: older)
            try FileManager.default.copyItem(at: fixture, to: latest)
        } catch {
            remove()
            throw error
        }
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }
}
#endif
